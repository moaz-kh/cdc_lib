// cdc_gray_sync_tb.sv — Testbench for bit-parallel Gray-code synchronizer
`timescale 1ns / 1ps

module cdc_gray_sync_tb;

    parameter WIDTH       = 4;
    parameter SYNC_STAGES = 2;

    logic               src_clk, dst_clk;
    logic               dst_rst_n;
    logic [WIDTH-1:0]   gray_in;
    logic [WIDTH-1:0]   gray_out;

    parameter SRC_CLK_PERIOD = 8.0;
    parameter DST_CLK_PERIOD = 13.0;

    initial src_clk = 0;
    initial dst_clk = 0;
    always #(SRC_CLK_PERIOD/2) src_clk = ~src_clk;
    always #(DST_CLK_PERIOD/2) dst_clk = ~dst_clk;

    cdc_gray_sync #(
        .WIDTH       (WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) dut (
        .clk      (dst_clk),
        .rst_n    (dst_rst_n),
        .gray_in  (gray_in),
        .gray_out (gray_out)
    );

    function automatic [WIDTH-1:0] bin2gray(input [WIDTH-1:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    integer errors = 0;

    initial begin
        $dumpfile("sim/waves/cdc_gray_sync_tb.vcd");
        $dumpvars(0, cdc_gray_sync_tb);

        dst_rst_n = 0;
        gray_in   = '0;

        repeat(5) @(posedge dst_clk);
        dst_rst_n = 1;
        repeat(3) @(posedge dst_clk);

        // Test 1: Reset clears output
        $display("Test 1: Output cleared by reset");
        if (gray_out !== '0) begin
            $display("ERROR: gray_out not 0 after reset, got %b", gray_out);
            errors++;
        end

        // Test 2: Static Gray value propagates after SYNC_STAGES dst cycles
        $display("Test 2: Static Gray propagation");
        @(posedge src_clk); #1;
        gray_in = bin2gray(4'd5);  // 0111
        repeat(SYNC_STAGES + 1) @(posedge dst_clk);
        if (gray_out !== bin2gray(4'd5)) begin
            $display("ERROR: static Gray: got %b, expected %b", gray_out, bin2gray(4'd5));
            errors++;
        end

        // Test 3: Incremental Gray sequence — 1-bit change per step, verify each arrives
        $display("Test 3: Incremental Gray sequence");
        for (int i = 0; i < 2**WIDTH; i++) begin
            @(posedge src_clk); #1;
            gray_in = bin2gray(i[WIDTH-1:0]);
            repeat(SYNC_STAGES + 2) @(posedge dst_clk);
            if (gray_out !== bin2gray(i[WIDTH-1:0])) begin
                $display("ERROR: step %0d: got %b, expected %b",
                         i, gray_out, bin2gray(i[WIDTH-1:0]));
                errors++;
            end
        end

        // Test 4: Reset mid-transfer clears output
        $display("Test 4: Reset mid-transfer");
        @(posedge src_clk); #1;
        gray_in = bin2gray(4'd9);
        @(posedge dst_clk);
        dst_rst_n = 0;
        @(posedge dst_clk);
        if (gray_out !== '0) begin
            $display("ERROR: gray_out not 0 during reset");
            errors++;
        end
        dst_rst_n = 1;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);

        // Test 5: All-zeros and all-ones round-trip
        $display("Test 5: All-zeros / all-ones");
        @(posedge src_clk); #1;
        gray_in = '0;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);
        if (gray_out !== '0) begin
            $display("ERROR: all-zeros: got %b", gray_out);
            errors++;
        end
        @(posedge src_clk); #1;
        gray_in = '1;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);
        if (gray_out !== '1) begin
            $display("ERROR: all-ones: got %b", gray_out);
            errors++;
        end

        repeat(5) @(posedge dst_clk);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
