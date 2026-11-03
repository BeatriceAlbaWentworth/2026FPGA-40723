# ============================================================
#  program_fpga.tcl —— 一键烧录固件到开发板
#
#  用法（Vivado Tcl Console 里）：
#      cd <本目录>
#      source program_fpga.tcl
#
#  或在命令行：
#      vivado -mode batch -source program_fpga.tcl
#
#  前提：开发板已上电，USB-C 接 UART_JTAG 口，JTAG 驱动已安装
# ============================================================

set here [file dirname [file normalize [info script]]]
set bitfile [file join $here top_full.bit]

if {![file exists $bitfile]} {
    error "找不到固件：$bitfile"
}

puts "INFO: 打开硬件管理器..."
open_hw_manager

puts "INFO: 连接 hw_server..."
connect_hw_server

puts "INFO: 打开目标..."
set targets [get_hw_targets]
if {[llength $targets] == 0} {
    error "没有检测到 JTAG 目标。请检查：1) 板子是否上电 2) USB 是否插在 UART_JTAG 口 3) 驱动是否安装"
}
current_hw_target [lindex $targets 0]
open_hw_target

puts "INFO: 选择器件..."
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

puts "INFO: 烧录 $bitfile ..."
set_property PROGRAM.FILE $bitfile $dev
program_hw_devices $dev

puts "INFO: 完成。"
puts "  - DONE 灯应点亮"
puts "  - PL_LED 待机时为灭，收到数据才会亮（这是正常状态）"
