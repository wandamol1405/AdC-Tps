# Trabajo Final — Pipeline del procesador RISC-V
### Arquitectura de Computadoras 2026

**Equipo:** Molina, Maria Wanda · Verdú, Melisa Noel
**Placa:** Basys 3 (Artix-7 XC7A35T)

> Plan de trabajo, diagramas y dependencias entre issues: [`PLAN.md`](PLAN.md).
> Decisiones de diseño: [`docs/decisiones.md`](docs/decisiones.md) · Protocolo UART: [`docs/protocolo.md`](docs/protocolo.md).

---

## Consigna

Transcripción de la presentación de la cátedra (*TRABAJO FINAL 2026*).

### 1. Objetivo

- Implementar el **pipeline del procesador RISC-V**.
- Implementar una **Debug Unit** que permita enviar y recibir información al procesador mediante el protocolo **UART**.
- Una **interfaz** para visualizar los datos e interactuar con la Debug Unit (**CLI, GUI y/o TUI**).

### 2. Marco teórico

#### 2.1 Etapas del pipeline

| Etapa | Nombre | Qué hace |
| --- | --- | --- |
| **IF** | Instruction Fetch | Búsqueda de la instrucción en la memoria de programa. |
| **ID** | Instruction Decode | Decodificación de la instrucción y lectura de registros. |
| **EX** | Execute | Ejecución de la instrucción propiamente dicha. |
| **MEM** | Memory Access | Lectura o escritura desde/hacia la memoria de datos. |
| **WB** | Write Back | Escritura de resultados en los registros. |

#### 2.2 Riesgos

- **Estructurales:** se producen cuando dos instrucciones tratan de utilizar el mismo recurso en el mismo ciclo.
- **De datos:** se intenta utilizar un dato antes de que esté preparado. Hay que mantener el orden estricto de lecturas y escrituras.
- **De control:** se intenta tomar una decisión sobre una condición todavía no evaluada.

#### 2.3 Tipos de instrucciones

| Tipo | Uso |
| --- | --- |
| **R** | Operaciones aritméticas y lógicas entre registros. |
| **I** | Operaciones con inmediato; también los loads. |
| **S** | Stores. |
| **B** | Ramificación condicional: saltan si se da una condición determinada. |
| **U** | Inmediato superior: usan un inmediato de 20 bits para cargar la parte más significativa de un valor o una dirección. |
| **J** | Salto incondicional (`jal`). |

> **Aclaración:** la diapositiva del tipo J dice que "la dirección a la que se salta es la almacenada en `rd`". En RV32I `jal` salta a `PC + imm` y **guarda en `rd` la dirección de retorno** (`PC + 4`).

Formato de los campos (RV32I, la presentación los muestra como imágenes):

```
         31        25 24   20 19   15 14  12 11         7 6      0
R-type  |  funct7    |  rs2  |  rs1  |funct3|     rd     | opcode |
I-type  |     imm[11:0]      |  rs1  |funct3|     rd     | opcode |
S-type  | imm[11:5]  |  rs2  |  rs1  |funct3|  imm[4:0]  | opcode |
B-type  |imm[12|10:5]|  rs2  |  rs1  |funct3|imm[4:1|11]| opcode |
U-type  |            imm[31:12]             |     rd     | opcode |
J-type  |     imm[20|10:1|11|19:12]         |     rd     | opcode |
```

### 3. Requerimientos generales

- El procesador debe poder **programarse y reprogramarse a través de comandos de UART**.
- **El clock no debe verse intervenido en ninguna parte del proyecto.**
- Hay elementos que requieren ingenio y toma de decisiones: **documentar estas decisiones y su porqué**.
- Ser creativos al momento de mostrar los datos e interactuar con ellos (GUI, TUI, CLI).

### 4. Instrucciones a implementar

| Tipo | Instrucciones |
| --- | --- |
| **R** (registro a registro) | `add`, `sub`, `sll`, `srl`, `sra`, `and`, `or`, `xor`, `slt`, `sltu` |
| **I** (carga) | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| **I** (inmediato) | `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `slli`, `srli`, `srai` |
| **I** (salto) | `jalr` |
| **S** (almacenamiento) | `sb`, `sh`, `sw` |
| **B** (ramificación condicional) | `beq`, `bne` |
| **U** (inmediato superior) | `lui` |
| **J** (salto incondicional) | `jal` |

Además, una instrucción **HALT** (o de stop), cuya codificación queda a elección.

### 5. Debug Unit

Se deben enviar a la PC a través de la UART:

- El contenido de los **32 registros**.
- El contenido de los **latches intermedios**.
- El contenido de la **memoria de datos usada**.

### 6. Carga de programa

El **programa** debe:

- Estar escrito en **ensamblador**.
- Contar con un mecanismo para **traducir las instrucciones a lenguaje máquina** para enviarlas al procesador.
- Contar con una instrucción **HALT** o instrucción de stop.

El **sistema** debe:

- Permitir la programación del procesador desde el software, escribiendo la memoria de programa.
- Permitir la **reprogramación del procesador de manera dinámica**.
- Responder a las preguntas:
  1. ¿Es necesario vaciar la memoria?
  2. ¿Y los registros?
  3. ¿Se necesita vaciar el pipeline?
  4. ¿Y la memoria de programa?

> **Importante:** la carga del programa debe llevarse a cabo a través de la comunicación UART y **sin resintetizar el procesador**.

### 7. Modos de operación

- **Continuo:** se envía un comando a la FPGA por la UART y esta inicia la ejecución del programa hasta llegar al final. Llegado ese punto se muestran en pantalla todos los valores indicados en la sección 5.
- **Paso a paso:** enviando un comando por la UART se ejecuta **un ciclo de clock**. A cada paso se deben mostrar los valores indicados.

En ambos casos, **el pipeline tiene que quedar vacío** al terminar la ejecución.

Responder: **¿Qué sucede si en la memoria no se encuentra una instrucción de parada?**

### 8. Clock

Llegada la integración, responder:

- ¿Cuál es el **camino crítico** del sistema?
- ¿Este camino crítico genera **skew** en el sistema? ¿Qué consecuencias tiene?

De encontrarse skew:

- Encontrar la **frecuencia de funcionamiento óptima** del sistema.
- Generar **métricas de funcionamiento** con las herramientas de Vivado.
- **Aplicar** esa frecuencia de funcionamiento en el sistema.

### 9. Tips de la cátedra

1. No copien, inspírense.
2. Investiguen las herramientas que brinda Vivado (IP Cores para las memorias, Clock Wizard).
3. Antes de escribir la primera línea:
   1. Diseñen, dibujen y esquematicen.
   2. Imaginen los módulos:
      - cómo probarlos,
      - cómo interactúan entre sí,
      - qué herramientas que ya usaron o vieron pueden utilizar.
   3. ¿Cómo voy a interactuar con mi sistema?
   4. ¿Cómo puedo interpretar el estado actual de mi sistema mientras lo uso?

> Todo lo que se les pide ya existe y ya se implementó mil veces. Asegúrense de que lo que hagan ustedes sea único.
> *Es lo último, disfrútenlo.*

### 10. Bibliografía

- **Instrucciones:** RISC-V Instruction Set Manual.
- **Pipeline:** Patterson & Hennessy, *Computer Organization and Design — The Hardware/Software Interface, RISC-V Edition*.
