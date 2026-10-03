// =============================================================================
// MODULO: Top del TP2 (top.v) — ALU del TP1 manejada solo por UART
//
// ¿QUE HACE ESTE MODULO?
// Conecta la UART con la ALU del TP1. Los operandos y el opcode llegan desde
// la PC por el pin rx, y el resultado vuelve por el pin tx:
//
//   rx -> sincronizador -> uart_rx -> interface_rx -> loader_uart -> reg_bank A/B/Op -> ALU
//                                                                                        |
//   tx <- uart_tx <- interface_tx <- result_sender <-------------------------------------+
//
//   baud_rate_generator le da s_tick a uart_rx y a uart_tx.
//
// PROTOCOLO (desde la PC): pares de bytes [dirección, valor]
//   0x01 = Op, 0x02 = A, 0x03 = B. Cualquier otra dirección se descarta.
// RESPUESTA (hacia la PC): 2 bytes cada vez que cambia la salida de la ALU
//   byte 1 = resultado, byte 2 = status {6'b0, overflow, carry}.
//   Si la ALU no cambia no se manda nada: la GUI tiene que leer con timeout.
//
// ALCANCE: solo UART. No hay switches, botones ni load_ctrl.v del TP1; eso se
// agrega más adelante con un mux. ALU.v y reg_bank.v se usan tal cual desde
// TP1/rtl, sin copiarlos ni modificarlos.
//
// LEDs: muestran el resultado igual que en el TP1, solo para poder ver en la
// placa que la ALU recibió bien los datos (no son carga manual).
//   led[7:0] = resultado, led[8] = apagado (separador),
//   led[9] = overflow, led[10] = carry
// =============================================================================

