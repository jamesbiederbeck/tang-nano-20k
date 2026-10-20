# cmtz-core: a reusable processor for cmtz programs (decision document)

Status (2026-10-19): **implemented and checked on the board** (`core_run.py`: 987 of 987 checks). The scope grew from the straight-line core below to a general-purpose one: branches, counted loops, CALL/RET and a data memory, so `matpow` runs on the core with the matrix written at run time. What was built, and where it differs from this proposal, is in **As built** at the end; the sections in between are the original reasoning.

## The decision

Build one **fixed-field, in-order, one-instruction-per-clock register machine**. Its instructions are the cmtz IR operations. A program is a short list of instructions loaded over the existing UART; the bitstream does not change per program. The compiler gains a backend that turns an IR DAG into that instruction list. The catalytic constructs become real hardware behaviour: `interrupt {}` becomes a real interrupt that runs a handler on the live register file, and `catalytic {}` stays advisory.

Short version of each sub-decision (reasons below):

| Question | Decision |
|---|---|
| Field | `p`, `q` fixed at synthesis. One bitstream per field, parameters in the RTL generator. |
| Complex (F_{p²}) | Packed `{im, re}` registers; complex ops built spatially in the ALU. Optional in v1. |
| ISA | 3-address, one op per runtime IR node; `rotate` becomes multiply by an immediate ω^j (no ROM). |
| Timing | CPI = 1, single-cycle ALU, no hazards. |
| Compiler | New backend: allocate over `topo_order()`, keep emit-time folding, plus a Python ISA simulator checked against `evaluate_all`. |
| Host | Extend the existing UART protocol; keep `board.js` and `uart_check.py` usable. |
| Catalytic | Real single-level interrupt; handler may only use reversible (linear) ops on borrowed registers; verifier runs on the **allocated** program and checks the net linear map is the identity. |
| Control flow | Straight-line plus a run-forever loop in v1. No general loops; `IRMatPow` stays rejected. |
| Build | `-noalu`; no "checked on the board" claim until `uart_check` has matched on the chip. |

## Why a processor at all, and what it costs

Measured in `benchmarks/cmtz-vs-cpu/README.md`: the generated pipeline does 27 Mop/s at 27 MHz, the CPU does 1 to 9 Gop/s, and over the UART the board manages 167 op/s measured (3 to 4 kop/s wire ceiling). The CPU wins every row. A processor does not change that.

What it costs: a program with N runtime nodes takes N clocks, so throughput is 27/N M-programs/s instead of 27. For `cmtz-fibonacci` (10 adds) that is 2.7 M runs/s against 27, a 10x loss on the datapath. At the UART-limited rate (at most 3.8 kop/s) that loss is invisible.

What it buys:
- **No resynthesis per program.** Today every program is a new netlist: `apio build` (about 10 s) plus a load, for each of 14 projects. A processor loads a new program in milliseconds.
- **Board verification is paid once.** Two projects gave wrong answers on the chip with the default ALU mapping while simulation passed. Each generated circuit is a new chance to hit that. One core, checked exhaustively on the board (F_17 mul is 289 pairs, as `board.py` already does), covers every program for that field. This holds only to the extent each ALU operation gets exhaustive coverage.
- **Catalytic semantics become observable**, not comments (see below).

It is not a speed argument, and the doc should not be read as one.

## Field binding

Every example in `examples/` uses `field(17, 19)` (12 uses) or the F_{p²} example with `cfield(7)` (2 uses). So one or two cores cover everything today.

Fix `p` and `q` at synthesis. A runtime `p` would break the current reduction scheme (unrolled conditional subtracts of `p << k`, chosen because `%` makes yosys build a divider).

`IRPoly` evaluates over F_q and reduces mod p, so the ALU needs lanes of `ceil(log2 q)` bits for poly. Two options: make every lane q-wide (simple, 5 bits for q=19, costs nothing here), or add a Horner step instruction with a separate reduce-to-p. Default: q-wide lanes, `HORNER rd, rs, coeff` (rd = rs*x + coeff mod q) and `REDP` (mod q to mod p).

## ISA

Register file `R0..R(N-1)`, lane width `W = ceil(log2 q)`, complex registers hold `{im, re}`. Instruction word 32 bits: `op(5) rd(5) rs1(5) rs2(5) imm(12)`.

