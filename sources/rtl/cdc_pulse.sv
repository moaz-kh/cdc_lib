// cdc_pulse.sv — Pulse Synchronizer
// Two modes selectable via MODE parameter:
//   MODE=0 (TOGGLE): Toggle-based — src_pulse toggles a FF, level crosses via
//                     cdc_bit, edge detect in dst produces single-cycle pulse.
//                     Lightweight, but back-to-back pulses must be spaced apart.
//   MODE=1 (COUNTER): Counter-based — counts pulses in src domain, syncs counter
//                      to dst domain via cdc_counter, dst generates pulses to
//                      match. Guarantees N-in = N-out even with bursts.

module cdc_pulse_toggle #(
    parameter int SYNC_STAGES = 2
) (
    input  logic src_clk,
    input  logic src_rst_n,
    input  logic src_pulse,
    input  logic dst_clk,
    input  logic dst_rst_n,
    output logic dst_pulse
);

    logic toggle_src;
    logic toggle_dst;
    logic toggle_dst_prev;

    initial begin
        toggle_src      = 1'b0;
        toggle_dst_prev = 1'b0;
    end

    always_ff @(posedge src_clk) begin
        if (!src_rst_n)
            toggle_src <= 1'b0;
        else if (src_pulse)
            toggle_src <= ~toggle_src;
    end

    cdc_bit #(
        .SYNC_STAGES (SYNC_STAGES),
        .RESET_VALUE (1'b0)
    ) u_sync_toggle (
        .clk      (dst_clk),
        .rst_n    (dst_rst_n),
        .async_in (toggle_src),
        .sync_out (toggle_dst)
    );

    always_ff @(posedge dst_clk) begin
        if (!dst_rst_n)
            toggle_dst_prev <= 1'b0;
        else
            toggle_dst_prev <= toggle_dst;
    end

    assign dst_pulse = toggle_dst ^ toggle_dst_prev;

endmodule


module cdc_pulse_counter #(
    parameter int SYNC_STAGES = 2,
    parameter int CTR_WIDTH   = 4
) (
    input  logic src_clk,
    input  logic src_rst_n,
    input  logic src_pulse,
    input  logic dst_clk,
    input  logic dst_rst_n,
    output logic dst_pulse
);

    logic [CTR_WIDTH-1:0] src_count;
    logic [CTR_WIDTH-1:0] dst_count_sync;
    logic [CTR_WIDTH-1:0] dst_count_local;

    initial begin
        src_count       = '0;
        dst_count_local = '0;
    end

    always_ff @(posedge src_clk) begin
        if (!src_rst_n)
            src_count <= '0;
        else if (src_pulse)
            src_count <= src_count + 1'b1;
    end

    cdc_counter #(
        .WIDTH       (CTR_WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_sync_count (
        .clk         (dst_clk),
        .rst_n       (dst_rst_n),
        .binary_in   (src_count),
        .binary_out  (dst_count_sync),
        .gray_out    (),
        .gray_in_out ()
    );

    // Generate one pulse per count difference
    always_ff @(posedge dst_clk) begin
        if (!dst_rst_n)
            dst_count_local <= '0;
        else if (dst_count_local != dst_count_sync)
            dst_count_local <= dst_count_local + 1'b1;
    end

    assign dst_pulse = (dst_count_local != dst_count_sync);

endmodule


// Top-level wrapper — instantiates one mode based on MODE parameter
module cdc_pulse #(
    parameter int SYNC_STAGES = 2,
    parameter int MODE        = 0,       // 0 = toggle, 1 = counter
    parameter int CTR_WIDTH   = 4        // Counter width for MODE=1
) (
    input  logic src_clk,
    input  logic src_rst_n,
    input  logic src_pulse,
    input  logic dst_clk,
    input  logic dst_rst_n,
    output logic dst_pulse
);

generate
    if (MODE == 0) begin : gen_toggle
        cdc_pulse_toggle #(
            .SYNC_STAGES (SYNC_STAGES)
        ) u_impl (
            .src_clk   (src_clk),
            .src_rst_n (src_rst_n),
            .src_pulse (src_pulse),
            .dst_clk   (dst_clk),
            .dst_rst_n (dst_rst_n),
            .dst_pulse (dst_pulse)
        );
    end else begin : gen_counter
        cdc_pulse_counter #(
            .SYNC_STAGES (SYNC_STAGES),
            .CTR_WIDTH   (CTR_WIDTH)
        ) u_impl (
            .src_clk   (src_clk),
            .src_rst_n (src_rst_n),
            .src_pulse (src_pulse),
            .dst_clk   (dst_clk),
            .dst_rst_n (dst_rst_n),
            .dst_pulse (dst_pulse)
        );
    end
endgenerate

endmodule
