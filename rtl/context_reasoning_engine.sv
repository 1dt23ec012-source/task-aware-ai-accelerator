// =============================================================================
// context_reasoning_engine.sv  (v2)
// =============================================================================
// DVCon India 2026 | Team Vulcan 629 | DSATM Bengaluru
//
// CHANGES FROM v1:
//   ✔ Synchronous reset
//   ✔ Tag decode moved fully into combinational always_comb block
//   ✔ Output registered cleanly on start rising edge
//   ✔ Saturation arithmetic uses explicit intermediate wire
// =============================================================================

`timescale 1ns/1ps


module context_reasoning_engine #(
    parameter int MAX_OBJECTS = 32,
    parameter int SCORE_W     = 16
)(
    input  logic                                         clk,
    input  logic                                         rst_n,
    input  logic                                         start,
    input  logic [5:0]                                   num_objects,
    input  logic [MAX_OBJECTS-1:0][SCORE_W-1:0]         aff_scores_in,
    output logic [MAX_OBJECTS-1:0][SCORE_W-1:0]         ctx_scores_out,
    output logic                                         done
);

    // Q1.15 constants
    // BONUS  = +0.15 × 32768 = 4915
    // PENALTY_MULT = 0.05 × 32768 = 1638 (Q0.15)
    localparam logic [SCORE_W-1:0] BONUS        = 16'd4915;
    localparam logic [SCORE_W-1:0] PENALTY_MULT = 16'd1638;

    // Tag encoding (upper 2 bits of score word)
    localparam logic [1:0] TAG_NEUTRAL    = 2'b00;
    localparam logic [1:0] TAG_PREFERRED  = 2'b11;
    localparam logic [1:0] TAG_PENALISED  = 2'b10;
    localparam logic [1:0] TAG_NEVER_TOOL = 2'b01;

    // ── Combinational adjustment per object ───────────────────────
    logic [MAX_OBJECTS-1:0][SCORE_W-1:0] adj;

    always_comb begin
        for (int i = 0; i < MAX_OBJECTS; i++) begin
            automatic logic [1:0]          tag;
            automatic logic [SCORE_W-1:0]  raw;
            automatic logic [31:0]         pen;
            automatic logic [SCORE_W-1:0]  bon;

            if (i >= num_objects) begin
                adj[i] = '0;
            end else begin
                tag = aff_scores_in[i][SCORE_W-1 -: 2];
                raw = {2'b00, aff_scores_in[i][SCORE_W-3:0]};
                pen = (raw * PENALTY_MULT) >> 15;
                bon = (raw + BONUS > {1'b0, {(SCORE_W-1){1'b1}}})
                      ? {1'b0, {(SCORE_W-1){1'b1}}}
                      : raw + BONUS;

                case (tag)
                    TAG_PREFERRED:  adj[i] = bon;
                    TAG_PENALISED:  adj[i] = pen[SCORE_W-1:0];
                    TAG_NEVER_TOOL: adj[i] = '0;
                    default:        adj[i] = raw;
                endcase
            end
        end
    end

    // ── Register on start ─────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ctx_scores_out <= '0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                ctx_scores_out <= adj;
                done           <= 1'b1;
            end
        end
    end

endmodule

