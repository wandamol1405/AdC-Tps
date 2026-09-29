`timescale 1ns / 1ps

// =============================================================================
// TESTBENCH: tb_loader_uart.v
//
// ¿QUE HACE ESTE TESTBENCH?
// Prueba el módulo loader_uart de forma independiente (standalone), sin
// necesidad de conectar el interface_rx real.
//
// Simulamos nosotros mismos al vecino interface_rx con un "buzón" mock:
// - Para mandar un byte, se carga en i_r_data y se baja i_rx_empty.
// - Cuando loader_uart pulsa o_rd, el mock vuelve a subir i_rx_empty
//   (i_r_data se retiene, igual que en interface_rx).
//
// Un monitor revisa en TODOS los ciclos que:
// - Nunca haya más de un o_enb_reg_* activo a la vez.
// - Ningún o_enb_reg_* dure más de 1 ciclo.
// - o_rd y o_enb_reg_* solo se activen si hay dato (i_rx_empty = 0).
// y cuenta los pulsos de cada enable junto con el valor de i_r_data en ese ciclo.
//
// CASOS QUE VERIFICA:
// - Caso 1: Estado inicial tras el reset (sin dato: ni o_rd ni enables).
// - Caso 2: Carga de A (0x02 + valor): solo pulsa o_enb_reg_A con el valor.
// - Caso 3: Carga en otro orden: B, después Op.
// - Caso 4: Carga en otro orden: Op, A, B.
// - Caso 5: Dirección inválida (0x07): consume el valor sin pulsar enables
//           y vuelve a WAIT_CMD (la trama siguiente se decodifica bien).
// - Caso 6: Direcciones inválidas de borde (0x00 y 0x04).
// - Caso 7: Espera larga entre dirección y valor: no pulsa nada mientras
//           espera, y pulsa al llegar el valor.
// - Caso 8: Reset en medio de una trama (en WAIT_VALUE): el byte siguiente
//           se interpreta como dirección.
// - Caso 9: Bytes seguidos sin ciclos libres en el medio (back-to-back).
// =============================================================================

module tb_loader_uart;

    parameter N_BITS = 8;

    // Direcciones del protocolo
    localparam [N_BITS-1:0] ADDR_OP = 8'h01,
                            ADDR_A  = 8'h02,
                            ADDR_B  = 8'h03;

    // Señales para conectar al módulo bajo prueba (DUT)
    reg                 clk;
    reg                 reset;
    reg  [N_BITS-1:0]   i_r_data;
    reg                 i_rx_empty;
    wire                o_rd;
    wire                o_enb_reg_A;
    wire                o_enb_reg_B;
    wire                o_enb_reg_OP;

    // Control del mock de interface_rx
    reg                 push;       // Pulso: "llegó un byte" (como i_rx_done_tick)
    reg  [N_BITS-1:0]   push_data;  // Byte que llega

    // Contadores de pulsos y último valor capturado por cada enable
    integer cnt_A, cnt_B, cnt_OP, cnt_rd;
    reg  [N_BITS-1:0]   val_A, val_B, val_OP;

    // Contador de errores
    integer errors;

    // Instancia del módulo a testear (DUT = Device Under Test)
    loader_uart #(
        .N_BITS(N_BITS)
    ) dut (
        .clk(clk),
        .reset(reset),
        .i_r_data(i_r_data),
        .i_rx_empty(i_rx_empty),
        .o_rd(o_rd),
        .o_enb_reg_A(o_enb_reg_A),
        .o_enb_reg_B(o_enb_reg_B),
        .o_enb_reg_OP(o_enb_reg_OP)
    );

    // Generador de reloj: 100 MHz (período de 10 ns: 5 ns en bajo, 5 ns en alto)
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // MOCK DE interface_rx: buffer + flag de vacío
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            i_r_data   <= {N_BITS{1'b0}};
            i_rx_empty <= 1'b1;
        end else if (push) begin
            i_r_data   <= push_data;
            i_rx_empty <= 1'b0;
        end else if (o_rd) begin
            i_rx_empty <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // MONITOR: chequeos que valen en todos los ciclos
    // -------------------------------------------------------------------------
    reg prev_A, prev_B, prev_OP;

    always @(posedge clk) begin
        if (reset) begin
            prev_A  <= 1'b0;
            prev_B  <= 1'b0;
            prev_OP <= 1'b0;
        end else begin
            if (o_enb_reg_A + o_enb_reg_B + o_enb_reg_OP > 1) begin
                $display("[FAIL] t=%0t: mas de un enable activo (A=%b B=%b OP=%b)",
                         $time, o_enb_reg_A, o_enb_reg_B, o_enb_reg_OP);
                errors = errors + 1;
            end
            if ((o_enb_reg_A && prev_A) || (o_enb_reg_B && prev_B) || (o_enb_reg_OP && prev_OP)) begin
                $display("[FAIL] t=%0t: un enable duro mas de 1 ciclo", $time);
                errors = errors + 1;
            end
            if (i_rx_empty && (o_rd || o_enb_reg_A || o_enb_reg_B || o_enb_reg_OP)) begin
                $display("[FAIL] t=%0t: o_rd/enable activo sin dato disponible", $time);
                errors = errors + 1;
            end

            if (o_rd)         cnt_rd = cnt_rd + 1;
            if (o_enb_reg_A)  begin cnt_A  = cnt_A  + 1; val_A  = i_r_data; end
            if (o_enb_reg_B)  begin cnt_B  = cnt_B  + 1; val_B  = i_r_data; end
            if (o_enb_reg_OP) begin cnt_OP = cnt_OP + 1; val_OP = i_r_data; end

            prev_A  <= o_enb_reg_A;
            prev_B  <= o_enb_reg_B;
            prev_OP <= o_enb_reg_OP;
        end
    end

    // -------------------------------------------------------------------------
    // Tareas auxiliares
    // -------------------------------------------------------------------------

    // Reinicia los contadores del monitor antes de cada caso
    task clear_counts;
        begin
            cnt_A = 0; cnt_B = 0; cnt_OP = 0; cnt_rd = 0;
            val_A = 0; val_B = 0; val_OP = 0;
        end
    endtask

    // Manda un byte por el mock y espera a que loader_uart lo consuma (o_rd)
    task send_byte(input [N_BITS-1:0] b);
        integer timeout;
        begin
            @(negedge clk);
            push      = 1'b1;
            push_data = b;
            @(negedge clk);
            push      = 1'b0;
            timeout   = 0;
            while (!i_rx_empty && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!i_rx_empty) begin
                $display("[FAIL] t=%0t: el byte 0x%02X nunca fue consumido (o_rd)", $time, b);
                errors = errors + 1;
            end
        end
    endtask

    // Manda una trama completa: dirección + valor
    task send_frame(input [N_BITS-1:0] addr, input [N_BITS-1:0] value);
        begin
            send_byte(addr);
            send_byte(value);
        end
    endtask

    // Compara contadores de pulsos y valores capturados contra lo esperado
    task check_loads(
        input integer exp_A,
        input integer exp_B,
        input integer exp_OP,
        input integer exp_rd,
        input [N_BITS-1:0] exp_val_A,
        input [N_BITS-1:0] exp_val_B,
        input [N_BITS-1:0] exp_val_OP,
        input [511:0] test_name
    );
        begin
            repeat (2) @(negedge clk); // Margen para que termine cualquier pulso pendiente
            if (cnt_A === exp_A && cnt_B === exp_B && cnt_OP === exp_OP && cnt_rd === exp_rd &&
                (exp_A  == 0 || val_A  === exp_val_A) &&
                (exp_B  == 0 || val_B  === exp_val_B) &&
                (exp_OP == 0 || val_OP === exp_val_OP)) begin
                $display("[OK]   %0s -> pulsos A=%0d B=%0d OP=%0d rd=%0d | A=0x%02X B=0x%02X OP=0x%02X",
                         test_name, cnt_A, cnt_B, cnt_OP, cnt_rd, val_A, val_B, val_OP);
            end else begin
                $display("[FAIL] %0s -> Se esperaba (A=%0d B=%0d OP=%0d rd=%0d | A=0x%02X B=0x%02X OP=0x%02X) pero se obtuvo (A=%0d B=%0d OP=%0d rd=%0d | A=0x%02X B=0x%02X OP=0x%02X)",
                         test_name, exp_A, exp_B, exp_OP, exp_rd, exp_val_A, exp_val_B, exp_val_OP,
                         cnt_A, cnt_B, cnt_OP, cnt_rd, val_A, val_B, val_OP);
                errors = errors + 1;
            end
            clear_counts;
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
        push      = 1'b0;
        push_data = {N_BITS{1'b0}};
        clear_counts;

        $display("========================================================");
        $display(" Testbench loader_uart (N_BITS=%0d)", N_BITS);
        $display("========================================================");

        // Dejamos 3 ciclos en reset y luego lo soltamos
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // ---------------------------------------------------------------------
        // CASO 1: Estado inicial tras el reset
        // Sin dato disponible no debe haber ni o_rd ni enables
        // ---------------------------------------------------------------------
        repeat (10) @(negedge clk);
        check_loads(0, 0, 0, 0, 0, 0, 0, "Caso 1 (Post-reset sin dato: nada activo)");

        // ---------------------------------------------------------------------
        // CASO 2: Carga de A
        // ---------------------------------------------------------------------
        send_frame(ADDR_A, 8'h11);
        check_loads(1, 0, 0, 2, 8'h11, 0, 0, "Caso 2 (Carga A=0x11)");

        // ---------------------------------------------------------------------
        // CASO 3: Carga en orden B, Op
        // ---------------------------------------------------------------------
        send_frame(ADDR_B, 8'h22);
        check_loads(0, 1, 0, 2, 0, 8'h22, 0, "Caso 3a (Carga B=0x22)");

        send_frame(ADDR_OP, 8'h20);
        check_loads(0, 0, 1, 2, 0, 0, 8'h20, "Caso 3b (Carga Op=0x20)");

        // ---------------------------------------------------------------------
        // CASO 4: Carga en orden Op, A, B (las tres seguidas)
        // ---------------------------------------------------------------------
        send_frame(ADDR_OP, 8'h22);
        send_frame(ADDR_A,  8'hA5);
        send_frame(ADDR_B,  8'h5A);
        check_loads(1, 1, 1, 6, 8'hA5, 8'h5A, 8'h22, "Caso 4 (Orden Op, A, B)");

        // ---------------------------------------------------------------------
        // CASO 5: Dirección inválida (0x07)
        // Se consume el valor sin pulsar enables y la FSM vuelve a WAIT_CMD:
        // la trama siguiente tiene que decodificarse normalmente
        // ---------------------------------------------------------------------
        send_frame(8'h07, 8'hFF);
        check_loads(0, 0, 0, 2, 0, 0, 0, "Caso 5a (Direccion invalida 0x07: descarta)");

        send_frame(ADDR_B, 8'h3C);
        check_loads(0, 1, 0, 2, 0, 8'h3C, 0, "Caso 5b (Trama valida despues de la invalida)");

        // ---------------------------------------------------------------------
        // CASO 6: Direcciones inválidas de borde (0x00 y 0x04)
        // ---------------------------------------------------------------------
        send_frame(8'h00, 8'h01);
        send_frame(8'h04, 8'h02);
        check_loads(0, 0, 0, 4, 0, 0, 0, "Caso 6a (Direcciones invalidas 0x00 y 0x04)");

        send_frame(ADDR_OP, 8'h24);
        check_loads(0, 0, 1, 2, 0, 0, 8'h24, "Caso 6b (Trama valida despues de las invalidas)");

        // ---------------------------------------------------------------------
        // CASO 7: Espera larga entre dirección y valor
        // Mientras la FSM espera el valor no debe pulsar nada
        // ---------------------------------------------------------------------
        send_byte(ADDR_A);
        repeat (30) @(negedge clk);
        check_loads(0, 0, 0, 1, 0, 0, 0, "Caso 7a (Esperando el valor: ningun enable)");

        send_byte(8'h77);
        check_loads(1, 0, 0, 1, 8'h77, 0, 0, "Caso 7b (Llega el valor: pulsa A=0x77)");

        // ---------------------------------------------------------------------
        // CASO 8: Reset en medio de una trama (FSM en WAIT_VALUE)
        // Tras el reset, el próximo byte se interpreta como dirección
        // ---------------------------------------------------------------------
        send_byte(ADDR_A);
        @(negedge clk);
        reset = 1'b1;
        repeat (2) @(negedge clk);
        reset = 1'b0;
        clear_counts;

        send_frame(ADDR_B, 8'h99);
        check_loads(0, 1, 0, 2, 0, 8'h99, 0, "Caso 8 (Reset en WAIT_VALUE: arranca en WAIT_CMD)");

        // ---------------------------------------------------------------------
        // CASO 9: Bytes back-to-back
        // Se empuja un byte nuevo en el mismo ciclo en que se consume el anterior
        // ---------------------------------------------------------------------
        @(negedge clk);
        push = 1'b1; push_data = ADDR_OP;
        @(negedge clk);
        push = 1'b1; push_data = 8'h26;  // Coincide con el o_rd de la dirección
        @(negedge clk);
        push = 1'b1; push_data = ADDR_A;
        @(negedge clk);
        push = 1'b1; push_data = 8'hC3;
        @(negedge clk);
        push = 1'b0;
        check_loads(1, 0, 1, 4, 8'hC3, 0, 8'h26, "Caso 9 (Bytes back-to-back: Op=0x26, A=0xC3)");

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
