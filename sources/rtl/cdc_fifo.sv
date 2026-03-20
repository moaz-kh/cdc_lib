// cdc_fifo.sv — Small Async FIFO Bus Synchronizer
// Cummings-style async FIFO using cdc_counter for pointer synchronization.
// Small register-array memory with combinational read.

module cdc_fifo #(
    parameter int WIDTH       = 8,
    parameter int DEPTH       = 4,
    parameter int SYNC_STAGES = 2,
    // Derived
    parameter int ADDR_WIDTH  = $clog2(DEPTH)
) (
    // Write domain
    input  logic                wr_clk,
    input  logic                wr_rst_n,
    input  logic                wr_en,
    input  logic [WIDTH-1:0]    wr_data,
    output logic                full,

    // Read domain
    input  logic                rd_clk,
    input  logic                rd_rst_n,
    input  logic                rd_en,
    output logic [WIDTH-1:0]    rd_data,
    output logic                empty
);

    // Pointer width is ADDR_WIDTH+1 to distinguish full from empty
    localparam int PTR_WIDTH = ADDR_WIDTH + 1;

    // --- All signal declarations up front (iverilog requires declaration before use) ---
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // Write domain signals
    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr_sync;
    logic [PTR_WIDTH-1:0] rd_ptr_gray_sync;
    logic [PTR_WIDTH-1:0] wr_ptr_gray;

    // Read domain signals
    logic [PTR_WIDTH-1:0] rd_ptr;
    logic [PTR_WIDTH-1:0] wr_ptr_sync;
    logic [PTR_WIDTH-1:0] wr_ptr_gray_sync;
    logic [PTR_WIDTH-1:0] rd_ptr_gray;

    initial begin
        wr_ptr = '0;
        rd_ptr = '0;
    end

    // --- Write domain ---

    always_ff @(posedge wr_clk) begin
        if (!wr_rst_n)
            wr_ptr <= '0;
        else if (wr_en && !full)
            wr_ptr <= wr_ptr + 1'b1;
    end

    always_ff @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // Synchronize read pointer to write domain
    cdc_counter #(
        .WIDTH       (PTR_WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_rd_ptr_sync (
        .clk         (wr_clk),
        .rst_n       (wr_rst_n),
        .binary_in   (rd_ptr),
        .binary_out  (rd_ptr_sync),
        .gray_out    (rd_ptr_gray_sync),
        .gray_in_out ()
    );

    // Local wr_ptr Gray for full comparison
    cdc_gray_conv #(.WIDTH(PTR_WIDTH)) u_wr_gray (
        .binary_in  (wr_ptr),
        .gray_out   (wr_ptr_gray),
        .gray_in    ({PTR_WIDTH{1'b0}}),
        .binary_out ()
    );

    // Full detection: Gray code comparison
    // Full when top 2 MSBs differ and remaining bits match
    assign full = (wr_ptr_gray[PTR_WIDTH-1]   != rd_ptr_gray_sync[PTR_WIDTH-1]) &&
                  (wr_ptr_gray[PTR_WIDTH-2]   != rd_ptr_gray_sync[PTR_WIDTH-2]) &&
                  (wr_ptr_gray[PTR_WIDTH-3:0] == rd_ptr_gray_sync[PTR_WIDTH-3:0]);

    // --- Read domain ---

    always_ff @(posedge rd_clk) begin
        if (!rd_rst_n)
            rd_ptr <= '0;
        else if (rd_en && !empty)
            rd_ptr <= rd_ptr + 1'b1;
    end

    // Combinational read
    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

    // Synchronize write pointer to read domain
    cdc_counter #(
        .WIDTH       (PTR_WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_wr_ptr_sync (
        .clk         (rd_clk),
        .rst_n       (rd_rst_n),
        .binary_in   (wr_ptr),
        .binary_out  (wr_ptr_sync),
        .gray_out    (wr_ptr_gray_sync),
        .gray_in_out ()
    );

    // Local rd_ptr Gray for empty comparison
    cdc_gray_conv #(.WIDTH(PTR_WIDTH)) u_rd_gray (
        .binary_in  (rd_ptr),
        .gray_out   (rd_ptr_gray),
        .gray_in    ({PTR_WIDTH{1'b0}}),
        .binary_out ()
    );

    // Empty detection: read Gray == synchronized write Gray
    assign empty = (rd_ptr_gray == wr_ptr_gray_sync);

endmodule
