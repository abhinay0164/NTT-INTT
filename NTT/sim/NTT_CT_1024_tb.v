`timescale 1ns / 1ps

module NTT_CT_1024_tb();
    parameter N=1024, Q=12289, W=10322, WIDTH=14, STAGES=10, BUTTERFLIES=N/2;
    
    reg clk, rst, start;
    wire stage_done, done;
    
    NTT_CT_1024 #(N,Q,W,WIDTH,STAGES,BUTTERFLIES) NTT_1024(clk,rst,start,stage_done,done);
    
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
        wait(done);
        repeat(2) @(negedge clk);
        $finish;
    end
endmodule