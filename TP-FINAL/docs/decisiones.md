# Decisiones del TP Final

Registro de las decisiones de diseño y de trabajo acordadas entre las dos.
Cada decisión dice **qué** se decidió y **por qué**; si después se cambia, se
edita acá en el mismo PR que hace el cambio.

---

## 1. Convenciones de código y flujo de trabajo

Basadas en lo que ya usamos en TP1 y TP2, para que los módulos que escribimos
en paralelo se conecten sin sorpresas. Los ejemplos de referencia son
`TP2/rtl/result_sender.v` (FSM y cabecera) y `TP2/rtl/top.v` (instancias).

### 1.1 Nombres

| Qué                         | Convención                                            | Ejemplo (TP1/TP2)                                |
| --------------------------- | ----------------------------------------------------- | ------------------------------------------------ |
| Clock y reset               | `clk`, `reset`, **sin prefijo**                       | todos los módulos                                |
| Entradas                    | `i_` + snake_case                                     | `i_result`, `i_tx_full`                          |
| Salidas                     | `o_` + snake_case                                     | `o_w_data`, `o_wr`                               |
| Pulsos de 1 ciclo           | sufijo `_tick`                                        | `o_done_tick`, `s_tick`                          |
| Registros de FSM / datapath | `nombre_reg` (actual) y `nombre_next` (próximo)       | `state_reg`/`state_next`, `data_reg`/`data_next` |
| Cables internos             | snake_case, sin prefijo                               | `rx_data`, `enb_reg_A`                           |
| Parámetros                  | MAYÚSCULAS; anchos con `NB_`                          | `NB_DATA`, `NB_OP`, `CLK_FREQ`                   |
| Estados y constantes        | `localparam` en MAYÚSCULAS                            | `IDLE`, `SEND_RESULT`, `ADD`                     |
| Instancias                  | `u_` + nombre del módulo                              | `u_uart_rx`, `u_result_sender`                   |
| Archivos                    | un módulo por archivo, mismo nombre                   | `uart_rx.v` → `module uart_rx`                   |
| Testbenches                 | `tb_<modulo>.v`, el módulo bajo prueba se llama `dut` | `tb_uart_rx.v`                                   |

Excepciones y aclaraciones:

- **Puertos del `top`**: usan los nombres de la Basys 3 tal como en el `.xdc`
  (`sw`, `led`, `btnL`, `rx`, `tx`), sin `i_`/`o_`, para que coincidan con
  `constraints/`.
- En TP2 hay casos que no siguen la tabla (`in_rx` en `uart_rx`, `snap_result`
  sin `_reg`, `D_BIT` en vez de `NB_`). **El código nuevo sigue la tabla.** Si
  se reutiliza un módulo viejo, se renombra al adaptarlo; si se usa tal cual,
  se deja como está.
- Las instancias se conectan **siempre por nombre** (`.i_data(rx_data)`),
  nunca por posición.
- En los cables internos del `top`, el comentario dice quién la genera y quién
  la usa (`// uart_rx -> interface_rx`), como en `TP2/rtl/top.v`.

### 1.2 Reset

- **Sincrónico y activo alto**: `always @(posedge clk) if (reset) ...`.
  Nunca `posedge reset` en la lista de sensibilidad.
- Todo registro tiene valor de reset explícito, con el ancho correcto
  (`{NB_DATA{1'b0}}`, no `0` suelto, en los buses parametrizados).
- Un solo `reset` global que viene del botón (como `btnD` en TP2). Si hace
  falta otro, por ejemplo el reset del pipeline que dispara la Debug Unit, se
  le da un nombre propio (`i_pipe_reset`) y se anota en este archivo.

### 1.3 FSM en 3 bloques

Igual que `result_sender.v` y `uart_rx.v`:

1. **Registro de estado** (`always @(posedge clk)`, `<=`): reset o
   `x_reg <= x_next`. No lleva lógica adentro.
2. **Próximo estado** (`always @(*)`, `=`): arranca con
   `x_next = x_reg;` para todos los registros (evita latches) y después un
   `case (state_reg)`.
