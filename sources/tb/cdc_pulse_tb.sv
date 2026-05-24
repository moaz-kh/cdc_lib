// cdc_pulse_tb.sv — Testbench for Pulse Synchronizer (both toggle and counter modes)
// Uses #1 delay after @(posedge) to avoid race conditions with DUT always_ff blocks.
`timescale 1ns / 1ps

module cdc_pulse_tb;

    logic src_clk, dst_clk;
    logic src_rst_n, dst_rst_n;

    parameter SRC_CLK_PERIOD = 6.0;   // ~167 MHz (fast)
    parameter DST_CLK_PERIOD = 14.0;  // ~71 MHz (slow)
    parameter SYNC_STAGES = 2;

    initial src_clk = 0;
    initial dst_clk = 0;
    always #(SRC_CLK_PERIOD/2) src_clk = ~src_clk;
    always #(DST_CLK_PERIOD/2) dst_clk = ~dst_clk;

    // --- Toggle mode (MODE=0) ---
    logic src_pulse_t, dst_pulse_t;

    cdc_pulse_toggle #(
        .SYNC_STAGES (SYNC_STAGES)
    ) dut_toggle (
        .i_src_clk    (src_clk),
        .i_src_rst_n  (src_rst_n),
        .i_src_pulse  (src_pulse_t),
        .i_dst_clk    (dst_clk),
        .i_dst_rst_n  (dst_rst_n),
        .o_dst_pulse  (dst_pulse_t)
    );

    // --- Counter mode (MODE=1) ---
    logic src_pulse_c, dst_pulse_c;

    cdc_pulse_counter #(
        .SYNC_STAGES (SYNC_STAGES),
        .CTR_WIDTH   (4)
    ) dut_counter (
        .i_src_clk    (src_clk),
        .i_src_rst_n  (src_rst_n),
        .i_src_pulse  (src_pulse_c),
        .i_dst_clk    (dst_clk),
        .i_dst_rst_n  (dst_rst_n),
        .o_dst_pulse  (dst_pulse_c)
    );

    integer errors = 0;
    integer dst_count_t = 0;
    integer dst_count_c = 0;

    // Count destination pulses
    always @(posedge dst_clk) begin
        if (dst_pulse_t) dst_count_t++;
        if (dst_pulse_c) dst_count_c++;
    end

    // Pulse-shape monitor: dst_pulse_c must never be high two consecutive dst_clk cycles.
    // A wide pulse (RTL bug) will trigger this immediately.
    logic dst_pulse_c_prev;
    initial dst_pulse_c_prev = 1'b0;

    always @(posedge dst_clk) begin
        if (dst_pulse_c && dst_pulse_c_prev) begin
            $display("ERROR [monitor]: dst_pulse_c HIGH for 2+ consecutive cycles (wide pulse bug)");
            errors = errors + 1;
        end
        dst_pulse_c_prev = dst_pulse_c;
    end

    // Helper task: send single-cycle pulse on src_pulse_t
    task automatic send_toggle_pulse();
        @(posedge src_clk); #1;
        src_pulse_t = 1;
        @(posedge src_clk); #1;
        src_pulse_t = 0;
    endtask

    // Helper task: send single-cycle pulse on src_pulse_c
    task automatic send_counter_pulse();
        @(posedge src_clk); #1;
        src_pulse_c = 1;
        @(posedge src_clk); #1;
        src_pulse_c = 0;
    endtask

    // Task: hold src_pulse_c HIGH for exactly N consecutive src_clk cycles (zero gaps).
    task automatic send_burst_contiguous(input integer n);
        integer i;
        @(posedge src_clk); #1;
        for (i = 0; i < n; i++) begin
            src_pulse_c = 1;
            @(posedge src_clk); #1;
        end
        src_pulse_c = 0;
    endtask

    initial begin
        $dumpfile("sim/waves/cdc_pulse_tb.vcd");
        $dumpvars(0, cdc_pulse_tb);

        src_rst_n = 0;
        dst_rst_n = 0;
        src_pulse_t = 0;
        src_pulse_c = 0;

        repeat(5) @(posedge src_clk);
        #1;
        src_rst_n = 1;
        dst_rst_n = 1;
        repeat(5) @(posedge dst_clk);

        // ===== TEST TOGGLE MODE =====
        $display("=== Toggle Mode (MODE=0) Tests ===");

        // Test T1: Single pulse transfer
        $display("Test T1: Single pulse transfer");
        dst_count_t = 0;

        send_toggle_pulse();

        repeat(SYNC_STAGES + 4) @(posedge dst_clk);

        if (dst_count_t !== 1) begin
            $display("ERROR [toggle]: Expected 1 dst pulse, got %0d", dst_count_t);
            errors++;
        end

        // Test T2: Multiple spaced pulses
        $display("Test T2: Multiple spaced pulses");
        dst_count_t = 0;

        repeat(5) begin
            send_toggle_pulse();
            // Wait enough for toggle to propagate and settle
            repeat(SYNC_STAGES + 4) @(posedge dst_clk);
        end

        repeat(SYNC_STAGES + 3) @(posedge dst_clk);

        if (dst_count_t !== 5) begin
            $display("ERROR [toggle]: Expected 5 dst pulses, got %0d", dst_count_t);
            errors++;
        end

        // ===== TEST COUNTER MODE =====
        $display("=== Counter Mode (MODE=1) Tests ===");

        // Test C1: Single pulse transfer
        $display("Test C1: Single pulse transfer");
        dst_count_c = 0;

        send_counter_pulse();

        repeat(SYNC_STAGES + 5) @(posedge dst_clk);

        if (dst_count_c !== 1) begin
            $display("ERROR [counter]: Expected 1 dst pulse, got %0d", dst_count_c);
            errors++;
        end

        // Test C2: Burst of 5 pulses (back-to-back in src domain)
        $display("Test C2: Burst of 5 back-to-back pulses");
        dst_count_c = 0;

        repeat(5) begin
            send_counter_pulse();
        end

        // Wait for all pulses to propagate and be generated in dst
        repeat(SYNC_STAGES + 15) @(posedge dst_clk);

        if (dst_count_c !== 5) begin
            $display("ERROR [counter]: Expected 5 dst pulses from burst, got %0d", dst_count_c);
            errors++;
        end else begin
            $display("INFO [counter]: All 5 burst pulses received correctly");
        end

        // Test C3: Larger burst — 10 pulses
        $display("Test C3: Burst of 10 pulses");
        dst_count_c = 0;

        repeat(10) begin
            send_counter_pulse();
        end

        repeat(SYNC_STAGES + 25) @(posedge dst_clk);

        if (dst_count_c !== 10) begin
            $display("ERROR [counter]: Expected 10 dst pulses, got %0d", dst_count_c);
            errors++;
        end else begin
            $display("INFO [counter]: All 10 burst pulses received correctly");
        end

        // Test C4: Reset mid-transfer (counter mode)
        $display("Test C4: Reset mid-transfer");
        send_counter_pulse();

        @(posedge dst_clk); #1;
        dst_rst_n = 0;
        src_rst_n = 0;
        repeat(3) @(posedge dst_clk);
        repeat(3) @(posedge src_clk);
        #1;
        dst_rst_n = 1;
        src_rst_n = 1;

        // Post-reset transfer
        repeat(5) @(posedge dst_clk);
        dst_count_c = 0;

        send_counter_pulse();

        repeat(SYNC_STAGES + 5) @(posedge dst_clk);

        if (dst_count_c !== 1) begin
            $display("ERROR [counter]: Post-reset pulse transfer failed, got %0d", dst_count_c);
            errors++;
        end

        repeat(10) @(posedge dst_clk);

        // Test C5: Contiguous burst — src_pulse_c held HIGH for 6 consecutive src_clk cycles
        $display("Test C5: Contiguous burst (6 consecutive src pulses, no gaps)");
        dst_count_c = 0;

        send_burst_contiguous(6);

        // Fixed impl: 6 pulses x 2 dst cycles = 12 minimum; SYNC_STAGES + 15 has 3-cycle margin
        repeat(SYNC_STAGES + 15) @(posedge dst_clk);

        if (dst_count_c !== 6) begin
            $display("ERROR [counter]: Expected 6 dst pulses from contiguous burst, got %0d", dst_count_c);
            errors++;
        end else begin
            $display("INFO [counter]: All 6 contiguous burst pulses received correctly");
        end

        repeat(5) @(posedge dst_clk);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
