`timescale 1ns / 1ps

module intt_step1 #(N=8, Q=17, XSI=2, WIDTH=5, STAGES=10, BUTTERFLIES=N/2)(
    input clk, rst, start,
    output reg stage_done
    );
    
    // N = number of inputs
    // Q = prime modulus i.e. all the values should be present within 0 to Q-1
    // XSI = Twiddle factor number
    // WIDTH = data width i.e. log2(Q)
    // STAGES = no of butterfly stages i.e. log2(N)
    // BUTTERFLIES = no of butterflies per stage i.e N/2
    
    reg [$clog2(N)-1:0] butterfly_count;
    
    //============= INPUT BRAM INITITIALIZATION =============== (Ture DUAL PORT RAM)
    reg en,w_en;
    reg [$clog2(N)-1:0] addr1, addr2;
    wire [$clog2(N)-1:0] addr1_rev,addr2_rev;
    reg [WIDTH-1:0] din1,din2;
    wire [WIDTH-1:0] dout1,dout2;
    
    bram_input b_in(.clka(clk), .ena(en), .wea(w_en), .addra(addr1), .dina(din1), .douta(dout1),
                    .clkb(clk), .enb(en), .web(w_en), .addrb(addr2), .dinb(din2), .doutb(dout2));
                  
    //============= TWIDDLE FACTOR BRAM INITITIALIZATION =============== (SINGLE PORT ROM)
    reg [$clog2(N/2)-1:0] addr_tw;
    wire [WIDTH-1:0] dout_tw;
    
    bram_twiddle b_tw(.clka(clk), .addra(addr_tw), .douta(dout_tw));
    
    
    //============= COMPUTE STATE COMBINATIONAL LOGIC =============
    wire [WIDTH:0] sum = dout1 + dout2;
    wire [WIDTH-1:0] diff = (dout1 >= dout2) ? (dout1 - dout2) : (dout1 + Q - dout2);
    
    wire [WIDTH-1:0] A = (sum >= Q)? (sum - Q) : sum; // Fast Modulo
    wire [2*WIDTH-1:0] prod = (diff * dout_tw);
    wire [WIDTH-1:0] B = prod % Q;
    
    //============= PARAMETERS & STATES =============
    localparam  IDLE = 4'd1,        //wait for start signal
                FETCH = 4'd2,       //give respective addresses to get 2 inputs and twiddle factor
                WAIT1 = 4'd3,       
                WAIT2 = 4'd4,       //wait 2 clock cycles because of 2 clk latency of BRAM
                COMPUTE = 4'd5,     //perform butterfly operations & store back into BRAM location for next stage computing
                STAGE_DONE = 4'd6;        //if all N/2 computations are done, we can say a stage is done
    
    reg [3:0] state, next_state;
    
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
            COMPUTE: if(butterfly_count >= N/2 - 1) next_state = STAGE_DONE;
                     else next_state = FETCH;
            STAGE_DONE: next_state = IDLE;  
            default: next_state = IDLE;
        endcase
    end
    
    //============= DATAPATH & OUTPUT REGISTERING =============
    always@(posedge clk or posedge rst) begin
        if(rst) begin
            {addr1, addr2, addr_tw} <= 0;
            {en, w_en} <= 0;
            {din1,din2} <= 0;
            butterfly_count <= 0;
            stage_done <= 0;
        end
        else begin
            w_en <= 0; //defaults to 0
            case(state)
                IDLE: begin
                    {addr1, addr2, addr_tw} <= 0;
                    butterfly_count <= 0;
                    stage_done <= 0;
                end
                
                FETCH: begin 
                    addr1 <= butterfly_count;
                    addr2 <= butterfly_count+4;
                    addr_tw <= butterfly_count;
                    en<=1;
                end
                
                COMPUTE: begin
                    din1 <= A;
                    din2 <= B;
                    w_en <= 1; // goes high only in compute state
                    butterfly_count <= butterfly_count+1;
                end
                
                STAGE_DONE: stage_done <=1;
                
            endcase
        end
    end
endmodule
