// =============================================================================
// interrupt_controller.sv  (v2)
// =============================================================================
// DVCon India 2026 | Team Vulcan 629 | DSATM Bengaluru
// CHANGES: synchronous reset
// =============================================================================

`timescale 1ns/1ps


module interrupt_controller (
    input  logic clk,
    input  logic rst_n,        // synchronous active-low
    input  logic irq_en,
    input  logic done_pulse,
    output logic irq_out
);
    always_ff @(posedge clk) begin
        if (!rst_n)
            irq_out <= 1'b0;
        else
            irq_out <= irq_en & done_pulse;
    end
endmodule

