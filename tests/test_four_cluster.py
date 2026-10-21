"""Executable acceptance specification: pyuvm driver, monitor and scoreboard."""
import json
import os
import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
import pyuvm
from pyuvm import uvm_component, uvm_test, uvm_analysis_port, uvm_analysis_export

from reference import signed, dot, convolution_at

INPUTS = "load_valid load_kind load_cluster_mask load_pe_mask load_addr load_data start_valid cfg_cluster_mask cfg_len cfg_weight_base cfg_psum_slot cfg_accumulate cfg_unsigned_iact cfg_reduce_rows out_ready".split()
OBSERVE = "load_ready start_ready busy out_valid out_cluster out_pe out_lane out_psum out_last done error compute_cycles mac_count".split()


def config(**overrides):
    result = dict(cfg_cluster_mask=15, cfg_len=4, cfg_weight_base=0,
                  cfg_psum_slot=0, cfg_accumulate=0, cfg_unsigned_iact=0,
                  cfg_reduce_rows=0)
    result.update(overrides)
    return result


class Data:
    def __init__(self, seed=1):
        rng = random.Random(seed)
        self.a = [[[rng.randrange(-128, 128) for _ in range(16)]
                   for _ in range(12)] for _ in range(4)]
        self.w = [[[[rng.randrange(-128, 128) for _ in range(2)]
                    for _ in range(96)] for _ in range(12)] for _ in range(4)]
        self.s = [[[0] * 32 for _ in range(12)] for _ in range(4)]

    def reference(self, cfg):
        k, base, slot = cfg['cfg_len'], cfg['cfg_weight_base'], cfg['cfg_psum_slot']
        outputs = []
        for c in range(4):
            if not (cfg['cfg_cluster_mask'] >> c) & 1:
                continue
            values = []
            for p in range(12):
                pair = []
                for lane in range(2):
                    seed = self.s[c][p][2 * slot + lane] if cfg['cfg_accumulate'] else 0
                    value = dot(self.a[c][p][:k],
                                [self.w[c][p][base + i][lane] for i in range(k)],
                                seed, cfg['cfg_unsigned_iact'])
                    self.s[c][p][2 * slot + lane] = value
                    pair.append(value)
                values.append(pair)
            if cfg['cfg_reduce_rows']:
                for x in range(4):
                    for lane in range(2):
                        outputs.append((c, x, lane, signed(sum(values[4*r+x][lane]
                                                               for r in range(3)), 20)))
            else:
                outputs.extend((c, p, lane, values[p][lane])
                               for p in range(12) for lane in range(2))
        return outputs


class Scoreboard(uvm_component):
    def build_phase(self):
        self.expected, self.actual = [], []
        self.analysis_export = uvm_analysis_export('analysis_export', self)
        self.analysis_export.write = self.write

    def write(self, item):
        index = len(self.actual)
        assert index < len(self.expected), f'Unexpected output #{index}: {item}'
        assert item == self.expected[index], f'Output #{index}: {item} != {self.expected[index]}'
        self.actual.append(item)

    def check_phase(self):
        assert self.actual == self.expected, f'Missing outputs: {len(self.actual)}/{len(self.expected)}'


class OutputMonitor(uvm_component):
    def build_phase(self):
        self.ap = uvm_analysis_port('ap', self)

    async def run_phase(self):
        d = cocotb.top
        while True:
            await FallingEdge(d.clk)
            await Timer(2, units='ns')
            item = None
            if int(d.rst_n.value) and int(d.out_valid.value) and int(d.out_ready.value):
                item = (int(d.out_cluster.value), int(d.out_pe.value),
                        int(d.out_lane.value), signed(int(d.out_psum.value), 20))
            await RisingEdge(d.clk)
            if item is not None:
                self.ap.write(item)


