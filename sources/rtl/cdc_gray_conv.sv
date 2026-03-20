// cdc_gray_conv.sv — Gray Code Conversion Utility
// Purely combinational bin-to-gray and gray-to-bin converter.
// Can be used standalone for Gray code operations.

module cdc_gray_conv #(
    parameter int WIDTH = 4
) (
    // Binary to Gray conversion
    input  logic [WIDTH-1:0] binary_in,
    output logic [WIDTH-1:0] gray_out,

    // Gray to Binary conversion
    input  logic [WIDTH-1:0] gray_in,
    output logic [WIDTH-1:0] binary_out
);

    // Binary to Gray: XOR each bit with the bit above it
    assign gray_out = binary_in ^ (binary_in >> 1);

    // Gray to Binary: XOR cascade from MSB down
    always_comb begin
        binary_out[WIDTH-1] = gray_in[WIDTH-1];
        for (int i = WIDTH-2; i >= 0; i--)
            binary_out[i] = binary_out[i+1] ^ gray_in[i];
    end

endmodule
