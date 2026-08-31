`timescale 1ns / 1ps

module ntt_step1_tb();
    reg clk, rst, start;
    wire done;
    
    parameter N=8, Q=17, W=9, WIDTH=5, STAGES=3, BUTTERFLIES=N/2;
    
    ntt_step1 #(N,Q,W,WIDTH,STAGES,BUTTERFLIES) ntt_s1(clk,rst,start,done);
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
