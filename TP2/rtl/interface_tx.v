// =============================================================================
// MODULO: Interface Circuit Transmisor (interface_tx.v)
//
// ¿QUE HACE ESTE MODULO?
// Es el puente o "buzón intermedio" entre la ALU (o result_sender) y el uart_tx.
//
// ¿POR QUE SE NECESITA?
// La ALU procesa cosas a 100 MHz (muy rápido) y uart_tx transmite bit a bit
// (muy lento). Este módulo le da a la ALU una señal de "semáforo" (o_tx_full):
// - Si o_tx_full = 0: la ALU puede mandar un dato con un pulso de i_wr.
// - Si o_tx_full = 1: el módulo está ocupado esperando que uart_tx termine,
//   así que la ALU debe esperar.
//
// ESTRUCTURA INTERNA:
// Es muy simple, no lleva máquina de estados (FSM):
// - 1 registro de 8 bits (buf_reg) para guardar el byte.
// - 1 flip-flop de bandera (flag_reg) que se pone en 1 con i_wr y en 0 con i_tx_done.
// =============================================================================

module interface_tx #(
    parameter D_BIT = 8 // Cantidad de bits del dato (8 bits = 1 byte)
) (
    input  wire             clk,        // Reloj del sistema (100 MHz)
    input  wire             reset,      // Reset sincrónico (limpia el registro y baja la bandera)
    
    // --- Lado ALU / result_sender (quien escribe el dato) ---
    input  wire [D_BIT-1:0] i_w_data,   // Byte que se quiere transmitir
    input  wire             i_wr,       // Pulso de 1 ciclo: "quiero transmitir esto" (set_flag)
    output wire             o_tx_full,  // 1 = ocupado transmitiendo, 0 = libre para recibir otro byte
    
    // --- Lado uart_tx (quien transmite en serie por el cable) ---
    input  wire             i_tx_done,  // Pulso de 1 ciclo de uart_tx avisando que terminó (clr_flag)
    output wire [D_BIT-1:0] o_d_in,     // Byte conectado a la entrada d_in de uart_tx
    output wire             o_tx_start  // Conectado a tx_start de uart_tx (se mantiene en 1 mientras flag=1)
);

    // -------------------------------------------------------------------------
    // REGISTROS INTERNOS
    // -------------------------------------------------------------------------
    reg [D_BIT-1:0] buf_reg;  // Guarda el byte a transmitir para que quede estable
    reg             flag_reg; // Bandera de estado: 1 = ocupado/transmitiendo, 0 = libre


    // -------------------------------------------------------------------------
    // LOGICA SECUENCIAL (Flip-Flops con clock)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            // En reset dejamos el buzón vacío y la bandera abajo
            buf_reg  <= {D_BIT{1'b0}};
            flag_reg <= 1'b0;
        end else begin
            if (i_wr) begin
                // SET FLAG: La ALU nos entrega un dato nuevo.
                // Lo guardamos en el buffer y levantamos la bandera (ocupado).
                buf_reg  <= i_w_data;
                flag_reg <= 1'b1;
            end else if (i_tx_done) begin
                // CLEAR FLAG: uart_tx nos avisa que ya mandó la trama completa.
                // Bajamos la bandera (quedamos libres de nuevo).
                flag_reg <= 1'b0;
            end
        end
    end


    // -------------------------------------------------------------------------
    // SALIDAS CONTINUAS
    // -------------------------------------------------------------------------
    // El byte guardado en el buffer va directo a la entrada de datos de uart_tx
    assign o_d_in = buf_reg;

    // La bandera roja de "ocupado" hacia la ALU
    assign o_tx_full = flag_reg;

    // La orden de transmisión hacia uart_tx. Se mantiene en nivel alto mientras
    // la bandera esté levantada; uart_tx la captura apenas está en IDLE.
    assign o_tx_start = flag_reg;

endmodule

