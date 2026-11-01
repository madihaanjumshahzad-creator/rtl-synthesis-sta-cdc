# cocotb tests for cdc_top (async FIFO)
# Inputs change on the falling edge of their own clock.
# Reference model is a deque: push on write, pop and compare on read.

import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer, RisingEdge

DEPTH = 16


async def start(dut, wper, rper):
    dut.winc.value = 0
    dut.rinc.value = 0
    dut.wdata.value = 0
    dut.arst_n.value = 0
    cocotb.start_soon(Clock(dut.wclk, wper, units="ps").start())
    cocotb.start_soon(Clock(dut.rclk, rper, units="ps").start())
    await Timer(5 * max(wper, rper), units="ps")
    dut.arst_n.value = 1
    for _ in range(4):
        await RisingEdge(dut.wclk)
        await RisingEdge(dut.rclk)


async def writer(dut, model, n, p_write, stats):
    sent = 0
    while sent < n:
        await FallingEdge(dut.wclk)
        if random.random() < p_write:
            if int(dut.wfull.value):
                stats["full_seen"] += 1
                dut.winc.value = 0
            else:
                val = random.getrandbits(32)
                dut.wdata.value = val
                dut.winc.value = 1
                model.append(val)
                sent += 1
        else:
            dut.winc.value = 0
    await FallingEdge(dut.wclk)
    dut.winc.value = 0


async def reader(dut, model, n, p_read, stats):
    got = 0
    while got < n:
        await FallingEdge(dut.rclk)
        if random.random() < p_read:
            if int(dut.rempty.value):
                stats["empty_seen"] += 1
                dut.rinc.value = 0
            else:
                assert model, "FIFO says not empty but the model is empty"
                exp = model.popleft()
                got_val = int(dut.rdata.value)
                assert got_val == exp, f"read {got_val:#x}, expected {exp:#x}"
                dut.rinc.value = 1
                got += 1
        else:
            dut.rinc.value = 0
    await FallingEdge(dut.rclk)
    dut.rinc.value = 0


@cocotb.test()
async def fill_and_drain(dut):
    # write 16 words, check full, then read all back
    await start(dut, 10000, 7300)
    vals = [random.getrandbits(32) for _ in range(DEPTH)]
    for v in vals:
        await FallingEdge(dut.wclk)
        assert not int(dut.wfull.value), "full too early"
        dut.wdata.value = v
        dut.winc.value = 1
    await FallingEdge(dut.wclk)
    dut.winc.value = 0
    await FallingEdge(dut.wclk)
    assert int(dut.wfull.value), "not full after DEPTH writes"

    # wait a few rclk cycles for the write pointer to get across
    for _ in range(6):
        await FallingEdge(dut.rclk)
    assert not int(dut.rempty.value)
    for v in vals:
        await FallingEdge(dut.rclk)
        assert not int(dut.rempty.value)
        assert int(dut.rdata.value) == v
        dut.rinc.value = 1
    await FallingEdge(dut.rclk)
    dut.rinc.value = 0
    await FallingEdge(dut.rclk)
    assert int(dut.rempty.value), "not empty after reading everything"


async def random_traffic(dut, wper, rper, pw, pr, n=2000):
    await start(dut, wper, rper)
    model = deque()
    stats = {"full_seen": 0, "empty_seen": 0}
    w = cocotb.start_soon(writer(dut, model, n, pw, stats))
    r = cocotb.start_soon(reader(dut, model, n, pr, stats))
    await w
    await r
    assert not model
    dut._log.info(f"wclk {wper} ps, rclk {rper} ps: {n} words, "
                  f"full seen {stats['full_seen']}x, empty seen {stats['empty_seen']}x")
    return stats


@cocotb.test()
async def fast_writer(dut):
    # fast writer, FIFO gets full often
    s = await random_traffic(dut, 4000, 11000, 0.9, 0.8)
    assert s["full_seen"] > 0


@cocotb.test()
async def fast_reader(dut):
    # fast reader, FIFO gets empty often
    s = await random_traffic(dut, 11000, 4000, 0.7, 0.9)
    assert s["empty_seen"] > 0


@cocotb.test()
async def near_equal_clocks(dut):
    # clocks 3% apart, phase drifts slowly
    await random_traffic(dut, 10000, 10300, 0.6, 0.6)
