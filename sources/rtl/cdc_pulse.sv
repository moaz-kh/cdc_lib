// cdc_pulse.sv — Pulse Synchronizer
// Two modes selectable via MODE parameter:
//   MODE=0 (TOGGLE): Toggle-based — i_src_pulse toggles a FF, level crosses via
//                     cdc_bit, edge detect in dst produces single-cycle pulse.
//                     Lightweight, but back-to-back pulses must be spaced apart.
//   MODE=1 (COUNTER): Counter-based — delegates to cdc_counter which owns the
//                      pulse count in the src domain and synchronizes it to dst.
//                      dst generates pulses to match. Guarantees N-in = N-out.

`include "cdc_config.svh"

module cdc_pulse_toggle #(
    parameter int SYNC_STAGES = 2
) (
    input  logic i_src_clk,
    input  logic i_src_rst_n,
    input  logic i_src_pulse,
    input  logic i_dst_clk,
    input  logic i_dst_rst_n,
    output logic o_dst_pulse
);

    logic toggle_src;
    logic toggle_dst;
    logic toggle_dst_prev;

    `ifndef CDC_ASYNC_RESET
    initial begin
        toggle_src      = 1'b0;
        toggle_dst_prev = 1'b0;
    end
    `endif

    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_src_clk or negedge i_src_rst_n) begin
    `else
    always_ff @(posedge i_src_clk) begin
    `endif
        if (!i_src_rst_n)
            toggle_src <= 1'b0;
        else if (i_src_pulse)
            toggle_src <= ~toggle_src;
    end

    cdc_bit #(
        .SYNC_STAGES (SYNC_STAGES),
        .RESET_VALUE (1'b0)
    ) u_sync_toggle (
        .i_clk      (i_dst_clk),
        .i_rst_n    (i_dst_rst_n),
        .i_async_in (toggle_src),
        .o_sync_out (toggle_dst)
    );

    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_dst_clk or negedge i_dst_rst_n) begin
    `else
    always_ff @(posedge i_dst_clk) begin
    `endif
        if (!i_dst_rst_n)
            toggle_dst_prev <= 1'b0;
        else
            toggle_dst_prev <= toggle_dst;
    end

    assign o_dst_pulse = toggle_dst ^ toggle_dst_prev;

endmodule


module cdc_pulse_counter #(
    parameter int SYNC_STAGES = 2,
    parameter int CTR_WIDTH   = 4
) (
    input  logic i_src_clk,
    input  logic i_src_rst_n,
    input  logic i_src_pulse,
    input  logic i_dst_clk,
    input  logic i_dst_rst_n,
    output logic o_dst_pulse
);

    logic [CTR_WIDTH-1:0] dst_count_sync;
    logic [CTR_WIDTH-1:0] dst_count_local;
    logic                 dst_pulse_r;

    `ifndef CDC_ASYNC_RESET
    initial begin
        dst_count_local = '0;
        dst_pulse_r     = 1'b0;
    end
    `endif

    // cdc_counter owns the src-domain pulse count and synchronizes it to dst.
    cdc_counter #(
        .WIDTH       (CTR_WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_sync_count (
        .i_src_clk    (i_src_clk),
        .i_src_rst_n  (i_src_rst_n),
        .i_count_up   (i_src_pulse),
        .i_count_down (1'b0),
        .o_src_count  (),
        .i_dst_clk    (i_dst_clk),
        .i_dst_rst_n  (i_dst_rst_n),
        .o_dst_gray   (),
        .o_dst_count  (dst_count_sync)
    );

    // Generate one pulse per count difference: exactly 1 dst_clk wide,
    // mandatory 1-cycle gap between consecutive pulses (self-gating via dst_pulse_r).
    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_dst_clk or negedge i_dst_rst_n) begin
    `else
    always_ff @(posedge i_dst_clk) begin
    `endif
        if (!i_dst_rst_n) begin
            dst_count_local <= '0;
            dst_pulse_r     <= 1'b0;
        end else begin
            dst_pulse_r <= 1'b0;
            if (!dst_pulse_r && (dst_count_local != dst_count_sync)) begin
                dst_pulse_r     <= 1'b1;
                dst_count_local <= dst_count_local + 1'b1;
            end
        end
    end

    assign o_dst_pulse = dst_pulse_r;

endmodule


// Top-level wrapper — instantiates one mode based on MODE parameter
module cdc_pulse #(
    parameter int SYNC_STAGES = 2,
    parameter int MODE        = 0,       // 0 = toggle, 1 = counter
    parameter int CTR_WIDTH   = 4        // Counter width for MODE=1
) (
    input  logic i_src_clk,
    input  logic i_src_rst_n,
    input  logic i_src_pulse,
    input  logic i_dst_clk,
    input  logic i_dst_rst_n,
    output logic o_dst_pulse
);

generate
    if (MODE == 0) begin : gen_toggle
        cdc_pulse_toggle #(
            .SYNC_STAGES (SYNC_STAGES)
        ) u_impl (
            .i_src_clk    (i_src_clk),
            .i_src_rst_n  (i_src_rst_n),
            .i_src_pulse  (i_src_pulse),
            .i_dst_clk    (i_dst_clk),
            .i_dst_rst_n  (i_dst_rst_n),
            .o_dst_pulse  (o_dst_pulse)
        );
    end else begin : gen_counter
        cdc_pulse_counter #(
            .SYNC_STAGES (SYNC_STAGES),
            .CTR_WIDTH   (CTR_WIDTH)
        ) u_impl (
            .i_src_clk    (i_src_clk),
            .i_src_rst_n  (i_src_rst_n),
            .i_src_pulse  (i_src_pulse),
            .i_dst_clk    (i_dst_clk),
            .i_dst_rst_n  (i_dst_rst_n),
            .o_dst_pulse  (o_dst_pulse)
        );
    end
endgenerate

endmodule
