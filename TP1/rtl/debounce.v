module debounce (
    input  wire clk,       // Reloj principal
    input  wire reset,     // Reset sincrónico
    input  wire sw,        // Entrada del botón con rebotes
    output reg  db_level,  // Nivel lógico filtrado
    output reg  db_tick    // Pulso de 1 ciclo al presionar
);

    localparam [1:0] 
        zero  = 2'b00,
        wait1 = 2'b01,
        one   = 2'b10,
        wait0 = 2'b11;

    localparam N = 21;

    reg [1:0]   state_reg, state_next;
    reg [N-1:0] q_reg, q_next;

    // Memoria de estados y contador con RESET SINCRÓNICO
    always @(posedge clk) begin
        if (reset) begin
            state_reg <= zero;
            q_reg     <= {N{1'b0}};
        end else begin
            state_reg <= state_next;
            q_reg     <= q_next;
        end
    end

    // Lógica combinacional de estado y salida
    always @(*) begin
        state_next = state_reg;
        q_next     = q_reg;
        db_tick    = 1'b0;

        case (state_reg)
            zero: begin
                db_level = 1'b0;
                if (sw) begin
                    state_next = wait1;
                    q_next     = {N{1'b1}};
                end
            end

            wait1: begin
                db_level = 1'b0;
                if (sw) begin
                    q_next = q_reg - 1'b1;
                    if (q_next == 0) begin
                        state_next = one;
                        db_tick    = 1'b1;
                    end
                end else begin
                    state_next = zero;
                end
            end

            one: begin
                db_level = 1'b1;
                if (~sw) begin
                    state_next = wait0;
                    q_next     = {N{1'b1}};
                end
            end

            wait0: begin
                db_level = 1'b1;
                if (~sw) begin
                    q_next = q_reg - 1'b1;
                    if (q_next == 0)
                        state_next = zero;
                end else begin
                    state_next = one;
                end
            end

            default: state_next = zero;
        endcase
    end

endmodule