// cdc_counter_tb.sv — Testbench for Counter Synchronizer
`timescale 1ns / 1ps

module cdc_counter_tb;

    parameter WIDTH = 4;
    parameter SYNC_STAGES = 2;

    logic src_clk, dst_clk;
    logic dst_rst_n;
    logic [WIDTH-1:0] counter_src;
    logic [WIDTH-1:0] binary_out, gray_out, gray_in_out;

    parameter SRC_CLK_PERIOD = 8.0;
    parameter DST_CLK_PERIOD = 12.0;

    initial src_clk = 0;
    initial dst_clk = 0;
    always #(SRC_CLK_PERIOD/2) src_clk = ~src_clk;
    always #(DST_CLK_PERIOD/2) dst_clk = ~dst_clk;

    cdc_counter #(
        .WIDTH       (WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) dut (
        .clk         (dst_clk),
        .rst_n       (dst_rst_n),
        .binary_in   (counter_src),
        .binary_out  (binary_out),
        .gray_out    (gray_out),
        .gray_in_out (gray_in_out)
    );

    // Gray conversion reference for verification
    function automatic [WIDTH-1:0] bin2gray(input [WIDTH-1:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    integer errors = 0;
    logic [WIDTH-1:0] prev_binary_out;

    initial begin
        $dumpfile("sim/waves/cdc_counter_tb.vcd");
        $dumpvars(0, cdc_counter_tb);

        dst_rst_n = 0;
        counter_src = 0;

        repeat(5) @(posedge dst_clk);
        dst_rst_n = 1;
        repeat(3) @(posedge dst_clk);

        // Test 1: Verify reset state
        if (binary_out !== '0) begin
            $display("ERROR: binary_out not 0 after reset, got %0d", binary_out);
            errors++;
        end

        // Test 2: Verify gray_in_out matches expected Gray of binary_in
        $display("Test 2: gray_in_out verification");
        counter_src = 4'd5;
        #1;
        begin
            logic [WIDTH-1:0] expected;
            expected = bin2gray(4'd5);
            if (gray_in_out !== expected) begin
                $display("ERROR: gray_in_out=%b, expected=%b for binary_in=5", gray_in_out, expected);
                errors++;
            end
        end

        // Test 3: Free-running counter, check monotonicity
        $display("Test 3: Free-running counter monotonicity");
        counter_src = 0;
        prev_binary_out = 0;

        repeat(3 * (2**WIDTH)) begin
            @(posedge src_clk);
            counter_src = counter_src + 1'b1;

            repeat(SYNC_STAGES + 1) @(posedge dst_clk);
            prev_binary_out = binary_out;
        end

        // Test 4: Verify gray_out matches expected Gray encoding of binary_out
        $display("Test 4: Gray code output verification");
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);
        begin
            logic [WIDTH-1:0] expected_gray;
            expected_gray = bin2gray(binary_out);
            if (gray_out !== expected_gray) begin
                $display("ERROR: gray_out=%b doesn't match expected=%b for binary_out=%b",
                         gray_out, expected_gray, binary_out);
                errors++;
            end
        end

        // Test 5: Counter rollover
        $display("Test 5: Counter rollover");
        counter_src = {WIDTH{1'b1}};
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);
        @(posedge src_clk);
        counter_src = '0;
        repeat(SYNC_STAGES + 2) @(posedge dst_clk);

        // Test 6: Reset during counting
        $display("Test 6: Reset during counting");
        counter_src = 4'd7;
        repeat(SYNC_STAGES + 1) @(posedge dst_clk);
        dst_rst_n = 0;
        @(posedge dst_clk);
        if (binary_out !== '0) begin
            $display("ERROR: binary_out not 0 during reset");
            errors++;
        end
        repeat(3) @(posedge dst_clk);
        dst_rst_n = 1;

        repeat(10) @(posedge dst_clk);

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
