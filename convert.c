/**************************************************************
Team 3:	Surya Ravikumar
		Suprita Kulkarni
		Manasa Veena Chilakapati
		Gaurav Shankar Archakam
		
ECE 486/586 Homework 4 
5th March, 2018
******************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define exponent_mask 0x7f800000
#define significand_mask 0x007fffff
#define sign_mask 0x80000000
#define lower_12_bits 0x00000fff
#define upper_12_bits 0x007ff000
#define exponent_shift 23
#define significand_shift 12
#define sign_shift 20

_Bool octal = 0;
FILE * fd;
FILE * fda;
FILE * fdm;

void convert(unsigned int);

int main(int argc, char * argv[])
{
	float a;
	float b;
	float c;
	float num;
	
	fd = fopen("add01.mem", "r+");
	fseek(fd, 0, SEEK_END);
	
	fda = fopen("add.txt", "w+");
	fdm = fopen("mul.txt", "w+");
	
	if(argc == 3)
	{
		octal = !strcmp(argv[1], "-o");
		num = atof(argv[2]);
		convert(*(unsigned int*) &num);
	}
	
	else if(argc == 2)
	{
		if((octal = !strcmp(argv[1], "-o")) || !strcmp(argv[1], "-h"))
		{
			while(scanf("%f", &num) != EOF)
				convert(*(unsigned int*) &num);	
		}
		
		else
		{
			num = atof(argv[1]);
			convert(*(unsigned int*) &num);
		}
	}
	
	else
	{
		while(scanf("%f %f", &a, &b) != EOF)
		{
			c = a+b;
			fprintf(fda, "%x\n", *(unsigned int*) &c);
			convert(*(unsigned int*) &a);	
			c = a*b;
			fprintf(fdm, "%x\n", *(unsigned int*) &c);
			convert(*(unsigned int*) &b);
		}	
	}
	
	return 0;
}

void convert(unsigned int val)
{
	int ad1 = (val & exponent_mask) >> exponent_shift;
	int ad2 = ((val & significand_mask) >> significand_shift) | (val & sign_mask) >> sign_shift;
	int ad3 = (val & significand_mask) & lower_12_bits;
		
	if(octal)	
		fprintf(fd, "%04o \n%04o \n%04o \n\n", ad1, ad2, ad3);
		
	else
		fprintf(fd, "%03x\n%03x\n%03x\n", ad1, ad2, ad3);
}
