"""
serial_link.py - Conexión real por puerto serie (pyserial), con la misma
interfaz que mock_fpga.MockSerialLink para que app.py no tenga que distinguir
entre "estoy hablando con la FPGA real" y "estoy hablando con el mock".

Interfaz común (duck typing, sin ABC porque son solo 2 implementaciones):
    write(data: bytes) -> None       # manda bytes, no bloquea
    poll() -> bytes                  # devuelve los bytes recibidos desde el
                                      # último poll() (puede ser vacío)
    close() -> None
"""

import serial
import serial.tools.list_ports


def list_ports():
    """Nombres de los puertos serie disponibles en el sistema (p.ej. /dev/ttyUSB0)."""
    return [p.device for p in serial.tools.list_ports.comports()]


class RealSerialLink:
    """
    Wrapper fino sobre pyserial. Se abre con timeout=0 (no bloqueante): un
    read() siempre vuelve al instante con lo que haya disponible, aunque sea
    nada. Así poll() se puede llamar seguido desde el loop de Tkinter sin
    trabar la interfaz esperando bytes que todavía no llegaron.
    """

    def __init__(self, port, baudrate=19200):
        self._ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0,
        )

    def write(self, data):
        self._ser.write(data)

    def poll(self):
        # read() con timeout=0 es no bloqueante: devuelve lo que haya, o b""
        waiting = self._ser.in_waiting
        return self._ser.read(waiting) if waiting else b""

    def close(self):
        self._ser.close()
