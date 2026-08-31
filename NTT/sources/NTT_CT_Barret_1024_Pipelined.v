`timescale 1ns / 1ps

module NTT_CT_Barret_1024_Pipelined #(
    parameter N           = 1024,
    parameter Q           = 12289,
    parameter W           = 10322,
    parameter BARRETT_M   = 21843,
    parameter WIDTH       = 14,
    parameter STAGES      = 10,
    parameter BUTTERFLIES = N/2
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    output reg  stage_done,
    output reg  done
);

    // =========================================================================
    // INPUT BRAM INITIALIZATION (True Dual Port RAM)
    // =========================================================================
    reg  en, w_en;
    reg  [$clog2(N)-1:0] addr1, addr2;
    reg  [$clog2(N)-1:0] wr_addr1, wr_addr2;
    wire [$clog2(N)-1:0] addr1_rev, addr2_rev;
    reg  [WIDTH-1:0]     din1, din2;
    wire [WIDTH-1:0]     dout1, dout2;

    bram_input_1024 b_in (
        .clka (clk),       .ena  (en),       .wea  (w_en), 
        .addra(addr1_rev), .dina (din1),     .douta(dout1),
        .clkb (clk),       .enb  (en),       .web  (w_en), 
        .addrb(addr2_rev), .dinb (din2),     .doutb(dout2)
    );
                  
    // =========================================================================
    // TWIDDLE FACTOR BRAM INITIALIZATION (Single Port ROM)
    // =========================================================================
    reg  [$clog2(N/2)-1:0] addr_tw;
    wire [WIDTH-1:0]       dout_tw;

    bram_twiddle_1024 b_tw (
        .clka (clk), 
        .addra(addr_tw), 
        .douta(dout_tw)
    );

    // =========================================================================
    // FSM STATES
    // =========================================================================
    localparam IDLE       = 4'd1,
               FETCH      = 4'd2,
               WAIT1      = 4'd3,
               WAIT2      = 4'd4,
               CALC1      = 4'd5,  // Stage 1: P = dout2 * dout_tw (DSP 1)
               CALC2      = 4'd6,  // Stage 2: barrett_mult = P * BARRETT_M (DSP 2)
               CALC3      = 4'd7,  // Stage 3: q_product = estimate * Q (DSP 3)
               CALC4      = 4'd8,  // Stage 4: fast modulo & butterfly A, B into din1/2
               WRITE      = 4'd9,  // Stage 5: BRAM writeback with preserved address
               STAGE_DONE = 4'd10,
               DONE       = 4'd11;
                
    reg [3:0] state, next_state;
    reg [$clog2(N)-1:0] butterfly_count, stage_idx;

    // =========================================================================
    // ADDRESS GENERATION & BIT-REVERSAL
    // =========================================================================
    wire [$clog2(N)-1:0] upper_bits = (butterfly_count >> stage_idx) << (stage_idx + 1);
    wire [$clog2(N)-1:0] lower_bits = butterfly_count & ((1 << stage_idx) - 1);

    wire [$clog2(N)-1:0] cur_addr1 = upper_bits | lower_bits;
    wire [$clog2(N)-1:0] cur_addr2 = (upper_bits | lower_bits) | (1 << stage_idx);

    genvar i;
    generate 
        for (i = 0; i < $clog2(N); i = i + 1) begin : bit_reverse
            assign addr1_rev[($clog2(N)-1)-i] = (w_en) ? wr_addr1[i] : addr1[i];
            assign addr2_rev[($clog2(N)-1)-i] = (w_en) ? wr_addr2[i] : addr2[i];
        end
    endgenerate

    // =========================================================================
    // PIPELINED DATAPATH REGISTERS & LOGIC
    // =========================================================================
    // Pipeline Stage 1 Registers
    reg [WIDTH-1:0]   u_stage1;
    reg [2*WIDTH-1:0] mult_out_reg;

    // Pipeline Stage 2 Registers
    reg [WIDTH-1:0]   u_stage2;
    reg [2*WIDTH-1:0] mult_out_stage2;
    reg [2*WIDTH + $clog2(BARRETT_M) - 1:0] barrett_mult_reg;

    // Pipeline Stage 3 Registers
    reg [WIDTH-1:0]   u_stage3;
    reg [2*WIDTH-1:0] mult_out_stage3;
    reg [2*WIDTH-1:0] q_product_reg;

    // Estimate wire extracted from Stage 2 register
    wire [WIDTH-1:0] estimate = barrett_mult_reg[2*WIDTH + $clog2(BARRETT_M) - 1 : 2*WIDTH];

    // Combinational logic for Stage 4 (fed by Stage 3 registers)
    wire [$clog2(BARRETT_M)-1:0] diff_comb = mult_out_stage3[$clog2(BARRETT_M)-1:0] - q_product_reg[$clog2(BARRETT_M)-1:0];
    wire [WIDTH-1:0] v_reduced = (diff_comb >= Q) ? (diff_comb - Q) : diff_comb[WIDTH-1:0];

    wire [WIDTH:0]   add_out = u_stage3 + v_reduced;
    wire [WIDTH-1:0] A_comb  = (add_out >= Q) ? (add_out - Q) : add_out[WIDTH-1:0];
    wire [WIDTH-1:0] B_comb  = (u_stage3 >= v_reduced) ? (u_stage3 - v_reduced) : (u_stage3 + Q - v_reduced);

    // =========================================================================
    // STATE TRANSITION LOGIC
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:       if (start) next_state = FETCH;
            FETCH:      next_state = WAIT1;
            WAIT1:      next_state = WAIT2;
            WAIT2:      next_state = CALC1;
            CALC1:      next_state = CALC2;
            CALC2:      next_state = CALC3;
            CALC3:      next_state = CALC4;
            CALC4:      next_state = WRITE;
            WRITE: begin
                if (butterfly_count >= BUTTERFLIES - 1)
                    next_state = STAGE_DONE;
                else
                    next_state = FETCH;
            end
            STAGE_DONE: begin
                if (stage_idx >= STAGES - 1)
                    next_state = DONE;
                else
                    next_state = FETCH;
            end
            DONE:       next_state = IDLE;
            default:    next_state = IDLE;
        endcase
    end

    // =========================================================================
    // SEQUENTIAL DATAPATH & CONTROL REGISTERS
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            {addr1, addr2, addr_tw}          <= 0;
            {wr_addr1, wr_addr2}             <= 0;
            {en, w_en}                       <= 0;
            {din1, din2}                     <= 0;
            {u_stage1, u_stage2, u_stage3}   <= 0;
            {mult_out_reg, mult_out_stage2, mult_out_stage3} <= 0;
            barrett_mult_reg                 <= 0;
            q_product_reg                    <= 0;
            butterfly_count                  <= 0;
            stage_idx                        <= 0;
            stage_done                       <= 0;
            done                             <= 0;
        end else begin
            w_en       <= 0;
            stage_done <= 0;

            case (state)
                IDLE: begin
                    {addr1, addr2, addr_tw} <= 0;
                    {wr_addr1, wr_addr2}    <= 0;
                    stage_idx               <= 0;
                    butterfly_count         <= 0;
                    done                    <= 0;
                    en                      <= 0;
                end

                FETCH: begin
                    addr1    <= cur_addr1;
                    addr2    <= cur_addr2;
                    wr_addr1 <= cur_addr1;
                    wr_addr2 <= cur_addr2;
                    addr_tw  <= (butterfly_count & ((1 << stage_idx) - 1)) << (STAGES - 1 - stage_idx);
                    en       <= 1;
                end

                WAIT1: begin
                    // BRAM Read Latency Cycle 1
                end

                WAIT2: begin
                    // BRAM Read Latency Cycle 2 (Data valid on dout buses)
                end

                CALC1: begin
                    // Stage 1: Twiddle factor multiplication (DSP Slice 1)
                    u_stage1     <= dout1;
                    mult_out_reg <= dout2 * dout_tw;
                end

                CALC2: begin
                    // Stage 2: Barrett quotient estimation multiplication (DSP Slice 2)
                    u_stage2         <= u_stage1;
                    mult_out_stage2  <= mult_out_reg;
                    barrett_mult_reg <= mult_out_reg * BARRETT_M;
                end

                CALC3: begin
                    // Stage 3: Modulus multiplication (DSP Slice 3)
                    u_stage3         <= u_stage2;
                    mult_out_stage3  <= mult_out_stage2;
                    q_product_reg    <= estimate * Q;
                end

                CALC4: begin
                    // Stage 4: Subtraction, Fast Modulo, and Butterfly Outputs
                    din1 <= A_comb;
                    din2 <= B_comb;
                end

                WRITE: begin
                    // Stage 5: BRAM writeback
                    w_en            <= 1;
                    butterfly_count <= butterfly_count + 1;
                end

                STAGE_DONE: begin
                    stage_done      <= 1;
                    stage_idx       <= stage_idx + 1;
                    butterfly_count <= 0;
                end

                DONE: begin
                    done <= 1;
                    en   <= 0;
                end
            endcase
        end
    end

endmodule