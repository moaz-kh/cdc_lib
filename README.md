# cdc_lib

A reusable, parameterized **Clock Domain Crossing (CDC)** synchronizer library in SystemVerilog. Provides 9 hierarchical modules covering the most common CDC patterns — from single-bit synchronization to async and sync FIFOs.

All modules are verified with self-checking testbenches and pass iCE40 synthesis (Yosys). Supports both **FPGA** (sync reset, `initial` blocks) and **ASIC** (async reset, no `initial` blocks) flows via a single compile-time macro.

## Module Hierarchy

```
cdc_bit               single-bit N-stage synchronizer (leaf)
cdc_reset             async-assert / sync-deassert reset synchronizer (leaf)
cdc_gray_conv         combinational binary <-> Gray code converter (leaf)
cdc_gray_sync         bit-parallel Gray-code synchronizer
  |--------------------uses cdc_bit x WIDTH
  |
cdc_counter           self-contained CDC-safe binary counter
  |--------------------uses cdc_gray_sync
  |--------------------uses cdc_gray_conv
  |
cdc_handshake         handshake-based multi-bit bus synchronizer
  |--------------------uses cdc_bit x 2
  |
cdc_pulse             pulse synchronizer (toggle or counter mode)
  |--- MODE=0 -------> uses cdc_bit
  |--- MODE=1 -------> uses cdc_counter
  |
cdc_fifo              small async FIFO (Cummings-style)
  |--------------------uses cdc_gray_sync x 2
  |
cdc_sync_fifo         single-clock synchronous FIFO (standalone)
```

## Modules

### cdc_bit

N-stage single-bit synchronizer. The fundamental CDC building block.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SYNC_STAGES` | 2 | Number of synchronizer flip-flops |
| `RESET_VALUE` | 1'b0 | Value held during reset and power-up |

```
i_clk, i_rst_n, i_async_in --> [FF]-[FF]-..--> o_sync_out
                                 ^  ASYNC_REG (FPGA mode only)
```

### cdc_reset

Reset synchronizer with **async assert, synchronous deassert**. Active-low. This is the one module where async reset is always used regardless of the `CDC_ASYNC_RESET` macro.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SYNC_STAGES` | 2 | Deassert latency in clock cycles |

```
i_async_rst_n --|>-- [FF]-[FF]--> o_sync_rst_n
                ^
           assert: instant (async)
           deassert: SYNC_STAGES clocks (sync)
```

### cdc_gray_conv

Purely combinational binary-to-Gray and Gray-to-binary converter. Both directions available simultaneously in a single instance.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 4 | Data width |

### cdc_gray_sync

Bit-parallel synchronizer for a pre-registered Gray-code bus. Instantiates one `cdc_bit` per bus bit. The caller must ensure `i_gray` is a registered flip-flop output from the source domain.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 4 | Bus width |
| `SYNC_STAGES` | 2 | Synchronizer depth per bit |

### cdc_counter

Self-contained CDC-safe binary counter. Owns the source-domain counter, registers binary and Gray in the same clock cycle, and synchronizes to the destination domain via `cdc_gray_sync`.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 4 | Counter width |
| `SYNC_STAGES` | 2 | Synchronizer depth per bit |

| Port | Direction | Description |
|------|-----------|-------------|
| `i_count_up` | in | Increment counter by 1 (src domain) |
| `i_count_down` | in | Decrement counter by 1 (src domain) |
| `o_src_count` | out | Binary count in source domain |
| `o_dst_gray` | out | Synchronized Gray code in destination domain |
| `o_dst_count` | out | Synchronized binary count in destination domain |

### cdc_handshake

Transfers multi-bit data across clock domains using a four-phase toggle handshake. Provides back-pressure via `o_src_ready`.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 8 | Data bus width |
| `SYNC_STAGES` | 2 | Synchronizer depth |

```
src domain                              dst domain
                    req (cdc_bit)
i_src_data --|hold|-- ~~~~~~~~~~~~~~~ --> o_dst_data
i_src_valid ->        <~~~~~~~~~~~~~~~ -- o_dst_valid
o_src_ready <-          ack (cdc_bit)
```

One transfer at a time. `o_src_ready` deasserts during transfer and reasserts after the ack round-trip.

### cdc_pulse