| IR node | Instruction | Note |
|---|---|---|
| `IREmbed` / `IRComplexEmbed` | `LDI rd, imm` | Constants that feed nothing runtime are folded by the compiler and never become instructions (same rule as the Verilog backend). Runtime inputs are written by the host. |
| `IRRotate` | `MULI rd, rs, imm` with `imm = ω^j mod p` | The compiler computes ω^j. No table in hardware. Runtime-`j` rotations do not exist in the IR. |
| `IRAdd` | `ADD rd, rs1, rs2` | |
| (new) | `SUB rd, rs1, rs2` | Inverse of ADD; needed for reversible handlers. |
| `IRMul` | `MUL rd, rs1, rs2` | Not invertible when the operand is 0. |
| `IRPoly` | `HORNER` sequence then `REDP` | One `HORNER` per coefficient. |
| `IRConjugate` | `CONJ rd, rs` | Involution, so reversible. |
| `IRMagnitudeSq` | `MAGSQ rd, rs` | Lossy. |
| `IRMeasure` | host reads the register (`S`) | `mod_p`/`real`/`imag` are field selects on the read; no instruction. |
| `IRCompose`, `IRRegion` | no instruction | Structure only. |
| `IRMatPow` | rejected | Same as the Verilog backend. |

Add `HALT`, `JMP addr` (for the run-forever loop), `RETI`.

Complex: with LUT use near 0% (belief-propagation uses 193 of 20736 LUT4), a combinational 4-multiplier complex multiply in one stage is fine and keeps CPI = 1. Dual-lane datapath, not expansion into real sequences. If this widens v1 too much, ship real-field only first.

Timing: v1 is a simple FSM, `FETCH -> EXECUTE/WRITEBACK`, with a wait state if the program memory has a synchronous read (BSRAM does; LUT RAM can read asynchronously but costs logic). **CPI = 1 is a later optimisation, not a v1 acceptance criterion**: it needs the next instruction fetched while the current one executes, and jumps and interrupt dispatch then cost a bubble. The generated pipeline stages close at 285 MHz for multiply plus reduce (belief-propagation, `apio report`), which suggests the ALU is not the limit at 27 MHz, but measure the complete core rather than assume it.

Resources: the F_17 core needs about 32 x 5 bits of registers and 256 x 32 bits of program memory (8 kbit). I did not verify BSRAM or multiplier counts: `apio report` only lists resources a design uses, and `developing.md` has no BSRAM or DSP figures. Totals I did read from the report: 20736 LUT4, 15552 DFF. Check the Gowin data sheet before choosing BSRAM versus LUT RAM for program memory.

## Compiler side

New backend `cmtz/backends/isa_backend.py` (name open):
1. Walk `topo_order()`, drop everything that folds at emit time (reuse `PythonBackend`, so hardware and reference share one definition of constants).
2. Linear-scan register allocation over liveness of runtime values; spill is an error in v1 (N registers is plenty for these programs).
3. Emit instructions plus an input map (which registers the host writes) and an output map (which registers `measure` reads).
4. Python **ISA simulator** that runs the instruction list. Test: simulator output equals `evaluate_all` for every example, the way `testdata/golden.json` checks `board.js` against the real Python encoder. Generated testbench vectors still come from `evaluate_all`.

Do not edit generated RTL by hand. Core RTL comes from a generator parameterised by `(p, q, regs, complex)` so the Python simulator and the RTL share constants.

## Host interface

Extend the existing UART protocol rather than inventing one. Existing (per `cook_mertz/CLAUDE.md`): one byte per lane, all-`0xFF` reply on an out-of-range lane, stalled requests dropped after a timeout, debug builds add `I` (info frame with a program hash), `R` (run), `S` (state readback). Proposed additions, letters provisional:
- `P` load program: length, then instruction words.
- `W` write one register (inputs).
- `R` run until `HALT` (existing meaning); `S` read registers (existing).
- `T` trigger the interrupt.
- `I` info frame reports a **core** hash (field, register count, ISA version) and the hash of the loaded program separately, so `uart_check.py` can tell a wrong core from a wrong program.

