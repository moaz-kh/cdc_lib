// cdc_qualifier_tb.sv — Testbench for Valid-Qualified Data Bus Synchronizer
`timescale 1ns / 1ps

module cdc_qualifier_tb;

    parameter WIDTH       = 8;
    parameter SYNC_STAGES = 2;

    logic               src_clk, dst_clk;
    logic               dst_rst_n;
    logic [WIDTH-1:0]   data_in;
    logic               valid_in;
    logic [WIDTH-1:0]   data_out;
    logic               valid_out;

    parameter SRC_CLK_PERIOD = 7.0;
    parameter DST_CLK_PERIOD = 13.0;

    initial src_clk = 0;
    initial dst_clk = 0;
    always #(SRC_CLK_PERIOD/2) src_clk = ~src_clk;
    always #(DST_CLK_PERIOD/2) dst_clk = ~dst_clk;

    cdc_qualifier #(
        .WIDTH       (WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) dut (
        .i_clk   (dst_clk),
        .i_rst_n (dst_rst_n),
        .i_data  (data_in),
        .i_valid (valid_in),
        .o_data  (data_out),
        .o_valid (valid_out)
    );

    integer errors = 0;

    // Task: assert data + valid, hold for enough dst cycles to settle,
    // then deassert valid and hold low between transfers.
    task automatic send_word(input [WIDTH-1:0] data, input integer hold_dst_cycles);
        @(posedge src_clk); #1;
        data_in  = data;
        valid_in = 1;
        repeat(hold_dst_cycles) @(posedge dst_clk);
        @(posedge src_clk); #1;
        valid_in = 0;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);
    endtask

    initial begin
        $dumpfile("sim/waves/cdc_qualifier_tb.vcd");
        $dumpvars(0, cdc_qualifier_tb);

        dst_rst_n = 0;
        data_in   = '0;
        valid_in  = 0;

        repeat(5) @(posedge dst_clk);
        dst_rst_n = 1;
        repeat(3) @(posedge dst_clk);

        // Test 1: Reset clears output
        $display("Test 1: Output cleared by reset");
        if (data_out !== '0 || valid_out !== 1'b0) begin
            $display("ERROR: data_out/valid_out not 0 after reset, got %02X/%b",
                      data_out, valid_out);
            errors++;
        end

        // Test 2: Single transfer — valid held long enough to settle
        $display("Test 2: Single transfer");
        send_word(8'hA5, SYNC_STAGES + 4);
        if (data_out !== 8'hA5) begin
            $display("ERROR: expected data_out=0xA5, got 0x%02X", data_out);
            errors++;
        end
        if (valid_out !== 1'b0) begin
            $display("ERROR: valid_out should deassert after valid_in drops");
            errors++;
        end

        // Test 3: valid_out follows valid_in level while asserted
        $display("Test 3: valid_out asserts while valid_in held high");
        @(posedge src_clk); #1;
        data_in  = 8'h3C;
        valid_in = 1;
        repeat(SYNC_STAGES + 3) @(posedge dst_clk);
        if (valid_out !== 1'b1) begin
            $display("ERROR: valid_out did not assert while valid_in held high");
            errors++;
        end
        if (data_out !== 8'h3C) begin
            $display("ERROR: data_out not captured while valid_out high, got 0x%02X", data_out);
            errors++;
        end
        @(posedge src_clk); #1;
        valid_in = 0;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);
        if (valid_out !== 1'b0) begin
            $display("ERROR: valid_out did not deassert after valid_in dropped");
            errors++;
        end

        // Test 4: Sequential transfers with distinct values
        $display("Test 4: Sequential transfers");
        for (int i = 0; i < 8; i++) begin
            send_word(i[WIDTH-1:0], SYNC_STAGES + 3);
            if (data_out !== i[WIDTH-1:0]) begin
                $display("ERROR: transfer %0d: expected 0x%02X, got 0x%02X",
                         i, i[WIDTH-1:0], data_out);
                errors++;
            end
        end

        // Test 5: Data updates while valid stays high (continuous capture)
        $display("Test 5: Data update mid-assertion");
        @(posedge src_clk); #1;
        data_in  = 8'h11;
        valid_in = 1;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);
        if (data_out !== 8'h11) begin
            $display("ERROR: expected data_out=0x11, got 0x%02X", data_out);
            errors++;
        end
        @(posedge src_clk); #1;
        data_in = 8'h22;
        repeat(2) @(posedge dst_clk);
        if (data_out !== 8'h22) begin
            $display("ERROR: expected data_out=0x22 after mid-assertion update, got 0x%02X", data_out);
            errors++;
        end
        @(posedge src_clk); #1;
        valid_in = 0;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);

        // Test 6: Reset mid-transfer
        $display("Test 6: Reset mid-transfer");
        @(posedge src_clk); #1;
        data_in  = 8'h42;
        valid_in = 1;
        repeat(2) @(posedge dst_clk); #1;
        dst_rst_n = 0;
        repeat(3) @(posedge dst_clk);
        if (data_out !== '0 || valid_out !== 1'b0) begin
            $display("ERROR: reset did not clear data_out/valid_out");
            errors++;
        end
        @(posedge src_clk); #1;
        valid_in = 0;
        dst_rst_n = 1;
        repeat(SYNC_STAGES + 3) @(posedge dst_clk);

        // Test 7: Post-reset recovery
        $display("Test 7: Post-reset recovery");
        send_word(8'hBE, SYNC_STAGES + 4);
        if (data_out !== 8'hBE) begin
            $display("ERROR: post-reset transfer failed, got 0x%02X", data_out);
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
