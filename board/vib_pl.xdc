# ============================================================
#  vib_pl.xdc  —— 正点原子 ZYNQ7020 最小系统板
#
#  引脚来源：系统板原理图.pdf
#    clk       U18   IO_L12P_T1_MRCC_34   50 MHz 有源晶振
#    rst_n     J15   IO_25_35J15          复位按键（低有效）
#    led       G14   IO_0_35G14
#
#  ⚠️ 串口：板载 CH340C 接在 PS 的 MIO14/MIO15（UART_RXD/UART_TXD），
#     纯 PL 设计用不了，必须外接 USB-TTL 模块，接到 J8 排针：
#
#        J8-16  B13_L11P  → U7   接 USB-TTL 的 TXD
#        J8-18  B13_L11N  → V7   接 USB-TTL 的 RXD
#        排针上的 GND     →    接 USB-TTL 的 GND
#        （模块电平选 3.3V）
#
#     bank 13 供电 3.3V，故 IOSTANDARD 用 LVCMOS33。
#     这两个网络在原理图上只连 FPGA 与排针，无其它外设占用。
# ============================================================

# ---------------- 时钟 ----------------
create_clock -name sys_clk -period 20.000 [get_ports clk]

set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports clk]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports rst_n]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports led]

# ---------------- 串口（外接 USB-TTL，J8 排针）----------------
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports uart_rx_pin]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33} [get_ports uart_tx_pin]

# ---------------- 异步输入 ----------------
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports uart_rx_pin]
