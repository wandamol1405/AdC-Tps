`timescale 1ns / 1ps

// =============================================================================
// TESTBENCH: tb_interface_rx.v
//
// ¿QUE HACE ESTE TESTBENCH?
// Prueba el módulo interface_rx de forma independiente (standalone), sin
// necesidad de conectar el uart_rx real.
//
// Simulamos nosotros mismos a los dos vecinos:
// 1. Al uart_rx: mandando un byte en i_rx_data junto con el pulso i_rx_done_tick.
// 2. Al loader_uart / consumidor: mandando el pulso i_rd cuando "ya leyó" el dato.
//
// CASOS QUE VERIFICA:
// - Caso 1: Estado inicial tras el reset (buzón vacío, rx_empty=1, r_data=0).
// - Caso 2: Llegada de un dato (set_flag): rx_empty=0 y o_r_data con el byte
//           correcto.
// - Caso 3: Persistencia mientras no se lee: el dato y el flag se mantienen
//           aunque pasen ciclos y aunque cambie el bus i_rx_data externo.
// - Caso 4: Lectura (clr_flag con i_rd): rx_empty vuelve a 1, pero o_r_data
//           retiene el último byte (no se borra, solo se libera el flag).
// - Caso 5: Segunda trama con otro dato (0x3C): vuelve a funcionar normalmente.
// - Caso 6: Reset mientras había un dato sin leer: limpia todo de inmediato.
// - Caso 7: Coincidencia de i_rx_done_tick e i_rd en el mismo ciclo: debe
//           prevalecer el dato nuevo (set gana sobre clr).
// - Caso 8: Overrun — dos tramas nuevas seguidas sin leer la primera en el
//           medio: el buffer se queda con el dato más reciente y rx_empty
//           sigue en 0 hasta que se lea (comportamiento esperado del esquema
//           flag+buffer, documentado en TP2/README.md).
// =============================================================================

module tb_interface_rx;

    parameter N_buffer = 8;

    // Señales para conectar al módulo bajo prueba (DUT)
    reg                   clk;
    reg                   reset;
    reg  [N_buffer-1:0]   i_rx_data;
    reg                   i_rd;
    reg                   i_rx_done_tick;
    wire [N_buffer-1:0]   o_r_data;
    wire                  o_rx_empty;

    // Contador de errores
    integer errors;

    // Instancia del módulo a testear (DUT = Device Under Test)
    interface_rx #(
        .N_buffer(N_buffer)
    ) dut (
        .clk(clk),
        .reset(reset),
        .i_rx_data(i_rx_data),
        .i_rd(i_rd),
        .i_rx_done_tick(i_rx_done_tick),
        .o_r_data(o_r_data),
        .o_rx_empty(o_rx_empty)
    );

    // Generador de reloj: 100 MHz (período de 10 ns: 5 ns en bajo, 5 ns en alto)
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Tarea auxiliar para chequear condiciones de forma limpia
    // -------------------------------------------------------------------------
    task check_status(
        input expected_empty,
        input [N_buffer-1:0] expected_data,
        input [511:0] test_name
    );
        begin
            #1; // Esperamos 1 ns tras el flanco de reloj para que las señales se estabilicen
            if (o_rx_empty === expected_empty &&
                o_r_data === expected_data) begin
                $display("[OK]   %0s -> rx_empty=%b, r_data=0x%02X",
                         test_name, o_rx_empty, o_r_data);
            end else begin
                $display("[FAIL] %0s -> Se esperaba (rx_empty=%b, r_data=0x%02X) pero se obtuvo (rx_empty=%b, r_data=0x%02X)",
                         test_name, expected_empty, expected_data,
                         o_rx_empty, o_r_data);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // SECUENCIA PRINCIPAL DE TEST
    // -------------------------------------------------------------------------
    initial begin
        // Inicialización de variables
        errors         = 0;
        clk            = 0;
        reset          = 1;
        i_rx_data      = {N_buffer{1'b0}};
        i_rd           = 1'b0;
        i_rx_done_tick = 1'b0;

        $display("========================================================");
        $display(" Testbench interface_rx (N_buffer=%0d)", N_buffer);
        $display("========================================================");

        // Dejamos 3 ciclos en reset y luego lo soltamos
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // ---------------------------------------------------------------------
        // CASO 1: Estado inicial tras el reset
        // El buzón debe estar vacío: rx_empty=1, r_data=0x00
        // ---------------------------------------------------------------------
        @(posedge clk);
        check_status(1'b1, 8'h00, "Caso 1 (Estado inicial post-reset)");

        // ---------------------------------------------------------------------
        // CASO 2: Llegada de un dato (0xA5) mediante pulso i_rx_done_tick
        // ---------------------------------------------------------------------
        @(negedge clk);
        i_rx_data      = 8'hA5;
        i_rx_done_tick = 1'b1; // Pulso de 1 ciclo, como lo manda uart_rx
        @(negedge clk);
        i_rx_done_tick = 1'b0;
        i_rx_data      = 8'h00; // Limpiamos el bus de entrada para comprobar que el dato quedó guardado adentro

        check_status(1'b0, 8'hA5, "Caso 2 (Llega 0xA5: flag baja a 0, dato guardado)");

        // ---------------------------------------------------------------------
        // CASO 3: Verificar que rx_empty NO sube solo con el paso del tiempo,
        // y que el dato no se pierde aunque cambie el bus externo i_rx_data
        // ---------------------------------------------------------------------
        i_rx_data = 8'hFF; // Ruido en el bus externo, no debería afectar
        repeat (10) @(posedge clk);
        check_status(1'b0, 8'hA5, "Caso 3 (Flag y dato se mantienen mientras no se lee)");

        // ---------------------------------------------------------------------
        // CASO 4: Lectura del dato (loader_uart manda el pulso i_rd)
        // rx_empty debe subir a 1, pero o_r_data retiene el último byte
        // ---------------------------------------------------------------------
        @(negedge clk);
        i_rd = 1'b1; // Pulso de 1 ciclo indicando "ya leí el dato"
        @(negedge clk);
        i_rd = 1'b0;

        check_status(1'b1, 8'hA5, "Caso 4 (Llega i_rd: flag sube a 1, dato retenido)");

        // ---------------------------------------------------------------------
        // CASO 5: Segunda trama con otro dato (0x3C)
        // Comprobar que el módulo queda listo para una nueva recepción
        // ---------------------------------------------------------------------
        repeat (3) @(posedge clk);
        @(negedge clk);
        i_rx_data      = 8'h3C;
        i_rx_done_tick = 1'b1;
        @(negedge clk);
        i_rx_done_tick = 1'b0;
        i_rx_data      = 8'h00;

        check_status(1'b0, 8'h3C, "Caso 5a (Segunda trama con 0x3C: flag baja)");

        repeat (5) @(posedge clk);

        @(negedge clk);
        i_rd = 1'b1;
        @(negedge clk);
        i_rd = 1'b0;

        check_status(1'b1, 8'h3C, "Caso 5b (Segundo i_rd: flag sube)");

        // ---------------------------------------------------------------------
        // CASO 6: Reset mientras había un dato sin leer
        // Si el sistema se resetea con una trama pendiente, debe volver a 0
        // ---------------------------------------------------------------------
        repeat (2) @(posedge clk);
        @(negedge clk);
        i_rx_data      = 8'h77;
        i_rx_done_tick = 1'b1;
        @(negedge clk);
        i_rx_done_tick = 1'b0;

        check_status(1'b0, 8'h77, "Caso 6a (Trama pendiente previa al reset)");

        @(negedge clk);
        reset = 1'b1; // Aplicamos reset con una trama sin leer
        @(posedge clk);
        check_status(1'b1, 8'h00, "Caso 6b (Reset forzado: limpia flag y buffer)");
        @(negedge clk);
        reset = 1'b0;

        // ---------------------------------------------------------------------
        // CASO 7: Llega una trama nueva (i_rx_done_tick) en el mismo ciclo en
        // que se lee la anterior (i_rd). Debe prevalecer la trama nueva.
        // ---------------------------------------------------------------------
        repeat (2) @(posedge clk);
        @(negedge clk);
        i_rx_data      = 8'h11;
        i_rx_done_tick = 1'b1;
        @(negedge clk);
        i_rx_done_tick = 1'b0;

        @(negedge clk);
        i_rx_data      = 8'hE1;
        i_rx_done_tick = 1'b1; // Nueva trama...
        i_rd           = 1'b1; // ...coincide con la lectura de la anterior
        @(negedge clk);
        i_rx_done_tick = 1'b0;
        i_rd           = 1'b0;

        check_status(1'b0, 8'hE1, "Caso 7 (Coincidencia rx_done_tick y rd: prevalece dato nuevo)");

        // Limpiamos finalmente con i_rd
        @(negedge clk);
        i_rd = 1'b1;
        @(negedge clk);
        i_rd = 1'b0;
        check_status(1'b1, 8'hE1, "Caso 7b (Cierre final tras coincidencia)");

        // ---------------------------------------------------------------------
        // CASO 8: Overrun — dos tramas nuevas seguidas sin leer la primera
        // El buffer se queda con el dato más reciente; rx_empty sigue en 0
        // ---------------------------------------------------------------------
        repeat (2) @(posedge clk);
        @(negedge clk);
        i_rx_data      = 8'h01;
        i_rx_done_tick = 1'b1;
        @(negedge clk);
        i_rx_done_tick = 1'b0;

        check_status(1'b0, 8'h01, "Caso 8a (Primera trama del overrun: 0x01)");

        // Llega una segunda trama antes de que nadie haya leído la primera
        @(negedge clk);
        i_rx_data      = 8'h02;
        i_rx_done_tick = 1'b1;
        @(negedge clk);
        i_rx_done_tick = 1'b0;

        check_status(1'b0, 8'h02, "Caso 8b (Overrun: el buffer pisa 0x01 con 0x02)");

        // Recién ahora se lee: se obtiene el dato más nuevo (0x02), el viejo (0x01) se perdió
        @(negedge clk);
        i_rd = 1'b1;
        @(negedge clk);
        i_rd = 1'b0;
        check_status(1'b1, 8'h02, "Caso 8c (Lectura tardia: se recupera el dato mas nuevo)");

        // ---------------------------------------------------------------------
        // RESUMEN FINAL
        // ---------------------------------------------------------------------
        $display("========================================================");
        if (errors == 0) begin
            $display(" RESULTADO: TODOS LOS CASOS PASARON");
        end else begin
            $display(" RESULTADO: %0d ERROR(ES) ENCONTRADO(S)", errors);
        end
        $display("========================================================");

        $finish;
    end

endmodule
