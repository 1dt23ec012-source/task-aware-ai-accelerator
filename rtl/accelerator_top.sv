`timescale 1ns/1ps

module accelerator_top #(
    parameter int EMB_DIM      = 384,
    parameter int MAX_OBJECTS  = 32,
    parameter int TOPK_MAX     = 8,
    parameter int SCORE_W      = 16,
    parameter int MAC_MODE     = 8,
    parameter int PERF_W       = 32,
    parameter int ADDR_W       = 14
)(
    input  logic        clk,
    input  logic        rst_n,

    // ── AXI4 Slave (CPU → Accelerator) ───────────────────────────
    input  logic [63:0] s_awaddr,  input  logic [7:0]  s_awlen,
    input  logic [2:0]  s_awsize,  input  logic [1:0]  s_awburst,
    input  logic [11:0] s_awid,    input  logic        s_awvalid,
    output logic        s_awready,
    input  logic [31:0] s_wdata,   input  logic [3:0]  s_wstrb,
    input  logic        s_wlast,   input  logic        s_wvalid,
    output logic        s_wready,
    output logic [11:0] s_bid,     output logic [1:0]  s_bresp,
    output logic        s_bvalid,  input  logic        s_bready,
    input  logic [63:0] s_araddr,  input  logic [7:0]  s_arlen,
    input  logic [2:0]  s_arsize,  input  logic [1:0]  s_arburst,
    input  logic [11:0] s_arid,    input  logic        s_arvalid,
    output logic        s_arready,
    output logic [31:0] s_rdata,   output logic [1:0]  s_rresp,
    output logic        s_rlast,   output logic [11:0] s_rid,
    output logic        s_rvalid,  input  logic        s_rready,

    // ── AXI4 Master (Accelerator → DDR3) ─────────────────────────
    output logic [63:0] m_awaddr,  output logic [7:0]  m_awlen,
    output logic [2:0]  m_awsize,  output logic [1:0]  m_awburst,
    output logic [11:0] m_awid,    output logic        m_awvalid,
    input  logic        m_awready,
    output logic [63:0] m_wdata,   output logic [7:0]  m_wstrb,
    output logic        m_wlast,   output logic        m_wvalid,
    input  logic        m_wready,
    input  logic [11:0] m_bid,     input  logic [1:0]  m_bresp,
    input  logic        m_bvalid,  output logic        m_bready,
    output logic [63:0] m_araddr,  output logic [7:0]  m_arlen,
    output logic [2:0]  m_arsize,  output logic [1:0]  m_arburst,
    output logic [11:0] m_arid,    output logic        m_arvalid,
    input  logic        m_arready,
    input  logic [63:0] m_rdata,   input  logic [1:0]  m_rresp,
    input  logic        m_rlast,   input  logic [11:0] m_rid,
    input  logic        m_rvalid,  output logic        m_rready,

    // ── Interrupt ─────────────────────────────────────────────────
    output logic              irq_out,
    output logic [PERF_W-1:0] perf_cycle_count,
    output logic [PERF_W-1:0] perf_compute_cycles
);

    logic        ctrl_start, ctrl_irq_en;
    logic [5:0]  ctrl_num_objects;
    logic [3:0]  ctrl_topk;
    logic [SCORE_W-1:0] ctrl_threshold;
    logic [63:0] ctrl_task_addr, ctrl_obj_addr, ctrl_result_addr;
    logic        fsm_busy, fsm_done, fsm_error;
    logic        mst_rd_start, mst_rd_done;
    logic [63:0] mst_rd_addr;
    logic [15:0] mst_rd_len;
    logic        mst_wr_start, mst_wr_done;
    logic [63:0] mst_wr_addr;
    logic [15:0] mst_wr_len;
    logic        compute_start;
    logic        ibuf_wr_en;
    logic [11:0] ibuf_wr_addr;
    logic [63:0] ibuf_wr_data;
    logic [ADDR_W-1:0]  ibuf_rd_addr;
    logic [SCORE_W-1:0] ibuf_rd_data;
    logic               ibuf_rd_valid;
    logic [MAX_OBJECTS-1:0][SCORE_W-1:0] aff_scores, ctx_scores;
    logic aff_valid, ctx_valid, gate_valid, topk_valid;
    logic [MAX_OBJECTS-1:0] obj_accepted;
    logic gate_any_accepted;
    logic [TOPK_MAX-1:0][4:0]         topk_ids;
    logic [TOPK_MAX-1:0][SCORE_W-1:0] topk_scores;
    logic [3:0]  topk_count;
    logic [9:0]  obuf_rd_addr;
    logic [63:0] obuf_rd_data;
    logic [9:0]  obuf_size_words;
    logic        accel_done_pulse;

    logic [PERF_W-1:0] cnt_cycle, cnt_compute, cnt_ddr_rd, cnt_ddr_wr;
    logic [PERF_W-1:0] cnt_accepted, cnt_rejected, cnt_total_obj;
    logic [PERF_W-1:0] cnt_axi_rd_beats, cnt_axi_wr_beats;
    logic [PERF_W-1:0] cnt_bytes_rd, cnt_bytes_wr, cnt_latency;

    assign perf_cycle_count    = cnt_cycle;
    assign perf_compute_cycles = cnt_compute;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cnt_cycle <= '0; cnt_compute <= '0; cnt_ddr_rd <= '0;
            cnt_ddr_wr <= '0; cnt_accepted <= '0; cnt_rejected <= '0;
            cnt_total_obj <= '0; cnt_axi_rd_beats <= '0;
            cnt_axi_wr_beats <= '0; cnt_bytes_rd <= '0;
            cnt_bytes_wr <= '0; cnt_latency <= '0;
        end else begin
            cnt_cycle <= cnt_cycle + 1'b1;
            if (fsm_busy && aff_valid)           cnt_compute      <= cnt_compute + 1'b1;
            if (mst_rd_start)                    cnt_ddr_rd       <= cnt_ddr_rd  + 1'b1;
            if (mst_wr_start)                    cnt_ddr_wr       <= cnt_ddr_wr  + 1'b1;
            if (m_rvalid && m_rready) begin
                cnt_axi_rd_beats <= cnt_axi_rd_beats + 1'b1;
                cnt_bytes_rd     <= cnt_bytes_rd + 32'd8;
            end
            if (m_wvalid && m_wready) begin
                cnt_axi_wr_beats <= cnt_axi_wr_beats + 1'b1;
                cnt_bytes_wr     <= cnt_bytes_wr + 32'd8;
            end
            if (topk_valid) begin
                cnt_accepted  <= cnt_accepted  + {28'b0, topk_count};
                cnt_rejected  <= cnt_rejected  + {26'b0, ctrl_num_objects} - {28'b0, topk_count};
                cnt_total_obj <= cnt_total_obj + {26'b0, ctrl_num_objects};
            end
            if (ctrl_start)    cnt_latency <= '0;
            else if (fsm_busy) cnt_latency <= cnt_latency + 1'b1;
        end
    end

    axi_slave_if #(.AXI_DW(32),.AXI_AW(64),.AXI_IW(12)) u_axi_slave (
        .clk(clk),.rst_n(rst_n),
        .s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),
        .s_awburst(s_awburst),.s_awid(s_awid),.s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wlast(s_wlast),
        .s_wvalid(s_wvalid),.s_wready(s_wready),
        .s_bid(s_bid),.s_bresp(s_bresp),.s_bvalid(s_bvalid),.s_bready(s_bready),
        .s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),
        .s_arburst(s_arburst),.s_arid(s_arid),.s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_rdata(s_rdata),.s_rresp(s_rresp),.s_rlast(s_rlast),
        .s_rid(s_rid),.s_rvalid(s_rvalid),.s_rready(s_rready),
        .ctrl_start(ctrl_start),.ctrl_irq_en(ctrl_irq_en),
        .ctrl_num_objects(ctrl_num_objects),
        .ctrl_topk(ctrl_topk[2:0]),.ctrl_threshold(ctrl_threshold),
        .ctrl_task_addr(ctrl_task_addr),.ctrl_obj_addr(ctrl_obj_addr),
        .ctrl_result_addr(ctrl_result_addr),
        .perf_cycle(cnt_cycle),.perf_compute(cnt_compute),
        .perf_ddr_rd(cnt_ddr_rd),.perf_ddr_wr(cnt_ddr_wr),
        .perf_accepted(cnt_accepted),.perf_rejected(cnt_rejected),
        .perf_total(cnt_total_obj),
        .perf_axi_rd_beats(cnt_axi_rd_beats),
        .perf_axi_wr_beats(cnt_axi_wr_beats),
        .perf_bytes_rd(cnt_bytes_rd),.perf_bytes_wr(cnt_bytes_wr),
        .perf_latency(cnt_latency),
        .status_busy(fsm_busy),.status_done(fsm_done),.status_error(fsm_error)
    );

    controller_fsm #(.AXI_AW(64),.AXI_DW(64),.EMB_DIM(EMB_DIM),
                     .MAX_OBJECTS(MAX_OBJECTS),.SCORE_W(SCORE_W),.TOPK_MAX(TOPK_MAX))
    u_fsm (
        .clk(clk),.rst_n(rst_n),
        .ctrl_start(ctrl_start),.ctrl_num_objects(ctrl_num_objects),
        .ctrl_task_addr(ctrl_task_addr),.ctrl_obj_addr(ctrl_obj_addr),
        .ctrl_result_addr(ctrl_result_addr),
        .fsm_busy(fsm_busy),.fsm_done(fsm_done),.fsm_error(fsm_error),
        .mst_rd_start(mst_rd_start),.mst_rd_addr(mst_rd_addr),
        .mst_rd_len(mst_rd_len),.mst_rd_done(mst_rd_done),
        .mst_wr_start(mst_wr_start),.mst_wr_addr(mst_wr_addr),
        .mst_wr_len(mst_wr_len),.mst_wr_done(mst_wr_done),
        .aff_valid(aff_valid),.ctx_valid(ctx_valid),
        .gate_valid(gate_valid),.topk_valid(topk_valid),
        .compute_start(compute_start),
        .accel_done_pulse(accel_done_pulse)
    );

    axi_master_if #(.AXI_DW(64),.AXI_AW(64),.AXI_IW(12)) u_axi_master (
        .clk(clk),.rst_n(rst_n),
        .rd_start(mst_rd_start),.rd_addr(mst_rd_addr),
        .rd_len(mst_rd_len),.rd_done(mst_rd_done),
        .wr_start(mst_wr_start),.wr_addr(mst_wr_addr),
        .wr_len(mst_wr_len),.wr_done(mst_wr_done),
        .ibuf_wr_en(ibuf_wr_en),.ibuf_wr_addr(ibuf_wr_addr),
        .ibuf_wr_data(ibuf_wr_data),
        .obuf_rd_addr(obuf_rd_addr),.obuf_rd_data(obuf_rd_data),
        .obuf_size_words(obuf_size_words),
        .m_awaddr(m_awaddr),.m_awlen(m_awlen),.m_awsize(m_awsize),
        .m_awburst(m_awburst),.m_awid(m_awid),.m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wlast(m_wlast),
        .m_wvalid(m_wvalid),.m_wready(m_wready),
        .m_bid(m_bid),.m_bresp(m_bresp),.m_bvalid(m_bvalid),.m_bready(m_bready),
        .m_araddr(m_araddr),.m_arlen(m_arlen),.m_arsize(m_arsize),
        .m_arburst(m_arburst),.m_arid(m_arid),.m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_rdata(m_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),
        .m_rid(m_rid),.m_rvalid(m_rvalid),.m_rready(m_rready)
    );

    input_buffer #(.AXI_DW(64),.EMB_DIM(EMB_DIM),
                   .MAX_OBJECTS(MAX_OBJECTS),.SCORE_W(SCORE_W),.ADDR_W(ADDR_W))
    u_ibuf (
        .clk(clk),.rst_n(rst_n),
        .wr_en(ibuf_wr_en),.wr_addr(ibuf_wr_addr),
        .wr_data(ibuf_wr_data),
        .rd_addr(ibuf_rd_addr),.rd_data(ibuf_rd_data),.rd_valid(ibuf_rd_valid)
    );

    affordance_scoring_engine #(
        .EMB_DIM(EMB_DIM),.MAX_OBJECTS(MAX_OBJECTS),
        .SCORE_W(SCORE_W),.ADDR_W(ADDR_W),.MAC_MODE(MAC_MODE))
    u_affscoring (
        .clk(clk),.rst_n(rst_n),
        .start(compute_start), // Clean pulse trigger from FSM
        .num_objects(ctrl_num_objects),
        .ibuf_rd_addr(ibuf_rd_addr),
        .ibuf_rd_data(ibuf_rd_data),.ibuf_rd_valid(ibuf_rd_valid),
        .aff_scores(aff_scores),.done(aff_valid)
    );

    context_reasoning_engine #(.MAX_OBJECTS(MAX_OBJECTS),.SCORE_W(SCORE_W))
    u_context (
        .clk(clk),.rst_n(rst_n),
        .start(aff_valid),.num_objects(ctrl_num_objects),
        .aff_scores_in(aff_scores),.ctx_scores_out(ctx_scores),.done(ctx_valid)
    );

    rejection_gate #(.MAX_OBJECTS(MAX_OBJECTS),.SCORE_W(SCORE_W))
    u_gate (
        .clk(clk),.rst_n(rst_n),
        .start(ctx_valid),.num_objects(ctrl_num_objects),
        .scores_in(ctx_scores),.threshold(ctrl_threshold),
        .obj_accepted(obj_accepted),.any_accepted(gate_any_accepted),.done(gate_valid)
    );

    topk_selector #(.MAX_OBJECTS(MAX_OBJECTS),.TOPK_MAX(TOPK_MAX),.SCORE_W(SCORE_W))
    u_topk (
        .clk(clk),.rst_n(rst_n),
        .start(gate_valid),.num_objects(ctrl_num_objects),
        .topk_k({1'b0, ctrl_topk[2:0]}),.scores_in(ctx_scores),
        .accepted_mask(obj_accepted),
        .topk_ids(topk_ids),.topk_scores(topk_scores),
        .topk_count(topk_count),.done(topk_valid)
    );

    output_buffer #(.AXI_DW(64),.MAX_OBJECTS(MAX_OBJECTS),
                    .TOPK_MAX(TOPK_MAX),.SCORE_W(SCORE_W))
    u_obuf (
        .clk(clk),.rst_n(rst_n),
        .load(topk_valid),.gate_accepted(gate_any_accepted),
        .topk_ids(topk_ids),.topk_scores(topk_scores),
        .topk_count(topk_count),.threshold_used(ctrl_threshold),
        .rd_addr(obuf_rd_addr),.rd_data(obuf_rd_data),
        .size_words(obuf_size_words)
    );

    interrupt_controller u_irq (
        .clk(clk),.rst_n(rst_n),
        .irq_en(ctrl_irq_en),.done_pulse(accel_done_pulse),.irq_out(irq_out)
    );

endmodule