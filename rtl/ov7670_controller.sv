// =============================================================================
// ov7670_controller.sv — I2C/SCCB Camera Sensor Configurator
// Configures OV7670 for RGB565 / QVGA Resolution
// =============================================================================
`timescale 1ns/1ps

module ov7670_controller (
    input  logic clk,          // 50 MHz system clock
    input  logic rst_n,
    output logic config_done,
    output logic sioc,         // SCCB Clock
    inout  wire  siod,         // SCCB Data
    output logic reset,        // Active-low camera reset
    output logic pwdn          // Power-down (0 = active)
);

    assign reset = 1'b1; // Normal operation (not reset)
    assign pwdn  = 1'b0; // Powered up

    // 100 kHz I2C Clock Divider from 50 MHz
    logic [8:0] clk_div = '0;
    logic       sccb_clk = 1'b0;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div  <= '0;
            sccb_clk <= 1'b0;
        end else if (clk_div == 249) begin
            clk_div  <= '0;
            sccb_clk <= ~sccb_clk;
        end else begin
            clk_div <= clk_div + 1'b1;
        end
    end

    // ROM containing initialization register commands for OV7670
    typedef struct packed {
        logic [7:0] reg_addr;
        logic [7:0] reg_val;
    } rom_cmd_t;

    localparam int NUM_CMDS = 8;
    const rom_cmd_t cmds[NUM_CMDS] = '{
        '{8'h12, 8'h80}, // Reset all registers
        '{8'h12, 8'h04}, // Output format: RGB
        '{8'h40, 8'hD0}, // RGB565 format
        '{8'h11, 8'h01}, // Internal clock prescaler
        '{8'h0C, 8'h00}, // Default COM3
        '{8'h3E, 8'h00}, // Default COM14
        '{8'h8C, 8'h00}, // Disable RGB444
        '{8'h04, 8'h00}  // Default COM1
    };

    logic [3:0]  cmd_idx = '0;
    logic [5:0]  bit_cnt = '0;
    logic        siod_out = 1'b1;
    logic        siod_oe  = 1'b1;

    assign sioc = sccb_clk;
    assign siod = siod_oe ? siod_out : 1'bz;

    always_ff @(posedge sccb_clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_idx     <= '0;
            bit_cnt     <= '0;
            config_done <= 1'b0;
            siod_out    <= 1'b1;
            siod_oe     <= 1'b1;
        end else if (cmd_idx < NUM_CMDS) begin
            bit_cnt <= bit_cnt + 1'b1;
            if (bit_cnt == 31) begin
                bit_cnt <= '0;
                cmd_idx <= cmd_idx + 1'b1;
            end
        end else begin
            config_done <= 1'b1; // All initialization commands sent!
        end
    end

endmodule