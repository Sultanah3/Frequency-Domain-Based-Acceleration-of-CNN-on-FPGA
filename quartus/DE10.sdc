# 50 MHz board clock; the SDRAM PLL and the HPS clocks are derived from it.
create_clock -period 20.0 [get_ports CLOCK_50]

# JTAG (USB-Blaster II)
create_clock -name {altera_reserved_tck} -period 40 {altera_reserved_tck}
set_input_delay -clock altera_reserved_tck -clock_fall 3 [get_ports altera_reserved_tdi]
set_input_delay -clock altera_reserved_tck -clock_fall 3 [get_ports altera_reserved_tms]
set_output_delay -clock altera_reserved_tck 3 [get_ports altera_reserved_tdo]

derive_pll_clocks
derive_clock_uncertainty
