`timescale 1ns/1ps

module axi_master_if #(
    parameter int AXI_DW = 64,
    parameter int AXI_AW = 64,
    parameter int AXI_IW = 12
)(
    input  logic               clk,
    input  logic               rst_n,

    // Read control from FSM
    input  logic               rd_start,
    input  logic [AXI_AW-1:0]  rd_addr,
    input  logic [15:0]        rd_len,
    output logic               rd_done,

    // Write control from FSM
    input  logic               wr_start,
    input  logic [AXI_AW-1:0]  wr_addr,
    input  logic [15:0]        wr_len,
    output logic               wr_done,

    // Input buffer write port
    output logic               ibuf_wr_en,
    output logic [11:0]        ibuf_wr_addr,
    output logic [AXI_DW-1:0]  ibuf_wr_data,

    // Output buffer read port
    output logic [9:0]         obuf_rd_addr,
    input  logic [AXI_DW-1:0]  obuf_rd_data,
    input  logic [9:0]         obuf_size_words,

    // AXI4 Master Read Address Channel
    output logic [AXI_AW-1:0]  m_araddr,
    output logic [7:0]         m_arlen,
    output logic [2:0]         m_arsize,
    output logic [1:0]         m_arburst,
    output logic [AXI_IW-1:0]  m_arid,
    output logic               m_arvalid,
    input  logic               m_arready,

    // AXI4 Master Read Data Channel
    input  logic [AXI_DW-1:0]  m_rdata,
    input  logic [1:0]         m_rresp,
    input  logic               m_rlast,
    input  logic [AXI_IW-1:0]  m_rid,
    input  logic               m_rvalid,
    output logic               m_rready,

    // AXI4 Master Write Address Channel
    output logic [AXI_AW-1:0]  m_awaddr,
    output logic [7:0]         m_awlen,
    output logic [2:0]         m_awsize,
    output logic [1:0]         m_awburst,
    output logic [AXI_IW-1:0]  m_awid,
    output logic               m_awvalid,
    input  logic               m_awready,

    // AXI4 Master Write Data Channel
    output logic [AXI_DW-1:0]   m_wdata,
    output logic [AXI_DW/8-1:0] m_wstrb,
    output logic                 m_wlast,
    output logic                 m_wvalid,
    input  logic                 m_wready,

    // AXI4 Master Write Response Channel
    input  logic [AXI_IW-1:0]  m_bid,
    input  logic [1:0]          m_bresp,
    input  logic                m_bvalid,
    output logic                m_bready
);

    localparam [2:0] AXSIZE_8B    = 3'b011;
    localparam [1:0] AXBURST_INCR = 2'b01;

    // Direct wire from registered output buffer (prevents 1-cycle skew)
    assign m_wdata = obuf_rd_data;
    assign m_wstrb = '1;

    // ── READ FSM ──────────────────────────────────────────────────
    typedef enum logic [1:0] {
        RD_IDLE, RD_ADDR, RD_DATA, RD_DONE
    } rd_st_t;
    rd_st_t rd_st;

    logic [AXI_AW-1:0] rd_base;
    logic [15:0]       rd_remain, rd_issued;
    logic [11:0]       rd_ptr;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_st        <= RD_IDLE;
            rd_done      <= 1'b0;
            m_arvalid    <= 1'b0;
            m_rready     <= 1'b0;
            ibuf_wr_en   <= 1'b0;
            ibuf_wr_addr <= '0;
            rd_ptr       <= '0;
            m_araddr     <= '0;
            m_arlen      <= '0;
        end else begin
            rd_done    <= 1'b0;
            ibuf_wr_en <= 1'b0;

            case (rd_st)
                RD_IDLE: begin
                    if (rd_start) begin
                        rd_base   <= rd_addr;
                        rd_remain <= rd_len;
                        rd_issued <= '0;
                        // Reset pointer only on new task (addr == base), keep continuous for objects
                        if (rd_addr[11:0] == 12'h000)
                            rd_ptr <= '0;
                        m_araddr  <= rd_addr;
                        m_arlen   <= (rd_len > 16'd256) ? 8'd255 : 8'(rd_len - 1);
                        m_arsize  <= AXSIZE_8B;
                        m_arburst <= AXBURST_INCR;
                        m_arid    <= '0;
                        m_arvalid <= 1'b1;
                        rd_st     <= RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (m_arvalid && m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready  <= 1'b1;
                        rd_st     <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (m_rvalid && m_rready) begin
                        ibuf_wr_en   <= 1'b1;
                        ibuf_wr_addr <= rd_ptr;
                        ibuf_wr_data <= m_rdata;
                        rd_ptr       <= rd_ptr + 1'b1;
                        rd_issued    <= rd_issued + 1'b1;
                        rd_remain    <= rd_remain - 1'b1;

                        if (m_rlast) begin
                            m_rready <= 1'b0;
                            if (rd_remain == 16'd1) begin
                                rd_st <= RD_DONE;
                            end else begin
                                m_araddr  <= rd_base + {(rd_issued + 16'd1), 3'b000};
                                m_arlen   <= ((rd_remain - 16'd1) > 16'd256) ? 8'd255 : 8'(rd_remain - 16'd2);
                                m_arvalid <= 1'b1;
                                rd_st     <= RD_ADDR;
                            end
                        end
                    end
                end

                RD_DONE: begin
                    rd_done <= 1'b1;
                    rd_st   <= RD_IDLE;
                end
            endcase
        end
    end

    // ── WRITE FSM ─────────────────────────────────────────────────
    typedef enum logic [2:0] {
        WR_IDLE, WR_ADDR, WR_DATA, WR_RESP, WR_DONE
    } wr_st_t;
    wr_st_t wr_st;

    logic [AXI_AW-1:0] wr_base;
    logic [15:0]       wr_remain, wr_sent;
    logic [9:0]        wr_ptr;
    logic [7:0]        wr_bcnt;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_st        <= WR_IDLE;
            wr_done      <= 1'b0;
            m_awvalid    <= 1'b0;
            m_wvalid     <= 1'b0;
            m_wlast      <= 1'b0;
            m_bready     <= 1'b0;
            obuf_rd_addr <= '0;
            m_awaddr     <= '0;
            m_awlen      <= '0;
            wr_bcnt      <= '0;
            wr_ptr       <= '0;
        end else begin
            wr_done <= 1'b0;

            case (wr_st)
                WR_IDLE: begin
                    if (wr_start) begin
                        wr_base      <= wr_addr;
                        wr_remain    <= wr_len;
                        wr_sent      <= '0;
                        wr_ptr       <= '0;
                        m_awaddr     <= wr_addr;
                        m_awlen      <= (wr_len > 16'd256) ? 8'd255 : 8'(wr_len - 1);
                        m_awsize     <= AXSIZE_8B;
                        m_awburst    <= AXBURST_INCR;
                        m_awid       <= '0;
                        m_awvalid    <= 1'b1;
                        wr_bcnt      <= (wr_len > 16'd256) ? 8'd255 : 8'(wr_len - 1);
                        obuf_rd_addr <= '0; // Address 0 pre-fetched
                        wr_st        <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (m_awvalid && m_awready) begin
                        m_awvalid    <= 1'b0;
                        m_wvalid     <= 1'b1;
                        m_wlast      <= (wr_bcnt == 8'd0);
                        obuf_rd_addr <= wr_ptr + 1'b1; // Pre-fetch Word 1
                        wr_st        <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (m_wvalid && m_wready) begin
                        wr_ptr    <= wr_ptr + 1'b1;
                        wr_remain <= wr_remain - 1'b1;
                        wr_sent   <= wr_sent + 1'b1;

                        if (wr_bcnt == 8'd0) begin
                            m_wvalid <= 1'b0;
                            m_wlast  <= 1'b0;
                            m_bready <= 1'b1;
                            wr_st    <= WR_RESP;
                        end else begin
                            wr_bcnt      <= wr_bcnt - 1'b1;
                            obuf_rd_addr <= wr_ptr + 2'd2; // Pre-fetch next words
                            m_wlast      <= (wr_bcnt == 8'd1);
                        end
                    end
                end

                WR_RESP: begin
                    if (m_bvalid && m_bready) begin
                        m_bready <= 1'b0;
                        wr_st    <= (wr_remain == 16'd0) ? WR_DONE : WR_ADDR;
                    end
                end

                WR_DONE: begin
                    wr_done <= 1'b1;
                    wr_st   <= WR_IDLE;
                end
            endcase
        end
    end

endmodule