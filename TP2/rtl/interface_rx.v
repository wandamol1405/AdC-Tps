// =============================================================================
// MODULO: Interface Circuit Receptor (interface_rx.v)
//
// ¿QUE HACE ESTE MODULO?
// Es el puente o "buzón intermedio" entre uart_rx y el consumidor (loader_uart).
//
// ¿POR QUE SE NECESITA?
// uart_rx recibe un byte cada vez que termina una trama serie (a la velocidad
// del baud rate, muy lenta comparada con el clock de 100 MHz) y solo avisa con
// un pulso de 1 ciclo (i_rx_done_tick). Sin este módulo, quien consume el dato
// tendría que estar escuchando exactamente en ese ciclo o lo perdería. Este
// módulo guarda el byte y levanta una bandera de "hay dato nuevo" (o_rx_empty
// en 0) hasta que el consumidor confirma que ya lo leyó con i_rd.
//
// ESTRUCTURA INTERNA:
// Es muy simple, no lleva máquina de estados (FSM):
// - 1 registro de N_buffer bits (r_data) para guardar el byte recibido.
// - 1 flip-flop de bandera (r_rx_empty) que se pone en 0 con i_rx_done_tick
//   (set_flag) y en 1 con i_rd (clr_flag).
//
// PRIORIDAD SET vs CLEAR:
// Si i_rx_done_tick e i_rd llegan en el mismo ciclo, gana el dato nuevo (se
// prioriza no perder la trama recién recibida por sobre la lectura vieja).
//
// OVERRUN:
// Si llega una segunda trama antes de que se lea la primera, el buffer se
// pisa con el dato más nuevo y el dato viejo se pierde — comportamiento
// esperado de este esquema (ver TP2/README.md, sección "Camino Rx -> ALU").
// =============================================================================

module interface_rx #(
    parameter N_buffer = 8 // Cantidad de bits del dato (8 bits = 1 byte)
) (
    input  wire                clk,            // Reloj del sistema (100 MHz)
    input  wire                reset,          // Reset sincrónico (limpia el buffer y sube la bandera de vacío)

    // --- Lado uart_rx (quien recibe el byte en serie) ---
    input  wire [N_buffer-1:0] i_rx_data,      // Byte recibido, conectado a o_data de uart_rx
    input  wire                i_rx_done_tick, // Pulso de 1 ciclo de uart_rx: "llegó un byte" (set_flag)

    // --- Lado consumidor / loader_uart (quien lee el dato) ---
    input  wire                i_rd,           // Pulso de 1 ciclo: "ya leí el dato" (clr_flag)
    output wire [N_buffer-1:0] o_r_data,       // Byte bufferizado, listo para leer
    output wire                o_rx_empty      // 1 = no hay dato nuevo, 0 = hay un dato esperando lectura
);

    // -------------------------------------------------------------------------
    // REGISTROS INTERNOS
    // -------------------------------------------------------------------------
    reg [N_buffer-1:0] r_data,     r_data_next;     // Buffer: guarda el último byte recibido
    reg                r_rx_empty, r_rx_empty_next; // Bandera: 1 = vacío, 0 = hay dato sin leer

    // -------------------------------------------------------------------------
    // LOGICA SECUENCIAL (Flip-Flops con clock)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            // En reset el buzón queda vacío: sin dato y con la bandera de vacío arriba
            r_data     <= 0;
            r_rx_empty <= 1;
        end else begin
            r_data     <= r_data_next;
            r_rx_empty <= r_rx_empty_next;
        end
    end

    // -------------------------------------------------------------------------
    // LOGICA COMBINACIONAL (próximo valor de cada registro)
    // -------------------------------------------------------------------------
    always @(*) begin
        r_data_next     = r_data;
        r_rx_empty_next = r_rx_empty;

        if (i_rx_done_tick) begin
            // SET FLAG: uart_rx nos entrega un byte nuevo.
            // Lo guardamos en el buffer y bajamos la bandera de vacío (hay dato).
            // Tiene prioridad sobre la lectura: si coincide con i_rd en el
            // mismo ciclo, no queremos perder la trama recién llegada.
            r_data_next     = i_rx_data;
            r_rx_empty_next = 0;
        end else if (i_rd) begin
            // CLEAR FLAG: el consumidor avisa que ya leyó el dato.
            // Solo sube la bandera de vacío; el buffer retiene el último
            // byte (no se borra), aunque ya no importa hasta la próxima lectura.
            r_rx_empty_next = 1;
        end
    end

    // -------------------------------------------------------------------------
    // SALIDAS CONTINUAS
    // -------------------------------------------------------------------------
    assign o_r_data   = r_data;     // El byte guardado, disponible para quien lo consuma
    assign o_rx_empty = r_rx_empty; // La bandera de "no hay nada nuevo" hacia el consumidor

endmodule
