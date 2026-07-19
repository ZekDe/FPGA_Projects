# MyLibs — Reusable FPGA IP Kütüphanesi

Bu klasör, FPGA donanım modüllerinin **yeniden kullanılabilir (reusable)** bloklarını
içerir. Tüm bloklar **vendor-bağımsız** (vendor-independent) VHDL ile yazılmıştır:
Quartus, Vivado, ModelSim, Questa — hepsinde çalışır. Black-box IP yoktur, DO-254
audit için tam transparan VHDL'dir.

## Yol Haritası (8 Faz)

Bu kütüphane, adım adım bir öğrenme yolculuğunun çıktısıdır. Her faz bir önceki
fazın üstüne inşa edilir:

```
[TAMAMLANDI] Faz 1: FSM
   ├─ button_gesture.c -> VHDL FSM port (5 durum, case-when)
   ├─ 1-bit CDC (synchronizer), debounce, TON, edge detector
   ├─ C'den VHDL'e birebir portlama metodolojisi
   ├─ One-hot event pulse cikislari, default+override deseni
   └─ Kartta LED gozlemi (DE0-Nano-SoC)

[TAMAMLANDI] Faz 2: CDC derin
   ├─ Multi-bit CDC problemi (2-FF yetmez) - simülasyonda ispatlandi
   ├─ Gray code: tanım, binary<->gray dönüşüm, neden çalışır
   ├─ Async handshake (req/ack) cok-bitli veri için
   ├─ Toggle-sync pulse CDC (cdc_pulse_sync) - 06_fifo_async'da kullanildi
   └─ MTBF hesabı (atlandi - pratik kural: 2 FF yeter, 3 FF savunma)

[TAMAMLANDI] Faz 3.1: Sync FIFO
   ├─ Dairesel tampon (circular buffer) + pointer matematigi
   ├─ "Full mu, empty mi?" - N+1 bit hilesi
   ├─ Inferred BRAM (Quartus M10K'a sentezlendi)
   └─ Kartta uygulama (05_fifo_sync)

[TAMAMLANDI] Faz 3.2: Async FIFO
   ├─ Gray pointer + 2-FF = Faz 2'nin uygulaması
   ├─ Cummings async FIFO mimarisi
   ├─ Simülasyonda doğrulandı (19/19 okuma, 2 domain)
   └─ Kartta uygulama (06_fifo_async) - 3 clock domain

[TAMAMLANDI] Faz 4: BRAM (teori)
   ├─ Inferred vs instantiated (sen inference kullandın - FIFO'larda)
   ├─ Single-port / simple-dual / true-dual modları
   └─ Write-first / read-first / no-change (FIFO = read-first)

[TAMAMLANDI] Faz PLL: Clock generation (06_fifo_async)
   ├─ ALTPLL IP: 50 MHz -> 100 MHz (wr_clk) + 33 MHz (rd_clk)
   ├─ m/n/c ratio, locked sinyali, VCO aralıkları
   ├─ fifo_rst_n = rst_n AND locked (Cummings onerisi)
   └─ SDC: derive_pll_clocks + create_generated_clock + set_clock_groups

[TAMAMLANDI] Faz 6: Timing closure (06_fifo_async raporu)
   ├─ Setup/hold slack, TNS, Fmax kavramları
   ├─ Timing raporu okuma (sta.rpt)
   ├─ CDC: set_clock_groups -asynchronous
   └─ Senin projende: TNS=0, worst setup slack +4.78 ns, closure SAĞLANDI

[SIRADA] Faz 5: AXI-Lite
   ├─ VALID/READY handshake (decoupled)
   ├─ 5 kanal: AW, W, B, AR, R
   ├─ Sinyaller: VALID/READY/ADDR/DATA/RESP/PROT/STRB
   ├─ Response kodları: OKAY, EXOKAY, SLVERR, DECERR
   ├─ Register file + adres decoding
   └─ Out-of-order Lite'ta yok

[SIRADA] Faz 7: HPS + Linux (Platform Designer, device tree, /dev/mem)
[SIRADA] Faz 8: IMU (SPI master + async FIFO + AXI-Stream)
   └─ Hedef: IMU -> SPI -> FIFO -> AXI -> HPS (ARM Cortex-A9) -> Linux
```

