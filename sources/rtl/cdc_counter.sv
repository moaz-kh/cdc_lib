// cdc_counter.sv — Counter Synchronizer
// Accepts a binary counter value, converts to Gray code, synchronizes
// each bit independently via cdc_bit, then converts back to binary.
// Exposes binary_out, gray_out (synchronized), and gray_in_out (pre-sync
// Gray of input — useful for local full/empty comparison in FIFOs).

module cdc_counter #(
    parameter int WIDTH       = 4,
    parameter int SYNC_STAGES = 2
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic [WIDTH-1:0]    binary_in,
    output logic [WIDTH-1:0]    binary_out,
    output logic [WIDTH-1:0]    gray_out,
    output logic [WIDTH-1:0]    gray_in_out   // Pre-sync Gray code of binary_in
);

    // Convert input binary to Gray
    logic [WIDTH-1:0] gray_in;

    cdc_gray_conv #(.WIDTH(WIDTH)) u_bin2gray (
        .binary_in  (binary_in),
        .gray_out   (gray_in),
        .gray_in    ({WIDTH{1'b0}}),  // Unused gray-to-bin direction
        .binary_out ()                // Unused
    );

    // Expose the pre-sync Gray code
    assign gray_in_out = gray_in;

    // Synchronize each Gray bit independently
    logic [WIDTH-1:0] gray_sync;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : gen_cdc_bits
            cdc_bit #(
                .SYNC_STAGES (SYNC_STAGES),
                .RESET_VALUE (1'b0)
            ) u_sync (
                .clk      (clk),
                .rst_n    (rst_n),
                .async_in (gray_in[i]),
                .sync_out (gray_sync[i])
            );
        end
    endgenerate

    // Convert synchronized Gray back to binary
    cdc_gray_conv #(.WIDTH(WIDTH)) u_gray2bin (
        .binary_in  ({WIDTH{1'b0}}),  // Unused bin-to-gray direction
        .gray_out   (),               // Unused
        .gray_in    (gray_sync),
        .binary_out (binary_out)
    );

    // Expose synchronized Gray code
    assign gray_out = gray_sync;

endmodule
