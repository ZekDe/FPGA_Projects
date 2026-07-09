##############################################################################
#  run_gui.do  -- Questa GUI'de tek komutla: derle + kos + dalgalari ekle
#
#  KULLANIM (Questa GUI acikken alttaki Transcript penceresine yaz):
#     cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/01_button_ton/sim}
#     do run_gui.do
##############################################################################

# Temiz baslangic: onceki work kutuphanesini sil, yenisini kur
if {[file exists work]} { vdel -all }
vlib work

# Tasarim dosyalarini derle (bagimlilik sirasi onemli: alt bloklar once)
vcom -2008 ../src/synchronizer.vhd
vcom -2008 ../src/time_base_ms.vhd
vcom -2008 ../src/ton.vhd
vcom -2008 ../src/edge_detector.vhd
vcom -2008 tb_button_chain.vhd

# Simulasyonu baslat (dalga verisi toplansin diye -voptargs ile optimizasyonu ac)
vsim -voptargs=+acc work.tb_button_chain

# --- Dalga penceresine sinyalleri ekle ---
# Ust seviye uyaranlar
add wave -divider "UYARAN (buton)"
add wave -label clk        /tb_button_chain/clk
add wave -label rst_n      /tb_button_chain/rst_n
add wave -label btn_raw    /tb_button_chain/btn_raw

# Zaman tabani: now_ms her clock (sim'de) 1 artar = C'deki 'now'
add wave -divider "ZAMAN TABANI (SysTick)"
add wave -unsigned -label now_ms /tb_button_chain/now_ms

add wave -divider "ADIM 1: senkronizasyon"
add wave -label btn_sync   /tb_button_chain/btn_sync

add wave -divider "ADIM 2: TON (on-delay, ms)"
add wave -label ton_q      /tb_button_chain/ton_q
# TON'un ic durumu: aux (kenar bayragi) ve since (hedef zaman = now+preset)
add wave -label aux           /tb_button_chain/u_ton/aux
add wave -unsigned -label since /tb_button_chain/u_ton/since_reg

add wave -divider "ADIM 3: kenar algilayici"
add wave -label pulse      /tb_button_chain/pulse

# Belirli sure kos. DIKKAT: saat (clk) serbest kostugu icin 'run -all' asla
# durmaz. Uyaranlar (stim) 2230 ns'de bitiyor; 2500 ns hepsini kapsar.
run 2500 ns

# Dalga penceresini ekrana sigdir
wave zoom full