Framing details must be checked against the `verilog_uart.py` docstring before implementing; I did not re-read it for this document.

## Catalytic semantics (the substantive part)

Today `interrupt {}` becomes `IRCatalyticRegion`, verified by name (`catalytic_verify.py` currently starts all deltas at 0 and flags writes to listed registers), and the Verilog backend turns both region kinds into comments. `catalytic {}` becomes the advisory `IRRegion`.

Proposal:
- **`interrupt {}` becomes a real interrupt.** The handler is a second instruction block. `T` (or a button, pins 88/87) sets a pending flag; at an instruction boundary the core saves the PC, runs the handler on the live register file, and `RETI` returns. Single level, no nesting. For this to be meaningful the main program must be running when the interrupt arrives, hence the run-forever `JMP 0` loop in v1.
- **Names stop meaning anything once allocation maps several IR names onto one register.** A name-based check on the allocated program proves nothing. Two fixes, and I propose both: (a) the allocator keeps the handler's `restoring (...)` registers out of the handler's temporary pool, and (b) the verifier runs on the **allocated** instruction stream over physical registers.
- **The handler's temporaries must not be live in the main program.** An interrupt can land between any two main instructions, so every register the handler writes that is not borrowed-and-restored would corrupt main's state. The allocator therefore gives the handler a scratch pool **disjoint from every register the main program uses**, and the verifier rejects a handler that writes outside its pool or its borrowed set. Borrowed registers may be modified only reversibly.
- **What the verifier proves.** `ADD`, `SUB`, `MULI`, `CONJ` are all linear over F_p. So the handler's net effect on each borrowed register is a linear map of the initial register values, and "restored" means that map is the identity. The map is taken over **all** initial registers, scratch and inputs included, so a borrowed register that ends up depending on a temporary or an external value is not the identity and is rejected. That is decidable and exact. `MUL` with two runtime operands is not linear: writes to a borrowed register by `MUL`, `MAGSQ` or `HORNER` are rejected; those ops are fine on non-borrowed temporaries. This is true catalytic use (compute reversibly, uncompute), not only "do not touch". Note `MUL` is not reversible when an operand is 0, which is why it is excluded for borrowed targets.
- **Optional debug check.** A `--debug` build snapshots the borrowed registers at handler entry and compares them at `RETI`, setting a status bit the host reads with `S`. This is a runtime backstop for the static verifier, not a replacement.
- `catalytic {}` stays advisory and emits no hardware, as in the spec (§2.6).

Interrupt state machine (v1, UART trigger only; a button needs synchronisation and debouncing and adds nothing to the semantics):
- `T` sets a pending bit. The core dispatches only at an instruction boundary, when pending is set and it is not already in the handler.
- On dispatch: save the return PC, clear pending, jump to the handler entry.
- `RETI` restores the PC. A `T` that arrives while the handler runs sets pending again (one bit, so repeated triggers coalesce) and is served after `RETI`.
- Single level, no nesting.

## Program image

The compiler emits one versioned artifact that the Python simulator, the UART host tool and the testbench generator all consume: header (ISA version, `p`, `q`, register count), instruction count, entry PC, handler PC, borrowed-register set, input and output register maps, instruction words, and a checksum. The loader rejects bad lengths, unsupported opcodes, register indices out of range and jump targets outside the program **before** running anything.

## Control flow

v1 is straight-line code plus the run-forever loop. A hardware loop counter would be the step that makes `IRMatPow` executable, but the matrix is a runtime parameter that the DSL cannot express, so that widens scope into the language. Defer.

## Build and verification policy

- `yosys-extra-options = -noalu` in `apio.ini`, per both `CLAUDE.md` files. A multiplier-heavy core may behave differently under `-noalu`; check area and fmax in `apio report`.
- Testbenches print `PASS`/`FAIL`; read the line, not `apio test`'s status. Break the design on purpose once and confirm `FAIL`.
- Load to SRAM, not flash. Do not say "checked on the board" until `uart_check.py` has matched every vector on the chip with the new core, and extend `ON_BOARD` only then.

## Build order

