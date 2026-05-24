// cdc_bit_tb.sv — Testbench for N-Stage Single-Bit Synchronizer
`timescale 1ns / 1ps

module cdc_bit_tb;

    // Dual-clock setup
    logic clk_src, clk_dst;
    logic rst_n;
    logic async_in, sync_out;

    parameter CLK_SRC_PERIOD = 7.3;   // ~137 MHz (fast)
    parameter CLK_DST_PERIOD = 10.0;  // 100 MHz (slow)
    parameter SYNC_STAGES = 2;

    initial clk_src = 0;
    initial clk_dst = 0;
    always #(CLK_SRC_PERIOD/2) clk_src = ~clk_src;
    always #(CLK_DST_PERIOD/2) clk_dst = ~clk_dst;

    cdc_bit #(
        .SYNC_STAGES (SYNC_STAGES),
        .RESET_VALUE (1'b0)
    ) dut (
        .i_clk      (clk_dst),
        .i_rst_n    (rst_n),
        .i_async_in (async_in),
        .o_sync_out (sync_out)
    );

    integer errors = 0;

    initial begin
        $dumpfile("sim/waves/cdc_bit_tb.vcd");
        $dumpvars(0, cdc_bit_tb);

        // Reset
        rst_n = 0;
        async_in = 0;
        repeat(5) @(posedge clk_dst);
        rst_n = 1;

        // Test 1: Verify reset value
        if (sync_out !== 1'b0) begin
            $display("ERROR: sync_out not 0 after reset");
            errors++;
        end

        // Test 2: Assert async_in, verify latency = SYNC_STAGES cycles
        @(posedge clk_src);
        async_in = 1;
        // Wait SYNC_STAGES destination clocks for propagation
        repeat(SYNC_STAGES) @(posedge clk_dst);
        // One more edge for sampling
        @(posedge clk_dst);
        if (sync_out !== 1'b1) begin
            $display("ERROR: sync_out not 1 after %0d dst clocks", SYNC_STAGES+1);
            errors++;
        end

        // Test 3: Deassert async_in
        @(posedge clk_src);
        async_in = 0;
        repeat(SYNC_STAGES + 1) @(posedge clk_dst);
        if (sync_out !== 1'b0) begin
            $display("ERROR: sync_out not 0 after deassert");
            errors++;
        end

        // Test 4: Stress toggle near clock edges
        repeat(50) begin
            @(posedge clk_src);
            #(CLK_SRC_PERIOD * 0.1);  // Near edge
            async_in = ~async_in;
        end
        // Let synchronizer settle
        repeat(SYNC_STAGES + 2) @(posedge clk_dst);

        // Test 5: Reset mid-operation
        async_in = 1;
        repeat(SYNC_STAGES + 1) @(posedge clk_dst);
        rst_n = 0;
        @(posedge clk_dst);
        if (sync_out !== 1'b0) begin
            $display("ERROR: sync_out not 0 during reset");
            errors++;
        end
        repeat(3) @(posedge clk_dst);
        rst_n = 1;

        repeat(5) @(posedge clk_dst);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
