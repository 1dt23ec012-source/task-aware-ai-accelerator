// output_buffer.sv (v2 fixed)
// DVCon India 2026 | Team Vulcan 629 | DSATM Bengaluru
// FIX: for-loop comparison against non-constant topk_count replaced
//      with parameter-bounded loop + runtime mask
`timescale 1ns/1ps


module output_buffer #(
    parameter int AXI_DW     = 64,
    parameter int MAX_OBJECTS = 32,
    parameter int TOPK_MAX    = 8,
    parameter int SCORE_W     = 16
)(
    input  logic                                clk,
    input  logic                                rst_n,
    input  logic                                load,
    input  logic                                gate_accepted,
    input  logic [TOPK_MAX-1:0][4:0]           topk_ids,
    input  logic [TOPK_MAX-1:0][SCORE_W-1:0]   topk_scores,
    input  logic [3:0]                          topk_count,
    input  logic [SCORE_W-1:0]                  threshold_used,
    input  logic [9:0]                          rd_addr,
    output logic [AXI_DW-1:0]                  rd_data,
    output logic [9:0]                          size_words
);
    localparam int    BUF_DEPTH = TOPK_MAX + 1;
    localparam [31:0] MAGIC     = 32'h44564330;


    logic [AXI_DW-1:0] buf_mem [0:BUF_DEPTH-1];

    assign size_words = 10'(BUF_DEPTH);

    // Pack on load — loop bound is TOPK_MAX (parameter, constant)
    // Runtime check k < topk_count done via ternary inside loop
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < BUF_DEPTH; i++)
                buf_mem[i] <= '0;
        end else if (load) begin
            // Word 0: status
            buf_mem[0] <= {
                MAGIC,
                threshold_used,
                {4'b0, topk_count},
                {7'b0, gate_accepted}
            };
            // Words 1..TOPK_MAX — loop over constant TOPK_MAX
            for (int k = 0; k < TOPK_MAX; k++) begin
                // Use ternary with constant-bounded index k
                buf_mem[k+1] <= (k < int'(topk_count))
                    ? {16'h0000,
                       {3'b0, topk_ids[k]},
                       topk_scores[k],
                       24'h000000}
                    : {16'h0000, 8'hFF, 16'h0000, 24'h000000};
            end
        end
    end

    // Synchronous read
    always_ff @(posedge clk) begin
        if (!rst_n)
            rd_data <= '0;
        else
            rd_data <= (rd_addr < 10'(BUF_DEPTH)) ? buf_mem[rd_addr] : '0;
    end

endmodule

