`timescale 1ns / 1ps

module INTT_GS_1024_tb();
    reg clk, rst, start;
    wire stage_done, done, finish;
    
    parameter N=1024, Q=12289, XSI=5173, WIDTH=14, STAGES=10, N_INV=12277, BUTTERFLIES=N/2;
    
    INTT_GS_1024 #(N,Q,XSI,WIDTH,STAGES,N_INV,BUTTERFLIES) intt_1024(clk,rst,start,stage_done,done,finish);
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