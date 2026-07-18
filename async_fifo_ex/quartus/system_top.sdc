# ==============================================================================
#  system_top.sdc  -- 06_async_fifo_test zamanlama kisiti (PLL + async FIFO)
#
#  3 clock domain:
#    CLOCK_50  (50 MHz, 20 ns) -> button_gesture / systick / UI
#    wr_clk    (100 MHz, 10 ns) -> async FIFO YAZMA tarafi (PLL c0)
#    rd_clk    (33 MHz,  30 ns) -> async FIFO OKUMA tarafi (PLL c1)
#
#  PLL clock'larina "wr_clk" / "rd_clk" KISA ISIMLER veriyoruz. Boylece SDC
#  boyunca bu isimleri kullaniriz; TimeQuest'in uzun hiyerarsik adlarini
#  (u_pll|...|general[0]...|divclk) bilmek zorunda degiliz. system_top.vhd'deki
#  sinyal isimleriyle bire bir ayni -> okunabilirlik artar.
#
#  COZUM YAKLASIMI:
#    derive_pll_clocks: Quartus PLL'i otomatik tarar, uzun isimlerle clock uretir.
#    Bizim create_generated_clock: ayrica KISA ISIMLI clock uretir, ayni pin'e.
#    Iki clock ayni pin'den uretilince TimeQuest bunlari "ayni clock" kabul eder
#    (multicycle path degil, sadece iki isim). Bu sayede CDC constraint'leri
#  kisa isimlerle yazilabilir.
#
#  DOGRULAMA: TimeQuest console'da "report_clocks" calistir.
#  CLOCK_50, wr_clk, rd_clk isimleriyle 3 clock gormelisin.
# ==============================================================================

# Ana clock: 50 MHz (20 ns)
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# PLL clock'larini otomatik turet (Quartus'un uzun isimleriyle).
# Bu, PLL'in dogru calismasi icin sart (fitter bunu kullanir).
derive_pll_clocks

# -----------------------------------------------------------------------------
#  PLL clock'larina KISA ISIM ver (system_top.vhd ile ayni isimler)
# -----------------------------------------------------------------------------
#  -source: CLOCK_50 (PLL referansi)
#  -multiply_by / -divide_by: PLL c0/c1 ayarlari
#    c0 = 100 MHz = 50 MHz * 2      -> -multiply_by 2
#    c1 = 33  MHz = 50 MHz * (2/3)  -> -multiply_by 2 -divide_by 3
#  Hedef pin: altera_pll outclk_wire[0] / [1]
#
#  PIN YOLLARI (fit.rpt:184-185 / 1789-1790'dan dogrulandi):
#    pll_2clk:u_pll|...|outclk_wire[0]  -> wr_clk (100 MHz)
#    pll_2clk:u_pll|...|outclk_wire[1]  -> rd_clk (33 MHz)
#
#  Not: Pin yollari uzun ama bunlar SDC'de sadece 1 kez yazilir. Asagidaki
#  CDC constraint'leri kisa isimlerle (wr_clk / rd_clk) yazilir.
# -----------------------------------------------------------------------------
create_generated_clock -name wr_clk \
  -source [get_ports CLOCK_50] \
  -multiply_by 2 \
  [get_pins {pll_2clk:u_pll|pll_2clk_0002:pll_2clk_inst|altera_pll:altera_pll_i|outclk_wire[0]}]

create_generated_clock -name rd_clk \
  -source [get_ports CLOCK_50] \
  -multiply_by 2 -divide_by 3 \
  [get_pins {pll_2clk:u_pll|pll_2clk_0002:pll_2clk_inst|altera_pll:altera_pll_i|outclk_wire[1]}]

# Asenkron reset ve butonlar: timing-kritik degil (insan eli)
set_false_path -from [get_ports {KEY[*] SW[*]}] -to *

# LED cikislari: timing-kritik degil (insan gozu)
set_false_path -from * -to [get_ports {LED[*]}]

# -----------------------------------------------------------------------------
#  CDC (Clock Domain Crossing) -- 3 domain, karsilikli ASENKRON
# -----------------------------------------------------------------------------
#  3 domain karsilikli ASENKRON'dur:
#    - FIFO pointer'lari wr_clk <-> rd_clk arasi gray code + 2-FF ile gecer
#    - button event pulse'lari CLOCK_50 -> wr_clk / rd_clk'e toggle-sync
#      (cdc_pulse_sync) ile gecer
#  Bu yuzden aralarindaki tum timing yollari "asenkron" isaretlenmeli;
#  yoksa TimeQuest anlamsiz setup/hold ihlalleri gosterir.
#
#  Artik kisa isimlerle yaziyoruz -- system_top.vhd ile bire bir ayni.
# -----------------------------------------------------------------------------
set_clock_groups -asynchronous \
  -group [get_clocks CLOCK_50] \
  -group [get_clocks wr_clk] \
  -group [get_clocks rd_clk]
