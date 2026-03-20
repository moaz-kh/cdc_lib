# fpga_cdc_lib

A reusable, parameterized **Clock Domain Crossing (CDC)** synchronizer library in SystemVerilog. Provides 7 hierarchical modules covering the most common CDC patterns in FPGA design — from single-bit synchronization to a full async FIFO.

All modules are verified with self-checking testbenches and pass iCE40 synthesis (Yosys).

## Module Hierarchy

```
cdc_bit               single-bit N-stage synchronizer (leaf)
cdc_reset             async assert, sync deassert reset synchronizer
cdc_gray_conv         combinational binary <-> Gray code converter
  |
cdc_pulse             pulse synchronizer (toggle or counter mode)
  |--- MODE=0 -------> uses cdc_bit
  |--- MODE=1 -------> uses cdc_counter
  |
cdc_counter           counter synchronizer (Gray code internally)
  |--------------------uses cdc_bit x WIDTH
  |--------------------uses cdc_gray_conv x 2
  |
cdc_handshake     handshake-based multi-bit bus synchronizer
  |--------------------uses cdc_bit x 2
  |
cdc_fifo          small async FIFO (Cummings-style)
  |--------------------uses cdc_counter x 2
  |--------------------uses cdc_gray_conv x 2
```

## Modules

### cdc_bit

N-stage single-bit synchronizer. The fundamental CDC building block.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SYNC_STAGES` | 2 | Number of synchronizer flip-flops |
| `RESET_VALUE` | 1'b0 | Value held during reset and power-up |

```
clk, rst_n, async_in --> [FF]-[FF]-..--> sync_out
                          ^  ASYNC_REG
```

### cdc_reset

Reset synchronizer with **async assert, synchronous deassert**. Active-low. This is the one valid use of async reset in FPGA design.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SYNC_STAGES` | 2 | Deassert latency in clock cycles |

```
async_rst_n --|>-- [FF]-[FF]--> sync_rst_n
               ^
          assert: instant (async)
          deassert: SYNC_STAGES clocks (sync)
```

### cdc_gray_conv

Purely combinational binary-to-Gray and Gray-to-binary converter. Both directions available simultaneously in a single instance.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 4 | Data width |

```
binary_in[WIDTH-1:0] --> gray_out[WIDTH-1:0]
gray_in[WIDTH-1:0]   --> binary_out[WIDTH-1:0]
```

### cdc_pulse

Transfers pulses across clock domains. Two compile-time selectable architectures:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SYNC_STAGES` | 2 | Synchronizer depth |
| `MODE` | 0 | 0 = toggle, 1 = counter |
| `CTR_WIDTH` | 4 | Counter width (MODE=1 only) |

**MODE=0 (toggle)** — Lightweight. Toggles a FF on each src pulse, syncs the level, edge-detects in dst. Requires spacing between consecutive pulses (at least `2*SYNC_STAGES + 1` dst clocks).

**MODE=1 (counter)** — Counts pulses in src, syncs the counter via `cdc_counter`, and generates matching pulses in dst. Guarantees **N pulses in = N pulses out**, even with back-to-back bursts. More logic, but handles any pulse rate the src can produce.

### cdc_counter

Synchronizes a binary counter value across clock domains using Gray code internally. Accepts binary, outputs binary — the Gray encoding is transparent to the user.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 4 | Counter width |
| `SYNC_STAGES` | 2 | Synchronizer depth per bit |

| Port | Direction | Description |
|------|-----------|-------------|
| `binary_in` | in | Binary counter value from source domain |
| `binary_out` | out | Synchronized binary value in destination domain |
| `gray_out` | out | Synchronized Gray code (post-sync) |
| `gray_in_out` | out | Pre-sync Gray code of `binary_in` (useful for local FIFO comparisons) |

### cdc_handshake

Transfers multi-bit data across clock domains using a four-phase toggle handshake. Provides back-pressure via `src_ready`.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 8 | Data bus width |
| `SYNC_STAGES` | 2 | Synchronizer depth |

```
src domain                              dst domain
                    req (cdc_bit)
src_data --|hold|-- ~~~~~~~~~~~~~~~~ --> dst_data
src_valid ->        <~~~~~~~~~~~~~~~~ -- dst_valid
src_ready <-          ack (cdc_bit)
```

One transfer at a time. `src_ready` deasserts during transfer and reasserts after the ack round-trip.

### cdc_fifo

Small asynchronous FIFO for streaming data across clock domains. Cummings-style Gray-coded pointer design using `cdc_counter` for pointer synchronization.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 8 | Data width |
| `DEPTH` | 4 | FIFO depth (must be power of 2) |
| `SYNC_STAGES` | 2 | Pointer synchronizer depth |

```
wr_clk domain              rd_clk domain
wr_data -->[  memory  ]--> rd_data
wr_en   -->[ wr | rd  ]--> rd_en
full    <--[ ptr  ptr ]<-- empty
```

Register-array memory with combinational read. Supports concurrent read/write at full throughput.

## Quick Start

```bash
# Check tools are installed
make check-tools

# Update file list (required after cloning)
make update_list

