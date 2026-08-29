module ALU #(
    parameter NB_DATA = 8, // Number of bits for the data inputs
    parameter NB_OP = 6  // Number of bits for the operation code
) (
    input wire signed [NB_DATA-1:0] i_a,
    input wire signed [NB_DATA-1:0] i_b,
    input wire [NB_OP-1:0] i_op,
    input wire i_enable,
    output reg [NB_DATA-1:0] o_result
);

localparam [NB_OP-1:0] ADD = {6'b100000};
localparam [NB_OP-1:0] SUB = {6'b100010};
localparam [NB_OP-1:0] AND = {6'b100100};
localparam [NB_OP-1:0] OR = {6'b100101};
localparam [NB_OP-1:0] XOR = {6'b100110};
localparam [NB_OP-1:0] SRA = {6'b000011};
localparam [NB_OP-1:0] SRL = {6'b000010};
localparam [NB_OP-1:0] NOR = {6'b100111};

always @(*) begin
    if (i_enable) begin
    case (i_op)
        ADD: o_result = i_a + i_b;
        SUB: o_result = i_a - i_b; // minuendo siempre a, sustraendo siempre b
        AND: o_result = i_a & i_b;
        OR: o_result = i_a | i_b;
        XOR: o_result = i_a ^ i_b;
        SRA: o_result = $signed(i_a) >>> i_b; // desplaza siempre a, desplaza b veces
        SRL: o_result = i_a >> i_b;
        NOR: o_result = ~(i_a | i_b);
        default: o_result = {NB_DATA{1'b0}};
    endcase
    end else begin
        o_result = {NB_DATA{1'b0}};
    end
end

endmodule