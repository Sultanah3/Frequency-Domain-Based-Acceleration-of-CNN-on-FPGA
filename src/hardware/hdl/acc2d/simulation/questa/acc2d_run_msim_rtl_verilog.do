transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog  -work work +incdir+D:/fpga_projects/Frequency-Domain-Based-Acceleration-of-CNN-on-FPGA/src/hardware/hdl/acc2d {D:/fpga_projects/Frequency-Domain-Based-Acceleration-of-CNN-on-FPGA/src/hardware/hdl/acc2d/acc2d.v}

