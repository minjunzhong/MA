# v0.1 verification and evaluation record

## Test-first history

1. Paper-derived `spec-v1.md`, independent integer/convolution reference, pyuvm
   environment and a non-computing interface stub were written first.
2. On `prakt19`, the stub ran all nine acceptance tests: **0 pass / 9 fail**.
   Failures were behavioral assertions, not missing dependencies or compile errors.
   This test-first state is commit `419bfef`.
3. The actual PE, 12-PE cluster and four-cluster RTL was implemented. First full
   regression: **9 pass / 0 fail**.
4. The test harness was refined to record load and end-to-end cycles, explicitly
   attempt a start while busy, and enforce nonzero exit on failed XML results.
   The complete final regression again passed **9/9**. No acceptance assertions
   were weakened to obtain a passing result.
5. Verilator lint passed with `-Wall -Wno-SYNCASYNCNET`. The one named waiver
   documents the intentionally synchronous write qualification of unreset
   scratchpads alongside asynchronous control/accumulator reset. No blanket
   warning suppression is used.

## Actual environment

- Ubuntu 22.04 on the authorized EDA machine `prakt19`.
- Python 3.10.12, Icarus Verilog 11.0, Verilator 4.038.
- cocotb 1.9.2, pyuvm 3.0.0, pytest 8.3.5.
- One deterministic randomized suite with 12 jobs, plus directed/edge-case jobs;
  random seeds are fixed in the tests. This is an initial regression, not exhaustive
  verification or functional coverage closure.
- Final full suite: 359629.01 ns simulated time; real runtime depends on the host.

The pyuvm monitor and scoreboard compare every accepted output ID/data against the
reference. Tests also check output stability under stalls, last markers, completion,
configuration isolation, invalid requests and reset during compute/stalled output.
`reports/verified/validation.json` records per-test status and source SHA-256 values.

## Measured cycle baseline

For K=16, raw outputs, no output stalls and individually loaded operands:

| Active clusters | MACs | Compute cycles | Start-to-done intervals | Host-load cycles | End-to-end cycles | Core MAC/cycle | End-to-end MAC/cycle |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 384 | 16 | 40 | 768 | 809 | 24 | 0.474660 |
| 2 | 768 | 16 | 64 | 1536 | 1601 | 48 | 0.479700 |
| 4 | 1536 | 16 | 112 | 3072 | 3185 | 96 | 0.482261 |

These are actual RTL simulation counters and driver cycle measurements, not an
analytical spreadsheet. Definitions are in README and the machine-readable
`reports/verified/benchmark.json`.

The result exposes the baseline bottleneck: adding compute lanes increases core
throughput but does not remove serial operand loading/output. Individual random
operands intentionally do not exploit multicast reuse. This is weak scaling (more
work with more active clusters), not a 4x claim for the same convolution workload.
Future comparisons should hold the full workload fixed and separately measure
multicast reuse, overlapping transfers and realistic memory bandwidth.

## Genus evaluation

The Genus executable and Genus_Synthesis license work. The RTL was read by Genus;
the initial library-free elaboration failed with LBR-163 (target library required).
That is a flow prerequisite, not a functional-test failure. The checked-in flow
now requires a readable library before elaboration and provides parse-only input
checking separately.

The school's `/nas/ei/share/tools/asiclibs/README` was not readable by this account,
and no authorized course timing library was supplied. A separate demonstration
uses the publicly available Nangate45 typical library from OpenROAD-flow-scripts:

- Source: https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/master/flow/platforms/nangate45
- SHA-256: `8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1`.
- Purpose: research/test, non-manufacturable standard-cell library.
- Not the paper's TSMC 65 nm process or the course's target PDK.
- Clock target 10 library time units; I/O delay 10%, uncertainty 5%; reset paths excluded.
- A separate Genus elaboration probe confirmed `Time_unit :1000ps`; the demo
  target is therefore 10 ns (100 MHz), not 10 ps. Exported SDC confirms the unit.
- No explicit external capacitive load or input driving cell is specified;
  the tool's defaults are used. This limits external-interface timing realism.
- No SRAM macros, place-and-route, clock-tree synthesis, routing extraction,
  workload SAIF, formal equivalence or gate-level regression was performed.
- Vectorless power is an assumption-driven estimate, not measured application energy.

Any synthesis result is to be interpreted only with these assumptions. Original
paper speed/area/power numbers are not a valid comparison target for this baseline.

## GitHub CI

The first complete implementation commit `298814c` was pushed successfully and its
[GitHub Actions run](https://github.com/minjunzhong/MA/actions/runs/39658735234)
completed successfully. This independently reran simulation, XML validation and
Verilator lint on an Ubuntu GitHub runner. Later documentation/report-only commits
do not change the RTL source hashes recorded in the verification artifact.
