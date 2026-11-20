`timescale 1ns/1ps

module tb_fpga_top;

    logic       sys_clk = 1'b0;
    logic       sys_rst_n = 1'b0;
    logic       btn_start = 1'b0;
    logic [3:0] task_sw = 4'd0; // Task 0: Serve Wine
    logic [7:0] led;
    logic       uart_txd;

    always #10.0 sys_clk = ~sys_clk;

    fpga_top dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .btn_start(btn_start),
        .task_sw(task_sw),
        .led(led),
        .uart_txd(uart_txd)
    );

    initial begin
        $display("[SIM] Starting FPGA Top Simulation with Task Switches...");
        sys_rst_n = 1'b0;
        btn_start = 1'b0;
        task_sw   = 4'd0; // Test Task 0: "Serve Wine"
        #200;
        sys_rst_n = 1'b1;
        #100;
        
        $display("[SIM] Triggering Task 0: 'Serve Wine'...");
        btn_start = 1'b1;
        #50;
        btn_start = 1'b0;

        wait (dut.is_done == 1'b1);
        repeat(2) @(posedge sys_clk);

        $display("\n==================================================");
        $display("  SUCCESS! TASK 0 FINISHED ON FPGA TOP!");
        $display("  Task Selected: %d (Serve Wine)", task_sw);
        $display("  Winner ID    : %d (0 = Wine Glass)", dut.winner_id);
        $display("  Winner Score : 0x%04X (Expected: 0x5332)", dut.winner_score);
        $display("  Any Accepted : %d", dut.any_accepted);
        $display("==================================================\n");
        $finish;
    end

    initial begin
        #500_000;
        $error("\n[SIM ERROR] FPGA Top timeout!");
        $finish;
    end

endmodule