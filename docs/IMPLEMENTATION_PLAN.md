# Synchronizer Library - Implementation Plan

## Context

Reusable, parameterized synchronizer library in SystemVerilog at `/home/moazk/nano/sync_lib/`. Provides generic CDC (Clock Domain Crossing) primitives for FPGA projects. Modules are hierarchical — higher-level modules instantiate lower-level ones.

## Naming Convention

All modules use the `cdc_` prefix: `cdc_<functionality>`

## Module Hierarchy

```
cdc_bit            (leaf - fundamental building block)
cdc_reset          (standalone - async assert, sync deassert)
cdc_gray_conv      (standalone - combinational bin↔gray conversion utility)
cdc_pulse          (uses cdc_bit via cdc_pulse_toggle, or cdc_counter via cdc_pulse_counter)
cdc_counter        (uses cdc_bit × WIDTH + cdc_gray_conv × 2, exposes gray_out + gray_in_out)
cdc_handshake  (uses cdc_bit × 2 for req/ack handshake)
cdc_fifo       (uses cdc_counter × 2 + cdc_gray_conv × 2 for pointer sync)
```

## Implementation Order & Module Details

### Step 1: `cdc_bit.sv` — N-Stage Single-Bit Synchronizer
- **Params**: `SYNC_STAGES=2`, `RESET_VALUE=1'b0`
- **Ports**: `clk, rst_n, async_in → sync_out`
- **Design**: Shift register of `SYNC_STAGES` FFs with `(* ASYNC_REG = "TRUE" *)` attribute
- **Instantiates**: Nothing (leaf)
- **TB**: Dual-clock, verify latency = SYNC_STAGES cycles, reset behavior, stress toggle near clock edges

### Step 2: `cdc_reset.sv` — Reset Synchronizer
- **Params**: `SYNC_STAGES=2`
- **Ports**: `clk, async_rst_n → sync_rst_n`
- **Design**: Active-low only (no configurable polarity — kept simple). FF chain with **async reset assert, sync deassert** (the one valid use of async reset in FPGA). Uses `negedge async_rst_n` for async assertion.
- **Instantiates**: Nothing (standalone, architecturally distinct from cdc_bit)
- **TB**: Verify instant assert, SYNC_STAGES-cycle deassert, mid-cycle assertion

### Step 3: `cdc_gray_conv.sv` — Gray Code Conversion Utility
- **Params**: `WIDTH=4`
- **Ports**: `binary_in[WIDTH-1:0] → gray_out[WIDTH-1:0]`, `gray_in[WIDTH-1:0] → binary_out[WIDTH-1:0]`
- **Design**: Purely combinational module providing bin-to-gray and gray-to-bin conversion. Both directions available simultaneously.
- **Instantiates**: Nothing (standalone utility)
- **TB**: Exhaustive test for all 2^WIDTH values, verify round-trip: `bin→gray→bin == original`, verify single-bit-change property

### Step 4: `cdc_pulse.sv` — Pulse Synchronizer (Dual Mode)
- **Params**: `SYNC_STAGES=2`, `MODE=0` (toggle), `CTR_WIDTH=4`
- **Ports**: `src_clk, src_rst_n, src_pulse, dst_clk, dst_rst_n → dst_pulse`
- **Design**: Two compile-time selectable modes via `MODE` parameter:
  - **MODE=0 (toggle)**: Implemented via `cdc_pulse_toggle` sub-module. src_pulse toggles a FF → cdc_bit → edge detect. Lightweight, requires pulse spacing.
  - **MODE=1 (counter)**: Implemented via `cdc_pulse_counter` sub-module. Counts pulses in src → cdc_counter → generate matching pulses in dst. Guarantees N-in = N-out.
- **Architecture**: Uses separate sub-modules (`cdc_pulse_toggle`, `cdc_pulse_counter`) instantiated inside a generate block in the wrapper `cdc_pulse`. This avoids iverilog generate-scope signal driving issues.
- **Instantiates**: `cdc_bit` (toggle mode) or `cdc_counter` (counter mode)
- **TB**: Tests both modes. Dual-clock, verify 1:1 pulse transfer, burst transfer (counter mode), latency, reset recovery

### Step 5: `cdc_counter.sv` — Counter Synchronizer (Binary In/Out, Gray Internally)
- **Params**: `WIDTH=4`, `SYNC_STAGES=2`
- **Ports**: `clk, rst_n, binary_in[WIDTH-1:0] → binary_out[WIDTH-1:0], gray_out[WIDTH-1:0], gray_in_out[WIDTH-1:0]`
- **Design**: Accepts binary counter value, uses `cdc_gray_conv` for bin→gray, synchronizes each Gray bit via `generate for` of `cdc_bit` instances, uses `cdc_gray_conv` for gray→bin output. `binary_out` is the primary output; `gray_out` exposes the raw synchronized Gray value; `gray_in_out` exposes the pre-sync Gray code of the input (useful for FIFO local comparisons).
- **Instantiates**: `cdc_gray_conv` (2 instances), `cdc_bit` (WIDTH instances)
- **TB**: Free-running binary counter in src domain, verify gray_in_out matches expected, verify gray_out, reset

