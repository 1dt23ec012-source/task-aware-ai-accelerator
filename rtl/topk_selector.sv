// =============================================================================
// topk_selector.sv  (v4 Fully Pipelined Tournament Tree - Timing Closure)
// =============================================================================
// DVCon India 2026 | Team Vulcan 629 | DSATM Bengaluru
// - Local registration of num_objects (eliminates 15ns cross-chip net delay)
// - Registered tournament champion in S_SCAN for clean timing closure at 50-150 MHz
// =============================================================================

`timescale 1ns/1ps

module topk_selector #(
    parameter int MAX_OBJECTS = 32,
    parameter int TOPK_MAX    = 8,
    parameter int SCORE_W     = 16
)(
    input  logic                                 clk,
    input  logic                                 rst_n,
    input  logic                                 start,
    input  logic [5:0]                           num_objects,
    input  logic [3:0]                           topk_k,
    input  logic [MAX_OBJECTS-1:0][SCORE_W-1:0]  scores_in,
    input  logic [MAX_OBJECTS-1:0]               accepted_mask,
    output logic [TOPK_MAX-1:0][4:0]             topk_ids,
    output logic [TOPK_MAX-1:0][SCORE_W-1:0]     topk_scores,
    output logic [3:0]                           topk_count,
    output logic                                 done
);

    typedef enum logic [1:0] {
        S_IDLE,
        S_SCAN,     // Tree reduction & winner registration
        S_RECORD,   // Slot write & used_mask update
        S_DONE
    } state_t;
    state_t state;

    logic [3:0]             k_idx;
    logic [MAX_OBJECTS-1:0] used_mask;
    logic [5:0]             num_obj_r; // Local register cuts cross-chip wire delay

    // Candidate structure for tournament tree
    typedef struct packed {
        logic [SCORE_W-1:0] score;
        logic [4:0]         id;
        logic               valid;
    } cand_t;

    cand_t l0 [32];
    cand_t l1 [16];
    cand_t l2 [8];
    cand_t l3 [4];
    cand_t l4 [2];
    cand_t l5;
    cand_t winner_r;

    // ── Balanced Parallel Tournament Reduction Tree ───────────────────
    always_comb begin
        // Leaf filter using local registered num_obj_r
        for (int i = 0; i < 32; i++) begin
            if (i < num_obj_r && accepted_mask[i] && !used_mask[i]) begin
                l0[i].score = scores_in[i];
                l0[i].id    = 5'(i);
                l0[i].valid = 1'b1;
            end else begin
                l0[i].score = '0;
                l0[i].id    = '0;
                l0[i].valid = 1'b0;
            end
        end

        // Level 1: 32 -> 16
        for (int i = 0; i < 16; i++) begin
            if (l0[2*i].valid && l0[2*i+1].valid)
                l1[i] = (l0[2*i].score >= l0[2*i+1].score) ? l0[2*i] : l0[2*i+1];
            else if (l0[2*i].valid)
                l1[i] = l0[2*i];
            else
                l1[i] = l0[2*i+1];
        end

        // Level 2: 16 -> 8
        for (int i = 0; i < 8; i++) begin
            if (l1[2*i].valid && l1[2*i+1].valid)
                l2[i] = (l1[2*i].score >= l1[2*i+1].score) ? l1[2*i] : l1[2*i+1];
            else if (l1[2*i].valid)
                l2[i] = l1[2*i];
            else
                l2[i] = l1[2*i+1];
        end

        // Level 3: 8 -> 4
        for (int i = 0; i < 4; i++) begin
            if (l2[2*i].valid && l2[2*i+1].valid)
                l3[i] = (l2[2*i].score >= l2[2*i+1].score) ? l2[2*i] : l2[2*i+1];
            else if (l2[2*i].valid)
                l3[i] = l2[2*i];
            else
                l3[i] = l2[2*i+1];
        end

        // Level 4: 4 -> 2
        for (int i = 0; i < 2; i++) begin
            if (l3[2*i].valid && l3[2*i+1].valid)
                l4[i] = (l3[2*i].score >= l3[2*i+1].score) ? l3[2*i] : l3[2*i+1];
            else if (l3[2*i].valid)
                l4[i] = l3[2*i];
            else
                l4[i] = l3[2*i+1];
        end

        // Level 5: 2 -> 1 (Champion)
        if (l4[0].valid && l4[1].valid)
            l5 = (l4[0].score >= l4[1].score) ? l4[0] : l4[1];
        else if (l4[0].valid)
            l5 = l4[0];
        else
            l5 = l4[1];
    end

    // ── FSM ───────────────────────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            k_idx       <= '0;
            used_mask   <= '0;
            num_obj_r   <= '0;
            topk_ids    <= '0;
            topk_scores <= '0;
            topk_count  <= '0;
            winner_r    <= '0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        k_idx     <= '0;
                        used_mask <= '0;
                        num_obj_r <= num_objects; // Latch locally
                        for (int j = 0; j < TOPK_MAX; j++) begin
                            topk_ids[j]    <= '1; // 0x1F = empty
                            topk_scores[j] <= '0;
                        end
                        topk_count <= '0;
                        state      <= S_SCAN;
                    end
                end

                // Pipeline stage: latch tournament champion cleanly
                S_SCAN: begin
                    winner_r <= l5;
                    state    <= S_RECORD;
                end

                // Record stage: sample registered champion
                S_RECORD: begin
                    if (winner_r.valid && k_idx < topk_k) begin
                        topk_ids[k_idx]          <= winner_r.id;
                        topk_scores[k_idx]       <= winner_r.score;
                        topk_count               <= topk_count + 1'b1;
                        used_mask[winner_r.id]   <= 1'b1;
                        k_idx                    <= k_idx + 1'b1;

                        if (k_idx + 1 < topk_k)
                            state <= S_SCAN;
                        else
                            state <= S_DONE;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule