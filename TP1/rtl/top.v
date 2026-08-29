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
reg [NB_DATA-1:0] reg_a_out, reg_b_out, reg_op_out;
wire enb_reg_A, enb_reg_B, enb_reg_OP;

load_ctrl #(
    .N_DEBOUNCE(20) // Number of bits for the debounce counter
) (
    .i_a(btnL),
    .i_b(btnC),
    .i_OP(btnR),
    .clk(clk),
    .reset(reset),
    .o_enb_reg_A(enb_reg_A),
    .o_enb_reg_B(enb_reg_B),
    .o_enb_reg_OP(enb_reg_OP),
    .o_enable_alu(alu_enable)
);

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

reg_bank #(
    .WIDTH(NB_OP)
) u_reg_bank_OP (
    .clk(clk),
    .reset(reset),
    .i_data(sw),
    .i_load_reg(enb_reg_OP),
    .o_data(reg_op_out)
);

ALU #(
    .NB_DATA(NB_DATA), // Number of bits for the data inputs
    .NB_OP(NB_OP)  // Number of bits for the operation code
) u_ALU (
    .i_a(reg_a_out), // Aca va la salida de la instancia reg_bank para A
    .i_b(reg_b_out), // Aca va la salida de la instancia reg_bank para B
    .i_op(reg_op_out), // Aca va la salida de la instancia reg_bank para OP
    .i_enable(alu_enable),
    .o_result(led)
);
endmodule