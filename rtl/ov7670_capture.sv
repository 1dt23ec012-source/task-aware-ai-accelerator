// =============================================================================
// ov7670_capture.sv — Pixel Capture & Frame Buffer Bridge
// Samples OV7670 8-bit bus, packages into 16-bit RGB565, and writes to memory
// =============================================================================
`timescale 1ns/1ps

module ov7670_capture (
    input  logic        pclk,        // Pixel clock from camera sensor
    input  logic        rst_n,
    input  logic        vsync,       // Vertical sync (Frame start)
    input  logic        href,        // Horizontal reference (Row active)
    input  logic [7:0]  d,           // 8-bit camera data bus
    output logic [9:0]  wr_addr,     // Memory write address
    output logic [63:0] wr_data,     // 64-bit packed word
    output logic        wr_en        // Memory write enable
);

    logic [15:0] pixel_reg;
    logic [63:0] word_reg;
    logic [1:0]  word_cnt;
    logic        byte_toggle;
    logic [9:0]  addr_cnt;

    assign wr_addr = addr_cnt;
    assign wr_data = word_reg;

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_reg   <= '0;
            word_reg    <= '0;
            word_cnt    <= '0;
            byte_toggle <= 1'b0;
            addr_cnt    <= 10'd64; // Streams into object memory space (Word 64)!
            wr_en       <= 1'b0;
        end else if (vsync) begin
            addr_cnt    <= 10'd64; // Reset to start of candidate object memory on new frame
            byte_toggle <= 1'b0;
            word_cnt    <= '0;
            wr_en       <= 1'b0;
        end else if (href) begin
            wr_en <= 1'b0;
            if (!byte_toggle) begin
                pixel_reg[15:8] <= d; // High byte
                byte_toggle     <= 1'b1;
            end else begin
                pixel_reg[7:0]  <= d; // Low byte
                byte_toggle     <= 1'b0;
                
                // Pack into 64-bit memory word
                word_reg <= {word_reg[47:0], pixel_reg[15:8], d};
                word_cnt <= word_cnt + 1'b1;

                if (word_cnt == 2'd3) begin
                    wr_en    <= 1'b1; // Full 64-bit word assembled!
                    addr_cnt <= (addr_cnt == 10'd95) ? 10'd64 : addr_cnt + 1'b1;
                end
            end
        end else begin
            wr_en       <= 1'b0;
            byte_toggle <= 1'b0;
        end
    end

endmodule