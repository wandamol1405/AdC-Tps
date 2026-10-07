// =============================================================================
// MODULO: Transmisor UART (uart_tx.v)
//
// ¿QUE HACE ESTE MODULO?
// Toma un dato de 8 bits que le llega todo junto en paralelo (d_in) y lo
// transmite bit a bit por un unico cable serie (tx).
//
// ¿COMO ARMA EL PAQUETE UART?
// 1. En reposo la linea serie esta siempre en 1.
// 2. Start bit: baja la linea a 0 para avisarle al receptor que empieza un dato.
// 3. Bits de datos: manda los 8 bits de a uno, empezando por el menos
//    significativo (LSB, el bit 0) hasta el mas significativo (MSB, bit 7).
// 4. Stop bit: vuelve a subir la linea a 1 para avisar que la transmision termino.
//
// ¿POR QUE SE CUENTAN 16 TICKS POR BIT?
// El modulo Baud Rate Generator genera una señal de pulsos llamada "i_tick".
// Manda 16 ticks por cada bit (sobremuestreo 16x). Por eso, cuando contamos
// 16 ticks (del 0 al 15), sabemos que ya paso exactamente el tiempo de un bit.
// =============================================================================

module uart_tx #(
    parameter D_BIT            = 8,  // Cantidad de bits del dato (8 bits = 1 byte)
    parameter SB_TICK          = 16, // Ticks que dura el bit de Stop (16 ticks = 1 bit)
    parameter OVERSAMPLE_TICK = 16  // Ticks que dura cada bit normal (Start y Datos)
) (
    input  wire               clk,          // Reloj principal de la placa (100 MHz)
    input  wire               reset,        // Señal de reinicio (resetea todo a IDLE)
    input  wire [D_BIT-1:0]   d_in,         // El byte que queremos transmitir
    input  wire               tx_start,     // Orden de inicio: ponela en 1 por un ciclo para arrancar
    input  wire               i_tick,       // Pulsito que viene del Baud Rate Generator (16 por bit)
    output reg                tx,           // Cable de salida serie por donde viajan los bits
    output reg                tx_done       // Pulso en 1 que avisa: "ya termine de mandar el byte"
);

    // -------------------------------------------------------------------------
    // ESTADOS DE LA MAQUINA (FSM)
    // -------------------------------------------------------------------------
    localparam [1:0]
        IDLE  = 2'b00, // Reposo: esperando que alguien le pida transmitir
        START = 2'b01, // Mandando el bit de Start (0)
        DATA  = 2'b10, // Mandando los bits de datos uno por uno
        STOP  = 2'b11; // Mandando el bit de Stop (1) y avisando que termino

    // El contador cuenta de 0 a 15 para completar los 16 ticks (15 es el tick final)
    localparam DATA_FULL_BIT = OVERSAMPLE_TICK - 1; // 16 - 1 = 15
    localparam STOP_FULL_BIT = SB_TICK - 1;          // 16 - 1 = 15

    // Cantidad de bits necesarios para el contador de ticks (ej: para contar hasta 15 necesitamos 4 bits)
    localparam TICK_CNT_WIDTH = (SB_TICK > OVERSAMPLE_TICK) ? $clog2(SB_TICK) : $clog2(OVERSAMPLE_TICK);

    // -------------------------------------------------------------------------
    // VARIABLES Y REGISTROS INTERNOS
    // Usamos parejas: _reg (lo que vale ahora) y _next (lo que va a valer en el proximo ciclo)
    // -------------------------------------------------------------------------
    reg [1:0]                state_reg, state_next;       // En que estado estamos y a cual vamos
    reg [TICK_CNT_WIDTH-1:0] tick_count, tick_count_next; // Cuenta los 16 ticks de cada bit (0 a 15)
    reg [3:0]                bit_count, bit_count_next;   // Cuenta cual de los 8 bits de datos estamos mandando (0 a 7)
    reg [D_BIT-1:0]          b_reg, b_next;               // Registro donde guardamos el dato y lo vamos corriendo a la derecha


    // =========================================================================
    // BLOQUE 1: MEMORIA DE LA FSM (Secuencial, sincronico con el clock)
    //
    // Este bloque solo contiene flip-flops. En cada flanco positivo de reloj (clk):
    // - Si hay reset: limpia todo y vuelve a IDLE.
    // - Si no: actualiza los valores actuales con lo que calculo la logica combinacional.
    // =========================================================================
    always @(posedge clk) begin
        if (reset) begin
            state_reg  <= IDLE;
            tick_count <= {TICK_CNT_WIDTH{1'b0}};
            bit_count  <= 4'd0;
            b_reg      <= {D_BIT{1'b0}};
        end else begin
            state_reg  <= state_next;
            tick_count <= tick_count_next;
            bit_count  <= bit_count_next;
            b_reg      <= b_next;
        end
    end


    // =========================================================================
    // BLOQUE 2: EL CEREBRO DE LA FSM (Logica de proximo estado y datapath)
    //
    // Es puramente combinacional: mira en que estado estamos y las entradas,
    // y decide a que estado ir y como actualizar los contadores en el siguiente ciclo.
    // =========================================================================
    always @(*) begin
        // Valores por defecto (si no entra a ningun if, se queda como esta para no generar latches)
        state_next      = state_reg;
        tick_count_next = tick_count;
        bit_count_next  = bit_count;
        b_next          = b_reg;

        case (state_reg)

            // -----------------------------------------------------------------
            // ESTADO IDLE (Reposo)
            // La linea esta quieta. Si nos ponen tx_start en 1:
            // 1. Guardamos el byte a transmitir en nuestro registro (b_reg = d_in).
            // 2. Ponemos el contador de ticks en 0.
            // 3. Pasamos al estado START para empezar a transmitir.
            // -----------------------------------------------------------------
            IDLE: begin
                if (tx_start) begin
                    state_next      = START;
                    tick_count_next = {TICK_CNT_WIDTH{1'b0}};
                    b_next          = d_in;
                end
            end

            // -----------------------------------------------------------------
            // ESTADO START (Start bit)
            // Tenemos que mantener el 0 durante 16 ticks.
            // Cada vez que llega un "i_tick":
            // - Si todavia no llego a 15, suma 1 tick.
            // - Si llego a 15 (ya pasaron los 16 ticks del start bit):
            //   resetea contadores y pasa al estado DATA para empezar con los datos.
            // -----------------------------------------------------------------
            START: begin
                if (i_tick) begin
                    if (tick_count == DATA_FULL_BIT) begin
                        state_next      = DATA;
                        tick_count_next = {TICK_CNT_WIDTH{1'b0}};
                        bit_count_next  = 4'd0; // Arrancamos con el bit 0
                    end else begin
                        tick_count_next = tick_count + 1'b1;
                    end
                end
            end

            // -----------------------------------------------------------------
            // ESTADO DATA (Bits de datos)
            // El bit que sale por el cable siempre es el bit de mas a la derecha: b_reg[0].
            // Cada vez que completamos 16 ticks de ese bit (tick_count == 15):
            // - Corremos el registro un lugar a la derecha (b_reg >> 1).
            //   Asi, el bit siguiente se ubica en b_reg[0] para ser transmitido.
            // - Si ya mandamos los 8 bits (bit_count == 7), pasamos al estado STOP.
            // - Si faltan bits, sumamos 1 al contador de bits y seguimos en DATA.
            // -----------------------------------------------------------------
            DATA: begin
                if (i_tick) begin
                    if (tick_count == DATA_FULL_BIT) begin
                        tick_count_next = {TICK_CNT_WIDTH{1'b0}}; // Resetea contador para el proximo bit
                        b_next          = b_reg >> 1;            // Desplaza a la derecha
                        if (bit_count == D_BIT - 1) begin
                            state_next = STOP; // Ya mandamos los 8 bits, toca el Stop bit
                        end else begin
                            bit_count_next = bit_count + 1'b1; // Pasa al siguiente bit
                        end
                    end else begin
                        tick_count_next = tick_count + 1'b1;
                    end
                end
            end

            // -----------------------------------------------------------------
            // ESTADO STOP (Stop bit)
            // Tenemos que mantener la linea en 1 durante 16 ticks para cerrar el frame.
            // Cuando llegamos al tick 15:
            // - Pasamos de nuevo a IDLE (la transmision termino con exito).
            // - En la logica de salida se enciende tx_done por este ciclo.
            // -----------------------------------------------------------------
            STOP: begin
                if (i_tick) begin
                    if (tick_count == STOP_FULL_BIT) begin
                        state_next      = IDLE;
                        tick_count_next = {TICK_CNT_WIDTH{1'b0}};
                        bit_count_next  = 4'd0;
                    end else begin
                        tick_count_next = tick_count + 1'b1;
                    end
                end
            end

            // -----------------------------------------------------------------
            // RECUPERACION ANTE ERRORES (Fault Recovery seguro)
            // Si por ruido electrico o error la maquina cae en un estado que no
            // existe, en el siguiente ciclo vuelve sana y salva a IDLE.
            // -----------------------------------------------------------------
            default: begin
                state_next      = IDLE;
                tick_count_next = {TICK_CNT_WIDTH{1'b0}};
                bit_count_next  = 4'd0;
                b_next          = {D_BIT{1'b0}};
            end
        endcase
    end


    // =========================================================================
    // BLOQUE 3: LOGICA DE SALIDAS (Combinacional)
    //
    // Este bloque decide que señal poner fisicamente en los cables de salida:
    // - tx: el cable por donde salen los bits.
    // - tx_done: el aviso de "terminé".
    // Depende exclusivamente del estado en el que estemos en este momento.
    // =========================================================================
    always @(*) begin
        // Valores por defecto
        tx      = 1'b1; // Por defecto la linea serie reposa en 1 (norma UART)
        tx_done = 1'b0; // Por defecto no avisa fin

        case (state_reg)
            IDLE: begin
                tx = 1'b1; // En reposo, la linea siempre va en 1
            end

            START: begin
                tx = 1'b0; // El Start bit siempre es un 0 logico
            end

            DATA: begin
                tx = b_reg[0]; // Manda el bit menos significativo del byte
            end

            STOP: begin
                tx = 1'b1; // El Stop bit siempre es un 1 logico
                // Si estamos en STOP y justo es el ultimo tick del bit de stop:
                if (i_tick && (tick_count == STOP_FULL_BIT)) begin
                    tx_done = 1'b1; // Pegamos el grito: ¡byte transmitido!
                end
            end

            default: begin
                tx      = 1'b1;
                tx_done = 1'b0;
            end
        endcase
    end

endmodule