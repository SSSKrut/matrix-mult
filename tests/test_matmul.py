# cocotb-тесты matmul: зеркалируют tb_matmul.v — случайные матрицы,
# случайные паузы valid, случайный backpressure, сверка с эталоном.
#
# Как и в верилоговском ТБ, вся работа идёт по negedge: DUT тактируется
# по posedge, на negedge сигналы стабильны. ready, увиденный на negedge,
# гарантированно действует на следующем posedge.
import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

M = int(os.environ.get("MATMUL_M", 3))
K = int(os.environ.get("MATMUL_K", 4))
N = int(os.environ.get("MATMUL_N", 2))
ROUNDS = int(os.environ.get("MATMUL_ROUNDS", 20))

INT16_MIN, INT16_MAX = -32768, 32767


def matmul_ref(a, b):
    """C = A*B, все матрицы row-major списками."""
    return [
        sum(a[i * K + k] * b[k * N + j] for k in range(K))
        for i in range(M)
        for j in range(N)
    ]


async def setup(dut):
    Clock(dut.clk, 10, unit="ns").start()
    dut.rst.value = 1
    dut.a_valid.value = 0
    dut.b_valid.value = 0
    dut.c_ready.value = 0
    dut.a_data.value = 0
    dut.b_data.value = 0
    for _ in range(4):
        await FallingEdge(dut.clk)
    dut.rst.value = 0
    await FallingEdge(dut.clk)


async def feed(dut, valid, data, ready, values):
    for v in values:
        while random.random() < 0.3:
            await FallingEdge(dut.clk)
        valid.value = 1
        data.value = v & 0xFFFF
        while not ready.value:
            await FallingEdge(dut.clk)
        await FallingEdge(dut.clk)
        valid.value = 0


async def collect(dut, count):
    got = []
    for _ in range(count):
        while True:
            rdy = 1 if random.random() < 0.7 else 0
            dut.c_ready.value = rdy
            if rdy and dut.c_valid.value:
                break
            await FallingEdge(dut.clk)
        got.append(dut.c_data.value.to_signed())
        await FallingEdge(dut.clk)
        dut.c_ready.value = 0
    return got


async def run_round(dut, a, b):
    exp = matmul_ref(a, b)
    fa = cocotb.start_soon(feed(dut, dut.a_valid, dut.a_data, dut.a_ready, a))
    fb = cocotb.start_soon(feed(dut, dut.b_valid, dut.b_data, dut.b_ready, b))
    got = await collect(dut, M * N)
    await fa
    await fb
    assert got == exp, f"A={a} B={b}: получено {got}, ожидалось {exp}"


@cocotb.test()
async def test_stress(dut):
    """Все элементы -32768 — худший случай аккумуляции."""
    await setup(dut)
    a = [INT16_MIN] * (M * K)
    b = [INT16_MIN] * (K * N)
    await run_round(dut, a, b)


@cocotb.test()
async def test_random(dut):
    """ROUNDS раундов случайных матриц подряд, без сброса между ними."""
    await setup(dut)
    for _ in range(ROUNDS):
        a = [random.randint(INT16_MIN, INT16_MAX) for _ in range(M * K)]
        b = [random.randint(INT16_MIN, INT16_MAX) for _ in range(K * N)]
        await run_round(dut, a, b)