## Uygulama Projeleri

MyLibs modülleri, `VHDL_Projects/` altındaki uygulama projelerinde kullanilir.
Her proje, `system_top.vhd` dosyasinin basindaki "DOSYA LISTESI" bolumunden
hangi modülleri kullandigini belirtir.

| Proje | Kullandigi MyLibs modülleri | Faz |
|-------|------------------------------|-----|
| `04_button_gesture/` | button_gesture, synchronizer, ton, edge_detector, divider_pipelined, time_base_ms, led_pulse | 1+6 |
| `05_fifo_sync/` | button_gesture (x2), fifo_sync, + 04'teki tüm modüller | 1+6+3.1 |
| `06_fifo_async/` | fifo_async, cdc_pulse_sync (x2), gray_pkg, + öncekilerin tümü, ALTPLL IP (PLL) | 1+2+3+PLL |

## İçindekiler — Fazlara Göre

| Dosya | Ne işe yarar | Faz | Tip |
|-------|--------------|-----|-----|
| `synchronizer.vhd` | 2-FF CDC: async tek-bit sinyali domain'ler arası güvenle taşır | 1 | CDC |
| `time_base_ms.vhd` | Clock → milisaniye zaman tabanı (donanım SysTick) | 1 | Zaman |
| `ton.vhd` | IEC 61131-3 On-Delay Timer (TON) | 1 | Zaman |
| `edge_detector.vhd` | Yükselen kenar algılayıcı (1-clock pulse) | 1 | Primitif |
| `button_gesture.vhd` | Buton gesture FSM: single/multi/long/repeat/release | 1 | FSM |
| `divider_pipelined.vhd` | 32-bit unsigned divider, 32-stage pipeline | 6 ön | Aritmetik |
| `led_pulse.vhd` | 1-clock pulse → N ms LED seviyesi (re-triggerable) | 1 | Çıkış |
| `gray_pkg.vhd` | Binary↔Gray code dönüşüm fonksiyonları (package) | 2 | CDC |
| `cdc_handshake_tx.vhd` | Async handshake verici: çok-bitli veriyi karşı domain'e gönder | 2 | CDC |
| `cdc_handshake_rx.vhd` | Async handshake alıcı: çok-bitli veriyi karşı domain'den al | 2 | CDC |
| `cdc_pulse_sync.vhd` | Toggle + 2-FF + edge detect: tek-bit pulse'u karşı domain'e güvenli taşı | 2 | CDC |
| `fifo_sync.vhd` | Senkron FIFO (tek clock domain), N+1 bit full/empty, inferred BRAM | 3 | FIFO |
| `fifo_async.vhd` | Asenkron FIFO (iki clock domain), gray pointer + 2-FF, inferred BRAM | 3 | FIFO |

## Bağımlılık Ağacı (Dependency Tree)

Bu ağacı oku: bir modülü kullanacaksan, altındaki tüm modülleri de projeye eklemelisin.

```
button_gesture          [Faz 1] buton gesture FSM
├─ synchronizer         [Faz 1]
├─ ton                  [Faz 1]
└─ divider_pipelined    [Faz 6 ön]

system_top (04_button_gesture)
├─ button_gesture
├─ time_base_ms         [Faz 1]
├─ led_pulse            [Faz 1]
└─ edge_detector        [Faz 1]

cdc_handshake_rx        [Faz 2]
└─ synchronizer         [Faz 1]

cdc_handshake_tx        [Faz 2]
└─ synchronizer         [Faz 1]

cdc_pulse_sync          [Faz 2] tek-bit pulse CDC (toggle + 2-FF + edge)
└─ synchronizer         [Faz 1]

fifo_sync               [Faz 3] senkron FIFO (tek clock)
└─ (bagimlilik yok - kendi basina)

fifo_async              [Faz 3] asenkron FIFO (iki clock domain)
├─ gray_pkg             [Faz 2]
└─ synchronizer         [Faz 1] (her pointer biti icin ayri 2-FF)
```

## Hangi Dosyaları Projeye Eklemeliyim?

