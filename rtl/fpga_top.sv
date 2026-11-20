`timescale 1ns/1ps

module fpga_top (
    input  logic       sys_clk,
    input  logic       sys_rst_n,
    input  logic       btn_start,
    output logic [7:0] led,
    output logic       uart_txd
);

    // 1. Clock Heartbeat
    logic [25:0] heartbeat_cnt;
    always_ff @(posedge sys_clk) begin
        heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
    assign led[0] = heartbeat_cnt[24];

    // 2. AXI Interconnect Signals
    logic [63:0] s_awaddr, s_araddr, m_awaddr, m_araddr;
    logic [7:0]  s_awlen, s_arlen, m_awlen, m_arlen;
    logic [2:0]  s_awsize, s_arsize, m_awsize, m_arsize;
    logic [1:0]  s_awburst, s_arburst, m_awburst, m_arburst;
    logic [11:0] s_awid, s_arid, m_awid, m_arid, s_bid, m_bid, s_rid, m_rid;
    logic        s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
    logic        s_arvalid, s_arready, s_rvalid, s_rready, s_rlast, s_wlast;
    logic        m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
    logic        m_arvalid, m_arready, m_rvalid, m_rready, m_rlast, m_wlast;
    logic [31:0] s_wdata, s_rdata;
    logic [63:0] m_wdata, m_rdata;
    logic [3:0]  s_wstrb;
    logic [7:0]  m_wstrb;
    logic [1:0]  s_bresp, s_rresp, m_bresp, m_rresp;
    logic        irq_out;

    // 3. Clean Synchronous BRAM Memory
    (* ram_style = "block" *)
    logic [63:0] local_mem [0:1023];
    initial begin
        for (int i = 0; i < 1024; i++) local_mem[i] = '0;
        // Task 0: Serve Wine (Words 0..3)
        local_mem[0]  = 64'h4000_4000_4000_4000;
        local_mem[1]  = 64'h4000_4000_4000_4000;
        local_mem[2]  = 64'h4000_4000_4000_4000;
        local_mem[3]  = 64'h4000_4000_4000_4000;
        // Obj0: Wine Glass (Words 64..67)
        local_mem[64] = 64'h4000_4000_4000_4000;
        local_mem[65] = 64'h4000_4000_4000_4000;
        local_mem[66] = 64'h4000_4000_4000_4000;
        local_mem[67] = 64'h4000_4000_4000_4000;
        // Obj1: Knife (Words 68..71)
        local_mem[68] = 64'h2800_2800_2800_2800;
        local_mem[69] = 64'h2800_2800_2800_2800;
        local_mem[70] = 64'h2800_2800_2800_2800;
        local_mem[71] = 64'h2800_2800_2800_2800;
        // Priors
        local_mem[80] = 64'h0000_0000_6000_E000;
        local_mem[81] = 64'h0000_0000_4000_8000;
    end

    // Read Responder
    logic [15:0] drd_cnt = '0;
    logic [9:0]  raddr_lat = '0;
    always_ff @(posedge sys_clk) begin
        m_arready <= 1'b1;
        if (m_arvalid && m_arready) begin
            drd_cnt   <= {8'b0, m_arlen};
            raddr_lat <= m_araddr[12:3];
            m_rdata   <= local_mem[m_araddr[12:3]];
            m_rvalid  <= 1'b1;
            m_rlast   <= (m_arlen == 8'h0);
        end else if (m_rvalid && m_rready) begin
            if (drd_cnt == 0) begin
                m_rvalid <= 1'b0;
                m_rlast  <= 1'b0;
            end else begin
                drd_cnt   <= drd_cnt - 1'b1;
                raddr_lat <= raddr_lat + 1'b1;
                m_rdata   <= local_mem[raddr_lat + 1'b1];
                m_rlast   <= (drd_cnt == 16'd1);
            end
        end
    end

    // Result Registers
    logic [4:0]  winner_id = '0;
    logic        is_busy = '0, is_done = '0, any_accepted = '0;
    logic [15:0] winner_score = '0;

    // Write Responder (Direct Result Latch)
    logic [9:0] waddr_lat = '0;
    always_ff @(posedge sys_clk) begin
        m_awready <= 1'b1;
        m_wready  <= 1'b1;

        if (m_awvalid && m_awready)
            waddr_lat <= m_awaddr[12:3];

        if (m_wvalid && m_wready) begin
            local_mem[waddr_lat] <= m_wdata;
            waddr_lat            <= waddr_lat + 1'b1;

            if (waddr_lat == 10'd512) any_accepted <= m_wdata[0];
            if (waddr_lat == 10'd513) begin
                winner_id    <= m_wdata[44:40];
                winner_score <= m_wdata[39:24]; // 0x5332!
            end
        end

        m_bvalid <= (m_wvalid && m_wlast && m_wready);
    end

    // 4. Accelerator Instance
    accelerator_top #(
        .EMB_DIM(16), .MAX_OBJECTS(8), .TOPK_MAX(4), .SCORE_W(16), .ADDR_W(14)
    ) u_accel (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .s_awaddr(s_awaddr), .s_awlen(s_awlen), .s_awsize(s_awsize), .s_awburst(s_awburst),
        .s_awid(s_awid), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arlen(s_arlen), .s_arsize(s_arsize), .s_arburst(s_arburst),
        .s_arid(s_arid), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rlast(s_rlast), .s_rid(s_rid),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst),
        .m_awid(m_awid), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst),
        .m_arid(m_arid), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast), .m_rid(m_rid),
        .m_rvalid(m_rvalid), .m_rready(m_rready),
        .irq_out(irq_out), .perf_cycle_count(), .perf_compute_cycles()
    );

    // ── 5. Master Sequencer ─────────────────────────────────────────────
    typedef enum logic [2:0] { M_IDLE, M_ADDR_DATA, M_WAIT_BVALID, M_WAIT_IRQ, M_DONE } m_state_t;
    m_state_t m_state = M_IDLE;

    logic [2:0] cfg_idx = '0;
    logic       vio_start;
    logic       aw_done_r = '0, w_done_r = '0;

    vio_0 u_vio (
        .clk(sys_clk),
        .probe_in0(is_done),
        .probe_in1(winner_id[3:0]),
        .probe_in2(winner_score),
        .probe_in3(any_accepted),
        .probe_out0(vio_start)
    );

    uart_tx #(.CLK_FREQ(50_000_000), .BAUD_RATE(115_200)) u_uart (
        .clk(sys_clk), .rst_n(sys_rst_n),
        .tx_start(is_done),
        .tx_data(8'h30 + {4'b0, winner_id[3:0]}),
        .tx_busy(),
        .uart_txd(uart_txd)
    );

    logic btn_start_prev = '0;
    wire  trigger = (btn_start || vio_start);

    always_ff @(posedge sys_clk) begin
        btn_start_prev <= trigger;

        case (m_state)
            M_IDLE: begin
                s_awvalid <= 1'b0;
                s_wvalid  <= 1'b0;
                s_bready  <= 1'b1;
                s_wstrb   <= 4'hF;
                s_awlen   <= '0;
                s_awsize  <= 3'b010;
                s_awburst <= 2'b01;
                cfg_idx   <= '0;
                is_busy   <= 1'b0;
                aw_done_r <= 1'b0;
                w_done_r  <= 1'b0;
                if (trigger && !btn_start_prev) begin
                    is_busy <= 1'b1;
                    is_done <= 1'b0;
                    m_state <= M_ADDR_DATA;
                end
            end

            M_ADDR_DATA: begin
                case (cfg_idx)
                    3'd0: begin s_awaddr <= 64'h2006_0010; s_wdata <= 32'h0000_0000; end // TASK_AL (0x0)
                    3'd1: begin s_awaddr <= 64'h2006_0018; s_wdata <= 32'h0000_0200; end // OBJ_AL (0x200)
                    3'd2: begin s_awaddr <= 64'h2006_0020; s_wdata <= 32'h0000_1000; end // RES_AL (0x1000)
                    3'd3: begin s_awaddr <= 64'h2006_0028; s_wdata <= 32'd4; end         // NUM_OBJECTS = 4
                    3'd4: begin s_awaddr <= 64'h2006_0000; s_wdata <= 32'd1; end         // Start!
                    default: ;
                endcase

                if (!aw_done_r) s_awvalid <= 1'b1;
                if (!w_done_r)  s_wvalid  <= 1'b1;

                if (s_awvalid && s_awready) begin
                    s_awvalid <= 1'b0;
                    aw_done_r <= 1'b1;
                end
                if (s_wvalid && s_wready) begin
                    s_wvalid <= 1'b0;
                    w_done_r <= 1'b1;
                end

                if ((aw_done_r || (s_awvalid && s_awready)) && 
                    (w_done_r  || (s_wvalid  && s_wready))) begin
                    m_state <= M_WAIT_BVALID;
                end
            end

            M_WAIT_BVALID: begin
                aw_done_r <= 1'b0;
                w_done_r  <= 1'b0;
                if (s_bvalid) begin
                    if (cfg_idx == 3'd4) begin
                        m_state <= M_WAIT_IRQ;
                    end else begin
                        cfg_idx <= cfg_idx + 1'b1;
                        m_state <= M_ADDR_DATA;
                    end
                end
            end

            M_WAIT_IRQ: begin
                if (irq_out) begin
                    is_busy <= 1'b0;
                    is_done <= 1'b1;
                    m_state <= M_DONE;
                end
            end

            M_DONE: begin
                if (!trigger) m_state <= M_IDLE;
            end

            default: m_state <= M_IDLE;
        endcase
    end

    // 6. Physical LEDs
    assign led[1]   = is_busy;
    assign led[2]   = is_done;
    assign led[3]   = any_accepted;
    assign led[7:4] = winner_id[3:0];

endmodule