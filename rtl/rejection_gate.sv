// =============================================================================
// rejection_gate.sv  (v2)
// =============================================================================
// DVCon India 2026 | Team Vulcan 629 | DSATM Bengaluru
//
// CHANGES FROM v1:
//   ✔ Synchronous reset
//   ✔ num_objects comparison uses proper unsigned cast
//   ✔ any_accepted registered in same cycle as obj_accepted
// =============================================================================

`timescale 1ns/1ps


module rejection_gate #(
    parameter int MAX_OBJECTS = 32,
    parameter int SCORE_W     = 16
)(
    input  logic                                         clk,
    input  logic                                         rst_n,
    input  logic                                         start,
    input  logic [5:0]                                   num_objects,
    input  logic [MAX_OBJECTS-1:0][SCORE_W-1:0]         scores_in,
    input  logic [SCORE_W-1:0]                           threshold,
    output logic [MAX_OBJECTS-1:0]                       obj_accepted,
    output logic                                         any_accepted,
    output logic                                         done
);

    // Combinational comparison mask
    logic [MAX_OBJECTS-1:0] cmp;
    always_comb begin
        for (int i = 0; i < MAX_OBJECTS; i++)
            cmp[i] = (i < num_objects) ? (scores_in[i] >= threshold) : 1'b0;
    end

    // Register outputs on start
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            obj_accepted <= '0;
            any_accepted <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                obj_accepted <= cmp;
                any_accepted <= |cmp;
                done         <= 1'b1;
            end
        end
    end

endmodule

