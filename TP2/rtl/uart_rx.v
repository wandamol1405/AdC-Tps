module uart_rx #(
    parameter D_BIT = 8,            // Número de bits de datos
    parameter SB_TICK = 16,         // Número de ticks por bit de stop
    parameter OVERSAMPLE_TICK = 16  // Ticks por bit para start/data (debe coincidir con el Baud Rate Generator)
) (
    input wire clk,
    input wire reset,
    input wire in_rx,               // Señal de recepción del UART
    input wire i_tick,              // Pulso de 1 ciclo para cada tick del reloj de muestreo
    output reg [D_BIT-1:0] o_data,  // Byte recibido
    output reg o_done_tick          // Pulso de 1 ciclo cuando se recibe un byte completo
);

// Estados de la FSM
localparam [3:0]
    IDLE = 4'b0000,
    START = 4'b0001,
    DATA = 4'b0010,
    STOP = 4'b0011;

// MIDDLE_BIT/DATA_FULL_BIT usan OVERSAMPLE_TICK (parámetro), no SB_TICK,
// para no depender de la duración configurada del stop.
localparam MIDDLE_BIT = (OVERSAMPLE_TICK / 2) - 1;
localparam DATA_FULL_BIT = OVERSAMPLE_TICK - 1;
localparam STOP_FULL_BIT = SB_TICK - 1;

// Ancho suficiente para contar hasta el mayor entre el sobremuestreo
// y la cantidad de ticks de stop (por si SB_TICK crece para más stop bits).
localparam TICK_CNT_WIDTH = (SB_TICK > OVERSAMPLE_TICK) ? $clog2(SB_TICK) : $clog2(OVERSAMPLE_TICK);

// Contador de ticks dentro del bit actual
reg [TICK_CNT_WIDTH-1:0] tick_count;
// Siguiente tick_count para la lógica combinacional
reg [TICK_CNT_WIDTH-1:0] tick_count_next;
// Contador de bits de datos recibidos
reg [3:0] bit_count;
// Siguiente bit_count para la lógica combinacional
reg [3:0] bit_count_next;
// Registro para almacenar el byte recibido
reg [D_BIT-1:0] data;
// Registro de estado actual y próximo estado
reg [3:0] state_reg, state_next;

always @(posedge clk) begin
    if (reset) begin
        // Inicialización de registros y señales de salida
        state_reg <= IDLE;
        tick_count <= 0;
        bit_count <= 0;
        o_data <= {D_BIT{1'b0}};
    end else begin
        // Lógica de recepción UART
        state_reg <= state_next;
        tick_count <= tick_count_next;
        bit_count <= bit_count_next;
        o_data <= data;
    end
end

// Lógica de cambio de estado: determina state_next y los contadores
// internos (tick_count_next, bit_count_next) en función del estado
// actual y las entradas.
always @(*) begin
    state_next = state_reg;
    tick_count_next = tick_count;
    bit_count_next = bit_count;

    case (state_reg)
        IDLE: begin
            if (in_rx == 1'b0) begin // Detecta el inicio de la transmisión
                state_next = START;
                tick_count_next = 0;
                bit_count_next = 0;
            end
        end

        START: begin
            if (i_tick) begin
                if (tick_count == MIDDLE_BIT) begin
                    if (in_rx == 1'b0) begin // Confirma el start bit
                        state_next = DATA;
                        tick_count_next = 0;
                        bit_count_next = 0;
                    end else begin
                        state_next = IDLE; // Falso start, vuelve a IDLE
                    end
                end else begin
                    tick_count_next = tick_count + 1;
                end
            end
        end

        DATA: begin
            if (i_tick) begin
                if (tick_count == DATA_FULL_BIT) begin
                    tick_count_next = 0;
                    if (bit_count == D_BIT - 1) begin
                        state_next = STOP; // Todos los bits de datos han sido recibidos
                    end else begin
                        bit_count_next = bit_count + 1; // Incrementa el contador de bits
                    end
                end else begin
                    tick_count_next = tick_count + 1;
                end
            end
        end

        STOP: begin
            if (i_tick) begin
                if (tick_count == STOP_FULL_BIT) begin
                    state_next = IDLE;
                    tick_count_next = 0;
                    bit_count_next = 0;
                end else begin
                    tick_count_next = tick_count + 1;
                end
            end
        end

        default: begin
            state_next = IDLE; // Estado por defecto en caso de error
            tick_count_next = 0;
            bit_count_next = 0;
        end
    endcase
end

// Lógica de salida: sólo actualiza o_done_tick y data (que alimenta
// o_data), en función del estado actual y las entradas.
always @(*) begin
    o_done_tick = 1'b0;

    case (state_reg)
        IDLE: begin
            if (in_rx == 1'b0) begin // Detecta el inicio de la transmisión
                data = {D_BIT{1'b0}};
            end
        end

        DATA: begin
            // Recepción de los bits de datos
            if (i_tick && tick_count == DATA_FULL_BIT) begin
                data[bit_count] = in_rx; // Almacena el bit recibido
            end
        end

        STOP: begin
            // Espera un tiempo para confirmar el final de la transmisión
            if (i_tick && tick_count == STOP_FULL_BIT) begin
                o_done_tick = 1'b1; // Indica que se ha recibido un byte completo
                // No resetear 'data' aca: o_data <= data se captura en este
                // mismo flanco, y necesita el byte recien recibido, no 0.
                // 'data' ya se vuelve a limpiar al detectar el proximo start bit (IDLE).
            end
        end

        default: data = {D_BIT{1'b0}};
    endcase
end
endmodule