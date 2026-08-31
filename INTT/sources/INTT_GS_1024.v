`timescale 1ns / 1ps

module INTT_GS_1024 #(N=1024, Q=12289, XSI=5173, WIDTH=14, STAGES=10, N_INV=12277, BUTTERFLIES=N/2)(
    input clk, rst, start,
    output reg stage_done, done, finish
    );
    
    // N = number of inputs
    // Q = prime modulus i.e. all the values should be present within 0 to Q-1
    // XSI = Twiddle factor number
    // WIDTH = data width i.e. log2(Q)
    // STAGES = no of butterfly stages i.e. log2(N)
    // BUTTERFLIES = no of butterflies per stage i.e N/2

    
    //============= INPUT BRAM INITITIALIZATION =============== (Ture DUAL PORT RAM)
    reg en, w_en1, w_en2;
    (* keep = "true" *) reg [$clog2(N)-1:0] addr1, addr2;
    (* keep = "true" *) reg [WIDTH-1:0] din1,din2;
    (* dont_touch = "true" *) wire [WIDTH-1:0] dout1,dout2;
    
    bram_input_1024 b_in_1024(.clka(clk), .ena(en), .wea(w_en1), .addra(addr1), .dina(din1), .douta(dout1),
                    .clkb(clk), .enb(en), .web(w_en2), .addrb(addr2), .dinb(din2), .doutb(dout2));
                  
    //============= TWIDDLE FACTOR BRAM INITITIALIZATION =============== (SINGLE PORT ROM)
    reg [$clog2(N/2)-1:0] addr_tw;
    wire [WIDTH-1:0] dout_tw;
    
    bram_twiddle_1024 b_tw_1024(.clka(clk), .addra(addr_tw), .douta(dout_tw));
    
    //============= PARAMETERS & STATES =============
    localparam  IDLE = 4'd1,        //wait for start signal
                FETCH = 4'd2,       //give respective addresses to get 2 inputs and twiddle factor
                WAIT1 = 4'd3,       
                WAIT2 = 4'd4,       //wait 2 clock cycles because of 2 clk latency of BRAM
                COMPUTE = 4'd5,     //perform butterfly operations & store back into BRAM location for next stage computing
                STAGE_DONE = 4'd6,        //if all N/2 computations are done, we can say a stage is done
                DONE = 4'd7,
                REORDER_FETCH = 4'd8,
                WAIT3 = 4'd9,
                WAIT4 = 4'd10,
                REORDER_COMPUTE = 4'd11,
                FINISH = 4'd12;
    
    reg [3:0] state, next_state;
    
    //============= COMPUTE STATE COMBINATIONAL LOGIC =============
    wire [WIDTH:0] sum = dout1 + dout2;
    wire [WIDTH-1:0] diff = (dout1 >= dout2) ? (dout1 - dout2) : (dout1 + Q - dout2);
    
    wire [WIDTH-1:0] A = (sum >= Q)? (sum - Q) : sum; // Fast Modulo
    wire [2*WIDTH-1:0] prod = (diff * dout_tw);
    wire [WIDTH-1:0] B = prod % Q;
    
    //============= FETCH STATE COMBINATIONAL LOGIC =============
    reg [$clog2(N)-1:0] butterfly_count, stage_idx;
    
    wire [$clog2(N)-1:0] bit_pos = (STAGES-1) - stage_idx;
    wire [$clog2(N)-1:0] upper = (butterfly_count >> bit_pos) << (bit_pos + 1);
    wire [$clog2(N)-1:0] lower = butterfly_count & ((1 << bit_pos) -1);
    
    wire [$clog2(N)-1:0] stride = 1 << bit_pos;
    
    //============= REORDER STAGE COMBINATIONAL LOGIC =============
    reg [$clog2(N)-1:0] bram_idx;
    wire [$clog2(N)-1:0] bram_idx_rev;
    genvar i;
    generate 
        for(i=0;i<$clog2(N);i=i+1) begin
            assign bram_idx_rev[($clog2(N)-1)-i] = bram_idx[i];
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
            COMPUTE: if(butterfly_count >= N/2 - 1) next_state = STAGE_DONE;
                     else next_state = FETCH;
            STAGE_DONE: if (stage_idx >= STAGES - 1) next_state = DONE;
                        else next_state = FETCH;
            DONE: next_state = REORDER_FETCH;
            REORDER_FETCH: next_state = WAIT3;
            WAIT3: next_state = WAIT4;
            WAIT4: next_state = REORDER_COMPUTE;
            REORDER_COMPUTE: if(bram_idx >= N-1) next_state = FINISH;
                             else next_state = REORDER_FETCH;
            FINISH: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
    
    //============= DATAPATH & OUTPUT REGISTERING =============
    always@(posedge clk or posedge rst) begin
        if(rst) begin
            {addr1, addr2, addr_tw} <= 0;
            {en, w_en1, w_en2} <= 0;
            {din1,din2} <= 0;
            stage_idx <= 0;
            butterfly_count <= 0;
            stage_done <= 0;
            done <= 0;
            bram_idx <= 0;
            finish <= 0;
        end
        else begin
            {w_en1, w_en2} <= 0; //defaults to 0
            stage_done <= 0;
            case(state)
                IDLE: begin
                    {addr1, addr2, addr_tw} <= 0;
                    stage_idx <= 0;
                    butterfly_count <= 0;
                    stage_done <= 0;
                    done <= 0;
                    bram_idx <= 0;
                    finish <= 0;
                end
                
                FETCH: begin 
                    addr1 <= upper | lower;
                    addr2 <= (upper | lower) + stride;
                    addr_tw <= (butterfly_count & ((1 << bit_pos) - 1)) << stage_idx;
                    en <= 1;
                end
                
                COMPUTE: begin
                    din1 <= A;
                    din2 <= B;
                    w_en1 <= 1; // goes high only in compute state
                    w_en2 <= 1;
                    butterfly_count <= butterfly_count+1;
                end
                
                STAGE_DONE: begin
                    stage_done <= 1;
                    butterfly_count <= 0;
                    stage_idx <= stage_idx + 1;
                end
                
                DONE: done <=1;
                
                REORDER_FETCH: begin
                    done <= 0;
                    addr1 <= bram_idx;
                    addr2 <= bram_idx_rev;
                    en <= 1;
                end
                
                REORDER_COMPUTE: begin 
                    if(bram_idx < bram_idx_rev) begin //flip the addresses
                        w_en1 <= 1;
                        w_en2 <= 1;
                        din1 <= (dout2 * N_INV) % Q;
                        din2 <= (dout1 * N_INV) % Q;
                    end
                    else if (bram_idx == bram_idx_rev) begin//ex: 0
                        w_en1 <= 1;
                        din1 <= (dout1 * N_INV) % Q;
                    end
                    else
                        {w_en1, w_en2} <= 0; //data stays in place  
                    
                    bram_idx <= bram_idx + 1;
                end
                
                FINISH: finish <= 1;
            endcase
        end
    end
endmodule