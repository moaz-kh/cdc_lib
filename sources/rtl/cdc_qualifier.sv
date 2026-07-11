// cdc_qualifier.sv — Valid-Qualified Data Bus Synchronizer
// Synchronizes a level-held i_valid into the destination clock domain via
// cdc_bit, then uses the synchronized valid as a load-enable to capture
// i_data into a destination-domain register. Caller must hold both i_data
// and i_valid stable for at least SYNC_STAGES+1 i_clk cycles — long enough
// for the valid synchronizer to settle before data is sampled.
//
// o_data lags o_valid by one extra i_clk cycle: o_valid is itself a
// registered output of cdc_bit, so the load-enable it drives is only
// visible to this module's always_ff one cycle after o_valid appears to
// assert. Total latency from i_valid asserting to o_data updating is
// SYNC_STAGES+1 i_clk cycles.

`include "cdc_config.svh"

module cdc_qualifier #(
    parameter int unsigned WIDTH       = 8,
    parameter int unsigned SYNC_STAGES = 2
) (
    // Destination clock domain
    input  logic                i_clk,
    input  logic                i_rst_n,

    // Source domain — i_data must remain stable while i_valid is held high
    input  logic [WIDTH-1:0]    i_data,
    input  logic                i_valid,

    // Destination domain
    output logic [WIDTH-1:0]    o_data,
    output logic                o_valid
);

    // Level-held valid crosses the CDC boundary through the standard
    // single-bit synchronizer.
    cdc_bit #(
        .SYNC_STAGES (SYNC_STAGES),
        .RESET_VALUE (1'b0)
    ) u_sync_valid (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_async_in (i_valid),
        .o_sync_out (o_valid)
    );

    `ifndef CDC_ASYNC_RESET
    initial begin
        o_data = '0;
    end
    `endif

    // Capture i_data directly while the synchronized valid is asserted.
    // Safe because i_data is required to be stable for the whole window
    // o_valid is high, not just at a single edge.
    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_clk or negedge i_rst_n) begin
    `else
    always_ff @(posedge i_clk) begin
    `endif
        if (!i_rst_n) begin
            o_data <= '0;
        end else if (o_valid) begin
            o_data <= i_data;
        end
    end

endmodule
