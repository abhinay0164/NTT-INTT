`timescale 1ns / 1ps

    module NTT_CT_1024 #(N=1024, Q=12289, W=10322, WIDTH=14, STAGES=10, BUTTERFLIES=N/2)(
    input clk, rst, start,
    output reg stage_done, done
    );
    
    // N = number of inputs
    // Q = prime modulus i.e. all the values should be present within 0 to Q-1
    // W = Twiddle factor number
    // WIDTH = data width i.e. log2(Q)
    // STAGES = no of butterfly stages i.e. log2(N)
    // BUTTERFLIES = no of butterflies per stage i.e N/2
    
    
    //============= INPUT BRAM INITITIALIZATION =============== (Ture DUAL PORT RAM)
    reg en,w_en;
    reg [$clog2(N)-1:0] addr1, addr2;
    wire [$clog2(N)-1:0] addr1_rev,addr2_rev;
    reg [WIDTH-1:0] din1,din2;
    wire [WIDTH-1:0] dout1,dout2;
    
    bram_input_1024 b_in(.clka(clk), .ena(en), .wea(w_en), .addra(addr1_rev), .dina(din1), .douta(dout1),
                    .clkb(clk), .enb(en), .web(w_en), .addrb(addr2_rev), .dinb(din2), .doutb(dout2));
                  
    //============= TWIDDLE FACTOR BRAM INITITIALIZATION =============== (SINGLE PORT ROM)
    reg [$clog2(N/2)-1:0] addr_tw;
    wire [WIDTH-1:0] dout_tw;
    
    bram_twiddle_1024 b_tw(.clka(clk), .addra(addr_tw), .douta(dout_tw));
    
    //============= PARAMETERS & STATES =============
    localparam  IDLE = 4'd1,        //wait for start signal
                FETCH = 4'd2,       //give respective addresses to get 2 inputs and twiddle factor
                WAIT1 = 4'd3,       
                WAIT2 = 4'd4,       //wait 2 clock cycles because of 2 clk latency of BRAM
                COMPUTE = 4'd5,     //perform butterfly operations & store back into BRAM location for next stage computing
                STAGE_DONE = 4'd6,        //if all N/2 computations are done, we can say a stage is done
                DONE = 4'd7;
                
    reg [3:0] state, next_state;
    
    //============= COMPUTE STATE COMBINATIONAL LOGIC =============
    wire [WIDTH-1:0] U = dout1; //U
    wire [2*WIDTH-1:0] mult_out = dout2 * dout_tw; //double bits as we are multiplying
    wire [WIDTH-1:0] V = mult_out % Q; //V
    wire [WIDTH:0] add_out = U + V; //extra bit in case of overflow
    
    wire [WIDTH-1:0] A = (add_out >= Q) ? (add_out - Q) : add_out; // Fast Modulo!
    wire [WIDTH-1:0] B = (U >= V) ? (U - V) : (U + Q - V); //order of U,Q,V matters as there is chance of going into underflow if U-V+Q is used
    
    //============= FETCH STATE COMBINATIONAL LOGIC =============
    reg [$clog2(N)-1:0] butterfly_count, stage_idx;
    //Zero Insertion logic --> addr1 = upper|lower
    wire [$clog2(N)-1:0] upper_bits = (butterfly_count >> stage_idx) << (stage_idx + 1);
    wire [$clog2(N)-1:0] lower_bits = butterfly_count & ((1 << stage_idx) - 1);
    
    //============= ADDRESS REVERSING =============
    //For input BRAMs
    genvar i;
    generate 
        for(i=0;i<$clog2(N);i=i+1) begin
            assign addr1_rev[($clog2(N)-1)-i] = addr1[i];
            assign addr2_rev[($clog2(N)-1)-i] = addr2[i];
        end
    endgenerate
    
    //============= STATE UPDATE LOGIC =============
    always@(posedge clk or posedge rst) begin
        if(rst) state <= IDLE;
        else state <= next_state;
    end
    
    //============= STATE TRANSITION LOGIC =============
    always@(*) begin
        next_state = state;
        case(state)
            IDLE: if(start) next_state = FETCH;
            FETCH: next_state = WAIT1;
            WAIT1: next_state = WAIT2;
            WAIT2: next_state = COMPUTE;
            COMPUTE: if(butterfly_count >= BUTTERFLIES - 1) next_state = STAGE_DONE;
                     else next_state = FETCH;
            STAGE_DONE: if(stage_idx >= STAGES - 1) next_state = DONE;
                        else next_state = FETCH;
            DONE: next_state = IDLE;  
            default: next_state = IDLE;
        endcase
    end
    
    //============= DATAPATH & OUTPUT REGISTERING =============
    always@(posedge clk or posedge rst) begin
        if(rst) begin
            {addr1, addr2, addr_tw} <= 0;
            {en, w_en} <= 0;
            {addr1,addr2} <= 0;
            {din1,din2} <= 0;
            butterfly_count <= 0;
            stage_done <= 0;
            done <= 0;
        end
        else begin
            w_en <= 0; //defaults to 0
            stage_done <= 0;
            case(state)
                IDLE: begin
                    {addr1, addr2, addr_tw} <= 0;
                    stage_idx <= 0;
                    butterfly_count <= 0;
                    stage_done <= 0;
                    done <= 0;
                end
                
                FETCH: begin 
                    addr1 <= upper_bits | lower_bits;
                    addr2 <= (upper_bits | lower_bits) | (1 << stage_idx); //(upper_bits | lower_bits) + (1 << stage_idx) can also be used, but may cause an overflow
                    addr_tw <= (butterfly_count & ((1 << stage_idx) - 1)) << (STAGES - 1 - stage_idx); //mask and shift operation
                    en<=1;
                end
                
                COMPUTE: begin
                    din1 <= A;
                    din2 <= B;
                    w_en <= 1; // goes high only in compute state
                    butterfly_count <= butterfly_count+1;
                end
                
                STAGE_DONE: begin
                    stage_done <=1;
                    stage_idx <= stage_idx + 1;
                    butterfly_count <= 0;
                end
                
                DONE: done <= 1;
            endcase
        end
    end
endmodule