"""
test_protocol.py - Tests de protocol.py, en particular del parser de
entrada (decimal/binario/hex) que usan los campos A/B de la GUI.

Correr con: python3 -m unittest test_protocol.py   (desde TP2/gui/)
"""

import unittest

from protocol import describe_byte, parse_int_auto, parse_with_format, to_signed8, to_unsigned8


class TestParseIntAuto(unittest.TestCase):
    def test_decimal(self):
        self.assertEqual(parse_int_auto("10"), 10)
        self.assertEqual(parse_int_auto("-5"), -5)
        self.assertEqual(parse_int_auto("  20  "), 20)

    def test_binario(self):
        self.assertEqual(parse_int_auto("0b1010"), 10)
        self.assertEqual(parse_int_auto("0B00001010"), 10)
        self.assertEqual(parse_int_auto("0b11111111"), 255)
        self.assertEqual(parse_int_auto("-0b1010"), -10)

    def test_hex(self):
        self.assertEqual(parse_int_auto("0x0A"), 10)
        self.assertEqual(parse_int_auto("0xFF"), 255)
        self.assertEqual(parse_int_auto("-0x0A"), -10)

    def test_vacio_o_invalido_lanza_valueerror(self):
        with self.assertRaises(ValueError):
            parse_int_auto("")
        with self.assertRaises(ValueError):
            parse_int_auto("abc")
        with self.assertRaises(ValueError):
            parse_int_auto("0b102")  # 2 no es un digito binario valido


class TestParseWithFormat(unittest.TestCase):
    def test_binario_sin_prefijo(self):
        # El caso que fallaba: escribir los bits directo, sin "0b" adelante.
        self.assertEqual(parse_with_format("1010", "Binario"), 10)
        self.assertEqual(parse_with_format("10000000", "Binario"), 128)
        self.assertEqual(parse_with_format("11111111", "Binario"), 255)
        self.assertEqual(parse_with_format("0", "Binario"), 0)

    def test_binario_con_prefijo_tambien_funciona(self):
        self.assertEqual(parse_with_format("0b1010", "Binario"), 10)

    def test_hex_sin_prefijo(self):
        self.assertEqual(parse_with_format("0A", "Hex"), 10)
        self.assertEqual(parse_with_format("FF", "Hex"), 255)

    def test_decimal_con_y_sin_signo(self):
        self.assertEqual(parse_with_format("10", "Decimal"), 10)
        self.assertEqual(parse_with_format("-5", "Decimal"), 251)  # to_unsigned8(-5)
        self.assertEqual(parse_with_format("255", "Decimal"), 255)

    def test_binario_invalido(self):
        with self.assertRaises(ValueError):
            parse_with_format("1012", "Binario")  # 2 no es bit valido
        with self.assertRaises(ValueError):
            parse_with_format("111111111", "Binario")  # 9 bits, fuera de rango

    def test_decimal_fuera_de_rango(self):
        with self.assertRaises(ValueError):
            parse_with_format("300", "Decimal")
        with self.assertRaises(ValueError):
            parse_with_format("-200", "Decimal")

    def test_vacio_lanza_valueerror(self):
        with self.assertRaises(ValueError):
            parse_with_format("", "Binario")


class TestDescribeByte(unittest.TestCase):
    def test_formato(self):
        self.assertEqual(describe_byte(0b00001010), "0b00001010 (0x0A = 10, 10 con signo)")

    def test_trunca_a_8_bits(self):
        # 0x1FF son 9 bits; solo deben quedar los 8 menos significativos (0xFF)
        self.assertIn("0b11111111", describe_byte(0x1FF))

    def test_valor_negativo_con_signo(self):
        texto = describe_byte(to_unsigned8(-1))  # 0xFF
        self.assertIn("-1 con signo", texto)

    def test_roundtrip_con_to_signed8(self):
        for value_u8 in (0, 1, 127, 128, 200, 255):
            self.assertIn(f"{to_signed8(value_u8)} con signo", describe_byte(value_u8))


if __name__ == "__main__":
    unittest.main()
