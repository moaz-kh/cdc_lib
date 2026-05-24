// cdc_sync_fifo_tb.sv — Testbench for Single-Clock Synchronous FIFO
// Uses #1 delay after @(posedge) to avoid race conditions with DUT always_ff blocks.
`timescale 1ns / 1ps

module cdc_sync_fifo_tb;

    parameter WIDTH     = 8;
    parameter DEPTH     = 16;
    parameter FWFT_MODE = 0;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    parameter CLK_PERIOD = 10.0;  // 100 MHz

    logic               clk;
    logic               rst_n;
    logic               wr_en, rd_en;
    logic [WIDTH-1:0]   wr_data, rd_data;
    logic               full, empty;
    logic [ADDR_WIDTH:0] count;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    cdc_sync_fifo #(
        .WIDTH     (WIDTH),
        .DEPTH     (DEPTH),
        .FWFT_MODE (FWFT_MODE)
    ) dut (
        .i_clk     (clk),
        .i_rst_n   (rst_n),
        .i_wr_en   (wr_en),
        .i_wr_data (wr_data),
        .o_full    (full),
        .i_rd_en   (rd_en),
        .o_rd_data (rd_data),
        .o_empty   (empty),
        .o_count   (count)
    );

    integer errors = 0;

    // Write task
    task automatic write_word(input [WIDTH-1:0] data);
        @(posedge clk); #1;
        wr_data = data;
        wr_en   = 1;
        @(posedge clk); #1;
        wr_en   = 0;
    endtask

    // Read task — handles both registered (1-cycle latency) and FWFT modes
    task automatic read_word(output [WIDTH-1:0] data);
        @(posedge clk); #1;
        rd_en = 1;
        if (FWFT_MODE) begin
            data = rd_data;  // Combinational read — data available immediately
        end
        @(posedge clk); #1;
        if (!FWFT_MODE) begin
            data = rd_data;  // Registered read — data available after clock edge
        end
        rd_en = 0;
    endtask

    initial begin
        $dumpfile("sim/waves/cdc_sync_fifo_tb.vcd");
        $dumpvars(0, cdc_sync_fifo_tb);

        rst_n   = 0;
        wr_en   = 0;
        rd_en   = 0;
        wr_data = 0;

        repeat(5) @(posedge clk); #1;
        rst_n = 1;
        repeat(3) @(posedge clk);

        // ---- Test 1: Empty after reset ----
        $display("Test 1: Empty after reset");
        if (!empty) begin
            $display("ERROR: FIFO not empty after reset");
            errors++;
        end
        if (full) begin
            $display("ERROR: FIFO full after reset");
            errors++;
        end
        if (count !== 0) begin
            $display("ERROR: Count not zero after reset (count=%0d)", count);
            errors++;
        end

        // ---- Test 2: Single write/read ----
        $display("Test 2: Single write/read");
        write_word(8'hAA);
        @(posedge clk); // let count update

        if (empty) begin
            $display("ERROR: FIFO still empty after write");
            errors++;
        end
        if (count !== 1) begin
            $display("ERROR: Count should be 1, got %0d", count);
            errors++;
        end

        begin
            logic [WIDTH-1:0] rdata;
            read_word(rdata);
            if (rdata !== 8'hAA) begin
                $display("ERROR: Read 0x%02X, expected 0xAA", rdata);
                errors++;
            end
        end

        @(posedge clk); // let flags settle
        if (!empty) begin
            $display("ERROR: FIFO not empty after reading single word");
            errors++;
        end

        // ---- Test 3: Fill to full ----
        $display("Test 3: Fill to full");
        for (int i = 0; i < DEPTH; i++) begin
            write_word(i[WIDTH-1:0]);
        end
        @(posedge clk);

        if (!full) begin
            $display("ERROR: FIFO not full after writing DEPTH words");
            errors++;
        end
        if (count !== DEPTH) begin
            $display("ERROR: Count should be %0d, got %0d", DEPTH, count);
            errors++;
        end

        // Verify write is blocked when full
        begin
            logic [ADDR_WIDTH:0] cnt_before;
            cnt_before = count;
            write_word(8'hFF);
            @(posedge clk);
            if (count !== cnt_before) begin
                $display("ERROR: Write succeeded when FIFO was full");
                errors++;
            end
        end

        // ---- Test 4: Drain FIFO ----
        $display("Test 4: Drain FIFO");
        for (int i = 0; i < DEPTH; i++) begin
            logic [WIDTH-1:0] rdata;
            read_word(rdata);
            if (rdata !== i[WIDTH-1:0]) begin
                $display("ERROR: Drain word %0d: read 0x%02X, expected 0x%02X",
                         i, rdata, i[WIDTH-1:0]);
                errors++;
            end
        end

        @(posedge clk);
        if (!empty) begin
            $display("ERROR: FIFO not empty after drain");
            errors++;
        end
        if (count !== 0) begin
            $display("ERROR: Count not zero after drain (count=%0d)", count);
            errors++;
        end

        // ---- Test 5: Simultaneous write/read ----
        $display("Test 5: Simultaneous write/read at steady state");
        // Pre-fill with 4 words
        for (int i = 0; i < 4; i++) begin
            write_word(i[WIDTH-1:0]);
        end
        @(posedge clk);

        // Simultaneous write and read for 16 cycles
        for (int i = 0; i < 16; i++) begin
            @(posedge clk); #1;
            wr_en   = 1;
            rd_en   = 1;
            wr_data = (i + 100) & 8'hFF;
            @(posedge clk); #1;
            wr_en = 0;
            rd_en = 0;
        end
        @(posedge clk);

        // Count should still be 4 (equal writes and reads)
        if (count !== 4) begin
            $display("ERROR: Count after simultaneous ops should be 4, got %0d", count);
            errors++;
        end

        // Drain remaining
        for (int i = 0; i < 4; i++) begin
            logic [WIDTH-1:0] rdata;
            read_word(rdata);
        end

        // ---- Test 6: Random bursts ----
        $display("Test 6: Random write/read bursts");
        fork
            // Writer
            begin
                for (int i = 0; i < 64; i++) begin
                    while (full) @(posedge clk);
                    write_word((i * 7 + 3) & 8'hFF);
                    repeat($urandom_range(0, 2)) @(posedge clk);
                end
            end
            // Reader
            begin
                logic [WIDTH-1:0] rdata;
                repeat(5) @(posedge clk);  // let data accumulate
                for (int i = 0; i < 64; i++) begin
                    while (empty) @(posedge clk);
                    read_word(rdata);
                    if (rdata !== ((i * 7 + 3) & 8'hFF)) begin
                        $display("ERROR: Burst word %0d: read 0x%02X, expected 0x%02X",
                                 i, rdata, (i * 7 + 3) & 8'hFF);
                        errors++;
                    end
                    repeat($urandom_range(0, 3)) @(posedge clk);
                end
            end
        join

        // ---- Test 7: Reset mid-operation ----
        $display("Test 7: Reset mid-operation");
        for (int i = 0; i < 8; i++) begin
            write_word(i[WIDTH-1:0]);
        end
        @(posedge clk);

        // Assert reset
        rst_n = 0;
        repeat(3) @(posedge clk); #1;
        rst_n = 1;
        repeat(3) @(posedge clk);

        if (!empty) begin
            $display("ERROR: FIFO not empty after mid-operation reset");
            errors++;
        end
        if (count !== 0) begin
            $display("ERROR: Count not zero after reset (count=%0d)", count);
            errors++;
        end

        // Verify FIFO works normally after reset
        write_word(8'h55);
        begin
            logic [WIDTH-1:0] rdata;
            read_word(rdata);
            if (rdata !== 8'h55) begin
                $display("ERROR: Post-reset read 0x%02X, expected 0x55", rdata);
                errors++;
            end
        end

        repeat(10) @(posedge clk);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

    // Timeout protection
    initial begin
        #(100000);
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
