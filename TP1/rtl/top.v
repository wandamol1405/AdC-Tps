module top #(
    parameter NB_DATA = 8, // Number of bits for the data inputs
    parameter NB_OP = 6, // Number of bits for the operation code
    parameter NB_SW = 8,
    parameter NB_INPUTS = 3,
    parameter N_DEBOUNCE = 20
) (
    input wire [NB_SW-1:0] sw, // switches donde ingresan los datos y opcode 
    input wire btnL, //btn de control A
    input wire btnC, // btn de control B
    input wire btnR, // btn de control Op
    output wire [NB_DATA-1:0] led 
);

wire alu_enable;

load_ctrl #(
    .N_DEBOUNCE(20) // Number of bits for the debounce counter
) (
    .i_a(btnL),
    .i_b(btnC),
    .i_OP(btnR),
    .clk(clk),
    .reset(reset),
    .o_enable(alu_enable)
);

ALU #(
    .NB_DATA(NB_DATA), // Number of bits for the data inputs
    .NB_OP(NB_OP)  // Number of bits for the operation code
) u_ALU (
    .i_a(), // Aca va la salida de la instancia reg_bank para A
    .i_b(), // Aca va la salida de la instancia reg_bank para B
    .i_op(), // Aca va la salida de la instancia reg_bank para OP
    .i_enable(alu_enable),
    .o_result(led)
);
endmodule