Each step leaves both repos testable.
1. ISA spec plus Python simulator; exhaustive tests per opcode (F_17 mul is 289 pairs).
2. `isa_backend.py`: allocation, program image, simulator equals `evaluate_all` on every example.
3. Minimal core with a hard-coded program, run under iverilog (so UART bugs cannot hide datapath bugs).
4. UART program loading; three-way comparison per example: `evaluate_all`, simulator, board. The first two run in CI; the board run is reported separately.
5. Interrupts plus the allocated-program verifier, with a negative test showing a bad handler is rejected.
6. Complex values, then pipelining only if measurements justify it.

The existing generated-pipeline projects stay as independent regression references for the same IR semantics.

## Open questions for you

Recommended defaults are given; say which to change.

1. **Real field only in v1** (complex after step 5)? Default yes; only two examples need it.
2. **One core per field**, no runtime `p`? Default yes.
3. **Interrupt trigger: UART `T` only in v1.** Default yes.
4. **Control flow:** `JMP 0` only, or a counted loop now (and a plan for `IRMatPow`)? Default `JMP 0` only.
5. **32 registers, 256 instructions:** my guess; I have not measured the largest program. Check against the examples in step 2.
6. **Location:** compiler backend, ISA, simulator and verifier in cook_mertz; generated `projects/cmtz/cmtz-core/` in this repo, as the other cmtz projects. Default yes.
7. **This document:** keep it here, move it to cook_mertz, or drop it? Neither repo has it committed.

I will not implement anything until you answer these.

## As built

Code: `cmtz/isa/` (ISA, assembler, image, simulator, host protocol, demos, matrix library), `cmtz/backends/isa_backend.py` (compiler), `cmtz/analysis/isa_catalytic.py` (handler verifier), `cmtz/backends/isa_core.py` and `isa_uart.py` (RTL and testbenches) in the Cook-Mertz repo; the generated project is `projects/cmtz/cmtz-core/`; `examples/fpga/core_run.py` checks a loaded board.

Differences from the proposal above:
- **General purpose.** Index registers X0..X15 (16-bit), data memory (1024 words), branches on index compares and on field values, CALL/RET with an 8-deep return stack. `matpow` is unrolled at compile time into calls to a runtime library (`matmul`, `matident`, `matcopy`) following Lemma 3.12 as `eval_matpow_matrix` does.
- **Timing.** A multi-cycle FSM (fetch, execute, memory), not CPI = 1.
- **WAITI.** A compiled program with an `interrupt {}` ends `WAITI; HALT`: main stalls until a handler has returned, so a trigger sent over the UART always runs it once. The interrupt demo that borrows a register mid-computation is hand-written (`demos.catalytic_loop`): a long loop reads the borrowed register every iteration, and the result must not change wherever the interrupt lands.
- **Verifier precondition.** The restore proof is over F_p; registers can also hold values in [p, q) (HORNER accumulators), so code outside the handler may not leave a borrowed register there.
- **Protocol.** `G` replies at once and the host polls `Q`; `T` and `X` work while running; `P` replies with the crc32 the core computed over the uploaded words. Full description in `cmtz/isa/host.py`.
- **Run contract.** `G` resets control state only; registers and data memory persist between runs, and the board check seeds the simulator with the board's state before each run.

Measured (`apio build`, `-noalu`): 2918 LUT4 of 20736, 690 DFF, 2 BSRAM, 1 MULT18X18 and 1 MULT9X9, fmax 115 MHz against the 27 MHz clock. `apio report` itself crashes on this design (a zero-capacity `DUMMY_CELL` row); the numbers come from `_build/default/hardware.pnr`.

Verified in simulation: the core testbench (71 cases back to back on one core, every opcode exhaustively over F_17, every error code, interrupts at chosen instruction counts) and the UART testbench (13 runs, an interrupt landing mid-loop, refusals and the timeout) both pass, and deliberately broken cores and front ends make them fail. On the board (Tang Nano 20K, SRAM load, `-noalu`), `examples/fpga/core_run.py` matched 987 of 987 checks: every real-field example and matpow (2x2 and 3x3) with the whole register file and data memory compared against the simulator seeded from the board's state, the exhaustive sweep of every field instruction, and the catalytic loop with the interrupt sent over the UART landing at four points between about 81k and 900k instructions into a 2.4M-instruction run, the loop result unchanged each time. Loading a program takes 5 to 31 ms.
