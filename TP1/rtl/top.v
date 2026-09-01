// Módulo de nivel superior para la Basys3: conecta switches y botones
// físicos con la ALU, a través de los bancos de registros (A, B, Op) y la
// máquina de estados que controla cuándo cargar cada uno.
//
// Flujo: sw + btnL/btnC/btnR/btnU -> load_ctrl (antirrebote + FSM) ->
// enables de carga -> reg_bank (A/B/Op) -> ALU -> led.
module top #(
    parameter NB_DATA = 8, // Number of bits for the data inputs
    parameter NB_OP = 6, // Number of bits for the operation code
    parameter NB_SW = 8,
    parameter NB_INPUTS = 3,
    parameter N_DEBOUNCE = 20,
    parameter NB_LED = NB_DATA + 3 // resultado + 1 led apagado (separador) + overflow + carry
) (
    input wire clk,
    input wire reset,
    input wire [NB_SW-1:0] sw, // switches donde ingresan los datos y opcode
    input wire btnL, //btn de control A
    input wire btnC, // btn de control B
    input wire btnR, // btn de control Op
    input wire btnU, // btn de limpieza: vuelve a WAIT_A sin borrar los registros
    output wire [NB_LED-1:0] led
);

wire alu_enable;                       // en 1 recién cuando A, B y Op ya fueron cargados
wire [NB_DATA-1:0] reg_a_out, reg_b_out; // salidas registradas de los bancos A y B
wire [NB_DATA-1:0] alu_result;
wire alu_overflow, alu_carry;
wire [NB_OP-1:0] reg_op_out;           // salida registrada del banco de Op
wire enb_reg_A, enb_reg_B, enb_reg_OP; // pulsos de carga, uno por registro

// Antirrebote de los 4 botones + FSM de secuenciación de la carga
// (WAIT_A -> WAIT_B -> WAIT_OP -> ENABLE). Ver load_ctrl.v para el detalle.
load_ctrl #(
    .N_DEBOUNCE(N_DEBOUNCE) // Number of bits for the debounce counter
) u_load_ctrl (
    .i_a(btnL),
    .i_b(btnC),
    .i_OP(btnR),
    .i_clean(btnU),
    .clk(clk),
    .reset(reset),
    .o_enb_reg_A(enb_reg_A),
    .o_enb_reg_B(enb_reg_B),
    .o_enb_reg_OP(enb_reg_OP),
    .o_enable_alu(alu_enable)
);

// Los tres registros comparten el mismo bus de switches como entrada de
// datos; cada uno solo lo captura cuando su propio enable (enb_reg_*) pulsa.
reg_bank #(
    .WIDTH(NB_DATA)
) u_reg_bank_A (
    .clk(clk),
    .reset(reset),
    .i_data(sw),
    .i_load_reg(enb_reg_A),
    .o_data(reg_a_out)
);

reg_bank #(
    .WIDTH(NB_DATA)
) u_reg_bank_B (
    .clk(clk),
    .reset(reset),
    .i_data(sw),
    .i_load_reg(enb_reg_B),
    .o_data(reg_b_out)
);

// WIDTH=NB_OP (6) conectado a sw de NB_SW (8) bits: Verilog toma los bits
// menos significativos de sw, es decir, el opcode se ingresa por SW5-SW0.
reg_bank #(
    .WIDTH(NB_OP)
) u_reg_bank_OP (
    .clk(clk),
    .reset(reset),
    .i_data(sw),
    .i_load_reg(enb_reg_OP),
    .o_data(reg_op_out)
);

// ALU puramente combinacional: mientras alu_enable esté en 0 (todavía
// cargando A/B/Op), fuerza su salida a 0.
ALU #(
    .NB_DATA(NB_DATA), // Number of bits for the data inputs
    .NB_OP(NB_OP)  // Number of bits for the operation code
) u_ALU (
    .i_a(reg_a_out), // Aca va la salida de la instancia reg_bank para A
    .i_b(reg_b_out), // Aca va la salida de la instancia reg_bank para B
    .i_op(reg_op_out), // Aca va la salida de la instancia reg_bank para OP
    .i_enable(alu_enable),
    .o_result(alu_result),
    .o_overflow(alu_overflow),
    .o_carry(alu_carry)
);

// led[NB_DATA-1:0] = resultado, led[NB_DATA] apagado (separador),
// led[NB_DATA+1] = overflow, led[NB_DATA+2] = carry
assign led = {alu_carry, alu_overflow, 1'b0, alu_result};

endmodule
