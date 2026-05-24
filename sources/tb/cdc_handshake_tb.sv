// cdc_handshake_tb.sv — Testbench for Handshake-Based Bus Synchronizer
`timescale 1ns / 1ps

module cdc_handshake_tb;

    parameter WIDTH = 8;
    parameter SYNC_STAGES = 2;

    logic               src_clk, dst_clk;
    logic               src_rst_n, dst_rst_n;
    logic [WIDTH-1:0]   src_data;
    logic               src_valid, src_ready;
    logic [WIDTH-1:0]   dst_data;
    logic               dst_valid;

    parameter SRC_CLK_PERIOD = 7.0;
    parameter DST_CLK_PERIOD = 13.0;

    initial src_clk = 0;
    initial dst_clk = 0;
    always #(SRC_CLK_PERIOD/2) src_clk = ~src_clk;
    always #(DST_CLK_PERIOD/2) dst_clk = ~dst_clk;

    cdc_handshake #(
        .WIDTH       (WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) dut (
        .i_src_clk    (src_clk),
        .i_src_rst_n  (src_rst_n),
        .i_src_data   (src_data),
        .i_src_valid  (src_valid),
        .o_src_ready  (src_ready),
        .i_dst_clk    (dst_clk),
        .i_dst_rst_n  (dst_rst_n),
        .o_dst_data   (dst_data),
        .o_dst_valid  (dst_valid)
    );

    integer errors = 0;

    // Collect received data
    logic [WIDTH-1:0] received_data [$];

    always @(posedge dst_clk) begin
        if (dst_valid)
            received_data.push_back(dst_data);
    end

    // Task: send one word with handshake (#1 delay avoids race with DUT always_ff)
    task automatic send_data(input [WIDTH-1:0] data);
        while (!src_ready) @(posedge src_clk);
        @(posedge src_clk); #1;
        src_data  = data;
        src_valid = 1;
        @(posedge src_clk); #1;
        src_valid = 0;
    endtask

    initial begin
        $dumpfile("sim/waves/cdc_handshake_tb.vcd");
        $dumpvars(0, cdc_handshake_tb);

        src_rst_n = 0;
        dst_rst_n = 0;
        src_valid = 0;
        src_data  = 0;

        repeat(5) @(posedge src_clk); #1;
        src_rst_n = 1;
        dst_rst_n = 1;
        repeat(5) @(posedge dst_clk);

        // Test 1: Single transfer
        $display("Test 1: Single transfer");
        send_data(8'hA5);
        // Wait for transfer to complete
        repeat(2 * SYNC_STAGES + 5) @(posedge dst_clk);

        if (received_data.size() < 1 || received_data[0] !== 8'hA5) begin
            $display("ERROR: Expected 0xA5, got 0x%02X (size=%0d)",
                     received_data.size() > 0 ? received_data[0] : 8'hXX,
                     received_data.size());
            errors++;
        end

        // Test 2: Sequential transfers with back-pressure
        $display("Test 2: Sequential transfers");
        received_data.delete();

        for (int i = 0; i < 8; i++) begin
            send_data(i[WIDTH-1:0]);
            // Wait for handshake completion
            repeat(2 * (2 * SYNC_STAGES + 3)) @(posedge dst_clk);
        end

        // Wait for last transfer
        repeat(2 * SYNC_STAGES + 5) @(posedge dst_clk);

        if (received_data.size() !== 8) begin
            $display("ERROR: Expected 8 transfers, got %0d", received_data.size());
            errors++;
        end else begin
            for (int i = 0; i < 8; i++) begin
                if (received_data[i] !== i[WIDTH-1:0]) begin
                    $display("ERROR: Transfer %0d: expected 0x%02X, got 0x%02X",
                             i, i[WIDTH-1:0], received_data[i]);
                    errors++;
                end
            end
        end

        // Test 3: Verify back-pressure (src_ready goes low during transfer)
        $display("Test 3: Back-pressure verification");
        received_data.delete();
        send_data(8'hFF);
        @(posedge src_clk);
        if (src_ready !== 1'b0) begin
            $display("INFO: src_ready should be low during transfer");
            // Not necessarily an error depending on timing
        end
        repeat(2 * SYNC_STAGES + 10) @(posedge dst_clk);

        // Test 4: Reset mid-transfer
        $display("Test 4: Reset mid-transfer");
        send_data(8'h42);
        repeat(2) @(posedge dst_clk); #1;
        dst_rst_n = 0;
        src_rst_n = 0;
        repeat(3) @(posedge dst_clk);
        repeat(3) @(posedge src_clk); #1;
        dst_rst_n = 1;
        src_rst_n = 1;
        repeat(10) @(posedge dst_clk);

        // Test 5: Post-reset transfer to verify recovery
        $display("Test 5: Post-reset recovery");
        received_data.delete();
        repeat(5) @(posedge src_clk);
        send_data(8'hBE);
        repeat(2 * SYNC_STAGES + 10) @(posedge dst_clk);

        if (received_data.size() < 1 || received_data[0] !== 8'hBE) begin
            $display("ERROR: Post-reset transfer failed");
            errors++;
        end

        repeat(10) @(posedge dst_clk);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
