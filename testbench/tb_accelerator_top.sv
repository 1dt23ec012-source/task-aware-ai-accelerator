// tb_accelerator_top.sv (v6 VCD dump enabled)
// DVCon India 2026 | Team Vulcan 629 | DSATM Bengaluru
`timescale 1ns/1ps
`default_nettype none

module tb_accelerator_top;

    localparam int  EMB_DIM     = 16;
    localparam int  MAX_OBJECTS = 8;
    localparam int  TOPK_MAX    = 4;
    localparam int  SCORE_W     = 16;
    localparam real CLK_PERIOD  = 20.0;

    localparam [63:0] ACCEL_BASE  = 64'h2006_0000;
    localparam [63:0] DDR_BASE    = 64'h8000_0000;
    localparam [63:0] TASK_ADDR   = DDR_BASE;
    localparam [63:0] OBJ_ADDR    = DDR_BASE + 64'h200;
    localparam [63:0] RESULT_ADDR = DDR_BASE + 64'h1000;

    localparam [6:0]
        O_CTRL   = 7'h00, O_STATUS  = 7'h04,
        O_TASK_AL= 7'h10, O_TASK_AH = 7'h14,
        O_OBJ_AL = 7'h18, O_OBJ_AH  = 7'h1C,
        O_RES_AL = 7'h20, O_RES_AH  = 7'h24,
        O_NUMOBJ = 7'h28, O_THRESH  = 7'h2C,
        O_TOPK   = 7'h30, O_IRQ_EN  = 7'h34,
        O_P_CYC  = 7'h40, O_P_LAT   = 7'h6C;

    logic        clk   = 1'b0;
    logic        rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── AXI4 Slave flat signals ───────────────────────────────────
    logic [63:0] s_awaddr; logic [7:0]  s_awlen;  logic [2:0] s_awsize;
    logic [1:0]  s_awburst;logic [11:0] s_awid;   logic       s_awvalid;
    logic        s_awready;
    logic [31:0] s_wdata;  logic [3:0]  s_wstrb;  logic       s_wlast;
    logic        s_wvalid; logic        s_wready;
    logic [11:0] s_bid;    logic [1:0]  s_bresp;  logic       s_bvalid;
    logic        s_bready;
    logic [63:0] s_araddr; logic [7:0]  s_arlen;  logic [2:0] s_arsize;
    logic [1:0]  s_arburst;logic [11:0] s_arid;   logic       s_arvalid;
    logic        s_arready;
    logic [31:0] s_rdata;  logic [1:0]  s_rresp;  logic       s_rlast;
    logic [11:0] s_rid;    logic        s_rvalid;  logic       s_rready;

    // ── AXI4 Master flat signals ──────────────────────────────────
    logic [63:0] m_awaddr; logic [7:0]  m_awlen;  logic [2:0] m_awsize;
    logic [1:0]  m_awburst;logic [11:0] m_awid;   logic       m_awvalid;
    logic        m_awready;
    logic [63:0] m_wdata;  logic [7:0]  m_wstrb;  logic       m_wlast;
    logic        m_wvalid; logic        m_wready;
    logic [11:0] m_bid;    logic [1:0]  m_bresp;  logic       m_bvalid;
    logic        m_bready;
    logic [63:0] m_araddr; logic [7:0]  m_arlen;  logic [2:0] m_arsize;
    logic [1:0]  m_arburst;logic [11:0] m_arid;   logic       m_arvalid;
    logic        m_arready;
    logic [63:0] m_rdata;  logic [1:0]  m_rresp;  logic       m_rlast;
    logic [11:0] m_rid;    logic        m_rvalid;  logic       m_rready;

    logic        irq_out;
    logic [31:0] perf_cycle_count;
    logic [31:0] perf_compute_cycles;

    // ── DUT ───────────────────────────────────────────────────────
    accelerator_top #(
        .EMB_DIM(EMB_DIM),.MAX_OBJECTS(MAX_OBJECTS),
        .TOPK_MAX(TOPK_MAX),.SCORE_W(SCORE_W),.MAC_MODE(8)
    ) dut (
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
        .m_rid(m_rid),.m_rvalid(m_rvalid),.m_rready(m_rready),
        .irq_out(irq_out),
        .perf_cycle_count(perf_cycle_count),
        .perf_compute_cycles(perf_compute_cycles)
    );

    // ── DDR3 model ────────────────────────────────────────────────
    logic [63:0] ddr3 [0:4095];

    task automatic init_ddr3;
        for (int i=0;i<4096;i++) ddr3[i]='0;
        // Task embedding (words 0..3)
        ddr3[0]=64'h4000_4000_4000_4000; ddr3[1]=64'h4000_4000_4000_4000;
        ddr3[2]=64'h4000_4000_4000_4000; ddr3[3]=64'h4000_4000_4000_4000;
        
        // Obj0 wine_glass PREFERRED (words 64..67)
        ddr3[64]=64'h4000_4000_4000_4000; ddr3[65]=64'h4000_4000_4000_4000;
        ddr3[66]=64'h4000_4000_4000_4000; ddr3[67]=64'h4000_4000_4000_4000;

        // Obj1 knife PENALISED (words 68..71)
        ddr3[68]=64'h2800_2800_2800_2800; ddr3[69]=64'h2800_2800_2800_2800;
        ddr3[70]=64'h2800_2800_2800_2800; ddr3[71]=64'h2800_2800_2800_2800;

        // Obj2 cup NEUTRAL (words 72..75)
        ddr3[72]=64'h3000_3000_3000_3000; ddr3[73]=64'h3000_3000_3000_3000;
        ddr3[74]=64'h3000_3000_3000_3000; ddr3[75]=64'h3000_3000_3000_3000;

        // Obj3 person NEVER_TOOL (words 76..79)
        ddr3[76]=64'h0800_0800_0800_0800; ddr3[77]=64'h0800_0800_0800_0800;
        ddr3[78]=64'h0800_0800_0800_0800; ddr3[79]=64'h0800_0800_0800_0800;

        // Priors located immediately after 16 object words (words 80..83)
        ddr3[80]=64'h0000_0000_6000_E000; // Obj0 (tag 2'b11 PREFERRED)
        ddr3[81]=64'h0000_0000_4000_8000; // Obj1 (tag 2'b10 PENALISED)
        ddr3[82]=64'h0000_0000_5000_5000; // Obj2 (tag 2'b00 NEUTRAL)
        ddr3[83]=64'h0000_0000_1000_4000; // Obj3 (tag 2'b01 NEVER_TOOL)
    endtask

    // ── DDR3 read responder ───────────────────────────────────────
    logic [15:0] drd_cnt;
    logic [63:0] raddr_lat;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_arready <= 1'b0; m_rvalid <= 1'b0; m_rlast <= 1'b0;
            m_rdata   <= '0;   m_rresp  <= 2'b00; m_rid   <= '0;
            drd_cnt   <= '0;   raddr_lat<= '0;
        end else begin
            m_arready <= 1'b1;
            if (m_arvalid && m_arready) begin
                drd_cnt   <= {8'b0, m_arlen};
                m_rid     <= m_arid;
                raddr_lat <= (m_araddr - DDR_BASE) >> 3;
                m_rdata   <= ddr3[(m_araddr - DDR_BASE) >> 3];
                m_rvalid  <= 1'b1;
                m_rlast   <= (m_arlen == 8'h0);
            end
            if (m_rvalid && m_rready) begin
                if (drd_cnt == 0) begin
                    m_rvalid <= 1'b0;
                    m_rlast  <= 1'b0;
                end else begin
                    drd_cnt   <= drd_cnt - 1'b1;
                    raddr_lat <= raddr_lat + 1'b1;
                    m_rdata   <= ddr3[raddr_lat + 1'b1];
                    m_rlast   <= (drd_cnt == 16'd1);
                end
            end
        end
    end

    // ── DDR3 write responder ──────────────────────────────────────
    logic [63:0] waddr_lat;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_awready <= 1'b0; m_wready <= 1'b0; m_bvalid <= 1'b0;
            m_bresp   <= 2'b00; m_bid   <= '0;   waddr_lat<= '0;
        end else begin
            m_awready <= 1'b1;
            m_wready  <= 1'b1;
            if (m_awvalid && m_awready) begin
                waddr_lat <= (m_awaddr - DDR_BASE) >> 3;
                m_bid     <= m_awid;
            end
            if (m_wvalid && m_wready) begin
                ddr3[waddr_lat] <= m_wdata;
                waddr_lat       <= waddr_lat + 1'b1;
            end
            if (m_wvalid && m_wlast && m_wready)
                m_bvalid <= 1'b1;
            if (m_bvalid && m_bready)
                m_bvalid <= 1'b0;
        end
    end

    // ── Robust AXI slave write task ───────────────────────────────
    task automatic axi_wr(input logic [6:0] off, input logic [31:0] d);
        @(posedge clk);
        s_awaddr  <= ACCEL_BASE | {57'b0, off};
        s_awlen   <= 8'h0;
        s_awsize  <= 3'b010;
        s_awburst <= 2'b01;
        s_awid    <= '0;
        s_awvalid <= 1'b1;

        s_wdata   <= d;
        s_wstrb   <= 4'hF;
        s_wlast   <= 1'b1;
        s_wvalid  <= 1'b1;
        s_bready  <= 1'b1;

        do @(posedge clk); while (!s_awready);
        s_awvalid <= 1'b0;

        while (!s_wready) @(posedge clk);
        s_wvalid <= 1'b0;

        while (!s_bvalid) @(posedge clk);
        s_bready <= 1'b0;
        @(posedge clk);
    endtask

    // ── Robust AXI slave read task ────────────────────────────────
    task automatic axi_rd(input logic [6:0] off, output logic [31:0] d);
        @(posedge clk);
        s_araddr  <= ACCEL_BASE | {57'b0, off};
        s_arlen   <= 8'h0;
        s_arsize  <= 3'b010;
        s_arburst <= 2'b01;
        s_arid    <= '0;
        s_arvalid <= 1'b1;
        s_rready  <= 1'b1;

        do @(posedge clk); while (!s_arready);
        s_arvalid <= 1'b0;

        while (!s_rvalid) @(posedge clk);
        d = s_rdata;
        s_rready <= 1'b0;
        @(posedge clk);
    endtask

    task automatic poll_done(output logic tmo);
        logic [31:0] st; int n=0; tmo=1'b0;
        forever begin
            axi_rd(O_STATUS, st);
            if (st[1]) break;
            if (++n > 10000) begin 
                $error("[TB] TIMEOUT waiting for accelerator done!"); 
                tmo=1'b1; 
                break; 
            end
            repeat(5) @(posedge clk);
        end
    endtask

    task automatic cfg_start;
        axi_wr(O_TASK_AL, 32'(TASK_ADDR   & 64'hFFFF_FFFF));
        axi_wr(O_TASK_AH, 32'(TASK_ADDR   >> 32));
        axi_wr(O_OBJ_AL,  32'(OBJ_ADDR    & 64'hFFFF_FFFF));
        axi_wr(O_OBJ_AH,  32'(OBJ_ADDR    >> 32));
        axi_wr(O_RES_AL,  32'(RESULT_ADDR & 64'hFFFF_FFFF));
        axi_wr(O_RES_AH,  32'(RESULT_ADDR >> 32));
        axi_wr(O_NUMOBJ,  32'd4);
        axi_wr(O_THRESH,  32'h2CCD);
        axi_wr(O_TOPK,    32'd2);
        axi_wr(O_IRQ_EN,  32'd1);
        axi_wr(O_CTRL,    32'd1);
    endtask

    int pc=0, fc=0;
    task automatic chk(input string n, input logic c);
        if(c) begin $display("  [PASS] %s",n); pc++; end
        else  begin $error ("  [FAIL] %s",n); fc++; end
    endtask

    logic [31:0] rd32;
    logic [63:0] rs, rw1;
    logic        tmo;

    initial begin
        // ── VCD Dump for Vivado Power Analysis ────────────────────────
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_accelerator_top);

        s_awaddr='0; s_awlen='0; s_awsize='0; s_awburst='0;
        s_awid='0;   s_awvalid='0;
        s_wdata='0;  s_wstrb='0; s_wlast='0; s_wvalid='0; s_bready='0;
        s_araddr='0; s_arlen='0; s_arsize='0; s_arburst='0;
        s_arid='0;   s_arvalid='0; s_rready='0;

        init_ddr3();

        $display("\n╔══════════════════════════════════════╗");
        $display(  "║  DVCon Stage 2B Testbench v6 golden  ║");
        $display(  "║  Team Vulcan 629 | DSATM Bengaluru  ║");
        $display(  "╚══════════════════════════════════════╝\n");

        rst_n=1'b0; repeat(10) @(posedge clk);
        rst_n=1'b1; repeat(4)  @(posedge clk);
        $display("[TB] Reset complete\n");

        $display("─── TC1: Register write");
        axi_wr(O_TASK_AL,32'h8000_0000); axi_wr(O_TASK_AH,32'h0);
        axi_wr(O_OBJ_AL, 32'h8000_0200); axi_wr(O_OBJ_AH, 32'h0);
        axi_wr(O_RES_AL, 32'h8000_1000); axi_wr(O_RES_AH, 32'h0);
        axi_wr(O_NUMOBJ,32'd4); axi_wr(O_THRESH,32'h2CCD);
        axi_wr(O_TOPK,  32'd2); axi_wr(O_IRQ_EN,32'd1);
        chk("TC1 write completes",1'b1);

        $display("─── TC2: Register read-back");
        axi_rd(O_NUMOBJ,rd32); chk("TC2 NUM_OBJECTS=4",  rd32[5:0]==6'd4);
        axi_rd(O_THRESH,rd32); chk("TC2 THRESHOLD=2CCD", rd32[15:0]==16'h2CCD);
        axi_rd(O_TOPK,  rd32); chk("TC2 TOPK=2",         rd32[2:0]==3'd2);

        $display("─── TC3: STATUS before start");
        axi_rd(O_STATUS,rd32);
        chk("TC3 BUSY=0",  rd32[0]==1'b0);
        chk("TC3 DONE=0",  rd32[1]==1'b0);
        chk("TC3 ERROR=0", rd32[2]==1'b0);
        chk("TC9a IRQ=0",  irq_out==1'b0);

        $display("─── TC4-TC10: Full pipeline run");
        cfg_start();
        repeat(2) @(posedge clk);
        axi_rd(O_STATUS,rd32); chk("TC4 BUSY=1 after START", rd32[0]==1'b1);

        poll_done(tmo); chk("TC10 no timeout", !tmo);

        axi_rd(O_STATUS,rd32);
        chk("TC8 DONE=1", rd32[1]==1'b1);
        chk("TC8 BUSY=0", rd32[0]==1'b0);

        @(posedge clk);
        chk("TC9 IRQ=0 after done", irq_out==1'b0);

        rs  = ddr3[(RESULT_ADDR-DDR_BASE)>>3];
        rw1 = ddr3[(RESULT_ADDR-DDR_BASE+8)>>3];
        $display("  Result[0]=0x%016h", rs);
        $display("  Result[1]=0x%016h", rw1);
        chk("TC10 magic=44564330",      rs[63:32]==32'h44564330);
        chk("TC7  any_accepted=1",      rs[0]==1'b1);
        chk("TC8  topk_count>=1",       rs[11:8]>=4'd1);
        chk("TC5  rank1=wine_glass(0)", rw1[47:40]==8'd0);
        chk("TC6  knife not rank1",     rw1[47:40]!=8'd1);

        $display("─── TC11: Performance counters");
        axi_rd(O_P_CYC,rd32); chk("TC11 cycle_count>0", rd32>32'd0);
        axi_rd(O_P_LAT,rd32); chk("TC11 latency>0",     rd32>32'd0);

        $display("─── TC12: Back-to-back run");
        axi_wr(O_CTRL,32'h2); repeat(2) @(posedge clk);
        cfg_start(); poll_done(tmo);
        chk("TC12 second run ok", !tmo);
        rs=ddr3[(RESULT_ADDR-DDR_BASE)>>3];
        chk("TC12 magic valid",   rs[63:32]==32'h44564330);

        $display("\n╔══════════════════════════════════════╗");
        $display(  "║  PASS=%-3d  FAIL=%-3d                 ║",pc,fc);
        if(fc==0) $display("║  ALL TESTS PASSED ✓                 ║");
        else      $display("║  %0d FAILURE(S) ✗                   ║",fc);
        $display(  "╚══════════════════════════════════════╝\n");
        $finish;
    end

    initial begin
        #(CLK_PERIOD*200_000);
        $error("[WATCHDOG] exceeded 200K cycles"); $finish;
    end

endmodule
`default_nettype wire