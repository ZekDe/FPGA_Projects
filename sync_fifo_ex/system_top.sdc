# ==============================================================================
#  system_top.sdc  -- zamanlama kisiti (DE0-Nano-SoC, 50 MHz Cyclone V)
#
#  50 MHz = 20 ns periyot. Bu olmadan Quartus "clock tanimsiz" der ve timing
#  analiz yapamaz. Tum FF'ler bu clock'a bagli; setup/hold bu periyoda gore.
#
#  KULLANIM: projeye ekle -> Assignments -> Settings -> TimeQuest Timing
#  Analyzer -> SDC files -> bu dosyayi ekle.
# ==============================================================================

# Ana clock: 50 MHz (20 ns periyot)
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# Turetilmis clock'lar (varsa PLL) otomatik hesaplansin
derive_clocks -period 20.000
derive_pll_clocks

# Asenkron girisler (KEY, SW - insan eli) timing-kritik degil:
# buton ne zaman basilacagini bizim 50 MHz saatimiz bilmez. Bu yuzden
# setup/hold ihlallerini gormek anlamsiz; TimeQuest bunlari "false path"
# olarak isaretlesin ki timing raporu temiz gozuksun.
set_false_path -from [get_ports {KEY[*] SW[*]}] -to *

# LED cikislari da timing-kritik degil (insan gozu 50 ms'i goremz):
# LED ne kadar gec yansa kimse fark etmez. Yine false path.
set_false_path -from * -to [get_ports {LED[*]}]
