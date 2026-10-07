`timescale 1ns / 1ps

// =============================================================================
// TESTBENCH: tb_result_sender.v
//
// ¿QUE HACE ESTE TESTBENCH?
// Prueba result_sender conectado a la cadena real de salida:
//
//   ALU (simulada) -> result_sender -> interface_tx -> uart_tx --tx--> uart_rx
//
// uart_rx hace de "PC": decodifica lo que sale por el cable y guarda cada byte
// recibido en rx_bytes[]. Así se verifica de punta a punta que los bytes que
// llegan son los correctos y en el orden correcto.
//
// Para que la simulación sea rápida, i_tick se deja fijo en 1 (un tick por
// ciclo de clock): cada trama dura 10 bits x 16 ticks = 160 ciclos.
//
// CHEQUEO CONTINUO (en todos los ciclos):
// - Nunca se pulsa o_wr con tx_full = 1 (la regla de la "banderita").
//
// CASOS QUE VERIFICA:
// - Caso 1: Con i_enable_alu = 0 la ALU cambia varias veces -> no se manda nada.
// - Caso 2: Sube i_enable_alu con resultado 0x00 -> se manda igual (primer envío).
// - Caso 3: Cambia el resultado a 0x08 -> llegan 0x08 y status 0x00.
// - Caso 4: Se repite el mismo valor -> no se manda nada.
// - Caso 5: Overflow y carry en 1 (0x80) -> llegan 0x80 y status 0x03.
// - Caso 6: Solo cambia el carry -> se detecta el cambio y llegan 0x80, 0x02.
// - Caso 7: La ALU cambia a mitad del envío -> los 2 bytes son de la misma
//           cuenta (foto) y después se manda la cuenta nueva.
// - Caso 8: Varios cambios durante la transmisión -> al final se manda solo el
//           último valor (los intermedios se descartan).
// - Caso 9: Reset a mitad de un envío -> vuelve a IDLE limpio y no manda nada
//           hasta que i_enable_alu vuelve a 1.
// =============================================================================

module tb_result_sender;

    parameter D_BIT = 8;
    localparam FRAME_CYCLES = 10 * 16;       // Duración de una trama con tick en cada ciclo
    localparam SETTLE       = 4 * FRAME_CYCLES; // Margen para que terminen 2 bytes (y sobre)

    // -------------------------------------------------------------------------
    // Señales
    // -------------------------------------------------------------------------
    reg              clk;
    reg              reset;

    // "ALU" simulada
    reg  [D_BIT-1:0] alu_result;
    reg              alu_overflow;
    reg              alu_carry;
    reg              enable_alu;

    // result_sender <-> interface_tx
    wire [D_BIT-1:0] w_data;
    wire             wr;
    wire             tx_full;

    // interface_tx <-> uart_tx
    wire [D_BIT-1:0] d_in;
    wire             tx_start;
    wire             tx_done;

    // Línea serie y receptor ("PC")
    wire             tx_line;
    wire [D_BIT-1:0] rx_data;
    wire             rx_done;

    integer errors;

    // -------------------------------------------------------------------------
    // Instancias
    // -------------------------------------------------------------------------
    result_sender #(.D_BIT(D_BIT)) dut (
        .clk(clk),
        .reset(reset),
        .i_result(alu_result),
        .i_overflow(alu_overflow),
        .i_carry(alu_carry),
        .i_enable_alu(enable_alu),
        .i_tx_full(tx_full),
        .o_w_data(w_data),
        .o_wr(wr)
    );

    interface_tx #(.D_BIT(D_BIT)) u_itx (
        .clk(clk),
        .reset(reset),
        .i_w_data(w_data),
        .i_wr(wr),
        .o_tx_full(tx_full),
        .i_tx_done(tx_done),
        .o_d_in(d_in),
        .o_tx_start(tx_start)
    );

    uart_tx #(.D_BIT(D_BIT)) u_utx (
        .clk(clk),
        .reset(reset),
        .d_in(d_in),
        .tx_start(tx_start),
        .i_tick(1'b1),
        .tx(tx_line),
        .tx_done(tx_done)
    );

    uart_rx #(.D_BIT(D_BIT)) u_urx (
        .clk(clk),
        .reset(reset),
        .in_rx(tx_line),
        .i_tick(1'b1),
        .o_data(rx_data),
        .o_done_tick(rx_done)
    );

    // Reloj de 100 MHz
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Registro de bytes recibidos por la "PC" y conteo de escrituras
    // -------------------------------------------------------------------------
    reg [D_BIT-1:0] rx_bytes [0:63];
    integer rx_count;
    integer wr_count;

    always @(posedge clk) begin
        if (rx_done) begin
            rx_bytes[rx_count] = rx_data;
            rx_count = rx_count + 1;
        end
        if (!reset && wr) begin
            wr_count = wr_count + 1;
            // Regla de la banderita: nunca escribir con el buzón ocupado
            if (tx_full) begin
                $display("[FAIL] t=%0t: o_wr=1 con tx_full=1 (se pisaria el byte pendiente)", $time);
                errors = errors + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Tareas auxiliares
    // -------------------------------------------------------------------------

    // Cambia la salida de la "ALU" (lejos del flanco, para evitar carreras)
    task set_alu(input [D_BIT-1:0] res, input ovf, input cy);
        begin
            @(negedge clk);
            alu_result   = res;
            alu_overflow = ovf;
            alu_carry    = cy;
        end
    endtask

    // Verifica cuántos bytes llegaron desde 'base' y cuáles fueron.
    // 'expected' trae hasta 4 bytes empaquetados: {b0, b1, b2, b3}.
    task check_rx(
        input integer     base,
        input integer     n,
        input [31:0]      expected,
        input [511:0]     test_name
    );
        integer i;
        reg ok;
        reg [D_BIT-1:0] exp_b;
        begin
            ok = (rx_count - base == n);
            for (i = 0; i < n && ok; i = i + 1) begin
                exp_b = expected[31 - 8*i -: 8];
                if (rx_bytes[base + i] !== exp_b) ok = 0;
            end

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

    // -------------------------------------------------------------------------
    // SECUENCIA PRINCIPAL DE TEST
    // -------------------------------------------------------------------------
    integer base;

    initial begin
        errors       = 0;
        rx_count     = 0;
        wr_count     = 0;
        clk          = 0;
        reset        = 1;
        alu_result   = 8'h00;
        alu_overflow = 1'b0;
        alu_carry    = 1'b0;
        enable_alu   = 1'b0;

        $display("========================================================");
        $display(" Testbench result_sender (D_BIT=%0d)", D_BIT);
        $display(" Cadena: result_sender -> interface_tx -> uart_tx -> uart_rx");
        $display("========================================================");

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // ---------------------------------------------------------------------
        // CASO 1: ALU deshabilitada -> aunque cambie, no se manda nada
        // ---------------------------------------------------------------------
        base = rx_count;
        set_alu(8'h11, 1'b0, 1'b0);
        repeat (20) @(posedge clk);
        set_alu(8'h22, 1'b1, 1'b1);
        repeat (SETTLE) @(posedge clk);
        check_rx(base, 0, 32'h0, "Caso 1 (enable_alu=0: no manda aunque cambie la ALU)");
        if (wr_count != 0) begin
            $display("[FAIL] Caso 1 -> hubo %0d pulso(s) de o_wr con enable_alu=0", wr_count);
            errors = errors + 1;
        end

        // ---------------------------------------------------------------------
        // CASO 2: Se habilita la ALU con resultado 0x00 -> primer envío igual
        // (0x00 coincide con la foto de reset: lo manda gracias a sent_once)
        // ---------------------------------------------------------------------
        base = rx_count;
        set_alu(8'h00, 1'b0, 1'b0);
        @(negedge clk);
        enable_alu = 1'b1;
        repeat (SETTLE) @(posedge clk);
        check_rx(base, 2, {8'h00, 8'h00, 16'h0}, "Caso 2 (primer envio con resultado 0x00)");

        // ---------------------------------------------------------------------
        // CASO 3: Cambia el resultado -> resultado + status
        // ---------------------------------------------------------------------
        base = rx_count;
        set_alu(8'h08, 1'b0, 1'b0);
        repeat (SETTLE) @(posedge clk);
        check_rx(base, 2, {8'h08, 8'h00, 16'h0}, "Caso 3 (cambio a 0x08)");

        // ---------------------------------------------------------------------
        // CASO 4: Mismo valor otra vez -> no se reenvía
        // ---------------------------------------------------------------------
        base = rx_count;
        set_alu(8'h08, 1'b0, 1'b0);
        repeat (SETTLE) @(posedge clk);
        check_rx(base, 0, 32'h0, "Caso 4 (mismo valor: no reenvia)");

        // ---------------------------------------------------------------------
        // CASO 5: Overflow y carry en 1 -> status = 0x03
        // ---------------------------------------------------------------------
        base = rx_count;
        set_alu(8'h80, 1'b1, 1'b1);
        repeat (SETTLE) @(posedge clk);
        check_rx(base, 2, {8'h80, 8'h03, 16'h0}, "Caso 5 (overflow=1, carry=1 -> status 0x03)");

        // ---------------------------------------------------------------------
        // CASO 6: Solo cambia el carry -> también cuenta como cambio
        // ---------------------------------------------------------------------
        base = rx_count;
        set_alu(8'h80, 1'b1, 1'b0);
        repeat (SETTLE) @(posedge clk);
        check_rx(base, 2, {8'h80, 8'h02, 16'h0}, "Caso 6 (solo cambia carry -> status 0x02)");

        // ---------------------------------------------------------------------
        // CASO 7: La ALU cambia a mitad del envío (la foto)
        // Se manda 0x11/0x01 completo y después 0x22/0x02.
        // ---------------------------------------------------------------------
        base = rx_count;
        set_alu(8'h11, 1'b0, 1'b1);
        wait (wr == 1'b1);           // Sale el byte de resultado
        repeat (40) @(posedge clk);  // A mitad de la trama...
        set_alu(8'h22, 1'b1, 1'b0);  // ...cambia la ALU
        repeat (2 * SETTLE) @(posedge clk);
        check_rx(base, 4, {8'h11, 8'h01, 8'h22, 8'h02}, "Caso 7 (cambio a mitad del envio: foto consistente)");

        // ---------------------------------------------------------------------
        // CASO 8: Varios cambios durante la transmisión -> solo el último
        // ---------------------------------------------------------------------
        base = rx_count;
        set_alu(8'h33, 1'b0, 1'b0);
        wait (wr == 1'b1);
        repeat (30) @(posedge clk);
        set_alu(8'h44, 1'b0, 1'b0);
        repeat (30) @(posedge clk);
        set_alu(8'h55, 1'b0, 1'b0);
        repeat (30) @(posedge clk);
        set_alu(8'h66, 1'b0, 1'b1);
        repeat (2 * SETTLE) @(posedge clk);
        check_rx(base, 4, {8'h33, 8'h00, 8'h66, 8'h01}, "Caso 8 (intermedios 0x44/0x55 descartados)");

        // ---------------------------------------------------------------------
        // CASO 9: Reset a mitad de un envío
        // Tras el reset (con enable_alu=0, como pasaría en top.v porque el
        // sticky también se resetea) no debe salir nada.
        // ---------------------------------------------------------------------
        set_alu(8'h77, 1'b0, 1'b0);
        wait (wr == 1'b1);
        repeat (40) @(posedge clk);
        @(negedge clk);
        reset      = 1'b1;
        enable_alu = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        if (dut.state_reg !== 2'b00 || tx_full !== 1'b0) begin
            $display("[FAIL] Caso 9a -> tras reset: state=%b tx_full=%b (se esperaba IDLE y 0)", dut.state_reg, tx_full);
            errors = errors + 1;
        end else begin
            $display("[OK]   Caso 9a (reset a mitad del envio: vuelve a IDLE y buzon libre)");
        end
        base = rx_count;
        repeat (SETTLE) @(posedge clk);
        check_rx(base, 0, 32'h0, "Caso 9b (tras reset con enable_alu=0: no manda nada)");

        base = rx_count;
        @(negedge clk);
        enable_alu = 1'b1;
        repeat (SETTLE) @(posedge clk);
        check_rx(base, 2, {8'h77, 8'h00, 16'h0}, "Caso 9c (al rehabilitar: primer envio de nuevo)");

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
