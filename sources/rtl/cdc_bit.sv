// cdc_bit.sv — N-Stage Single-Bit Synchronizer
// Fundamental CDC building block: shift register of SYNC_STAGES flip-flops
// with ASYNC_REG attribute for proper FPGA placement.

module cdc_bit #(
    parameter int SYNC_STAGES = 2,
    parameter logic RESET_VALUE = 1'b0
) (
    input  logic clk,
    input  logic rst_n,
    input  logic async_in,
    output logic sync_out
);

    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-1:0] sync_chain;

    initial begin
        sync_chain = {SYNC_STAGES{RESET_VALUE}};
    end

    always_ff @(posedge clk) begin
        if (!rst_n)
            sync_chain <= {SYNC_STAGES{RESET_VALUE}};
        else
            sync_chain <= {sync_chain[SYNC_STAGES-2:0], async_in};
    end

    assign sync_out = sync_chain[SYNC_STAGES-1];

endmodule
