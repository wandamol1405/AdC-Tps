"""
test_mock_alu.py - Compara MockALU contra los mismos casos dirigidos que usa
TP1/sim/tb_ALU.v (ver la tabla de resultados en TP1/README.md), para
confirmar que el mock representa fielmente lo que hace el hardware real.

Correr con: python3 -m unittest test_mock_alu.py   (desde TP2/gui/)
"""

import unittest

from mock_fpga import MockALU
from protocol import ADDR_A, ADDR_B, ADDR_OP, OPCODES, to_unsigned8

# (a, b, opcode, resultado_esperado, overflow_esperado, carry_esperado)
# 'a'/'b' en decimal con signo, igual que se loguea en TP1/README.md.
CASES = [
    (10, 20, "ADD", 30, False, False),
    (-5, 3, "ADD", 254, False, False),
    (-1, 1, "ADD", 0, False, True),  # ADD-CA
    (127, 1, "ADD", 127, True, False),  # ADD-OVP
    (127, 127, "ADD", 127, True, False),  # ADD-OVP
    (-128, -128, "ADD", 128, True, True),  # ADD-OVN
    (20, 10, "SUB", 10, False, False),
    (10, 20, "SUB", 246, False, False),
    (-8, -8, "SUB", 0, False, False),
    (-52, -86, "AND", 136, False, False),
    (-1, 0, "AND", 0, False, False),
    (-52, -86, "OR", 238, False, False),
    (0, 0, "OR", 0, False, False),
    (-52, -86, "XOR", 102, False, False),
    (-1, -1, "XOR", 0, False, False),
    (-128, 2, "SRA", 224, False, False),
    (64, 3, "SRA", 8, False, False),
    (-128, 2, "SRL", 32, False, False),
    (64, 3, "SRL", 8, False, False),
    (-52, -86, "NOR", 17, False, False),
    (0, 0, "NOR", 255, False, False),
]


class TestMockALUContraTbALU(unittest.TestCase):
    def test_casos_dirigidos_de_tp1(self):
        for a, b, op_name, expected_result, expected_ov, expected_ca in CASES:
            with self.subTest(op=op_name, a=a, b=b):
                alu = MockALU()
                alu.load(ADDR_A, to_unsigned8(a))
                alu.load(ADDR_B, to_unsigned8(b))
                alu.load(ADDR_OP, OPCODES[op_name])

                result, overflow, carry = alu.compute()

                self.assertEqual(result, expected_result, "resultado")
                self.assertEqual(overflow, expected_ov, "overflow")
                self.assertEqual(carry, expected_ca, "carry")

    def test_opcode_invalido_da_cero(self):
        alu = MockALU()
        alu.load(ADDR_A, 5)
        alu.load(ADDR_B, 5)
        alu.load(ADDR_OP, 0b111111)  # INVAL, igual que tb_ALU.v

        result, overflow, carry = alu.compute()

        self.assertEqual(result, 0)
        self.assertFalse(overflow)
        self.assertFalse(carry)

    def test_no_habilitada_hasta_cargar_los_3_campos(self):
        alu = MockALU()
        self.assertFalse(alu.enabled)
        alu.load(ADDR_A, 50)
        self.assertFalse(alu.enabled)
        alu.load(ADDR_B, 10)
        self.assertFalse(alu.enabled)
        alu.load(ADDR_OP, OPCODES["ADD"])
        self.assertTrue(alu.enabled)
        self.assertEqual(alu.compute(), (60, False, False))

    def test_recargar_un_solo_campo_mantiene_habilitada(self):
        alu = MockALU()
        alu.load(ADDR_A, to_unsigned8(15))
        alu.load(ADDR_B, to_unsigned8(5))
        alu.load(ADDR_OP, OPCODES["SUB"])
        self.assertEqual(alu.compute()[0], 10)

        alu.load(ADDR_B, to_unsigned8(3))  # solo se recarga B
        self.assertTrue(alu.enabled)
        self.assertEqual(alu.compute()[0], 12)


if __name__ == "__main__":
    unittest.main()
