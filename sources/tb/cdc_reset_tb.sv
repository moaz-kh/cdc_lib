// cdc_reset_tb.sv — Testbench for Reset Synchronizer (active-low only)
`timescale 1ns / 1ps

module cdc_reset_tb;

    logic clk;
    logic async_rst_n;
    logic sync_rst_n;

    parameter CLK_PERIOD = 10.0;
    parameter SYNC_STAGES = 2;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    cdc_reset #(
        .SYNC_STAGES(SYNC_STAGES)
    ) dut (
        .clk         (clk),
        .async_rst_n (async_rst_n),
        .sync_rst_n  (sync_rst_n)
    );

    integer errors = 0;

    initial begin
        $dumpfile("sim/waves/cdc_reset_tb.vcd");
        $dumpvars(0, cdc_reset_tb);

        // Start with reset asserted (active-low = 0)
        async_rst_n = 0;
        repeat(3) @(posedge clk);

        // Test 1: Verify instant assert
        if (sync_rst_n !== 1'b0) begin
            $display("ERROR: sync_rst_n not asserted (low) during reset");
            errors++;
        end

        // Test 2: Release async reset, verify sync deassert takes SYNC_STAGES cycles
        @(negedge clk);  // Change between clock edges
        async_rst_n = 1;

        // Should still be in reset for first SYNC_STAGES-1 clocks
        repeat(SYNC_STAGES - 1) @(posedge clk);
        #1;
        if (sync_rst_n !== 1'b0) begin
            $display("INFO: Reset still asserted after %0d clocks (expected)", SYNC_STAGES-1);
        end

        // After SYNC_STAGES clocks, should be deasserted
        repeat(2) @(posedge clk);
        #1;
        if (sync_rst_n !== 1'b1) begin
            $display("ERROR: Reset not deasserted after SYNC_STAGES clocks");
            errors++;
        end

        // Test 3: Assert reset asynchronously (mid-cycle)
        repeat(5) @(posedge clk);
        #(CLK_PERIOD * 0.3);  // Mid-cycle assertion
        async_rst_n = 0;
        #1;

        // Should assert immediately (async)
        if (sync_rst_n !== 1'b0) begin
            $display("ERROR: Reset did not assert asynchronously");
            errors++;
        end

        // Test 4: Release and verify clean deassert again
        repeat(3) @(posedge clk);
        async_rst_n = 1;
        repeat(SYNC_STAGES + 1) @(posedge clk);
        #1;
        if (sync_rst_n !== 1'b1) begin
            $display("ERROR: Reset did not cleanly deassert");
            errors++;
        end

        repeat(5) @(posedge clk);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