module top #(
    parameter NB_DATA    = 8,          // Bits de los operandos y del resultado
    parameter NB_OP      = 6,          // Bits del opcode
    parameter CLK_FREQ   = 100000000,  // Clock de la Basys3 (100 MHz)
    parameter BAUD_RATE  = 19200,      // Velocidad de la UART
    parameter OVERSAMPLE = 16,         // Ticks por bit (sobremuestreo)
    parameter NB_LED     = NB_DATA + 3 // resultado + separador + overflow + carry
) (
    input  wire              clk,   // Reloj de 100 MHz (pin W5)
    input  wire              reset, // Reset sincrónico (btnD, pin U17)
    input  wire              rx,    // Línea serie desde la PC (pin B18, RsRx)
    output wire              tx,    // Línea serie hacia la PC (pin A18, RsTx)
    output wire [NB_LED-1:0] led    // Resultado y banderas, para ver en la placa
);

    // -------------------------------------------------------------------------
    // CABLES INTERNOS
    // -------------------------------------------------------------------------
    // Recepción
    wire               s_tick;                     // 16 ticks por bit, para Rx y Tx
    wire [NB_DATA-1:0] rx_data;                    // uart_rx -> interface_rx
    wire               rx_done_tick;               // uart_rx -> interface_rx
    wire [NB_DATA-1:0] r_data;                     // interface_rx -> loader_uart y reg_bank
    wire               rx_empty;                   // interface_rx -> loader_uart
    wire               rd;                         // loader_uart -> interface_rx
    wire               enb_reg_A, enb_reg_B, enb_reg_OP; // loader_uart -> reg_bank

    // Registros y ALU
    wire [NB_DATA-1:0] reg_a_out, reg_b_out;
    wire [NB_OP-1:0]   reg_op_out;
    wire               alu_enable;
    wire [NB_DATA-1:0] alu_result;
    wire               alu_overflow, alu_carry;

    // Transmisión
    wire [NB_DATA-1:0] w_data;                     // result_sender -> interface_tx
    wire               wr;                         // result_sender -> interface_tx
    wire               tx_full;                    // interface_tx -> result_sender
    wire [NB_DATA-1:0] tx_d_in;                    // interface_tx -> uart_tx
    wire               tx_start;                   // interface_tx -> uart_tx
    wire               tx_done;                    // uart_tx -> interface_tx

    // -------------------------------------------------------------------------
    // SINCRONIZADOR DE rx (2 flip-flops)
    // rx viene de la PC, que no conoce nuestro clock, así que puede cambiar
    // justo en un flanco y dejar al flip-flop que lo lee "indeciso"
    // (metaestabilidad). Con 2 flip-flops en fila, el primero tiene un ciclo
    // entero para estabilizarse antes de que el segundo lo lea. Cuesta 2 ciclos
    // de demora, despreciables frente a los 5200 ciclos que dura cada bit.
    // En reset arrancan en 1 (línea en reposo) para no simular un start bit.
    // ASYNC_REG le avisa a Vivado que son un sincronizador y los ubica juntos.
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg rx_meta;
    (* ASYNC_REG = "TRUE" *) reg rx_sync;

    always @(posedge clk) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;      // Puede quedar metaestable
            rx_sync <= rx_meta; // Ya estable, alineado con clk
        end
    end

    // -------------------------------------------------------------------------
    // BAUD RATE GENERATOR (compartido por Rx y Tx)
    // -------------------------------------------------------------------------
    baud_rate_generator #(
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE),
        .CLK_FREQ(CLK_FREQ)
    ) u_baud_rate_generator (
        .clk(clk),
        .reset(reset),
        .s_tick(s_tick)
    );

    // -------------------------------------------------------------------------
    // CAMINO DE ENTRADA: PC -> registros
    // -------------------------------------------------------------------------
    uart_rx #(
        .D_BIT(NB_DATA),
        .OVERSAMPLE_TICK(OVERSAMPLE)
    ) u_uart_rx (
        .clk(clk),
        .reset(reset),
        .in_rx(rx_sync),
        .i_tick(s_tick),
        .o_data(rx_data),
        .o_done_tick(rx_done_tick)
    );

    interface_rx #(
        .N_buffer(NB_DATA)
    ) u_interface_rx (
        .clk(clk),
        .reset(reset),
        .i_rx_data(rx_data),
        .i_rx_done_tick(rx_done_tick),
        .i_rd(rd),
        .o_r_data(r_data),
        .o_rx_empty(rx_empty)
    );

    // Pulsa o_enb_reg_* en el mismo ciclo en que r_data tiene el valor, así que
    // los reg_bank lo toman directo del bus de interface_rx.
    loader_uart #(
        .N_BITS(NB_DATA)
    ) u_loader_uart (
        .clk(clk),
        .reset(reset),
        .i_r_data(r_data),
        .i_rx_empty(rx_empty),
        .o_rd(rd),
        .o_enb_reg_A(enb_reg_A),
        .o_enb_reg_B(enb_reg_B),
        .o_enb_reg_OP(enb_reg_OP)
    );

    // -------------------------------------------------------------------------
    // REGISTROS A, B y Op (reg_bank.v del TP1, sin cambios)
    // -------------------------------------------------------------------------
    reg_bank #(
        .WIDTH(NB_DATA)
    ) u_reg_bank_A (
        .clk(clk),
        .reset(reset),
        .i_data(r_data),
        .i_load_reg(enb_reg_A),
        .o_data(reg_a_out)
    );

    reg_bank #(
        .WIDTH(NB_DATA)
    ) u_reg_bank_B (
        .clk(clk),
        .reset(reset),
        .i_data(r_data),
        .i_load_reg(enb_reg_B),
        .o_data(reg_b_out)
    );

    // El opcode es de 6 bits: se toman los bits menos significativos del byte
    reg_bank #(
        .WIDTH(NB_OP)
    ) u_reg_bank_OP (
        .clk(clk),
        .reset(reset),
        .i_data(r_data[NB_OP-1:0]),
        .i_load_reg(enb_reg_OP),
        .o_data(reg_op_out)
    );

    // -------------------------------------------------------------------------
    // HABILITACION STICKY DE LA ALU
    // Mismo patrón que load_ctrl.v del TP1: cada flag se levanta la primera vez
    // que se carga su registro y solo baja con reset. La ALU queda habilitada
    // cuando A, B y Op se cargaron alguna vez (en cualquier orden). Como por
    // ahora la única fuente es la UART, los flags se alimentan solo de
    // loader_uart; cuando se agregue el TP1, acá entran también los de load_ctrl.
    // -------------------------------------------------------------------------
    reg loaded_a, loaded_b, loaded_op;

    always @(posedge clk) begin
        if (reset) begin
            loaded_a  <= 1'b0;
            loaded_b  <= 1'b0;
            loaded_op <= 1'b0;
        end else begin
            if (enb_reg_A)  loaded_a  <= 1'b1;
            if (enb_reg_B)  loaded_b  <= 1'b1;
            if (enb_reg_OP) loaded_op <= 1'b1;
        end
    end

    assign alu_enable = loaded_a & loaded_b & loaded_op;

    // -------------------------------------------------------------------------
    // ALU (ALU.v del TP1, sin cambios). Combinacional: con alu_enable = 0
    // la salida vale 0.
    // -------------------------------------------------------------------------
    ALU #(
        .NB_DATA(NB_DATA),
        .NB_OP(NB_OP)
    ) u_ALU (
        .i_a(reg_a_out),
        .i_b(reg_b_out),
        .i_op(reg_op_out),
        .i_enable(alu_enable),
        .o_result(alu_result),
        .o_overflow(alu_overflow),
        .o_carry(alu_carry)
    );

    // -------------------------------------------------------------------------
    // CAMINO DE SALIDA: ALU -> PC
    // -------------------------------------------------------------------------
    result_sender #(
        .D_BIT(NB_DATA)
    ) u_result_sender (
        .clk(clk),
        .reset(reset),
        .i_result(alu_result),
        .i_overflow(alu_overflow),
        .i_carry(alu_carry),
        .i_enable_alu(alu_enable),
        .i_tx_full(tx_full),
        .o_w_data(w_data),
        .o_wr(wr)
    );

    interface_tx #(
        .D_BIT(NB_DATA)
    ) u_interface_tx (
        .clk(clk),
        .reset(reset),
        .i_w_data(w_data),
        .i_wr(wr),
        .o_tx_full(tx_full),
        .i_tx_done(tx_done),
        .o_d_in(tx_d_in),
        .o_tx_start(tx_start)
    );

    uart_tx #(
        .D_BIT(NB_DATA),
        .OVERSAMPLE_TICK(OVERSAMPLE)
    ) u_uart_tx (
        .clk(clk),
        .reset(reset),
        .d_in(tx_d_in),
        .tx_start(tx_start),
        .i_tick(s_tick),
        .tx(tx),
        .tx_done(tx_done)
    );

    // -------------------------------------------------------------------------
    // LEDs: mismo formato que el TP1
    // -------------------------------------------------------------------------
    assign led = {alu_carry, alu_overflow, 1'b0, alu_result};

endmodule
