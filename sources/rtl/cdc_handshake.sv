// cdc_handshake.sv — Handshake-Based Bus Synchronizer
// Four-phase toggle handshake for safe multi-bit data transfer across
// clock domains. Data is held stable in a holding register while
// req/ack toggles cross domains via cdc_bit.

`include "cdc_config.svh"

module cdc_handshake #(
    parameter int WIDTH       = 8,
    parameter int SYNC_STAGES = 2
) (
    // Source domain
    input  logic               i_src_clk,
    input  logic               i_src_rst_n,
    input  logic [WIDTH-1:0]   i_src_data,
    input  logic               i_src_valid,
    output logic               o_src_ready,

    // Destination domain
    input  logic               i_dst_clk,
    input  logic               i_dst_rst_n,
    output logic [WIDTH-1:0]   o_dst_data,
    output logic               o_dst_valid
);

    // All signal declarations up front (iverilog requires declaration before use)
    // Source domain signals
    logic               req_toggle;
    logic               ack_sync;
    logic [WIDTH-1:0]   data_hold;
    logic               busy;

    // Destination domain signals
    logic               req_sync;
    logic               ack_toggle;
    logic               req_sync_prev;

    `ifndef CDC_ASYNC_RESET
    initial begin
        req_toggle    = 1'b0;
        data_hold     = '0;
        busy          = 1'b0;
        ack_toggle    = 1'b0;
        req_sync_prev = 1'b0;
        o_dst_data    = '0;
        o_dst_valid   = 1'b0;
    end
    `endif

    // --- Source domain ---

    // Synchronize ack back to source domain
    cdc_bit #(
        .SYNC_STAGES (SYNC_STAGES),
        .RESET_VALUE (1'b0)
    ) u_sync_ack (
        .i_clk      (i_src_clk),
        .i_rst_n    (i_src_rst_n),
        .i_async_in (ack_toggle),
        .o_sync_out (ack_sync)
    );

    // Source logic: capture data and toggle req on accepted transfer
    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_src_clk or negedge i_src_rst_n) begin
    `else
    always_ff @(posedge i_src_clk) begin
    `endif
        if (!i_src_rst_n) begin
            req_toggle <= 1'b0;
            data_hold  <= '0;
            busy       <= 1'b0;
        end else begin
            if (i_src_valid && o_src_ready) begin
                data_hold  <= i_src_data;
                req_toggle <= ~req_toggle;
                busy       <= 1'b1;
            end else if (busy && (ack_sync == req_toggle)) begin
                busy <= 1'b0;
            end
        end
    end

    // o_src_ready is combinational: high whenever not busy
    assign o_src_ready = ~busy;


    // --- Destination domain ---

    // Synchronize req to destination domain
    cdc_bit #(
        .SYNC_STAGES (SYNC_STAGES),
        .RESET_VALUE (1'b0)
    ) u_sync_req (
        .i_clk      (i_dst_clk),
        .i_rst_n    (i_dst_rst_n),
        .i_async_in (req_toggle),
        .o_sync_out (req_sync)
    );

    // Destination logic: detect req change, capture data, ack
    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_dst_clk or negedge i_dst_rst_n) begin
    `else
    always_ff @(posedge i_dst_clk) begin
    `endif
        if (!i_dst_rst_n) begin
            ack_toggle    <= 1'b0;
            req_sync_prev <= 1'b0;
            o_dst_data    <= '0;
            o_dst_valid   <= 1'b0;
        end else begin
            o_dst_valid   <= 1'b0;
            req_sync_prev <= req_sync;

            if (req_sync != req_sync_prev) begin
                o_dst_data  <= data_hold;
                o_dst_valid <= 1'b1;
                ack_toggle  <= req_sync;
            end
        end
    end

endmodule
