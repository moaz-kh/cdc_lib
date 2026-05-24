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

module cdc_counter #(
    parameter int unsigned WIDTH       = 4,
    parameter int unsigned SYNC_STAGES = 2
) (
    // Source clock domain
    input  logic                src_clk,
    input  logic                src_rst_n,
    input  logic                count_up,
    input  logic                count_down,
    output logic [WIDTH-1:0]    src_count,   // binary count in source domain

    // Destination clock domain
    input  logic                dst_clk,
    input  logic                dst_rst_n,
    output logic [WIDTH-1:0]    dst_gray,    // synchronized Gray in dst domain
    output logic [WIDTH-1:0]    dst_count    // synchronized binary in dst domain
);

    // -------------------------------------------------------------------------
    // Source domain: binary counter and Gray registration
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] count_r;
    logic [WIDTH-1:0] count_nxt;
    logic [WIDTH-1:0] gray_r;

    always_comb begin
        if      (count_up   && !count_down) count_nxt = count_r + 1'b1;
        else if (count_down && !count_up)   count_nxt = count_r - 1'b1;
        else                                count_nxt = count_r;
    end

    // Register binary and its Gray code in the same clock cycle — no extra
    // latency, and gray_r is always a stable FF output for the synchronizer.
    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            count_r <= '0;
            gray_r  <= '0;
        end else begin
            count_r <= count_nxt;
            gray_r  <= count_nxt ^ (count_nxt >> 1);
        end
    end

    assign src_count = count_r;

    // -------------------------------------------------------------------------
    // Synchronize registered Gray to destination domain
    // -------------------------------------------------------------------------
    cdc_gray_sync #(
        .WIDTH       (WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_gray_sync (
        .clk      (dst_clk),
        .rst_n    (dst_rst_n),
        .gray_in  (gray_r),
        .gray_out (dst_gray)
    );

    // Gray-to-binary for callers that need a binary value in the dst domain
    cdc_gray_conv #(.WIDTH(WIDTH)) u_gray2bin (
        .binary_in  ('0),
        .gray_out   (),
        .gray_in    (dst_gray),
        .binary_out (dst_count)
    );

endmodule

`default_nettype wire
