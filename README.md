# FPGA Çalışması

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
| `tb_button_gesture.vhd` | Buton gesture FSM: 4 senaryo | (`04_button_gesture/sim/`) |

## VHDL 2008

Bu kütüphanenin tümü VHDL 2008 standardında yazılmıştır. Derleme komutları:

```bash
# Questa/ModelSim:
vcom -2008 <dosya.vhd>

# Quartus: Settings → General → VHDL Input Version → VHDL 2008
```

## Lisans ve Rotasyon

Kişisel öğrenme kütüphanesi. Sentez için tam transparan VHDL — DO-254 audit uygun.
