module uart_tx #(
    parameter D_BIT            = 8,  // Cantidad de bits de datos (8)
    parameter SB_TICK          = 16, // Ticks por bit de stop (16 ticks = 1 bit de stop)
    parameter OVERSAMPLE_TICK = 16  // Ticks por bit de datos/start (muestreo 16x)
) (
    input  wire               clk,          // Clock del sistema
    input  wire               reset,        // Reset sincrónico
    input  wire [D_BIT-1:0]   d_in,         // Dato paralelo a transmitir
    input  wire               tx_start,     // Solicitud de inicio de transmisión (handshake)
    input  wire               i_tick,       // Pulso de 1 ciclo generado por el Baud Rate Generator
    output reg                tx,           // Salida serie UART
    output reg                tx_done       // Pulso de 1 ciclo que indica fin de transmisión
);

    // Estados de la FSM
    localparam [1:0]
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11;

    // Tiempos medidos en ticks para 1 bit completo
    localparam DATA_FULL_BIT = OVERSAMPLE_TICK - 1; // 15 -> lo que dura un bit en ticks
    localparam STOP_FULL_BIT = SB_TICK - 1;          // 15

    // Ancho dinámico para el contador de ticks
    localparam TICK_CNT_WIDTH = (SB_TICK > OVERSAMPLE_TICK) ? $clog2(SB_TICK) : $clog2(OVERSAMPLE_TICK);

    // Registros de la FSM y contadores
    reg [1:0]                state_reg, state_next; // Registro de estado actual y próximo estado
    reg [TICK_CNT_WIDTH-1:0] tick_count, tick_count_next;  
    reg [3:0]                bit_count, bit_count_next;
    reg [D_BIT-1:0]          b_reg, b_next; // b_reg es el shift register que almacena el dato a transmitir, los 8 bits a mandar
    reg                      tx_reg, tx_next; //tx_reg es el registro que almacena el valor de la salida tx, para evitar ruido en el pin


    always @(posedge clk) begin
        if (reset) begin
            state_reg  <= IDLE;
            tick_count <= {TICK_CNT_WIDTH{1'b0}};
            bit_count  <= 4'd0;
            b_reg      <= {D_BIT{1'b0}};
            tx_reg     <= 1'b1; // En reset o reposo, la línea serie debe estar en 1 lógico (Idle)
        end else begin
            state_reg  <= state_next;
            tick_count <= tick_count_next;
            bit_count  <= bit_count_next;
            b_reg      <= b_next;
            tx_reg     <= tx_next;
        end
    end

    always @(*) begin
        // Asignaciones por defecto para evitar Latches
        state_next      = state_reg;
        tx_done         = 1'b0; 
        tick_count_next = tick_count;
        bit_count_next  = bit_count;
        b_next          = b_reg;
        tx_next         = tx_reg;

        case (state_reg)
            // ESTADO IDLE: Espera la señal tx_start en nivel alto
            IDLE: begin
                tx_next = 1'b1; // salida serie en reposo (1 lógico)
                if (tx_start) begin  // Si se solicita inicio de transmisión
                    state_next      = START;
                    tick_count_next = 0;
                    b_next          = d_in; // Carga el dato paralelo al shift register
                end
            end

            // ESTADO START: Sostiene el Start Bit (0 lógico) durante 16 ticks
            START: begin
                tx_next = 1'b0; // Pone la línea serie en 0 (Start bit) -> el receptor detecta el flanco de bajada 
                if (i_tick) begin
                    if (tick_count == DATA_FULL_BIT) begin // Si completó los 16 ticks del Start Bit
                        state_next      = DATA;
                        tick_count_next = 0;
                        bit_count_next  = 0;
                    end else begin
                        tick_count_next = tick_count + 1'b1;
                    end
                end
            end

            // ESTADO DATA: Envía bit a bit (LSB primero) cada 16 ticks
            DATA: begin
                tx_next = b_reg[0];  // Saca siempre el bit menos significativo (LSB first)
                if (i_tick) begin
                    if (tick_count == DATA_FULL_BIT) begin // Si completó los 16 ticks del bit actual
                        tick_count_next = 0;
                        b_next          = b_reg >> 1; // Desplaza a la derecha para poner el siguiente bit en b_reg[0]
                        if (bit_count == D_BIT - 1) begin // Si ya envió los 8 bits, pasa al estado STOP
                            state_next = STOP; // Si completó los 8 bits, pasa a Stop
                        end else begin
                            bit_count_next = bit_count + 1'b1;
                        end
                    end else begin
                        tick_count_next = tick_count + 1'b1;
                    end
                end
            end

            // ESTADO STOP: Sostiene el Stop Bit (1 lógico) durante los ticks correspondientes
            STOP: begin
                tx_next = 1'b1; // Pone la línea serie en 1 (Stop bit)
                if (i_tick) begin
                    if (tick_count == STOP_FULL_BIT) begin
                        tx_done         = 1'b1; // Emite el pulso de 1 ciclo indicando fin de transmisión
                        state_next      = IDLE; // Retorna al reposo
                        tick_count_next = 0;
                        bit_count_next  = 0;
                    end else begin
                        tick_count_next = tick_count + 1'b1;
                    end
                end
            end

            // ESTADO DE RECUPERACIÓN (Fault Recovery seguro)
            default: begin
                state_next      = IDLE;
                tick_count_next = 0;
                bit_count_next  = 0;
                tx_next         = 1'b1;
            end
        endcase
    end

    always @(*) begin
        tx = tx_reg; // Asigna el valor del buffer registrado a la salida física para evitar glitches
    end

endmodule