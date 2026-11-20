`timescale 1ns/1ps

module input_buffer #(
    parameter int AXI_DW      = 64,
    parameter int EMB_DIM     = 384,
    parameter int MAX_OBJECTS = 32,
    parameter int SCORE_W     = 16,
    parameter int BRAM_DEPTH  = 3200,
    parameter int ADDR_W      = 14
)(
    input  logic               clk,
    input  logic               rst_n,

    // Port A: Write (AXI master -> buffer, 12-bit word address)
    input  logic               wr_en,
    input  logic [11:0]        wr_addr,
    input  logic [AXI_DW-1:0]  wr_data,

    // Port B: Read (scoring engine <- buffer, 14-bit element address)
    input  logic [ADDR_W-1:0]  rd_addr,
    output logic [SCORE_W-1:0] rd_data,
    output logic               rd_valid
);

    (* ram_style = "block" *)
    logic [AXI_DW-1:0] mem [0:BRAM_DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    logic [AXI_DW-1:0] rd_word_r;
    logic [1:0]        rd_sub_r;
    logic              rd_valid_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_valid_r <= 1'b0;
            rd_word_r  <= '0;
            rd_sub_r   <= '0;
        end else begin
            rd_word_r  <= mem[rd_addr[ADDR_W-1:2]];
            rd_sub_r   <= rd_addr[1:0];
            rd_valid_r <= 1'b1;
        end
    end

    always_comb begin
        case (rd_sub_r)
            2'd0: rd_data = rd_word_r[15:0];
            2'd1: rd_data = rd_word_r[31:16];
            2'd2: rd_data = rd_word_r[47:32];
            2'd3: rd_data = rd_word_r[63:48];
        endcase
    end

    assign rd_valid = rd_valid_r;
endmodule
