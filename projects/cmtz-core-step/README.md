# cmtz-core-step

[`cmtz/cmtz-core`](../cmtz/cmtz-core/) with a debugger. Same processor, same UART protocol, plus three things
you can do to a running core:

| Byte | Meaning |
|---|---|
| `H` | pause. A running core stops at the next instruction boundary; an idle, halted or failed one is armed paused at its entry (what the simulator's `start()` does, nothing executed). Replies `00`, or `FF` with nothing loaded. |
| `N` | run exactly one step of a paused core, then pause again. One step is one `Machine.step()` of the simulator: a pending interrupt is taken and the handler's first instruction runs in the same step, and a `WAITI` that keeps waiting is a step that retires nothing. Replies `00`, or `FF` if not paused. |
| `G` | on a paused core, resume it where it stands (nothing is reset). On an idle core it starts a run, as before. |

While paused, `S` (registers), `M` (data memory), `Q`, `T` and `X` work; `P`, `W` and `D` are refused.
`Q` reports status `4` for paused. LED 0 blinks while paused. The info frame is unchanged, so a core
without the debugger simply ignores `H` and `N` (a timeout on `H` means "no step support").

The full protocol is the docstring of `cmtz/isa/host.py` in the Cook-Mertz repo. The step build is a
generator flag (`emit_core(step=True)`, `emit_core_uart(step=True)`) that is off by default, so
`cmtz/cmtz-core` is byte-identical to what it was.

## Files

| File | What |
|---|---|
| `cmtz_core.v`, `cmtz_core_uart.v` | The processor and its UART front end, step build. Generated. |
| `cmtz_core_step_tb.v` | Every `N` compared with `Machine.step()`: status frame and all 64 register bytes after each step. Straight-line code, a looping 3x3 matpow, an interrupt sent while paused on `WAITI`, a pause in the middle of a run, and the refusals. Generated. |
| `cmtz_core_uart_tb.v` | The unchanged UART testbench of cmtz-core, run on this build: every old command still behaves. Generated. |
| `pins.cst`, `apio.ini` | As cmtz-core; `-noalu` |

Regenerate with `uv run python examples/fpga/build_projects.py <dir> --core-step` in the Cook-Mertz repo.

```
source ../../env.sh
apio test cmtz_core_step_tb.v     # PASS: 6 stepped runs
apio test cmtz_core_uart_tb.v     # PASS: 13 runs
apio build                        # about 55 s
openFPGALoader -c ft2232 _build/default/hardware.fs        # SRAM
```

## Status

Built: 2727 of 20736 LUT4, 722 flip-flops, 2 block RAMs, timing 108 MHz (the clock is 27 MHz).

Checked on the board (loaded to SRAM):

- `core_run.py --quick` of the Cook-Mertz repo: 801 of 801, the same checks as plain cmtz-core.
- Lockstep against the simulator, one instruction at a time (166 comparisons of status, error, retired
  count, pc, interrupt count and every R and X register, 0 mismatches): a straight-line program, 120
  steps through a looping matpow and then a resume, `T` sent while paused on `WAITI`, `H` in the middle
  of a 3.2-million-instruction run (it stopped at retired 80279 and matched the simulator at that
  count) followed by five steps and a resume, and `X` while paused.

The visualizer of the Cook-Mertz repo drives this build: Board panel, protocol "cmtz-core (step build)",
then the Processor tab of the Chip dialog.
