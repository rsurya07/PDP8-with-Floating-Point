#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#define WORD_SIZE 12
#define MEM_SIZE 4096
#define OBJFILENAME "add01.mem"

#define OPCODEMASK 0x0E00
#define PAGEADDRESSMASK 0x007F


//processor state
u_int16_t PC;		//Program counter
u_int16_t IR;		//Instruction Register
u_int16_t AC;		//Accumulator
u_int16_t SR;		//front panel switch register
u_int16_t MA;		//memory address register
u_int16_t L;		//Link register
u_int32_t FPAC;

u_int16_t Cpage;	//Current page

u_int16_t Mem[MEM_SIZE];	//4k memory

bool InterruptsOn;
bool InterruptReq;
bool Run;


//Fields in instruction word - based on IR
u_int8_t OpCode;		//instruction OpCode	IR[0:2]
u_int16_t IndirectBit = 0x0100;	//Indirect Address Bit	IR[3]
u_int16_t Page0Bit = 0x0080;		//Memory Reference is to Page 0 IR[4]
u_int16_t PageAddress;	//Page offset	IR[5:11]



//opcodes
u_int8_t AND = 0;
u_int8_t TAD = 1;
u_int8_t ISZ = 2;
u_int8_t DCA = 3;
u_int8_t JMS = 4;
u_int8_t JMP = 5;
u_int8_t IOT = 6;
u_int8_t OPR = 7;

u_int8_t FPINS = 055;


//Microinstructions
u_int16_t Group = 0x0100;	//IR[3]
u_int16_t CLA = 0x0080;		//IR[4]



//Group 1 microinstructions (IR[3] = 0)
u_int16_t CLL = 0x0040;	//clear L			IR[5]
u_int16_t CMA = 0x0020;	//complement AC 	IR[6]
u_int16_t CML = 0x0010;	//complement L		IR[7]
u_int16_t ROT = 0x000E;	//rotate 			IR[8:10]
u_int16_t IAC = 0x0001;	//increment AC		IR[11]



//Group 2 microinstructions (IR[3] = 1 and IR[11] = 0)
u_int16_t SMA = 0x0040;	//skip on minus AC			IR[5]
u_int16_t SZA = 0x0020;	//skip on zero AC			IR[6]
u_int16_t SNL = 0x0010;	//skip on non-zero L		IR[7]
u_int16_t SPA = 0x0040;	//skip on positive AC		IR[5]
u_int16_t SNA = 0x0020;	//skip on non-zero AC		IR[6]
u_int16_t SZL = 0x0010;	//skip on zero L			IR[7]
u_int16_t IS  = 0x0008;	//invert sense of skip		IR[8]
u_int16_t OSR = 0x0004;	//OR with switch register	IR[9]
u_int16_t HLT = 0x0002;	//halt processor			IR[10]



//Trace Info
int Clocks;
int TotalClocks;
int TotalIC;
int CPI[8]; 	//clocks per instruction
int IC[8];		//instruction count per instruction
int i;

void LoadObj();
void Fetch();
void Execute();
void Operate();
u_int16_t EffectiveAddress();
void DumpMemory();
void SkipGroup();

void fpload();
void fpstore();
void fpadd();
void fpmult();

