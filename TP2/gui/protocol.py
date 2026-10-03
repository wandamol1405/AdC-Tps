"""
protocol.py - Codificación/decodificación del protocolo UART definido en TP2/README.md

FORMATO DE CARGA (GUI -> FPGA), 2 bytes por campo:
    byte 1 = dirección (ADDR_OP / ADDR_A / ADDR_B)
    byte 2 = valor

FORMATO DE RESULTADO (FPGA -> GUI), 2 bytes, se mandan solos cuando cambia algo:
    byte 1 = resultado (o_result, 8 bits)
    byte 2 = status    = {6'b0, overflow, carry}  (bit 1 = overflow, bit 0 = carry)

Los códigos de operación son los mismos 6 bits que usa TP1/rtl/ALU.v.
"""

ADDR_OP = 0x01
ADDR_A = 0x02
ADDR_B = 0x03

ADDR_NAMES = {ADDR_OP: "Op", ADDR_A: "A", ADDR_B: "B"}

# Mismos códigos que TP1/rtl/ALU.v (6 bits, pero se mandan en un byte completo;
# el hardware solo usa los 6 bits menos significativos al cargar el registro de Op).
OPCODES = {
    "ADD": 0b100000,
    "SUB": 0b100010,
    "AND": 0b100100,
    "OR": 0b100101,
    "XOR": 0b100110,
    "SRA": 0b000011,
    "SRL": 0b000010,
    "NOR": 0b100111,
}
OPCODE_NAMES = {code: name for name, code in OPCODES.items()}


def encode_load(addr, value_byte):
    """Arma los 2 bytes [addr, valor] para cargar un campo (A, B u Op)."""
    return bytes([addr & 0xFF, value_byte & 0xFF])


def decode_status(status_byte):
    """Separa el byte de status en (overflow, carry), ambos bool."""
    overflow = bool(status_byte & 0b10)
    carry = bool(status_byte & 0b01)
    return overflow, carry


def encode_status(overflow, carry):
    """Inverso de decode_status, para armar el byte de status desde el mock."""
    return (1 if overflow else 0) << 1 | (1 if carry else 0)


def to_signed8(value_u8):
    """0..255 -> -128..127 (interpretación en complemento a 2)."""
    value_u8 &= 0xFF
    return value_u8 - 256 if value_u8 >= 128 else value_u8


def to_unsigned8(value_s8):
    """Cualquier entero -> 0..255, truncando a 8 bits (complemento a 2)."""
    return value_s8 & 0xFF


def parse_int_auto(text):
    """
    Convierte texto a entero aceptando decimal, binario (prefijo 0b) y
    hexadecimal (prefijo 0x), con signo opcional. Pensado para los campos de
    A/B de la GUI, para poder escribir el patrón de bits directo (ej.
    '0b10110000') en vez de tener que calcular el decimal a mano.

    Ejemplos válidos: "10", "-5", "0x0A", "0b1010", "-0b1010".
    Lanza ValueError si el texto no matchea ninguno de esos formatos.
    """
    text = text.strip()
    if not text:
        raise ValueError("campo vacio")

    negative = text.startswith("-")
    body = text[1:] if negative else text
    body_lower = body.lower()

    if body_lower.startswith("0b"):
        value = int(body, 2)
    elif body_lower.startswith("0x"):
        value = int(body, 16)
    else:
        value = int(body, 10)

    return -value if negative else value


FORMATS = ("Decimal", "Hex", "Binario")


def parse_with_format(text, fmt):
    """
    Convierte texto a un byte sin signo (0..255) según un formato elegido
    explícitamente ('Decimal', 'Hex' o 'Binario') -- a diferencia de
    parse_int_auto, acá no hace falta ningún prefijo: en modo 'Binario' basta
    con escribir los bits directo (ej. '10000000'), sin tener que escribir
    '0b10000000' a mano. Es lo que usan los campos A/B de la GUI con su
    selector de formato.

    - 'Decimal' acepta signo (-128..127) además de sin signo (0..255).
    - 'Hex' y 'Binario' son directamente el patrón de bits sin signo
      (0..255); si el usuario de todas formas escribe el prefijo (0x/0b) o
      un signo, también se aceptan, para no romper nada si alguien los usa.

    Devuelve siempre un entero 0..255. Lanza ValueError si el texto no es
    válido en el formato elegido, o si decimal queda fuera de -128..255.
    """
    text = text.strip()
    if not text:
        raise ValueError("campo vacio")

    if fmt == "Decimal":
        value = int(text, 10)
        if not (-128 <= value <= 255):
            raise ValueError("fuera de rango (-128..255)")
        return to_unsigned8(value) if value < 0 else value

    negative = text.startswith("-")
    body = text[1:] if negative else text

    if fmt == "Binario":
        if body.lower().startswith("0b"):
            body = body[2:]
        value = int(body, 2)
    elif fmt == "Hex":
        if body.lower().startswith("0x"):
            body = body[2:]
        value = int(body, 16)
    else:
        raise ValueError(f"formato desconocido: {fmt}")

    if negative:
        value = -value
    if not (0 <= value <= 255):
        raise ValueError("fuera de rango (0..255)")
    return value


def describe_byte(value_u8, bits=8):
    """
    Representación legible de un byte en binario/hex/decimal, para mostrar
    en la GUI el patrón de bits exacto que se cargó o que llegó de resultado
    -- útil para comparar a ojo el efecto de AND/OR/XOR/SRA/SRL/NOR.

    Ej: describe_byte(0b00001010) -> "0b00001010 (0x0A = 10)"
    """
    value_u8 &= (1 << bits) - 1
    return f"0b{value_u8:0{bits}b} (0x{value_u8:02X} = {value_u8}, {to_signed8(value_u8)} con signo)"
