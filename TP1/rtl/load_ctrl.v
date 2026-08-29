module load_ctrl #(
    parameter N_DEBOUNCE = 20, // Number of bits for the debounce counter
) (
    input wire i_a,
    input wire i_b,
    input wire i_OP,
    input wire clk,
    output wire o_enable
);

// me hace falta un cable que lleve la señal de los antirrebote hacia las entradas de

wire tick_a, tick_b, tick_op;

//Tengo que instanciar los antirrebotes para cada boton de control, y luego conectar
//la salida de cada antirrebote a la entrada de la maquina de estados.
//esto todo el tiempo esta viendo si hay un flanco en cada boton de control, y si lo hay, 
//lo manda a la maquina de estados para que cambie de estado.
debounce_edge #(.N(N_DEBAUNCE)) db_a (
    .clk(clk),          // Clock input
    .reset(reset),      // Reset input
    .sw_btn(i_a),       // entrada del boton de control A (que puede generar un rebote)
    .btn_tick(tick_a)   // salida del antirrebote, que tiene el que va 

    // Lo que yo entiendo es que agarra el pin del clk del antirrebote y lo conecta al
    // clk de la placa que entiendo que seria el top.
)
debounce_edge #(.N(N_DEBOUNCE)) db_b (
    .clk(clk),
    .reset(reset),
    .sw_btn(i_b),
    .btn_tick(tick_b)
);

debounce_edge #(.N(N_DEBOUNCE)) db_op (
    .clk(clk),
    .reset(reset),
    .sw_btn(i_OP),
    .btn_tick(tick_op)
);


//voy con los estados
localparam [1:0] 
    WAIT_A = 2'b00,     // estado de espera para el boton A
    WAIT_B = 2'b01,     // estado de espera para el boton B
    WAIT_OP = 2'b10,    // estado de espera para el boton OP
    ENABLE = 2'b11;     // estado de habilitación

//Necesito un registro para guardar el estado en el que estoy y el que sigue 
reg [1:0] state_reg, state_next;

//como seria lo de los flancos
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state_reg <= WAIT_A; // si hay reset, vuelvo al estado de espera para A
    end else begin
        state_reg <= state_next; // si no hay reset, paso al siguiente estado
    end
end


//ahora voy con la logica de como cambian los estados
always @(*) begin
    state_next = state_reg; // por default, el siguiente estado es el mismo que el actual
    //si todo sale bien, cuando llegue al enable, me quedo ahi hasta que haya un reset, y vuelvo al estado de espera para A

    //veo en que estado estoy y que hago
    case (state_reg)                        // dependiendo del estado en el que estoy, hago algo distinto       
        WAIT_A: begin                       // si estoy en el estado de espera para A, espero a que haya un flanco en A
            if (tick_a) begin               // si hay un flanco en A, paso al estado de espera para B
                state_next = WAIT_B;        // si no hay flanco en A, me quedo en el estado de espera para A
            end
        end
        WAIT_B: begin
            if (tick_b) begin // si hay un flanco en B, paso al estado de espera para OP
                state_next = WAIT_OP;
            end
        end
        WAIT_OP: begin
            if (tick_op) begin // si hay un flanco en OP, paso al estado de habilitación
                state_next = ENABLE;
            end
        end
        ENABLE: begin
            // en el estado de habilitación, no hago nada, me quedo en este estado hasta que haya un reset
        end
    endcase

end

endmodule