class ArrayDriver(uvm_component):
    async def cycle(self, **signals):
        d = cocotb.top
        await FallingEdge(d.clk)
        for name, value in signals.items():
            getattr(d, name).value = value
        await Timer(1, units='ns')
        before = {name: int(getattr(d, name).value) for name in OBSERVE}
        await RisingEdge(d.clk)
        await Timer(1, units='ns')
        return before

    async def reset(self):
        await self.cycle(rst_n=0, load_valid=0, start_valid=0, out_ready=0)
        await self.cycle()
        await self.cycle(rst_n=1)
        assert int(cocotb.top.start_ready.value) == 1
        assert int(cocotb.top.load_ready.value) == 1
        for name in ('busy', 'out_valid', 'error', 'done'):
            assert int(getattr(cocotb.top, name).value) == 0, name

    async def load(self, kind, cmask, pmask, addr, value):
        pre = await self.cycle(load_valid=1, load_kind=kind, load_cluster_mask=cmask,
                               load_pe_mask=pmask, load_addr=addr, load_data=value & 0xfffff)
        assert pre['load_ready'], 'Load unexpectedly blocked'
        await self.cycle(load_valid=0)

    async def program(self, data, cfg, seeds=False):
        for c in range(4):
            if not (cfg['cfg_cluster_mask'] >> c) & 1:
                continue
            for p in range(12):
                for k in range(cfg['cfg_len']):
                    await self.load(0, 1 << c, 1 << p, k, data.a[c][p][k] & 255)
                    b = cfg['cfg_weight_base'] + k
                    pair = data.w[c][p][b]
                    await self.load(1, 1 << c, 1 << p, b,
                                    (pair[0] & 255) | ((pair[1] & 255) << 8))
                if seeds:
                    for lane in range(2):
                        addr = cfg['cfg_psum_slot'] * 2 + lane
                        await self.load(2, 1 << c, 1 << p, addr, data.s[c][p][addr])

    async def run_job(self, cfg, expected, scoreboard, seed=1, disturb=False):
        d = cocotb.top
        scoreboard.expected.extend(expected)
        before_count = len(scoreboard.actual)
        pre = await self.cycle(start_valid=1, out_ready=0, **cfg)
        assert pre['start_ready'] and not pre['load_ready'], 'Start must have priority'
        overrides = dict(start_valid=0)
        if disturb:
            overrides.update(config(cfg_len=0, cfg_cluster_mask=0, cfg_unsigned_iact=1,
                                    cfg_reduce_rows=1, cfg_psum_slot=15))
            overrides.update(load_valid=1, load_kind=0, load_cluster_mask=15,
                             load_pe_mask=4095, load_addr=0, load_data=0)
        pre = await self.cycle(**overrides)
        assert not pre['load_ready'] and not pre['start_ready']
        await self.cycle(load_valid=0, start_valid=0)
        rng = random.Random(seed)
        stalled = None
        accepted, last_count, cycles = 0, 0, 0
        for _ in range(1200):
            ready = 1 if seed == 0 else int(rng.random() > 0.35)
            pre = await self.cycle(out_ready=ready)
            cycles += 1
            identity = tuple(pre[n] for n in ('out_cluster', 'out_pe', 'out_lane', 'out_psum', 'out_last'))
            if stalled is not None:
                assert pre['out_valid'] and identity == stalled, 'Output changed under backpressure'
            stalled = identity if pre['out_valid'] and not ready else None
            if pre['out_valid'] and ready:
                accepted += 1
                last_count += pre['out_last']
                assert pre['out_last'] == int(accepted == len(expected)), 'Incorrect last marker'
            if int(d.done.value):
                assert accepted == len(expected), 'Early completion'
                break
        else:
            raise AssertionError('Job did not complete within 1200 drain cycles')
        assert last_count == 1
        assert len(scoreboard.actual) - before_count == len(expected)
        assert int(d.compute_cycles.value) == cfg['cfg_len']
        assert int(d.mac_count.value) == cfg['cfg_cluster_mask'].bit_count() * 24 * cfg['cfg_len']
        assert not int(d.error.value)
        await self.cycle(out_ready=0)
        assert not int(d.done.value), 'done must be one cycle'
        assert not int(d.busy.value) and int(d.start_ready.value)
        return dict(compute_cycles=int(d.compute_cycles.value), macs=int(d.mac_count.value),
                    outputs=len(expected), drain_poll_cycles=cycles,
                    active_clusters=cfg['cfg_cluster_mask'].bit_count())


