// cdc_reset.sv — Reset Synchronizer
// Async assert, synchronous deassert reset synchronizer.
// This is the one valid use of async reset in FPGA design.
// Active-low reset: async_rst_n=0 asserts instantly, deasserts after SYNC_STAGES clocks.

module cdc_reset #(
    parameter int SYNC_STAGES = 2
) (
    input  logic clk,
    input  logic async_rst_n,    // Active-low async reset input
    output logic sync_rst_n      // Active-low synchronized reset output
);

    (* ASYNC_REG = "TRUE" *)
    logic [SYNC_STAGES-1:0] rst_chain;

    initial begin
        rst_chain = {SYNC_STAGES{1'b1}};  // Power-up in reset
    end

    // Async assert (immediate on rst_n=0), sync deassert (after SYNC_STAGES clocks)
    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n)
            rst_chain <= {SYNC_STAGES{1'b1}};
        else
            rst_chain <= {rst_chain[SYNC_STAGES-2:0], 1'b0};
    end

    assign sync_rst_n = ~rst_chain[SYNC_STAGES-1];

endmodule
