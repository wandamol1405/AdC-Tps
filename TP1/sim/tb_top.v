`timescale 1ns / 1ps

// Testbench de sistema completo: switches + botones (con antirrebote real) ->
// bancos de registros -> ALU -> leds. Se instancia "top" con un N_DEBOUNCE
// reducido (solo para simulacion) para no tener que esperar los ~21ms reales
// del antirrebote de hardware; en la sintesis real "top" sigue usando su
// default (20) ya que aca solo se sobreescribe el parametro de esta instancia.
module tb_top;

    localparam NB_DATA = 8;
    localparam NB_OP   = 6;
    localparam NB_SW   = 8;
    localparam N_DEBOUNCE_SIM = 4; // 2^4-1 = 15 ciclos de estabilidad para confirmar un flanco
    localparam NB_LED  = NB_DATA + 3; // resultado + 1 led apagado (separador) + overflow + carry

    localparam BTN_A  = 0; // btnL
    localparam BTN_B  = 1; // btnC
    localparam BTN_OP = 2; // btnR

    // Opcodes (deben coincidir con los definidos en ALU.v)
    localparam [NB_OP-1:0] ADD    = 6'b100000;
    localparam [NB_OP-1:0] SUB    = 6'b100010;
    localparam [NB_OP-1:0] SRA    = 6'b000011;
    localparam [NB_OP-1:0] SRL    = 6'b000010;
    localparam [NB_OP-1:0] NOR_OP = 6'b100111;

    reg                 clk;
    reg                 reset;
    reg  [NB_SW-1:0]    sw;
    reg                 btnL, btnC, btnR;
    wire [NB_LED-1:0]   led;

    integer casos, errores;
    integer tick_a_count, tick_b_count, tick_op_count;

    top #(
        .NB_DATA(NB_DATA),
        .NB_OP(NB_OP),
        .NB_SW(NB_SW),
        .N_DEBOUNCE(N_DEBOUNCE_SIM)
    ) dut (
        .clk(clk),
        .reset(reset),
        .sw(sw),
        .btnL(btnL),
        .btnC(btnC),
        .btnR(btnR),
        .led(led)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk; // 100MHz de referencia (el periodo no es critico para la funcionalidad)

    // ---- Sondas jerarquicas: solo para loguear/verificar el funcionamiento interno del antirrebote ----
    always @(posedge clk) begin
        if (dut.u_load_ctrl.tick_a) begin
            tick_a_count = tick_a_count + 1;
            $display("    [DEBOUNCE] tick_a  #%0d confirmado en t=%0t", tick_a_count, $time);
        end
        if (dut.u_load_ctrl.tick_b) begin
            tick_b_count = tick_b_count + 1;
            $display("    [DEBOUNCE] tick_b  #%0d confirmado en t=%0t", tick_b_count, $time);
        end
        if (dut.u_load_ctrl.tick_op) begin
            tick_op_count = tick_op_count + 1;
            $display("    [DEBOUNCE] tick_op #%0d confirmado en t=%0t", tick_op_count, $time);
        end
    end

    function [8*8-1:0] state_name;
        input [1:0] st;
        begin
            case (st)
                2'b00:   state_name = "WAIT_A";
                2'b01:   state_name = "WAIT_B";
                2'b10:   state_name = "WAIT_OP";
                2'b11:   state_name = "ENABLE";
                default: state_name = "??????";
            endcase
        end
    endfunction

    // -------------------- Tareas --------------------

    task do_reset;
        begin
            reset = 1'b1;
            btnL = 1'b0; btnC = 1'b0; btnR = 1'b0; sw = {NB_SW{1'b0}};
            repeat (3) @(posedge clk);
            reset = 1'b0;
            @(posedge clk);
        end
    endtask

    // Los botones se seleccionan por indice en vez de pasarse por
    // referencia: en Verilog, un argumento de tarea "inout"/"output" solo se
    // copia de vuelta a la señal real al FINALIZAR la tarea, no en cada
    // asignacion intermedia. Como estas tareas esperan varios ciclos de reloj
    // en el medio, pasar btnL/btnC/btnR como "inout" nunca los mueve de
    // verdad durante la espera; por eso se referencian los regs del testbench
    // directamente a traves de este selector.
    task set_btn;
        input integer which; // 0=A(btnL), 1=B(btnC), 2=OP(btnR)
        input value;
        begin
            case (which)
                0: btnL = value;
                1: btnC = value;
                2: btnR = value;
            endcase
        end
    endtask

    // Presiona y suelta limpiamente (sin rebote), sosteniendo cada flanco el
    // tiempo suficiente para que el antirrebote lo confirme.
    task press_clean;
        input integer which;
        input integer hold_cycles;
        begin
            set_btn(which, 1'b1);
            repeat (hold_cycles) @(posedge clk);
            set_btn(which, 1'b0);
            repeat (hold_cycles) @(posedge clk);
        end
    endtask

    // Simula un boton que rebota: varios pulsos cortos (menores al conteo de
    // antirrebote, por lo tanto deben ser ignorados) antes de asentarse en 1
    // el tiempo suficiente como para confirmar el flanco real.
    task bounce_press;
        input integer which;
        input integer n_glitches;
        input integer glitch_cycles;
        input integer settle_cycles;
        integer i;
        begin
            for (i = 0; i < n_glitches; i = i + 1) begin
                set_btn(which, 1'b1);
                repeat (glitch_cycles) @(posedge clk);
                set_btn(which, 1'b0);
                repeat (glitch_cycles) @(posedge clk);
            end
            set_btn(which, 1'b1);
            repeat (settle_cycles) @(posedge clk);
            set_btn(which, 1'b0);
            repeat (settle_cycles) @(posedge clk);
        end
    endtask

    // Carga A, B y OP con presiones limpias y compara el resultado final contra los leds
    task run_case;
        input [127:0] nombre;
        input signed [NB_DATA-1:0] a;
        input signed [NB_DATA-1:0] b;
        input [NB_OP-1:0] op;
        input [NB_DATA-1:0] esperado_result;
        input esperado_overflow;
        input esperado_carry;
        reg [NB_LED-1:0] esperado_led;
        begin
            do_reset;

            sw = a;
            press_clean(BTN_A, 25); // > 2^N_DEBOUNCE_SIM ciclos: asegura confirmar el flanco
            sw = b;
            press_clean(BTN_B, 25);
            sw = op;
            press_clean(BTN_OP, 25);
            @(posedge clk);

            casos = casos + 1;
            esperado_led = {esperado_carry, esperado_overflow, 1'b0, esperado_result};

            if (led !== esperado_led) begin
                errores = errores + 1;
                $display("[FALLO] %-8s a=%0d b=%0d op=%b -> result=%0d(0x%0h) ov=%b ca=%b | esperado result=%0d(0x%0h) ov=%b ca=%b",
                    nombre, a, b, op, led[NB_DATA-1:0], led[NB_DATA-1:0], led[NB_DATA+1], led[NB_DATA+2],
                    esperado_result, esperado_result, esperado_overflow, esperado_carry);
            end else begin
                $display("[OK]    %-8s a=%0d b=%0d op=%b -> result=%0d(0x%0h) ov=%b ca=%b",
                    nombre, a, b, op, led[NB_DATA-1:0], led[NB_DATA-1:0], led[NB_DATA+1], led[NB_DATA+2]);
            end
        end
    endtask

    initial begin
        casos = 0; errores = 0;
        tick_a_count = 0; tick_b_count = 0; tick_op_count = 0;

        $display("========================================================");
        $display(" Testbench de sistema completo (top) - N_DEBOUNCE(sim)=%0d", N_DEBOUNCE_SIM);
        $display("========================================================");

        // ---------------- Datapath completo: switches -> registros -> ALU -> leds ----------------
        run_case("ADD",     8'sd10,        8'sd20,  ADD,    8'd30,          1'b0, 1'b0);
        run_case("ADD-OVP", 8'sd127,       8'sd1,   ADD,    8'sd127,        1'b1, 1'b0); // satura positivo
        run_case("ADD-OVN", -8'sd128,      -8'sd128,ADD,    -8'sd128,       1'b1, 1'b1); // satura negativo, con carry
        run_case("ADD-CA",  -8'sd1,        8'sd1,   ADD,    8'd0,           1'b0, 1'b1); // carry sin overflow
        run_case("SUB",     8'sd10,        8'sd20,  SUB,    -8'sd10,        1'b0, 1'b0);
        run_case("SRA",     8'sb1000_0000, 8'sd2,   SRA,    8'sb1110_0000,  1'b0, 1'b0); // extiende signo
        run_case("SRL",     8'sb1000_0000, 8'sd2,   SRL,    8'b0010_0000,   1'b0, 1'b0); // no extiende signo
        run_case("NOR",     8'h00,         8'h00,   NOR_OP, 8'hFF,          1'b0, 1'b0);

        // ---------------- Registros latcheados: mover los switches tras ENABLE no debe alterar el resultado ----------------
        $display("--------------------------------------------------------");
        $display(" Verificando que A/B/OP queden latcheados una vez en ENABLE");
        sw = 8'h55; // valor bien distinto al ultimo resultado (0xFF), para detectar si "se cuela"
        @(posedge clk);
        casos = casos + 1;
        if (led[NB_DATA-1:0] === 8'hFF) begin
            $display("[OK]    LATCH    mover sw a 0x55 no afecta el resultado ya cargado (result=0x%0h)", led[NB_DATA-1:0]);
        end else begin
            errores = errores + 1;
            $display("[FALLO] LATCH    el resultado cambio al mover los switches: result=0x%0h (esperado 0xFF)", led[NB_DATA-1:0]);
        end

        // ---------------- Funcionamiento del antirrebote ----------------
        $display("--------------------------------------------------------");
        $display(" Probando filtrado de rebotes en btnL");
        do_reset;
        sw = 8'd42;
        tick_a_count = 0;
        // 4 rebotes cortos (5 ciclos, muy por debajo de los ~15 necesarios) + asentamiento largo
        bounce_press(BTN_A, 4, 5, 30);
        @(posedge clk);
        casos = casos + 1;
        if (tick_a_count == 1 && dut.reg_a_out === 8'd42 && dut.u_load_ctrl.state_reg == 2'b01) begin
            $display("[OK]    BOUNCE   4 rebotes filtrados, 1 solo tick_a, A=%0d, estado=%s",
                dut.reg_a_out, state_name(dut.u_load_ctrl.state_reg));
        end else begin
            errores = errores + 1;
            $display("[FALLO] BOUNCE   tick_a_count=%0d (esperado 1), A=%0d (esperado 42), estado=%s",
                tick_a_count, dut.reg_a_out, state_name(dut.u_load_ctrl.state_reg));
        end

        $display(" Probando que un pulso mas corto que el antirrebote NO dispare el tick");
        tick_a_count = 0;
        btnL = 1'b1;
        repeat (5) @(posedge clk);  // menos que los ~15 ciclos necesarios para confirmar
        btnL = 1'b0;
        repeat (20) @(posedge clk); // tiempo de sobra para confirmar que NO hubo tick
        casos = casos + 1;
        if (tick_a_count == 0) begin
            $display("[OK]    BOUNCE   pulso corto (5 ciclos) correctamente ignorado, sin tick_a");
        end else begin
            errores = errores + 1;
            $display("[FALLO] BOUNCE   pulso corto genero tick_a inesperadamente (count=%0d)", tick_a_count);
        end

        // ---------------- Reset a mitad de la secuencia de carga ----------------
        $display("--------------------------------------------------------");
        $display(" Probando reset a mitad de la secuencia de carga (antes de completar B y OP)");
        do_reset;
        sw = 8'd5;
        press_clean(BTN_A, 25); // cargo A, quedo en WAIT_B
        casos = casos + 1;
        if (dut.u_load_ctrl.state_reg == 2'b01) begin
            $display("[OK]    MIDSEQ   tras cargar A, estado=%s", state_name(dut.u_load_ctrl.state_reg));
        end else begin
            errores = errores + 1;
            $display("[FALLO] MIDSEQ   estado inesperado tras cargar A: %s", state_name(dut.u_load_ctrl.state_reg));
        end

        do_reset; // interrumpo antes de cargar B
        casos = casos + 1;
        if (dut.u_load_ctrl.state_reg == 2'b00 && led == {NB_LED{1'b0}}) begin
            $display("[OK]    MIDSEQ   reset a mitad de secuencia vuelve a WAIT_A y led=0");
        end else begin
            errores = errores + 1;
            $display("[FALLO] MIDSEQ   tras reset, estado=%s led=%b (esperado WAIT_A y led=0)",
                state_name(dut.u_load_ctrl.state_reg), led);
        end

        $display("========================================================");
        if (errores == 0)
            $display(" RESULTADO: TODOS LOS CASOS PASARON (%0d/%0d)", casos, casos);
        else
            $display(" RESULTADO: %0d FALLOS DE %0d CASOS", errores, casos);
        $display("========================================================");

        $finish;
    end

endmodule
