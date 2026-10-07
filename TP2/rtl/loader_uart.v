// =============================================================================
// MODULO: Loader UART (loader_uart.v)
//
// ¿QUE HACE ESTE MODULO?
// Es el equivalente por UART de load_ctrl.v (TP1): lee los bytes que deja
// interface_rx, decodifica el protocolo de trama y genera los pulsos de carga
// o_enb_reg_A/B/OP hacia reg_bank.
//
// PROTOCOLO (2 bytes por trama: dirección + valor):
// - Byte 1 = dirección: 0x01 = Op, 0x02 = A, 0x03 = B.
// - Byte 2 = valor: se pulsa durante 1 ciclo el o_enb_reg_* que corresponde a
//   la dirección. En ese mismo ciclo i_r_data tiene el valor, así que reg_bank
//   lo captura directamente del bus de interface_rx.
// - No hay comando EXEC: la ALU de TP1 es combinacional con habilitación
//   sticky, así que alcanza con cargar el último campo pendiente.
//
// FAULT RECOVERY:
// Si la dirección no es válida, el byte de valor se consume igual (o_rd) pero
// no se pulsa ningún enable, y la FSM vuelve a WAIT_CMD. Así la trama queda
// descartada completa y la siguiente se decodifica bien.
//
// ESTRUCTURA INTERNA:
// FSM de 2 estados (WAIT_CMD / WAIT_VALUE) + 1 registro con la dirección
// recibida (addr_reg). Las salidas son de tipo Mealy: dependen del estado y
// de i_rx_empty, para que el pulso caiga en el mismo ciclo en que llega el byte.
//
// ¿POR QUE PULSOS EN CRUDO Y NO UN o_enable_alu?
// El enable de la ALU tiene que ser único y compartido con load_ctrl.v. Si cada
// módulo tuviera su propio sticky y se combinaran con un OR, una carga mixta
// (por ejemplo A por switches, B y Op por UART) nunca habilitaría la ALU. Por
// eso la lógica sticky unificada se calcula afuera de este módulo.
// =============================================================================

module loader_uart #(
    parameter N_BITS = 8 // Cantidad de bits del dato (8 bits = 1 byte)
) (
    input  wire              clk,          // Reloj del sistema (100 MHz)
    input  wire              reset,        // Reset sincrónico (vuelve a WAIT_CMD)

    // --- Lado interface_rx (de donde se leen los bytes) ---
    input  wire [N_BITS-1:0] i_r_data,     // Byte bufferizado en interface_rx
    input  wire              i_rx_empty,   // 1 = no hay dato nuevo, 0 = hay un dato esperando lectura
    output reg               o_rd,         // Pulso de 1 ciclo: "ya leí el dato" (clr_flag de interface_rx)

    // --- Lado reg_bank (hacia el wiring final, junto con load_ctrl.v) ---
    output reg               o_enb_reg_A,  // Pulso de 1 ciclo: cargar i_r_data en A
    output reg               o_enb_reg_B,  // Pulso de 1 ciclo: cargar i_r_data en B
    output reg               o_enb_reg_OP  // Pulso de 1 ciclo: cargar i_r_data en Op
);

    // -------------------------------------------------------------------------
    // ESTADOS DE LA FSM
    // -------------------------------------------------------------------------
    localparam WAIT_CMD   = 1'b0,  // Esperando el byte de dirección
               WAIT_VALUE = 1'b1;  // Dirección guardada, esperando el byte de valor

    // -------------------------------------------------------------------------
    // DIRECCIONES DEL PROTOCOLO (cualquier otro valor es inválido)
    // -------------------------------------------------------------------------
    localparam [N_BITS-1:0] ADDR_OP = 8'h01,
                            ADDR_A  = 8'h02,
                            ADDR_B  = 8'h03;

    // -------------------------------------------------------------------------
    // REGISTROS INTERNOS
    // -------------------------------------------------------------------------
    reg              state_reg, state_next; // Estado actual / próximo de la FSM
    reg [N_BITS-1:0] addr_reg,  addr_next;  // Dirección recibida en el primer byte de la trama

    // -------------------------------------------------------------------------
    // LOGICA SECUENCIAL (Flip-Flops con clock)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            // En reset se descarta cualquier trama a medias
            state_reg <= WAIT_CMD;
            addr_reg  <= 0;
        end else begin
            state_reg <= state_next;
            addr_reg  <= addr_next;
        end
    end

    // -------------------------------------------------------------------------
    // LOGICA DE PROXIMO ESTADO: sólo actualiza state_next y addr_next
    // -------------------------------------------------------------------------
    always @(*) begin
        // Por defecto se mantiene el estado y la dirección guardada
        state_next = state_reg;
        addr_next  = addr_reg;

        case (state_reg)
            WAIT_CMD:
                if (!i_rx_empty) begin
                    // Llegó el byte de dirección: se guarda para decodificarlo
                    // cuando llegue el valor
                    addr_next  = i_r_data;
                    state_next = WAIT_VALUE;
                end
            WAIT_VALUE:
                if (!i_rx_empty)
                    // Llegó el byte de valor: la trama terminó, se vuelve a
                    // WAIT_CMD tanto con dirección válida como inválida
                    state_next = WAIT_CMD;
        endcase
    end

    // -------------------------------------------------------------------------
    // LOGICA DE SALIDA: sólo actualiza o_rd y o_enb_reg_*
    // -------------------------------------------------------------------------
    always @(*) begin
        // Por defecto no hay pulsos (además evita latches)
        o_rd         = 1'b0;
        o_enb_reg_A  = 1'b0;
        o_enb_reg_B  = 1'b0;
        o_enb_reg_OP = 1'b0;

        case (state_reg)
            WAIT_CMD:
                if (!i_rx_empty)
                    o_rd = 1'b1; // Consume el byte de dirección
            WAIT_VALUE:
                if (!i_rx_empty) begin
                    o_rd = 1'b1; // Consume el byte de valor
                    // Pulsa solo el enable que corresponde a la dirección guardada.
                    // i_r_data tiene el valor en este mismo ciclo.
                    case (addr_reg)
                        ADDR_OP: o_enb_reg_OP = 1'b1;
                        ADDR_A:  o_enb_reg_A  = 1'b1;
                        ADDR_B:  o_enb_reg_B  = 1'b1;
                        default: ; // Dirección inválida: descarta el valor (fault recovery)
                    endcase
                end
        endcase
    end

endmodule
