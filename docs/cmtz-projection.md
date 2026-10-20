# Roots-of-unity projection on cmtz-core

The question: does the reusable F_17 processor (`projects/cmtz/cmtz-core/`, design in `cmtz-processor.md`) compute the Cook-Mertz roots-of-unity projection exactly, and can it evaluate a small circuit cleanly, with every catalytic register coming back? Code lives in the Cook-Mertz repo (`jamesbiederbeck/catalytic_computing`). The bitstream and the ISA are unchanged. Everything new is programs, analysis and host tooling.

## The identity

Let ω have multiplicative order m in F_p, and let P be a polynomial of total degree d < m. Then for any shifts τ,

    Σ_{j=0}^{m-1} P(x + ω^j·τ) = m · P(x)

This holds because P(x + zτ) has degree ≤ d in z, and the sum of ω^{jk} over j is 0 unless m divides k. In F_17, ω = 3 has order 16, and 16 ≡ −1. So `y ← y − Σ_j P(x + ω^j τ)` adds P(x) to y, and the masks τ never appear in the result.

A two-input gate g is evaluated through its multilinear extension ĝ(u, v) = k0 + k1·u + k2·v + k3·u·v (degree 2), which equals g on {0,1}². The masked-gate step uses two registers τ1 and τ2 that start with arbitrary values, plus an output register y. Each of 16 iterations does:

1. Add a into τ1 and b into τ2.
2. Subtract ĝ(τ1, τ2) from y.
3. Subtract a and b again.
4. Rotate both τ registers by ω.

Since ω^16 = 1, the masks end where they began.

## Programs (`cmtz/isa/projection.py`)

All programs are hand-written assembly; none needed a new instruction. Gate coefficients are host-written registers, so one image covers all 16 gates.

| Program | What it does |
|---|---|
| `gate_direct` | y += ĝ(a, b), straight-line (baseline) |
| `gate_projection` | y −= Σ_j ĝ(a + ω^j τ1, b + ω^j τ2); the masks are read-only and the shifted arguments are built in temporaries |
| `gate_clean` | The same sum computed in place: the masks are added into, rotated and restored |
| `gate_sweep` | `gate_clean` for all 289 mask pairs in one run, with the results stored to data memory |
| `gate_irq` | `gate_clean` repeated, with an interrupt handler that borrows mask τ1 mid-computation |
| `tree_direct` | y += f̂(ĝ1(a, b), ĝ2(c, d)), straight-line |
| `tree_clean` | Two levels of projection. The parent's registers τl and τr receive g1 and g2 by a full child loop, which a second child loop of the opposite sign removes. Both children share τ1 and τ2. g1 and g2 never exist anywhere except added into a register that is later restored. |

## Results, by kind of evidence

**Exact (mathematics, and a proof on the machine code)**

- The identity is the argument above.
- `analysis/isa_clean.py` executes a program symbolically:
  - Every field register is a polynomial over F_17 in the entry values of all 31 registers, reduced with x^17 = x, so equality means equality as functions on F_17.
  - Index registers and control flow stay concrete.
- `projection.prove()` uses it to establish, for every coefficient, input, mask and accumulator value in F_17:
  - `gate_clean` and `tree_clean` (14,755 instructions) add exactly ĝ, respectively f̂(ĝ1, ĝ2), to y;
  - every catalytic register comes back as its own value;
  - nothing else changes except one declared temporary and the loop counters.
- The proven tree gain, evaluated at all 4,096 gate triples × 16 Boolean inputs, is the tree's truth value.
- The proof rejects these mutations:
  - removing the uncompute;
  - removing a rotation, adding an extra one, or doing 15 rotations instead of 16;
  - the wrong sign;
  - reading a register the host did not write;
  - a data-dependent branch.
