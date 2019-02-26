FPCLAC=6550
FPLOAD=6551
FPSTOR=6552
FPADD=6553
FPMULT=6554

	
*0200			/ start at address 0200
Main, 	cla cll 	/ clear AC and Link
loop,	FPCLAC 		
	FPLOAD 
A1,	A
	FPADD  
B1,	B
	tad A1
	tad E
	dca A1
	tad B1
	tad E
	dca B1
	isz count
	jmp loop
	hlt 			/ Halt program
	jmp Main		/ To continue - goto Main
/
/ Data Section
/
*0250 	
count,	-205
E, 6	
A, 	0000
	0000
	0000 		
B, 	0000
	0000
	0000	
$Main 			/ End of Program; Main is entry point
