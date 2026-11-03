# Eyeriss-Inspired PE Cluster and Static Router

## Project introduction

This project implements three building blocks of an Eyeriss v2 inspired accelerator: a dense processing element, a scratchpad based PE cluster, and a configurable static router. Each PE shares one activation between two MAC lanes and accumulates 20 bit results. Twelve PEs form a three by four cluster, with four vertical accumulators combining results by column. The router supports unicast, multicast, broadcast, and ready valid flow control. The repository also includes module level SystemVerilog tests and an English code reading guide. Mesh networks, global buffers, output quantization, and DMA integration are outside the scope of this version of the project.

## Connect to the school server and run

1. Connect to the university network or VPN if required.
2. Open PowerShell or a terminal on your computer and log in:

   ```sh
   ssh ge47cup@prakt19.eda.cit.tum.de
   ```

   Enter your university password at the SSH prompt. No password is stored in this repository. If host-key verification fails, verify the server fingerprint with the university before changing the corresponding `known_hosts` entry.

3. In the remote terminal, create a fresh checkout:

   ```sh
   git clone https://github.com/minjunzhong/MA.git ~/MA-stage3
   cd ~/MA-stage3
   ```

4. Check that Python 3 and Icarus Verilog are available:

   ```sh
   python3 --version
   iverilog -V
   vvp -V
   ```

   If a tool is missing, check the server's available environment modules with `module avail`, or ask the administrator which module provides it. The Python runner uses only the standard library.

5. Run the simulations:

   ```sh
   python3 scripts/test_stage3.py
   ```

   Each of the PE, cluster, and router tests must print `PASS`. The runner returns a nonzero exit code for missing tools, compilation failures, timeouts, or failed assertions. Logs and a JSON summary are written to `reports/local/stage3/`.

6. Optionally run Verilator lint when it is available:

   ```sh
   python3 scripts/test_stage3.py --lint
   ```

   `make test`, `make lint`, and `make all` are convenient equivalents for simulation, lint only, and both checks. Exit the SSH session with `exit` when finished.

## Source layout

```text
rtl/
  eyeriss_pe.sv                 Local SPads and dual-MAC computation
  rs_spad_cluster.sv            Loading and control for a 3 x 4 PE array
  rs_vertical_accumulator.sv    Per-column SIMD2 accumulation with backpressure
  dense_static_router.sv       Buffered static routing and multicast
tests/
  tb_eyeriss_pe.sv
  tb_rs_spad_cluster.sv
  tb_dense_static_router.sv
scripts/
  test_stage3.py
docs/
  architecture.md              Module functions, interfaces, and data flow
  verification.md              Test coverage and commands
  figures/                     English presentation diagrams
```

The cluster and the router are tested as separate building blocks. This version does not connect them into a mesh or a complete accelerator.

Start with the [architecture guide](docs/architecture.md), then read the [verification guide](docs/verification.md).
