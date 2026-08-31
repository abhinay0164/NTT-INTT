`timescale 1ns / 1ps

module intt_step2_tb();
    reg clk, rst, start;
    wire stage_done, done, finish;
    
    parameter N=8, Q=17, XSI=2, WIDTH=5, STAGES=3, N_INV=15, BUTTERFLIES=N/2;
    
    intt_step2 #(N,Q,XSI,WIDTH,STAGES,N_INV,BUTTERFLIES) intt_s2(clk,rst,start,stage_done,done,finish);
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    task rst_dut();
    begin
        start <= 0; rst <= 1;
        repeat(10) @(negedge clk);
        rst <= 0;
    end
    endtask
    
    task start_dut();
    begin
        start <=1;
        @(negedge clk);
        start <=0;
    end
    endtask
    
    initial begin
        rst_dut;
        start_dut;
        wait(finish);
        repeat(2) @(negedge clk);
        $stop;
    end
endmodule
