//-----------------------------------------------------------------------------
// Module : cdc_gray_sync
// Purpose: Bit-parallel synchronizer for a pre-registered Gray-code bus.
//          Instantiates one cdc_bit per bit, all clocked by the destination
//          clock. Caller must ensure i_gray is a registered flip-flop output
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
    input  logic                i_clk,
    input  logic                i_rst_n,

    // Data — i_gray must be a registered output from the source domain
    input  logic [WIDTH-1:0]    i_gray,
    output logic [WIDTH-1:0]    o_gray
);

    for (genvar i = 0; i < WIDTH; i++) begin : gen_sync_bits
        cdc_bit #(
            .SYNC_STAGES (SYNC_STAGES),
            .RESET_VALUE (1'b0)
        ) u_sync (
            .i_clk      (i_clk),
            .i_rst_n    (i_rst_n),
            .i_async_in (i_gray[i]),
            .o_sync_out (o_gray[i])
        );
    end

endmodule

`default_nettype wire
