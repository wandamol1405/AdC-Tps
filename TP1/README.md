```========================================================
 Testbench de sistema completo (top) - N_DEBOUNCE(sim)=4
========================================================
    [DEBOUNCE] tick_a  #1 confirmado en t=195000
    [DEBOUNCE] tick_b  #1 confirmado en t=695000
    [DEBOUNCE] tick_op #1 confirmado en t=1195000
[OK]                 ADD a=10 b=20 op=100000 -> result=30(0x1e) ov=0 ca=0
    [DEBOUNCE] tick_a  #2 confirmado en t=1745000
    [DEBOUNCE] tick_b  #2 confirmado en t=2245000
    [DEBOUNCE] tick_op #2 confirmado en t=2745000
[OK]             ADD-OVP a=127 b=1 op=100000 -> result=127(0x7f) ov=1 ca=0
    [DEBOUNCE] tick_a  #3 confirmado en t=3295000
    [DEBOUNCE] tick_b  #3 confirmado en t=3795000
    [DEBOUNCE] tick_op #3 confirmado en t=4295000
[OK]             ADD-OVN a=-128 b=-128 op=100000 -> result=128(0x80) ov=1 ca=1
    [DEBOUNCE] tick_a  #4 confirmado en t=4845000
    [DEBOUNCE] tick_b  #4 confirmado en t=5345000
    [DEBOUNCE] tick_op #4 confirmado en t=5845000
[OK]              ADD-CA a=-1 b=1 op=100000 -> result=0(0x0) ov=0 ca=1
    [DEBOUNCE] tick_a  #5 confirmado en t=6395000
    [DEBOUNCE] tick_b  #5 confirmado en t=6895000
    [DEBOUNCE] tick_op #5 confirmado en t=7395000
[OK]                 SUB a=10 b=20 op=100010 -> result=246(0xf6) ov=0 ca=0
    [DEBOUNCE] tick_a  #6 confirmado en t=7945000
    [DEBOUNCE] tick_b  #6 confirmado en t=8445000
    [DEBOUNCE] tick_op #6 confirmado en t=8945000
[OK]                 SRA a=-128 b=2 op=000011 -> result=224(0xe0) ov=0 ca=0
    [DEBOUNCE] tick_a  #7 confirmado en t=9495000
    [DEBOUNCE] tick_b  #7 confirmado en t=9995000
    [DEBOUNCE] tick_op #7 confirmado en t=10495000
[OK]                 SRL a=-128 b=2 op=000010 -> result=32(0x20) ov=0 ca=0
    [DEBOUNCE] tick_a  #8 confirmado en t=11045000
    [DEBOUNCE] tick_b  #8 confirmado en t=11545000
    [DEBOUNCE] tick_op #8 confirmado en t=12045000
[OK]                 NOR a=0 b=0 op=100111 -> result=255(0xff) ov=0 ca=0
--------------------------------------------------------
 Verificando que A/B/OP queden latcheados una vez en ENABLE
[OK]    LATCH    mover sw a 0x55 no afecta el resultado ya cargado (result=0xff)
--------------------------------------------------------
 Probando filtrado de rebotes en btnL
    [DEBOUNCE] tick_a  #1 confirmado en t=13005000
[OK]    BOUNCE   4 rebotes filtrados, 1 solo tick_a, A=42, estado=  WAIT_B
 Probando que un pulso mas corto que el antirrebote NO dispare el tick
[OK]    BOUNCE   pulso corto (5 ciclos) correctamente ignorado, sin tick_a
--------------------------------------------------------
 Probando reset a mitad de la secuencia de carga (antes de completar B y OP)
    [DEBOUNCE] tick_a  #1 confirmado en t=13905000
[OK]    MIDSEQ   tras cargar A, estado=  WAIT_B
[OK]    MIDSEQ   reset a mitad de secuencia vuelve a WAIT_A y led=0
--------------------------------------------------------
 Probando el boton de limpieza (clean): no debe borrar A/B/OP ya cargados
    [DEBOUNCE] tick_a  #2 confirmado en t=14485000
    [DEBOUNCE] tick_b  #9 confirmado en t=14985000
    [DEBOUNCE] tick_op #9 confirmado en t=15485000
[OK]    CLEAN-PRE  15+5=20 cargado y habilitado antes de limpiar
[OK]    CLEAN    vuelve a WAIT_A, led=0, pero A=15 B=5 OP=100000 siguen intactos
    [DEBOUNCE] tick_a  #3 confirmado en t=16495000
    [DEBOUNCE] tick_b  #10 confirmado en t=16995000
    [DEBOUNCE] tick_op #10 confirmado en t=17495000
[OK]    CLEAN-POST tras clean, nueva operacion SUB reutilizando A/B: 15-5=10
========================================================
 RESULTADO: TODOS LOS CASOS PASARON (16/16)
========================================================
$finish called at time : 17845 ns : File "/home/wanda/Documentos/Facultad/AdC/AdC-Tps/TP1/sim/tb_top.v" Line 335
```
