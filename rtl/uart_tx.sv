`timescale 1ns/1ps

module uart_tx #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx_busy,
    output logic       uart_txd
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [1:0] { IDLE, START_BIT, DATA_BITS, STOP_BIT } state_t;
    state_t state;

    logic [15:0] clk_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  tx_data_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            uart_txd    <= 1'b1;
            tx_busy     <= 1'b0;
            clk_cnt     <= '0;
            bit_idx     <= '0;
            tx_data_reg <= '0;
        end else begin
            case (state)
                IDLE: begin
                    uart_txd <= 1'b1;
                    clk_cnt  <= '0;
                    bit_idx  <= '0;
                    if (tx_start) begin
                        tx_data_reg <= tx_data;
                        tx_busy     <= 1'b1;
                        state       <= START_BIT;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                START_BIT: begin
                    uart_txd <= 1'b0;
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= '0;
                        state   <= DATA_BITS;
                    end
                end

                DATA_BITS: begin
                    uart_txd <= tx_data_reg[bit_idx];
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= '0;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1'b1;
                        end else begin
                            bit_idx <= '0;
                            state   <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    uart_txd <= 1'b1;
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        clk_cnt <= '0;
                        tx_busy <= 1'b0;
                        state   <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule