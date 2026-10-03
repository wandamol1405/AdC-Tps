# TP2 — UART (Baud Rate Generator, Rx, Tx) integrada a la ALU de TP1

**Materia:** Arquitectura de Computadoras

**Carrera:** Ingeniería en Computación

**Alumnas:** Molina Maria Wanda - Verdú Melisa Noel

## Objetivo

Según la consigna (`consigna_tp2_uart.md`):

- Diseñar e implementar en Verilog, modelando cada bloque como una **FSM explícita** (lógica de próximo estado / registro de estado / lógica de salida separados, con `parameter`/`localparam` para los estados y un estado de recuperación ante entrada inválida), un módulo de comunicación serie **UART**.
- Integrarlo a la arquitectura de la ALU de [TP1](../TP1/README.md) (ALU + Interface Circuit + UART), reemplazando la carga por switches/pulsadores por una carga serie manejada desde una **GUI en Python**.

## Arquitectura general

```mermaid
flowchart LR
    GUI(["GUI Python"])

    subgraph FPGA["FPGA"]
        direction LR
        BRG["baud_rate_generator"]
        RX["uart_rx"]
        TX["uart_tx"]
        IFCRX["Interface Circuit RX\n(flag FF + buffer)"]
        IFCTX["Interface Circuit TX\n(flag FF)"]
        LOADER["Loader / Register Router\n(addr + value)"]
        SENDER["result_sender\n(2 bytes: resultado + status)"]
        REGBANK["reg_bank x3\n(A, B, Op) — de TP1, sin cambios"]
        ALU["ALU — de TP1, sin cambios"]
    end

    GUI -- "rx (serie)" --> RX
    BRG -- s_tick --> RX
    BRG -- s_tick --> TX
    RX -- "o_data, o_done_tick" --> IFCRX
    IFCRX -- "r_data, rx_empty" --> LOADER
    LOADER -- "o_enb_reg_A/B/OP + i_data" --> REGBANK
    LOADER -. "o_enb_reg_* → sticky unificado (wiring final) → o_enable_alu" .-> ALU
    REGBANK --> ALU
    ALU -- "o_result, o_overflow, o_carry" --> SENDER
    SENDER -- "w_data, wr" --> IFCTX
    IFCTX -- "d_in, tx_start" --> TX
    TX -- "tx (serie)" --> GUI

    classDef done fill:#2d6a4f,color:#fff,stroke:#1b4332;
    classDef pending fill:#7f5539,color:#fff,stroke:#5c3a1e,stroke-dasharray: 5 5;
    class BRG,RX,TX,IFCRX,IFCTX,LOADER,SENDER,REGBANK,ALU done;
```

