all: build compile run

all_VerificationMode: build compile1 run

build:
	vlib work
 
compile:
	vlog -sv pdp8.sv 

compile1:
	vlog -sv +define+VerificationMode pdp8.sv
		
run: 
	vsim -c +MEM= PDP8
