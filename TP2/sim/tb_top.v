`timescale 1ns / 1ps

// =============================================================================
// TESTBENCH: tb_top.v
//
// ¿QUE HACE ESTE TESTBENCH?
// Prueba el top completo del TP2 de punta a punta, como lo usaría la PC:
// - Manda bytes reales bit a bit por rx (start + 8 bits LSB primero + stop) a
//   la velocidad real de la placa (19200 baud con clock de 100 MHz).
// - Decodifica lo que sale por tx con un receptor propio del testbench (no
//   usa uart_rx), así la verificación no depende del diseño que se prueba.
//
// Comandos: pares [dirección, valor] con 0x01 = Op, 0x02 = A, 0x03 = B.
// Respuesta esperada: [resultado, status] con status = {6'b0, overflow, carry}.
//
// CASOS QUE VERIFICA:
// - Caso 1: Estado post-reset: tx en reposo (1), LEDs apagados.
// - Caso 2: Cargar A y B sin Op: no hay respuesta (ALU sin habilitar), pero los
//           registros se cargan.
// - Caso 3: Cargar Op = ADD: se habilita la ALU y llega 5 + 3 = 0x08, status 0x00.
//           Los LEDs muestran el resultado.
// - Caso 4: Overflow: B = 0x7F -> 5 + 127 satura en 0x7F, status 0x02.
// - Caso 5: Cambio de opcode a SUB: 5 - 127 = 0x86, status 0x00.
// - Caso 6: Recargar A con el mismo valor: no hay respuesta.
// - Caso 7: Dirección inválida (0x07) seguida de un comando válido: el inválido
//           se descarta y el siguiente se decodifica bien.
// - Caso 8: Carry: 0xFF + 0x01 con ADD -> 0x00, status 0x01.
// - Caso 9: Comandos seguidos sin pausa (como los mandaría la GUI): llegan
//           respuestas en pares completos y la última es la cuenta final.
// =============================================================================

module tb_top;

    // -------------------------------------------------------------------------
    // Parámetros de tiempo (los mismos que la placa)
    // -------------------------------------------------------------------------
    localparam CLK_FREQ   = 100000000;
    localparam BAUD_RATE  = 19200;
    localparam OVERSAMPLE = 16;
    localparam CLK_NS     = 10;                                         // 100 MHz
    localparam BAUD_DIV   = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);        // 325
    localparam BIT_NS     = BAUD_DIV * OVERSAMPLE * CLK_NS;             // 52000 ns por bit
    localparam FRAME_NS   = 10 * BIT_NS;                                // 1 byte = 10 bits
    localparam RESP_WAIT  = 3 * FRAME_NS;                               // Margen para 2 bytes de respuesta

    // Opcodes de la ALU (TP1)
    localparam [7:0] OP_ADD = 8'h20;
    localparam [7:0] OP_SUB = 8'h22;

    // Direcciones del protocolo
    localparam [7:0] ADDR_OP = 8'h01;
    localparam [7:0] ADDR_A  = 8'h02;
    localparam [7:0] ADDR_B  = 8'h03;

    // -------------------------------------------------------------------------
    // Señales
    // -------------------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg         rx;
    wire        tx;
    wire [10:0] led;

    integer errors;

    top #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .tx(tx),
        .led(led)
    );

    always #(CLK_NS / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // "PC" transmitiendo: manda un byte por rx (LSB primero)
    // -------------------------------------------------------------------------
    task send_byte(input [7:0] b);
        integer i;
        begin
            rx = 1'b0;                 // Start bit
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];             // Datos, LSB primero
                #(BIT_NS);
            end
            rx = 1'b1;                 // Stop bit
            #(BIT_NS);
        end
    endtask

    // Comando completo: dirección + valor
    task send_cmd(input [7:0] addr, input [7:0] value);
        begin
            send_byte(addr);
            send_byte(value);
        end
    endtask

    // -------------------------------------------------------------------------
    // "PC" recibiendo: decodifica tx de forma independiente
    // Espera el flanco de bajada del start bit, va a la mitad del bit y desde
    // ahí muestrea cada bit cada BIT_NS. Guarda cada byte en rx_bytes[].
    // -------------------------------------------------------------------------
    reg [7:0] rx_bytes [0:127];
    integer   rx_count;
    reg [7:0] rbyte;
    integer   k;

    always begin
        @(negedge tx);
        if (!reset) begin
            #(BIT_NS / 2);
            if (tx === 1'b0) begin                 // Start bit confirmado
                for (k = 0; k < 8; k = k + 1) begin
                    #(BIT_NS);
                    rbyte[k] = tx;
                end
                #(BIT_NS);
                if (tx !== 1'b1) begin
                    $display("[FAIL] t=%0t: stop bit invalido en tx (byte 0x%02X)", $time, rbyte);
                    errors = errors + 1;
                end
                rx_bytes[rx_count] = rbyte;
                rx_count = rx_count + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Verificación: bytes recibidos desde 'base' (hasta 4, empaquetados {b0,b1,b2,b3})
    // -------------------------------------------------------------------------
    task check_rx(
        input integer base,
        input integer n,
        input [31:0]  expected,
        input [511:0] test_name
    );
        integer i;
        reg ok;
        begin
            ok = (rx_count - base == n);
            for (i = 0; i < n && ok; i = i + 1)
                if (rx_bytes[base + i] !== expected[31 - 8*i -: 8]) ok = 0;

            if (ok) begin
                $write("[OK]   %0s -> %0d byte(s):", test_name, n);
            end else begin
                $write("[FAIL] %0s -> se esperaban %0d byte(s):", test_name, n);
                for (i = 0; i < n; i = i + 1) $write(" 0x%02X", expected[31 - 8*i -: 8]);
                $write(" | llegaron %0d:", rx_count - base);
                errors = errors + 1;
            end
            for (i = base; i < rx_count; i = i + 1) $write(" 0x%02X", rx_bytes[i]);
            $write("\n");
        end
    endtask

    task check_value(input [31:0] got, input [31:0] expected, input [511:0] test_name);
        begin
            if (got === expected) begin
                $display("[OK]   %0s -> 0x%0X", test_name, got);
            end else begin
                $display("[FAIL] %0s -> se esperaba 0x%0X pero se obtuvo 0x%0X", test_name, expected, got);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // SECUENCIA PRINCIPAL DE TEST
    // -------------------------------------------------------------------------
    integer base, i, pairs_ok;

    initial begin
        errors   = 0;
        rx_count = 0;
        clk      = 0;
        reset    = 1;
        rx       = 1'b1; // Línea en reposo

        $display("========================================================");
        $display(" Testbench top TP2 (solo UART) - %0d baud, %0d ns por bit", BAUD_RATE, BIT_NS);
        $display("========================================================");

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // ---------------------------------------------------------------------
        // CASO 1: Estado post-reset
        // ---------------------------------------------------------------------
        base = rx_count;
        #(FRAME_NS);
        check_value(tx,  1'b1,  "Caso 1a (post-reset: tx en reposo)");
        check_value(led, 11'h0, "Caso 1b (post-reset: LEDs apagados)");
        check_rx(base, 0, 32'h0, "Caso 1c (post-reset: no sale nada por tx)");

        // ---------------------------------------------------------------------
        // CASO 2: A y B sin Op -> la ALU no está habilitada, no hay respuesta
        // ---------------------------------------------------------------------
        base = rx_count;
        send_cmd(ADDR_A, 8'h05);
        send_cmd(ADDR_B, 8'h03);
        #(RESP_WAIT);
        check_rx(base, 0, 32'h0, "Caso 2a (A y B sin Op: no responde)");
        check_value(dut.reg_a_out, 8'h05, "Caso 2b (registro A cargado)");
        check_value(dut.reg_b_out, 8'h03, "Caso 2c (registro B cargado)");

        // ---------------------------------------------------------------------
        // CASO 3: Op = ADD -> se habilita y responde 5 + 3
        // ---------------------------------------------------------------------
        base = rx_count;
        send_cmd(ADDR_OP, OP_ADD);
        #(RESP_WAIT);
        check_rx(base, 2, {8'h08, 8'h00, 16'h0}, "Caso 3a (Op=ADD: 5 + 3)");
        check_value(led, {1'b0, 1'b0, 1'b0, 8'h08}, "Caso 3b (LEDs muestran el resultado)");

        // ---------------------------------------------------------------------
        // CASO 4: Overflow con signo -> 5 + 127 satura en 0x7F
        // ---------------------------------------------------------------------
        base = rx_count;
        send_cmd(ADDR_B, 8'h7F);
        #(RESP_WAIT);
        check_rx(base, 2, {8'h7F, 8'h02, 16'h0}, "Caso 4a (5 + 127: overflow, status 0x02)");
        check_value(led, {1'b0, 1'b1, 1'b0, 8'h7F}, "Caso 4b (LED de overflow encendido)");

        // ---------------------------------------------------------------------
        // CASO 5: Cambio de opcode -> SUB
        // ---------------------------------------------------------------------
        base = rx_count;
        send_cmd(ADDR_OP, OP_SUB);
        #(RESP_WAIT);
        check_rx(base, 2, {8'h86, 8'h00, 16'h0}, "Caso 5 (Op=SUB: 5 - 127 = 0x86)");

        // ---------------------------------------------------------------------
        // CASO 6: Mismo valor otra vez -> no hay respuesta (la GUI usa timeout)
        // ---------------------------------------------------------------------
        base = rx_count;
        send_cmd(ADDR_A, 8'h05);
        #(RESP_WAIT);
        check_rx(base, 0, 32'h0, "Caso 6 (A=5 otra vez: no responde)");

        // ---------------------------------------------------------------------
        // CASO 7: Dirección inválida y después un comando válido
        // ---------------------------------------------------------------------
        base = rx_count;
        send_cmd(8'h07, 8'hFF);
        #(RESP_WAIT);
        check_rx(base, 0, 32'h0, "Caso 7a (direccion 0x07: se descarta)");
        check_value({dut.reg_a_out, dut.reg_b_out, 2'b00, dut.reg_op_out}, {8'h05, 8'h7F, 2'b00, OP_SUB[5:0]},
                    "Caso 7b (registros sin cambios: A, B, Op)");

        base = rx_count;
        send_cmd(ADDR_A, 8'h0A);
        #(RESP_WAIT);
        check_rx(base, 2, {8'h8B, 8'h00, 16'h0}, "Caso 7c (comando siguiente bien: 10 - 127 = 0x8B)");

        // ---------------------------------------------------------------------
        // CASO 8: Carry sin signo -> 0xFF + 0x01 = 0x00 con carry
        // ---------------------------------------------------------------------
        base = rx_count;
        send_cmd(ADDR_A, 8'hFF);
        send_cmd(ADDR_B, 8'h01);
        send_cmd(ADDR_OP, OP_ADD);
        #(2 * RESP_WAIT);
        if (rx_count - base >= 2) begin
            base = rx_count - 2; // Solo importa la última respuesta
            check_rx(base, 2, {8'h00, 8'h01, 16'h0}, "Caso 8 (0xFF + 0x01: carry, status 0x01)");
        end else begin
            check_rx(base, 2, {8'h00, 8'h01, 16'h0}, "Caso 8 (0xFF + 0x01: carry, status 0x01)");
        end

        // ---------------------------------------------------------------------
        // CASO 9: Comandos seguidos sin pausa (como los manda la GUI)
        // A=0x10, B=0x20, Op=ADD -> final 0x30. Las respuestas se cruzan con los
        // comandos que siguen entrando: tienen que llegar en pares completos y
        // la última tiene que ser la cuenta final.
        // ---------------------------------------------------------------------
        base = rx_count;
        send_cmd(ADDR_A, 8'h10);
        send_cmd(ADDR_B, 8'h20);
        send_cmd(ADDR_OP, OP_ADD);
        #(2 * RESP_WAIT);

        if ((rx_count - base) % 2 != 0 || rx_count - base < 2) begin
            $display("[FAIL] Caso 9a -> llegaron %0d byte(s): se esperaban pares completos", rx_count - base);
            errors = errors + 1;
        end else begin
            $display("[OK]   Caso 9a (comandos seguidos: %0d respuesta(s) en pares completos)", (rx_count - base) / 2);
            // Cada par tiene que ser una cuenta real por la que pasó la ALU:
            // A=0x10 (0x10+0x01=0x11), B=0x20 (0x10+0x20=0x30) con Op=ADD
            pairs_ok = 1;
            for (i = base; i < rx_count; i = i + 2)
                if (!((rx_bytes[i] == 8'h11 || rx_bytes[i] == 8'h30) && rx_bytes[i + 1] == 8'h00))
                    pairs_ok = 0;
            if (pairs_ok) begin
                $display("[OK]   Caso 9b (cada par es una cuenta valida: resultado y status de la misma cuenta)");
            end else begin
                $display("[FAIL] Caso 9b -> algun par no corresponde a una cuenta real");
                errors = errors + 1;
            end
            check_rx(rx_count - 2, 2, {8'h30, 8'h00, 16'h0}, "Caso 9c (ultima respuesta = cuenta final 0x10 + 0x20)");
        end

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
