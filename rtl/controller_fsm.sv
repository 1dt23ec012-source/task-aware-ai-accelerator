`timescale 1ns/1ps

module controller_fsm #(
    parameter int AXI_AW     = 64,
    parameter int AXI_DW     = 64,
    parameter int EMB_DIM    = 384,
    parameter int MAX_OBJECTS = 32,
    parameter int SCORE_W    = 16,
    parameter int TOPK_MAX   = 8
)(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               ctrl_start,
    input  logic [5:0]         ctrl_num_objects,
    input  logic [AXI_AW-1:0]  ctrl_task_addr,
    input  logic [AXI_AW-1:0]  ctrl_obj_addr,
    input  logic [AXI_AW-1:0]  ctrl_result_addr,
    output logic               fsm_busy,
    output logic               fsm_done,
    output logic               fsm_error,
    output logic               mst_rd_start,
    output logic [AXI_AW-1:0]  mst_rd_addr,
    output logic [15:0]        mst_rd_len,
    input  logic               mst_rd_done,
    output logic               mst_wr_start,
    output logic [AXI_AW-1:0]  mst_wr_addr,
    output logic [15:0]        mst_wr_len,
    input  logic               mst_wr_done,
    input  logic               aff_valid,
    input  logic               ctx_valid,
    input  logic               gate_valid,
    input  logic               topk_valid,
    output logic               compute_start,
    output logic               accel_done_pulse
);
    localparam int TASK_WORDS   = (EMB_DIM * 2 + 7) / 8;
    localparam int RESULT_WORDS = 1 + TOPK_MAX;

    typedef enum logic [3:0] {
        S_IDLE      = 4'd0,
        S_RD_TASK   = 4'd1,
        S_WAIT_TASK = 4'd2,
        S_RD_OBJS   = 4'd3,
        S_WAIT_OBJS = 4'd4,
        S_COMPUTE   = 4'd5,
        S_WRITE     = 4'd6,
        S_WAIT_WR   = 4'd7,
        S_DONE      = 4'd8
    } state_t;
    state_t state;

    logic [15:0] obj_words, prior_words, total_obj_words;
    always_comb begin
        obj_words       = 16'((ctrl_num_objects * EMB_DIM * 2 + 7) / 8);
        prior_words     = 16'((ctrl_num_objects * 6 + 7) / 8);
        total_obj_words = obj_words + prior_words;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            fsm_busy         <= 1'b0;
            fsm_done         <= 1'b0;
            fsm_error        <= 1'b0;
            mst_rd_start     <= 1'b0;
            mst_wr_start     <= 1'b0;
            mst_rd_addr      <= '0;
            mst_rd_len       <= '0;
            mst_wr_addr      <= '0;
            mst_wr_len       <= '0;
            compute_start    <= 1'b0;
            accel_done_pulse <= 1'b0;
        end else begin
            mst_rd_start     <= 1'b0;
            mst_wr_start     <= 1'b0;
            compute_start    <= 1'b0;
            accel_done_pulse <= 1'b0;
            fsm_done         <= 1'b0;

            case (state)
                S_IDLE: begin
                    fsm_busy <= 1'b0;
                    if (ctrl_start) begin 
                        fsm_busy <= 1'b1; 
                        state    <= S_RD_TASK; 
                    end
                end

                S_RD_TASK: begin
                    mst_rd_start <= 1'b1;
                    mst_rd_addr  <= ctrl_task_addr;
                    mst_rd_len   <= 16'(TASK_WORDS);
                    state        <= S_WAIT_TASK;
                end

                S_WAIT_TASK: begin
                    if (mst_rd_done) state <= S_RD_OBJS;
                end

                S_RD_OBJS: begin
                    mst_rd_start <= 1'b1;
                    mst_rd_addr  <= ctrl_obj_addr;
                    mst_rd_len   <= total_obj_words;
                    state        <= S_WAIT_OBJS;
                end

                S_WAIT_OBJS: begin
                    if (mst_rd_done) begin
                        compute_start <= 1'b1; // Trigger scoring safely after DDR load
                        state         <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    if (topk_valid) state <= S_WRITE;
                end

                S_WRITE: begin
                    mst_wr_start <= 1'b1;
                    mst_wr_addr  <= ctrl_result_addr;
                    mst_wr_len   <= 16'(RESULT_WORDS);
                    state        <= S_WAIT_WR;
                end

                S_WAIT_WR: begin
                    if (mst_wr_done) state <= S_DONE;
                end

                S_DONE: begin
                    fsm_busy         <= 1'b0;
                    fsm_done         <= 1'b1;
                    accel_done_pulse <= 1'b1;
                    state            <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

