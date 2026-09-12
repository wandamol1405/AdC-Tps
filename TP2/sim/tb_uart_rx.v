`timescale 1ns / 1ps

// Testbench standalone para uart_rx: genera i_tick internamente (sin
// instanciar el Baud Rate Generator) y arma tramas serie bit a bit sobre
// in_rx, verificando el protocolo de la seccion 5 de la consigna TP2:
//   - o_data coincide con el byte enviado.
//   - o_done_tick pulsa una unica vez por byte recibido.
//   - un glitch (ruido) en el start bit, mas corto que medio periodo de
//     bit, no debe disparar una recepcion falsa (ver seccion 5.1, paso 2:
//     "se confirma que no es ruido").
module tb_uart_rx;

    parameter D_BIT           = 8;
    parameter SB_TICK         = 16;
    parameter OVERSAMPLE_TICK = 16;
    parameter TICK_PERIOD_CYCLES = 4; // ciclos de clk simulados entre ticks

    reg clk;
    reg reset;
    reg in_rx;
    reg i_tick;
    wire [D_BIT-1:0] o_data;
    wire o_done_tick;

    integer errors;
    integer done_pulse_count;

    uart_rx #(
        .D_BIT(D_BIT),
        .SB_TICK(SB_TICK),
        .OVERSAMPLE_TICK(OVERSAMPLE_TICK)
    ) dut (
        .clk(clk),
        .reset(reset),
        .in_rx(in_rx),
        .i_tick(i_tick),
        .o_data(o_data),
        .o_done_tick(o_done_tick)
    );

    always #5 clk = ~clk; // 100 MHz

    // Generador de i_tick: divisor libre de clk, analogo en su rol al
    // Baud Rate Generator pero sin instanciarlo (testbench standalone).
    reg [$clog2(TICK_PERIOD_CYCLES+1)-1:0] tick_div;
    always @(posedge clk) begin
        if (reset) begin
            tick_div <= 0;
            i_tick   <= 1'b0;
        end else if (tick_div == TICK_PERIOD_CYCLES - 1) begin
            tick_div <= 0;
            i_tick   <= 1'b1;
        end else begin
            tick_div <= tick_div + 1;
            i_tick   <= 1'b0;
        end
    end

    // Cuenta pulsos de o_done_tick durante la ventana de observacion actual.
    always @(posedge clk) begin
        if (o_done_tick) done_pulse_count = done_pulse_count + 1;
    end

    // Envia una trama serie completa (start + D_BIT datos LSB-primero +
    // stop) respetando el timing de muestreo de la FSM del DUT.
    task send_byte(input [D_BIT-1:0] tx_byte);
        integer b;
        begin
            // Punto de partida lejos de cualquier flanco de i_tick: si
            // in_rx cayera exactamente en el mismo instante que un tick ya
            // en curso, el primer repeat(...) de mas abajo podria "perder"
            // ese tick y contar uno de menos durante todo el resto de la trama.
            @(negedge i_tick);
            in_rx = 1'b0; // start bit
            repeat (OVERSAMPLE_TICK/2) @(posedge i_tick);
            // i_tick queda en alto todo el ciclo de clk; el DUT recien
            // latchea el resultado de esta confirmacion en el flanco de
            // clk que hace bajar i_tick. Hay que esperar a que baje antes
            // de cambiar in_rx, o el bit nuevo se cuela en ese muestreo.
            @(negedge i_tick);

            for (b = 0; b < D_BIT; b = b + 1) begin
                in_rx = tx_byte[b];
                repeat (OVERSAMPLE_TICK) @(posedge i_tick);
                @(negedge i_tick); // idem: esperar a que termine el tick de muestreo de este bit
            end

            in_rx = 1'b1; // stop bit
            repeat (SB_TICK) @(posedge i_tick);
            @(negedge i_tick);
        end
    endtask

    // Verifica una trama valida: o_data debe coincidir y o_done_tick debe
    // haber pulsado exactamente una vez.
    task check_frame(input [D_BIT-1:0] expected, input [511:0] label);
        begin
            if (o_data === expected)
                $display("[OK]   %0s: o_data = 0x%0h coincide con lo enviado", label, o_data);
            else begin
                $display("[FAIL] %0s: o_data = 0x%0h, esperado 0x%0h", label, o_data, expected);
                errors = errors + 1;
            end

            if (done_pulse_count == 1)
                $display("[OK]   %0s: o_done_tick pulso exactamente 1 vez", label);
            else begin
                $display("[FAIL] %0s: o_done_tick pulso %0d vez/veces (esperado 1)", label, done_pulse_count);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors           = 0;
        clk              = 0;
        reset            = 1;
        in_rx            = 1'b1; // linea en reposo
        done_pulse_count = 0;

        $display("========================================================");
        $display(" Testbench uart_rx - D_BIT=%0d SB_TICK=%0d OVERSAMPLE_TICK=%0d", D_BIT, SB_TICK, OVERSAMPLE_TICK);
        $display("========================================================");

        repeat (5) @(posedge clk);
        reset = 0;
        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------
        // Caso 1: trama valida.
        // ---------------------------------------------------------------
        done_pulse_count = 0;
        send_byte(8'hA5);
        repeat (SB_TICK) @(posedge clk); // margen tras el stop bit
        check_frame(8'hA5, "Caso 1 (trama valida 0xA5)");

        in_rx = 1'b1;
        repeat (20) @(posedge clk);

        // Segunda trama, para confirmar que el receptor vuelve a
        // sincronizarse correctamente despues de una recepcion previa.
        done_pulse_count = 0;
        send_byte(8'h3C);
        repeat (SB_TICK) @(posedge clk);
        check_frame(8'h3C, "Caso 1b (segunda trama valida 0x3C)");

        in_rx = 1'b1;
        repeat (20) @(posedge clk);

        // ---------------------------------------------------------------
        // Caso 2: glitch en el start bit. La linea cae a 0 por mucho menos
        // que medio periodo de bit (ruido) y vuelve a 1 antes de que la FSM
        // llegue al punto medio del start bit (tick MIDDLE_BIT). No debe
        // completarse ninguna recepcion durante una ventana equivalente a
        // una trama completa.
        // ---------------------------------------------------------------
        done_pulse_count = 0;
        @(negedge i_tick); // punto de partida lejos de cualquier flanco de tick
        in_rx = 1'b0;
        repeat (2) @(posedge i_tick); // << OVERSAMPLE_TICK/2: glitch, no start real
        #1;
        in_rx = 1'b1;

        repeat ((OVERSAMPLE_TICK/2) + D_BIT*OVERSAMPLE_TICK + SB_TICK + 8) @(posedge i_tick);

        if (done_pulse_count == 0)
            $display("[OK]   Caso 2 (glitch en start bit): no disparo o_done_tick");
        else begin
            $display("[FAIL] Caso 2 (glitch en start bit): o_done_tick pulso %0d vez/veces (falso positivo, o_data=0x%0h)", done_pulse_count, o_data);
            errors = errors + 1;
        end

        // El receptor debe poder sincronizar una trama valida despues del glitch.
        in_rx = 1'b1;
        repeat (20) @(posedge clk);
        done_pulse_count = 0;
        send_byte(8'h5A);
        repeat (SB_TICK) @(posedge clk);
        check_frame(8'h5A, "Caso 2b (trama valida 0x5A tras el glitch)");

        $display("========================================================");
        if (errors == 0)
            $display(" RESULTADO: TODOS LOS CASOS PASARON");
        else
            $display(" RESULTADO: %0d CASO(S) FALLARON", errors);
        $display("========================================================");

        $finish;
    end

endmodule
