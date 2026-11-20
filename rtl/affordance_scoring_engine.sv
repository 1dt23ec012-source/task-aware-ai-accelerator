`timescale 1ns/1ps

module affordance_scoring_engine #(
    parameter int EMB_DIM     = 384,
    parameter int MAX_OBJECTS = 32,
    parameter int SCORE_W     = 16,
    parameter int ACCUM_W     = 32,
    parameter int ADDR_W      = 14,
    parameter int MAC_MODE    = 8
)(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [5:0]         num_objects,
    output logic [ADDR_W-1:0]  ibuf_rd_addr,
    input  logic [SCORE_W-1:0] ibuf_rd_data,
    input  logic               ibuf_rd_valid,
    output logic [MAX_OBJECTS-1:0][SCORE_W-1:0] aff_scores,
    output logic               done
);
    localparam logic [7:0] ALPHA = 8'd128;
    localparam logic [7:0] BETA  = 8'd64;
    localparam logic [7:0] GAMMA = 8'd64;

    localparam logic [ADDR_W-1:0] TASK_BASE  = '0;
    localparam logic [ADDR_W-1:0] OBJ_BASE   = ADDR_W'(EMB_DIM);

    typedef enum logic [3:0] {
        S_IDLE        = 4'd0,
        S_LOAD_TASK   = 4'd1,
        S_START_OBJ   = 4'd2,
        S_DOT_PROD    = 4'd3,
        S_FLUSH       = 4'd4,
        S_READ_PRIORS = 4'd5,
        S_COMBINE     = 4'd6,
        S_NEXT_OBJ    = 4'd7,
        S_DONE        = 4'd8
    } state_t;
    state_t state;

    (* ram_style = "block" *)
    logic [SCORE_W-1:0] task_emb [0:EMB_DIM-1];

    logic [ACCUM_W-1:0]        accum;
    logic [ADDR_W-1:0]         elem_cnt;
    logic [5:0]                obj_idx;
    logic signed [SCORE_W-1:0] dsp_a_r, dsp_b_r;
    logic signed [ACCUM_W-1:0] dsp_p;
    logic [SCORE_W-1:0]        phys_score_r, prior_score_r, sem_sim_r;
    logic [1:0]                prior_phase;
    logic [31:0]               combined_r;

    // Dynamically calculate base addresses based on num_objects and 4-element word alignment
    logic [ADDR_W-1:0] obj_base_addr;
    logic [ADDR_W-1:0] prior_base_addr;
    always_comb begin
        obj_base_addr   = OBJ_BASE + ADDR_W'(obj_idx) * ADDR_W'(EMB_DIM);
        prior_base_addr = OBJ_BASE + ADDR_W'(num_objects) * ADDR_W'(EMB_DIM) + ADDR_W'(obj_idx) * ADDR_W'(4);
    end

    // DSP Pipeline
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            dsp_a_r <= '0; dsp_b_r <= '0; dsp_p <= '0;
        end else begin
            dsp_a_r <= $signed(task_emb[elem_cnt[8:0]]);
            dsp_b_r <= $signed(ibuf_rd_data);
            dsp_p   <= $signed(dsp_a_r) * $signed(dsp_b_r);
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            done         <= 1'b0;
            elem_cnt     <= '0;
            obj_idx      <= '0;
            accum        <= '0;
            ibuf_rd_addr <= '0;
            aff_scores   <= '0;
            phys_score_r <= '0;
            prior_score_r<= '0;
            prior_phase  <= '0;
            sem_sim_r    <= '0;
            combined_r   <= '0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        elem_cnt     <= '0;
                        ibuf_rd_addr <= TASK_BASE;
                        state        <= S_LOAD_TASK;
                    end
                end

                S_LOAD_TASK: begin
                    if (ibuf_rd_valid) begin
                        task_emb[elem_cnt[8:0]] <= ibuf_rd_data;
                        elem_cnt     <= elem_cnt + 1'b1;
                        ibuf_rd_addr <= TASK_BASE + elem_cnt + 1'b1;
                        if (elem_cnt == ADDR_W'(EMB_DIM - 1)) begin
                            obj_idx  <= '0;
                            elem_cnt <= '0;
                            state    <= S_START_OBJ;
                        end
                    end
                end

                S_START_OBJ: begin
                    accum        <= '0;
                    elem_cnt     <= '0;
                    ibuf_rd_addr <= obj_base_addr;
                    state        <= S_DOT_PROD;
                end

                S_DOT_PROD: begin
                    if (ibuf_rd_valid) begin
                        if (elem_cnt >= ADDR_W'(2)) begin
                            if (accum + ACCUM_W'(dsp_p) > 32'h3FFF_FFFF)
                                accum <= 32'h3FFF_FFFF;
                            else
                                accum <= accum + ACCUM_W'(dsp_p);
                        end
                        elem_cnt     <= elem_cnt + 1'b1;
                        ibuf_rd_addr <= obj_base_addr + elem_cnt + 1'b1;
                        if (elem_cnt == ADDR_W'(EMB_DIM - 1))
                            state <= S_FLUSH;
                    end
                end

                S_FLUSH: begin
                    if (accum + ACCUM_W'(dsp_p) > 32'h3FFF_FFFF)
                        accum <= 32'h3FFF_FFFF;
                    else
                        accum <= accum + ACCUM_W'(dsp_p);

                    elem_cnt <= elem_cnt + 1'b1;
                    if (elem_cnt == ADDR_W'(EMB_DIM + 2)) begin
                        sem_sim_r    <= (accum > 32'h3FFF_FFFF) ? 16'h7FFF : accum[29:14];
                        prior_phase  <= '0;
                        ibuf_rd_addr <= prior_base_addr;
                        state        <= S_READ_PRIORS;
                    end
                end

                S_READ_PRIORS: begin
                    if (ibuf_rd_valid) begin
                        case (prior_phase)
                            2'd1: prior_score_r <= ibuf_rd_data;
                            2'd2: phys_score_r  <= ibuf_rd_data;
                            default: ;
                        endcase
                        ibuf_rd_addr <= prior_base_addr + ADDR_W'(prior_phase) + 1'b1;
                        prior_phase  <= prior_phase + 1'b1;
                        if (prior_phase == 2'd2) state <= S_COMBINE;
                    end
                end

                S_COMBINE: begin
                    combined_r <= ({24'b0, ALPHA} * {16'b0, sem_sim_r}
                                 + {24'b0, BETA}  * {16'b0, phys_score_r}
                                 + {24'b0, GAMMA} * {16'b0, {2'b00, prior_score_r[13:0]}}) >> 8;
                    state <= S_NEXT_OBJ;
                end

                S_NEXT_OBJ: begin
                    // Preserve tag in [15:14]
                    aff_scores[obj_idx] <= {prior_score_r[15:14],
                                           (combined_r > 32'h3FFF) ? 14'h3FFF : combined_r[13:0]};
                    if (obj_idx == num_objects - 1)
                        state <= S_DONE;
                    else begin
                        obj_idx <= obj_idx + 1'b1;
                        state   <= S_START_OBJ;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule