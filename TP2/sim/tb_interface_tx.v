`timescale 1ns / 1ps

// =============================================================================
// TESTBENCH: tb_interface_tx.v
//
// ¿QUE HACE ESTE TESTBENCH?
// Prueba el módulo interface_tx de forma independiente (standalone), sin
// necesidad de conectar el uart_tx real.
//
// Simulamos nosotros mismos a los dos vecinos:
// 1. A la ALU / result_sender: enviando pulsos en i_wr con un byte en i_w_data.
// 2. Al uart_tx: simulando el tiempo que tarda en transmitir y mandando el
//    pulsito de fin en i_tx_done.
//
// CASOS QUE VERIFICA:
// - Caso 1: Estado inicial tras el reset (buzón vacío, full=0, start=0).
// - Caso 2: Carga de un dato (set_flag): verificar que full=1, start=1 y que
//           el dato en o_d_in sea el correcto.
// - Caso 3: Inmunidad durante la transmisión: verificar que full se mantiene
//           en 1 aunque pasen ciclos y aunque cambie el bus i_w_data.
// - Caso 4: Fin de transmisión (clr_flag con i_tx_done): verificar que full
//           baja recién acá a 0.
// - Caso 5: Segundo envío con otro dato (0x3C): comprobar que vuelve a
//           funcionar normalmente en un ciclo posterior.
// - Caso 6: Reset mientras está ocupado: verificar que limpia todo de inmediato.
// - Caso 7: Llegada simultánea de nuevo dato (i_wr) y fin previo (i_tx_done).
// =============================================================================

module tb_interface_tx;

    parameter D_BIT = 8;

    // Señales para conectar al módulo bajo prueba (DUT)
    reg              clk;
    reg              reset;
    reg  [D_BIT-1:0] i_w_data;
    reg              i_wr;
    reg              i_tx_done;
    wire             o_tx_full;
    wire [D_BIT-1:0] o_d_in;
    wire             o_tx_start;

    // Contador de errores
    integer errors;

    // Instancia del módulo a testear (DUT = Device Under Test)
    interface_tx #(
        .D_BIT(D_BIT)
    ) dut (
        .clk(clk),
        .reset(reset),
        .i_w_data(i_w_data),
        .i_wr(i_wr),
        .i_tx_done(i_tx_done),
        .o_tx_full(o_tx_full),
        .o_d_in(o_d_in),
        .o_tx_start(o_tx_start)
    );

    // Generador de reloj: 100 MHz (período de 10 ns: 5 ns en bajo, 5 ns en alto)
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Tarea auxiliar para chequear condiciones de forma limpia
    // -------------------------------------------------------------------------
    task check_status(
        input expected_full,
        input expected_start,
        input [D_BIT-1:0] expected_data,
        input [511:0] test_name
    );
        begin
            #1; // Esperamos 1 ns tras el flanco de reloj para que las señales se estabilicen
            if (o_tx_full === expected_full &&
                o_tx_start === expected_start &&
                o_d_in === expected_data) begin
                $display("[OK]   %0s -> full=%b, start=%b, d_in=0x%02X",
                         test_name, o_tx_full, o_tx_start, o_d_in);
            end else begin
                $display("[FAIL] %0s -> Se esperaba (full=%b, start=%b, d_in=0x%02X) pero se obtuvo (full=%b, start=%b, d_in=0x%02X)",
                         test_name, expected_full, expected_start, expected_data,
                         o_tx_full, o_tx_start, o_d_in);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // SECUENCIA PRINCIPAL DE TEST
    // -------------------------------------------------------------------------
    initial begin
        // Inicialización de variables
        errors    = 0;
        clk       = 0;
        reset     = 1;
        i_w_data  = 8'h00;
        i_wr      = 1'b0;
        i_tx_done = 1'b0;

        $display("========================================================");
        $display(" Testbench interface_tx (D_BIT=%0d)", D_BIT);
        $display("========================================================");

        // Dejamos 3 ciclos en reset y luego lo soltamos
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // ---------------------------------------------------------------------
        // CASO 1: Estado inicial tras el reset
        // El buzón debe estar vacío: tx_full=0, tx_start=0, d_in=0x00
        // ---------------------------------------------------------------------
        @(posedge clk);
        check_status(1'b0, 1'b0, 8'h00, "Caso 1 (Estado inicial post-reset)");

        // ---------------------------------------------------------------------
        // CASO 2: Carga de un dato (0xA5) mediante pulso i_wr
        // ---------------------------------------------------------------------
        @(negedge clk);
        i_w_data = 8'hA5;
        i_wr     = 1'b1; // Pulso de escritura durante 1 ciclo
        @(negedge clk);
        i_wr     = 1'b0;
        i_w_data = 8'h00; // Limpiamos el bus de entrada para comprobar que el dato quedó guardado adentro

        // En el flanco que capturó i_wr, el buffer debe tener 0xA5 y el flag en 1
        check_status(1'b1, 1'b1, 8'hA5, "Caso 2 (Escritura de 0xA5: flag sube)");

        // ---------------------------------------------------------------------
        // CASO 3: Verificar que tx_full NO se limpia solo con el paso del tiempo
        // Simulamos que pasan varios ciclos de reloj (uart_tx transmitiendo)
        // ---------------------------------------------------------------------
        repeat (10) @(posedge clk);
        check_status(1'b1, 1'b1, 8'hA5, "Caso 3 (Flag se mantiene en 1 mientras transmite)");

        // ---------------------------------------------------------------------
        // CASO 4: Fin de transmisión (uart_tx manda el pulso i_tx_done)
        // tx_full debe limpiarse recién acá, no antes
        // ---------------------------------------------------------------------
        @(negedge clk);
        i_tx_done = 1'b1; // Pulso de 1 ciclo indicando fin de trama UART
        @(negedge clk);
        i_tx_done = 1'b0;

        // Comprobamos que el flag bajó a 0 (buzón libre de nuevo)
        check_status(1'b0, 1'b0, 8'hA5, "Caso 4 (Llega tx_done: flag se limpia a 0)");

        // ---------------------------------------------------------------------
        // CASO 5: Segunda transmisión con otro dato (0x3C)
        // Comprobar que el módulo queda listo para un nuevo envío
        // ---------------------------------------------------------------------
        repeat (3) @(posedge clk);
        @(negedge clk);
        i_w_data = 8'h3C;
        i_wr     = 1'b1;
        @(negedge clk);
        i_wr     = 1'b0;
        i_w_data = 8'hFF; // Ruido en el bus externo

        check_status(1'b1, 1'b1, 8'h3C, "Caso 5a (Segunda carga con 0x3C: flag sube)");

        repeat (5) @(posedge clk);

        @(negedge clk);
        i_tx_done = 1'b1;
        @(negedge clk);
        i_tx_done = 1'b0;

        check_status(1'b0, 1'b0, 8'h3C, "Caso 5b (Segundo tx_done: flag baja)");

        // ---------------------------------------------------------------------
        // CASO 6: Reset mientras estaba ocupado
        // Si el sistema se resetea a mitad de una transmisión, debe volver a 0
        // ---------------------------------------------------------------------
        repeat (2) @(posedge clk);
        @(negedge clk);
        i_w_data = 8'h77;
        i_wr     = 1'b1;
        @(negedge clk);
        i_wr     = 1'b0;

        check_status(1'b1, 1'b1, 8'h77, "Caso 6a (Carga previa al reset)");

        @(negedge clk);
        reset = 1'b1; // Aplicamos reset con la bandera arriba
        @(posedge clk);
        check_status(1'b0, 1'b0, 8'h00, "Caso 6b (Reset forzado: limpia flag y buffer)");
        @(negedge clk);
        reset = 1'b0;

        // ---------------------------------------------------------------------
        // CASO 7: Llega nuevo dato (i_wr) en el mismo ciclo que termina el anterior (i_tx_done)
        // Debe prevalecer la nueva escritura
        // ---------------------------------------------------------------------
        repeat (2) @(posedge clk);
        @(negedge clk);
        i_w_data  = 8'hE1;
        i_wr      = 1'b1;
        i_tx_done = 1'b1; // Simulamos coincidencia de ambos pulsos
        @(negedge clk);
        i_wr      = 1'b0;
        i_tx_done = 1'b0;

        check_status(1'b1, 1'b1, 8'hE1, "Caso 7 (Coincidencia wr y tx_done: prevalece nuevo dato)");

        // Limpiamos finalmente con tx_done
        @(negedge clk);
        i_tx_done = 1'b1;
        @(negedge clk);
        i_tx_done = 1'b0;
        check_status(1'b0, 1'b0, 8'hE1, "Caso 7b (Cierre final tras coincidencia)");

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
