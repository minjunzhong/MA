# Architecture and Code Reading Guide

## Scope and reading order

1. [eyeriss_pe.sv](../rtl/eyeriss_pe.sv): local storage and computation.
2. [rs_vertical_accumulator.sv](../rtl/rs_vertical_accumulator.sv): combine three PE result pairs and a seed.
3. [rs_spad_cluster.sv](../rtl/rs_spad_cluster.sv): loading, synchronization, and completion of twelve PEs.
4. [dense_static_router.sv](../rtl/dense_static_router.sv): configurable transfer and multicast handshaking.

The PE cluster and static router are independent modules in this version. A higher-level network and system controller are not included.

## Processing element

| Storage | Shape | Use |
| --- | --- | --- |
| Activation SPad | 16 x 8 bits | Activations indexed by `step` |
| Weight SPad | 96 x 16 bits | Low byte is lane 0; high byte is lane 1 |
| Partial-sum SPad | 32 x 20 bits | Sixteen pairs of saved partial sums |

`load_en`, `load_kind`, `load_addr`, and `load_data` form the shared loading interface. Kind 0 writes an activation, kind 1 writes a weight pair, and kind 2 writes a partial sum. Provide valid addresses and load every location before use. SPads have no bulk reset.

`launch` initializes both accumulators to zero, or restores the pair selected by `start_slot` when `start_accumulate` is set. Each edge with `run_en` reads `iact[step]` and `weight[weight_base + step]`:

```text
acc0 = acc0 + activation * weight0
acc1 = acc1 + activation * weight1
```

Weights are signed eight-bit values. `unsigned_iact` selects signed or unsigned activations; a nine-bit signed extension accommodates both. Arithmetic wraps to 20 bits. `final_step` writes the newly computed sums, including the final products, to the pair selected by `run_slot`. `result0` and `result1` continuously expose the accumulators without an independent valid signal.

Read the source as interface declarations, storage and combinational arithmetic, SPad writes, and accumulator updates. Reset has priority over launch, and launch has priority over a run update. Schedule loading and execution separately.

## Vertical accumulator

Each instance receives a 40-bit seed and a 120-bit `rows` vector. Every 40-bit pair contains lane 0 in bits `[19:0]` and lane 1 in bits `[39:20]`.

```text
rows[119:80] = bottom PE pair
rows[79:40]  = middle PE pair
rows[39:0]   = top PE pair

stage 0: seed + bottom
stage 1: previous result + middle
stage 2: previous result + top
```

`add_pair` performs two independent 20-bit additions; carries cannot cross between lanes. `remaining0` and `remaining1` preserve rows for later stages. The `full` and `accept` bits permit movement when a stage has space or its contents can advance. A stalled output keeps valid data stable until accepted.

## SPad cluster

The cluster instantiates twelve PEs and four vertical accumulators:

```text
PE0   PE1   PE2   PE3
PE4   PE5   PE6   PE7
PE8   PE9   PE10  PE11
 |     |     |     |
 V0    V1    V2    V3
```

### Loading

Each of three activation inputs carries a 24-bit packet, a twelve-bit PE mask, and a four-bit starting address. A handshake latches the packet and sideband fields. Over the next three edges, the unpacker writes low, middle, and high bytes to consecutive activation SPad addresses. Every selected PE receives the packet. Simultaneously valid activation masks must not overlap. Starting addresses must be at most 13; the module does not report address wraparound.

Three weight inputs are fixed to the three PE rows. For PE index `p`, `p/4` selects its weight input, and `w_mask[p]` selects whether it writes. Low sixteen bits contain the weight pair; high eight bits must be zero. Valid weight loading takes priority over accepting activation packets. Loading stops during computation and result delivery.

### Execution

The three phases are idle/loading, computation, and accumulation/output. A legal launch requires `length` between 1 and 16 and `weight_base + length <= 96`. `start_ready` indicates loading is idle, rather than validating those numeric parameters. Parameters are captured on launch and a common `step` advances for all twelve PEs.

The PE instances have `start_accumulate=0`, `start_slot=0`, and `run_slot=0`. They compute local dot products from zero. External seeds are added in vertical accumulators. Three values per packet do not restrict `length` to three: load more packets at different addresses before starting a longer dot product.

### Results

Column `c` collects PEs `c`, `c+4`, and `c+8`. The vertical accumulator starts when that column's seed handshakes. Even zero seeds require a valid handshake. `sent` records submitted columns; `received` records delivered outputs. A one-cycle `done` pulse follows acceptance of all four output pairs. Loading masks are not compute-enable masks: all PEs execute, and all columns must be serviced even if some results are unused.

For a three-tap example, the first column can calculate `[1,2,3]`, `[6,7,8]`, and `[11,12,13]` against unit weights. The PE results are 6, 21, and 36; a zero seed gives lane-0 result 63. Other columns can process other output positions in parallel. Input windows and reuse schedules are prepared externally.

## Static router

`PORTS` sets the input and output count; `WIDTH` sets each port's data width; `SEL_W` sets source-selector width. Each enabled output selects one input through `cfg_source`. Several outputs selecting one input implement multicast or broadcast; distinct outputs can select different inputs concurrently. Selectors must identify legal input indices.

Configuration is accepted with `cfg_valid && cfg_ready`. The router must be idle to accept new configuration. Routes remain fixed while transactions are outstanding. There are no packet headers or dynamic arbitration.

Each input has a current `payload`, a `pending` destination bitmap, and a second `shadow` slot. A destination handshake clears only its own pending bit, preventing repeated multicast delivery to fast receivers. After the current word completes, the shadow word is promoted or a new input is captured. A full shadow slot backpressures the input.

Data transfers require valid and ready high on the same clock edge. `idle` means all current and shadow slots are empty. An input needs at least one configured destination to be accepted. The router neither computes sums nor selects routes from payload values.

## Presentation diagrams

- [PE cluster](figures/pe-cluster.pdf)
- [Static router](figures/static-router.pdf)

## Relation to the paper

This is an independently written dense implementation inspired by Eyeriss v2. It retains shared-activation dual MACs and 20-bit partial sums. CSC address SPads, count fields, zero skipping, and the paper's seven-stage sparse pipeline are not implemented. Vertical accumulation uses separate modules. Functional correctness does not establish cycle, area, power, or timing equivalence.

Reference: Y.-H. Chen, T.-J. Yang, J. Emer, and V. Sze, [Eyeriss v2](https://eems.mit.edu/wp-content/uploads/2019/04/2019_jetcas_eyerissv2.pdf), 2019.
