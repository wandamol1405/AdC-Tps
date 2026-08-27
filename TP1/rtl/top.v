module top #(
    parameter NB_DATA = 8, // Number of bits for the data inputs
    parameter NB_OP = 6, // Number of bits for the operation code
    parameter NB_SW = 8,
    parameter NB_INPUTS = 3
) (
    input wire [NB_SW-1:0] sw, // switches donde ingresan los datos y opcode 
    input wire btnL, //btn de control A
    input wire btnC, // btn de control B
    input wire btnR, // btn de control Op
    output wire [NB_DATA-1:0] led 
);

/*
Instancia de la ALU en el top, ver los registros de A, B y OP
ALU #(
    .NB_DATA(NB_DATA),
    .NB_OP(NB_OP)  // Number of bits for the operation code
) (
    .i_a(),
    .i_b(),
    .i_op(),
    o_result(o_leds)
);
*/
endmodule