- Two outcomes surprised me; both are correct:
  - **Rotating τ2 by ω^5 instead of ω still verifies.** A monomial τ1^i τ2^l then picks up ω^{j(i+5l)}, and i + 5l is never 0 mod 16 when 0 < i + l ≤ 2.
  - **Removing the uncompute still restores the masks.** Σω^k = 0 brings them back. The gain is wrong instead: ĝ at a/(1 − ω) = 8a. The oracle predicts exactly this.

**Independent oracle** (`cmtz/projection_oracle.py`, plain integers, imports nothing from cmtz)

- All 16 gates, exhaustively over a, b ∈ {0, 1}, τ1, τ2 and y ∈ F_17 (314,432 cases).
- The identity at every point of F_17 for the monomials that gates are built from.
- 48 gate triples × all 16 tree inputs.
- Controls that break it: degree m, a root of the wrong order (ω = 4), skipping the rotation, skipping the uncompute.

**Simulator** (`cmtz/isa/sim.py`, against the oracle)

- Every gate and input for direct, projection and clean, starting from scrambled leftover state.
- `gate_clean` exhaustively over all 289 mask pairs, for every gate and input, with the starting accumulator cycling through F_17.
- 128 tree cases.
- An interrupt dispatched at every instruction boundary of `gate_irq`, for all 16 gates: the result is unchanged each time. With the non-restoring handler, it changes.

**RTL** (iverilog, `test_isa_core.py::TestProjectionSimulation`)

- 27 cases cover every program, with interrupts at chosen boundaries.
- Each case checks the whole register file and data memory against the simulator, plus the clock cycle count against the simulator's FSM model (2 per instruction, plus 1 per LD and 1 per dispatch).
- A mutated cycle count fails the test.

**Board** (Tang Nano 20K, SRAM load, `-noalu`, `examples/fpga/core_run.py`, full run)

- 2,459 of 2,459 checks matched.
- The projection checks cover these runs:

  | Runs | Programs | Inputs |
  |---|---|---|
  | 64 each | direct, projection and clean | all 16 gates × 4 inputs |
  | 64 | `gate_sweep` | all 289 masks × every gate × every input |
  | 16 each | `tree_direct`, `tree_clean` | random trees |

- Each run compares the whole state against the simulator seeded with the board's state, plus the outputs against the oracle.
- In `gate_irq`, a handler borrows a mask. T was sent over the UART and landed between about 81k and 892k instructions into a 2.36M-instruction run. y and both masks were unchanged.
- The non-restoring handler changed them.
- `projection_bench.py --board`: the chip's retired counts equal the model's for all five programs.

## Cost (`examples/fpga/projection_bench.py`)

Instructions and cycles are the same for every input. No branch depends on a field value, and the proof follows the single path. Cycles come from the RTL-checked model. The UART cannot time the core: one round trip is about 6 ms.

| Program | Words | Instructions | Cycles | µs @ 27 MHz | Inputs | Catalytic | Out | Temps | X | R total |
|---|---|---|---|---|---|---|---|---|---|---|
| gate_direct | 7 | 7 | 14 | 0.52 | 6 | 0 | 1 | 1 | 0 | 8 |
| gate_projection | 17 | 212 | 424 | 15.7 | 8 | 0 | 1 | 4 | 2 | 13 |
| gate_clean | 17 | 227 | 454 | 16.81 | 6 | 2 | 1 | 1 | 2 | 10 |
| tree_direct | 17 | 17 | 34 | 1.26 | 16 | 0 | 1 | 3 | 0 | 20 |
| tree_clean | 53 | 14,755 | 29,510 | 1,092.96 | 16 | 4 | 1 | 1 | 3 | 22 |

Projection costs about 30× direct for one gate. The depth-2 tree costs about 870× direct. Each level multiplies the cost by about 65 = 16 rotations × 4 child runs (each child is added and removed again): 14,755 ≈ 16 × (4 × 227 + 14).

**No space advantage is claimed.** At this size, the clean versions use *more* registers than direct evaluation: the tree needs 4 catalytic registers against 3 temporaries. Restoring registers is a correctness property. Cook-Mertz's space bound comes from reusing the same catalytic registers across levels of a deep tree, while the free space grows only by a loop counter per level. A depth-2 tree is too small to show that. What this work does show is the mechanism, exact on hardware: intermediate values that only ever exist inside restored registers, and one pair of masks reused by both children.

