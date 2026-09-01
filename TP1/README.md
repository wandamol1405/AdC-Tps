# TP1 — ALU

Implementación en FPGA (Basys3) de una ALU parametrizable, con un datapath de carga por switches/pulsadores y verificación por testbench autochequeado.

## Objetivo

Según el enunciado (`Trabajo_Practico_N_1_-_ALU (2).pdf`):

- Implementar en FPGA una ALU.
- Que la ALU sea parametrizable en ancho de bus de datos, para poder reutilizarse en el trabajo final.
- Validar el desarrollo con testbench, incluyendo generación de entradas aleatorias/dirigidas y chequeo automático.
- Simular el diseño en Vivado, incluyendo análisis de tiempo.

## Arquitectura general

Los datos A, B y el código de operación se ingresan por los switches de la Basys3 y se cargan a sus respectivos registros presionando un pulsador por campo (`btnL`→A, `btnC`→B, `btnR`→Op). Una máquina de estados exige que la carga se haga en ese orden y recién habilita la salida de la ALU cuando los tres campos ya fueron cargados. El resultado (más las banderas de overflow y carry) se muestra en los LEDs.

![Esquemático RTL de top](images/Captura%20desde%202026-09-01%2009-55-54.png)

### Módulos

- **`debounce.v`**: FSM antirrebote de 4 estados con detector de flanco integrado. Filtra los rebotes mecánicos de un pulsador y entrega un pulso de 1 ciclo (`db_tick`) por cada pulsación real, esperando `N` ciclos de clock de estabilidad antes de confirmarla (parametrizable, para poder usar un `N` chico en simulación y uno realista — ~21 ms con clock de 100 MHz — en la síntesis).
- **`load_ctrl.v`**: instancia un `debounce` por cada uno de los 4 pulsadores (A, B, Op y el de "limpieza") y una FSM de 4 estados (`WAIT_A → WAIT_B → WAIT_OP → ENABLE`) que habilita, de a uno, el `reg_bank` correspondiente y finalmente la salida de la ALU. El pulsador de limpieza (`btnU`) vuelve la FSM a `WAIT_A` sin borrar lo ya cargado en los registros, para poder reutilizar A/B en una operación nueva sin resetear todo el sistema.

  ![Esquemático RTL de load_ctrl](images/Captura%20desde%202026-09-01%2009-56-45.png)

- **`reg_bank.v`**: registro genérico parametrizable por ancho (`WIDTH`), con reset y enable de carga síncronos. Se instancia tres veces (A, B y Op) en vez de escribir tres registros separados a mano.
- **`ALU.v`**: puramente combinacional. Implementa las 8 operaciones del enunciado (ADD, SUB, AND, OR, XOR, SRA, SRL, NOR) y calcula overflow con signo y carry sin signo para ADD (con saturación al valor límite representable en caso de overflow). Si `i_enable` está en 0, fuerza la salida a 0.

  ![Esquemático RTL de la ALU](images/Captura%20desde%202026-09-01%2009-57-36.png)

- **`top.v`**: conecta todo lo anterior con los pines físicos de la Basys3 y arma el vector de LEDs: `led[7:0]` = resultado, `led[8]` apagado (separador), `led[9]` = overflow, `led[10]` = carry.

## Mapeo de pines (Basys3)

Definido en `constraints/constraints.xdc`:

| Señal | Función | Pines Basys3 |
|---|---|---|
| `clk` | Clock de 100 MHz | W5 |
| `reset` | Reset síncrono | SW15 |
| `sw[7:0]` | Dato (A/B) u opcode (SW5-SW0) | SW7-SW0 |
| `btnL` | Cargar A | Botón izquierdo |
| `btnC` | Cargar B | Botón central |
| `btnR` | Cargar Op | Botón derecho |
| `btnU` | Limpiar (sin borrar registros) | Botón superior |
| `led[10:0]` | Resultado + separador + overflow + carry | LD10-LD0 |

## Verificación

### `tb_ALU.v` — ALU combinacional aislada

Testbench autochequeado: aplica un estímulo por operación (incluyendo casos borde de overflow/carry en ADD, `i_enable=0` y un opcode inválido) y compara automáticamente la salida esperada contra la obtenida.