class Environment(uvm_component):
    def build_phase(self):
        self.driver = ArrayDriver('driver', self)
        self.monitor = OutputMonitor('monitor', self)
        self.scoreboard = Scoreboard('scoreboard', self)

    def connect_phase(self):
        self.monitor.ap.connect(self.scoreboard.analysis_export)


class BaseTest(uvm_test):
    def build_phase(self):
        self.env = Environment('env', self)

    async def run_phase(self):
        self.raise_objection()
        d = cocotb.top
        d.rst_n.value = 0
        for name in INPUTS:
            getattr(d, name).value = 0
        cocotb.start_soon(Clock(d.clk, 10, units='ns').start())
        self.dr, self.sb = self.env.driver, self.env.scoreboard
        await self.dr.reset()
        await self.scenario()
        await self.dr.cycle()
        await self.dr.cycle()
        self.drop_objection()

    async def job(self, data, cfg, seeds=False, **kwargs):
        await self.dr.program(data, cfg, seeds)
        return await self.dr.run_job(cfg, data.reference(cfg), self.sb, **kwargs)


@pyuvm.test()
class SignedDotProducts(BaseTest):
    async def scenario(self):
        data = Data(11)
        for c in range(4):
            for p in range(12):
                data.a[c][p][0] = -128 if p % 2 else 127
                data.w[c][p][95] = [-128, 127]
        await self.job(data, config(cfg_len=1, cfg_weight_base=95), seed=0)
        await self.job(data, config(cfg_len=16, cfg_weight_base=80), seed=7)


@pyuvm.test()
class UnsignedAndMulticast(BaseTest):
    async def scenario(self):
        data, cfg = Data(22), config(cfg_len=5, cfg_unsigned_iact=1)
        await self.dr.program(data, cfg)
        await self.dr.load(0, 0b1010, 0b101001010101, 2, 255)
        await self.dr.load(1, 0b0101, 0b010110101010, 3, 0x807f)
        await self.dr.load(0, 0, 4095, 0, 99)  # zero mask is a no-op
        for c in range(4):
            for p in range(12):
                if (0b1010 >> c) & (0b101001010101 >> p) & 1:
                    data.a[c][p][2] = 255
                if (0b0101 >> c) & (0b010110101010 >> p) & 1:
                    data.w[c][p][3] = [127, -128]
        await self.dr.run_job(cfg, data.reference(cfg), self.sb, seed=22)


@pyuvm.test()
class AccumulateAndWrap(BaseTest):
    async def scenario(self):
        data = Data(33)
        for c in range(4):
            for p in range(12):
                data.s[c][p][30:32] = [524280, -524280]
        cfg = config(cfg_len=16, cfg_psum_slot=15, cfg_accumulate=1)
        await self.job(data, cfg, seeds=True, seed=33)
        await self.dr.run_job(cfg, data.reference(cfg), self.sb, seed=34)
        other = config(cfg_len=3, cfg_psum_slot=0)
        await self.job(data, other, seed=35)
        await self.dr.run_job(cfg, data.reference(cfg), self.sb, seed=36)


