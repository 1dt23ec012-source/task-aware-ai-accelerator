// axi_slave_if.sv (v3 clean declaration order)
// DVCon India 2026 | Team Vulcan 629 | DSATM Bengaluru
`timescale 1ns/1ps

module axi_slave_if #(
    parameter int AXI_DW = 32,
    parameter int AXI_AW = 64,
    parameter int AXI_IW = 12
)(
    input  logic               clk,
    input  logic               rst_n,

    input  logic [AXI_AW-1:0]   s_awaddr,
    input  logic [7:0]           s_awlen,
    input  logic [2:0]           s_awsize,
    input  logic [1:0]           s_awburst,
    input  logic [AXI_IW-1:0]   s_awid,
    input  logic                 s_awvalid,
    output logic                 s_awready,
    input  logic [AXI_DW-1:0]   s_wdata,
    input  logic [AXI_DW/8-1:0] s_wstrb,
    input  logic                 s_wlast,
    input  logic                 s_wvalid,
    output logic                 s_wready,
    output logic [AXI_IW-1:0]   s_bid,
    output logic [1:0]           s_bresp,
    output logic                 s_bvalid,
    input  logic                 s_bready,
    input  logic [AXI_AW-1:0]   s_araddr,
    input  logic [7:0]           s_arlen,
    input  logic [2:0]           s_arsize,
    input  logic [1:0]           s_arburst,
    input  logic [AXI_IW-1:0]   s_arid,
    input  logic                 s_arvalid,
    output logic                 s_arready,
    output logic [AXI_DW-1:0]   s_rdata,
    output logic [1:0]           s_rresp,
    output logic                 s_rlast,
    output logic [AXI_IW-1:0]   s_rid,
    output logic                 s_rvalid,
    input  logic                 s_rready,

    // Config outputs
    output logic                ctrl_start,
    output logic                ctrl_irq_en,
    output logic [5:0]          ctrl_num_objects,
    output logic [2:0]          ctrl_topk,
    output logic [15:0]         ctrl_threshold,
    output logic [63:0]         ctrl_task_addr,
    output logic [63:0]         ctrl_obj_addr,
    output logic [63:0]         ctrl_result_addr,

    input  logic [31:0]         perf_cycle,
    input  logic [31:0]         perf_compute,
    input  logic [31:0]         perf_ddr_rd,
    input  logic [31:0]         perf_ddr_wr,
    input  logic [31:0]         perf_accepted,
    input  logic [31:0]         perf_rejected,
    input  logic [31:0]         perf_total,
    input  logic [31:0]         perf_axi_rd_beats,
    input  logic [31:0]         perf_axi_wr_beats,
    input  logic [31:0]         perf_bytes_rd,
    input  logic [31:0]         perf_bytes_wr,
    input  logic [31:0]         perf_latency,

    input  logic                status_busy,
    input  logic                status_done,
    input  logic                status_error
);

    localparam [6:0]
        O_CTRL   = 7'h00, O_STATUS  = 7'h04,
        O_TASK_AL= 7'h10, O_TASK_AH = 7'h14,
        O_OBJ_AL = 7'h18, O_OBJ_AH  = 7'h1C,
        O_RES_AL = 7'h20, O_RES_AH  = 7'h24,
        O_NUMOBJ = 7'h28, O_THRESH  = 7'h2C,
        O_TOPK   = 7'h30, O_IRQ_EN  = 7'h34,
        O_P_CYC  = 7'h40, O_P_COMP  = 7'h44,
        O_P_DRD  = 7'h48, O_P_DWR   = 7'h4C,
        O_P_ACC  = 7'h50, O_P_REJ   = 7'h54,
        O_P_TOT  = 7'h58, O_P_ARD   = 7'h5C,
        O_P_AWR  = 7'h60, O_P_BRD   = 7'h64,
        O_P_BWR  = 7'h68, O_P_LAT   = 7'h6C;

    logic [31:0] reg_ctrl, reg_task_al, reg_task_ah;
    logic [31:0] reg_obj_al, reg_obj_ah, reg_res_al, reg_res_ah;
    logic [31:0] reg_numobj, reg_thresh, reg_topk, reg_irq_en;
    logic        reg_done_sticky;

    // Write channel declarations (Declared before use to avoid warning Synth 8-6901)
    logic [AXI_AW-1:0] aw_lat;
    logic [AXI_IW-1:0] aw_id_lat;
    logic              aw_pend;

    assign ctrl_start       = reg_ctrl[0];
    assign ctrl_irq_en      = reg_irq_en[0];
    assign ctrl_num_objects = reg_numobj[5:0];
    assign ctrl_topk        = reg_topk[2:0];
    assign ctrl_threshold   = reg_thresh[15:0];
    assign ctrl_task_addr   = {reg_task_ah, reg_task_al};
    assign ctrl_obj_addr    = {reg_obj_ah,  reg_obj_al};
    assign ctrl_result_addr = {reg_res_ah,  reg_res_al};

    // Latch sticky done
    always_ff @(posedge clk) begin
        if (!rst_n)
            reg_done_sticky <= 1'b0;
        else if (reg_ctrl[0] || (s_wvalid && s_wready && aw_lat[6:0] == O_CTRL))
            reg_done_sticky <= 1'b0;
        else if (status_done)
            reg_done_sticky <= 1'b1;
    end

    // Write channel state logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_awready   <= 1'b1; 
            s_wready    <= 1'b0; 
            s_bvalid    <= 1'b0;
            aw_pend     <= 1'b0;
            reg_ctrl    <= '0;       reg_task_al <= '0; reg_task_ah <= '0;
            reg_obj_al  <= '0;       reg_obj_ah  <= '0; reg_res_al  <= '0;
            reg_res_ah  <= '0;       reg_numobj  <= 32'd1;
            reg_thresh  <= 32'h2CCD; reg_topk    <= 32'd1;
            reg_irq_en  <= 32'd1;
            aw_lat      <= '0;
            aw_id_lat   <= '0;
            s_bid       <= '0;
            s_bresp     <= '0;
        end else begin
            if (s_awvalid && s_awready) begin
                aw_lat    <= s_awaddr; 
                aw_id_lat <= s_awid;
                aw_pend   <= 1'b1; 
                s_awready <= 1'b0; 
                s_wready  <= 1'b1;
            end
            if (s_wvalid && s_wready && aw_pend) begin
                s_wready  <= 1'b0; 
                aw_pend   <= 1'b0; 
                s_awready <= 1'b1;
                case (aw_lat[6:0])
                    O_CTRL:   reg_ctrl    <= s_wdata;
                    O_TASK_AL:reg_task_al <= s_wdata;
                    O_TASK_AH:reg_task_ah <= s_wdata;
                    O_OBJ_AL: reg_obj_al  <= s_wdata;
                    O_OBJ_AH: reg_obj_ah  <= s_wdata;
                    O_RES_AL: reg_res_al  <= s_wdata;
                    O_RES_AH: reg_res_ah  <= s_wdata;
                    O_NUMOBJ: reg_numobj  <= s_wdata;
                    O_THRESH: reg_thresh  <= s_wdata;
                    O_TOPK:   reg_topk    <= s_wdata;
                    O_IRQ_EN: reg_irq_en  <= s_wdata;
                    default: ;
                endcase
                s_bid   <= aw_id_lat; 
                s_bresp <= 2'b00; 
                s_bvalid <= 1'b1;
            end
            if (reg_ctrl[0] && status_busy) reg_ctrl[0] <= 1'b0;
            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
        end
    end

    // Read channel declarations and multiplexer
    logic [AXI_AW-1:0] ar_lat;
    logic [AXI_IW-1:0] ar_id_lat;
    logic              ar_pend;

    logic [AXI_DW-1:0] rd_mux;
    always_comb begin
        rd_mux = '0;
        case (ar_lat[6:0])
            O_CTRL:   rd_mux = reg_ctrl;
            O_STATUS: rd_mux = {29'b0, status_error, (status_done | reg_done_sticky), status_busy};
            O_TASK_AL:rd_mux = reg_task_al;
            O_TASK_AH:rd_mux = reg_task_ah;
            O_OBJ_AL: rd_mux = reg_obj_al;
            O_OBJ_AH: rd_mux = reg_obj_ah;
            O_RES_AL: rd_mux = reg_res_al;
            O_RES_AH: rd_mux = reg_res_ah;
            O_NUMOBJ: rd_mux = reg_numobj;
            O_THRESH: rd_mux = reg_thresh;
            O_TOPK:   rd_mux = reg_topk;
            O_IRQ_EN: rd_mux = reg_irq_en;
            O_P_CYC:  rd_mux = perf_cycle;
            O_P_COMP: rd_mux = perf_compute;
            O_P_DRD:  rd_mux = perf_ddr_rd;
            O_P_DWR:  rd_mux = perf_ddr_wr;
            O_P_ACC:  rd_mux = perf_accepted;
            O_P_REJ:  rd_mux = perf_rejected;
            O_P_TOT:  rd_mux = perf_total;
            O_P_ARD:  rd_mux = perf_axi_rd_beats;
            O_P_AWR:  rd_mux = perf_axi_wr_beats;
            O_P_BRD:  rd_mux = perf_bytes_rd;
            O_P_BWR:  rd_mux = perf_bytes_wr;
            O_P_LAT:  rd_mux = perf_latency;
            default:  rd_mux = 32'hDEAD_BEEF;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_arready <= 1'b1; 
            s_rvalid  <= 1'b0;
            s_rlast   <= 1'b0; 
            ar_pend   <= 1'b0;
            s_rdata   <= '0;
            s_rresp   <= '0;
            s_rid     <= '0;
            ar_lat    <= '0;
            ar_id_lat <= '0;
        end else begin
            if (s_arvalid && s_arready) begin
                ar_lat    <= s_araddr; 
                ar_id_lat <= s_arid;
                ar_pend   <= 1'b1; 
                s_arready <= 1'b0;
            end
            if (ar_pend && !s_rvalid) begin
                s_rdata   <= rd_mux; 
                s_rresp   <= 2'b00;
                s_rlast   <= 1'b1; 
                s_rid     <= ar_id_lat;
                s_rvalid  <= 1'b1; 
                ar_pend   <= 1'b0;
            end
            if (s_rvalid && s_rready) begin
                s_rvalid  <= 1'b0; 
                s_rlast   <= 1'b0; 
                s_arready <= 1'b1;
            end
        end
    end

endmodule