🟢 Verde = ya implementado y testeado · 🟤 Marrón punteado = decidido en diseño, todavía no escrito en código (ver [Pendiente](#pendiente--próximos-pasos)).

Esto reemplaza al datapath de entrada de TP1, donde A/B/Op se cargaban con switches + un pulsador dedicado por campo (`btnL`/`btnC`/`btnR`). La versión final de `load_ctrl.v` (ver [TP1](../TP1/README.md)) ya permite cargar los tres campos **en cualquier orden**, con flags "sticky" que habilitan la ALU de forma permanente una vez que los tres se cargaron alguna vez, y que se pueden recargar individualmente sin perder la habilitación — no hay más botón de "clean" (`btnU`), se sacó al simplificar `load_ctrl.v`.

Esto es una simplificación importante para el diseño de la interfaz UART: como TP1 ya resuelve la carga libre (sin importar el orden) a nivel de ALU, el Loader de este TP2 **no necesita reinventar eso**, solo necesita reproducir el mismo patrón (flags sticky + habilitación combinacional) pero alimentado por los pulsos que arman `addr`+`valor` en vez de por botones físicos — sin comando de "ejecutar" explícito, igual que en TP1 (ver [Protocolo de direccionamiento](#protocolo-de-direccionamiento-comando-dirección--valor-2-bytes)).

## Estado actual de la implementación

| Módulo | Estado | Testbench |
|---|---|---|
| `baud_rate_generator.v` | ✅ Implementado | ✅ `tb_baud_rate_generator.v` — pasa |
| `uart_rx.v` | ✅ Implementado | ✅ `tb_uart_rx.v` — pasa |
| `uart_tx.v` | ✅ Implementado | ✅ `tb_uart_tx.v` — pasa (ver nota en [Verificación](#verificación)) |
| `interface_rx.v` (flag FF + buffer) | ✅ Implementado | ✅ `tb_interface_rx.v` — pasa |
| `interface_tx.v` (flag FF simple) | ✅ Implementado | ✅ `tb_interface_tx.v` — pasa |
| `loader_uart.v` (protocolo addr+valor) | ✅ Implementado | ✅ `tb_loader_uart.v` — pasa |
| `result_sender.v` (envío automático, byte de status) | ✅ Implementado | ✅ `tb_result_sender.v` — pasa |
| `top.v` (integración con TP1, 1ª versión solo UART) | 🔧 En curso | — |
| GUI en Python (`TP2/gui/`) | ✅ Implementada | ✅ `test_mock_alu.py` + `test_protocol.py` — pasan |

## Módulos implementados

### `baud_rate_generator.v`

Contador módulo `N` que genera `s_tick` 16 veces por bit (sobremuestreo `OVERSAMPLE=16`). Con los valores por defecto (`CLK_FREQ=100e6`, `BAUD_RATE=19200`):

```
N = CLK_FREQ / (BAUD_RATE × OVERSAMPLE) = 100.000.000 / (19.200 × 16) = 325 (truncado)
```

Verificado por `tb_baud_rate_generator.v`: confirma que los 16 ticks de un período de bit caen cada 325 ciclos de clock exactos (16/16 intervalos correctos).

### `uart_rx.v`

FSM de 4 estados (`IDLE → START → DATA → STOP`), fiel al diagrama ASM de la consigna. Estructurada en **3 procesos separados**, como pide la sección 2 de la consigna:

1. `always @(posedge clk)` — registro de estado y de los contadores (`state_reg`, `tick_count`, `bit_count`, `o_data`).
2. `always @(*)` — lógica de cambio de estado: calcula `state_next`, `tick_count_next` y `bit_count_next` (los "próximo valor" de todo lo que es registro interno de la FSM).
3. `always @(*)` — lógica de salida: solo toca las salidas reales del módulo, `o_done_tick` y `data` (que alimenta `o_data`).

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> START: rx == 0
    START --> DATA: tick==MIDDLE_BIT and rx==0 (confirma start)
    START --> IDLE: tick==MIDDLE_BIT and rx==1 (falso start / ruido)
    DATA --> DATA: tick==DATA_FULL_BIT and bit_count < D_BIT-1
    DATA --> STOP: tick==DATA_FULL_BIT and bit_count == D_BIT-1
    STOP --> IDLE: tick==STOP_FULL_BIT (o_done_tick = 1)
    IDLE --> IDLE: default (fault recovery)
```

`D_BIT=8`, `SB_TICK=16` (1 stop bit), **sin bit de paridad** (la consigna lo marca opcional; no se requiere para el protocolo de la sección "Decisiones de diseño de la interfaz" de este documento, que ya valida los bytes por su dirección/campo, no por paridad).

### `uart_tx.v`

FSM análoga a la de `uart_rx.v`, en sentido inverso: arma la trama de salida a partir de `d_in`, disparada por `tx_start`.

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> START: tx_start (carga d_in al shift register)
    START --> DATA: tick==DATA_FULL_BIT
    DATA --> DATA: tick==DATA_FULL_BIT and bit_count < D_BIT-1 (shift LSB-first)
    DATA --> STOP: tick==DATA_FULL_BIT and bit_count == D_BIT-1
    STOP --> IDLE: tick==STOP_FULL_BIT (tx_done = 1)
    IDLE --> IDLE: default (fault recovery)
```

`tx` es una salida registrada (`tx_reg`) para evitar glitches en el pin físico — esto introduce 1 ciclo de clock de latencia entre el cambio de estado interno y el reflejo en `tx`, que es la causa de las fallas del testbench (ver [Verificación](#verificación)).

### `loader_uart.v`

FSM de 2 estados (`WAIT_CMD` / `WAIT_VALUE`) que implementa el [protocolo de direccionamiento](#protocolo-de-direccionamiento-comando-dirección--valor-2-bytes) (`0x01`=Op, `0x02`=A, `0x03`=B). Misma estructura de 3 procesos que `uart_rx.v`/`uart_tx.v`:

1. `always @(posedge clk)` — registro de estado y de la dirección recibida (`state_reg`, `addr_reg`).
2. `always @(*)` — lógica de próximo estado: `state_next` y `addr_next`.
3. `always @(*)` — lógica de salida: `o_rd` y `o_enb_reg_A/B/OP`.

Las salidas son de tipo Mealy: `o_rd` y el `o_enb_reg_*` pulsan en el mismo ciclo en que `i_rx_empty=0`, así que el pulso de carga coincide con `i_r_data` = valor y `reg_bank` lo captura directo del bus de `interface_rx.v`. Con una dirección inválida el byte de valor se consume igual (`o_rd`) pero no se pulsa ningún enable, y la FSM vuelve a `WAIT_CMD` — se descarta la trama completa y no se desfasa la siguiente.

### `result_sender.v`

FSM de 3 estados (`IDLE` / `SEND_RESULT` / `SEND_STATUS`) que mira `{i_result, i_overflow, i_carry}` de la ALU y manda 2 bytes por `interface_tx.v` cada vez que cambia algo, con `i_enable_alu` como gate (no manda nada hasta que A/B/Op se cargaron alguna vez). Misma estructura de 3 procesos que el resto de las FSMs del diseño.

Dos detalles de la implementación real que no estaban en el diseño original:

- **Primer envío garantizado**: la condición para salir de `IDLE` es `i_enable_alu && (!sent_once || changed)`, no solo `changed`. Sin el `!sent_once`, si la ALU habilita con resultado `0x00` (que coincide con el valor inicial de la "foto" tras el reset), el módulo nunca mandaría nada — `sent_once` fuerza el primer envío sin importar el valor.
- **"Foto" (snapshot)**: al salir de `IDLE` se copian `i_result`/status a `snap_result`/`snap_status`, y los 2 bytes se mandan desde esa copia, no desde las entradas en vivo. Esto evita que los 2 bytes queden desincronizados si la ALU cambia a mitad de la transmisión (ej. el usuario recarga B justo cuando se está mandando el byte de status del cálculo anterior) — los 2 bytes de un mismo envío siempre corresponden al mismo cálculo, y si hubo más cambios mientras se transmitía, se descartan los intermedios y se manda solo el último valor al volver a `IDLE`.

El handshake con `interface_tx.v` nunca escribe con el buzón ocupado: `o_wr` se pulsa únicamente cuando `i_tx_full=0`, en el mismo ciclo en que se avanza de estado — igual que describe la sección de [Camino ALU → Tx](#camino-alu--tx-flag-ff-simple-sin-buffer) más abajo.

## Decisiones de diseño de la interfaz

Discutidas antes de escribir código, para no tener que rehacer el Interface Circuit una vez implementado.

### Camino Rx → ALU: `flag FF + buffer de una palabra`

De los 3 esquemas del libro de referencia (`docs/FPGAPrototypingByVerilogExamples.pdf`, sección 8.2.4): **flag FF sola**, **flag FF + buffer de 1 palabra** y **FIFO**.

Se descartó *flag FF sola* porque expone directamente el registro interno del receptor (riesgo de overrun si llega una trama nueva antes de leer la anterior) y se descartó la *FIFO* por ser más lógica de la que pide la consigna ("protocolo simple de handshake"). El nombrado de señales de la consigna (`r_data`, `rd`, `rx_empty`) además calza 1 a 1 con el esquema de flag+buffer (Listing 8.2 del libro, módulo `flag_buf`), no con una FIFO.

```mermaid
flowchart LR
    RX["uart_rx"] -- "o_data" --> BUF["buffer (1 palabra)"]
    RX -- "o_done_tick" --> SETFLAG["set_flag"]
    SETFLAG --> FLAG["flag FF"]
    FLAG -- "invertido" --> EMPTY["rx_empty"]
    BUF --> RDATA["r_data"]
    LOADER["Loader"] -- "rd" --> CLRFLAG["clr_flag"]
    CLRFLAG --> FLAG
```

### Protocolo de direccionamiento: comando (dirección) + valor, 2 bytes

Una GUI no tiene "un pulsador por campo": tiene que poder decir explícitamente a qué campo se refiere cada valor, y poder actualizar un solo operando sin reenviar los otros. Por eso el frame UART se extiende a nivel de protocolo (no a nivel de framing físico, que sigue siendo 1 byte = 1 start + 8 datos + 1 stop) con una capa de 2 bytes: **dirección** + **valor**.

| `addr` (byte 1) | Destino | Byte de valor (byte 2) |
|---|---|---|
| `0x01` | `opcode` | se carga en el registro de opcode (6 bits menos significativos del byte) |
| `0x02` | operando A | se carga en `reg_bank` de A |
| `0x03` | operando B | se carga en `reg_bank` de B |
| cualquier otro | inválido | se descarta, vuelve a `WAIT_CMD` (fault recovery) |

No hace falta un comando `EXEC` — la versión final de `load_ctrl.v` en TP1 ya no dispara la ALU al completar una secuencia fija, sino que la habilita de forma **sticky**: apenas A, B y Op fueron cargados alguna vez (en cualquier orden), la ALU queda habilitada para siempre (hasta el próximo reset), y al ser puramente combinacional, `o_result` se recalcula solo con recargar cualquier campo. El Loader de este TP2 reproduce exactamente ese mismo patrón (ver más abajo), así que "cargar el tercer campo pendiente" ya alcanza para que el resultado esté disponible — no hay un paso de "ejecutar" separado de "cargar".

```mermaid
sequenceDiagram
    participant GUI as GUI (Python)
    participant IFC as Interface Circuit (RX)
    participant LD as Loader FSM
    participant RB as reg_bank / ALU

    GUI->>IFC: byte 1 = addr (0x01..0x03)
    IFC-->>LD: r_data, rx_empty=0
    LD->>IFC: rd (consume addr)
    Note over LD: addr_reg <= r_data<br/>state <= WAIT_VALUE
    GUI->>IFC: byte 2 = valor
    IFC-->>LD: r_data, rx_empty=0
    LD->>IFC: rd (consume valor)
    LD->>RB: o_enb_reg_A/B/OP (pulso 1 ciclo, según addr_reg), i_data = r_data
    Note over LD: state <= WAIT_CMD
```

La FSM del Loader necesita solo 2 estados (no un contador genérico), consistente con exigir FSM explícita en todo el diseño (sección 2 de la consigna) y con tener un estado de recuperación ante una dirección inválida:

```mermaid
stateDiagram-v2
    [*] --> WAIT_CMD
    WAIT_CMD --> WAIT_VALUE: !rx_empty (addr_reg <= r_data)
    WAIT_VALUE --> WAIT_CMD: !rx_empty, addr válido (pulsa o_enb_reg_A/B/OP)
    WAIT_VALUE --> WAIT_CMD: !rx_empty, addr inválido (descarta, fault recovery)
```

El `reg_bank.v` de TP1 se reutiliza tal cual — su interfaz (`i_data`, `i_load_reg` de 1 ciclo, `o_data`) ya es exactamente lo que el Loader necesita manejar para A/B/Op.

### Enable de la ALU: se replica el patrón sticky de `load_ctrl.v`, no se instancia tal cual

`load_ctrl.v` de TP1 no es reutilizable tal cual acá: internamente instancia un `debounce` por entrada, pensado para filtrar rebotes mecánicos de un botón físico durante varios ciclos. Los pulsos que arma el Loader al decodificar `addr`+`valor` ya llegan limpios y de 1 ciclo (no hay rebote que filtrar), así que pasarlos por un `debounce` solo agregaría una demora de `N_DEBOUNCE` ciclos innecesaria.

Lo que sí se replica es el **patrón combinacional de flags sticky** de `load_ctrl.v` — 3 flags (`loaded_a`, `loaded_b`, `loaded_op`) que se levantan la primera vez que se pulsa el `o_enb_reg_*` correspondiente y solo bajan con `reset`, con `o_enable_alu = loaded_a & loaded_b & loaded_op`. Ese sticky **no vive dentro de `loader_uart.v`**: el Loader expone solo los pulsos `o_enb_reg_A/B/OP` en crudo, y los flags se calculan en el wiring final, unificados con los de `load_ctrl.v` (ver [Módulos nuevos a agregar](#módulos-nuevos-a-agregar)). Así una carga mixta (parte por switches, parte por UART) también habilita la ALU.

### Camino ALU → Tx: `flag FF simple` (sin buffer)

Mismo menú de esquemas, aplicado al revés: acá es la ALU la que setea el flag (`wr` + `w_data`) y `uart_tx` el que lo limpia. Se evaluaron dos variantes:

- **Flag simple, limpia con `tx_done`**: `tx_full` quedaría en 1 desde que la ALU escribe hasta que termina de transmitirse la trama completa. No requiere tocar `uart_tx.v`.
- **Flag + buffer real** (mismo colchón de 1 palabra que del lado Rx): permitiría a la ALU cargar el siguiente resultado mientras el anterior todavía se transmite, pero exige agregarle a `uart_tx.v` una salida de "estoy libre" que hoy no tiene (solo expone `tx_done`, al final de la trama).

**Se eligió flag simple**: la GUI en Python manda comandos a ritmo humano, no a velocidad de línea, así que el pipelining no aporta nada acá y esta opción no requiere modificar `uart_tx.v`.

```mermaid
flowchart LR
    ALU["ALU"] -- "w_data, wr" --> SETFLAG["set_flag"]
    SETFLAG --> FLAG["flag FF"]
    FLAG --> TXFULL["tx_full"]
    FLAG -- "d_in, tx_start" --> TX["uart_tx"]
    TX -- "tx_done" --> CLRFLAG["clr_flag"]
    CLRFLAG --> FLAG
```

## Módulos nuevos a agregar

**Decidido y ya implementado**: 4 módulos nuevos, sin fusionar, **sin capa `uart.v`** — `interface_rx.v`/`interface_tx.v` se conectan directo a `uart_rx.v`/`uart_tx.v`, sin ningún wrapper intermedio. Cada uno tuvo su propia sub-issue (ver detalle y puertos reales en [Módulos implementados](#módulos-implementados)). Lo único que queda es el wiring final (instanciar los 4 + `load_ctrl.v`/`reg_bank.v`/`ALU.v` de TP1, mux switches/UART, constraints `.xdc`), todavía sin issue propia.

**Fuera de este alcance:** la GUI en Python no es RTL — no agrega módulos ni complejidad a la arquitectura digital, solo es el software que arma los bytes `addr`+`valor` del lado de la PC.

```mermaid
flowchart TB
    BRG[baud_rate_generator] -.s_tick.-> RXM[uart_rx]
    BRG -.s_tick.-> TXM[uart_tx]

    RXM --> IFCRX["interface_rx.v (nuevo)\nflag + buffer"]
    IFCTX["interface_tx.v (nuevo)\nflag simple"] --> TXM

    IFCRX -- "r_data, rx_empty" --> LOADER["loader_uart.v (nuevo)"]
    LOADER -- rd --> IFCRX
    SENDER["result_sender.v (nuevo)"] -- "w_data, wr" --> IFCTX
    IFCTX -- tx_full --> SENDER

    LOADER -- "o_enb_reg_A/B/OP" --> MUX{{"mux switches/UART + sticky unificado\n(wiring final, NO es módulo nuevo)"}}
    LC["load_ctrl.v (TP1, sin cambios)"] -- "enb_reg_A/B/OP" --> MUX
    MUX -- "i_enable_alu" --> SENDER
    MUX --> RB["reg_bank x3 (TP1, sin cambios)"]
    RB --> ALU["ALU.v (TP1, sin cambios)"]
    ALU -- "o_result, o_overflow, o_carry" --> SENDER
```

El mux preserva la interfaz física de TP1: `load_ctrl.v` (switches/botones) y `loader_uart.v` (UART) quedan como dos fuentes hermanas compitiendo por los mismos `reg_bank`, ninguna reemplaza a la otra — se puede seguir usando la FPGA a mano exactamente como en TP1. Ojo con el enable: tiene que ser un solo sticky unificado en el wiring final (seteado por *cualquiera* de las dos fuentes por campo), no un OR de dos sticky ya calculados por separado — si no, una carga mixta (ej. A por switch, B y Op por UART) nunca habilita la ALU.

### 1. `interface_rx.v`

Genérico, no conoce A/B/Op — esquema *flag FF + buffer* (sección [Camino Rx → ALU](#camino-rx--alu-flag-ff--buffer-de-una-palabra) más arriba). Se conecta directo a `uart_rx.v`.

| Puerto | Dirección | Descripción |
|---|---|---|
| `clk`, `reset` | in | — |
| `i_rx_data[7:0]` | in | `o_data` de `uart_rx.v` |
| `i_rx_done_tick` | in | `o_done_tick` de `uart_rx.v` (`set_flag`) |
| `i_rd` | in | pulso de 1 ciclo: "ya leí el dato" (`clr_flag`), lo maneja `loader_uart.v` |
| `o_r_data[7:0]` | out | dato bufferizado |
| `o_rx_empty` | out | `~flag_reg` |

Estructura interna: 1 registro de 8 bits (buffer) + 1 flip-flop (flag). Sin FSM propiamente dicha — es el módulo `flag_buf` del libro, casi sin lógica de próximo estado más allá del set/clear del flag.

### 2. `interface_tx.v`

Simétrico, esquema *flag FF simple*. Se conecta directo a `uart_tx.v`.

| Puerto | Dirección | Descripción |
|---|---|---|
| `clk`, `reset` | in | — |
| `i_w_data[7:0]` | in | dato a transmitir |
| `i_wr` | in | pulso de 1 ciclo: "quiero transmitir esto" (`set_flag`), lo maneja `result_sender.v` |
| `i_tx_done` | in | de `uart_tx.v` (`clr_flag`) |
| `o_tx_full` | out | `flag_reg` |
| `o_d_in[7:0]` | out | hacia `d_in` de `uart_tx.v` |
| `o_tx_start` | out | hacia `tx_start` de `uart_tx.v` (nivel, se mantiene en 1 mientras `flag_reg`; `uart_tx.v` lo captura solo cuando está en `IDLE`) |

Misma complejidad que (1): 1 registro + 1 flip-flop, sin FSM propia.

### 3. `loader_uart.v`

FSM `addr`+`valor` — ✅ implementado (ver [`loader_uart.v`](#loader_uartv) en Módulos implementados), protocolo documentado en detalle en [Protocolo de direccionamiento](#protocolo-de-direccionamiento-comando-dirección--valor-2-bytes) y [Enable de la ALU](#enable-de-la-alu-se-replica-el-patrón-sticky-de-load_ctrlv-no-se-instancia-tal-cual) más arriba.

| Puerto | Dirección | Descripción |
|---|---|---|
| `clk`, `reset` | in | — |
| `i_r_data[7:0]`, `i_rx_empty` | in | de `interface_rx.v` |
| `o_rd` | out | pulso de 1 ciclo hacia `interface_rx.v` |
| `o_enb_reg_A`, `o_enb_reg_B`, `o_enb_reg_OP` | out | pulsos de 1 ciclo (al mux, junto con los de `load_ctrl.v`) |

No expone `o_enable_alu` propio: ese enable sale unificado del mux del wiring final (ver nota de arriba), no de este módulo. `i_data` de los `reg_bank` tampoco pasa por acá: se muxea directo entre `sw` e `i_r_data`, seleccionado por cuál de los dos enables (`load_ctrl` o `loader_uart`) está pulsando.

### 4. `result_sender.v`

✅ implementado (ver [`result_sender.v`](#result_senderv) en Módulos implementados). El envío se dispara automáticamente al cambiar `{o_result, o_overflow, o_carry}` (no hay comando explícito de lectura desde la GUI), y `o_overflow`/`o_carry` van en un byte de status separado del byte de resultado — 2 bytes por envío, nada se pierde:

- byte 1 = `o_result[7:0]`
- byte 2 = status = `{6'b0, o_overflow, o_carry}`

Como hay que mandar 2 bytes en secuencia por un único puerto `w_data`/`wr` (con backpressure de `tx_full`), necesita una FSM chica de 3 estados: `IDLE` (detecta el cambio, solo cuando `i_enable_alu=1`) → `SEND_RESULT` (`wr`+`w_data=result`, espera a que `tx_full` baje) → `SEND_STATUS` (`wr`+`w_data=status`, espera a que `tx_full` baje) → vuelve a `IDLE`. Con `default` de recuperación a `IDLE`, como el resto de las FSMs del diseño.

| Puerto | Dirección | Descripción |
|---|---|---|
| `clk`, `reset` | in | — |
| `i_result[7:0]`, `i_overflow`, `i_carry` | in | de `ALU.v` |
| `i_enable_alu` | in | del mux del wiring final (gatea el envío: no manda nada hasta que A/B/Op se cargaron alguna vez) |
| `i_tx_full` | in | de `interface_tx.v` |
| `o_w_data[7:0]` | out | hacia `interface_tx.v` |
| `o_wr` | out | pulso, hacia `interface_tx.v` |

## Verificación

Corridos con Icarus Verilog (`iverilog` + `vvp`) desde `TP2/`:

```
iverilog -o /tmp/tb.vvp sim/tb_baud_rate_generator.v rtl/baud_rate_generator.v && vvp /tmp/tb.vvp
iverilog -o /tmp/tb.vvp sim/tb_uart_rx.v rtl/uart_rx.v && vvp /tmp/tb.vvp
iverilog -o /tmp/tb.vvp sim/tb_uart_tx.v rtl/uart_tx.v && vvp /tmp/tb.vvp
iverilog -o /tmp/tb.vvp sim/tb_interface_rx.v rtl/interface_rx.v && vvp /tmp/tb.vvp
iverilog -o /tmp/tb.vvp sim/tb_interface_tx.v rtl/interface_tx.v && vvp /tmp/tb.vvp
iverilog -o /tmp/tb.vvp sim/tb_loader_uart.v rtl/loader_uart.v && vvp /tmp/tb.vvp
iverilog -o /tmp/tb.vvp sim/tb_result_sender.v rtl/result_sender.v rtl/interface_tx.v rtl/uart_tx.v rtl/uart_rx.v && vvp /tmp/tb.vvp
```

- **`tb_baud_rate_generator.v`**: ✅ **pasa** — los 16 intervalos entre ticks (sobremuestreo 16x) caen exactamente a los 325 ciclos de clock esperados.
- **`tb_uart_rx.v`**: ✅ **pasa** — 2 tramas válidas (`0xA5`, `0x5A`) con `o_data`/`o_done_tick` correctos, y 1 caso de glitch en el start bit correctamente ignorado (falso start no dispara `o_done_tick`).
- **`tb_uart_tx.v`**: ✅ **pasa**. Una versión anterior de `uart_tx.v`/`tb_uart_tx.v` daba 12 errores por un desfasaje de 1 ciclo de clock entre el cambio de estado interno y el reflejo en la salida registrada `tx` (`tx_reg <= tx_next(state_reg)`, calculada a partir del estado *previo* a la transición — comportamiento típico de una FSM Moore con salida registrada). Ese fix ya estaba resuelto en la rama `dev-tp2` remota (no bajada todavía a la copia local en el momento de la primera verificación) y se incorporó acá vía merge; los 25 casos (2 tramas completas, bit a bit, más `tx_done`) pasan limpio.
- **`tb_interface_rx.v`**: ✅ **pasa** — 13 casos (estado inicial, llegada de dato, persistencia mientras no se lee, lectura vía `i_rd`, segunda trama, reset con dato pendiente, coincidencia `i_rx_done_tick`/`i_rd` en el mismo ciclo, y overrun explícito verificando que el buffer se queda con el dato más reciente). La primera versión de `interface_rx.v` no compilaba (orden de `wire` en un puerto, y un `output reg` maneja con `assign`) y le faltaba el puerto `i_rd`/`clr_flag` por completo — corregido antes de escribir este testbench.
- **`tb_interface_tx.v`**: ✅ **pasa** — 7 casos (estado inicial, carga de dato, inmunidad de `tx_full` mientras transmite, `tx_done` limpia el flag, segundo envío, reset a mitad de transmisión, coincidencia `i_wr`/`i_tx_done`).
- **`tb_loader_uart.v`**: ✅ **pasa** — 13 chequeos en 9 casos, con un mock de `interface_rx` (buffer + flag): estado post-reset, carga de A/B/Op en distintos órdenes, direcciones inválidas (`0x07`, `0x00`, `0x04`) descartadas sin trabar la FSM, espera larga entre dirección y valor, reset en `WAIT_VALUE` y bytes back-to-back. Un monitor verifica en todos los ciclos que nunca hay más de un `o_enb_reg_*` activo, que ninguno dura más de 1 ciclo y que `o_rd`/enables solo se activan con dato disponible. La primera versión de `loader_uart.v` no compilaba (coma de más, salidas `wire` asignadas en `always` y con doble driver), tenía el mapeo de direcciones corrido (`0x00`-`0x02`) y pulsaba los enables durante todo `WAIT_VALUE` en vez de 1 ciclo — corregido antes de escribir este testbench.
- **`tb_result_sender.v`**: ✅ **pasa** — 11 casos, pero a diferencia de los anteriores este testbench prueba la **cadena completa de salida real** (`result_sender` → `interface_tx` → `uart_tx` → `uart_rx`, con `uart_rx` haciendo de "PC" que decodifica lo que sale por el cable), no un mock. Cubre: `i_enable_alu=0` no manda nada, primer envío con resultado `0x00` (el caso que `!sent_once` resuelve), cambio de resultado, valor repetido (no reenvía), overflow/carry empaquetados en el byte de status, cambio de la ALU a mitad de un envío (la "foto" mantiene los 2 bytes consistentes), varios cambios intermedios durante la transmisión (se descartan, se manda solo el último), y reset a mitad de un envío. Un monitor verifica en todos los ciclos que `o_wr` nunca se pulsa con `i_tx_full=1`.

## Pendiente / Próximos pasos

1. ~~Implementar `interface_rx.v`~~ — hecho, `tb_interface_rx.v` pasa (13/13).
2. ~~Implementar `interface_tx.v`~~ — hecho, `tb_interface_tx.v` pasa (7/7).
3. ~~Implementar `loader_uart.v`~~ — hecho, `tb_loader_uart.v` pasa (13/13).
4. ~~Implementar `result_sender.v`~~ — hecho, `tb_result_sender.v` pasa (11/11), probado en cadena completa hasta `uart_rx`.
5. 🔧 En curso: wiring final, en una **primera versión simplificada sin `load_ctrl.v`** — solo carga por UART (`interface_rx.v`/`interface_tx.v`/`loader_uart.v`/`result_sender.v` + `ALU.v`/`reg_bank.v` de TP1), sin mux ni sticky unificado todavía. El mux switches/UART + `load_ctrl.v` + constraints `.xdc` para los pines Rx/Tx físicos quedan para una segunda etapa, una vez que esto funcione end-to-end.
6. ✅ GUI en Python (`TP2/gui/`) — Tkinter, con un backend mock (`mock_fpga.py`) que simula la ALU para poder probar el protocolo sin esperar al wiring final. Ver [`TP2/gui/README.md`](gui/README.md).
