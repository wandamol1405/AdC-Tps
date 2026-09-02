// FSM antirrebote (tipo Moore) con detector de flanco integrado.
// Filtra los rebotes mecánicos de un pulsador y entrega tanto el nivel
// ya estabilizado (db_level) como un pulso de 1 ciclo al detectar
// una pulsación válida (db_tick).
module debounce #(
    // N define cuántos ciclos de clock hay que ver la entrada estable
    // antes de aceptar el cambio de nivel como real (y no un rebote).
    // Con clk = 100 MHz, N = 21 equivale a 2^21 ciclos ≈ 21 ms de espera,
    // tiempo típico mayor al rebote mecánico de los pulsadores de la Basys3.
    // Es un parameter (no localparam) para poder ajustarlo por instancia,
    // como hace load_ctrl.v vía N_DEBOUNCE.
    parameter N = 21
) (
    input  wire clk,       // Reloj principal
    input  wire reset,     // Reset sincrónico
    input  wire sw,        // Entrada del botón con rebotes
    output reg  db_level,  // Nivel lógico filtrado
    output reg  db_tick    // Pulso de 1 ciclo al presionar
);

    // Estados: zero/one = niveles estables (sin rebote); wait1/wait0 son
    // estados de "espera confirmando" mientras corre el contador de N bits.
    localparam [1:0]
        zero  = 2'b00,
        wait1 = 2'b01,
        one   = 2'b10,
        wait0 = 2'b11;

    reg [1:0]   state_reg, state_next; // estado actual / próximo estado de la FSM
    reg [N-1:0] q_reg, q_next;         // contador regresivo de confirmación (registro / próximo valor)

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
        db_level   = 1'b0;
        db_tick    = 1'b0;
        case (state_reg)
            // Reposo: entrada estable en 0. Ante el primer 1 se arranca
            // el conteo (q_next se carga en todo unos) para confirmarlo.
            zero: begin
                db_level = 1'b0;
                if (sw) begin
                    state_next = wait1;
                    q_next     = {N{1'b1}};
                end
            end

            // Confirmando el 1: mientras sw se mantenga en 1, el contador
            // decrementa. Si vuelve a 0 antes de llegar a cero, fue rebote
            // y se cancela volviendo a "zero". Si el contador llega a 0,
            // el nivel alto se da por real y se emite el pulso db_tick.
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

            // Nivel alto ya confirmado y estable. Ante el primer 0 se
            // arranca el mismo conteo pero para confirmar la liberación.
            one: begin
                db_level = 1'b1;
                if (~sw) begin
                    state_next = wait0;
                    q_next     = {N{1'b1}};
                end
            end

            // Confirmando el 0: misma lógica que wait1 pero en sentido
            // inverso (sin generar db_tick, que solo marca flanco de subida).
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