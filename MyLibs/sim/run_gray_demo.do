##############################################################################
#  run_gray_demo.do  -- BINARY vs GRAY CDC karsilastirma (GUI)
#
#  KULLANIM:
#     cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/MyLibs/sim}
#     do run_gray_demo.do
#
#  GORULECEKLER:
#     - src domain: binary sayac (0..15) ve gray karsiligi
#     - AYNI skew (0/600/1200/1800 ps) hem binary hem gray'e uygulaniyor
#     - dst domain: ikisini de ornekliyor
#     - err_bin artarken err_gray SIFIR kalir
##############################################################################
if {[file exists work]} { vdel -all }
vlib work

vcom -2008 ../gray_pkg.vhd
vcom -2008 tb_cdc_binary_vs_gray.vhd

vsim -t 1ps -voptargs="+acc" work.tb_cdc_binary_compare

# --- SINYALLERI EKLE ---
add wave -divider "CLOCK'LAR (iliskisiz)"
add wave -label src_clk  /tb_cdc_binary_compare/src_clk
add wave -label dst_clk  /tb_cdc_binary_compare/dst_clk
add wave -label rst_n    /tb_cdc_binary_compare/rst_n

add wave -divider "SRC DOMAIN"
add wave -unsigned -label cnt_src        /tb_cdc_binary_compare/cnt_src
add wave -unsigned -label cnt_src_gray   /tb_cdc_binary_compare/cnt_src_gray
add wave -unsigned -label src_prev       /tb_cdc_binary_compare/src_prev
add wave -unsigned -label src_prev_gray  /tb_cdc_binary_compare/src_prev_gray

add wave -divider "SKEW + DST (BINARY yol)"
add wave -unsigned -label bin_skewed  /tb_cdc_binary_compare/bin_skewed
add wave -unsigned -label bin_dst     /tb_cdc_binary_compare/bin_dst

add wave -divider "SKEW + DST (GRAY yol)"
add wave -unsigned -label gray_skewed  /tb_cdc_binary_compare/gray_skewed
add wave -unsigned -label gray_dst     /tb_cdc_binary_compare/gray_dst

add wave -divider "HATA SAYACLARI"
add wave -unsigned -label err_bin   /tb_cdc_binary_compare/err_bin
add wave -unsigned -label err_gray  /tb_cdc_binary_compare/err_gray

echo "===== BASLA ====="
run 2000 ns
echo "===== BITIS ====="
wave zoom full
