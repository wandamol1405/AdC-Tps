"""
app.py - GUI en Tkinter para cargar A/B/Op por UART y ver el resultado de la
ALU (TP2 - Arquitectura de Computadoras).

Uso:
    python3 app.py

Protocolo (ver TP2/README.md): 2 bytes para cargar un campo ([addr, valor]),
2 bytes de vuelta con el resultado ([resultado, status]) cada vez que la ALU
tiene algo nuevo para mostrar. El detalle de la codificación vive en
protocol.py.

Mientras no esté el wiring final en la FPGA, se puede elegir "Mock (sin
hardware)" como puerto: ahí se habla con mock_fpga.MockSerialLink en vez de
con un puerto serie real, para poder probar la GUI y el protocolo ya mismo.
"""

import tkinter as tk
from tkinter import ttk

from mock_fpga import MockSerialLink
from protocol import (
    ADDR_A,
    ADDR_B,
    ADDR_OP,
    FORMATS,
    OPCODES,
    decode_status,
    describe_byte,
    encode_load,
    parse_with_format,
    to_signed8,
)
from serial_link import RealSerialLink, list_ports

MOCK_LABEL = "Mock (sin hardware)"
POLL_MS = 50  # cada cuanto se revisa si llegaron bytes nuevos
BAUD_DEFAULT = 19200
DISPLAY_DEBOUNCE_MS = 200  # ver nota en _schedule_display_update


