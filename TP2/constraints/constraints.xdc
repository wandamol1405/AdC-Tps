## Constraints del TP2 (top.v): ALU manejada solo por UART, placa Basys3

## Clock 100 MHz
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

## Reset (btnD, igual que en el TP1)
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { reset }];

## UART por el puerto USB (USB-RS232 en Basys3_Master.xdc)
## rx: entra desde la PC (RsRx) · tx: sale hacia la PC (RsTx)
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports { rx }];
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { tx }];

## LEDs LD0-LD7: resultado de la ALU
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports { led[4] }];
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports { led[5] }];
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { led[6] }];
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { led[7] }];

## LD8: apagado a proposito, separa el resultado de las banderas
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports { led[8] }];
## LD9: overflow con signo (ADD saturado)
set_property -dict { PACKAGE_PIN V3 IOSTANDARD LVCMOS33 } [get_ports { led[9] }];
## LD10: carry de salida sin signo (ADD)
set_property -dict { PACKAGE_PIN W3 IOSTANDARD LVCMOS33 } [get_ports { led[10] }];
