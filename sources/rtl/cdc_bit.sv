// cdc_bit.sv — N-Stage Single-Bit Synchronizer
// Fundamental CDC building block: shift register of SYNC_STAGES flip-flops
// with ASYNC_REG attribute for proper FPGA placement.

`include "cdc_config.svh"

module cdc_bit #(
    parameter int   SYNC_STAGES = 2,
    parameter logic RESET_VALUE = 1'b0
) (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic i_async_in,
    output logic o_sync_out
);

    `ifndef CDC_ASYNC_RESET
    (* ASYNC_REG = "TRUE" *)
    `endif
    logic [SYNC_STAGES-1:0] sync_chain;

    `ifndef CDC_ASYNC_RESET
    initial begin
        sync_chain = {SYNC_STAGES{RESET_VALUE}};
    end
    `endif

    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_clk or negedge i_rst_n) begin
    `else
    always_ff @(posedge i_clk) begin
    `endif
        if (!i_rst_n)
            sync_chain <= {SYNC_STAGES{RESET_VALUE}};
        else
            sync_chain <= {sync_chain[SYNC_STAGES-2:0], i_async_in};
    end

    assign o_sync_out = sync_chain[SYNC_STAGES-1];

endmodule
