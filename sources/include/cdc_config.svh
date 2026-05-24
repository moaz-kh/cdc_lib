// cdc_config.svh — project-wide reset style for cdc_lib
//
// This file is included by every RTL module. Edit it once to change the
// project-wide default without touching any RTL source.
//
// Per-run override (does not modify this file):
//   make sim RESET_STYLE=async  →  forces async regardless of this file
//   make sim RESET_STYLE=sync   →  forces sync  regardless of this file
//
// When CDC_ASYNC_RESET is NOT defined (default):
//   - always_ff uses posedge clk only (sync reset)
//   - initial blocks set power-up state (FPGA-friendly)
//   - (* ASYNC_REG = "TRUE" *) attribute present on synchronizer chains
//
// When CDC_ASYNC_RESET IS defined:
//   - always_ff sensitivity includes negedge rst_n (async reset)
//   - initial blocks removed (not synthesizable in ASIC flows)
//   - (* ASYNC_REG = "TRUE" *) attribute removed (Vivado-specific)
//
// Exception: cdc_reset.sv always uses async-assert/sync-deassert by design
// and ignores this macro entirely.
//
// Uncomment the line below to enable async-reset (ASIC-portable) mode:
// `define CDC_ASYNC_RESET
