// dvcon_pkg.sv
// DVCon India 2026 | Team Vulcan 629 | DSATM Bengaluru
// AXI4 struct typedefs moved to a package so all files share them cleanly
// Vivado: add this file FIRST in compile order
`timescale 1ns/1ps

package dvcon_pkg;

    typedef struct packed {
        logic [63:0] awaddr; logic [7:0]  awlen;  logic [2:0]  awsize;
        logic [1:0]  awburst;logic [11:0] awid;   logic        awvalid;
        logic [63:0] wdata;  logic [7:0]  wstrb;  logic        wlast;
        logic        wvalid; logic        bready;
        logic [63:0] araddr; logic [7:0]  arlen;  logic [2:0]  arsize;
        logic [1:0]  arburst;logic [11:0] arid;   logic        arvalid;
        logic        rready;
    } axi4_s_in_t;

    typedef struct packed {
        logic        awready; logic        wready;
        logic [11:0] bid;     logic [1:0]  bresp;  logic bvalid;
        logic        arready;
        logic [63:0] rdata;   logic [1:0]  rresp;  logic rlast;
        logic [11:0] rid;     logic        rvalid;
    } axi4_s_out_t;

    typedef struct packed {
        logic [63:0] awaddr; logic [7:0]  awlen;  logic [2:0]  awsize;
        logic [1:0]  awburst;logic [11:0] awid;   logic        awvalid;
        logic [63:0] wdata;  logic [7:0]  wstrb;  logic        wlast;
        logic        wvalid; logic        bready;
        logic [63:0] araddr; logic [7:0]  arlen;  logic [2:0]  arsize;
        logic [1:0]  arburst;logic [11:0] arid;   logic        arvalid;
        logic        rready;
    } axi4_m_out_t;

    typedef struct packed {
        logic        awready; logic        wready;
        logic [11:0] bid;     logic [1:0]  bresp;  logic bvalid;
        logic        arready;
        logic [63:0] rdata;   logic [1:0]  rresp;  logic rlast;
        logic [11:0] rid;     logic        rvalid;
    } axi4_m_in_t;

endpackage
