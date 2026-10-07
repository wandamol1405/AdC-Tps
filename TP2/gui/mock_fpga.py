"""
mock_fpga.py - Simula del lado de la PC lo que haría la FPGA, para poder
probar la GUI y el protocolo antes de que el wiring final (loader_uart +
result_sender + ALU) esté programado en la placa real.

Replica 2 cosas, intencionalmente simplificadas respecto del RTL real:

1. MockALU: la misma tabla de operaciones de TP1/rtl/ALU.v (incluida la
   saturación con overflow de ADD) y el mismo patrón de habilitación "sticky"
   que arma el wiring final sin load_ctrl: una vez que A, B y Op se cargaron
   alguna vez por UART, la ALU queda habilitada para siempre.

2. MockSerialLink: entiende el protocolo addr+valor (2 bytes) que decodifica
   loader_uart.v, y devuelve el resultado como 2 bytes (resultado + status)
   cada vez que cambia algo, igual que result_sender.v -- incluyendo el envío
   garantizado del primer resultado aunque sea 0x00 (bit `sent_once` del
   RTL real).

Lo que NO replica (no hace falta para probar la GUI): la temporización bit a
bit de la UART real, ni la carrera de "la ALU cambia a mitad de la
transmisión" que resuelve el snapshot de result_sender.v -- el mock procesa
cada comando de una sola vez, no bit a bit.
"""

from protocol import ADDR_A, ADDR_B, ADDR_OP, encode_status, to_signed8, to_unsigned8


class MockALU:
    """Mismas 8 operaciones y flags que TP1/rtl/ALU.v, más el enable sticky."""

    def __init__(self):
        self.a = 0
        self.b = 0
        self.op = 0
        self.loaded_a = False
        self.loaded_b = False
        self.loaded_op = False

    @property
    def enabled(self):
        return self.loaded_a and self.loaded_b and self.loaded_op

    def load(self, addr, value):
        if addr == ADDR_A:
            self.a = value & 0xFF
            self.loaded_a = True
        elif addr == ADDR_B:
            self.b = value & 0xFF
            self.loaded_b = True
        elif addr == ADDR_OP:
            self.op = value & 0x3F  # reg_bank de Op es de 6 bits (igual que TP1/rtl/top.v)
            self.loaded_op = True
        else:
            raise ValueError(f"direccion invalida: 0x{addr:02X}")

    def compute(self):
        """(result_u8, overflow, carry). Si no está enabled, todo en 0 (igual que ALU.v)."""
        if not self.enabled:
            return 0, False, False

        a_s, b_s = to_signed8(self.a), to_signed8(self.b)
        overflow = False
        carry = False

        if self.op == 0b100000:  # ADD
            add_full = self.a + self.b  # suma sin signo de los patrones de bits, 9 bits
            carry = bool(add_full & 0x100)
            result = add_full & 0xFF
            sign_a, sign_result = (a_s < 0), (to_signed8(result) < 0)
            overflow = (a_s < 0) == (b_s < 0) and sign_result != sign_a
            if overflow:
                result = 0x80 if sign_a else 0x7F  # saturacion, igual que ALU.v
        elif self.op == 0b100010:  # SUB
            result = to_unsigned8(self.a - self.b)
        elif self.op == 0b100100:  # AND
            result = self.a & self.b
        elif self.op == 0b100101:  # OR
            result = self.a | self.b
        elif self.op == 0b100110:  # XOR
            result = self.a ^ self.b
        elif self.op == 0b000011:  # SRA (desplaza con signo, extiende el bit de signo)
            result = to_unsigned8(a_s >> self.b)
        elif self.op == 0b000010:  # SRL (desplaza sin signo)
            result = (self.a >> self.b) & 0xFF if self.b < 8 else 0
        elif self.op == 0b100111:  # NOR
            result = (~(self.a | self.b)) & 0xFF
        else:  # opcode invalido -> mismo default que ALU.v
            result = 0

        return result, overflow, carry


class MockSerialLink:
    """
    Misma interfaz que serial_link.RealSerialLink (write/poll/close), pero
    habla con un MockALU en vez de con hardware real.
    """

    def __init__(self):
        self.alu = MockALU()
        self._rx_buf = bytearray()  # bytes de la GUI todavia sin completar un par [addr, valor]
        self._pending_response = bytearray()  # listo para "llegar" en el proximo poll()
        self._available = bytearray()  # ya disponible para que poll() lo devuelva
        self._last_sent = None  # (result, overflow, carry) del ultimo envio, o None

    def write(self, data):
        self._rx_buf.extend(data)
        while len(self._rx_buf) >= 2:
            addr, value = self._rx_buf[0], self._rx_buf[1]
            del self._rx_buf[0:2]
            self._handle_load(addr, value)

    def _handle_load(self, addr, value):
        if addr not in (ADDR_A, ADDR_B, ADDR_OP):
            return  # direccion invalida: se descarta, igual que el fault recovery de loader_uart.v

        self.alu.load(addr, value)

        if not self.alu.enabled:
            return

        result, overflow, carry = self.alu.compute()
        current = (result, overflow, carry)
        if current != self._last_sent:
            self._last_sent = current
            status = encode_status(overflow, carry)
            self._pending_response.extend(bytes([result & 0xFF, status & 0xFF]))

    def poll(self):
        # Lo que se armó en el write() anterior "llega" en este poll (ver
        # docstring del módulo: no se simula el timing bit a bit real).
        self._available.extend(self._pending_response)
        self._pending_response.clear()
        out = bytes(self._available)
        self._available.clear()
        return out

    def close(self):
        pass

    def reset(self):
        """Solo tiene sentido en el mock: no hay comando de reset por UART real."""
        self.alu = MockALU()
        self._rx_buf.clear()
        self._pending_response.clear()
        self._available.clear()
        self._last_sent = None
