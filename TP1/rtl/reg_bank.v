// Registro genérico de carga paralela con reset y enable síncronos.
// Se instancia tres veces en top.v (para A, B y Op), cada vez con un ancho
// (WIDTH) distinto, en vez de escribir tres registros separados a mano.
module reg_bank #(
    parameter WIDTH = 8 // Number of bits for the register
) (
    input wire clk,
    input wire reset,             // reset síncrono: limpia el registro a 0
    input wire [WIDTH-1:0] i_data, // dato a cargar (viene de los switches)
    input wire i_load_reg,         // pulso de 1 ciclo: "cargar i_data ahora"
    output reg [WIDTH-1:0] o_data  // valor actualmente almacenado
);

    // El registro solo cambia en el flanco de clock, y solo si reset o
    // i_load_reg están activos; fuera de eso mantiene su valor (retención
    // implícita: no hay rama "else" final, por eso o_data no cambia).
    always @(posedge clk) begin
        if (reset) begin
            o_data <= {WIDTH{1'b0}};
        end else if (i_load_reg) begin
            o_data <= i_data;
        end
    end

endmodule
