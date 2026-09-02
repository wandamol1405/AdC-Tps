`timescale 1ns / 1ps

// Testbench autochequeable de la ALU: aplica un estímulo por cada operación
// (incluyendo casos borde de overflow/carry en ADD, i_enable en 0 y un
// opcode inválido) y compara automáticamente la salida contra el valor
// esperado, sin intervención manual — solo hay que leer el resumen final.
// Además de los casos dirigidos, corre un bloque de entradas aleatorias
// (a, b, op e i_enable con $random) autochequeadas contra un modelo de
// referencia que reproduce la especificación de la ALU de forma independiente
// del RTL (ver task ref_model), tal como pide el enunciado del TP.
module tb_ALU;

    localparam NB_DATA = 8;
    localparam NB_OP   = 6;

    // Opcodes (deben coincidir con los definidos en ALU.v)
    localparam [NB_OP-1:0] ADD = 6'b100000;
    localparam [NB_OP-1:0] SUB = 6'b100010;
    localparam [NB_OP-1:0] AND = 6'b100100;
    localparam [NB_OP-1:0] OR  = 6'b100101;
    localparam [NB_OP-1:0] XOR = 6'b100110;
    localparam [NB_OP-1:0] SRA = 6'b000011;
    localparam [NB_OP-1:0] SRL = 6'b000010;
    localparam [NB_OP-1:0] NOR = 6'b100111;
    localparam [NB_OP-1:0] INVALID_OP = 6'b111111;

    localparam NUM_RANDOM = 300; // cantidad de estimulos aleatorios a correr

    reg  signed [NB_DATA-1:0] i_a;
    reg  signed [NB_DATA-1:0] i_b;
    reg  [NB_OP-1:0]          i_op;
    reg                       i_enable;
    wire [NB_DATA-1:0]        o_result;
    wire                      o_overflow;
    wire                      o_carry;

    integer errores; // cantidad de check_op que fallaron
    integer casos;   // cantidad total de check_op ejecutados

    integer rnd_i;
    reg [NB_OP-1:0] rnd_op;
    reg [NB_DATA-1:0] rnd_exp;
    reg rnd_exp_ov, rnd_exp_ca;

    ALU #(
        .NB_DATA(NB_DATA),
        .NB_OP(NB_OP)
    ) dut (
        .i_a(i_a),
        .i_b(i_b),
        .i_op(i_op),
        .i_enable(i_enable),
        .o_result(o_result),
        .o_overflow(o_overflow),
        .o_carry(o_carry)
    );

    // Tarea que aplica un estimulo, espera y compara contra los valores esperados.
    // Al ser combinacional el DUT, alcanza con un pequeño delay (#10) para que
    // se propague la lógica antes de muestrear las salidas; no hace falta clock.
    task check_op;
        input [127:0] nombre_op; // nombre para mostrar por consola
        input signed [NB_DATA-1:0] a;
        input signed [NB_DATA-1:0] b;
        input [NB_OP-1:0] op;
        input en;
        input [NB_DATA-1:0] esperado;
        input esperado_overflow;
        input esperado_carry;
        begin
            i_a = a;
            i_b = b;
            i_op = op;
            i_enable = en;
            #10;
            casos = casos + 1;
            // !== (comparación estricta) en vez de != para detectar también
            // discrepancias con bits en X/Z, no solo diferencias de valor.
            if (o_result !== esperado || o_overflow !== esperado_overflow || o_carry !== esperado_carry) begin
                errores = errores + 1;
                $display("[FALLO] %-8s a=%0d b=%0d en=%0d op=%b -> o_result=%0d (0x%0h) ov=%b ca=%b | esperado=%0d (0x%0h) ov=%b ca=%b",
                    nombre_op, a, b, en, op, o_result, o_result, o_overflow, o_carry,
                    esperado, esperado, esperado_overflow, esperado_carry);
            end else begin
                $display("[OK]    %-8s a=%0d b=%0d en=%0d op=%b -> o_result=%0d (0x%0h) ov=%b ca=%b",
                    nombre_op, a, b, en, op, o_result, o_result, o_overflow, o_carry);
            end
        end
    endtask

    // Modelo de referencia: recalcula la especificacion de la ALU (misma
    // logica de overflow/carry/saturacion en ADD que el enunciado define)
    // para poder autochequear entradas generadas con $random, sin depender
    // de valores esperados escritos a mano caso por caso.
    task ref_model;
        input signed [NB_DATA-1:0] a;
        input signed [NB_DATA-1:0] b;
        input [NB_OP-1:0] op;
        input en;
        output [NB_DATA-1:0] exp_result;
        output exp_overflow;
        output exp_carry;
        reg [NB_DATA:0]   full;
        reg [NB_DATA-1:0] wrapped;
        reg               ovf;
        begin
            exp_overflow = 1'b0;
            exp_carry    = 1'b0;
            if (!en) begin
                exp_result = {NB_DATA{1'b0}};
            end else begin
                case (op)
                    ADD: begin
                        full = {1'b0, a} + {1'b0, b};
                        wrapped = full[NB_DATA-1:0];
                        exp_carry = full[NB_DATA];
                        ovf = (a[NB_DATA-1] == b[NB_DATA-1]) && (wrapped[NB_DATA-1] != a[NB_DATA-1]);
                        exp_overflow = ovf;
                        exp_result = ovf
                            ? (a[NB_DATA-1] ? {1'b1, {(NB_DATA-1){1'b0}}} : {1'b0, {(NB_DATA-1){1'b1}}})
                            : wrapped;
                    end
                    SUB: exp_result = a - b;
                    AND: exp_result = a & b;
                    OR:  exp_result = a | b;
                    XOR: exp_result = a ^ b;
                    SRA: exp_result = $signed(a) >>> b;
                    SRL: exp_result = a >> b;
                    NOR: exp_result = ~(a | b);
                    default: exp_result = {NB_DATA{1'b0}};
                endcase
            end
        end
    endtask

    initial begin
        errores = 0;
        casos = 0;

        $display("========================================================");
        $display(" Testbench ALU - NB_DATA=%0d NB_OP=%0d", NB_DATA, NB_OP);
        $display("========================================================");

        // ---------------- ADD (sin overflow) ----------------
        check_op("ADD", 8'd10, 8'd20, ADD, 1'b1, 8'd30, 1'b0, 1'b0);
        check_op("ADD", -8'sd5, 8'sd3, ADD, 1'b1, -8'sd2, 1'b0, 1'b0);

        // ---------------- ADD: carry sin overflow (signos opuestos, wrap unsigned) ----------------
        check_op("ADD-CA", -8'sd1, 8'sd1, ADD, 1'b1, 8'd0, 1'b0, 1'b1); // -1+1=0, carry unsigned=1

        // ---------------- ADD: overflow con saturacion (positivo) ----------------
        check_op("ADD-OVP", 8'sd127, 8'sd1, ADD, 1'b1, 8'sd127, 1'b1, 1'b0); // satura a MAX_VALUE
        check_op("ADD-OVP", 8'sd127, 8'sd127, ADD, 1'b1, 8'sd127, 1'b1, 1'b0); // satura a MAX_VALUE, sin carry

        // ---------------- ADD: overflow con saturacion (negativo) ----------------
        check_op("ADD-OVN", -8'sd128, -8'sd128, ADD, 1'b1, -8'sd128, 1'b1, 1'b1); // satura a MIN_VALUE, con carry

        // ---------------- SUB ----------------
        check_op("SUB", 8'd20, 8'd10, SUB, 1'b1, 8'd10, 1'b0, 1'b0);
        check_op("SUB", 8'd10, 8'd20, SUB, 1'b1, -8'sd10, 1'b0, 1'b0);
        check_op("SUB", -8'sd8, -8'sd8, SUB, 1'b1, 8'd0, 1'b0, 1'b0);

        // ---------------- AND ----------------
        check_op("AND", 8'b1100_1100, 8'b1010_1010, AND, 1'b1, 8'b1000_1000, 1'b0, 1'b0);
        check_op("AND", 8'hFF, 8'h00, AND, 1'b1, 8'h00, 1'b0, 1'b0);

        // ---------------- OR ----------------
        check_op("OR", 8'b1100_1100, 8'b1010_1010, OR, 1'b1, 8'b1110_1110, 1'b0, 1'b0);
        check_op("OR", 8'h00, 8'h00, OR, 1'b1, 8'h00, 1'b0, 1'b0);

        // ---------------- XOR ----------------
        check_op("XOR", 8'b1100_1100, 8'b1010_1010, XOR, 1'b1, 8'b0110_0110, 1'b0, 1'b0);
        check_op("XOR", 8'hFF, 8'hFF, XOR, 1'b1, 8'h00, 1'b0, 1'b0);

        // ---------------- SRA (shift aritmetico) ----------------
        check_op("SRA", 8'sb1000_0000, 8'd2, SRA, 1'b1, 8'sb1110_0000, 1'b0, 1'b0); // negativo, extiende signo
        check_op("SRA", 8'sd64, 8'd3, SRA, 1'b1, 8'sd8, 1'b0, 1'b0);

        // ---------------- SRL (shift logico) ----------------
        check_op("SRL", 8'b1000_0000, 8'd2, SRL, 1'b1, 8'b0010_0000, 1'b0, 1'b0); // no extiende signo
        check_op("SRL", 8'd64, 8'd3, SRL, 1'b1, 8'd8, 1'b0, 1'b0);

        // ---------------- NOR ----------------
        check_op("NOR", 8'b1100_1100, 8'b1010_1010, NOR, 1'b1, ~(8'b1100_1100 | 8'b1010_1010), 1'b0, 1'b0);
        check_op("NOR", 8'h00, 8'h00, NOR, 1'b1, 8'hFF, 1'b0, 1'b0);

        // ---------------- i_enable en 0 (debe forzar salida y banderas a 0) ----------------
        check_op("ADD-EN0", 8'd50, 8'd10, ADD, 1'b0, 8'd0, 1'b0, 1'b0);
        check_op("XOR-EN0", 8'hFF, 8'h0F, XOR, 1'b0, 8'd0, 1'b0, 1'b0);
        check_op("OVF-EN0", 8'sd127, 8'sd127, ADD, 1'b0, 8'd0, 1'b0, 1'b0); // aun con condicion de overflow, deshabilitada

        // ---------------- Opcode invalido (debe caer en default = 0) ----------------
        check_op("INVAL", 8'd5, 8'd5, INVALID_OP, 1'b1, 8'd0, 1'b0, 1'b0);

        // ---------------- Entradas aleatorias (autochequeadas contra ref_model) ----------------
        $display("--------------------------------------------------------");
        $display(" Bloque de %0d entradas aleatorias (a, b, op, i_enable con $random)", NUM_RANDOM);
        for (rnd_i = 0; rnd_i < NUM_RANDOM; rnd_i = rnd_i + 1) begin
            i_a = $random;
            i_b = $random;
            i_enable = ($random % 10 != 0); // ~90% habilitada, ~10% deshabilitada
            if ($random % 5 == 0) begin
                rnd_op = $random; // opcode totalmente aleatorio: puede caer en el default
            end else begin
                case ($unsigned($random) % 8) // opcode valido, con distribucion pareja entre las 8 operaciones
                    0: rnd_op = ADD;
                    1: rnd_op = SUB;
                    2: rnd_op = AND;
                    3: rnd_op = OR;
                    4: rnd_op = XOR;
                    5: rnd_op = SRA;
                    6: rnd_op = SRL;
                    default: rnd_op = NOR;
                endcase
            end
            i_op = rnd_op;
            #10;

            ref_model(i_a, i_b, i_op, i_enable, rnd_exp, rnd_exp_ov, rnd_exp_ca);
            casos = casos + 1;
            if (o_result !== rnd_exp || o_overflow !== rnd_exp_ov || o_carry !== rnd_exp_ca) begin
                errores = errores + 1;
                $display("[FALLO][RAND] a=%0d b=%0d en=%0d op=%b -> o_result=%0d ov=%b ca=%b | esperado=%0d ov=%b ca=%b",
                    i_a, i_b, i_enable, i_op, o_result, o_overflow, o_carry, rnd_exp, rnd_exp_ov, rnd_exp_ca);
            end
        end
        $display(" Bloque aleatorio: %0d casos ejecutados", NUM_RANDOM);

        $display("========================================================");
        if (errores == 0)
            $display(" RESULTADO: TODOS LOS CASOS PASARON (%0d/%0d)", casos, casos);
        else
            $display(" RESULTADO: %0d FALLOS DE %0d CASOS", errores, casos);
        $display("========================================================");

        $finish;
    end

endmodule