# Run all tests
make sim TOP_MODULE=cdc_bit            TESTBENCH=cdc_bit_tb
make sim TOP_MODULE=cdc_reset          TESTBENCH=cdc_reset_tb
make sim TOP_MODULE=cdc_gray_conv      TESTBENCH=cdc_gray_conv_tb
make sim TOP_MODULE=cdc_pulse          TESTBENCH=cdc_pulse_tb
make sim TOP_MODULE=cdc_counter        TESTBENCH=cdc_counter_tb
make sim TOP_MODULE=cdc_handshake  TESTBENCH=cdc_handshake_tb
make sim TOP_MODULE=cdc_fifo       TESTBENCH=cdc_fifo_tb

# Synthesize any module for iCE40
make synth-ice40 TOP_MODULE=cdc_fifo

# View waveforms after simulation
make waves TOP_MODULE=cdc_bit TESTBENCH=cdc_bit_tb
```

All testbenches are self-checking and print `*** TEST PASSED ***` or `*** TEST FAILED ***`.

## Usage Examples

```systemverilog
// Synchronize a single-bit signal
cdc_bit #(.SYNC_STAGES(3)) u_sync (
    .clk      (dst_clk),
    .rst_n    (dst_rst_n),
    .async_in (signal_from_other_domain),
    .sync_out (synchronized_signal)
);

// Synchronize reset with clean deassert
cdc_reset #(.SYNC_STAGES(3)) u_rst_sync (
    .clk         (sys_clk),
    .async_rst_n (pll_locked),
    .sync_rst_n  (sys_rst_n)
);

// Transfer pulses (counter mode — burst safe)
cdc_pulse #(.MODE(1), .CTR_WIDTH(8)) u_irq_sync (
    .src_clk   (periph_clk), .src_rst_n (periph_rst_n), .src_pulse (irq_pulse),
    .dst_clk   (cpu_clk),    .dst_rst_n (cpu_rst_n),    .dst_pulse (irq_synced)
);

// Transfer a register value with handshake
cdc_handshake #(.WIDTH(32)) u_cfg_sync (
    .src_clk   (cfg_clk),  .src_rst_n (cfg_rst_n),
    .src_data  (cfg_data),  .src_valid (cfg_valid),  .src_ready (cfg_ready),
    .dst_clk   (core_clk), .dst_rst_n (core_rst_n),
    .dst_data  (cfg_synced), .dst_valid (cfg_synced_valid)
);

// Stream data across clock domains
cdc_fifo #(.WIDTH(16), .DEPTH(8)) u_stream_fifo (
    .wr_clk   (adc_clk),  .wr_rst_n (adc_rst_n),
    .wr_en    (sample_valid), .wr_data (sample_data), .full (fifo_full),
    .rd_clk   (proc_clk), .rd_rst_n (proc_rst_n),
    .rd_en    (read_en),     .rd_data (proc_data),   .empty (fifo_empty)
);
```

## Design Conventions

- **`(* ASYNC_REG = "TRUE" *)`** on all synchronizer registers for correct FPGA placement
- **`initial` blocks** for FPGA power-up values
- **Synchronous reset** everywhere except `cdc_reset` (async by design)
- **`always_ff`** for sequential logic, **`always_comb`** for combinational
- **Parameterized** — all widths, depths, and sync stages are configurable
- **No vendor primitives** — portable across Lattice, Xilinx, Intel, etc.

## Directory Structure

```
fpga_cdc_lib/
├── sources/
│   │   ├── cdc_bit.sv
│   │   ├── cdc_reset.sv
│   │   ├── cdc_gray_conv.sv
│   │   ├── cdc_pulse.sv
│   │   ├── cdc_counter.sv
│   │   ├── cdc_handshake.sv
│   │   ├── cdc_fifo.sv
│   ├── tb/                          # 7 self-checking testbenches
│   ├── include/
│   └── constraints/
├── sim/
│   ├── waves/                       # VCD waveform dumps
│   └── logs/
├── backend/
│   ├── synth/                       # Yosys synthesis outputs
│   ├── pnr/                         # Place & route outputs
│   ├── bitstream/
│   └── reports/
├── docs/
│   └── IMPLEMENTATION_PLAN.md
├── Makefile                         # Build system (sim, synth, PnR, bitstream)
└── README.md
```

## Tools

| Tool | Purpose | Install |
|------|---------|---------|
| Icarus Verilog | Simulation | `sudo apt install iverilog` |
| GTKWave | Waveform viewer | `sudo apt install gtkwave` |
| Yosys | Synthesis | `sudo apt install yosys` |
| NextPNR | Place & route (optional) | `sudo apt install nextpnr-ice40` |

## Status

| Module | Simulation | Synthesis (iCE40) |
|--------|------------|-------------------|
| cdc_bit | PASS | PASS |
| cdc_reset | PASS | PASS |
| cdc_gray_conv | PASS | PASS |
| cdc_pulse (toggle) | PASS | PASS |
| cdc_pulse (counter) | PASS | PASS |
| cdc_counter | PASS | PASS |
| cdc_handshake | PASS | PASS |
| cdc_fifo | PASS | PASS |

## License

This project is part of an FPGA design portfolio. See repository root for license details.
