// cdc_counter_tb.sv — Testbench for self-contained CDC counter
`timescale 1ns / 1ps

module cdc_counter_tb;

    parameter WIDTH       = 4;
    parameter SYNC_STAGES = 2;

    logic               src_clk, dst_clk;
    logic               src_rst_n, dst_rst_n;
    logic               count_up, count_down;
    logic [WIDTH-1:0]   src_count;
    logic [WIDTH-1:0]   dst_gray, dst_count;

    parameter SRC_CLK_PERIOD = 8.0;
    parameter DST_CLK_PERIOD = 13.0;

    initial src_clk = 0;
    initial dst_clk = 0;
    always #(SRC_CLK_PERIOD/2) src_clk = ~src_clk;
    always #(DST_CLK_PERIOD/2) dst_clk = ~dst_clk;

    cdc_counter #(
        .WIDTH       (WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) dut (
        .src_clk    (src_clk),
        .src_rst_n  (src_rst_n),
        .count_up   (count_up),
        .count_down (count_down),
        .src_count  (src_count),
        .dst_clk    (dst_clk),
        .dst_rst_n  (dst_rst_n),
        .dst_gray   (dst_gray),
        .dst_count  (dst_count)
    );

    function automatic [WIDTH-1:0] bin2gray(input [WIDTH-1:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    integer errors = 0;

    // Module-level temporaries (iverilog: no logic decl inside unnamed begin/end)
    logic [WIDTH-1:0] tmp_expected;
    logic [WIDTH-1:0] tmp_before;
    integer           tmp_i;

    initial begin
        $dumpfile("sim/waves/cdc_counter_tb.vcd");
        $dumpvars(0, cdc_counter_tb);

        src_rst_n  = 0;
        dst_rst_n  = 0;
        count_up   = 0;
        count_down = 0;

        repeat(5) @(posedge dst_clk);
        src_rst_n = 1;
        dst_rst_n = 1;
        repeat(3) @(posedge dst_clk);

        // Test 1: Reset state
        $display("Test 1: Reset state");
        if (src_count !== '0) begin
            $display("ERROR: src_count not 0 after reset, got %0d", src_count);
            errors++;
        end
        if (dst_count !== '0) begin
            $display("ERROR: dst_count not 0 after reset, got %0d", dst_count);
            errors++;
        end

        // Test 2: count_up increments src_count each src cycle
        $display("Test 2: count_up increments src_count");
        for (int i = 0; i < 8; i++) begin
            @(posedge src_clk); #1;
            count_up = 1;
            @(posedge src_clk); #1;
            count_up = 0;
            if (src_count !== (i + 1)) begin
                $display("ERROR: src_count step %0d: got %0d, expected %0d",
                         i, src_count, i + 1);
                errors++;
            end
        end

        // Test 3: dst_count catches up after SYNC_STAGES+1 dst cycles
        $display("Test 3: dst_count propagates to destination");
        tmp_expected = src_count;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);
        if (dst_count !== tmp_expected) begin
            $display("ERROR: dst_count=%0d, expected=%0d", dst_count, tmp_expected);
            errors++;
        end
        if (dst_gray !== bin2gray(tmp_expected)) begin
            $display("ERROR: dst_gray=%b, expected=%b", dst_gray, bin2gray(tmp_expected));
            errors++;
        end

        // Test 4: count_down decrements src_count
        $display("Test 4: count_down decrements src_count");
        tmp_before = src_count;
        @(posedge src_clk); #1;
        count_down = 1;
        @(posedge src_clk); #1;
        count_down = 0;
        if (src_count !== (tmp_before - 1'b1)) begin
            $display("ERROR: after count_down: got %0d, expected %0d",
                     src_count, tmp_before - 1'b1);
            errors++;
        end

        // Test 5: Simultaneous count_up and count_down — no change
        $display("Test 5: Simultaneous up+down = no change");
        tmp_before = src_count;
        @(posedge src_clk); #1;
        count_up   = 1;
        count_down = 1;
        @(posedge src_clk); #1;
        count_up   = 0;
        count_down = 0;
        if (src_count !== tmp_before) begin
            $display("ERROR: simultaneous up+down changed count: %0d -> %0d",
                     tmp_before, src_count);
            errors++;
        end

        // Test 6: Rollover — drive to all-ones then increment once more
        $display("Test 6: Rollover");
        tmp_i = src_count;
        while (tmp_i < (2**WIDTH - 1)) begin
            @(posedge src_clk); #1;
            count_up = 1;
            @(posedge src_clk); #1;
            count_up = 0;
            tmp_i = src_count;
        end
        if (src_count !== {WIDTH{1'b1}}) begin
            $display("ERROR: pre-rollover src_count=%0d, expected %0d",
                     src_count, {WIDTH{1'b1}});
            errors++;
        end
        @(posedge src_clk); #1;
        count_up = 1;
        @(posedge src_clk); #1;
        count_up = 0;
        if (src_count !== '0) begin
            $display("ERROR: post-rollover src_count=%0d, expected 0", src_count);
            errors++;
        end

        // Test 7: Reset during counting clears both domains
        $display("Test 7: Reset during counting");
        @(posedge src_clk); #1;
        count_up = 1;
        @(posedge src_clk); #1;
        count_up  = 0;
        src_rst_n = 0;
        dst_rst_n = 0;
        @(posedge src_clk); #1;
        if (src_count !== '0) begin
            $display("ERROR: src_count not 0 during reset");
            errors++;
        end
        @(posedge dst_clk); #1;
        if (dst_count !== '0) begin
            $display("ERROR: dst_count not 0 during reset");
            errors++;
        end
        repeat(3) @(posedge dst_clk);
        src_rst_n = 1;
        dst_rst_n = 1;

        repeat(10) @(posedge dst_clk);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
