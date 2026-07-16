##############################################################################
#  run_fifo_async.do  -- Asynchronous FIFO GUI demo (iki clock domain)
#
#  KULLANIM:
#     cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/MyLibs/sim}
#     do run_fifo_async.do
#
#  GORULECEKLER:
#     - Iki iliskisiz clock (wr_clk=100MHz, rd_clk=~71MHz)
#     - Write domain gray pointer -> 2-FF -> read domain (ve tersi)
#     - Veri bütünlügü: yazilan degerler ayni sirada okunur
#     - full/empty flag'leri CDC'ye ragmen tutarli
##############################################################################
if {[file exists work]} { vdel -all }
vlib work

vcom -2008 ../gray_pkg.vhd
vcom -2008 ../synchronizer.vhd
vcom -2008 ../fifo_async.vhd
vcom -2008 tb_fifo_async.vhd

vsim -t 1ps -voptargs="+acc" work.tb_fifo_async

add wave -divider "CLOCK'LAR (iliskisiz domain'ler)"
add wave -label wr_clk  /tb_fifo_async/wr_clk
add wave -label rd_clk  /tb_fifo_async/rd_clk
add wave -label rst_n   /tb_fifo_async/rst_n

add wave -divider "WRITE DOMAIN"
add wave -label wr_en        /tb_fifo_async/wr_en
add wave -hex -label wr_data /tb_fifo_async/wr_data
add wave -label full         /tb_fifo_async/full
add wave -unsigned -label wr_ptr     /tb_fifo_async/u_dut/wr_ptr
add wave -unsigned -label wr_gray    /tb_fifo_async/u_dut/wr_gray

add wave -divider "GRAY POINTER SYNC (2-FF)"
add wave -unsigned -label wr_gray_sync  /tb_fifo_async/u_dut/wr_gray_sync
add wave -unsigned -label rd_gray_sync  /tb_fifo_async/u_dut/rd_gray_sync

add wave -divider "READ DOMAIN"
add wave -label rd_en        /tb_fifo_async/rd_en
add wave -hex -label rd_data /tb_fifo_async/rd_data
add wave -label empty        /tb_fifo_async/empty
add wave -unsigned -label rd_ptr     /tb_fifo_async/u_dut/rd_ptr
add wave -unsigned -label rd_gray    /tb_fifo_async/u_dut/rd_gray

add wave -divider "DOGULAMA"
add wave -unsigned -label check_cnt  /tb_fifo_async/check_cnt

echo "===== BASLA ====="
run 5 us
echo "===== BITIS ====="
wave zoom full
