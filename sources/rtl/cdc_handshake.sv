// cdc_handshake.sv — Handshake-Based Bus Synchronizer
// Four-phase toggle handshake for safe multi-bit data transfer across
// clock domains. Data is held stable in a holding register while
// req/ack toggles cross domains via cdc_bit.

module cdc_handshake #(
    parameter int WIDTH       = 8,
    parameter int SYNC_STAGES = 2
) (
    // Source domain
    input  logic               src_clk,
    input  logic               src_rst_n,
    input  logic [WIDTH-1:0]   src_data,
    input  logic               src_valid,
    output logic               src_ready,

    // Destination domain
    input  logic               dst_clk,
    input  logic               dst_rst_n,
    output logic [WIDTH-1:0]   dst_data,
    output logic               dst_valid
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

    initial begin
        req_toggle    = 1'b0;
        data_hold     = '0;
        busy          = 1'b0;
        ack_toggle    = 1'b0;
        req_sync_prev = 1'b0;
        dst_data      = '0;
        dst_valid     = 1'b0;
    end

    // --- Source domain ---

    // Synchronize ack back to source domain
    cdc_bit #(
        .SYNC_STAGES (SYNC_STAGES),
        .RESET_VALUE (1'b0)
    ) u_sync_ack (
        .clk      (src_clk),
        .rst_n    (src_rst_n),
        .async_in (ack_toggle),
        .sync_out (ack_sync)
    );

    // Source logic: capture data and toggle req
    always_ff @(posedge src_clk) begin
        if (!src_rst_n) begin
            req_toggle <= 1'b0;
            data_hold  <= '0;
            busy       <= 1'b0;
        end else begin
            if (src_valid && src_ready) begin
                data_hold  <= src_data;
                req_toggle <= ~req_toggle;
                busy       <= 1'b1;
            end else if (busy && (ack_sync == req_toggle)) begin
                busy <= 1'b0;
            end
        end
    end

    assign src_ready = ~busy;

    // --- Destination domain ---

    // Synchronize req to destination domain
    cdc_bit #(
        .SYNC_STAGES (SYNC_STAGES),
        .RESET_VALUE (1'b0)
    ) u_sync_req (
        .clk      (dst_clk),
        .rst_n    (dst_rst_n),
        .async_in (req_toggle),
        .sync_out (req_sync)
    );

    // Destination logic: detect req change, capture data, ack
    always_ff @(posedge dst_clk) begin
        if (!dst_rst_n) begin
            ack_toggle    <= 1'b0;
            req_sync_prev <= 1'b0;
            dst_data      <= '0;
            dst_valid     <= 1'b0;
        end else begin
            dst_valid     <= 1'b0;
            req_sync_prev <= req_sync;

            if (req_sync != req_sync_prev) begin
                dst_data   <= data_hold;
                dst_valid  <= 1'b1;
                ack_toggle <= req_sync;
            end
        end
    end

endmodule