Transfers pulses across clock domains. Two compile-time selectable architectures:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SYNC_STAGES` | 2 | Synchronizer depth |
| `MODE` | 0 | 0 = toggle, 1 = counter |
| `CTR_WIDTH` | 4 | Counter width (MODE=1 only) |

**MODE=0 (toggle)** — Lightweight. Toggles a FF on each src pulse, syncs the level, edge-detects in dst. Requires spacing between consecutive pulses (at least `2*SYNC_STAGES + 1` dst clocks).

**MODE=1 (counter)** — Counts pulses in src domain, syncs the counter via `cdc_counter`, and generates matching pulses in dst domain. Guarantees **N pulses in = N pulses out**, even with back-to-back or contiguous bursts. Each output pulse is exactly **1 dst_clk wide**, separated by a mandatory 1-cycle gap. More logic than toggle mode, but handles any pulse rate the src can produce.

### cdc_fifo

Small asynchronous FIFO for streaming data across clock domains. Cummings-style Gray-coded pointer design.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 8 | Data width |
| `DEPTH` | 4 | FIFO depth (must be power of 2, minimum 4) |
| `SYNC_STAGES` | 2 | Pointer synchronizer depth |

```
i_wr_clk domain            i_rd_clk domain
i_wr_data -->[  memory  ]--> o_rd_data
i_wr_en   -->[ wr | rd  ]--> i_rd_en
o_full    <--[ ptr  ptr ]<-- o_empty
```

Combinational read output. Supports concurrent read/write at full throughput.

### cdc_sync_fifo

Single-clock synchronous FIFO for same-domain buffering. Supports registered read (default) or FWFT mode.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `WIDTH` | 8 | Data width |
| `DEPTH` | 16 | FIFO depth |
| `FWFT_MODE` | 0 | 0 = registered read (1-cycle latency), 1 = FWFT (zero latency) |

| Port | Direction | Description |
|------|-----------|-------------|
| `o_count` | out | Current occupancy (ADDR_WIDTH+1 bits) |
| `o_full` | out | Asserted when FIFO is full |
| `o_empty` | out | Asserted when FIFO is empty |

Standalone module with no CDC dependencies. Useful as a data buffer within a single clock domain.

## Reset Style

The library supports two reset styles selected at compile time via the `CDC_ASYNC_RESET` macro.

| Mode | Macro | `always_ff` sensitivity | `initial` blocks | `ASYNC_REG` attribute |
|------|-------|------------------------|------------------|-----------------------|
| FPGA (default) | *(not defined)* | `posedge clk` only | present | present |
| ASIC-portable | `-DCDC_ASYNC_RESET` | `posedge clk or negedge rst_n` | absent | absent |

**Setting the project default** — edit `sources/include/cdc_config.svh` and uncomment the `define` line. This applies to every build without any Make flags.

**Per-run override:**
```bash
make sim TOP_MODULE=cdc_fifo TESTBENCH=cdc_fifo_tb RESET_STYLE=async   # force async
make sim TOP_MODULE=cdc_fifo TESTBENCH=cdc_fifo_tb RESET_STYLE=sync    # force sync
```

`cdc_reset` is exempt — it always uses async-assert/sync-deassert by design.

## Quick Start

```bash
# Check tools are installed
make check-tools

# Update file list (required after cloning)
make update_list

# Run all tests
make sim TOP_MODULE=cdc_bit         TESTBENCH=cdc_bit_tb
make sim TOP_MODULE=cdc_reset       TESTBENCH=cdc_reset_tb
make sim TOP_MODULE=cdc_gray_conv   TESTBENCH=cdc_gray_conv_tb
make sim TOP_MODULE=cdc_gray_sync   TESTBENCH=cdc_gray_sync_tb
make sim TOP_MODULE=cdc_counter     TESTBENCH=cdc_counter_tb
make sim TOP_MODULE=cdc_handshake   TESTBENCH=cdc_handshake_tb
make sim TOP_MODULE=cdc_pulse       TESTBENCH=cdc_pulse_tb
make sim TOP_MODULE=cdc_fifo        TESTBENCH=cdc_fifo_tb
make sim TOP_MODULE=cdc_sync_fifo   TESTBENCH=cdc_sync_fifo_tb

# Run same tests in ASIC async-reset mode
make sim TOP_MODULE=cdc_fifo TESTBENCH=cdc_fifo_tb RESET_STYLE=async

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
    .i_clk      (dst_clk),
    .i_rst_n    (dst_rst_n),
    .i_async_in (signal_from_other_domain),
    .o_sync_out (synchronized_signal)
);

// Synchronize reset with clean deassert
cdc_reset #(.SYNC_STAGES(3)) u_rst_sync (
    .i_clk         (sys_clk),
    .i_async_rst_n (pll_locked),
    .o_sync_rst_n  (sys_rst_n)
);

