## Clock 100 MHz
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

## Reset (SW15)
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { rst }];


## Switch SW0: i_data
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { i_data }];

## Buttons
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports { i_valid }];
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports { i_enable_load }];

## LEDs LD0-LD7: muestran el ultimo byte recibido por UART
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { o_led[0] }];
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports { o_led[1] }];
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { o_led[2] }];
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports { o_led[3] }];

