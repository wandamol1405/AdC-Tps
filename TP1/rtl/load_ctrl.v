// Controla la carga de A, B y Op desde los switches, cada uno disparado por
// su propio botón (con antirrebote), y habilita la salida de la ALU una vez
// que los tres fueron cargados al menos una vez desde el último reset.
//
// Se pueden cargar en cualquier orden, con tres flags "sticky" (loaded_a/b/op)
// que se levantan con su tick y solo se bajan con reset. Una vez que los tres
// están levantados, o_enable_alu queda habilitado para siempre (hasta el
// próximo reset): en cualquier momento se puede volver a tocar cualquiera de
// los tres botones para actualizar solo ese registro —reusando lo que ya haya
// en los otros dos— sin perder la habilitación.
module load_ctrl #(
    parameter N_DEBOUNCE = 20 // Number of bits for the debounce counter
) (
    input wire i_a,
    input wire i_b,
    input wire i_OP,
    input wire clk,
    input wire reset,
    output reg o_enb_reg_A,
    output reg o_enb_reg_B,
    output reg o_enb_reg_OP,
    output reg o_enable_alu
);

// Pulsos de 1 ciclo, ya libres de rebotes, que indica cada antirrebote
// cuando confirma una pulsación real de su botón correspondiente.
wire tick_a, tick_b, tick_op;

// Un antirrebote por cada botón de carga: cada uno filtra los rebotes
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

// Flags "sticky": se levantan la primera vez que se confirma el botón
// correspondiente y solo se bajan con reset. No hace falta recordar "en qué
// paso de la secuencia" estamos, solo si cada dato ya fue cargado alguna vez.
reg loaded_a, loaded_b, loaded_op;

always @(posedge clk) begin
    if (reset) begin
        loaded_a  <= 1'b0;
        loaded_b  <= 1'b0;
        loaded_op <= 1'b0;
    end else begin
        if (tick_a)  loaded_a  <= 1'b1;
        if (tick_b)  loaded_b  <= 1'b1;
        if (tick_op) loaded_op <= 1'b1;
    end
end

// Lógica combinacional de salida: los pulsos de carga van directo a los
// reg_bank en cualquier momento (se puede recargar A, B u Op individualmente,
// antes o después de habilitar la ALU, sin afectar a los otros dos), y el
// enable de la ALU refleja si los tres ya fueron cargados alguna vez.
always @(*) begin
    o_enb_reg_A  = tick_a;
    o_enb_reg_B  = tick_b;
    o_enb_reg_OP = tick_op;
    o_enable_alu = loaded_a & loaded_b & loaded_op;
end

endmodule
