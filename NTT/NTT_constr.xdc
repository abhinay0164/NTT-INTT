create_clock -period 10.000 -name virtual -waveform {0.000 5.000} -add [get_ports clk]

# Set input delays (adjust t1 and t2 based on your design requirements)
set_input_delay -clock virtual -min 2.000 [get_ports {rst start}]
set_input_delay -clock virtual -max 2.000 [get_ports {rst start}]

# Set output delays (adjust t1 and t2 based on your design requirements)
set_output_delay -clock virtual -min 1.000 [get_ports {stage_done done}]
