# GUI en Python — Consola UART de la ALU

GUI de escritorio (Tkinter) para cargar A, B y la operación por UART y ver el resultado que manda la FPGA, según el protocolo definido en [`TP2/README.md`](../README.md).

## Requisitos

- Python 3.
- [`pyserial`](https://pypi.org/project/pyserial/) para hablar con el puerto serie real (`pip install pyserial`). No hace falta para usar el modo mock.
- Tkinter (viene con la instalación estándar de Python en la mayoría de las distros; en Linux a veces hay que instalar el paquete `python3-tk` del sistema).

## Cómo correrla

```bash
cd TP2/gui
python3 app.py
```

En el combo de **Puerto** aparece siempre la opción **"Mock (sin hardware)"**, además de los puertos serie reales detectados (p. ej. `/dev/ttyUSB0`). Mientras el wiring final (`TP2/README.md`, sección "Pendiente", ítem 5) no esté programado en la Basys3, usar el mock para probar la GUI y el protocolo de punta a punta.

## Estructura

| Archivo | Qué hace |
|---|---|
| `protocol.py` | Codifica/decodifica el protocolo (direcciones `0x01`/`0x02`/`0x03`, opcodes de `ALU.v`, byte de status) y los helpers de formato: `parse_with_format` (el que usa la GUI, con el formato elegido explícitamente) y `describe_byte` (representación legible). Sin dependencias de UI ni de I/O — es lo que se testea más directo. |
| `serial_link.py` | `RealSerialLink`: wrapper no bloqueante sobre `pyserial` (8N1, `timeout=0`). |
| `mock_fpga.py` | `MockALU` (mismas 8 operaciones + saturación de `ALU.v`, con el enable "sticky" de A/B/Op) y `MockSerialLink`, que entiende el protocolo igual que `loader_uart.v` + `result_sender.v` lo harían. |
| `app.py` | La GUI. No le importa si `self.link` es `RealSerialLink` o `MockSerialLink` — ambas exponen `write()`/`poll()`/`close()`. |
| `test_mock_alu.py` | Compara `MockALU` contra los mismos casos dirigidos de `TP1/sim/tb_ALU.v` (ver `TP1/README.md`), para confirmar que el mock representa fielmente el hardware real. |
| `test_protocol.py` | Tests de `parse_with_format`/`describe_byte` (decimal, hex, binario sin prefijo, signo, rangos, truncado a 8 bits). |

Correr los tests: `python3 -m unittest test_mock_alu.py test_protocol.py -v` (desde esta carpeta).

## Qué hace la GUI

- **Conexión**: elegir puerto (real o mock) + baud (default `19200`, igual que `baud_rate_generator.v`) y Conectar/Desconectar.
- **Cargar operandos**: campos para A y B, cada uno con su propio selector de formato (**Decimal**, **Hex**, **Binario**) al lado. En **Binario** se escriben los bits directo, sin prefijo (ej. `10000000` para -128/128), nada de tener que anteponer `0b` a mano — es lo que hacía falta para poder ver el efecto de `AND`/`OR`/`XOR`/`SRA`/`SRL`/`NOR` bit a bit. **Decimal** admite signo (`-128..255`); **Hex** y **Binario** son directamente el patrón de bits sin signo (`0..255`, ej. `0A` o `FF` en Hex). A la derecha de cada campo se ve en vivo cómo queda interpretado ese valor, mientras se escribe. Combo con las 8 operaciones de la ALU (`ADD`, `SUB`, `AND`, `OR`, `XOR`, `SRA`, `SRL`, `NOR`), con su código de 6 bits al lado. Cada campo tiene su propio botón de carga, más un botón "Cargar los 3" — se puede recargar uno solo sin tocar los otros dos, igual que permite el enable sticky del lado hardware.
- **Resultado**: se actualiza solo, sin que la GUI tenga que pedir nada — el mock (y eventualmente `result_sender.v`) manda los 2 bytes automáticamente apenas cambia algo. Debajo del valor (con y sin signo) se muestran **A, B y Resultado alineados en binario**, uno debajo del otro, pensado específicamente para poder comparar a ojo el efecto bit a bit de `AND`/`OR`/`XOR`/`SRA`/`SRL`/`NOR`. Más los indicadores de Overflow/Carry, que se pintan rojos cuando están activos.
- **Reset (solo mock)**: no existe un comando de reset por UART real (el reset de la FPGA es el botón físico `btnD`); este botón solo tiene sentido para reiniciar el estado del mock entre pruebas, y queda deshabilitado cuando se está conectado a un puerto real.
- **Log**: todos los bytes enviados y recibidos, con su interpretación, para poder depurar el protocolo.

## Limitaciones a propósito del mock

`MockSerialLink` no simula la temporización bit a bit de la UART real (cada "trama" se procesa de una sola vez, no bit a bit), así que no reproduce la carrera que resuelve la "foto"/snapshot de `result_sender.v` (ALU cambiando a mitad de una transmisión real). Para eso ya está `TP2/sim/tb_result_sender.v`, que sí corre contra el RTL real. El mock alcanza para validar la GUI y el protocolo, no para reemplazar la verificación en Verilog.
