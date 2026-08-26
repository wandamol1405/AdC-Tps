module top #(
    parameter NB_DATA = 8, // Number of bits for the data inputs
    parameter NB_OP = 6, // Number of bits for the operation code
    parameter NB_SW = 16,
    parameter NB_INPUTS = 3,
) (
    input wire [NB_SW-1:0] i_sw, // switches donde ingresan los datos y opcode 
    input wire [NB_INPUTS-1:0] i_enb, // habilita 1, 2 y 3
    output wire [NB_DATA-1:0] o_leds 
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