class App:
    def __init__(self, root):
        self.root = root
        self.root.title("TP2 - Consola UART de la ALU")

        self.link = None
        self._rx_buffer = bytearray()  # bytes de resultado que todavia no completan un par
        self._last_a = None  # ultimo A cargado con exito (0..255), para la vista en binario
        self._last_b = None  # idem para B
        self._pending_display = None  # (result, overflow, carry) a mostrar cuando se asiente la rafaga
        self._display_after_id = None  # id del after() pendiente del debounce

        self._build_ui()
        self._refresh_ports()
        self._set_connected_state(False)

    # ------------------------------------------------------------------
    # Construcción de la interfaz
    # ------------------------------------------------------------------
    def _build_ui(self):
        pad = {"padx": 6, "pady": 4}

        # --- Conexión ---
        conn = ttk.LabelFrame(self.root, text="Conexión")
        conn.grid(row=0, column=0, sticky="ew", **pad)

        ttk.Label(conn, text="Puerto:").grid(row=0, column=0, **pad)
        self.port_combo = ttk.Combobox(conn, width=22, state="readonly")
        self.port_combo.grid(row=0, column=1, **pad)

        ttk.Button(conn, text="Actualizar", command=self._refresh_ports).grid(row=0, column=2, **pad)

        ttk.Label(conn, text="Baud:").grid(row=0, column=3, **pad)
        self.baud_entry = ttk.Entry(conn, width=8)
        self.baud_entry.insert(0, str(BAUD_DEFAULT))
        self.baud_entry.grid(row=0, column=4, **pad)

        self.connect_btn = ttk.Button(conn, text="Conectar", command=self._on_connect_clicked)
        self.connect_btn.grid(row=0, column=5, **pad)

        self.status_label = ttk.Label(conn, text="Desconectado", foreground="#b00020")
        self.status_label.grid(row=0, column=6, **pad)

        # --- Carga de operandos ---
        load = ttk.LabelFrame(self.root, text="Cargar operandos")
        load.grid(row=1, column=0, sticky="ew", **pad)
        mono = ("TkFixedFont", 10)

        ttk.Label(load, text="A:").grid(row=0, column=0, **pad)
        self.a_entry = ttk.Entry(load, width=12)
        self.a_entry.insert(0, "0")
        self.a_entry.grid(row=0, column=1, **pad)
        self.a_format = ttk.Combobox(load, width=8, state="readonly", values=FORMATS)
        self.a_format.current(0)
        self.a_format.grid(row=0, column=2, **pad)
        self.a_entry.bind("<KeyRelease>", lambda _e: self._update_live_preview(self.a_entry, self.a_format, self.a_preview_label))
        self.a_format.bind("<<ComboboxSelected>>", lambda _e: self._update_live_preview(self.a_entry, self.a_format, self.a_preview_label))
        ttk.Button(load, text="Cargar A", command=self._on_load_a).grid(row=0, column=3, **pad)
        self.a_preview_label = ttk.Label(load, text="", font=mono)
        self.a_preview_label.grid(row=0, column=4, sticky="w", **pad)

        ttk.Label(load, text="B:").grid(row=1, column=0, **pad)
        self.b_entry = ttk.Entry(load, width=12)
        self.b_entry.insert(0, "0")
        self.b_entry.grid(row=1, column=1, **pad)
        self.b_format = ttk.Combobox(load, width=8, state="readonly", values=FORMATS)
        self.b_format.current(0)
        self.b_format.grid(row=1, column=2, **pad)
        self.b_entry.bind("<KeyRelease>", lambda _e: self._update_live_preview(self.b_entry, self.b_format, self.b_preview_label))
        self.b_format.bind("<<ComboboxSelected>>", lambda _e: self._update_live_preview(self.b_entry, self.b_format, self.b_preview_label))
        ttk.Button(load, text="Cargar B", command=self._on_load_b).grid(row=1, column=3, **pad)
        self.b_preview_label = ttk.Label(load, text="", font=mono)
        self.b_preview_label.grid(row=1, column=4, sticky="w", **pad)

        ttk.Label(load, text="Operación:").grid(row=2, column=0, **pad)
        self.op_combo = ttk.Combobox(load, width=8, state="readonly", values=list(OPCODES.keys()))
        self.op_combo.current(0)
        self.op_combo.grid(row=2, column=1, **pad)
        self.op_combo.bind("<<ComboboxSelected>>", lambda _e: self._update_op_preview())
        ttk.Button(load, text="Cargar Op", command=self._on_load_op).grid(row=2, column=3, **pad)
        self.op_preview_label = ttk.Label(load, text="", font=mono)
        self.op_preview_label.grid(row=2, column=4, sticky="w", **pad)

        ttk.Button(load, text="Cargar los 3", command=self._on_load_all).grid(row=0, column=5, rowspan=3, sticky="ns", **pad)

        self.mock_reset_btn = ttk.Button(load, text="Reset (solo mock)", command=self._on_mock_reset)
        self.mock_reset_btn.grid(row=0, column=6, rowspan=3, sticky="ns", **pad)

        hint = ttk.Label(
            load,
            text="Decimal admite signo (-128..255). Hex y Binario son el patrón de bits sin signo (0..255): "
            "en Binario se escriben los bits directo (ej. 10000000), sin prefijo.",
            foreground="#666",
        )
        hint.grid(row=3, column=0, columnspan=7, sticky="w", **pad)

        self._update_live_preview(self.a_entry, self.a_format, self.a_preview_label)
        self._update_live_preview(self.b_entry, self.b_format, self.b_preview_label)
        self._update_op_preview()

        # --- Resultado ---
        result = ttk.LabelFrame(self.root, text="Resultado")
        result.grid(row=2, column=0, sticky="ew", **pad)

        self.result_label = ttk.Label(result, text="Esperando datos...", font=("TkDefaultFont", 14, "bold"))
        self.result_label.grid(row=0, column=0, columnspan=2, sticky="w", **pad)

        # Vista alineada en binario de A, B y Resultado, para poder comparar
        # bit a bit el efecto de AND/OR/XOR/SRA/SRL/NOR.
        self.bits_label = ttk.Label(result, text="", font=mono, justify="left")
        self.bits_label.grid(row=1, column=0, columnspan=2, sticky="w", **pad)

        self.overflow_label = ttk.Label(result, text="Overflow", background="#444", foreground="white", padding=4)
        self.overflow_label.grid(row=2, column=0, **pad)
        self.carry_label = ttk.Label(result, text="Carry", background="#444", foreground="white", padding=4)
        self.carry_label.grid(row=2, column=1, **pad)

        # --- Log ---
        logf = ttk.LabelFrame(self.root, text="Log")
        logf.grid(row=3, column=0, sticky="nsew", **pad)
        self.root.grid_rowconfigure(3, weight=1)
        self.root.grid_columnconfigure(0, weight=1)

        self.log_text = tk.Text(logf, height=12, width=70, state="disabled")
        self.log_text.grid(row=0, column=0, sticky="nsew", **pad)
        logf.grid_rowconfigure(0, weight=1)
        logf.grid_columnconfigure(0, weight=1)
        ttk.Button(logf, text="Limpiar log", command=self._clear_log).grid(row=1, column=0, sticky="e", **pad)

    # ------------------------------------------------------------------
    # Conexión
    # ------------------------------------------------------------------
    def _refresh_ports(self):
        ports = list_ports()
        self.port_combo["values"] = [MOCK_LABEL] + ports
        if not self.port_combo.get():
            self.port_combo.current(0)

    def _on_connect_clicked(self):
        if self.link is not None:
            self._disconnect()
        else:
            self._connect()

    def _connect(self):
        selected = self.port_combo.get()
        try:
            if selected == MOCK_LABEL:
                self.link = MockSerialLink()
                self._log(f"Conectado al mock (sin hardware real)")
            else:
                baud = int(self.baud_entry.get())
                self.link = RealSerialLink(selected, baudrate=baud)
                self._log(f"Conectado a {selected} @ {baud} baud")
        except Exception as exc:  # puerto ocupado, no existe, baud invalido, etc.
            self._log(f"ERROR al conectar: {exc}")
            self.link = None
            return

        self._rx_buffer.clear()
        self._set_connected_state(True)
        self.root.after(POLL_MS, self._poll_loop)

    def _disconnect(self):
        if self.link is not None:
            self.link.close()
            self.link = None
        self._cancel_pending_display()
        self._set_connected_state(False)
        self._log("Desconectado")

    def _cancel_pending_display(self):
        if self._display_after_id is not None:
            self.root.after_cancel(self._display_after_id)
            self._display_after_id = None
        self._pending_display = None

    def _set_connected_state(self, connected):
        self.connect_btn.config(text="Desconectar" if connected else "Conectar")
        self.status_label.config(
            text="Conectado" if connected else "Desconectado",
            foreground="#2e7d32" if connected else "#b00020",
        )
        is_mock = connected and isinstance(self.link, MockSerialLink)
        self.mock_reset_btn.config(state="normal" if is_mock else "disabled")

    # ------------------------------------------------------------------
    # Envío de comandos
    # ------------------------------------------------------------------
    def _parse_byte_field(self, entry, fmt_combo, label):
        text = entry.get().strip()
        fmt = fmt_combo.get()
        try:
            return parse_with_format(text, fmt)
        except ValueError as exc:
            self._log(f"ERROR: '{text}' no es valido en formato {fmt} para {label} ({exc})")
            return None

    def _update_live_preview(self, entry, fmt_combo, preview_label):
        """Muestra en vivo, mientras se escribe, el byte que se va a mandar."""
        try:
            value_u8 = parse_with_format(entry.get().strip(), fmt_combo.get())
        except ValueError:
            preview_label.config(text="(valor invalido)", foreground="#b00020")
            return
        preview_label.config(text=f"= {describe_byte(value_u8)}", foreground="black")

    def _update_op_preview(self):
        op_name = self.op_combo.get()
        code = OPCODES[op_name]
        self.op_preview_label.config(text=f"= 0b{code:06b}")

    def _send_load(self, addr, value, label):
        if self.link is None:
            self._log("ERROR: no hay conexion activa")
            return
        frame = encode_load(addr, value)
        self.link.write(frame)
        self._log(f"TX  {label}=0x{value:02X}  (frame: {frame.hex(' ')})")

    def _on_load_a(self):
        value = self._parse_byte_field(self.a_entry, self.a_format, "A")
        if value is not None:
            self._send_load(ADDR_A, value, "A")
            self._last_a = value

    def _on_load_b(self):
        value = self._parse_byte_field(self.b_entry, self.b_format, "B")
        if value is not None:
            self._send_load(ADDR_B, value, "B")
            self._last_b = value

    def _on_load_op(self):
        op_name = self.op_combo.get()
        self._send_load(ADDR_OP, OPCODES[op_name], f"Op({op_name})")

    def _on_load_all(self):
        self._on_load_a()
        self._on_load_b()
        self._on_load_op()

    def _on_mock_reset(self):
        if isinstance(self.link, MockSerialLink):
            self.link.reset()
            self._last_a = None
            self._last_b = None
            self._cancel_pending_display()
            self.result_label.config(text="Esperando datos...")
            self.bits_label.config(text="")
            self._set_flag_label(self.overflow_label, False)
            self._set_flag_label(self.carry_label, False)
            self._log("Mock reiniciado (A/B/Op sin cargar)")

    # ------------------------------------------------------------------
    # Recepción (polling no bloqueante, igual para mock y puerto real)
    # ------------------------------------------------------------------
    def _poll_loop(self):
        if self.link is None:
            return  # se desconectó mientras esperaba el próximo after()

        try:
            data = self.link.poll()
        except Exception as exc:
            self._log(f"ERROR leyendo el puerto: {exc}")
            self._disconnect()
            return

        if data:
            self._rx_buffer.extend(data)
            self._consume_result_frames()

        self.root.after(POLL_MS, self._poll_loop)

    def _consume_result_frames(self):
        while len(self._rx_buffer) >= 2:
            result_byte = self._rx_buffer[0]
            status_byte = self._rx_buffer[1]
            del self._rx_buffer[0:2]

            overflow, carry = decode_status(status_byte)
            signed = to_signed8(result_byte)
            self._log(f"RX  resultado=0x{result_byte:02X} ({signed})  status=0x{status_byte:02X} (ov={int(overflow)} ca={int(carry)})")

            # No actualizamos el panel grande al toque: como la ALU manda un
            # resultado automático cada vez que CUALQUIER campo cambia (no
            # hay comando EXEC), "Cargar los 3" en realidad manda 3 cargas
            # separadas y puede generar 2-3 respuestas intermedias antes de
            # la que corresponde a los 3 valores ya cargados. El log las
            # muestra todas (arriba); acá sólo programamos mostrar en el
            # panel grande la ÚLTIMA de la ráfaga, una vez que se asienta.
            self._schedule_display_update(result_byte, overflow, carry)

    def _schedule_display_update(self, result_byte, overflow, carry):
        self._pending_display = (result_byte, overflow, carry)
        if self._display_after_id is not None:
            self.root.after_cancel(self._display_after_id)
        self._display_after_id = self.root.after(DISPLAY_DEBOUNCE_MS, self._commit_display)

    def _commit_display(self):
        self._display_after_id = None
        if self._pending_display is None:
            return
        result_byte, overflow, carry = self._pending_display
        self._pending_display = None

        signed = to_signed8(result_byte)
        self.result_label.config(text=f"Resultado: {signed}  (0x{result_byte:02X}, sin signo {result_byte})")
        self._update_bits_view(result_byte)
        self._set_flag_label(self.overflow_label, overflow)
        self._set_flag_label(self.carry_label, carry)

    def _update_bits_view(self, result_u8):
        """Alinea A, B y Resultado en binario, uno debajo del otro, para
        poder comparar a ojo el efecto de AND/OR/XOR/SRA/SRL/NOR."""
        lines = []
        if self._last_a is not None:
            lines.append(f"A      = 0b{self._last_a:08b}  (0x{self._last_a:02X} = {self._last_a})")
        if self._last_b is not None:
            lines.append(f"B      = 0b{self._last_b:08b}  (0x{self._last_b:02X} = {self._last_b})")
        lines.append(f"Result = 0b{result_u8:08b}  (0x{result_u8:02X} = {result_u8})")
        self.bits_label.config(text="\n".join(lines))

    @staticmethod
    def _set_flag_label(label, active):
        label.config(background="#c62828" if active else "#444")

    # ------------------------------------------------------------------
    # Log
    # ------------------------------------------------------------------
    def _log(self, line):
        self.log_text.config(state="normal")
        self.log_text.insert("end", line + "\n")
        self.log_text.see("end")
        self.log_text.config(state="disabled")

    def _clear_log(self):
        self.log_text.config(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.config(state="disabled")


def main():
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
