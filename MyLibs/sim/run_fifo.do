##############################################################################
#  run_fifo.do  -- Sync FIFO GUI demo
#
#  KULLANIM:
#     cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/MyLibs/sim}
#     do run_fifo.do
#
#  GORULECEKLER:
#     - 3 eleman yazilir, sirayla okunur (AA00, AA01, AA02)
#     - 16 eleman yazilir, full flag kalkar
#     - 16 eleman okunur, empty flag kalkar
#     - wr_ptr ve rd_ptr N+1 bit hareketini gorebilirsin (tur biti)
##############################################################################
if {[file exists work]} { vdel -all }
vlib work

vcom -2008 ../fifo_sync.vhd
vcom -2008 tb_fifo_sync.vhd

vsim -t 1ps -voptargs="+acc" work.tb_fifo_sync

add wave -divider "UYARANLAR"
add wave -label clk      /tb_fifo_sync/clk
add wave -label rst_n    /tb_fifo_sync/rst_n
add wave -label wr_en    /tb_fifo_sync/wr_en
add wave -hex -label wr_data  /tb_fifo_sync/wr_data
add wave -label rd_en    /tb_fifo_sync/rd_en

add wave -divider "DUT IC: RAM + POINTER'LAR"
add wave -hex -label wr_ptr     /tb_fifo_sync/u_dut/wr_ptr
add wave -hex -label rd_ptr     /tb_fifo_sync/u_dut/rd_ptr
add wave -hex -label "ram(0)"   /tb_fifo_sync/u_dut/ram(0)
add wave -hex -label "ram(1)"   /tb_fifo_sync/u_dut/ram(1)
add wave -hex -label "ram(2)"   /tb_fifo_sync/u_dut/ram(2)

add wave -divider "CIKISLAR"
add wave -hex -label rd_data  /tb_fifo_sync/rd_data
add wave -label full          /tb_fifo_sync/full
add wave -label empty         /tb_fifo_sync/empty

add wave -divider "SAYACLAR"
add wave -unsigned -label check_cnt  /tb_fifo_sync/check_cnt

echo "===== BASLA ====="
run 1 us
echo "===== BITIS ====="
wave zoom full