int main()
{
	LoadObj();
	DumpMemory();
	
	PC = 0200;
	L = 0;
	AC = 0;
	InterruptsOn = 0;
	InterruptReq = 0;
	Run = 1;
	
	for(i = 0; i < 8; i++)
	{
		CPI[i] = 0;
		IC[i] = 0;
	}
	
	while(Run)
	{
		Clocks = 0;
		Fetch();
		
		Execute();
		
		if ((InterruptsOn) && (InterruptReq))
	  	{
	 		Mem[0] = PC;		// save PC
	  		PC = 1;			// jump to interrupt service routine
	  	}
    }
    
    TotalClocks = 0;
    TotalIC = 0;
    
    printf("\n\n");
    
    for(i = 0; i < 8; i++)
    {
    	if(i == AND)
    		printf("%d AND instruction executed, using %d clocks\n", IC[i], CPI[i]);
    		
    	else if(i == TAD)
    		printf("%d TAD instruction executed, using %d clocks\n", IC[i], CPI[i]);
    		
    	else if(i == ISZ)
    		printf("%d ISZ instruction executed, using %d clocks\n", IC[i], CPI[i]);
    		
    	else if(i == DCA )
    		printf("%d DCA instruction executed, using %d clocks\n", IC[i], CPI[i]);
    		
    	else if(i == JMS)
    		printf("%d JMS instruction executed, using %d clocks\n", IC[i], CPI[i]);
    		
    	else if(i == JMP)
    		printf("%d JMP instruction executed, using %d clocks\n", IC[i], CPI[i]);
    		
    	else if(i == IOT)
    		printf("%d IOT instruction executed, using %d clocks\n", IC[i], CPI[i]);
    		
    	else if(i == OPR)
    		printf("%d OPR instruction executed, using %d clocks\n", IC[i], CPI[i]);
    		
    	TotalClocks += CPI[i];
    	TotalIC += IC[i];
    }
    
    printf("------------------------------------------------------\n");
    printf("%d Total instructions executed, using %d clocks\n\n", TotalIC, TotalClocks);
    printf("Average CPI         = %4.2f\n\n\n", 100.0 * TotalClocks/(TotalIC * 100.0));
	
	DumpMemory();
	
	return 0;
}
void LoadObj()
{
	char buff;
	int ins;
	int add = 0;
	
	FILE * memFile = fopen(OBJFILENAME, "r");
	
	while(fscanf(memFile, "%c[\n]", &buff) == 1)
	{         
		if(buff != '@')
		{
			fseek(memFile, ftell(memFile) - 1, SEEK_SET);
			fscanf(memFile, "%x", &ins);
			Mem[add++] = ins;					
		}
		
		else
		{
			fscanf(memFile, "%x", &add);
		}
		
		if (!fscanf(memFile, "%c", &buff))
            break; 		
	}
	
	fclose(memFile);
}


void Fetch()
{
	IR = Mem[PC];
	printf("fetched %o from %o\n", IR, PC);
	Cpage = (PC >> 7);
	PC = PC + 1;
}


void Execute()
{	
	OpCode = IR >> 9;
	
	if(OpCode == AND)
	{
		Clocks = Clocks + 2;
		MA = EffectiveAddress();
		AC = AC & Mem[MA];
	}
	
	else if(OpCode == TAD)
	{
		Clocks = Clocks + 2;
		MA = EffectiveAddress();
		
		AC = AC + Mem[MA];
		
		L = (AC >> 12) & 0x0001;
		AC = AC & 0x0FFF;
		printf("\nMA = %o    AC = %o\n", MA, AC);	
		
	}
	
	else if(OpCode == ISZ)
	{
		Clocks = Clocks + 2;
		MA = EffectiveAddress();
		Mem[MA] = (Mem[MA] + 1) & 0xfff;
		
		printf("\nMA = %o\n", Mem[MA]);
				  
		if(Mem[MA] == 00000)
			PC = PC + 1;
	}
	
	else if(OpCode == DCA)
	{
		Clocks = Clocks + 2;
		MA = EffectiveAddress();
		Mem[MA] = AC;
		AC = 0;
	}
	
	else if(OpCode == JMS)
	{
		Clocks = Clocks + 2;
		MA = EffectiveAddress();
		Mem[MA] = PC;
		PC = MA + 1;
	}
	
	else if (OpCode == JMP)
	{
		Clocks = Clocks + 1;
		PC = EffectiveAddress();
	}
	
	else if(OpCode == IOT)		
	{		
		if(IR == 06550)
			FPAC = 0;
			
		else if(IR == 06551)
			fpload();
			
		else if(IR == 06552)
			fpstore();
			
		else if(IR == 06553)
			fpadd();
			
		else if(IR == 06554)
			fpmult();
			
		else
			printf("Invalid IOT instruction at PC = %o ignored\n", PC - 1);
	}
	
	else if(OpCode == OPR)
	{
		Clocks = Clocks + 1;
		Operate();
	}
	
	
	CPI[OpCode] = CPI[OpCode] + Clocks;
	IC[OpCode] = IC[OpCode] + 1;
}


