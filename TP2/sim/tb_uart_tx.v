`timescale 1ns / 1ps

// Testbench standalone para uart_tx. Genera i_tick internamente y verifica
// una trama UART completa: start, datos LSB-first, stop y tx_done.
module tb_uart_tx;

    parameter D_BIT = 8;
    parameter SB_TICK = 16;
    parameter OVERSAMPLE_TICK = 16;
    parameter TICK_PERIOD_CYCLES = 4;

    reg clk;
    reg reset;
    reg i_tick;
    reg [D_BIT-1:0] d_in;
    reg tx_start;
    wire tx;
    wire tx_done;

    integer errors;
    integer done_pulse_count;

    uart_tx #(
        .D_BIT(D_BIT),
        .SB_TICK(SB_TICK),
        .OVERSAMPLE_TICK(OVERSAMPLE_TICK)
    ) dut (
        .clk(clk),
        .reset(reset),
        .i_tick(i_tick),
        .d_in(d_in),
        .tx_start(tx_start),
        .tx(tx),
        .tx_done(tx_done)
    );

    always #5 clk = ~clk; // 100 MHz

    // Generador de i_tick analogo al usado en tb_uart_rx.
    reg [$clog2(TICK_PERIOD_CYCLES+1)-1:0] tick_div;
    always @(posedge clk) begin
        if (reset) begin
            tick_div <= 0;
            i_tick   <= 1'b0;
        end else if (tick_div == TICK_PERIOD_CYCLES - 1) begin
            tick_div <= 0;
            i_tick   <= 1'b1;
        end else begin
            tick_div <= tick_div + 1'b1;
            i_tick   <= 1'b0;
        end
    end

    // Cuenta los pulsos durante la trama que se esta verificando.
    always @(posedge clk) begin
        if (tx_done)
            done_pulse_count = done_pulse_count + 1;
    end

    // Solicita el envio durante un ciclo de clock. Luego cambia d_in para
    // verificar que el DUT transmitio el valor capturado al aceptar tx_start.
    task start_transmission(input [D_BIT-1:0] tx_byte);
        begin
            @(negedge i_tick);
            @(negedge clk);
            d_in = tx_byte;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;
            d_in = ~tx_byte;
        end
    endtask

    // Comprueba que tx conserva el valor esperado durante tick_total ticks.
    task check_level_for_ticks(
        input expected,
        input integer tick_total,
        input [255:0] field_name
    );
        integer tick_number;
        begin
            for (tick_number = 0; tick_number < tick_total; tick_number = tick_number + 1) begin
                if (tx === expected)
                    $display("[OK]   %0s, tick %0d: tx=%b", field_name, tick_number, tx);
                else begin
                    $display("[FAIL] %0s, tick %0d: tx=%b, esperado=%b", field_name, tick_number, tx, expected);
                    errors = errors + 1;
                end
                @(posedge i_tick);
                // La FSM actualiza sus registros al terminar el ciclo alto
                // de i_tick; asi el siguiente campo se observa ya estable.
                @(negedge i_tick);
            end
        end
    endtask

    task check_frame(input [D_BIT-1:0] expected, input [255:0] label);
        integer bit_index;
        begin
            done_pulse_count = 0;
            start_transmission(expected);

            check_level_for_ticks(1'b0, OVERSAMPLE_TICK, "Start bit");
            for (bit_index = 0; bit_index < D_BIT; bit_index = bit_index + 1)
                check_level_for_ticks(expected[bit_index], OVERSAMPLE_TICK, "Bit de datos");
            check_level_for_ticks(1'b1, SB_TICK, "Stop bit");

            if (done_pulse_count == 1)
                $display("[OK]   %0s: tx_done pulso exactamente 1 vez", label);
            else begin
                $display("[FAIL] %0s: tx_done pulso %0d vez/veces (esperado 1)", label, done_pulse_count);
                errors = errors + 1;
            end

            if (tx === 1'b1)
                $display("[OK]   %0s: tx regreso a reposo", label);
            else begin
                $display("[FAIL] %0s: tx no regreso a reposo (tx=%b)", label, tx);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        done_pulse_count = 0;
        clk = 0;
        reset = 1;
        i_tick = 1'b0;
        d_in = {D_BIT{1'b0}};
        tx_start = 1'b0;

        $display("========================================================");
        $display(" Testbench uart_tx - D_BIT=%0d SB_TICK=%0d OVERSAMPLE_TICK=%0d", D_BIT, SB_TICK, OVERSAMPLE_TICK);
        $display("========================================================");

        repeat (5) @(posedge clk);
        reset = 0;
        repeat (5) @(posedge clk);

        if (tx !== 1'b1) begin
            $display("[FAIL] La linea no esta en reposo despues de reset (tx=%b)", tx);
            errors = errors + 1;
        end

        // Byte con unos y ceros alternados: facilita detectar orden incorrecto.
        check_frame(8'hA5, "Caso 1 (trama valida 0xA5)");
        repeat (8) @(posedge clk);

        // Segunda trama para comprobar el retorno a IDLE y un nuevo envio.
        check_frame(8'h3C, "Caso 2 (segunda trama valida 0x3C)");

        $display("========================================================");
        if (errors == 0)
            $display(" RESULTADO: TODOS LOS CASOS PASARON");
        else
            $display(" RESULTADO: %0d ERROR(ES)", errors);
        $display("========================================================");
        $finish;
    end

endmodule
