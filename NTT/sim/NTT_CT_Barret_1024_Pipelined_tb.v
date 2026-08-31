`timescale 1ns / 1ps

module NTT_CT_Barret_1024_Pipelined_tb();
    parameter N=1024, Q=12289, W=10322, BARRETT_M=21843, WIDTH=14, STAGES=10, BUTTERFLIES=N/2;
    
    reg clk, rst, start;
    wire stage_done, done;
    
    NTT_CT_Barret_1024_Pipelined #(N,Q,W,BARRETT_M,WIDTH,STAGES,BUTTERFLIES) NTT_Barret_1024(clk,rst,start,stage_done,done);
    
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