u_int16_t EffectiveAddress()
{
	u_int16_t EA;
	
	PageAddress = IR & PAGEADDRESSMASK;
	
	EA = (IR & Page0Bit) ? ((Cpage << 7) + PageAddress) : PageAddress;
	
	if(IndirectBit & IR)
	{
		Clocks = Clocks + 1;
		
		if((EA >> 3) == 1)
		{
			printf("                         +   ");
			Clocks = Clocks + 1;
			Mem[EA] = Mem[EA] + 1;
		}
	
		EA = Mem[EA];
	}	
	
	return EA;	
}


void Operate()
{
	if(IR & Group)
	{
		if(IR & 0x0001) //IR[11]
		{
			printf("Group 3 microsinstruction at PC = %o ignored\n", PC - 1);
		}
		
		else
		{
			SkipGroup();
			
			if(IR & CLA)
				AC = 0;
				
			if(IR & OSR)
				AC = AC | SR;	
				
			if(IR & HLT)
				Run = 0;
		}
	}
	
	else
	{
		if(IR & CLA)
			AC = 0;
			
		if(IR & CLL)
			L = 0;
			
		if(IR & CMA)
		{
			AC = ~AC;
			AC = AC & 0x0FFF;
		}
			
		if(IR & CML)
		{
			L = ~L;
			L = L & 0x0001;
		}
			
		if(IAC & IR)
		{
			AC = (L << 12) + AC + 1;
			L = (AC >> 12) & 0x0001;
			AC = AC & 0x0FFF;
		}
		
		switch ((ROT & IR) >> 1)
		{
			case 0:	break;
			
			case 1: AC = (AC & 0x003F) << 6 | (AC & 0x0FC0) >> 6;
					break;
				
			case 2:	AC = (AC << 1) | L;
					L = (AC >> 12) & 0x0001;
					AC = AC & 0x0FFF;
					break;
				
			case 3:	AC = (((AC << 1) | L) << 1) | ((AC & 0x0800) >> 11);
					L = (AC >> 12) & 0x0001;
					AC = AC & 0x0FFF;
					break;
				
			case 4:	AC = AC | (L << 12);
					AC = (AC >> 1) | ((AC & 0x0001) << 12);
					L = (AC >> 12) & 0x0001;
					AC = AC & 0x0FFF;
					break;
						
			case 5:	AC = AC | (L << 12);
					AC = (AC >> 2) | ((AC & 0x0003) << 11);
					L = (AC >> 12) & 0x0001;
					AC = AC & 0x0FFF;
					break;
				
			case 6: printf("Unsupported Group 1 microinstruction at PC = %o ignored\n", PC - 1);
					break;
				
			case 7: printf("Unsupported Group 1 microinstruction at PC = %o ignored\n", PC - 1);
					break;
				
			default: break;
		}
	}
}


void SkipGroup()
{
	bool Skip;
	
	if(IS & IR)
	{
		Skip = 1;
		
		if((SZL & IR) && !(L == 0))
			Skip = 0;
			
		if((SNA & IR) && !(AC != 0))
			Skip = 0;
			
		if((SPA & IR) && !((AC >> 11) == 0))
			Skip = 0;
	}
	
	else
	{
		Skip = 0;
		
		if((SNL & IR) && (L == 1))
			Skip = 1;
			
		if((SZA & IR) && (AC == 0))
			Skip = 1;
			
		if((SMA & IR) && ((AC >> 11) == 1))
			Skip = 1;
	}
	
	if(Skip)
		PC = PC + 1;
}	


void DumpMemory()
{
	for(i = 0; i < MEM_SIZE; i++)
	{
		if(Mem[i] != 0)
			printf("%o %o\n", i, Mem[i]);
	}
}	
				 
