// cdc_gray_conv_tb.sv — Testbench for Gray Code Conversion Utility
`timescale 1ns / 1ps

module cdc_gray_conv_tb;

    parameter WIDTH = 4;
    parameter NUM_VALUES = 2**WIDTH;

    logic [WIDTH-1:0] binary_in, gray_out;
    logic [WIDTH-1:0] gray_in, binary_out;

    cdc_gray_conv #(.WIDTH(WIDTH)) dut (
        .binary_in  (binary_in),
        .gray_out   (gray_out),
        .gray_in    (gray_in),
        .binary_out (binary_out)
    );

    integer errors = 0;
    integer i;
    logic [WIDTH-1:0] expected_gray;
    logic [WIDTH-1:0] roundtrip_result;

    initial begin
        $dumpfile("sim/waves/cdc_gray_conv_tb.vcd");
        $dumpvars(0, cdc_gray_conv_tb);

        // Test 1: Exhaustive bin-to-gray-to-bin round trip
        $display("Testing exhaustive round-trip for WIDTH=%0d (%0d values)", WIDTH, NUM_VALUES);

        for (i = 0; i < NUM_VALUES; i++) begin
            // Binary to Gray
            binary_in = i[WIDTH-1:0];
            #1;

            // Feed Gray output into Gray-to-Binary input
            gray_in = gray_out;
            #1;

            // Verify round-trip
            if (binary_out !== binary_in) begin
                $display("ERROR: Round-trip failed: bin=%b -> gray=%b -> bin=%b (expected %b)",
                         binary_in, gray_out, binary_out, binary_in);
                errors++;
            end
        end

        // Test 2: Verify Gray code property — adjacent values differ by exactly 1 bit
        $display("Testing single-bit change property");
        for (i = 0; i < NUM_VALUES - 1; i++) begin
            logic [WIDTH-1:0] gray_a, gray_b, diff;
            integer bit_count;

            binary_in = i[WIDTH-1:0];
            #1;
            gray_a = gray_out;

            binary_in = (i + 1);
            #1;
            gray_b = gray_out;

            diff = gray_a ^ gray_b;
            bit_count = 0;
            for (int b = 0; b < WIDTH; b++)
                if (diff[b]) bit_count++;

            if (bit_count !== 1) begin
                $display("ERROR: Gray codes for %0d and %0d differ by %0d bits (expected 1): %b vs %b",
                         i, i+1, bit_count, gray_a, gray_b);
                errors++;
            end
        end

        // Test 3: Verify known values
        binary_in = '0;
        #1;
        if (gray_out !== '0) begin
            $display("ERROR: Gray(0) should be 0, got %b", gray_out);
            errors++;
        end

        binary_in = {{(WIDTH-1){1'b0}}, 1'b1};  // 1
        #1;
        if (gray_out !== {{(WIDTH-1){1'b0}}, 1'b1}) begin
            $display("ERROR: Gray(1) should be 1, got %b", gray_out);
            errors++;
        end

        #10;

        if (errors == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED *** (%0d errors)", errors);

        $finish;
    end

endmodule
