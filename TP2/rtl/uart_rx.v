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
// Registro donde se va armando el byte recibido (actual y próximo valor).
// Es un registro con clock, no un latch: si se asignara solo en algunas ramas
// de un always @(*), la síntesis infiere un latch cuya habilitación sale de
// lógica combinacional y en la FPGA puede capturar bits equivocados.
reg [D_BIT-1:0] data_reg, data_next;
// Registro de estado actual y próximo estado
reg [3:0] state_reg, state_next;

always @(posedge clk) begin
    if (reset) begin
        // Inicialización de registros y señales de salida
        state_reg <= IDLE;
        tick_count <= 0;
        bit_count <= 0;
        data_reg <= {D_BIT{1'b0}};
        o_data <= {D_BIT{1'b0}};
    end else begin
        // Lógica de recepción UART
        state_reg <= state_next;
        tick_count <= tick_count_next;
        bit_count <= bit_count_next;
        data_reg <= data_next;
        o_data <= data_reg;
    end
end

// Lógica de cambio de estado: determina state_next, los contadores
// internos (tick_count_next, bit_count_next) y el byte en armado
// (data_next) en función del estado actual y las entradas.
always @(*) begin
    state_next = state_reg;
    tick_count_next = tick_count;
    bit_count_next = bit_count;
    data_next = data_reg; // Por defecto el byte se mantiene (evita latches)

    case (state_reg)
        IDLE: begin
            if (in_rx == 1'b0) begin // Detecta el inicio de la transmisión
                state_next = START;
                tick_count_next = 0;
                bit_count_next = 0;
                data_next = {D_BIT{1'b0}}; // Arranca un byte nuevo
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
                    data_next[bit_count] = in_rx; // Almacena el bit recibido (mitad del bit)
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
            data_next = {D_BIT{1'b0}};
        end
    endcase
end

// Lógica de salida: sólo actualiza o_done_tick, en función del estado
// actual y las entradas. o_data sale registrado de data_reg (ver arriba):
// el último bit se guarda 16 ticks antes del fin del stop, así que cuando
// pulsa o_done_tick, o_data ya tiene el byte completo.
always @(*) begin
    o_done_tick = 1'b0;

    case (state_reg)
        STOP: begin
            // Espera un tiempo para confirmar el final de la transmisión
            if (i_tick && tick_count == STOP_FULL_BIT) begin
                o_done_tick = 1'b1; // Indica que se ha recibido un byte completo
            end
        end

        default: o_done_tick = 1'b0;
    endcase
end
endmodule