@pyuvm.test()
class ConvolutionRowStationary(BaseTest):
    async def scenario(self):
        data = Data(44)
        image = [[(y * 13 + x * 7) % 31 - 15 for x in range(6)] for y in range(5)]
        kernels = [[[(oc + r * 3 + s) % 9 - 4 for s in range(3)]
                    for r in range(3)] for oc in range(8)]
        expected = []
        for c in range(4):
            y = c % 3
            for r in range(3):
                for x in range(4):
                    p = r * 4 + x
                    data.a[c][p][:3] = image[y + r][x:x+3]
                    for k in range(3):
                        data.w[c][p][k] = [kernels[2*c+l][r][k] for l in range(2)]
            expected.extend((c, x, l, convolution_at(image, kernels[2*c+l], y, x))
                            for x in range(4) for l in range(2))
        cfg = config(cfg_len=3, cfg_reduce_rows=1)
        await self.dr.program(data, cfg)
        await self.dr.run_job(cfg, expected, self.sb, seed=44)


@pyuvm.test()
class RandomizedJobs(BaseTest):
    async def scenario(self):
        rng = random.Random(20261021)
        for i in range(12):
            k = rng.choice([1, 2, 7, 16])
            cfg = config(cfg_len=k, cfg_weight_base=rng.randrange(97-k),
                         cfg_cluster_mask=rng.randrange(1, 16), cfg_psum_slot=rng.randrange(16),
                         cfg_unsigned_iact=i % 2, cfg_reduce_rows=(i // 2) % 2)
            await self.job(Data(100+i), cfg, seed=100+i)


@pyuvm.test()
class ProtocolAndConfiguration(BaseTest):
    async def scenario(self):
        cfg = config(cfg_len=16, cfg_cluster_mask=0b1010)
        data = Data(55)
        await self.job(data, cfg, seed=55, disturb=True)
        # Check that the attempted busy write did not corrupt activation address 0.
        await self.dr.run_job(cfg, data.reference(cfg), self.sb, seed=56)


@pyuvm.test()
class InvalidRequests(BaseTest):
    async def scenario(self):
        for cfg in [config(cfg_len=0), config(cfg_len=17),
                    config(cfg_len=2, cfg_weight_base=95), config(cfg_cluster_mask=0)]:
            await self.dr.cycle(start_valid=1, **cfg)
            await self.dr.cycle(start_valid=0)
            assert int(cocotb.top.error.value)
            assert not int(cocotb.top.busy.value) and not int(cocotb.top.out_valid.value)
        for kind, addr in [(0, 16), (1, 96), (2, 32), (3, 0)]:
            await self.dr.reset()
            await self.dr.load(kind, 15, 4095, addr, 99)
            assert int(cocotb.top.error.value)
        await self.job(Data(66), config(cfg_len=2, cfg_cluster_mask=1), seed=66)


@pyuvm.test()
class ResetAndAbort(BaseTest):
    async def scenario(self):
        data, cfg = Data(77), config(cfg_len=16)
        await self.dr.program(data, cfg)
        await self.dr.cycle(start_valid=1, **cfg)
        await self.dr.cycle(start_valid=0)
        assert int(cocotb.top.busy.value)
        await self.dr.reset()
        await self.dr.program(data, cfg)
        await self.dr.cycle(start_valid=1, **cfg)
        await self.dr.cycle(start_valid=0)
        for _ in range(25):
            await self.dr.cycle()
        assert int(cocotb.top.out_valid.value)
        await self.dr.reset()
        await self.job(data, cfg, seed=77)


@pyuvm.test()
class MetricsScaling(BaseTest):
    async def scenario(self):
        rows = []
        for mask in [1, 3, 15]:
            rows.append(await self.job(Data(88), config(cfg_len=16, cfg_cluster_mask=mask), seed=0))
        assert [r['macs'] for r in rows] == [384, 768, 1536]
        assert all(r['compute_cycles'] == 16 for r in rows)
        target = Path(os.environ.get('REPORT_DIR', 'reports/local'))
        target.mkdir(parents=True, exist_ok=True)
        (target / 'benchmark.json').write_text(json.dumps({
            'clock_period_ns': 10, 'note': 'Simulation clock is not a measured Fmax.',
            'rows': rows}, indent=2) + '\n')
