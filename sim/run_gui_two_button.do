##############################################################################
#  run_gui.do  -- iki butonlu ornek: derle + kos + dalgalari ekle
#
#  KULLANIM (Questa GUI Transcript'inde):
#     cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/02_two_button/sim}
#     do run_gui.do
##############################################################################

# --- KUTUPHANE YOLU ---
# Yeniden kullanilabilir bloklar simdilik 01_button_ton/src altinda.
# libs/ yapisina gecince SADECE bu satiri degistir ( or: set LIB ../../libs).
set LIB ../../01_button_ton/src

if {[file exists work]} { vdel -all }
vlib work

# Kutuphane bloklari (bagimlilik yok, alt seviye)
vcom -2008 $LIB/synchronizer.vhd
vcom -2008 $LIB/time_base_ms.vhd
vcom -2008 $LIB/ton.vhd
vcom -2008 $LIB/edge_detector.vhd

# Bu projeye ozel: ust seviye + testbench
vcom -2008 ../src/two_button_top.vhd
vcom -2008 tb_two_button.vhd

vsim -voptargs=+acc work.tb_two_button

# --- Dalga penceresi ---
add wave -divider "systick (ortak, C'deki global)"
add wave -unsigned -label systick /tb_two_button/dut/systick

add wave -divider "BUTON 1  (timeout 100 ms)"
add wave -label btn1_raw            /tb_two_button/dut/btn1_raw
add wave -label btn1_sync           /tb_two_button/dut/btn1_sync
add wave -unsigned -label since1    /tb_two_button/dut/u_ton1/since_reg
add wave -label btn1_out            /tb_two_button/dut/btn1_out
add wave -label btn1_out_pulse      /tb_two_button/dut/btn1_out_pulse

add wave -divider "BUTON 2  (timeout 150 ms)"
add wave -label btn2_raw            /tb_two_button/dut/btn2_raw
add wave -label btn2_sync           /tb_two_button/dut/btn2_sync
add wave -unsigned -label since2    /tb_two_button/dut/u_ton2/since_reg
add wave -label btn2_out            /tb_two_button/dut/btn2_out
add wave -label btn2_out_pulse      /tb_two_button/dut/btn2_out_pulse

# stim ~21 us'de biter; 22 us hepsini kapsar (saat serbest, 'run -all' kullanma)
run 22 us
wave zoom full
