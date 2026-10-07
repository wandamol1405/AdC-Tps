// ALU combinacional parametrizable. Ejecuta la operación indicada por i_op
// sobre i_a/i_b y expone el resultado más las banderas de overflow y carry
// (calculadas únicamente para ADD, que es la única operación que las define
// en este TP). Cuando i_enable está en 0, la salida se fuerza a 0 — así el
// datapath puede mantener la ALU "apagada" mientras se están cargando A/B/Op.
module ALU #(
    parameter NB_DATA = 8, // Number of bits for the data inputs
    parameter NB_OP = 6  // Number of bits for the operation code
) (
    input wire signed [NB_DATA-1:0] i_a,
    input wire signed [NB_DATA-1:0] i_b,
    input wire [NB_OP-1:0] i_op,
    input wire i_enable,
    output reg [NB_DATA-1:0] o_result,
    output reg o_overflow, // overflow con signo (solo valido para ADD, con saturacion)
    output reg o_carry     // carry de salida sin signo (solo valido para ADD)
);

// Códigos de operación (deben coincidir con los del enunciado del TP)
localparam [NB_OP-1:0] ADD = {6'b100000};
localparam [NB_OP-1:0] SUB = {6'b100010};
localparam [NB_OP-1:0] AND = {6'b100100};
localparam [NB_OP-1:0] OR = {6'b100101};
localparam [NB_OP-1:0] XOR = {6'b100110};
localparam [NB_OP-1:0] SRA = {6'b000011};
localparam [NB_OP-1:0] SRL = {6'b000010};
localparam [NB_OP-1:0] NOR = {6'b100111};

// Límites del rango representable en complemento a 2 de NB_DATA bits,
// usados para saturar el resultado de ADD cuando hay overflow con signo.
localparam [NB_DATA-1:0] MAX_VALUE = {1'b0, {(NB_DATA-1){1'b1}}}; // maximo positivo representable
localparam [NB_DATA-1:0] MIN_VALUE = {1'b1, {(NB_DATA-1){1'b0}}}; // minimo negativo representable

reg [NB_DATA:0]   add_full;    // suma sin signo extendida (incluye carry)
reg [NB_DATA-1:0] add_result;  // suma truncada a NB_DATA bits (resultado natural, sin saturar)
reg sum_overflow;

always @(*) begin

    // Valores por defecto: solo ADD los sobreescribe; en el resto de las
    // operaciones (y con i_enable=0) las banderas quedan en 0.

    o_carry = 1'b0;
    o_overflow = 1'b0;
    if (i_enable) begin
    case (i_op)
        ADD: begin

            // Se suman los patrones de bits como si fueran sin signo, en un
            // bus de NB_DATA+1 bits: el bit extra (add_full[NB_DATA]) es
            // exactamente el carry de salida sin signo.

            add_full = {1'b0, i_a} + {1'b0, i_b}; // suma sin signo de los patrones de bits
            add_result = add_full[NB_DATA-1:0];
            o_carry = add_full[NB_DATA]; // carry sin signo

            // overflow con signo: mismo signo en los operandos y resultado con signo distinto

            sum_overflow = (i_a[NB_DATA-1] == i_b[NB_DATA-1]) && (add_result[NB_DATA-1] != i_a[NB_DATA-1]);
            o_overflow = sum_overflow;
            if (sum_overflow)
                o_result = i_a[NB_DATA-1] ? MIN_VALUE : MAX_VALUE; // saturacion
            else
                o_result = add_result;
        end
        SUB: o_result = i_a - i_b; // minuendo siempre a, sustraendo siempre b
        AND: o_result = i_a & i_b;
        OR: o_result = i_a | i_b;
        XOR: o_result = i_a ^ i_b;

        // >>> ya maneja el desplazamiento con signo (replica el bit de signo)
        // siempre que el operando de la izquierda esté declarado/casteado signed.
        SRA: o_result = $signed(i_a) >>> i_b; // desplaza siempre a, desplaza b veces
        SRL: o_result = i_a >> i_b;
        NOR: o_result = ~(i_a | i_b);

        // default evita que se infiera un latch: cubre cualquier opcode no
        // contemplado (los 6 bits de i_op permiten 64 combinaciones, solo 8 son válidas).
        default: o_result = {NB_DATA{1'b0}};
    endcase
    end else begin
        o_result = {NB_DATA{1'b0}};
    end
end

endmodule
