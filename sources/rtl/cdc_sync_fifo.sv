// cdc_sync_fifo.sv — Single-Clock Synchronous FIFO
// Simple FIFO for same-clock-domain buffering.
// Supports registered read (default) or FWFT mode via parameter.

module cdc_sync_fifo #(
    parameter int WIDTH     = 8,
    parameter int DEPTH     = 16,
    parameter int FWFT_MODE = 0,
    // Derived
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic                clk,
    input  logic                rst_n,

    // Write interface
    input  logic                wr_en,
    input  logic [WIDTH-1:0]    wr_data,
    output logic                full,

    // Read interface
    input  logic                rd_en,
    output logic [WIDTH-1:0]    rd_data,
    output logic                empty,

    // Status
    output logic [ADDR_WIDTH:0] count
);

    localparam int PTR_WIDTH = ADDR_WIDTH;

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] rd_ptr;
    logic [ADDR_WIDTH:0]  fifo_count;

    logic wr_en_int, rd_en_int;

    initial begin
        wr_ptr     = '0;
        rd_ptr     = '0;
        fifo_count = '0;
    end

    assign wr_en_int = wr_en & ~full;
    assign rd_en_int = rd_en & ~empty;

    assign full  = (fifo_count == DEPTH[ADDR_WIDTH:0]);
    assign empty = (fifo_count == '0);
    assign count = fifo_count;

    // Write pointer and memory
    always_ff @(posedge clk) begin
        if (!rst_n)
            wr_ptr <= '0;
        else if (wr_en_int) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr      <= wr_ptr + 1'b1;
        end
    end

    // Read pointer and data path
    generate
        if (FWFT_MODE) begin : gen_fwft
            assign rd_data = mem[rd_ptr];

            always_ff @(posedge clk) begin
                if (!rst_n)
                    rd_ptr <= '0;
                else if (rd_en_int)
                    rd_ptr <= rd_ptr + 1'b1;
            end
        end else begin : gen_sync
            initial rd_data = '0;

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    rd_ptr  <= '0;
                    rd_data <= '0;
                end else if (rd_en_int) begin
                    rd_data <= mem[rd_ptr];
                    rd_ptr  <= rd_ptr + 1'b1;
                end
            end
        end
    endgenerate

    // Count management
    always_ff @(posedge clk) begin
        if (!rst_n)
            fifo_count <= '0;
        else begin
            case ({wr_en_int, rd_en_int})
                2'b01:   fifo_count <= fifo_count - 1'b1;
                2'b10:   fifo_count <= fifo_count + 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

endmodule
