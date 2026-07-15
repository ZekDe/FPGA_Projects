##############################################################################
#  run_gui.do  -- pipelined divider testi (Questa GUI)
#
#  KULLANIM:
#     Questa GUI Transcript:
#        cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/MyLibs/sim}
#        do run_gui.do
##############################################################################

# Kutuphane yolu (sim klasoru -> MyLibs bir üstte)
set LIB ..

# Temiz baslangic
if {[file exists work]} { vdel -all }
vlib work

# Derle
vcom -2008 $LIB/divider_pipelined.vhd
vcom -2008 tb_divider_pipelined.vhd

# Simulasyonu baslat (-voptargs=+acc ile internal sinyaller gorunsun)
vsim -voptargs=+acc work.tb_divider_pipelined

# ===========================================================================
# DALGA PENCERESI
# ===========================================================================

add wave -divider "UYARANLAR"
add wave -label clk       /tb_divider_pipelined/clk
add wave -label rst_n     /tb_divider_pipelined/rst_n
add wave -label start     /tb_divider_pipelined/start
add wave -unsigned -label dividend  /tb_divider_pipelined/dividend
add wave -unsigned -label divisor   /tb_divider_pipelined/divisor

add wave -divider "CIKISLAR"
add wave -label valid     /tb_divider_pipelined/valid
add wave -unsigned -label quotient  /tb_divider_pipelined/quotient
add wave -unsigned -label remainder /tb_divider_pipelined/remainder

add wave -divider "PIPELINE INTERNALS (ilk ve son stage)"
add wave -unsigned -label "pipe_a(0)"   /tb_divider_pipelined/dut/pipe_a(0)
add wave -unsigned -label "pipe_a(31)"  /tb_divider_pipelined/dut/pipe_a(31)
add wave -unsigned -label "pipe_b(0)"   /tb_divider_pipelined/dut/pipe_b(0)
add wave -unsigned -label "pipe_q(31)"  /tb_divider_pipelined/dut/pipe_q(31)
add wave -unsigned -label "pipe_r(31)"  /tb_divider_pipelined/dut/pipe_r(31)
add wave -label "pipe_valid(0)"  /tb_divider_pipelined/dut/pipe_valid(0)
add wave -label "pipe_valid(31)" /tb_divider_pipelined/dut/pipe_valid(31)

# ===========================================================================
# CALISTIR
# ===========================================================================
# 5 test senaryosu + back-to-back ~5 us icinde bitiyor.
run 5 us
wave zoom full
