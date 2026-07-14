##############################################################################
#  run_gui.do  -- button_gesture FSM testi (pipelined divider entegreli)
#
#  KULLANIM:
#     Questa GUI'de Transcript penceresine:
#        cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/04_button_gesture/sim}
#        do run_gui.do
#
#  YAPISI:
#     - MyLibs/ altindaki ortak bloklari derler (synchronizer, time_base_ms,
#       ton, edge_detector, divider_pipelined, button_gesture)
#     - Testbench'i derler
#     - Dalga penceresini acar ve 100 us simule eder
##############################################################################

# --- KUTUPHANE YOLU ---
# MyLibs: tum projeler tarafindan paylasilan reusable bloklar
set LIB ../../MyLibs

# Temiz baslangic: onceki work kutuphanesini sil, yenisini kur
if {[file exists work]} { vdel -all }
vlib work

# --- DERLEME (bagimlilik sirasi: alt bloklar once) ---
vcom -2008 $LIB/synchronizer.vhd
vcom -2008 $LIB/time_base_ms.vhd
vcom -2008 $LIB/ton.vhd
vcom -2008 $LIB/edge_detector.vhd
vcom -2008 $LIB/divider_pipelined.vhd
vcom -2008 $LIB/button_gesture.vhd

# Testbench
vcom -2008 tb_button_gesture.vhd

# --- SIMULASYONU BASLAT ---
# -voptargs=+acc : optimizasyonu ac ki tum ic sinyaller dalga penceresinde gorunsun
vsim -voptargs=+acc work.tb_button_gesture

# ===========================================================================
# --- DALGA PENCERESINE SINYALLERI EKLE ---
# ===========================================================================

# Uyaranlar (testbench seviyesi)
add wave -divider "UYARANLAR"
add wave -label clk              /tb_button_gesture/clk
add wave -label rst_n            /tb_button_gesture/rst_n
add wave -label raw_pressed      /tb_button_gesture/raw_pressed
add wave -label require_repress  /tb_button_gesture/require_repress

# Zaman tabani
add wave -divider "ZAMAN (SysTick)"
add wave -unsigned -label now_ms  /tb_button_gesture/now_ms

# Config portlari (C'deki struct alanlari)
add wave -divider "CONFIG PORTLARI"
add wave -unsigned -label debounce_ms           /tb_button_gesture/debounce_ms
add wave -unsigned -label long_press_ms         /tb_button_gesture/long_press_ms
add wave -unsigned -label multi_click_window_ms /tb_button_gesture/multi_click_window_ms
add wave -unsigned -label repeat_start_ms       /tb_button_gesture/repeat_start_ms
add wave -unsigned -label repeat_end_ms         /tb_button_gesture/repeat_end_ms
add wave -unsigned -label repeat_ramp_ms        /tb_button_gesture/repeat_ramp_ms

# DUT ic sinyalleri: debounce + edge + ton cikislari
add wave -divider "DEBOUNCE / EDGE / TON"
add wave -label stable            /tb_button_gesture/dut/stable
add wave -label stable_prev       /tb_button_gesture/dut/stable_prev
add wave -label rise              /tb_button_gesture/dut/rise
add wave -label long_level        /tb_button_gesture/dut/long_level

# FSM durumu ve register'lar
add wave -divider "FSM STATE + REGISTERS"
add wave -label state             /tb_button_gesture/dut/state
add wave -unsigned -label click_count_reg  /tb_button_gesture/dut/click_count_reg
add wave -unsigned -label window_start     /tb_button_gesture/dut/window_start
add wave -unsigned -label long_started_at  /tb_button_gesture/dut/long_started_at
add wave -unsigned -label last_repeat      /tb_button_gesture/dut/last_repeat

# PIPED DIVIDER internal sinyalleri (period hesabi)
add wave -divider "PIPED DIVIDER (period hesabi)"
add wave -unsigned -label delta         /tb_button_gesture/dut/delta
add wave -unsigned -label elapsed_calc  /tb_button_gesture/dut/elapsed_calc
add wave -unsigned -label product_64    /tb_button_gesture/dut/product_64
add wave -label div_start               /tb_button_gesture/dut/div_start
add wave -unsigned -label div_dividend  /tb_button_gesture/dut/div_dividend
add wave -label div_valid               /tb_button_gesture/dut/div_valid
add wave -unsigned -label div_quotient  /tb_button_gesture/dut/div_quotient
add wave -unsigned -label period_reg    /tb_button_gesture/dut/period_reg

# Cikis: one-hot event pulse'lari + click_count
add wave -divider "EVENT CIKISLARI (one-hot pulse)"
add wave -label evt_single         /tb_button_gesture/evt_single
add wave -label evt_multi          /tb_button_gesture/evt_multi
add wave -label evt_long           /tb_button_gesture/evt_long
add wave -label evt_long_repeat    /tb_button_gesture/evt_long_repeat
add wave -label evt_long_released  /tb_button_gesture/evt_long_released
add wave -unsigned -label click_count /tb_button_gesture/click_count

# --- SIMULASYONU CALISTIR ---
# Stim 80 us civarinda bitiyor; 100 us hepsini kapsar.
# Dikkat: saat serbest kostugu icin 'run -all' kullanma (asla durmaz).
run 100 us

# Dalga penceresini ekrana sigdir
wave zoom full
