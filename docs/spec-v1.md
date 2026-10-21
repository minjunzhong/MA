# Four-cluster Eyeriss-v2-inspired RTL: v0.1 specification

Status: test-first dense baseline. This is an original experimental implementation,
not RTL released by the paper authors and not a cycle-accurate reproduction.

## Source and traceability

Yu-Hsin Chen, Tien-Ju Yang, Joel S. Emer, Vivienne Sze, *Eyeriss v2: A Flexible
Accelerator for Emerging Deep Neural Networks on Mobile Devices*, IEEE JETCAS,
2019, DOI: 10.1109/JETCAS.2019.2910232, arXiv:1807.07928.
Local source: `../paper/Eyeriss_v2_A_Flexible_Accelerator_for_Emerging_Deep_Neural_Networks_on_Mobile_Devices.pdf`.
The reference PDF is not redistributed in this repository.

| Paper evidence | v0.1 requirement / explicit deviation |
|---|---|
| Sec. II, Fig. 6, Table II (PDF pp. 4-5): 16 clusters, 12 PEs in 3 rows x 4 columns | Scale to 4 logical clusters in a 2x2 arrangement; retain 3x4 PEs each (48 PEs total). |
| Sec. II (p. 5): 8-bit activations/weights, optional unsigned activations, 20-bit psums | Signed 8-bit weights, selectable signed/unsigned 8-bit activations; modular 20-bit signed accumulation. |
| Sec. IV-B, Fig. 17 (p. 11): two SIMD MACs share an activation | Two weight lanes per PE, one activation shared per cycle: 96 physical MAC lanes. |
| Sec. IV-A/B, Fig. 17: iact data 16 words, weight data 96 packed words, psum 32 words | Dense iact 16x8, weight 96x16 (two weights), psum 32x20 per PE. CSC address/count fields are omitted. |
| Sec. III, Figs. 8-13: hierarchical multicast and vertical psum flow | Programmable host-driven cluster/PE multicast plus optional three-row output reduction. Central fanout is a baseline, NOT the paper's router mesh. |
| Table II: 12 KB GLB per cluster; separate networks; Sec. IV: CSC pipeline | Full GLB/SRAM macros, CSC sparse pipeline, pipelined HM-NoC, DMA, quantization/ReLU, layer mapper and paper's 2134-bit command are deferred. |

Consequently sparse speedups, original energy efficiency, NoC scalability and paper
PPA numbers cannot be inferred from this version. The logical 2x2 layout is a
software naming convention; no physical placement constraint is implied.

## Computation

Cluster `c=0..3`, physical PE `p=4*r+x` (`r=0..2`, `x=0..3`), lane `l=0..1`:

```
result[c,p,l] = wrap20(seed[c,p,l] +
    sum(k=0..K-1, decode8(iact[c,p,k]) * signed8(weight[c,p,B+k,l])))
```

`K=1..16`, `B=0..95`, and `B+K<=96`. Seed is zero when `cfg_accumulate=0`;
otherwise it is psum scratchpad entry `2*cfg_psum_slot+l`. Each final PE result is
written back to that entry. Psum slots 0..15 independently hold two SIMD results.
Overflow wraps modulo 2^20; there is no saturation, rounding or requantization.

When `cfg_reduce_rows=1`, output ID `p=x=0..3` denotes
`wrap20(result[c,x,l]+result[c,4+x,l]+result[c,8+x,l])`.
The reduced value is NOT written into the per-PE psum scratchpad. This is an output
adder tree, not the paper's cycle-by-cycle vertical forwarding pipeline.
For a 3xS row-stationary convolution tile, map kernel rows to PE rows, four output
x positions to PE columns, and two output channels to SIMD lanes; use `K=S` and
row reduction. Longer channel/kernel windows are tiled by software. There is no
hardware scheduler for arbitrary CNN layers.

## Interface contract (single clock; active-low asynchronous reset)

All transfers use `valid && ready` sampled on the rising clock edge.

