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
`include "cdc_config.svh"

module cdc_fifo #(
    parameter int WIDTH       = 8,
    parameter int DEPTH       = 4,
    parameter int SYNC_STAGES = 2,
    // Derived
    parameter int ADDR_WIDTH  = $clog2(DEPTH)
) (
    // Write domain
    input  logic                i_wr_clk,
    input  logic                i_wr_rst_n,
    input  logic                i_wr_en,
    input  logic [WIDTH-1:0]    i_wr_data,
    output logic                o_full,

    // Read domain
    input  logic                i_rd_clk,
    input  logic                i_rd_rst_n,
    input  logic                i_rd_en,
    output logic [WIDTH-1:0]    o_rd_data,
    output logic                o_empty
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

    `ifndef CDC_ASYNC_RESET
    initial begin
        wr_ptr_r      = '0;
        wr_ptr_gray_r = '0;
        rd_ptr_r      = '0;
        rd_ptr_gray_r = '0;
    end
    `endif

    // -------------------------------------------------------------------------
    // Write domain — pointer and Gray registration
    // -------------------------------------------------------------------------
    assign wr_ptr_nxt = (i_wr_en && !o_full) ? wr_ptr_r + 1'b1 : wr_ptr_r;

    // Binary and Gray advance together — Gray is always in sync with binary,
    // and wr_ptr_gray_r is a stable FF output ready for the CDC synchronizer.
    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_wr_clk or negedge i_wr_rst_n) begin
    `else
    always_ff @(posedge i_wr_clk) begin
    `endif
        if (!i_wr_rst_n) begin
            wr_ptr_r      <= '0;
            wr_ptr_gray_r <= '0;
        end else begin
            wr_ptr_r      <= wr_ptr_nxt;
            wr_ptr_gray_r <= wr_ptr_nxt ^ (wr_ptr_nxt >> 1);
        end
    end

    always_ff @(posedge i_wr_clk) begin
        if (i_wr_en && !o_full)
            mem[wr_ptr_r[ADDR_WIDTH-1:0]] <= i_wr_data;
    end

    // Synchronize rd_ptr_gray_r (rd_clk domain) into wr_clk domain
    cdc_gray_sync #(
        .WIDTH       (PTR_WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_rd_ptr_sync (
        .i_clk   (i_wr_clk),
        .i_rst_n (i_wr_rst_n),
        .i_gray  (rd_ptr_gray_r),
        .o_gray  (rd_ptr_gray_sync)
    );

    // Full: top two MSBs of local and synced Gray differ; remaining bits match.
    // Requires PTR_WIDTH >= 3 (DEPTH >= 4).
    assign o_full = (wr_ptr_gray_r[PTR_WIDTH-1]   != rd_ptr_gray_sync[PTR_WIDTH-1]) &&
                   (wr_ptr_gray_r[PTR_WIDTH-2]   != rd_ptr_gray_sync[PTR_WIDTH-2]) &&
                   (wr_ptr_gray_r[PTR_WIDTH-3:0] == rd_ptr_gray_sync[PTR_WIDTH-3:0]);

    // -------------------------------------------------------------------------
    // Read domain — pointer and Gray registration
    // -------------------------------------------------------------------------
    assign rd_ptr_nxt = (i_rd_en && !o_empty) ? rd_ptr_r + 1'b1 : rd_ptr_r;

    `ifdef CDC_ASYNC_RESET
    always_ff @(posedge i_rd_clk or negedge i_rd_rst_n) begin
    `else
    always_ff @(posedge i_rd_clk) begin
    `endif
        if (!i_rd_rst_n) begin
            rd_ptr_r      <= '0;
            rd_ptr_gray_r <= '0;
        end else begin
            rd_ptr_r      <= rd_ptr_nxt;
            rd_ptr_gray_r <= rd_ptr_nxt ^ (rd_ptr_nxt >> 1);
        end
    end

    // Combinational read — data available the cycle rd_ptr_r is valid
    assign o_rd_data = mem[rd_ptr_r[ADDR_WIDTH-1:0]];

    // Synchronize wr_ptr_gray_r (wr_clk domain) into rd_clk domain
    cdc_gray_sync #(
        .WIDTH       (PTR_WIDTH),
        .SYNC_STAGES (SYNC_STAGES)
    ) u_wr_ptr_sync (
        .i_clk   (i_rd_clk),
        .i_rst_n (i_rd_rst_n),
        .i_gray  (wr_ptr_gray_r),
        .o_gray  (wr_ptr_gray_sync)
    );

    // Empty: local rd Gray equals synchronized wr Gray
    assign o_empty = (rd_ptr_gray_r == wr_ptr_gray_sync);

endmodule

`default_nettype wire