Formas de onda de la simulación (`i_a`, `i_b`, `o_result` en decimal con signo — o en binario para las operaciones bit a bit y de shift, donde importa ver cada bit —, `i_op` en hexadecimal, `i_enable`/`o_overflow`/`o_carry` en binario):

**ADD** — caso básico, carry sin overflow (`-1+1`) y overflow con saturación positiva (`127+1`, `127+127`) y negativa (`-128+-128`):

![Waveform ALU - ADD](images/Captura%20desde%202026-09-01%2010-22-25.png)

**SUB** — casos básicos con resultado positivo, negativo y cero:

![Waveform ALU - SUB](images/Captura%20desde%202026-09-01%2010-23-10.png)

**AND y OR**:

![Waveform ALU - AND y OR](images/Captura%20desde%202026-09-01%2010-24-50.png)

**XOR**:

![Waveform ALU - XOR](images/Captura%20desde%202026-09-01%2010-25-15.png)

**SRA y SRL** — mismo patrón de bits desplazado con y sin extensión de signo:

![Waveform ALU - SRA y SRL](images/Captura%20desde%202026-09-01%2010-25-34.png)

**Cola de SRL y NOR**:

![Waveform ALU - SRL (cola) y NOR](images/Captura%20desde%202026-09-01%2010-26-02.png)

**`i_enable=0`** (fuerza `o_result=0` incluso con condición de overflow) **y opcode inválido** (cae en el `default` del `case`):

![Waveform ALU - i_enable=0 y opcode inválido](images/Captura%20desde%202026-09-01%2010-26-28.png)

Resultado en consola: **25/25 casos pasaron**.

![Log de simulación tb_ALU](images/Captura%20desde%202026-09-01%2009-54-10.png)

### `tb_top.v` — sistema completo (datapath + control)

Simula la secuencia real de carga por switches y pulsadores (con antirrebote modelado, incluyendo rebotes simulados y pulsos por debajo del umbral de confirmación), la máquina de estados de `load_ctrl`, el latcheo de A/B/Op una vez en `ENABLE`, el reset a mitad de secuencia y el botón de limpieza (`btnU`). `N_DEBOUNCE` se reduce solo para esta instancia de simulación, para no tener que esperar los ~21 ms reales del antirrebote de hardware.

