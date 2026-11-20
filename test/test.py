# SPDX-FileCopyrightText: © 2026 Ayman Ishraq Zoha
# SPDX-License-Identifier: Apache-2.0
#
# Tests for the 4-bit CPU. A small Python model of the CPU runs alongside the
# real hardware and every clock cycle we check the chip matches the model.

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

DEMO_ROM = [0x11, 0x90, 0x10, 0x70, 0xD0, 0xA0, 0xB3] + [0x00] * 9


class Model:
    """Reference model: what the CPU *should* do, written in plain Python."""

    def __init__(self):
        self.A = self.B = self.PC = 0
        self.C = self.Z = self.halted = 0

    def step(self, instr):
        if self.halted:
            return
        op, k = instr >> 4, instr & 0xF
        nxt = (self.PC + 1) & 0xF
        if op == 0x1:
            self.A = k
        elif op in (0x2, 0x7):
            x = self.B if op == 0x7 else k
            s = self.A + x
            self.A, self.C, self.Z = s & 0xF, s >> 4, int(s & 0xF == 0)
        elif op in (0x3, 0x8):
            x = self.B if op == 0x8 else k
            d = self.A + (~x & 0xF) + 1
            self.A, self.C, self.Z = d & 0xF, (d >> 4) & 1, int(d & 0xF == 0)
        elif op in (0x4, 0x5, 0x6):
            r = {4: self.A & k, 5: self.A | k, 6: self.A ^ k}[op]
            self.A, self.Z = r, int(r == 0)
        elif op == 0x9:
            self.B = self.A
        elif op == 0xA:
            self.A, self.B = self.B, self.A
            self.Z = int(self.A == 0)
        elif op == 0xB:
            nxt = k
        elif op == 0xC and self.Z:
            nxt = k
        elif op == 0xD and self.C:
            nxt = k
        elif op == 0xE:
            self.A = ~self.A & 0xF
            self.Z = int(self.A == 0)
        elif op == 0xF:
            self.halted, nxt = 1, self.PC
        self.PC = nxt

    def outputs(self):
        return (self.halted << 6) | (self.Z << 5) | (self.C << 4) | self.A


async def start(dut, external):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0x80 if external else 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1


async def run_and_check(dut, program, cycles, external=True):
    """Run `program`, feeding instructions by the PC the chip puts out,
    and compare against the model after every clock edge."""
    m = Model()
    trace = []
    for _ in range(cycles):
        pc = int(dut.uio_out.value) & 0xF
        assert pc == m.PC, f"PC mismatch: chip {pc}, model {m.PC}"
        instr = program[pc]
        if external:
            dut.ui_in.value = instr
        m.step(instr)
        await FallingEdge(dut.clk)
        got = int(dut.uo_out.value)
        assert got == m.outputs(), (
            f"after instr {instr:02X} at PC {pc}: chip {got:07b}, model {m.outputs():07b}"
        )
        trace.append(m.A)
    return trace


@cocotb.test()
async def test_pins_after_reset(dut):
    await start(dut, external=True)
    assert int(dut.uo_out.value) == 0
    assert int(dut.uio_out.value) == 0
    assert int(dut.uio_oe.value) == 0x0F


@cocotb.test()
async def test_demo_fibonacci(dut):
    await start(dut, external=False)
    trace = await run_and_check(dut, DEMO_ROM, 60, external=False)
    # Pull out the values of A right after each SWAP: the Fibonacci numbers
    seen = []
    for v in trace:
        if not seen or seen[-1] != v:
            seen.append(v)
    dut._log.info(f"A over time: {seen}")
    for fib in (1, 2, 3, 5, 8, 13):
        assert fib in seen


@cocotb.test()
async def test_add_carry_and_jumps(dut):
    await start(dut, external=True)
    prog = [
        0x1F,  # 0 LDI 15
        0x21,  # 1 ADDI 1   -> A=0, C=1, Z=1
        0xD5,  # 2 JC 5     (taken)
        0x17,  # 3 LDI 7    (skipped)
        0xF0,  # 4 HLT      (skipped)
        0xC8,  # 5 JZ 8     (taken)
        0x17,  # 6 skipped
        0xF0,  # 7 skipped
        0x13,  # 8 LDI 3
        0x35,  # 9 SUBI 5   -> A=14, C=0 (borrow)
        0xE0,  # A NOT      -> A=1
        0xF0,  # B HLT
    ] + [0x00] * 4
    await run_and_check(dut, prog, 20)
    assert int(dut.uo_out.value) & 0xF == 1
    assert (int(dut.uo_out.value) >> 6) & 1 == 1  # halted


@cocotb.test()
async def test_random_programs(dut):
    await start(dut, external=True)
    rng = random.Random(2026)
    for _ in range(40):
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 2)
        await FallingEdge(dut.clk)
        dut.rst_n.value = 1
        prog = [rng.randrange(256) for _ in range(16)]
        await run_and_check(dut, prog, 50)
