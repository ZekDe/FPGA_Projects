--------------------------------------------------------------------------------
--  two_button_top.vhd  -- iki butonun PARALEL debounce zinciri
--
--  FIKIR: Tek bir ORTAK SysTick (time_base_ms) 'now_ms' uretir. Iki buton
--  zinciri bu ayni 'now_ms'i paylasir ama her biri kendi TON'una (kendi 'since'
--  ve 'aux') sahiptir. Iki zincir donanimda AYNI ANDA, birbirinden bagimsiz
--  calisir -- FPGA paralelliginin ta kendisi. C'de olsaydin iki TON'u sirayla
--  cagirirdin; burada ikisi ayni clock kenarinda es zamanli isler.
--
--    CLOCK_50 --> time_base_ms --now_ms--+--> ton1 (100 ms) --> ed1 --> btn1_pulse
--                                        |         `--> btn1_on_pressed
--    KEY[0] --> sync1 --> ton1.in_sig    |
--                                        |
--    KEY[1] --> sync2 --> ton2.in_sig    +--> ton2 (150 ms) --> ed2 --> btn2_pulse
--                                                  `--> btn2_on_pressed
--
--  Sinyaller (istenildigi gibi):
--    btn1_on_pressed / btn2_on_pressed : TON cikislari (seviye: preset kadar
--                                        kesintisiz basili kalindi mi)
--    btn1_pulse      / btn2_pulse      : edge detector cikislari (tek-tick tetik)
--
--  DE0-Nano pin gercekleri:
--    CLOCK_50 = 50 MHz ; KEY[0], KEY[1] iki buton (AKTIF-DUSUK: basili=0)
--    SW[0] = reset (slide switch); LED[3:0] cikislari gosterir
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity two_button_top is
    generic (
        G_CLK_HZ     : positive := 50_000_000;   -- clock frekansi (sim'de 1000 verilir)
        G_PRESET1_MS : natural  := 100;          -- buton1 debounce/on-delay suresi
        G_PRESET2_MS : natural  := 150           -- buton2 debounce/on-delay suresi
    );
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(1 downto 0);   -- iki buton (aktif-dusuk)
        SW       : in  std_logic_vector(0 downto 0);   -- SW[0] = reset (aktif-dusuk)
        LED      : out std_logic_vector(7 downto 0)
    );
end entity two_button_top;

architecture rtl of two_button_top is

    constant C_WIDTH : positive := 32;

    signal rst_n  : std_logic;
    signal now_ms : unsigned(C_WIDTH - 1 downto 0);   -- ORTAK zaman tabani

    -- Buton 1 zinciri sinyalleri
    signal btn1_raw        : std_logic;
    signal btn1_sync       : std_logic;
    signal btn1_on_pressed : std_logic;               -- TON1 cikisi (seviye)
    signal btn1_pulse      : std_logic;               -- ED1 cikisi (tek-tick)

    -- Buton 2 zinciri sinyalleri
    signal btn2_raw        : std_logic;
    signal btn2_sync       : std_logic;
    signal btn2_on_pressed : std_logic;               -- TON2 cikisi (seviye)
    signal btn2_pulse      : std_logic;               -- ED2 cikisi (tek-tick)

begin

    -- Reset ve buton polariteleri (KEY/SW aktif-dusuk: basili/acik = 0)
    rst_n    <= SW(0);
    btn1_raw <= not KEY(0);   -- basili = 1 istiyoruz
    btn2_raw <= not KEY(1);

    ----------------------------------------------------------------------------
    -- ORTAK SysTick: tek bir now_ms, iki zincir de bunu paylasir
    ----------------------------------------------------------------------------
    u_time : entity work.time_base_ms
        generic map ( G_CLK_HZ => G_CLK_HZ, G_WIDTH => C_WIDTH )
        port map    ( clk => CLOCK_50, rst_n => rst_n, tick_ms => open, now_ms => now_ms );

    ----------------------------------------------------------------------------
    -- BUTON 1 zinciri: sync -> ton(100 ms) -> edge
    ----------------------------------------------------------------------------
    u_sync1 : entity work.synchronizer
        generic map ( G_STAGES => 2, G_RST_VAL => '0' )
        port map    ( clk => CLOCK_50, rst_n => rst_n, async_in => btn1_raw, sync_out => btn1_sync );

    u_ton1 : entity work.ton
        generic map ( G_WIDTH => C_WIDTH )
        port map (
            clk         => CLOCK_50,
            rst_n       => rst_n,
            in_sig      => btn1_sync,
            now_ms      => now_ms,
            preset_time => to_unsigned(G_PRESET1_MS, C_WIDTH),
            retval      => btn1_on_pressed,
            since       => open
        );

    u_ed1 : entity work.edge_detector
        port map ( clk => CLOCK_50, rst_n => rst_n, val => btn1_on_pressed, retval => btn1_pulse );

    ----------------------------------------------------------------------------
    -- BUTON 2 zinciri: sync -> ton(150 ms) -> edge   (buton 1 ile birebir ayni,
    -- sadece preset farkli) -- iki kopya, ayni anda calisir
    ----------------------------------------------------------------------------
    u_sync2 : entity work.synchronizer
        generic map ( G_STAGES => 2, G_RST_VAL => '0' )
        port map    ( clk => CLOCK_50, rst_n => rst_n, async_in => btn2_raw, sync_out => btn2_sync );

    u_ton2 : entity work.ton
        generic map ( G_WIDTH => C_WIDTH )
        port map (
            clk         => CLOCK_50,
            rst_n       => rst_n,
            in_sig      => btn2_sync,
            now_ms      => now_ms,
            preset_time => to_unsigned(G_PRESET2_MS, C_WIDTH),
            retval      => btn2_on_pressed,
            since       => open
        );

    u_ed2 : entity work.edge_detector
        port map ( clk => CLOCK_50, rst_n => rst_n, val => btn2_on_pressed, retval => btn2_pulse );

    ----------------------------------------------------------------------------
    -- Cikislar
    ----------------------------------------------------------------------------
    LED(0)          <= btn1_on_pressed;
    LED(1)          <= btn2_on_pressed;
    LED(2)          <= btn1_pulse;
    LED(3)          <= btn2_pulse;
    LED(7 downto 4) <= (others => '0');

end architecture rtl;