```
========================================================
 Testbench de sistema completo (top) - N_DEBOUNCE(sim)=4
========================================================
    [DEBOUNCE] tick_a  #1 confirmado en t=195000
    [DEBOUNCE] tick_b  #1 confirmado en t=695000
    [DEBOUNCE] tick_op #1 confirmado en t=1195000
[OK]                 ADD a=10 b=20 op=100000 -> result=30(0x1e) ov=0 ca=0
    [DEBOUNCE] tick_a  #2 confirmado en t=1745000
    [DEBOUNCE] tick_b  #2 confirmado en t=2245000
    [DEBOUNCE] tick_op #2 confirmado en t=2745000
[OK]             ADD-OVP a=127 b=1 op=100000 -> result=127(0x7f) ov=1 ca=0
    [DEBOUNCE] tick_a  #3 confirmado en t=3295000
    [DEBOUNCE] tick_b  #3 confirmado en t=3795000
    [DEBOUNCE] tick_op #3 confirmado en t=4295000
[OK]             ADD-OVN a=-128 b=-128 op=100000 -> result=128(0x80) ov=1 ca=1
    [DEBOUNCE] tick_a  #4 confirmado en t=4845000
    [DEBOUNCE] tick_b  #4 confirmado en t=5345000
    [DEBOUNCE] tick_op #4 confirmado en t=5845000
[OK]              ADD-CA a=-1 b=1 op=100000 -> result=0(0x0) ov=0 ca=1
    [DEBOUNCE] tick_a  #5 confirmado en t=6395000
    [DEBOUNCE] tick_b  #5 confirmado en t=6895000
    [DEBOUNCE] tick_op #5 confirmado en t=7395000
[OK]                 SUB a=10 b=20 op=100010 -> result=246(0xf6) ov=0 ca=0
    [DEBOUNCE] tick_a  #6 confirmado en t=7945000
    [DEBOUNCE] tick_b  #6 confirmado en t=8445000
    [DEBOUNCE] tick_op #6 confirmado en t=8945000
[OK]                 SRA a=-128 b=2 op=000011 -> result=224(0xe0) ov=0 ca=0
    [DEBOUNCE] tick_a  #7 confirmado en t=9495000
    [DEBOUNCE] tick_b  #7 confirmado en t=9995000
    [DEBOUNCE] tick_op #7 confirmado en t=10495000
[OK]                 SRL a=-128 b=2 op=000010 -> result=32(0x20) ov=0 ca=0
    [DEBOUNCE] tick_a  #8 confirmado en t=11045000
    [DEBOUNCE] tick_b  #8 confirmado en t=11545000
    [DEBOUNCE] tick_op #8 confirmado en t=12045000
[OK]                 NOR a=0 b=0 op=100111 -> result=255(0xff) ov=0 ca=0
--------------------------------------------------------
 Verificando que A/B/OP queden latcheados una vez en ENABLE
[OK]    LATCH    mover sw a 0x55 no afecta el resultado ya cargado (result=0xff)
--------------------------------------------------------
 Probando filtrado de rebotes en btnL
    [DEBOUNCE] tick_a  #1 confirmado en t=13005000
[OK]    BOUNCE   4 rebotes filtrados, 1 solo tick_a, A=42, estado=  WAIT_B
 Probando que un pulso mas corto que el antirrebote NO dispare el tick
[OK]    BOUNCE   pulso corto (5 ciclos) correctamente ignorado, sin tick_a
--------------------------------------------------------
 Probando reset a mitad de la secuencia de carga (antes de completar B y OP)
    [DEBOUNCE] tick_a  #1 confirmado en t=13905000
[OK]    MIDSEQ   tras cargar A, estado=  WAIT_B
[OK]    MIDSEQ   reset a mitad de secuencia vuelve a WAIT_A y led=0
--------------------------------------------------------
 Probando el boton de limpieza (clean): no debe borrar A/B/OP ya cargados
    [DEBOUNCE] tick_a  #2 confirmado en t=14485000
    [DEBOUNCE] tick_b  #9 confirmado en t=14985000
    [DEBOUNCE] tick_op #9 confirmado en t=15485000
[OK]    CLEAN-PRE  15+5=20 cargado y habilitado antes de limpiar
[OK]    CLEAN    vuelve a WAIT_A, led=0, pero A=15 B=5 OP=100000 siguen intactos
    [DEBOUNCE] tick_a  #3 confirmado en t=16495000
    [DEBOUNCE] tick_b  #10 confirmado en t=16995000
    [DEBOUNCE] tick_op #10 confirmado en t=17495000
[OK]    CLEAN-POST tras clean, nueva operacion SUB reutilizando A/B: 15-5=10
========================================================
 RESULTADO: TODOS LOS CASOS PASARON (16/16)
========================================================
$finish called at time : 17845 ns : File "/home/wanda/Documentos/Facultad/AdC/AdC-Tps/TP1/sim/tb_top.v" Line 335
```

## Resultados

- **`tb_ALU.v`**: 25/25 casos pasaron (las 8 operaciones, casos borde de overflow/carry en ADD con y sin saturación, `i_enable=0` y opcode inválido).
- **`tb_top.v`**: 16/16 casos pasaron (datapath completo, latcheo de registros, antirrebote real con rebotes simulados, reset a mitad de secuencia y botón de limpieza).
- Síntesis, implementación y generación de bitstream completadas sin errores en Vivado; validado en hardware sobre la Basys3.

## Cómo simular / sintetizar

1. Agregar como fuentes de diseño todos los archivos de `rtl/`.
2. Agregar `sim/tb_ALU.v` y/o `sim/tb_top.v` como fuente de simulación (según qué testbench se quiera correr) y ejecutar la simulación de comportamiento en Vivado.
3. Para hardware: agregar `constraints/constraints.xdc`, correr síntesis + implementación, generar bitstream y programar la Basys3.
