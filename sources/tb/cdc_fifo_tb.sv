// cdc_fifo_tb.sv — Testbench for Small Async FIFO Bus Synchronizer
// Uses #1 delay after @(posedge) to avoid race conditions with DUT always_ff blocks.
`timescale 1ns / 1ps

module cdc_fifo_tb;

    parameter WIDTH = 8;
    parameter DEPTH = 4;
    parameter SYNC_STAGES = 2;

    logic               wr_clk, rd_clk;
    logic               wr_rst_n, rd_rst_n;
    logic               wr_en, rd_en;
    logic [WIDTH-1:0]   wr_data, rd_data;
    logic               full, empty;

    parameter WR_CLK_PERIOD = 8.0;   // 125 MHz
    parameter RD_CLK_PERIOD = 12.0;  // ~83 MHz

    initial wr_clk = 0;
    initial rd_clk = 0;
    always #(WR_CLK_PERIOD/2) wr_clk = ~wr_clk;
    always #(RD_CLK_PERIOD/2) rd_clk = ~rd_clk;

    cdc_fifo #(
        .WIDTH       (WIDTH),
        .DEPTH       (DEPTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) dut (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .full     (full),
        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .empty    (empty)
    );

    integer errors = 0;

    // Write task — #1 delay ensures DUT sees correct values
    task automatic write_word(input [WIDTH-1:0] data);
        while (full) @(posedge wr_clk);
        @(posedge wr_clk); #1;
        wr_data = data;
        wr_en   = 1;
        @(posedge wr_clk); #1;
        wr_en   = 0;
    endtask

    // Read task — #1 delay and sample rd_data before deasserting rd_en
    task automatic read_word(output [WIDTH-1:0] data);
        while (empty) @(posedge rd_clk);
        @(posedge rd_clk); #1;
        rd_en = 1;
        data  = rd_data;  // Combinational read — data available immediately
        @(posedge rd_clk); #1;
        rd_en = 0;
    endtask

    initial begin
        $dumpfile("sim/waves/cdc_fifo_tb.vcd");
        $dumpvars(0, cdc_fifo_tb);

        wr_rst_n = 0;
        rd_rst_n = 0;
        wr_en    = 0;
        rd_en    = 0;
        wr_data  = 0;

        repeat(5) @(posedge wr_clk); #1;
        wr_rst_n = 1;
        rd_rst_n = 1;
        // Wait for cdc_counter to propagate reset
        repeat(SYNC_STAGES + 3) @(posedge wr_clk);
        repeat(SYNC_STAGES + 3) @(posedge rd_clk);

        // Test 1: Verify empty after reset
        $display("Test 1: Empty after reset");
        if (!empty) begin
            $display("ERROR: FIFO not empty after reset");
            errors++;
        end
        if (full) begin
            $display("ERROR: FIFO full after reset");
            errors++;
        end

        // Test 2: Write and read single word
        $display("Test 2: Single write/read");
        write_word(8'hAA);
        // Wait for empty flag to update
        repeat(SYNC_STAGES + 3) @(posedge rd_clk);

        if (empty) begin
            $display("ERROR: FIFO still empty after write");
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

        // Test 3: Fill FIFO to full
        $display("Test 3: Fill to full");
        for (int i = 0; i < DEPTH; i++) begin
            write_word(i[WIDTH-1:0]);
        end
        // Wait for full flag to settle
        repeat(SYNC_STAGES + 3) @(posedge wr_clk);

        if (!full) begin
            $display("ERROR: FIFO not full after writing DEPTH words");
            errors++;
        end

        // Test 4: Drain FIFO
        $display("Test 4: Drain FIFO");
        repeat(SYNC_STAGES + 3) @(posedge rd_clk);

        for (int i = 0; i < DEPTH; i++) begin
            logic [WIDTH-1:0] rdata;
            read_word(rdata);
            if (rdata !== i[WIDTH-1:0]) begin
                $display("ERROR: Drain word %0d: read 0x%02X, expected 0x%02X",
                         i, rdata, i[WIDTH-1:0]);
                errors++;
            end
        end

        // Wait for empty flag
        repeat(SYNC_STAGES + 3) @(posedge rd_clk);
        if (!empty) begin
            $display("ERROR: FIFO not empty after drain");
            errors++;
        end

        // Test 5: Concurrent write and read
        $display("Test 5: Concurrent write/read");
        fork
            begin
                for (int i = 0; i < 16; i++) begin
                    write_word(i[WIDTH-1:0]);
                end
            end
            begin
                logic [WIDTH-1:0] rdata;
                repeat(SYNC_STAGES + 5) @(posedge rd_clk);
                for (int i = 0; i < 16; i++) begin
                    read_word(rdata);
                    if (rdata !== i[WIDTH-1:0]) begin
                        $display("ERROR: Concurrent word %0d: read 0x%02X, expected 0x%02X",
                                 i, rdata, i[WIDTH-1:0]);
                        errors++;
                    end
                end
            end
        join

        repeat(SYNC_STAGES + 5) @(posedge rd_clk);

        // Test 6: Random bursts
        $display("Test 6: Random bursts");
        fork
            begin
                for (int i = 0; i < 32; i++) begin
                    write_word((i * 7 + 3) & 8'hFF);
                    repeat($urandom_range(0, 3)) @(posedge wr_clk);
                end
            end
            begin
                logic [WIDTH-1:0] rdata;
                repeat(SYNC_STAGES + 5) @(posedge rd_clk);
                for (int i = 0; i < 32; i++) begin
                    read_word(rdata);
                    if (rdata !== ((i * 7 + 3) & 8'hFF)) begin
                        $display("ERROR: Burst word %0d: read 0x%02X, expected 0x%02X",
                                 i, rdata, (i * 7 + 3) & 8'hFF);
                        errors++;
                    end
                    repeat($urandom_range(0, 3)) @(posedge rd_clk);
                end
            end
        join

        repeat(20) @(posedge rd_clk);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
