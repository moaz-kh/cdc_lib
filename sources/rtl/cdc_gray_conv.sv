// cdc_gray_conv.sv — Gray Code Conversion Utility
// Purely combinational bin-to-gray and gray-to-bin converter.
// Can be used standalone for Gray code operations.

`include "cdc_config.svh"

module cdc_gray_conv #(
    parameter int WIDTH = 4
) (
    // Binary to Gray conversion
    input  logic [WIDTH-1:0] i_binary,
    output logic [WIDTH-1:0] o_gray,

    // Gray to Binary conversion
    input  logic [WIDTH-1:0] i_gray,
    output logic [WIDTH-1:0] o_binary
);

    // Binary to Gray: XOR each bit with the bit above it
    assign o_gray = i_binary ^ (i_binary >> 1);

    // Gray to Binary: XOR cascade from MSB down
    always_comb begin
        o_binary[WIDTH-1] = i_gray[WIDTH-1];
        for (int i = WIDTH-2; i >= 0; i--)
            o_binary[i] = o_binary[i+1] ^ i_gray[i];
    end

endmodule
