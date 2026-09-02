// Máquina de estados que orquesta la carga secuencial de A, B y Op desde los
// switches, cada uno disparado por su propio botón (con antirrebote), y
// habilita la salida de la ALU recién cuando los tres ya fueron cargados.
// También soporta un botón de "limpieza" (i_clean) que reinicia la secuencia
// sin borrar lo ya cargado en los reg_bank, útil para repetir una operación
// reusando A/B/Op sin tener que resetear todo el diseño.
module load_ctrl #(
    parameter N_DEBOUNCE = 20 // Number of bits for the debounce counter
) (
    input wire i_a,
    input wire i_b,
    input wire i_OP,
    input wire i_clean, // vuelve a WAIT_A y apaga la ALU sin tocar lo cargado en los registros
    input wire clk,
    input wire reset,
    output reg o_enb_reg_A,
    output reg o_enb_reg_B,
    output reg o_enb_reg_OP,
    output reg o_enable_alu
);

// Pulsos de 1 ciclo, ya libres de rebotes, que indica cada antirrebote
// cuando confirma una pulsación real de su botón correspondiente.
wire tick_a, tick_b, tick_op, tick_clean;

// Un antirrebote por cada botón de control: cada uno filtra los rebotes
// mecánicos de su entrada y entrega un único pulso (db_tick) por pulsación.
debounce #(.N(N_DEBOUNCE)) db_a (
    .clk(clk),          // Clock input
    .reset(reset),      // Reset input
    .sw(i_a),           // entrada del boton de control A (que puede generar un rebote)
    .db_tick(tick_a)    // pulso de 1 ciclo cuando el flanco ya fue confirmado
    // db_level sin conectar: acá solo necesitamos el pulso, no el nivel filtrado
);

debounce #(.N(N_DEBOUNCE)) db_b (
    .clk(clk),
    .reset(reset),
    .sw(i_b),
    .db_tick(tick_b)
);

debounce #(.N(N_DEBOUNCE)) db_op (
    .clk(clk),
    .reset(reset),
    .sw(i_OP),
    .db_tick(tick_op)
);

debounce #(.N(N_DEBOUNCE)) db_clean (
    .clk(clk),
    .reset(reset),
    .sw(i_clean),
    .db_tick(tick_clean)
);


// Estados de la FSM: se espera un botón por vez, en orden fijo A -> B -> Op,
// y una vez en ENABLE se permanece ahí (mostrando resultado) hasta reset o clean.
localparam [1:0]
    WAIT_A = 2'b00,     // estado de espera para el boton A
    WAIT_B = 2'b01,     // estado de espera para el boton B
    WAIT_OP = 2'b10,    // estado de espera para el boton OP
    ENABLE = 2'b11;     // estado de habilitación

// Registro de estado actual y su valor combinacional "próximo estado"
reg [1:0] state_reg, state_next;

// Memoria de estado con reset y "clean" síncronos: ambos único que tocan
// state_reg directamente (todo lo demás se decide en el bloque combinacional).
always @(posedge clk) begin
    if (reset) begin
        state_reg <= WAIT_A; // si hay reset, vuelvo al estado de espera para A
    end else if (tick_clean) begin
        state_reg <= WAIT_A; // "clean": vuelvo a WAIT_A (y por lo tanto se apaga o_enable_alu)
                              // sin resetear los reg_bank, que conservan A/B/OP
    end else begin
        state_reg <= state_next; // si no hay reset, paso al siguiente estado
    end
end


// Lógica combinacional de transición y de salida. Todas las salidas arrancan
// en 0 cada evaluación (evita inferir latches) y solo la rama del estado
// activo las levanta — así, con solo cambiar de estado, las demás quedan
// automáticamente deshabilitadas sin código extra por estado.
always @(*) begin
    state_next = state_reg; // por default, el siguiente estado es el mismo que el actual
    //si todo sale bien, cuando llegue al enable, me quedo ahi hasta que haya un reset, y vuelvo al estado de espera para A

    // por default, no habilito ninguna salida
    o_enb_reg_A  = 1'b0;
    o_enb_reg_B  = 1'b0;
    o_enb_reg_OP = 1'b0;
    o_enable_alu = 1'b0;

    //veo en que estado estoy y que hago
    case (state_reg)                        // dependiendo del estado en el que estoy, hago algo distinto
        WAIT_A: begin                       // si estoy en el estado de espera para A, espero a que haya un flanco en A
            if (tick_a) begin               // si hay un flanco en A, paso al estado de espera para B
                state_next = WAIT_B;        // si no hay flanco en A, me quedo en el estado de espera para A
                o_enb_reg_A = 1'b1;         // pulso de 1 ciclo: reg_bank de A lo usa como su i_load_reg
            end
        end
        WAIT_B: begin
            if (tick_b) begin // si hay un flanco en B, paso al estado de espera para OP
                state_next = WAIT_OP;
                o_enb_reg_B = 1'b1;
            end
        end
        WAIT_OP: begin
            if (tick_op) begin // si hay un flanco en OP, paso al estado de habilitación
                state_next = ENABLE;
                o_enb_reg_OP = 1'b1;
            end
        end
        ENABLE: begin
            // en el estado de habilitación, no hago nada, me quedo en este estado hasta que haya un reset (o un clean)
            o_enable_alu = 1'b1; // habilito la salida de la ALU
        end
    endcase

end

endmodule
