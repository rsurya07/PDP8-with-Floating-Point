//
//
// Verilog ISA model of the PDP-8. 
//
//
//  Copyright(c) 2006 Mark G. Faust
//
//  Mark G. Faust
//  ECE Department
//  Portland State University
//
//
//
// This is a non-synthesizable model of the PDP-8 at the ISA level.  It's based
// upon DEC documentation and an ISPS description by Mario Barbacci.  Neither I//O
// instructions (opcode 6) nor Group 3 Microinstructions (EAE) are supported.
//
//
// A single object file (pdp8.mem) is read in $readmemh() format and simulated
// beginning at location 200 (octal).

// For each instruction type the instruction count is recorded along with the number
// of cycles (which depends upon addressing mode) consumed.
//
// Upon completion, these along with the total number of cycles
// simulated is printed along with the contents of the L, AC registers.
//

// Except for reading the memory image in hex, we will try report/display everything
// in octal since that's the dominant radix used on the PDP-8 (tools, documentation).
//
 

module PDP8();


`define WORD_SIZE 12			// 12-bit word
`define MEM_SIZE  4096			// 4K memory
`define OBJFILENAME "pdp8.mem"	// input file with object code

//
// Processor state (note PDP-8 is a big endian system, bit 0 is MSB)
//


reg [0:`WORD_SIZE-1] PC;		// Program counter
reg [0:`WORD_SIZE-1] IR;		// Instruction Register
reg [0:`WORD_SIZE-1] AC;		// accumulator
reg [0:`WORD_SIZE-1] SR;		// front panel switch register
reg [0:`WORD_SIZE-1] MA;		// memory address register
reg        	      L;			// Link register

reg [0:31] FPAC;			//Floating point accumulator

reg [0:4]  CPage;				// Current page

reg [0:`WORD_SIZE-1] Mem[0:`MEM_SIZE-1];// 4K memory

reg InterruptsOn;				// not currently used
reg InterruptReq;				// not currently used
reg Run;	

reg [100:0] S1; 				//s=$value$plusargs("MEM=%s", S1);
reg [100:0] s;

//`define VerificationMode 1					// Run while 1
//reg VerificationMode =1'b1;
//
// Fields in instruction word
//


`define OpCode		IR[0:2]		// Instruction OpCode
`define IndirectBit	IR[3]		// Indirect Address Bit
`define Page0Bit	IR[4]		// Memory Reference is to Page 0
`define PageAddress	IR[5:11]	// Page Offset


//
// Opcodes
//

parameter
	AND = 0,
	TAD = 1,
	ISZ = 2,
	DCA = 3,
	JMS = 4,
	JMP = 5,
	IOT = 6,
	OPR = 7;




//
// Microinstructions
//

`define Group	IR[3]		//  Group = 0 --> Group 1
`define CLA	IR[4]			//  clear AC  (both groups)



//
// Group 1 microinstructions (IR[3] = 0)
//


`define CLL	IR[5]			// clear L
`define CMA	IR[6]			// complement AC
`define CML	IR[7]			// complement L
`define ROT	IR[8:10]		// rotate
`define IAC	IR[11]			// increment AC


//
// Group 2 microinstructions (IR[3] = 1 and IR[11] = 0)
//

`define SMA IR[5]			// skip on minus AC
`define SZA IR[6]			// skip on zero AC
`define SNL IR[7]			// skip on non-zero L
`define SPA IR[5]			// skip on positive AC
`define SNA IR[6]			// skip on non-zero AC
`define SZL IR[7]			// skip on zero L
`define IS  IR[8]			// invert sense of skip
`define OSR IR[9]			// OR with switch register
`define HLT IR[10]			// halt processor



//
// Trace information
//

integer Clocks;
integer TotalClocks;
integer TotalIC;
integer CPI[0:7]; 	// clocks per instruction;
integer  IC[0:7];	// instruction count per instruction;
integer i;

//
//Registers for Verification 
//
shortreal A, B, C; 


task LoadObj;
  begin
  s=$value$plusargs("MEM=%s", S1);
