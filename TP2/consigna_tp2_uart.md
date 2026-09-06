# Trabajo Práctico N°2 — UART
### Arquitectura de Computadoras

## 1. Objetivo

Diseñar e implementar en **Verilog**, modelando cada bloque como una **Máquina de Estado Finita (FSM)**, un módulo de comunicación serie **UART** (Universal Asynchronous Receiver/Transmitter) capaz de recibir y transmitir datos en forma asíncrona, integrado a la arquitectura del procesador visto en la cátedra (ALU + Interface Circuit + UART).

## 2. Consideraciones generales de diseño (según lo indicado en clase)

- Todo el diseño debe modelarse explícitamente como **FSM**, separando:
  - la **lógica de próximo estado** (`next_state`),
  - el **registro de estado** (`state`, actualizado sólo en `posedge clock`),
  - y la **lógica de salida**.
- Usar **`parameter`** o **`localparam`** para nombrar/codificar los estados (no "números mágicos" sueltos en el código).
- Las máquinas de estado deben ser **seguras**: ante una entrada desconocida o el ingreso a un estado inválido, deben contemplar un `default` que lleve a un **estado de recuperación** (*fault recovery*) en el ciclo siguiente. No se pide (salvo que la cátedra indique lo contrario) optimizar por sobre esta robustez sacrificando el estado de recuperación (eso sería una "máquina de estado rápida", con menos lógica pero menos segura).
- Cada bloque (Baud Rate Generator, Rx, Tx) debe implementarse como un **módulo** separado, instanciado luego en un módulo de nivel superior.

## 3. Formato de la trama serie (frame UART)

La comunicación es **asíncrona**: no hay clock compartido entre transmisor y receptor, por lo que el propio frame debe permitir reconstruir el timing.

```
 start bit        data byte             parity bit   stop bit
 (lógico 0)       (6 a 8 bits)           (opcional)   (lógico 1)
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ S │D0 │D1 │D2 │D3 │D4 │D5 │D6 │D7 │PB │ P │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                                                  ──▶ time
```

- **Start bit**: la línea, en reposo en `1`, cae a `0` para indicar el inicio de una trama.
- **Data byte**: entre 6 y 8 bits de datos (a definir según lo que indique la cátedra; se recomienda 8 bits salvo indicación contraria), transmitidos LSB primero.
- **Parity bit** (opcional): bit de paridad.
- **Stop bit**: uno o más bits en `1` que marcan el fin de la trama.

## 4. Baud Rate Generator

- Debe generar un **tick** (`s_tick`) **16 veces por cada bit** transmitido/recibido (sobremuestreo 16x), para poder ubicar con precisión el punto medio de cada bit.
- El módulo del contador se calcula como:

  ```
          Clock
  ──────────────────  ≈  N
     BaudRate × 16
  ```

- **Ejemplo dado en clase**: con clock de placa de **50 MHz** y baud rate de **19.200**, se necesitan 19.200 × 16 = 307.200 ticks/seg ⇒ N ≈ 163. El Baud Rate Generator es, en ese caso, un **contador módulo 163**.
- El valor de `N`, el clock y el baud rate reales a usar deben ajustarse según la placa/entorno de trabajo indicado por la cátedra.

## 5. Receptor (Rx)

### 5.1 Idea general (explicada en clase, 6 pasos)

1. Esperar a que la entrada `rx` sea `0` (comienzo del start bit) e iniciar el contador de ticks.
2. Cuando el contador llega a **7**, la señal está en el punto medio del start bit (se confirma que no es ruido). Reiniciar el contador.
3. Cuando el contador llega a **15**, la señal alcanzó la mitad del bit de dato actual: tomar ese valor, cargarlo en un **shift register**, y reiniciar el contador.
4. Repetir el paso 3 tantas veces como bits de datos falten.
5. Si se usa paridad, repetir el paso 3 una vez más para el bit de paridad.
6. Repetir el paso 3 tantas veces como bits de stop tenga la trama.

### 5.2 Diagrama de estados (ASM) presentado en clase

El receptor se modela con **4 estados**: `idle`, `start`, `data`, `stop`, usando:

