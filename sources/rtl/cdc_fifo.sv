//-----------------------------------------------------------------------------
// Module : cdc_fifo
// Purpose: Async FIFO with Cummings-style Gray-code pointer synchronization.
//          Binary pointer and its Gray code are registered together in the
//          source domain on the same clock edge, so the synchronizer input is
//          always a stable FF output — no combinational glitches at CDC boundary.
// Author : <author>
// Date   : <date>
//-----------------------------------------------------------------------------
`default_nettype none

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

    localparam int PTR_WIDTH = ADDR_WIDTH + 1;

    // -------------------------------------------------------------------------
    // All signal declarations up front — iverilog requires declaration before use
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0]    mem [0:DEPTH-1];

    // Write domain
    logic [PTR_WIDTH-1:0] wr_ptr_r;
    logic [PTR_WIDTH-1:0] wr_ptr_nxt;
    logic [PTR_WIDTH-1:0] wr_ptr_gray_r;    // registered Gray of wr_ptr (wr_clk)
    logic [PTR_WIDTH-1:0] rd_ptr_gray_sync; // synchronized rd Gray (in wr_clk domain)

    // Read domain
    logic [PTR_WIDTH-1:0] rd_ptr_r;
    logic [PTR_WIDTH-1:0] rd_ptr_nxt;
    logic [PTR_WIDTH-1:0] rd_ptr_gray_r;    // registered Gray of rd_ptr (rd_clk)
    logic [PTR_WIDTH-1:0] wr_ptr_gray_sync; // synchronized wr Gray (in rd_clk domain)

    initial begin
        wr_ptr_r      = '0;
        wr_ptr_gray_r = '0;
        rd_ptr_r      = '0;
        rd_ptr_gray_r = '0;
    end

    // -------------------------------------------------------------------------
    // Write domain — pointer and Gray registration
    // -------------------------------------------------------------------------
    assign wr_ptr_nxt = (wr_en && !full) ? wr_ptr_r + 1'b1 : wr_ptr_r;

    // Binary and Gray advance together — Gray is always in sync with binary,
    // and wr_ptr_gray_r is a stable FF output ready for the CDC synchronizer.
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_r      <= '0;
            wr_ptr_gray_r <= '0;
        end else begin
            wr_ptr_r      <= wr_ptr_nxt;
            wr_ptr_gray_r <= wr_ptr_nxt ^ (wr_ptr_nxt >> 1);
        end
    end

    always_ff @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wr_ptr_r[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // Synchronize rd_ptr_gray_r (rd_clk domain) into wr_clk domain
    cdc_gray_sync #(
        .WIDTH       (PTR_WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_rd_ptr_sync (
        .clk      (wr_clk),
        .rst_n    (wr_rst_n),
        .gray_in  (rd_ptr_gray_r),
        .gray_out (rd_ptr_gray_sync)
    );

    // Full: top two MSBs of local and synced Gray differ; remaining bits match.
    // Requires PTR_WIDTH >= 3 (DEPTH >= 4).
    assign full = (wr_ptr_gray_r[PTR_WIDTH-1]   != rd_ptr_gray_sync[PTR_WIDTH-1]) &&
                  (wr_ptr_gray_r[PTR_WIDTH-2]   != rd_ptr_gray_sync[PTR_WIDTH-2]) &&
                  (wr_ptr_gray_r[PTR_WIDTH-3:0] == rd_ptr_gray_sync[PTR_WIDTH-3:0]);

    // -------------------------------------------------------------------------
    // Read domain — pointer and Gray registration
    // -------------------------------------------------------------------------
    assign rd_ptr_nxt = (rd_en && !empty) ? rd_ptr_r + 1'b1 : rd_ptr_r;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_r      <= '0;
            rd_ptr_gray_r <= '0;
        end else begin
            rd_ptr_r      <= rd_ptr_nxt;
            rd_ptr_gray_r <= rd_ptr_nxt ^ (rd_ptr_nxt >> 1);
        end
    end

    // Combinational read — data available the cycle rd_ptr_r is valid
    assign rd_data = mem[rd_ptr_r[ADDR_WIDTH-1:0]];

    // Synchronize wr_ptr_gray_r (wr_clk domain) into rd_clk domain
    cdc_gray_sync #(
        .WIDTH       (PTR_WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_wr_ptr_sync (
        .clk      (rd_clk),
        .rst_n    (rd_rst_n),
        .gray_in  (wr_ptr_gray_r),
        .gray_out (wr_ptr_gray_sync)
    );

    // Empty: local rd Gray equals synchronized wr Gray
    assign empty = (rd_ptr_gray_r == wr_ptr_gray_sync);

endmodule

`default_nettype wire