$display("%s", S1);
  $readmemh(S1, Mem);
  end
endtask


task Fetch;
  begin
  IR = Mem[PC];
	//$display("fetched %0o from %0x	%0b\n\n", IR, PC, IR[3:11]);
  CPage = PC[0:4];	// Need to maintain this BEFORE PC is incremented for EA calculation
  PC = PC + 1;
  end
endtask


task Execute;
  begin
  case (`OpCode)	
    AND:	begin
			Clocks = Clocks + 2;
			EffectiveAddress(MA);
			AC = AC & Mem[MA];
			end
	
	TAD:	begin
			Clocks = Clocks + 2;
			EffectiveAddress(MA);	
			{L,AC} = {L,AC} + {1'b0,Mem[MA]};
			end
			
	ISZ:	begin
			Clocks = Clocks + 2;
			EffectiveAddress(MA);
			Mem[MA] = Mem[MA] + 1;
			if (Mem[MA] == `WORD_SIZE'o0000)
				PC = PC + 1;
			end
			
	DCA:	begin
			Clocks = Clocks + 2;
			EffectiveAddress(MA);
			Mem[MA] = AC;
			AC = 0;
			end
			
	JMS:	begin
			Clocks = Clocks + 2;
			EffectiveAddress(MA);
			Mem[MA] = PC;
			PC = MA + 1;
			end
			
	JMP:	begin
			Clocks = Clocks + 1;
			EffectiveAddress(PC);
			end
			
	IOT:	begin		
			if(IR[3:11] == 9'b101101000)
				begin
				FPAC = 0;
				end

			else if(IR[3:11] == 9'b101101001)
				begin
				FPLOAD;
				end

			else if(IR[3:11] == 9'b101101010)
				begin
				FPSTOR;
				end

			else if(IR[3:11] == 9'b101101011)
				begin
				FPADD;
				end

			else if(IR[3:11] == 9'b101101100)
				begin
				FPMULT;
				end

			else
				begin
				$display("Invalid IOT instruction at PC = %0o",PC-1," ignored");
				end
		end
			
	OPR:	begin
			Clocks = Clocks + 1;
			Operate;
			end
			
  endcase
  
  CPI[`OpCode] = CPI[`OpCode] + Clocks;
  IC[`OpCode] = IC[`OpCode] + 1;
  end
endtask
 



//
// Compute effective address taking into account indirect and auto-increment.
// Advance Clocks accordingly.  Auto-increment applies to indirect references
// to addresses 10-17 (octal) on page 0.
//
// Note that for auto-increment, this function has the side-effect of incrementing
// memory, so it should be called only once per execute cycle
//


task EffectiveAddress;
  output [0:`WORD_SIZE-1] EA;
  begin
  EA = (`Page0Bit) ? {CPage,`PageAddress} : {5'b00000,`PageAddress};

// $display("CPage = %0o   EA = %0o",CPage,EA);	
  if (`IndirectBit)
	begin
	Clocks = Clocks + 1;
    if (EA[0:8] == 9'b000000001)    // auto-increment
		begin
		$display("                         +   ");
		Clocks = Clocks + 1;
		Mem[EA] = Mem[EA] + 1;
		end
	EA = Mem[EA];
	end
 // $display("EA = %0o",EA);
  end
endtask
  
  
  
  
  
//
// Handle microinstructions.  Some of these are done in parallel, some can
// be combined because they're done sequentially.
//
  
  
task Operate;
  begin
	case (`Group)
	  0:										// Group 1 Microinstructions
		begin
		if (`CLA) AC = 0;
		if (`CLL) L = 0;
		
		if (`CMA) AC = ~AC;
		if (`CML) L = ~L;
		
		if (`IAC) {L,AC} = {L,AC} + 1;
		
		case (`ROT)
			0:	;
			1:	{AC[6:11],AC[0:5]} = AC;		// BSW -- byte swap
			2:	{L,AC} = {AC,L};				// RAL -- left shift/rotate 1x
			3:	{L,AC} = {AC[1:11],L,AC[0]};	// RTL -- left shift/rotate 2x
			4:	{L,AC} = {AC[11],L,AC[0:10]};	// RAR -- right shift/rotate 1x
			5:	{L,AC} = {AC[10:11],L,AC[0:9]};	// RTR  -- right shift/rotate 2x
			6:	$display("Unsupported Group 1 microinstruction at PC = %0o",PC-1," ignored");
			7:	$display("Unsupported Group 1 microinstruction at PC = %0o",PC-1," ignored");
		endcase
		end
		
	  1:
		begin
		case (IR[11])
			0:	begin                           // Group 2 Microinstructions
				SkipGroup;
				if (`CLA) AC = 0;
				if (`OSR) AC = AC | SR;
				if (`HLT) Run = 0;
				end
				
			1:	begin							// Group 3 Microinstructions
				$display("Group 3 microinstruction at PC = %0o",PC-1," ignored");
				end
		endcase
		end
		
	endcase
  end
endtask
 
	
	
	
	
//
// Handle the Skip Group of microinstructions
//
//
	
	
task SkipGroup;
	reg Skip;
    begin
	case (`IS)			
	  0:	begin		// don't invert sense of skip [OR group]
			Skip = 0;
			if ((`SNL) && (L == 1'b1)) Skip = 1;
			if ((`SZA) && (AC == `WORD_SIZE'b0)) Skip = 1;
			if ((`SMA) && (AC[0] == 1'b1)) Skip = 1;			// less than zero
			end
			
	  1:	begin		// invert sense of skip [AND group]
			Skip = 1;
			if ((`SZL) && !(L == 1'b0)) Skip = 0;
			if ((`SNA) && !(AC != `WORD_SIZE'b0)) Skip = 0;
			if ((`SPA) && !(AC[0] == 1'b0)) Skip = 0;
			end
	endcase
	if (Skip)
		PC = PC + 1;
	end	
 endtask



//
// Dump contents of memory
//

task DumpMemory;
    begin
	for (i=0;i<`MEM_SIZE;i=i+1)
	    if (Mem[i] != 0)
		$display("%0o  %o",i,Mem[i]);
			
	end
endtask








task FPLOAD;
    begin
	MA = Mem[PC];
	PC = PC + 1;

	FPAC[1:8] = Mem[MA];
	{FPAC[0],FPAC[9:19]} = Mem[MA+1];
	FPAC[20:31] = Mem[MA+2]; 

	//$display("FPAC after load from[%0o]: %0x", MA, FPAC);
    end
endtask







task FPSTOR;
    begin
	MA = Mem[PC];
	PC = PC + 1;

	Mem[MA] = FPAC[1:8];
	Mem[MA+1] = {FPAC[0], FPAC[9:19]};
	Mem[MA+2] = FPAC[20:31];

	//$display("Mem after store at[%0o]: %0x %0x %0x %0x", MA, Mem[MA], Mem[MA+1], Mem[MA+2], FPAC);
    end
endtask
	




task FPADD;
	reg [7:0] expA;
	reg [7:0] expB;
	reg [25:0] sigA;
	reg [25:0] sigB;
	reg sinA;
	reg sinB;
	reg[23:0] diff;
	integer p;

    begin
	MA = Mem[PC];		//load address
	PC = PC + 1;		//increment counter

	expB = Mem[MA];		//load three words
	sinB = Mem[MA+1][0];
	sigB = {3'b000, Mem[MA+1][1:11], Mem[MA+2]};

	expA = FPAC[1:8];	//split FPAC into sign, exponent, and mantissa
	sinA = FPAC[0];
	sigA = {3'b000, FPAC[9:31]};
	
	`ifdef VerificationMode begin
		A = $bitstoshortreal({sinA,expA,sigA[22:0]});
		B = $bitstoshortreal({sinB, expB, sigB[22:0]});  		//32 bit operands in IEEE 754 format. 
		end 
	`endif
	 
	//check if one or both of the operands are 0
	//if zero, set FPAC to other operand if not zero - sign can be positive or negative even if both operands are 0s
	if((expA == 8'b0 && sigA == 23'b0) && (expB == 8'b0 && sigB == 23'b0)) begin
	    FPAC = {sinA&sinB, 31'b0};
	end

	else if(expA == 8'b0 && sigA == 23'b0) begin
	    FPAC = {sinB, expB[7:0], sigB[22:0]};
	end

	else if(expB == 8'b0 && sigB == 23'b0) begin
	    FPAC = FPAC;
	end

	else if(expA == expB && sigA == sigB && sinA != sinB)	//same number different signs = 0
		FPAC = 32'b0;

	//if both not zero
	else
	    begin
	        if(expA < expB)			//set A and B so that number with bigger exponent is always stored in A
	    	    begin
			expA = expB;
			expB = FPAC[1:8];

			sinA = sinB;
			sinB = FPAC[0];

			sigA = sigB;
			sigB = {3'b000, FPAC[9:31]};
	    	    end

		
		//J-bits
		sigA[23] = 1'b1;
		sigB[23] = 1'b1;

		//variable used to round sigB if it is shifted to match exponents
		diff = sigB[23:0];	//saves sigB for now but will be shifted to retrieve the bits that are cut off
		sigB = sigB >> (expA - expB);
		diff = diff << (24 - (expA - expB)); //keep track of bits lost when sigB was shifted

		//$display("\nA: %0x %0x %0x \nB: %0x %0x %0x", sinA, expA, sigA, sinB, expB, sigB);

		if(expA == 1'b1 && expB == 1'b1 && sinA != sinB)
		    expA = 8'b0;

		if(sinA == 1'b1)
	   	    sigA = -sigA;

		if(sinB == 1'b1)
	    	    sigB = -sigB;

		//$display("%0x %0x %0x", sinB, expB, sigB);

		sigA = sigA + sigB;
		sinA = sigA[25];		//sign of result

		if(sinA == 1'b1)
	    	    sigA = -sigA;

		

		//$display("%0x %0x %0x", sinA, expA, sigA);

		//if(expA == 8'b0)
			
		//overflow case - round and normalize
		if(sigA[24] == 1'b1 && expA != 8'b0)
	   	    begin
			expA = expA + 1;

			if(sigA[1:0] == 2'b11)
		    	    begin
				sigA = sigA >> 1;
				sigA = sigA + 1;
		    	    end

			else
		    	    sigA = sigA >> 1;	

			if(sigA[24] == 1'b1)
		    	    begin
				expA = expA + 1;
				sigA = sigA >> 1;
		    	    end	
	    	    end

		//underflow - normalize
		else if(sigA && expA != 8'b0)
	    	    begin	
			for (p = 23; p >= 0; p = p - 1)
		    	    begin
				if(sigA[p] == 1'b1)
			    	    begin
					sigA = sigA << (23 - p);
 					sigA = sigA - (diff >> p+1); //restore lost bits
					expA = expA - (23 - p);				
					p = -1;
			   	     end
		    	    end
	    	    end

	
		//$display("%0x %0x %0x", sinA, expA, sigA);
		FPAC[0] = sinA;
		FPAC[1:8] = expA;
		FPAC[9:31] = sigA[22:0];

		if(expA == 8'b11111111) begin	//infinity
	    	    FPAC = {sinA, 8'b11111111, 23'b0};

	    end

	
	end

	`ifndef VerificationMode 
		$display("			FPAC after addition: %0x", FPAC);
	`endif

	
	`ifdef VerificationMode begin
		Verify();
		end
	`endif

    end
endtask




task FPMULT;
	reg [7:0]expA;
	reg [7:0]expB;
	logic unsigned [8:0]expC;
	reg [23:0]sigA;
	reg [23:0]sigB;
	reg sinA;
	reg sinB;
	integer p;
	reg [47:0]result;

    begin

	MA = Mem[PC];
	PC = PC + 1;

	result = 0;

	expB = Mem[MA];		//load three words
	sinB = Mem[MA+1][0];
	sigB = {1'b0,Mem[MA+1][1:11],Mem[MA+2]};

	expA = FPAC[1:8];	//split FPAC into sign, exponent, mantissa
	sinA = FPAC[0];
	sigA = {1'b0, FPAC[9:31]};

	//$display("\nA: %0x %0x %0x \nB: %0x %0x %0x", sinA, expA, sigA, sinB, expB, sigB);

	`ifdef VerificationMode begin
		A = $bitstoshortreal({sinA,expA,sigA[22:0]});
		B = $bitstoshortreal({sinB, expB, sigB[22:0]});  		//32 bit operands in IEEE 754 format. 
		end
	`endif 

	//if one operand is 0 - result 0
	//sign can be negative
	if((sigA == 23'b0 && expA == 8'b0) || (sigB == 23'b0 && expB == 8'b0))
	    FPAC = {sinA^sinB, 31'b0};

	else if((expA + expB) > 127)
	    begin
		//$display("\nA: %0x %0x %0x \nB: %0x %0x %0x", sinA, expA, sigA, sinB, expB, sigB);

		sigA[23] = 1'b1;		//J-bits
		sigB[23] = 1'b1;

		//calculate result of multiplication
		for(p = 0; p < 24; p = p+1)
	   	    begin
	        	if(sigB[p] == 1'b1)
		    	    result = result + (sigA << p);
	   	    end

		expC = expA + expB - 127;		//exponent
		expA = expC[7:0];
			//$display("\nexpC %0b expA %0b\n", expC, expA);

		//determine sign
		if(sinA && sinB)
	   	    sinA = 0;

		else if(!sinA && !sinB)
	    	    sinA = 0;

		else
	    	    sinA = 1;

		//overflow
		if(result[47] == 1'b1)
	    	    begin
			expA = expA + 1;
			result = result >> 1;    
	    	    end

		//round answer
		if(result[22] == 1'b1 && result[21:0] != 22'b0)
	   	    begin
			result = result + (1 << 23);
	    	    end

		else if(result[22] == 1'b1 && result[21:0] == 22'b0 && result[23] == 1'b1)
	   	    begin
			result = result + (1 << 23);
	    	    end

		//renormalize if overflow after rounding
		if(result[47] == 1'b1)
	    	    begin
			expA = expA + 1;
			result = result >> 1;    
	    	    end

		//$display("\nA: %0x %0d %0x %0d", sinA, expA, sigA, expC);


		FPAC[0] = sinA;
		FPAC[1:8] = expA;
		FPAC[9:31] = result[45:23];

		if(expC >= 8'b11111111)		//infinity or nan
	   	    FPAC = {sinA, 8'b11111111, 23'b0};

	    end	

	else if((expA + expB) <=127)
		FPAC = {sinA^sinB, 31'b0};

	//$display("\nA: %0x %0x %0x", expA, expB, expC);
	`ifndef VerificationMode 
		$display("FPAC after multiplication: %0x", FPAC);
	`endif

	
	`ifdef VerificationMode begin
		Verify();
		end
	`endif

    end
endtask




task Verify;
	logic unsigned [31:0] InExactFlag;                    // 1 for InExact answer , 0 for Exact .
	logic [31:0] D;
	if((`OpCode == IOT)&&(IR[3:11] == 9'b101101011)) begin
		C = A + B;
		D = $shortrealtobits(C); 
		
		InExactFlag = (FPAC > D) ? (FPAC - D) : (D - FPAC);
		if(InExactFlag == 2'b00 || InExactFlag == 2'b01 )
			$display(" Result in Accumulator : %b_%h_%h \t %o_%o_%o \t  Expected result: %b_%h_%h \t Result Differs by: %d	", FPAC[0], FPAC[1:8], FPAC[9:31],FPAC[1:8]  ,{FPAC[0],FPAC[9:19]}, FPAC[20:31] , D[31], D[30:23], D[22:0], InExactFlag);
		else if (InExactFlag > 2'b01)
			$display("\nOops, We're trying to fix it: Result in Accumulator : %b_%h_%h \t %o_%o_%o \t  Expected result: %b_%h_%h \t Result Differs by: %d	", FPAC[0], FPAC[1:8], FPAC[9:31],FPAC[1:8] , {FPAC[0],FPAC[9:19]} ,FPAC[20:31] , D[31], D[30:23], D[22:0],InExactFlag);

		end
	else if((`OpCode == IOT)&&(IR[3:11] == 9'b101101100)) begin
		C = A * B;
		D = $shortrealtobits(C); 
		InExactFlag = (FPAC > D) ? (FPAC - D) : (D - FPAC);
		if(InExactFlag == 2'b00 || InExactFlag == 2'b01 )
			$display(" Result in Accumulator : %b_%h_%h \t %o_%o_%o \t  Expected result: %b_%h_%h \t Result Differs by: %d	", FPAC[0], FPAC[1:8], FPAC[9:31],FPAC[1:8]  ,{FPAC[0],FPAC[9:19]}, FPAC[20:31] , D[31], D[30:23], D[22:0], InExactFlag);
		else if (InExactFlag > 2'b01)
			$display("\n Oops we're trying to fix it! Result in Accumulator : %b_%h_%h \t %o_%o_%o \t  Expected result: %b_%h_%h \t Result Differs by: %d	", FPAC[0], FPAC[1:8], FPAC[9:31],FPAC[1:8]  ,{FPAC[0],FPAC[9:19]}, FPAC[20:31] , D[31], D[30:23], D[22:0], InExactFlag);
		end
endtask 		



initial
  begin

  LoadObj;			    // load memory from object file
  
  //DumpMemory;
  
  PC = `WORD_SIZE'o200; // octal 200 start address
  L = 0;			    // initialize accumulator and link
  AC = 0;
  InterruptsOn = 0;
  InterruptReq = 0;
  Run = 1;				// not halted
  
  for (i=0;i<8;i = i + 1)
    begin
    CPI[i] = 0;
    IC[i] = 0;
    end



// $display(" PC L  AC   IR  Op P I + Clocks");
// $display("-------------------------------");

  while (Run)
    begin

    Clocks = 0;
    Fetch;
	
//	$display("%0o %0o %o %o %0o  %0o %0o",PC-1,L,AC,IR,`OpCode,`Page0Bit,`IndirectBit);
	
    Execute;
	
//    $display("                 %d ",Clocks);
	
    if ((InterruptsOn) && (InterruptReq))
	  begin
	  Mem[0] = PC;		// save PC
	  PC = 1;			// jump to interrupt service routine
	  end
    end

//  $display("    %0o %o\n\n",L,AC);
  DumpMemory;
	
  TotalClocks = 0;
  TotalIC = 0;	
  /*
  for (i=0;i<8;i = i +1)
	begin
	case (i)
	  AND:  $display("%0d AND instructions executed, using %0d clocks",IC[i],CPI[i]);
	
	  TAD:  $display("%0d TAD instructions executed, using %0d clocks",IC[i],CPI[i]);
	
	  ISZ:	$display("%0d ISZ instructions executed, using %0d clocks",IC[i],CPI[i]);
	
	  DCA:	$display("%0d DCA instructions executed, using %0d clocks",IC[i],CPI[i]);
			
	  JMS:	$display("%0d JSM instructions executed, using %0d clocks",IC[i],CPI[i]);
			
	  JMP:	$display("%0d JMP instructions executed, using %0d clocks",IC[i],CPI[i]);
			
	  IOT:	$display("%0d IOT instructions executed, using %0d clocks",IC[i],CPI[i]);
					
	  OPR:	$display("%0d OPR instructions executed, using %0d clocks",IC[i],CPI[i]);
	endcase

	TotalClocks = TotalClocks + CPI[i];
	TotalIC = TotalIC + IC[i];
	end
  $display("---------------------------------------------------------");
  $display("%0d Total instructions executed, using %0d clocks\n",TotalIC, TotalClocks);
  $display("Average CPI        = %4.2f\n",100.0 * TotalClocks/(TotalIC * 100.0));
*/	
  end


endmodule