## Soundness gaps found in the handler verifier, and fixed

`analysis/isa_catalytic.py` proved restoration over F_p. But registers are 5 bits wide and can hold any value below q = 19:

- HORNER results;
- LDI immediates;
- LD from data memory;
- host `W`, which accepts anything below q.

On such operands the ALU is not arithmetic mod p: its SUB computes 0 − 18 as 12, because rb + p − rc wraps. Four gaps followed:

1. **Missed writes.** Only HORNER and LDI ≥ p writes to a borrowed register were caught. LD and MOV-from-such-a-register were missed. Now `noncanonical_registers()`, a fixpoint over all code outside the handler, covers them.
2. **Unchecked reads.** Registers the handler only reads were never checked. `demos.noncanonical_handler` passed the old verifier: it subtracts and then adds back R7 = 18, an affine identity on borrowed R2. On the chip it turns x = 0 into 13. Two requirements now apply:
   - the handler's reads must be outside that fixpoint set;
   - they must be host-written unless borrowed, since a dispatch can come before main writes anything.
3. **Scratch disjointness.** This was assumed from the allocator; it is now checked for any image.
4. **Host input range.** `CoreLink.run` wrote inputs without the < p check that the simulator applies. It now refuses them.

Every compiled example still verifies. The simulator raises on out-of-range operands rather than modelling them, so the counterexamples were shown on the RTL (`test_isa_catalytic.py`) and on the board (`core_run.py --only soundness`):

- x = 0 came back as 13.
- `gate_clean` with mask register τ1 = 17 or 18 returns it as 0 or 1. y is still right, since 17 ≡ 0 and 18 ≡ 1.

## Limitations

1. **Restoration holds for values in [0, p), not for every bit pattern a register can hold.** A true catalytic tape on this hardware would have to restore all 19 values below q. Today the host has to keep catalytic registers in [0, p); `requires_canonical` in both reports lists which registers.
2. **The clean proof covers interrupt-free runs.** Interrupts enter through a composition argument rather than a mechanised proof: the handler verifier proves that a handler restores what it borrows and touches nothing main uses. That argument is tested at every dispatch point in the simulator and at four points on the board.
3. **What the proof refuses.** It rejects LD/ST, HORNER/REDP and data-dependent branches. The handler verifier is still affine and straight-line, so it cannot accept a handler that restores a register by nonlinear cancellation.
4. **No compiler support.** The DSL's `catalytic {}` is still advisory, and nothing lowers a circuit to a projection loop.
5. **No on-chip cycle counter.** Cycles come from the model, which is checked against the RTL.

## Next engineering blockers

1. **Alphabet.** Decide whether field registers should be exactly F_p (W and LDI refuse values ≥ p, and HORNER/REDP get their own registers or a reduce-on-write). The alternative is a catalytic contract over all values below q. Either way it is an ISA and RTL change.
2. **Depth.** Register count is the first wall, before the 8-deep return stack or the loop-counter registers. With leaves and gate coefficients in registers, depth d needs 2^d inputs plus 4·(2^d − 1) coefficients. At depth 3 that is 36 registers, more than the 31 there are, before counting catalytic registers. So depth 3 needs coefficients compiled into the code (MULI/ADD chains) or loaded from data memory, and the latter needs LD support in the proof. Cost grows about 65× per level: depth 3 would be about 16 × 4 × 14,755 ≈ 944k instructions, about 70 ms.
3. **Lowering.** A compiler pass from a gate circuit (or `IRCatalyticRegion`) to these loops, using `prove()` as the acceptance check. That probably needs a DSL construct for circuits, so it is a language decision.
4. **Handler proofs with nonlinear restoration.** Run `isa_clean`'s polynomial execution on handlers as well, then mechanise the main/handler composition.
