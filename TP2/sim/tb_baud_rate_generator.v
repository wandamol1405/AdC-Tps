`timescale 1ns / 1ps

// Testbench autochequeado: mide, contando ciclos de clock, el periodo entre
// pulsos consecutivos de s_tick y verifica que sea exactamente el esperado
// (CLK_FREQ / (BAUD_RATE * OVERSAMPLE)) durante los 16 ticks de un periodo
// de bit completo (ver consigna TP2 seccion 4).
module tb_baud_rate_generator;

    parameter BAUD_RATE  = 19200;
    parameter CLK_FREQ   = 100000000;
    parameter OVERSAMPLE = 16;
    localparam integer EXPECTED_DIV = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);

    reg  clk;
    reg  reset;
    wire s_tick;

    integer errors;
    integer tick_count;
    integer cycles_since_last_tick;
    integer last_tick_cycle;
    integer cycle_counter;

    baud_rate_generator #(
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE),
        .CLK_FREQ(CLK_FREQ)
    ) u_baud_rate_generator (
        .clk(clk),
        .reset(reset),
        .s_tick(s_tick)
    );

    always #5 clk = ~clk; // 100 MHz clock (periodo 10 ns, igual al de la Basys3)

    // Cuenta ciclos de clock transcurridos desde el reset, para medir el
    // periodo entre pulsos de s_tick de forma independiente al contador interno del DUT.
    always @(posedge clk) begin
        if (reset)
            cycle_counter <= 0;
        else
            cycle_counter <= cycle_counter + 1;
    end

    initial begin
        errors          = 0;
        tick_count      = 0;
        last_tick_cycle = 0;
        clk             = 0;
        reset           = 1;

        $display("========================================================");
        $display(" Testbench baud_rate_generator - BAUD_RATE=%0d OVERSAMPLE=%0d CLK_FREQ=%0d", BAUD_RATE, OVERSAMPLE, CLK_FREQ);
        $display(" Periodo esperado entre s_tick: %0d ciclos de clock", EXPECTED_DIV);
        $display("========================================================");

        repeat (3) @(posedge clk);
        reset = 0;

        // El primer tick post-reset solo sirve de referencia de arranque: su
        // fase respecto de reset no forma parte de la spec (depende de una
        // carrera de simulacion entre el contador interno del DUT y este
        // contador de ciclos). Lo que sí exige la spec es que, en regimen,
        // cada uno de los 16 intervalos entre ticks consecutivos de un
        // periodo de bit dure exactamente lo mismo -> se verifican esos
        // 16 intervalos entre los ticks #1 a #17.
        @(posedge s_tick);
        tick_count      = 1;
        last_tick_cycle = cycle_counter;
        $display("[INFO] tick #1 (referencia de arranque, fase no especificada) a los %0d ciclos de clock", cycle_counter);

        while (tick_count < OVERSAMPLE + 1) begin
            @(posedge s_tick);
            tick_count             = tick_count + 1;
            cycles_since_last_tick = cycle_counter - last_tick_cycle;
            last_tick_cycle        = cycle_counter;

            if (cycles_since_last_tick == EXPECTED_DIV) begin
                $display("[OK]   intervalo #%0d (tick #%0d) a los %0d ciclos de clock", tick_count - 1, tick_count, cycles_since_last_tick);
            end else begin
                $display("[FAIL] intervalo #%0d (tick #%0d) a los %0d ciclos de clock (esperado %0d)", tick_count - 1, tick_count, cycles_since_last_tick, EXPECTED_DIV);
                errors = errors + 1;
            end
        end

        $display("--------------------------------------------------------");
        if (tick_count == OVERSAMPLE + 1 && errors == 0) begin
            $display("[OK]   Se verificaron los %0d intervalos (sobremuestreo 16x) de un periodo de bit", OVERSAMPLE);
        end else begin
            $display("[FAIL] Cantidad de intervalos o periodo incorrecto");
            errors = errors + 1;
        end

        $display("========================================================");
        if (errors == 0)
            $display(" RESULTADO: TODOS LOS CASOS PASARON");
        else
            $display(" RESULTADO: %0d CASO(S) FALLARON", errors);
        $display("========================================================");

        $finish;
    end

endmodule
