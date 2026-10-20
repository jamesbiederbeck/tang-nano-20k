# Multilane cmtz-core

RFC-003 in the Cook-Mertz repo (`rfcs/RFC-003-catalytic-multicore.md`) asks
two separate questions about the reusable F_17 processor (`cmtz-processor.md`):

1. Do several lanes (independent instruction streams in one bitstream) get
   more work done per clock?
2. Can one lane borrow another lane's *occupied* registers (values that must
   come back unchanged), so that it needs less workspace of its own without
   adding storage?

This page records what was built and measured on the Tang Nano 20K. The RFC
holds the design, and the simulator and RTL evidence.

## Projects

| Project | Lanes | Leases | Lane module |
|---|---|---|---|
| `projects/cmtz/cmtz-dual` | 2 | no | `cmtz_core`, unmodified (same text as `cmtz-core`) |

Protocol: CMTM (`cmtz/isa/mlane_host.py`). It is cmtz-core's protocol on a
selected lane, plus these commands:

- `L` selects a lane;
- `B` starts several lanes on the same clock;
- a 28-byte `Q` frame carries cycle stamps from a free-running 27 MHz counter.

The single-core tools refuse this bitstream, and the multilane tools refuse
cmtz-core.

## Independent lanes (`cmtz-dual`)

Board run: `examples/fpga/mlane_run.py`, 958 of 958 checks. Each check reads
the whole board state, seeds the multilane model with it, runs the same
scene on both and compares every lane's state, status, retired count,
cycle count and stall count. Each lane is also compared with a scalar
simulator run on its own, and the outputs with the plain-integer oracle.

An interrupt was sent to lane 0 during a 2.46 M-instruction `gate_irq` run.
Lane 0's result held with the restoring handler and broke without it. Lane
1's `tree_clean` took exactly 39 910 cycles both times.

Instructions per clock, from the on-chip stamps:

| Lanes busy with | IPC |
|---|---|
| one lane, any program | 0.500 (2 cycles per instruction) |
| two equal jobs (e.g. `gate_clean` + `gate_clean`) | 1.000 |
| `gate_projection` + `gate_clean` (424 vs 614 cycles) | 0.845 |
| `tree_clean` + `gate_direct` (39 910 vs 14 cycles) | 0.500 |
| 12-job random batch, dealt in pairs | 0.631 (1.26× one lane) |

Two lanes double the peak, not the delivered rate. Over the UART,
wall-clock time got worse (0.14 s against 0.18 s for the batch). The jobs
are microseconds long, and host polling dominates.

Synthesis (`-noalu`):

| Build | LUT4 | DFF | BSRAM | Fmax |
|---|---|---|---|---|
| `cmtz-core` | 2918 | 690 | 2 | 114.9 MHz |
| `cmtz-dual` | 5030 | 1132 | 4 | 104.0 MHz |
