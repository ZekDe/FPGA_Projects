--------------------------------------------------------------------------------
--  tb_button_chain.vhd  -- buton zinciri testbench'i (sync -> ton -> edge)
--
--  AMAC: Karti hic programlamadan, zincirin dogru calistigini dalga formunda
--        gormek. Ozellikle:
--          - Buton "ziplamasini" (bounce) TON eliyor mu?
--          - Kisa (gurultu) basmalar cikisi tetikliyor mu? (tetiklememeli)
--          - Gercek uzun bas -> ton_q '1', ve o anda tek-tick pulse cikiyor mu?
--
--  TESTBENCH bir "entity"dir ama port'u YOKTUR: disariya baglanmaz, kendi
--  icinde saat ve uyaranlari (stimulus) uretir, DUT'u (Device Under Test)
--  ornekler ve gozler. Sentezlenmez -- sadece simulasyonda calisir; bu yuzden
--  'wait', 'after' gibi sentezlenemez ama simulasyonda cok kullanisli
--  ifadeleri serbestce kullaniriz.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_button_chain is
    -- port yok
end entity tb_button_chain;

architecture sim of tb_button_chain is

    -- Simulasyonda gercek saat periyodunu kullanmak zorunda degiliz ama
    -- gercekci olsun diye 50 MHz = 20 ns periyot seciyoruz.
    constant C_CLK_PERIOD : time := 20 ns;

    -- SIM HIZI HILESI: preset artik MILISANIYE. Gercek kartta time_base_ms
    -- G_CLK_HZ=50_000_000 ile 1 ms = 50_000 clock sayar -> 20 ms = 1_000_000 clock,
    -- sim'de saatlerce surer. Cozum: sim'de time_base_ms'e G_CLK_HZ=1000 ver ->
    -- C_CYC_PER_MS = 1000/1000 = 1, yani HER CLOCK = 1 ms. Boylece now_ms her clock
    -- 1 artar, 20 ms = 20 clock = 400 ns. Arayuz ms olarak KALIR (preset=20 ms).
    constant C_SIM_CLK_HZ : positive := 1000;    -- sim'de sahte frekans: 1 clock = 1 ms
    constant C_PRESET_MS  : natural  := 20;      -- 20 ms preset (kart: 100 ms)
    constant C_CNT_WIDTH  : positive := 32;

    signal clk     : std_logic := '0';
    signal rst_n   : std_logic := '0';
    signal btn_raw : std_logic := '0';   -- butonun aktif-yuksek hali (basili=1)

    -- ic sinyaller (gozlem icin)
    signal now_ms   : unsigned(C_CNT_WIDTH - 1 downto 0);   -- ortak zaman (=C'deki now)
    signal btn_sync : std_logic;
    signal ton_q    : std_logic;
    signal pulse    : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Saat ureteci: sonsuza kadar 20 ns'de bir toggle
    ----------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- DUT: zinciri elle kuruyoruz (top yerine bilesenleri dogrudan baglayarak,
    -- boylece preset'i simulasyon degeriyle verebiliyoruz).
    ----------------------------------------------------------------------------
    -- ZAMAN TABANI: sim'de 1 clock = 1 ms (G_CLK_HZ=1000) -> now_ms uretir
    u_time : entity work.time_base_ms
        generic map ( G_CLK_HZ => C_SIM_CLK_HZ, G_WIDTH => C_CNT_WIDTH )
        port map ( clk => clk, rst_n => rst_n, tick_ms => open, now_ms => now_ms );

    u_sync : entity work.synchronizer
        generic map ( G_STAGES => 2, G_RST_VAL => '0' )
        port map ( clk => clk, rst_n => rst_n, async_in => btn_raw, sync_out => btn_sync );

    u_ton : entity work.ton
        generic map ( G_WIDTH => C_CNT_WIDTH )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            in_sig      => btn_sync,
            now_ms      => now_ms,
            preset_time => to_unsigned(C_PRESET_MS, C_CNT_WIDTH),
            retval      => ton_q,
            since       => open
        );

    u_edge : entity work.edge_detector
        port map ( clk => clk, rst_n => rst_n, val => ton_q, retval => pulse );

    ----------------------------------------------------------------------------
    -- Uyaran (stimulus) sureci: butona cesitli sekillerde "basiyoruz"
    ----------------------------------------------------------------------------
    stim : process
    begin
        -- 1) Reset uygula (aktif-dusuk): 100 ns tut, sonra birak
        rst_n   <= '0';
        btn_raw <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait for 100 ns;

        -- 2) MEKANIK ZIPLAMA (bounce): buton basiliyor ama ilk anda titriyor.
        --    Kisa 0/1 sicramalar. TON bunlari ELEMELI -> ton_q '0' kalmali.
        report "TEST 1: bounce (ziplamali kisa darbeler) - cikis tetiklenmemeli";
        btn_raw <= '1'; wait for 60 ns;
        btn_raw <= '0'; wait for 40 ns;
        btn_raw <= '1'; wait for 80 ns;
        btn_raw <= '0'; wait for 50 ns;
        -- toplam basili sure kesintiye ugradi, preset (400 ns) dolmadi

        -- 3) Bir sure tamamen birak (buton serbest)
        btn_raw <= '0';
        wait for 500 ns;

        -- 4) GERCEK UZUN BAS: kesintisiz 1000 ns basili tut.
        --    ~100 ns senkron gecikme + 400 ns preset sonrasi ton_q '1' olmali,
        --    ve o anda 'pulse' tek-tick '1' vermeli.
        report "TEST 2: gercek uzun bas - preset sonrasi cikis '1' + tek pulse";
        btn_raw <= '1';
        wait for 1000 ns;

        -- 5) Butonu birak -> ton_q ve sayac sifirlanmali
        report "TEST 3: birakma - cikis '0'a donmeli";
        btn_raw <= '0';
        wait for 300 ns;

        report "Simulasyon bitti." severity note;
        wait;  -- sureci sonsuza kadar beklet (simulasyonu durdurur)
    end process stim;

end architecture sim;