Her `system_top` örneğinin **başında** bir "DOSYA LİSTESİ" (manifest) bölümü vardır.
O bölüm, o system_top'u derlemek için gereken **tam dosya listesini** verir — QSF
satırları olarak, kopyala-yapıştır hazır.

Kural: **system_top başındaki listeyi oku → QSF'ye ekle → derle.**

Eğer hangi dosyaya ihtiyacın olduğunu bilmiyorsan, **bağımlılık ağacını** oku: bir
modülü kullanacaksan, onun altındaki tüm modülleri de eklemelisin.

## Yollar Hakkında

Bu kütüphaneyi kullanmak isteyen bir proje, kendi qsf'inde şöyle yollar kullanır:

```tcl
# Proje klasoru: 04_xxx/
# MyLibs klasoru: ../MyLibs/   (bir üst dizin)
set_global_assignment -name VHDL_FILE ../MyLibs/synchronizer.vhd
set_global_assignment -name VHDL_FILE ../MyLibs/button_gesture.vhd
# ... vb
```

Eğer MyLibs'u başka bir yere koyarsan, sadece yolları güncellersin.

## Sentez Kuralları

- **2008 VHDL standardı** kullanılır (`vcom -2008`, Quartus'ta "VHDL 2008" seçeneği).
- Tüm modüller **asenkron reset, aktif-düşük** (`rst_n`) kullanır.
- Tüm zamanlama **`now_ms` (milisaniye) üzerinden** yapılır, clock tick değil.
- Tüm modüller **vendor-bağımsız**dır — `std_logic_1164` + `numeric_std` dışında
  hiçbir vendor IP'si kullanılmaz.

## Simülasyon

Her modül için bir testbench `sim/` altındadır. Çalıştırmak için:

```tcl
# Questa/ModelSim Transcript penceresinde:
cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/MyLibs/sim}
do run_<test_adi>.do
```

| Testbench | Ne test eder | do dosyası |
|-----------|--------------|------------|
| `tb_divider_pipelined.vhd` | Pipelined divider: 5 senaryo | `tb_divider_pipelined.do` |
| `tb_cdc_binary_vs_gray.vhd` | CDC: binary (15 hata) vs gray (0 hata) | `run_gray_demo.do` |
| `tb_cdc_handshake.vhd` | 32-bit rastgele verinin handshake ile transferi | `run_handshake.do` |
| `tb_fifo_sync.vhd` | Sync FIFO: yaz/oku sırası, full/empty flag'leri | `run_fifo.do` |
| `tb_fifo_async.vhd` | Async FIFO: iki clock domain arası veri bütünlüğü (19/19 okuma) | `run_fifo_async.do` |
| `tb_button_gesture.vhd` | Buton gesture FSM: 4 senaryo | (`04_button_gesture/sim/`) |

## VHDL 2008

Bu kütüphanenin tümü VHDL 2008 standardında yazılmıştır. Derleme komutları:

```bash
# Questa/ModelSim:
vcom -2008 <dosya.vhd>

# Quartus: Settings → General → VHDL Input Version → VHDL 2008
```

## Testbench Tuzakları ve Çözümleri

Bu bölüm, bu kütüphaneyi geliştirirken karşılaşılan **gerçek hataları** ve çözümlerini
toplar. Yeni başlayanların aynı tuzaklara düşmemesi için. Sıralama: en sık karşılaşılandan.

### 1. Çift Sürücü (Multiple Drivers) → 'X' (Unknown)

**Belirti:** Bir register, simülasyonda `0xXXXX...` olarak görünüyor. Çıkışı etkileyen
tüm karşılaştırmalar `false` olduğundan hiçbir şey çalışmıyor (örneğin FSM asla tetiklenmiyor).

**Sebep:** Aynı sinyale **iki farklı process** atama yapıyor. VHDL'in resolution function'ı
iki driver farklı değer tuttuğunda **'X'** üretir. Derleme hatası vermez — sessizce bozar.

**Örnek:** `button_gesture.vhd`'de `period_reg` eski sürümde hem `p_period_reg` hem `p_state`
tarafından sürülüyordu. Sonuç: `period_reg = 0x000000XX` → repeat event'leri hiç patlamıyordu.

**Çözüm:**
- Bir register'ı **sadece tek bir process** içinde yaz.
- Birden fazla yerde güncellemen gerekiyorsa, tüm atamaları aynı process'in içine koy.
- İkinci bir clocked process açma. C'deki gibi "bu değişkeni burada da değiştireyim"
  düşünce VHDL'de geçerli değil.

**İpucu:** Sentez sonrası Quartus'ta "Cannot resolve tri-state driver" veya
"multiple drivers" uyarısı da aynı soruna işaret eder.

### 1b. Çift Sürücü - Kombinasyonel vs Process (system_top'ta yaşandı)

**Belirti:** `fifo_wr_data` gibi bir sinyal hem `begin` sonrası kombinasyonel atamada
hem de bir clocked process içinde atanıyor. Sonuç yine 'X'.

**Sebep:** "Process içinde yazıyorum" ile "dışarıda sürekli atama yapıyorum" aynı sinyale
çakışır — VHDL her ikisini de ayrı driver sayar. `fifo_wr_data <= SW ...` dışarıda, process
içinde `fifo_wr_data <= (others => '0')` yazarsan → iki driver → 'X'.

**Örnek:** `05_fifo_sync/src/system_top.vhd`'nin ilk versiyonunda `fifo_wr_data` hem Bölüm 3'te
kombinasyonel, hem Bölüm 5'teki `p_fifo_ctrl` process'inde reset/default olarak atandı.

**Çözüm:** Bir sinyal ya process içinde olur (registered) ya dışarıda (kombinasyonel).
İkisi birden olmaz. `fifo_wr_data`'yı process dışında tut, process içine hiç dokunma.

### 2. Delta Cycle (FWFT / Kombinasyonel Çıkış Tuzağı)

**Belirti:** Testbench'te `wait until rising_edge(clk)` sonrası `assert` hatalı değer
görüyor, ama dalga formu doğru çalışıyor.

**Sebep:** VHDL'de sinyal atamaları bir delta cycle sonra etkili olur. Kombinasyonel
çıkışlar (örneğin FIFO'da FWFT `rd_data = ram[rd_ptr]`) clock edge'inde güncellenen
bir pointer'a bağlıdır. Edge geldiğinde `rd_ptr` henüz güncellenmemiş olabilir.

**Örnek:** `tb_fifo_sync.vhd`'de `rd_data`'yı assert etmek için edge sonrası
`wait for 1 ps` eklemek gerekti. Aksi halde `rd_ptr`'in eski değerinden okuma yapıyorduk.

**Çözüm:**
- Clock edge sonrası `wait for 1 ps` ekle (sinyallerin yerleşmesi için).
- Ya da `wait until rising_edge(clk) and <sinyal> = <deger>` şeklinde bekle.

### 2b. Clamp (Üst/Alt Sınır) Kaybı → Underflow → FSM Dondu

**Belirti:** Bir ramp (örneğin repeat ramp ivmesi) başlangıçta güzel çalışıyor, giderek
hızlanıyor, ama belirli bir noktada **aniden duruyor** — sonraki event'ler hiç gelmiyor.

**Sebep:** Bir değer ramp son değerini geçince **clamp'lenmemiş** (sınırlanmamış).
Unsigned çıkarmada bu **underflow** yaratır: `start - quotient` eğer `quotient > start`
ise → `4294967295` gibi dev bir değer → karşılaştırma asla true olmaz → FSM donar.

**Örnek:** `button_gesture.vhd`'de repeat period hesabı: `period = repeat_start_ms -
(delta*elapsed)/ramp_ms`. `elapsed` ramp süresini geçince quotient delta'yı aşıyor,
`start - quotient` underflow'a giriyor, period devasa oluyor → repeat event'leri duruyor.
C referans kodunda bu `if (elapsed >= ramp_ms) period = end_ms` ile **clamp**'leniyordu,
ama VHDL portunda o dal unutulmuştu.

**Çözüm:** Ramp hesaplarında **clamp** şarttır. En temiz yer: dividend'i clample:
`elapsed_calc <= elapsed_raw when elapsed_raw <= ramp_ms else ramp_ms`.
Böylece quotient asla delta'yı geçemez, underflow imkânsız olur. C referansındaki
üç dallı if'in (ramp bitince end_ms'de sabit) birebir karşılığı budur.

### 3. Doğru Test Mantığı Kurmamak (False Positive / Negative)

**Belirti:** Test "geçiyor" gibi görünüyor ama aslında hiçbir şey test etmiyor.
Veya test sürekli fail veriyor ama DUT aslında doğru çalışıyor.

**Sebep:** Testbench'in tespit kuralı yanlış. En sık görülen biçimi: iki clock domain'li
testlerde, yavaş domain her zaman geride kalır → `|diff| > 1` her an tetiklenir →
test CDC hatası değil, sadece "yavaş domain geride" diye raporlar.

**Örnek:** `tb_gray_cdc.vhd`'nin ilk versiyonunda `cnt_dst` ile `cnt_src`'i doğrudan
kıyasladık — ama dst clock daha yavaş olduğu için dst daima geride kaldı, bu yüzden
test her an "hata" diyordu. Oysa gray code gayet iyi çalışıyordu.

**Çözüm:**
- **Ne test ettiğini net tanımla.** CDC hatası = "alıcı, vericinin hiç üretmediği bir
  değer yakaladı mı?" Bu, "alıcı vericiden geride mi kaldı?" demek değil.
- Doğru kural: "alıcının yakaladığı değer, vericinin ürettiği değerler kümesinde mi?"
  (pencere kontrolü).
- "Test geçti" ile "test anlamlı bir şey test etti" farklı şeyler.

### 4. Sözdizimi Hatalarının Yüzeyde Okunması

**Belirti:** Derleyici "Unknown identifier X" veya "No feasible entries for infix
operator" hatası veriyor, ama sen o identifier'ı tanımladığını sanıyorsun.

**Sebep:** Derleyici hatayı bulunduğu yerde raporlar, ama kök sebep genellikle daha
yukarıda. En sık görüleni: bir package veya `use` statement eksik.

**Örnek:** `gray_pkg.vhd`'yi yazarken `xor` operatörü "No feasible entries" hatası verdi.
`xor` kullanıyordum ama package `use ieee.std_logic_1164.all` eklemeden `std_logic`
tipini kullandım. Derleyici `xor`'u suçladı, ama asıl sorun tipin tanımsız olmasıydı.

**Çözüm:**
- Derleme hatalarını yüzeyde okuma. "xor bulunamadı" → aslında tip tanımsız.
- Package'larında her zaman `library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;`
  olsun.
- Hata satırına değil, hata satırının **üstündeki** declaration'lara bak.

### 5. Çok Büyük/Çok Küçük Simülasyon Parametreleri

**Belirti:** Simülasyon beklenen davranışı göstermiyor ama DUT doğru.

**Sebep:** Testbench'teki parametreler (skew, frekans, bekleme süresi) çok küçük veya çok
büüyük. İdeal sıfır-gecikmeli simülasyonda skew yoktur, bu yüzden CDC hatalarını görmek
için realistic skew modellemek gerekir.

**Örnek:** `tb_cdc_binary_vs_gray.vhd`'de başta 0/50/100/150 ps skew kullandık → 0 hata
geldi (skew penceresi çok küçük). Skew'ları 0/600/1200/1800 ps'ye çıkarınca binary'de
15 hata, gray'de 0 hata net olarak görüldü.

**Çözüm:**
- CDC testlerinde realistic skew modelle (her bit'e farklı transport delay).
- Skew değerlerini değiştirerek sonucun değişmediğini doğrula (robustness).
- Simülasyon "geçti" diye yetinme — eğer hiç hata görmüyorsan, belki test çok hafiftir.

### 6. Sentez Dışı Yapıların Simülasyonda Çalışması

**Belirti:** Simülasyon mükemmel, ama sentezde hata veya donanımda farklı davranış.

**Sebep:** Simülasyon tüm VHDL'i destekler, ama sentezleyici sadece sentezlenebilir
alt kümesini destekler. En sık görüleni: `integer` tipli sayaçlar çok büyük aralıklarla
(2^31+) veya initial değerleri.

**Çözüm:**
- `integer range 0 to N` kullan (finite aralık).
- Initial değerler (`:= 0`) sentezlenir ama FPGA açılışta garantili değildir;
  **reset şart**. Senin tüm modüllerinde `rst_n` var, iyi.
- `for` loop'lar sentezlenir ama **sabit sınır** olmalı (variable sınır sentezlenmez).

---

## Konu Anlatımları (Teknik Referans)

Bu bölüm, unutursan bakacağın teknik referans. Her konu kısa, örnekli ve
"neden?" sorusuna cevap verecek şekilde yazıldı.

### Timing Closure Nedir?

FPGA'da her flip-flop, veriyi clock'un yükselen kenarında örnekler. Timing
closure = **tüm FF'lerin zamanında veriyi aldığını kanıtlamak.** Quartus'un
TimeQuest Timing Analyzer aracı bunu sentezden sonra yapar.

**Slack** = her yol (path) için "ne kadar boşluk var" metriği:
```
Setup slack = required_time - arrival_time
            = clock_period - setup_time - data_path_delay
```
- **Pozitif slack** = yol zamanında bitiyor (iyi)
- **Negatif slack** = yol çok uzun, clock kaçırılıyor (kötü — donanım hata verir)

**Üç tür slack** TimeQuest raporunda görünür:
- **Setup slack:** veri zamanında ulaştı mı? (Pozitif = iyi)
- **Hold slack:** veri çok erken gelmedi mi? (Pozitif = iyi)
- **Minimum Pulse Width:** clock pulse genişliği yeterli mi?

**TNS (Total Negative Slack)** = tüm ihlal edilmiş yolların slack toplamı:
- `TNS = 0` → **timing closure sağlandı** (hiç ihlal yok)
- `TNS < 0` → ihlal var, donanımda sorun olabilir

**Setup vs Hold ihlali — çözümleri farklı:**
| İhlal | Sebep | Çözüm |
|-------|-------|-------|
| Setup negatif | Yol çok uzun | Pipeline ekle, kayıt ekle |
| Hold negatif | Yol çok kısa | Quartus otomatik delay zinciri ekler |

`divider_pipelined.vhd`'nin hikayesi tam budur: combinational division setup
slack negatifti (yol 32 cascade subtract çok uzun), pipeline ekledik, her stage
kısa oldu, slack pozitif oldu.

### Hold Fix — FPGA'nın Hassas Dengesi

Setup ihlali çözümü (pipeline) sezgisel gelse de, **hold ihlali** tersdir ve
FPGA'nın ne kadar ince bir dengede çalıştığını gösterir:

- **Setup ihlali:** veri ÇOK GEÇ geldi (yol çok uzun) → kullanıcı pipeline ekler
- **Hold ihlali:** veri ÇOK ERKEN geldi (yol çok kısa) → Quartus **otomatik**
  olarak yola **delay zinciri** (seri buffer/inverter) ekler

Yani iki komşu FF arasındaki yol **çok kısa** ise, kaynak FF'in çıkışı hedef
FF'e o kadar hızlı ulaşır ki, hedef FF bir önceki cycle'ın verisini kaçırır
(veri çok erken değişir). Quartus bunu router'da **yapay gecikme ekleyerek**
çözer — yola birkaç inverter/buffer koyar, veriyi yavaşlatır, hold penceresine
oturtur. Buna **hold fix** denir ve sentezden sonra fitter otomatik yapar.

Bu mekanizma gösterir ki FPGA'de timing sadece "yol ne kadar uzun" değil,
**"yol ne kadar kısa"** da sorun yaratabilir. İdeal: her yol ne çok uzun ne
çok kısa — denge.

**Pratik kural:** Setup ihlalini kullanıcı (sen) çözersin (pipeline). Hold
ihlalini Quartus çözer (delay chain). Senin projelerinde hold slack pozitif
(TNS=0) olduğu için fitter bunu başardı, senin müdahale etmen gerekmedi.

### Timing Raporu Nasıl Okunur?

`output_files/<proje>.sta.rpt` dosyası TimeQuest çıktısıdır. Önemli bölümler:

**1. Fmax tablosu:** her clock'un elde edebildiği maksimum frekans
```
; Fmax       ; Clock Name
; 125.55 MHz ; CLOCK_50       ← hedef 50 MHz, elde 125 MHz (rahat)
; 231.43 MHz ; ...general[0]  ← PLL c0 = wr_clk (100 MHz hedef)
; 281.37 MHz ; ...general[1]  ← PLL c1 = rd_clk (33 MHz hedef)
```

**2. Worst-case Slack tablosu:** her clock için en kötü yol
```
; Clock          ; Setup  ; Hold  ; Recovery ; Removal ; Min Pulse Width
; Worst-case     ; 4.780  ; 0.167 ; N/A       ; N/A     ; 1.250
; CLOCK_50       ; 12.035 ; 0.167
; wr_clk         ; 4.780  ; 0.168  ← en dar domain (100 MHz, mantıklı)
```

**3. Design-wide TNS:** en kritik metrik
```
; Design-wide TNS ; 0.0    ← timing closure SAĞLANDI
```

### PLL Clock İsimlerini Bulma (get_pins)

SDC'de `create_generated_clock` için PLL çıkış pininin tam hiyerarşik adı
lazım (`pll_2clk:u_pll|...|outclk_wire[0]`). Üç yöntem:

1. **TimeQuest `report_clocks`** (en sağlam) — Tools → Timing Analyzer,
   Tcl konsoluna `report_clocks` yaz. Tüm clock'ları listeler.
2. **Node Finder** (en pratik) — Tools → Node Finder, Filter: "Clocks",
   `outclk` ara, tam yolu kopyala.
3. **fit.rpt oku** (en düşük seviye) — derleme raporunda pin adları geçer.

**İş akışı:** İlk derlemede sadece `derive_pll_clocks` yaz (Quartus otomatik
tanır). `report_clocks` ile isimleri öğren. Sonra `create_generated_clock` ile
kısa isim ver (`wr_clk`, `rd_clk`). İkinci derlemede timing analizi.

### SDC Komutları Referansı

| Komut | Ne yapar | Ne zaman kullan |
|-------|----------|-----------------|
| `create_clock` | Ana clock tanımla | Her zaman (CLOCK_50 vb.) |
| `derive_pll_clocks` | PLL clock'larını otomatik türet | PLL varsa |
| `create_generated_clock` | PLL çıkışına kısa isim ver | SDC okunabilirliği için |
| `set_false_path` | Bir yolu analizden çıkar | Reset, LED, async input |
| `set_clock_groups -asynchronous` | Domain'leri birbirinden ayır | CDC (multi-clock) |
| `set_multicycle_path` | Bir yola ekstra cycle tanı | AXI handshake, enable'lı register |

### Multicycle Path vs False Path

İkisi de "bu yolu analizden çıkar/rahatlat" ama farklı:
- **False path:** yol ASLA analiz edilmemeli (reset, LED). "Bu yol timing değil."
- **Multicycle path:** yol analiz edilsin ama **N cycle süre** tanı. "Bu yol
  1 cycle'da değil, 3 cycle'da tamamlanır."

Yanlış false path yazarsan kritik yolu gizlersin → donanım hatası.
Yanlış multicycle yazarsan yanlış pozitif slack → yine donanım hatası.

### Recovery ve Removal (Async Reset İçin)

Async reset (`rst_n`) timing analizde iki metrik verir:
- **Recovery:** reset bırakıldıktan sonra ilk clock edge'inden ÖNCE kararlı olma
  süresi (setup gibi)
- **Removal:** reset bırakıldıktan sonra clock edge'inden SONRA kalma süresi
  (hold gibi)

Çoğu tasarım async reset için `set_false_path -from rst_n` yazar, TimeQuest
bunları analiz dışı bırakır. Senin tasarımın raporunda `Recovery/Removal: N/A`
çünkü reset async.

### Async FIFO'da CDC ve Timing

`fifo_async.vhd`'de gray pointer yolları `set_clock_groups -asynchronous`
ile timing analizden çıkarıldı. Çünkü:
- Kaynak rd_clk, hedef wr_clk (farklı domain'ler)
- Arada 2-FF synchronizer var (metastability'e izin verilmiş)
- Bu yol timing closure OLAMAZ ama **CDC kurallarıyla güvenli**

Timing closure'ın CDC boyutu: **analizden çıkarmak** = hatayı gizlemek değil,
doğru analiz kapsamını belirlemektir.

### AXI-Lite Nedir? (Faz 5)

AXI = ARM'nin tasarladığı veri taşıma protokolü. **AXI-Lite** basit hali —
register erişimi için, 32-bit adres + 32-bit veri. HPS (ARM Cortex-A9) ile
FPGA fabric arasındaki köprü bu protokolle çalışır.

**Temel: VALID/READY handshake (decoupled):**
```
Master (HPS):  "Verim hazır"  →  VALID = 1
Slave  (FPGA): "Alabilirim"   →  READY = 1
İkisi aynı cycle'da '1'      →  TRANSFER GERÇEKLEŞİR
```
Kural: VALID kalkınca transfer olana kadar düşemez (sözünden dönmez). READY
serbestçe değişebilir. Bu, cdc_handshake'teki req/ack mantığının çok kanallısı.

**5 ayrı kanal (her birinin kendi VALID/READY'si):**

| Kanal | Yön | Ne işe yarar |
|-------|-----|--------------|
| **AW** | Master→Slave | "Bu adrese yazacağım" (AWADDR) |
| **W** | Master→Slave | "Veri bu" (WDATA, WSTRB) |
| **B** | Slave→Master | "Yazdım, cevap OK" (BRESP) |
| **AR** | Master→Slave | "Bu adresi oku" (ARADDR) |
| **R** | Slave→Master | "İşte veri" (RDATA, RRESP) |

- **Yazma:** AW + W + B (3 kanal sırayla)
- **Okuma:** AR + R (2 kanal)

**Response kodları (BRESP, RRESP) — 2 bit:**
- `00` OKAY (normal başarılı)
- `01` EXOKAY (exclusive — kullanmayız)
- `10` SLVERR (slave hatası)
- `11` DECERR (adres hiçbir slave'e ait değil)

**Register file + adres decoding:** Slave'in arkasında 32-bit register'lar
vardır. Adresin alt bit'leri hangi register'a erişildiğini seçer:
```
0x00 → MULTI_CLICK_WINDOW_MS (rw)
0x04 → LONG_PRESS_MS         (rw)
0x08 → DEBOUNCE_MS           (rw)
0x0C → FIFO_STATUS           (ro)
```
Linux `/dev/mem` ile sanki RAM'e erişir gibi yazar/okur. AXI-Lite Slave bu
adresleri decode edip ilgili register'a yönlendirir.

**AXI Full vs AXI-Lite:**
- Lite: tek transaction, sırayla bitmek zorunda, basit
- Full: burst, out-of-order, transaction ID — DMA için, Faz 8'de lazım olabilir

**Out-of-order Lite'ta yok** — her transaction sırayla bitmeli.

---

## Lisans ve Durum

Kişisel öğrenme kütüphanesi. Sentez için tam transparan VHDL — DO-254 audit uygun.
Faz 1, 2, 3, 4, PLL ve 6 (timing closure) tamamlandı. Sırada Faz 5 (AXI-Lite),
Faz 7 (HPS+Linux) ve Faz 8 (IMU) var. Yol haritası yukarıdadır.

## Metodoloji

- **C referansı:** Her FSM, C'deki bir kütüphanenin birebir port'idur. Header
  yorumları C fonksiyon imzalarını ve satır numaralarını belirtir.
- **Testbench + simülasyon doğrulaması:** Her modül için testbench yazılır, simülasyonda
  çalıştırılır, dalga formu incelenir. Çok zor ise ihmal edilir.
- **Kart doğrulaması:** FPGA'a yüklenip gözlemlenir.
- **Kendin yaz:** Her primitif sıfırdan yazılır, black-box IP zorunlu olmadıkça alınmaz. "Neden böyle?"
  sorusu her zaman sorulur, cevap header yorumunda yazılı olur.


"C'den FPGA'ye yolculuk" serisinin çıktısıdır. Her faz bir sonrakine
temel olur. Hedef: IMU → SPI → FIFO → AXI Full → HPS (ARM Cortex-A9) → Linux pipeline'ı.
