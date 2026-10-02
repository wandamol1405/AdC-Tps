// =============================================================================
// MODULO: Emisor de resultados (result_sender.v)
//
// ¿QUE HACE ESTE MODULO?
// Mira la salida de la ALU y, cada vez que cambia, manda 2 bytes por la UART
// a través de interface_tx:
//   - byte 1 = resultado          (i_result)
//   - byte 2 = status             ({6'b0, i_overflow, i_carry})
//
// ¿CUANDO MANDA?
// Solo cuando i_enable_alu = 1 (A, B y Op ya se cargaron alguna vez) y:
//   - es el primer envío desde el reset (sent_once = 0), o
//   - {i_result, i_overflow, i_carry} es distinto de lo último que se mandó.
// Si la ALU no cambia, no manda nada (la GUI tiene que leer con timeout).
//
// LA "FOTO" (snapshot):
// Al salir de IDLE se copian resultado y status en snap_result/snap_status, y
// los 2 bytes se mandan desde esa copia. Así los dos bytes siempre son de la
// misma cuenta aunque la ALU cambie a mitad del envío. La foto sirve además
// como "lo último que mandé" para detectar el próximo cambio. Si la ALU cambia
// varias veces mientras se transmite, al volver a IDLE se manda solo el valor
// más reciente (los intermedios se descartan).
//
// HANDSHAKE CON interface_tx (la "banderita" = i_tx_full):
// o_wr se pulsa SOLO si i_tx_full = 0, y en ese mismo ciclo se avanza de
// estado. El flag de interface_tx sube recién en el flanco siguiente, así que
// en el estado de después ya se lo ve en 1 y se espera. Nunca se escribe con
// el buzón ocupado (eso pisaría el byte pendiente y se perdería).
// =============================================================================

module result_sender #(
    parameter D_BIT = 8 // Cantidad de bits del dato (8 bits = 1 byte)
) (
    input  wire             clk,          // Reloj del sistema (100 MHz)
    input  wire             reset,        // Reset sincrónico (vuelve a IDLE y olvida lo enviado)

    // --- Lado ALU ---
    input  wire [D_BIT-1:0] i_result,     // Resultado de la ALU
    input  wire             i_overflow,   // Overflow de la ALU
    input  wire             i_carry,      // Carry de la ALU
    input  wire             i_enable_alu, // Enable unificado: no manda nada mientras esté en 0

    // --- Lado interface_tx ---
    input  wire             i_tx_full,    // 1 = buzón de salida ocupado (la "banderita")
    output reg  [D_BIT-1:0] o_w_data,     // Byte a transmitir
    output reg              o_wr          // Pulso de 1 ciclo: "mandá este byte"
);

    // -------------------------------------------------------------------------
    // ESTADOS DE LA MAQUINA (FSM)
    // -------------------------------------------------------------------------
    localparam [1:0]
        IDLE        = 2'b00, // Esperando un cambio en la salida de la ALU
        SEND_RESULT = 2'b01, // Esperando buzón libre para mandar el resultado
        SEND_STATUS = 2'b10; // Esperando buzón libre para mandar el status
        // 2'b11 no se usa: si se llega ahí, el default vuelve a IDLE

    // -------------------------------------------------------------------------
    // VARIABLES Y REGISTROS INTERNOS (_reg = valor actual, _next = próximo)
    // -------------------------------------------------------------------------
    reg [1:0]       state_reg,   state_next;
    reg [D_BIT-1:0] snap_result, snap_result_next; // Foto del resultado
    reg [D_BIT-1:0] snap_status, snap_status_next; // Foto del status ya empaquetado
    reg             sent_once,   sent_once_next;   // 1 = ya se tomó al menos una foto

    // Status tal como está ahora en la ALU, empaquetado en un byte
    wire [D_BIT-1:0] status_now = {{(D_BIT-2){1'b0}}, i_overflow, i_carry};

    // 1 = la salida de la ALU es distinta de la última foto enviada
    wire changed = ({i_result, i_overflow, i_carry} != {snap_result, snap_status[1:0]});


    // =========================================================================
    // BLOQUE 1: REGISTRO DE ESTADO (Secuencial, sincronico con el clock)
    // =========================================================================
    always @(posedge clk) begin
        if (reset) begin
            state_reg   <= IDLE;
            snap_result <= {D_BIT{1'b0}};
            snap_status <= {D_BIT{1'b0}};
            sent_once   <= 1'b0;
        end else begin
            state_reg   <= state_next;
            snap_result <= snap_result_next;
            snap_status <= snap_status_next;
            sent_once   <= sent_once_next;
        end
    end


    // =========================================================================
    // BLOQUE 2: LOGICA DE PROXIMO ESTADO (Combinacional)
    // =========================================================================
    always @(*) begin
        // Por defecto todo se queda como está (evita latches)
        state_next       = state_reg;
        snap_result_next = snap_result;
        snap_status_next = snap_status;
        sent_once_next   = sent_once;

        case (state_reg)
            // -----------------------------------------------------------------
            // IDLE: si la ALU está habilitada y hay algo nuevo para contar,
            // sacamos la foto y arrancamos el envío.
            // -----------------------------------------------------------------
            IDLE: begin
                if (i_enable_alu && (!sent_once || changed)) begin
                    snap_result_next = i_result;
                    snap_status_next = status_now;
                    sent_once_next   = 1'b1;
                    state_next       = SEND_RESULT;
                end
            end

            // -----------------------------------------------------------------
            // SEND_RESULT: esperamos a que la banderita esté abajo. En el ciclo
            // en que lo está, la lógica de salida pulsa o_wr y avanzamos.
            // -----------------------------------------------------------------
            SEND_RESULT: begin
                if (!i_tx_full) begin
                    state_next = SEND_STATUS;
                end
            end

            // -----------------------------------------------------------------
            // SEND_STATUS: acá la banderita ya está arriba (la subió el byte de
            // resultado), así que esperamos a que uart_tx termine y la baje.
            // -----------------------------------------------------------------
            SEND_STATUS: begin
                if (!i_tx_full) begin
                    state_next = IDLE;
                end
            end

            // -----------------------------------------------------------------
            // RECUPERACION ANTE ERRORES (Fault Recovery): estado inválido 2'b11
            // -----------------------------------------------------------------
            default: begin
                state_next = IDLE;
            end
        endcase
    end


    // =========================================================================
    // BLOQUE 3: LOGICA DE SALIDAS (Combinacional)
    // o_wr depende del estado y de i_tx_full: solo se escribe con el buzón libre.
    // =========================================================================
    always @(*) begin
        // Valores por defecto: no escribir nada
        o_wr     = 1'b0;
        o_w_data = {D_BIT{1'b0}};

        case (state_reg)
            SEND_RESULT: begin
                o_w_data = snap_result;
                o_wr     = !i_tx_full;
            end

            SEND_STATUS: begin
                o_w_data = snap_status;
                o_wr     = !i_tx_full;
            end

            default: begin
                o_wr     = 1'b0;
                o_w_data = {D_BIT{1'b0}};
            end
        endcase
    end

endmodule