- `s`: contador de ticks dentro del bit actual (0 a 15).
- `n`: contador de bits de datos ya recibidos.
- `b`: shift register donde se van cargando los bits recibidos.
- `s_tick`: tick generado por el Baud Rate Generator.
- `D_BIT`: cantidad de bits de datos (parámetro).
- `SB_TICK`: cantidad de ticks correspondientes a los bits de stop (parámetro).

```
idle:
    if (rx == 0)         s ← 0                      → start

start:
    if (s_tick == 1)
        if (s == 7)       s ← 0 ; n ← 0              → data
        else              s ← s + 1                  (queda en start)

data:
    if (s_tick == 1)
        if (s == 15)
            s ← 0 ; b ← {rx, b[7:1]}
            if (n == D_BIT - 1)                      → stop
            else          n ← n + 1                  (queda en data)
        else              s ← s + 1                  (queda en data)

stop:
    if (s_tick == 1)
        if (s == SB_TICK - 1)   rx_done_tick ← 1      → idle
        else                    s ← s + 1             (queda en stop)
```

> Nota: éste es el **diagrama de referencia dado en clase**; se debe traducir fielmente a Verilog respetando la separación entre lógica de próximo estado, registro de estado y lógica de salida (sección 2).

### 5.3 Interfaz del módulo Rx

| Señal | Dirección | Descripción |
|---|---|---|
| `rx` | in | Entrada serie |
| `clk` | in | Clock del sistema |
| `s_tick` | in | Tick del Baud Rate Generator (16x baud rate) |
| `dout` / `d_out` | out | Dato paralelo recibido |
| `rx_done_tick` / `rx_done` | out | Pulso que indica dato recibido y válido |

## 6. Transmisor (Tx)

El transmisor debe resolverse con una **FSM análoga** a la del receptor (estados `idle`, `start`, `data`, `stop`), pero en sentido inverso: en lugar de muestrear la entrada serie, debe **armar** la trama de salida bit a bit a partir de un dato paralelo, respetando el mismo formato de frame (sección 3) y el mismo tick de 16x generado por el Baud Rate Generator.

Interfaz sugerida:

| Señal | Dirección | Descripción |
|---|---|---|
| `tx` | out | Salida serie |
| `clk` | in | Clock del sistema |
| `s_tick` | in | Tick del Baud Rate Generator |
| `d_in` | in | Dato paralelo a transmitir |
| `tx_start` | in | Solicitud de inicio de transmisión |
| `tx_done` | out | Pulso que indica fin de transmisión |

## 7. Interface Circuit

Bloque que conecta la UART (Rx/Tx) con la ALU, exponiendo un protocolo simple de *handshake*:

- **Lectura (lado Rx → ALU)**: `r_data` (dato), `rd` (pedido de lectura), `rx_empty` (flag: no hay dato disponible).
- **Escritura (lado ALU → Tx)**: `w_data` (dato), `wr` (pedido de escritura), `tx_full` (flag: buffer de transmisión ocupado).

## 8. Arquitectura completa a integrar

```
RX ──▶ Rx (FSM) ──dout, rx_done_tick──▶ Interface Circuit ──r_data, rx_empty──▶ ALU
                        ▲
TX ◀── Tx (FSM) ◀──d_in, tx_start── Interface Circuit ◀──w_data, wr── ALU
                        ▲
                Baud Rate Generator (rate, clk) ──s_tick──▶ Rx, Tx
```

## 9. Entregables

- Código fuente en Verilog: `baud_rate_generator.v`, `uart_rx.v`, `uart_tx.v`, `interface_circuit.v`, y el módulo top `uart.v` que los integra.
- Testbenches de Rx y Tx (y, opcionalmente, un test de *loopback* Tx→Rx end-to-end).
- Breve informe/README explicando las decisiones de diseño tomadas (valor de `N` del Baud Rate Generator, cantidad de bits de datos y de stop usados, si se implementó paridad, manejo del estado de recuperación, etc.).

> Los valores puntuales de baud rate, frecuencia de clock, cantidad de bits de datos/stop, uso o no de paridad, fecha de entrega y modalidad de presentación deben confirmarse con la cátedra, ya que no quedaron fijados de forma explícita en el material de la clase y pueden variar según la placa/entorno de trabajo indicado.
