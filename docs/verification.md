# Verification

## Requirements and commands

Simulation requires Python 3, Icarus Verilog, and `vvp`. No third-party Python packages are needed. Verilator is optional for lint.

```sh
python3 scripts/test_stage3.py                 # All simulation benches
python3 scripts/test_stage3.py --case pe       # PE only
python3 scripts/test_stage3.py --case cluster  # Cluster and vertical accumulation
python3 scripts/test_stage3.py --case router   # Router only
python3 scripts/test_stage3.py --lint          # Simulation and lint
python3 scripts/test_stage3.py --lint-only     # Lint only
```

Equivalent make targets: `make test`, `make lint`, `make all`. On Windows use `python` when the tools are on `PATH`.

## Coverage

| Bench | Checks |
| --- | --- |
| `tb_eyeriss_pe` | Signed/unsigned activations; both weight lanes; lengths 3 and 16; nonzero partial-sum restore; 20-bit wraparound; final-step writeback followed by restore; result hold |
| `tb_rs_spad_cluster` | Three packet inputs; masks and row distribution; multiple packets; lengths 3, 6, and 16; both lanes; nonzero seeds; output backpressure and stability; completion after all columns; overlapping activation masks and invalid weight padding |
| `tb_dense_static_router` | Stalled broadcast without duplicates; concurrent unicast; grouped/interleaved multicast; shadow buffering and ordering; continuous broadcast; idle status; reset |

Expected cluster lane-0 totals before adding seeds are 63 for length 3, 153 for length 6, and 648 for length 16. Lane 1 uses negative unit weights. Each column receives its own signed seed pair.

## Results

The runner saves compile/run logs and `results.json` in `reports/local/stage3/`. It checks exit codes and bench-specific `PASS` markers. Missing tools, assertions, and timeouts fail the command; they are never reported as passed. Generated files are ignored by Git.

The cluster bench exercises the vertical accumulator through PE results and ready/valid stalls. These module-level tests do not validate a mesh, memory controller, complete convolution scheduler, or physical implementation. A PASS applies to the source revision actually tested.