3. **Salidas** (`always @(*)`, `=`): arranca con valores por defecto y después
   un `case (state_reg)`.

Reglas comunes:

- Los estados son `localparam` con ancho explícito (`localparam [1:0] IDLE = 2'b00, ...`).
- Todo `case` tiene `default`. En el bloque 2 vuelve a `IDLE` (recuperación
  ante estados inválidos).
- `<=` solo en bloques con clock; `=` solo en `always @(*)`. Nunca mezclados.

### 1.4 Comentarios

Cada módulo arranca con una cabecera como la de TP2:

```verilog
// =============================================================================
// MODULO: <Nombre legible> (<archivo>.v)
//
// ¿QUE HACE ESTE MODULO?
// <Qué hace, en 2-5 líneas: qué entra, qué sale, cuándo actúa.>
//
// <Secciones opcionales en MAYÚSCULAS si hacen falta: TIMING, HANDSHAKE,
//  PROTOCOLO, DIAGRAMA ASCII de conexiones, etc.>
// =============================================================================
```

Además:

- Cada puerto y cada parámetro lleva un comentario corto al costado.
- Los bloques se separan con banners (`// ---- ESTADOS ----`,
  `// ==== BLOQUE 1: REGISTRO DE ESTADO ====`).
- Los comentarios se escriben en español y explican **por qué**, no repiten el
  código.

### 1.5 Testbenches

- `` `timescale 1ns / 1ps `` en la primera línea y clock de 100 MHz (`always #5 clk = ~clk;`).
- Son autoverificables: un contador `errors` y mensajes `[OK]` / `[ERROR]`
  por caso. Al final se imprime `RESULTADO: TODOS LOS CASOS PASARON` o la
  cantidad de errores, y después `$finish`.
- Cada módulo nuevo entra al repo con su testbench, salvo los que sean puro
  cableado.

### 1.6 Ramas

Mismo esquema que en TP2 (`main` ← `dev-tp2` ← `dev-tp2X-...`):

```
main                       solo entregas / hitos, siempre funcional
 └── dev-tpf               integración del TP final: siempre sintetiza y pasan los tb
      ├── dev-tpf-27-definir-convenciones-de-código-y-flujo-de-ramas
      ├── dev-tpf-<N>-etapa-if
      └── dev-tpf-<N>-fix-alu-sll
```

- **Una rama por issue**, creada desde `dev-tpf` con el botón "Create a
  branch" de la issue en GitHub o a mano con el nombre `dev-tpf-<N>-<descripcion>`.
  Así el número de issue queda en el nombre de la rama.
- Antes de abrir el PR se actualiza la rama con `dev-tpf` (`git merge dev-tpf`)
  y se verifica que compile y que pasen los testbenches que toca.
- Nunca se hace commit directo en `main` ni en `dev-tpf`.
- `dev-tpf` → `main` se mergea en hitos acordados (pipeline integrado, Debug
  Unit andando, entrega final) con un PR propio, como el #24 de TP2.

### 1.7 Pull requests

- PR de `dev-tpf-<N>-...` hacia `dev-tpf`, **revisado y aprobado por la otra**
  antes del merge. Quien abre el PR no lo aprueba.
- Descripción con el formato que ya usamos en TP2:
  - `## Resumen`: qué se agrega o cambia y por qué.
  - `## Cómo se probó`: testbench, captura de la forma de onda o prueba en placa.
  - `Closes #N` al final.
- **Ojo con `Closes #N`**: GitHub solo cierra la issue sola cuando el PR entra a
  la rama por defecto (`main`). En los PRs hacia `dev-tpf` el `Closes #N` queda
  como referencia, pero **la issue se cierra a mano al mergear**. En el PR
  `dev-tpf` → `main` se listan los `Closes #N` pendientes.
- Commits: título corto en imperativo que diga qué cambia (`Add uart_rx FSM`,
  `Agrega generador de inmediatos`). Un commit por cambio lógico.