### Step 6: `cdc_handshake.sv` — Handshake-Based Bus Synchronizer
- **Params**: `WIDTH=8`, `SYNC_STAGES=2`
- **Ports**: `src_clk, src_rst_n, src_data, src_valid, src_ready` / `dst_clk, dst_rst_n, dst_data, dst_valid`
- **Design**: Four-phase toggle handshake — data held stable in holding register while req/ack toggles cross domains via `cdc_bit`. `src_ready` provides back-pressure.
- **Important**: All signal declarations must be at module top before any instantiation (iverilog forward-reference requirement).
- **Instantiates**: `cdc_bit` (2 instances: req crossing, ack crossing)
- **TB**: Sequential transfers, verify data integrity, back-pressure, reset mid-transfer, post-reset recovery

### Step 7: `cdc_fifo.sv` — Small Async FIFO Bus Synchronizer
- **Params**: `WIDTH=8`, `DEPTH=4`, `SYNC_STAGES=2`
- **Ports**: `wr_clk, wr_rst_n, wr_en, wr_data, full` / `rd_clk, rd_rst_n, rd_en, rd_data, empty`
- **Design**: Cummings-style async FIFO. Uses `cdc_counter` for pointer synchronization (handles Gray conversion internally). Uses `cdc_gray_conv` for local pointer-to-Gray conversion (for full/empty comparison). Small register-array memory (distributed RAM). Combinational read output.
- **Important**: All signal declarations must be at module top before any instantiation (iverilog forward-reference requirement).
- **Instantiates**: `cdc_counter` (2 instances: wr_ptr→rd_domain, rd_ptr→wr_domain), `cdc_gray_conv` (2 instances for local Gray conversion)
- **TB**: Fill/drain, full/empty flags, concurrent write/read, random bursts, various clock ratios

## Files Created (14 files)

**RTL** (`sources/rtl/`):
1. `cdc_bit.sv`
2. `cdc_reset.sv`
3. `cdc_gray_conv.sv`
4. `cdc_pulse.sv` (contains `cdc_pulse_toggle`, `cdc_pulse_counter`, and wrapper `cdc_pulse`)
5. `cdc_counter.sv`
6. `cdc_handshake.sv`
7. `cdc_fifo.sv`

**Testbenches** (`sources/tb/`):
8. `cdc_bit_tb.sv`
9. `cdc_reset_tb.sv`
10. `cdc_gray_conv_tb.sv`
11. `cdc_pulse_tb.sv`
12. `cdc_counter_tb.sv`
13. `cdc_handshake_tb.sv`
14. `cdc_fifo_tb.sv`

## Design Conventions

- `(* ASYNC_REG = "TRUE" *)` on all synchronizer registers
- `initial` blocks for FPGA power-up values
- Synchronous reset everywhere except `cdc_reset` (which handles async by design)
- `always_ff` for sequential, `always_comb` for combinational
- Self-checking TBs with `*** TEST PASSED ***` / `*** TEST FAILED ***` output
- VCD dumps for waveform viewing
- All signal declarations before any module instantiation (iverilog compatibility)
- TB stimulus uses `#1` delay after `@(posedge clk)` to avoid Verilog race conditions

## Verification

```bash
cd /home/moazk/nano/sync_lib
make update_list
make sim TOP_MODULE=cdc_bit            TESTBENCH=cdc_bit_tb
make sim TOP_MODULE=cdc_reset          TESTBENCH=cdc_reset_tb
make sim TOP_MODULE=cdc_gray_conv      TESTBENCH=cdc_gray_conv_tb
make sim TOP_MODULE=cdc_pulse          TESTBENCH=cdc_pulse_tb
make sim TOP_MODULE=cdc_counter        TESTBENCH=cdc_counter_tb
make sim TOP_MODULE=cdc_handshake  TESTBENCH=cdc_handshake_tb
make sim TOP_MODULE=cdc_fifo       TESTBENCH=cdc_fifo_tb
```

**Status: All 7/7 tests PASS.**

## Key Design Decisions

1. **cdc_reset**: Active-low only — no configurable polarity parameter. Keeps the module simple without extra mux logic.

2. **cdc_pulse dual mode**: Toggle mode (MODE=0) is lightweight but can't handle back-to-back pulses. Counter mode (MODE=1) guarantees N-in=N-out even with bursts, at the cost of more logic (cdc_counter + local counter). Both are available via compile-time parameter selection.

3. **cdc_counter gray_in_out port**: Exposes the pre-synchronization Gray code of the input. Useful for FIFO full/empty comparison without needing a separate cdc_gray_conv instance in the consuming module.

4. **cdc_pulse architecture**: Uses separate sub-modules (`cdc_pulse_toggle`, `cdc_pulse_counter`) instantiated via generate in the wrapper, rather than generate blocks with inline logic. This avoids iverilog issues with driving output ports from within generate scopes.

5. **iverilog compatibility**: All signal declarations placed before module instantiations to avoid forward-reference elaboration errors. TB stimulus uses `#1` delay after clock edge to avoid race conditions between initial/always blocks.
