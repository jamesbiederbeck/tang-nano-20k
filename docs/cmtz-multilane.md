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
| `projects/cmtz/cmtz-lease` | 2 | yes | `cmtz_lane`: the same generator with the register file moved out |

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

## Register leases (`cmtz-lease`)

`K b o bank count` lends `count` (1..8) of lane o's registers, R(8·bank)
upward, to lane b. Lane b reaches them as R24 upward.

- **No copies.** The two lanes' registers sit in one physical array, and
  the window is a different path to the same flip-flops.
- **Owner stalls.** The owner keeps running, but an owner instruction that
  names a leased register waits in EXEC.
- **Release.** When the borrower halts, the owner continues one cycle
  later. A borrower that ends in an error *poisons* the registers: they are
  never handed back as if nothing happened.
- **Refusals.** The hardware refuses a lease of a register holding 17 or 18
  (outside F_17; the restoration proofs do not cover those). It also
  refuses a lane that would lend and borrow at the same time (which rules
  out deadlock), and a bank that is already taken.

Board run: `mlane_run.py`, 1733 of 1733 checks.

- The independent-lane checks above pass on this build too.
- So do the testbench's lease scenes: every refusal code, a poisoned lease
  and its recovery, and an owner write that stalls.
- In 40 random leases, a gate (3 registers) or a gate tree (5 registers)
  was evaluated in the other lane's live registers while that lane looped
  and then read one of them. The owner's values came back 40 times out of
  40, and the outputs matched the oracle.
- The owner stalls were 0 to 39 425 cycles, each exactly as the model
  predicted.

**What it costs.** +3792 LUT4 (+75 %) and +460 DFF over `cmtz-dual`, and Fmax
68.6 MHz instead of 104.0. On a single core the register file maps to
distributed RAM. Shared between lanes, behind a window mux with three read
ports per lane, it becomes flip-flops and wide multiplexers. The register
bits are the same, 2 × 32 × 5, so leasing in hardware saves no storage at
this size and costs logic.
