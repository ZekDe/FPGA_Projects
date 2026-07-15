# MyLibs — FPGA IP Kütüphanesi

Bu klasör, FPGA donanım modüllerinin **yeniden kullanılabilir (reusable)** bloklarını
içerir. Tüm bloklar **vendor-bağımsız** (vendor-independent) VHDL ile yazılmıştır:
Quartus, Vivado, ModelSim, Questa — hepsinde çalışır. Black-box IP yoktur, DO-254
audit için tam transparan VHDL'dir.

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
| `fifo_sync.vhd` | Senkron FIFO (tek clock domain), N+1 bit full/empty, inferred BRAM | 3 | FIFO |

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

fifo_sync               [Faz 3] senkron FIFO (tek clock)
└─ (bagimlilik yok - kendi basina)
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
# Proje klasoru: xxx/
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

## Lisans ve Rotasyon

Kişisel öğrenme kütüphanesi. Sentez için tam transparan VHDL — DO-254 audit uygun.