// Transfer pulses (counter mode — burst safe)
cdc_pulse #(.MODE(1), .CTR_WIDTH(8)) u_irq_sync (
    .i_src_clk   (periph_clk), .i_src_rst_n (periph_rst_n), .i_src_pulse (irq_pulse),
    .i_dst_clk   (cpu_clk),    .i_dst_rst_n (cpu_rst_n),    .o_dst_pulse (irq_synced)
);

// Transfer a register value with handshake
cdc_handshake #(.WIDTH(32)) u_cfg_sync (
    .i_src_clk   (cfg_clk),  .i_src_rst_n (cfg_rst_n),
    .i_src_data  (cfg_data), .i_src_valid (cfg_valid), .o_src_ready (cfg_ready),
    .i_dst_clk   (core_clk), .i_dst_rst_n (core_rst_n),
    .o_dst_data  (cfg_synced), .o_dst_valid (cfg_synced_valid)
);

// Stream data across clock domains
cdc_fifo #(.WIDTH(16), .DEPTH(8)) u_stream_fifo (
    .i_wr_clk  (adc_clk),  .i_wr_rst_n (adc_rst_n),
    .i_wr_en   (sample_valid), .i_wr_data (sample_data), .o_full  (fifo_full),
    .i_rd_clk  (proc_clk), .i_rd_rst_n (proc_rst_n),
    .i_rd_en   (read_en),      .o_rd_data (proc_data),   .o_empty (fifo_empty)
);

// Single-clock buffering (FWFT mode)
cdc_sync_fifo #(.WIDTH(32), .DEPTH(16), .FWFT_MODE(1)) u_cmd_buf (
    .i_clk    (sys_clk),  .i_rst_n  (sys_rst_n),
    .i_wr_en  (cmd_valid), .i_wr_data (cmd_data), .o_full  (cmd_full),
    .i_rd_en  (cmd_read),  .o_rd_data (cmd_out),  .o_empty (cmd_empty),
    .o_count  (cmd_count)
);
```

## Design Conventions

- **Dual reset style** — sync reset (FPGA default) or async reset (ASIC) selectable via `CDC_ASYNC_RESET` macro; see `sources/include/cdc_config.svh`
- **`(* ASYNC_REG = "TRUE" *)`** on synchronizer registers in FPGA mode for correct placement (removed in ASIC mode)
- **`initial` blocks** for FPGA power-up values (removed in ASIC mode)
- **`always_ff`** for sequential logic, **`always_comb`** for combinational
- **Parameterized** — all widths, depths, and sync stages are configurable
- **No vendor primitives** — portable across Lattice, Xilinx, Intel, etc.

## Directory Structure

```
cdc_lib/
├── sources/
│   ├── rtl/
│   │   ├── cdc_bit.sv
│   │   ├── cdc_reset.sv
│   │   ├── cdc_gray_conv.sv
│   │   ├── cdc_gray_sync.sv
│   │   ├── cdc_counter.sv
│   │   ├── cdc_handshake.sv
│   │   ├── cdc_pulse.sv
│   │   ├── cdc_fifo.sv
│   │   └── cdc_sync_fifo.sv
│   ├── tb/                          # 9 self-checking testbenches
│   ├── include/
│   │   └── cdc_config.svh           # Reset style configuration
│   └── constraints/
├── sim/
│   ├── waves/                       # VCD waveform dumps
│   └── logs/
├── backend/
│   ├── synth/                       # Yosys synthesis outputs
│   ├── pnr/                         # Place & route outputs
│   ├── bitstream/
│   └── reports/
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

| Module | Simulation (sync) | Simulation (async) | Synthesis (iCE40) |
|--------|-------------------|--------------------|-------------------|
| cdc_bit | PASS | PASS | PASS |
| cdc_reset | PASS | PASS | PASS |
| cdc_gray_conv | PASS | PASS | PASS |
| cdc_gray_sync | PASS | PASS | PASS |
| cdc_counter | PASS | PASS | PASS |
| cdc_handshake | PASS | PASS | PASS |
| cdc_pulse (toggle) | PASS | PASS | PASS |
| cdc_pulse (counter) | PASS | PASS | PASS |
| cdc_fifo | PASS | PASS | PASS |
| cdc_sync_fifo | PASS | PASS | PASS |

## Development

This project includes a `CLAUDE.md` file with detailed guidance for AI-assisted development — covering HDL coding standards, naming conventions, reset/clock rules, FSM templates, and project workflow for both Verilog/SystemVerilog and VHDL.

## License

MIT License — Copyright (c) 2026 [moaz khaled](https://github.com/moaz-kh).

Free to use, modify, and distribute for any purpose. Attribution required — keep the copyright notice in all copies or substantial portions of the code.
