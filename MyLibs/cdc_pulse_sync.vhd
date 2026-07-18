--------------------------------------------------------------------------------
--  cdc_pulse_sync.vhd  -- Toggle synchronizer (1-clock pulse, async domain)
--
--  AMAC:
--    Kaynak clock domain'indeki 1-clock pulse'u, hedef clock domain'inde
--    yine 1-clock pulse olarak GUVENLI sekilde tasi. Iki domain asenkron ise
--    (farkli frekans ya da farkli osilator) 2-FF synchronizer tek basina
--    YETERLI DEGILDIR, cunku:
--      - 2-FF LEVEL tasir, pulse DEGIL.
--      - Hedef clock kaynak clock'tan yavassa, kaynak pulse'u iki hedef
--        clock kenari arasinda tamamen kaybolabilir (sampling miss).
--
--  COZUM: pulse -> toggle -> 2-FF -> XOR kenar tespiti -> pulse
--    1) Kaynak domain: her pulse_in'de bir toggle FF terslenir.
--       toggle artik LEVEL'dir (pulse degil) -> hic daralmaz.
--    2) 2-FF synchronizer toggle'i hedef domain'e tasir (metastability onlemi).
--    3) Hedef domain: toggle'in her degisimini XOR ile yakalar (1-clock pulse).
--
--  NEDEN 2-FF YETMEZ DE TOGGLE GEREKIR?
--    2-FF, girisini 2 clock sonra cikisa kopyalar. Girisi 1-clock pulse ise,
--    cikis ya o pulse'u (gecikmeli) verir ya da tamamen gostermez -- hedef
--    clock'un pulse'u kacirma olasiligina bagli. Toggle ise girisi bir
--    "durum degisimine" cevirir; durum ne kadar yavas orneklenirse ornelensin
--    her zaman yakalanir.
--
--  NEDEN HANDSHAKE DEGIL DE TOGGLE?
--    Handshake (cdc_handshake_tx/rx) cok-bit veri tasiyabilir ve back-pressure
--    saglar. Ama tek-bit event pulse icin asiri gelir (2 FSM, ~80 satir).
--    Toggle sync sadece 1-bit pulse tasiyacaksa en sade ve dogru cozum.
--    Handshake, multi-bit veri ya da back-pressure gerektiginde kullanilmali.
--
--  RATE SINIRI (ONEMLI):
--    Kaynak domain, hedef domain 2-3 clock ornekleyene kadar yeni pulse
--    uretmemelidir. Yoksa iki toggle degisimi arka arkaya gelir, hedef
--    domain tek pulse olarak gorur -> pulse YUTULUR.
--    Hesap: hedef frekans * 3 >= maksimum kaynak pulse rate.
--    Oneri: hedef clock >= 3x kaynak event rate.
--    Buton/insan hizi uygulamalari icin sorun degil (200 ms aralikla basilan
--    buton, 33 MHz domain'de 6.6M clock aralik demek,button_gesture gibi).
--
--  METASTABILITY ve FF DERINLIGI:
--    G_STAGES parametresi 2-FF zincirinin kademelerini belirler.
--      G_STAGES=2 : ticari standart, MTBF yillar (Cyclone V, 100 MHz tipik)
--      G_STAGES=3 : yuksek guvenilirlik (uzay/otomotiv/medikal), MTBF binlerce yil
--    Ilk FF metastable olabilir; her ek kademede MTBF ustel artar.
--
--  KULLANIM:
--    u_wr_pulse : entity work.cdc_pulse_sync
--      generic map ( G_STAGES => 2 )
--      port map (
--          src_clk   => CLOCK_50,    -- kaynak domain (pulse'in uretildigi yer)
--          pulse_in  => evt_single,  -- 1-clock pulse (kaynak domain)
--          dst_clk   => wr_clk,      -- hedef domain (pulse'in kullanilacagi yer)
--          rst_n     => rst_n,       -- asenkron reset (her iki domain'de ortak)
--          pulse_out => wr_pulse     -- 1-clock pulse (hedef domain)
--      );
--
--  ONEMLI:
--    - pulse_in MUTLAKA 1-clock pulse olmalidir. Level (sabit '1') olarak
--      tutulursa her src_clk'ta toggle degisir -> hedef domain'de kasitli
--      olmayan pulse dizisi uretilir.
--    - rst_n her iki domain tarafindan da gorulmelidir. Asenkron reset oldugu
--      icin domainler arasi senkronize edilmesi sart degil (kart reseti).
--      Reset sonrasi toggle=0, toggle_sync=0, toggle_sync_d=0 -> pulse_out=0.
--      Ilk pulse'ta toggle 0->1, hedef domain bunu temiz bir pulse olarak verir.
--    - G_STAGES >= 2 olmali. 1 kademe metastability icin YETERSIZDIR.
--
--  BAGIMLILIKLAR:
--    - synchronizer  (2-FF CDC, G_STAGES parametreli)
--
--  ILISKILI MODULLER:
--    - cdc_handshake_tx/rx : cok-bit veri tasiyacaksa bunun yerine kullan
--    - gray_pkg            : cok-bit counter/pointer tasiyacaksa kullan
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity cdc_pulse_sync is
    generic (
        G_STAGES : positive := 2          -- 2-FF derinligi (min 2 onerilir)
    );
    port (
        -- kaynak domain
        src_clk   : in  std_logic;
        pulse_in  : in  std_logic;        -- 1-clock pulse (kaynak domain)

        -- hedef domain
        dst_clk   : in  std_logic;
        rst_n     : in  std_logic;        -- asenkron reset (her iki domain)
        pulse_out : out std_logic         -- 1-clock pulse (hedef domain)
    );
end entity cdc_pulse_sync;


architecture rtl of cdc_pulse_sync is

    --------------------------------------------------------------------------
    -- KAYNAK DOMAIN: toggle FF
    -- pulse_in her geldiginde toggle'i tersle. toggle artik LEVEL'dir:
    -- ne kadar yavas orneklenirse ornelensin hedef domain mutlaka gorur.
    --------------------------------------------------------------------------
    signal toggle : std_logic := '0';

    --------------------------------------------------------------------------
    -- HEDEF DOMAIN: senkronize toggle + 1-clock gecikmeli kopya (kenar icin)
    -- toggle_sync  : 2-FF cikisi (hedef domain'de oturmus toggle)
    -- toggle_sync_d: toggle_sync'in 1 clock onceki degeri (XOR kenar icin)
    --------------------------------------------------------------------------
    signal toggle_sync   : std_logic := '0';
    signal toggle_sync_d : std_logic := '0';

begin

    --------------------------------------------------------------------------
    -- [1] KAYNAK DOMAIN: pulse_in -> toggle (level)
    --------------------------------------------------------------------------
    -- Her pulse_in=1 aninda toggle terslenir. pulse_in 1-clock pulse ise,
    -- her pulse'a tam 1 toggle degisimi karsilik gelir (birebir eslesme).
    --------------------------------------------------------------------------
    p_toggle : process(src_clk, rst_n)
    begin
        if rst_n = '0' then
            toggle <= '0';
        elsif rising_edge(src_clk) then
            if pulse_in = '1' then
                toggle <= not toggle;
            end if;
        end if;
    end process p_toggle;

    --------------------------------------------------------------------------
    -- [2] 2-FF SENKRONIZATORU: toggle'i hedef domain'e tasi
    -- Tek bit tasidigimiz icin 2-FF guvenli (multi-bit CDC sorunu yok).
    -- G_STAGES generic'i disaridan alinir; metastability derinligini belirler.
    --------------------------------------------------------------------------
    u_sync : entity work.synchronizer
        generic map ( G_STAGES => G_STAGES, G_RST_VAL => '0' )
        port map (
            clk      => dst_clk,
            rst_n    => rst_n,
            async_in => toggle,
            sync_out => toggle_sync
        );

    --------------------------------------------------------------------------
    -- [3] HEDEF DOMAIN: XOR kenar tespiti -> 1-clock pulse
    -- toggle_sync degistigi TEK clock'ta XOR cikisi 1 olur, sonra 0'a doner.
    -- Boylece hedef domain'de kaynak pulse'ina karsilik 1-clock pulse uretilir.
    --------------------------------------------------------------------------
    p_edge : process(dst_clk, rst_n)
    begin
        if rst_n = '0' then
            toggle_sync_d <= '0';
            pulse_out     <= '0';
        elsif rising_edge(dst_clk) then
            toggle_sync_d <= toggle_sync;
            pulse_out     <= toggle_sync xor toggle_sync_d;
        end if;
    end process p_edge;

end architecture rtl;