| Ports | Width / behavior |
|---|---|
| `clk`, `rst_n` | Clock; asynchronous reset of control and accumulators. |
| `load_valid`, `load_ready` | Load only in IDLE and while `start_valid=0`. Start has priority over load. |
| `load_kind` | 2 bits: 0 activation, 1 packed weights, 2 psum seed, 3 invalid. |
| `load_cluster_mask`, `load_pe_mask` | 4 and 12 bits; multicast to selected endpoints. Zero mask is a legal no-op. |
| `load_addr`, `load_data` | 7 and 20 bits. Activation: addr<16, low8. Weight: addr<96, low16, lane0 low8. Seed: addr<32, low20. |
| `start_valid`, `start_ready` | Start accepted in IDLE; legal configuration launches all selected clusters. |
| `cfg_cluster_mask` | 4 bits, nonzero; defines active clusters for compute and output. |
| `cfg_len`, `cfg_weight_base`, `cfg_psum_slot` | 5, 7, 4 bits; K, B, slot. |
| `cfg_accumulate`, `cfg_unsigned_iact`, `cfg_reduce_rows` | 1 bit each; sampled only on accepted legal start. |
| `busy` | High during COMPUTE and DRAIN. Loads/starts are not accepted then. |
| `out_valid`, `out_ready` | Backpressured output; ID and data remain stable until accepted. |
| `out_cluster`, `out_pe`, `out_lane`, `out_psum` | 2, 4, 1, 20 bits; raw two's-complement psum. |
| `out_last` | High with final output of selected clusters; stable during stalls. |
| `done` | One-cycle pulse after the final output handshake. No early done. |
| `error` | Sticky for invalid accepted load/start; cleared by reset or next legal start. Invalid requests have no memory/compute effects. |
| `compute_cycles`, `mac_count` | 32-bit counters reset on legal start. K compute cycles; `popcount(mask)*24*K` MACs (multiply+add counted as one MAC). |

Output order: selected cluster ascending, PE ascending (12 or 4), lane ascending.
Exactly `active_clusters * (24 if raw else 8)` outputs are emitted per job.
COMPUTE takes K cycles after the start edge. DRAIN takes one cycle per accepted
output, plus any stalls. Load time and serial output time are included in end-to-end
latency measurements, not in `compute_cycles`. No claim that 96 MAC/cycle equals
end-to-end application throughput is permitted.

Reset aborts in-flight compute/output, removes out_valid/busy/error/done, and
restores ready in IDLE. SRAM-like scratchpads are intentionally not reset; software
must initialize every address that will be read. Accumulate mode requires an
initialized psum pair. Uninitialized reads are outside this contract.

## Acceptance tests (written before implementation)

1. Reset/idle control, including reset during compute and stalled output.
2. Signed dot products including -128/127, K=1 and K=16, and last legal weight address.
3. Unsigned activations 128..255 and signed weights.
4. Independent multicast masks, single active cluster and noncontiguous active clusters.
5. Psum initialization, wraparound, repeated accumulation and independent slots.
6. Independent 3x3 convolution reference compared to row-reduced outputs (32 values).
7. Randomized operands, lengths, offsets, masks and backpressure; scoreboard checks all IDs/data.
8. Stalled output stability, final marker, exact count, done timing and counter values.
9. Rejection of invalid lengths/base/masks/load addresses; no unsolicited outputs.
10. Start/load exclusion during busy, start priority, and configuration snapshot isolation.

## Evaluation contract

Functional performance: record load/compute/drain cycles, MAC count, utilization and
output count from simulation. Physical performance: run Genus with an explicitly
supplied Liberty library, clock period, corner and I/O assumptions; report WNS,
area and estimated power separately. Register-inferred memories and centralized
fanout make this a baseline, not paper-equivalent physical hardware. Never commit
licensed PDK/Liberty files. A successful synthesis alone does not prove timing
closure, accurate dynamic power or post-layout performance.