void fpload()
{
	Fetch();
	MA = Mem[IR];//EffectiveAddress();
	
	FPAC = Mem[MA] << 23;
	FPAC |= (Mem[MA+1] & 0x800) << 31;
	FPAC |= (Mem[MA+1] & 0x7ff) << 12;
	FPAC |= Mem[MA+2];
	
	printf("FPAC after load from[%o]: %x\n", MA, FPAC);
}

void fpstore()
{
	Fetch();
	MA = Mem[IR];
	
	Mem[MA] = (FPAC & 0x7f800000) >> 23;
	Mem[MA+1] = (FPAC & 0x7ff000) >> 12;
	Mem[MA+1] |= (FPAC & 0x80000000) >> 20;
	Mem[MA+2] = FPAC & 0xfff;
	
	printf("Mem after store at [%o]: %x %x %x %x\n", MA, Mem[MA], Mem[MA+1], Mem[MA+2], FPAC);
}

void fpadd()
{
	int expA, expB, sigA, sigB, sinA, sinB;
	
	Fetch();
	MA = Mem[IR];
	
	expB = Mem[MA];
	sinB = Mem[MA+1] >> 11;
	sigB = (Mem[MA+1] & 0x7ff) << 12 | Mem[MA+2];
	
	sinA = FPAC >> 31;
	expA = (FPAC & 0x7f800000) >> 23;
	sigA = FPAC & 0x7fffff;
	
	printf("\nA: %x %x %x\nB: %x %x %x\n", sinA, expA, sigA, sinB, expB, sigB);
	
	if(expA < expB)
	{
		expA = expB;
		expB = (FPAC & 0x7f800000) >> 23;
		
		sinA = sinB;
		sinB = FPAC >> 31;
		
		sigA = sigB;
		sigB = FPAC & 0x7fffff;
	}
	
	sigA |= 0x800000;
	sigB |= 0x800000;
	
	sigB = sigB >> (expA - expB);
	
	if(sinA)
		sigA = -sigA;
		
	if(sinB)
		sigB = -sigB;
		
	sigA = sigA + sigB;
	sinA = (sigA & 0x80000000) >> 31;
	
	if(sinA)
		sigA = -sigA;
	
	if(sigA & 0x1000000)
	{
		expA++;
		sigA = sigA >> 1;
	}
	
	else if(sigA)
	{
		for(int i = 23; i >= 0; i--)
		{
			if(sigA >> i)
			{
				expA = expA - (23 - i);
				sigA = sigA << (23 - i);
				break;
			}
		}	
	}
	
	FPAC = sinA << 31 | (expA << 23) | (sigA & 0x7fffff);
	
	printf("FPAC after addition: %x\n", FPAC);
}

void fpmult()
{
	int expA, expB, sigA, sigB, sinA, sinB;
	
	Fetch();
	MA = Mem[IR];
	
	expB = Mem[MA];
	sinB = Mem[MA+1] >> 11;
	sigB = (Mem[MA+1] & 0x7ff) << 12 | Mem[MA+2];
	
	sinA = FPAC >> 31;
	expA = (FPAC & 0x7f800000) >> 23;
	sigA = FPAC & 0x7fffff;
	
	printf("\nA: %x %x %x\nB: %x %x %x\n", sinA, expA, sigA, sinB, expB, sigB);
	
	sigA |= 0x800000;
	sigB |= 0x800000;
	
	long long int result = 0;
	
	for(int i = 0; i < 24; i++)
	{
		if((sigB >> i) & 0x1)
			result = result + ((long)sigA << i);
	}
	
	expA = expA + expB - 127;
	
	if(sinA && sinB)
		sinA = 0;
		
	else if(!sinA && !sinB)
		sinA = 0;
		
	else
		sinA = 1;
		
	if(result & 0x800000000000)
	{
		expA++;
		result = result >> 1;
	}
	
	result = result >> 23;
	result = result & 0x7fffff;
	
	FPAC = sinA << 31 | (expA << 23) | result;
	
	printf("\nA: %x %x %llx\n", sinA, expA, result);
	printf("FPAC after multiplication: %x\n", FPAC);
} 
	
