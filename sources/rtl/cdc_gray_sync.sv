//-----------------------------------------------------------------------------
// Module : cdc_gray_sync
// Purpose: Bit-parallel synchronizer for a pre-registered Gray-code bus.
//          Instantiates one cdc_bit per bit, all clocked by the destination
//          clock. Caller must ensure gray_in is a registered flip-flop output
//          from the source clock domain — this module does not register it.
// Author : <author>
// Date   : <date>
//-----------------------------------------------------------------------------
`default_nettype none

module cdc_gray_sync #(
    parameter int unsigned WIDTH       = 4,
    parameter int unsigned SYNC_STAGES = 2
) (
    // Destination clock domain
    input  logic                clk,
    input  logic                rst_n,

    // Data — gray_in must be a registered output from the source domain
    input  logic [WIDTH-1:0]    gray_in,
    output logic [WIDTH-1:0]    gray_out
);

    for (genvar i = 0; i < WIDTH; i++) begin : gen_sync_bits
        cdc_bit #(
            .SYNC_STAGES (SYNC_STAGES),
            .RESET_VALUE (1'b0)
        ) u_sync (
            .clk      (clk),
            .rst_n    (rst_n),
            .async_in (gray_in[i]),
            .sync_out (gray_out[i])
        );
    end

endmodule

`default_nettype wire
