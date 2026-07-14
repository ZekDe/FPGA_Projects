--------------------------------------------------------------------------------
--  tb_button_gesture.vhd  -- button_gesture FSM testbench'i
--
--  SENARYOLAR:
--    1) SINGLE click       - kisa bas/birak, window timeout -> SINGLE
--    2) MULTI (double)     - window icinde 2. basism -> MULTI count=2
--    3) LONG + REPEAT      - 300+ ms basili -> LONG, ardindan REPEAT ramp
--       + RELEASED         - birakma -> LONG_RELEASED
--    4) IGNORE             - basiliyken require_repress -> olaylar yutulur
--
--  SIM HIZ HILESI: time_base_ms'e G_CLK_HZ=1000 verilince 1 clock = 1 ms.
--  clk periyodu 20 ns -> 1 ms = 20 ns. Yani debounce_ms=20 -> 400 ns'de dolar.
--  Bu sayede 100 ms'lik senaryalar us seviyesinde simule edilir.
--
--  CONFIG (C'deki struct alanlari; sim icin kisa degerler):
--    debounce_ms=20, long_press_ms=300, multi_click_window_ms=200,
--    repeat_start_ms=100, repeat_end_ms=20, repeat_ramp_ms=500
--
--  ONEMLI: repeat_ramp_ms=500 (2^n DEGIL). Bu, pipelined divider'in gercek
--  division yaptigini test eder (eski combinational shift workaround degil).
--  Divider 32 cycle latency'li -> S_LONG_HELD'ye girdikten 32 ms sonra gercek
--  period degeri gelir. O zamana kadar period_reg = repeat_start_ms (initial).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_button_gesture is
end entity tb_button_gesture;

architecture sim of tb_button_gesture is

    constant C_CLK_PERIOD : time     := 20 ns;
    constant C_SIM_CLK_HZ : positive := 1000;   -- 1 clock = 1 ms

    -- uyaranlar
    signal clk              : std_logic := '0';
    signal rst_n            : std_logic := '0';
    signal raw_pressed      : std_logic := '0';
    signal require_repress  : std_logic := '0';

    -- zaman tabani (time_base_ms cikisi)
    signal now_ms           : unsigned(31 downto 0);

    -- config portlari (C'deki struct alanlari)
    signal debounce_ms           : unsigned(31 downto 0) := to_unsigned(20, 32);
    signal long_press_ms         : unsigned(31 downto 0) := to_unsigned(300, 32);
    signal multi_click_window_ms : unsigned(31 downto 0) := to_unsigned(200, 32);
    signal repeat_start_ms       : unsigned(31 downto 0) := to_unsigned(100, 32);
    signal repeat_end_ms         : unsigned(31 downto 0) := to_unsigned(20, 32);
    signal repeat_ramp_ms        : unsigned(31 downto 0) := to_unsigned(500, 32);

    -- DUT cikislari
    signal evt_single         : std_logic;
    signal evt_multi          : std_logic;
    signal evt_long           : std_logic;
    signal evt_long_repeat    : std_logic;
    signal evt_long_released  : std_logic;
    signal click_count        : unsigned(7 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Saat: sonsuza kadar 20 ns'de bir toggle
    ----------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- Zaman tabani: sim hiz hilesi (1 clock = 1 ms)
    ----------------------------------------------------------------------------
    u_time : entity work.time_base_ms
        generic map ( G_CLK_HZ => C_SIM_CLK_HZ, G_WIDTH => 32 )
        port map ( clk => clk, rst_n => rst_n, tick_ms => open, now_ms => now_ms );

    ----------------------------------------------------------------------------
    -- DUT (Device Under Test)
    ----------------------------------------------------------------------------
    dut : entity work.button_gesture
        port map (
            clk                   => clk,
            rst_n                 => rst_n,
            now_ms                => now_ms,
            raw_pressed           => raw_pressed,
            require_repress       => require_repress,
            debounce_ms           => debounce_ms,
            long_press_ms         => long_press_ms,
            multi_click_window_ms => multi_click_window_ms,
            repeat_start_ms       => repeat_start_ms,
            repeat_end_ms         => repeat_end_ms,
            repeat_ramp_ms        => repeat_ramp_ms,
            evt_single            => evt_single,
            evt_multi             => evt_multi,
            evt_long              => evt_long,
            evt_long_repeat       => evt_long_repeat,
            evt_long_released     => evt_long_released,
            click_count           => click_count
        );

    ----------------------------------------------------------------------------
    -- Uyaran (stimulus)
    ----------------------------------------------------------------------------
    stim : process
    begin
        -- RESET: 100 ns tut, sonra birak
        rst_n            <= '0';
        raw_pressed      <= '0';
        require_repress  <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait for 100 ns;

        --------------------------------------------------------------------
        -- TEST 1: SINGLE click
        --   50 ms basili (debounce 20 ms'i gecer) -> rise -> window acilir
        --   birak -> 200 ms window timeout -> SINGLE patlar
        --------------------------------------------------------------------
        report "TEST 1: SINGLE click - 50 ms bas, birak, window bekle";
        raw_pressed <= '1';
        wait for 1000 ns;    -- 50 ms basili
        raw_pressed <= '0';
        wait for 5000 ns;    -- 250 ms bekle (window 200 ms'de dolar -> SINGLE)

        --------------------------------------------------------------------
        -- TEST 2: MULTI (double) click
        --   1. click + birak -> window acilir (count=1)
        --   100 ms bekle (window=200ms icinde)
        --   2. click + birak -> count=2
        --   window timeout -> MULTI patlar (count=2)
        --------------------------------------------------------------------
        report "TEST 2: DOUBLE click - window icinde 2. basis";
        raw_pressed <= '1';
        wait for 1000 ns;    -- 1. click 50 ms
        raw_pressed <= '0';
        wait for 2000 ns;    -- 100 ms bekle (window icinde)
        raw_pressed <= '1';
        wait for 1000 ns;    -- 2. click 50 ms
        raw_pressed <= '0';
        wait for 5000 ns;    -- window timeout -> MULTI

        --------------------------------------------------------------------
        -- TEST 3: LONG + REPEAT + RELEASED
        --   300+ ms basili -> LONG patlar (long_press_ms=300)
        --   basili kaldikca repeat ramp: 100ms->20ms periyotla ivmelenir
        --   birakma -> LONG_RELEASED patlar
        --------------------------------------------------------------------
        report "TEST 3: LONG basili tut + REPEAT ramp + RELEASE";
        raw_pressed <= '1';
        wait for 20000 ns;   -- 1000 ms (1 sn) basili - LONG + REPEAT'ler
        raw_pressed <= '0';
        wait for 1000 ns;    -- LONG_RELEASED patlar

        --------------------------------------------------------------------
        -- TEST 4: IGNORE (require_repress)
        --   100 ms basili (long olmadan once) -> require_repress pulse
        --   state S_IGNORE'a gecer, buton birakilana kadar tum olaylar yutulur
        --   500 ms daha basili tut -> HIC event yok
        --   birakma -> S_IGNORE'dan cik
        --------------------------------------------------------------------
        report "TEST 4: IGNORE - require_repress ile olaylar yutulur";
        raw_pressed <= '1';
        wait for 2000 ns;    -- 100 ms basili (long threshold altinda)
        require_repress <= '1';
        wait for 40 ns;      -- 2 clock pulse (1 clock yeterli ama guvenli)
        require_repress <= '0';
        wait for 10000 ns;   -- 500 ms basili kalsa bile event yok
        raw_pressed <= '0';  -- release -> S_IGNORE'dan cikis
        wait for 1000 ns;

        report "Simulasyon bitti." severity note;
        wait;
    end process stim;

end architecture sim;
