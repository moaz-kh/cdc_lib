//-----------------------------------------------------------------------------
// Module : cdc_counter
// Purpose: Self-contained CDC-safe binary counter. Owns the binary counter in
//          the source domain, registers the Gray code on the same clock edge,
//          then synchronizes to the destination domain via cdc_gray_sync.
//          Reusable primitive for credit counters, sequence numbers, etc.
// Author : <author>
// Date   : <date>
//-----------------------------------------------------------------------------
`default_nettype none
`include "cdc_config.svh"

module cdc_counter #(
    parameter int unsigned WIDTH       = 4,
    parameter int unsigned SYNC_STAGES = 2
) (
    // Source clock domain
    input  logic                i_src_clk,
    input  logic                i_src_rst_n,
    input  logic                i_count_up,
    input  logic                i_count_down,
    output logic [WIDTH-1:0]    o_src_count,   // binary count in source domain

    // Destination clock domain
    input  logic                i_dst_clk,
    input  logic                i_dst_rst_n,
    output logic [WIDTH-1:0]    o_dst_gray,    // synchronized Gray in dst domain
    output logic [WIDTH-1:0]    o_dst_count    // synchronized binary in dst domain
);

    // -------------------------------------------------------------------------
    // Source domain: binary counter and Gray registration
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] count_r;
    logic [WIDTH-1:0] count_nxt;
    logic [WIDTH-1:0] gray_r;

    always_comb begin
        if      (i_count_up   && !i_count_down) count_nxt = count_r + 1'b1;
        else if (i_count_down && !i_count_up)   count_nxt = count_r - 1'b1;
        else                                    count_nxt = count_r;
    end

    // Register binary and its Gray code in the same clock cycle — no extra
    // latency, and gray_r is always a stable FF output for the synchronizer.
    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_src_clk or negedge i_src_rst_n) begin
    `else
    always_ff @(posedge i_src_clk) begin
    `endif
        if (!i_src_rst_n) begin
            count_r <= '0;
            gray_r  <= '0;
        end else begin
            count_r <= count_nxt;
            gray_r  <= count_nxt ^ (count_nxt >> 1);
        end
    end

    assign o_src_count = count_r;

    // -------------------------------------------------------------------------
    // Synchronize registered Gray to destination domain
    // -------------------------------------------------------------------------
    cdc_gray_sync #(
        .WIDTH       (WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_gray_sync (
        .i_clk   (i_dst_clk),
        .i_rst_n (i_dst_rst_n),
        .i_gray  (gray_r),
        .o_gray  (o_dst_gray)
    );

    // Gray-to-binary for callers that need a binary value in the dst domain
    cdc_gray_conv #(.WIDTH(WIDTH)) u_gray2bin (
        .i_binary ('0),
        .o_gray   (),
        .i_gray   (o_dst_gray),
        .o_binary (o_dst_count)
    );

endmodule

`default_nettype wire
