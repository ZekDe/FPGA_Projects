--------------------------------------------------------------------------------
--  system_top.vhd  (04_button_gesture)  -- SISTEM UST SEVIYESI: buton gesture
--
--  Konusu:
--    DE0-Nano-SoC'nin KEY[0] butonunu button_gesture FSM'ine baglar.
--    Event'leri LED'lerle gosterir. LED flash suresi 50 ms (insan gozu rahat).
--
--  LED mapping (8 LED):
--    LED[0] : SINGLE click       -> 50 ms flash
--    LED[1] : MULTI click flag   -> 50 ms flash (herhangi bir multi-click)
--    LED[2] : MULTI count bit 0  -> 50 ms (multi aninda, binary LSB)
--    LED[3] : MULTI count bit 1  -> 50 ms (multi aninda, binary MSB)
--             count=2 -> LED[3]=1            (binary 10)
--             count=3 -> LED[2,3]=1          (binary 11)
--             count=4 -> (2 bit tasmaz, 0 gozuker - 4 click nadir)
--    LED[4] : LONG               -> 50 ms flash (long threshold gecildi)
--    LED[5] : LONG_REPEAT        -> 50 ms flash (her repeat, ivmeyi gosterir)
--    LED[6] : LONG_RELEASED      -> 50 ms flash (buton birakildi)
--    LED[7] : buton basili       -> seviye (debug)
--
--  CONFIG (kart gercegi icin makul degerler - 2^n KISITLAMASI YOK):
--    (Pipelined divider sayesinde combinational division timing sorunu cozuldu.
--     Eskiden 2^n seciliyordu ki division shift_right olarak sentezlensin;
--     artik 32-stage pipelined divider gercek bolme yapiyor.)
--    debounce_ms            = 20    (mekanik bounce icin yeterli)
--    long_press_ms          = 1000  (1 sn basili tutunca LONG)
--    multi_click_window_ms  = 400   (double click icin makul pencere)
--    repeat_start_ms        = 500   (LONG sonrasi ilk repeat 0.5 sn sonra)
--    repeat_end_ms          = 100   (hizlanip 100 ms'ye iner)
--    repeat_ramp_ms         = 1000  (start->end gecisi 1 sn'de (linear ramp))
--
--  DE0-Nano-SoC: CLOCK_50=50MHz; KEY[0] buton (aktif-dusuk); SW[0] reset.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity system_top is
    generic (
        G_CLK_HZ : positive := 50_000_000
    );
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(0 downto 0);   -- KEY[0] (aktif-dusuk)
        SW       : in  std_logic_vector(0 downto 0);   -- SW[0] = reset (aktif-dusuk)
        LED      : out std_logic_vector(7 downto 0)
    );
end entity system_top;

architecture rtl of system_top is

    constant C_WIDTH : positive := 32;

    ---------------------------------------------------------------------------
    -- Board katmani sinyalleri
    ---------------------------------------------------------------------------
    signal rst_n    : std_logic;
    signal btn0_raw : std_logic;

    ---------------------------------------------------------------------------
    -- Ortak zaman tabani (C'deki global systick)
    ---------------------------------------------------------------------------
    signal systick  : unsigned(C_WIDTH-1 downto 0);

    ---------------------------------------------------------------------------
    -- button_gesture config (kart gercegi icin sabitler)
    -- Ileride: bu sabitler yerine AXI-Lite register'dan yazilan signal'ler
    -- baglanabilir (Faz 5). Su an constants ile basliyoruz.
    ---------------------------------------------------------------------------
    -- NOT: onceki versiyonda tum sabitler 2^n seciliyordu, cunku period hesabi
    -- COMBINATIONAL division (v_product / ramp_ms) yapiyordu ve 2^n ancak
    -- shift_right olarak sentezleniyordu. Ancak 50 MHz'de bu kombinasyonel yol
    -- timing slack negatif uretiyordu (LPM_DIVIDE cok yavas).
    --
    -- Faz 6 on-adiminda pipelined divider (divider_pipelined.vhd) entegre
    -- edildi: 32-stage pipeline, 32 cycle latency, 1/cycle throughput, vendor
    -- bagimsiz, DO-254 audit'e uygun tam transparan VHDL. Artik division
    -- KAYITLI stage'lerde calistigi icin 2^n kısıtlaması YOKTUR. Kart gercegi
    -- icin makul (2^n olmayan) degerler kullanabiliriz. Simulasyonda
    -- repeat_ramp_ms=500 ile dogrulandi (divider gercek bolme yapiyor).
    ---------------------------------------------------------------------------
    constant C_DEBOUNCE_MS           : unsigned(C_WIDTH-1 downto 0) := to_unsigned(20,   C_WIDTH);  -- 20   ms (mekanik bounce)
    constant C_LONG_PRESS_MS         : unsigned(C_WIDTH-1 downto 0) := to_unsigned(1000, C_WIDTH);  -- 1    sn (long press threshold)
    constant C_MULTI_CLICK_WINDOW_MS : unsigned(C_WIDTH-1 downto 0) := to_unsigned(400,  C_WIDTH);  -- 400  ms (double-click penceresi)
    constant C_REPEAT_START_MS       : unsigned(C_WIDTH-1 downto 0) := to_unsigned(500,  C_WIDTH);  -- 500  ms (LONG sonrasi ilk repeat)
    constant C_REPEAT_END_MS         : unsigned(C_WIDTH-1 downto 0) := to_unsigned(100,  C_WIDTH);  -- 100  ms (ivmelenme sonu, en hizli)
    constant C_REPEAT_RAMP_MS        : unsigned(C_WIDTH-1 downto 0) := to_unsigned(3000, C_WIDTH);  -- 1    sn (start->end linear ramp)

    ---------------------------------------------------------------------------
    -- button_gesture cikislari
    ---------------------------------------------------------------------------
    signal evt_single         : std_logic;
    signal evt_multi          : std_logic;
    signal evt_long           : std_logic;
    signal evt_long_repeat    : std_logic;
    signal evt_long_released  : std_logic;
    signal click_count        : unsigned(7 downto 0);

    ---------------------------------------------------------------------------
    -- LED pulse stretcher cikislari (50 ms)
    ---------------------------------------------------------------------------
    signal led_single   : std_logic;
    signal led_multi    : std_logic;
    signal led_long     : std_logic;
    signal led_repeat   : std_logic;
    signal led_released : std_logic;

    ---------------------------------------------------------------------------
    -- MULTI count latch: evt_multi geldiginde count'u yakala, 50 ms boyunca
    -- LED[3:2]'de binary goster. Bu sayede double/triple click sayisi okunur.
    ---------------------------------------------------------------------------
    constant C_COUNT_CYCLES : positive := (G_CLK_HZ / 1000) * 50;   -- 50 ms
    signal count_latch      : unsigned(1 downto 0) := (others => '0');
    signal count_timer      : integer range 0 to C_COUNT_CYCLES := 0;

begin

    ---------------------------------------------------------------------------
    -- BOARD POLARITESI: aktif-dusuk pinleri mantiga cevir (sadece burada)
    ---------------------------------------------------------------------------
    rst_n    <= SW(0);
    btn0_raw <= not KEY(0);

    ---------------------------------------------------------------------------
    -- ORTAK systick (tek sefer uretilir)
    ---------------------------------------------------------------------------
    u_systick : entity work.time_base_ms
        generic map ( G_CLK_HZ => G_CLK_HZ, G_WIDTH => C_WIDTH )
        port map ( clk => CLOCK_50, rst_n => rst_n, tick_ms => open, now_ms => systick );

    ---------------------------------------------------------------------------
    -- BUTON GESTURE FSM
    ---------------------------------------------------------------------------
    u_btn : entity work.button_gesture
        port map (
            clk                   => CLOCK_50,
            rst_n                 => rst_n,
            now_ms                => systick,
            raw_pressed           => btn0_raw,
            require_repress       => '0',                       -- su an kullanilmiyor
            debounce_ms           => C_DEBOUNCE_MS,
            long_press_ms         => C_LONG_PRESS_MS,
            multi_click_window_ms => C_MULTI_CLICK_WINDOW_MS,
            repeat_start_ms       => C_REPEAT_START_MS,
            repeat_end_ms         => C_REPEAT_END_MS,
            repeat_ramp_ms        => C_REPEAT_RAMP_MS,
            evt_single            => evt_single,
            evt_multi             => evt_multi,
            evt_long              => evt_long,
            evt_long_repeat       => evt_long_repeat,
            evt_long_released     => evt_long_released,
            click_count           => click_count
        );

    ---------------------------------------------------------------------------
    -- LED PULSE STRETCHER'lar (her event icin 50 ms flash)
    --    1-clock pulse -> 50 ms yanik LED (insan gozu rahat)
    ---------------------------------------------------------------------------
    u_led_single  : entity work.led_pulse
        generic map ( G_CLK_HZ => G_CLK_HZ, G_ON_MS => 50 )
        port map ( clk => CLOCK_50, rst_n => rst_n, pulse => evt_single,        led => led_single );

    u_led_multi   : entity work.led_pulse
        generic map ( G_CLK_HZ => G_CLK_HZ, G_ON_MS => 50 )
        port map ( clk => CLOCK_50, rst_n => rst_n, pulse => evt_multi,         led => led_multi );

    u_led_long    : entity work.led_pulse
        generic map ( G_CLK_HZ => G_CLK_HZ, G_ON_MS => 50 )
        port map ( clk => CLOCK_50, rst_n => rst_n, pulse => evt_long,          led => led_long );

    u_led_repeat  : entity work.led_pulse
        generic map ( G_CLK_HZ => G_CLK_HZ, G_ON_MS => 50 )
        port map ( clk => CLOCK_50, rst_n => rst_n, pulse => evt_long_repeat,   led => led_repeat );

    u_led_released: entity work.led_pulse
        generic map ( G_CLK_HZ => G_CLK_HZ, G_ON_MS => 50 )
        port map ( clk => CLOCK_50, rst_n => rst_n, pulse => evt_long_released, led => led_released );

    ---------------------------------------------------------------------------
    -- MULTI COUNT LATCH
    --    evt_multi pulse'i geldigi tick'te click_count(1:0)'i yakala,
    --    50 ms boyunca LED[3:2]'de binary olarak tut.
    --    Bu, "double mu triple mi?" sorusunun LED'lerden okunmasini saglar.
    ---------------------------------------------------------------------------
    p_count_latch : process(CLOCK_50, rst_n)
    begin
        if rst_n = '0' then
            count_latch <= (others => '0');
            count_timer <= 0;
        elsif rising_edge(CLOCK_50) then
            if evt_multi = '1' then
                count_latch <= click_count(1 downto 0);   -- max 4 click (2 bit)
                count_timer <= C_COUNT_CYCLES;             -- 50 ms sayaci baslat
            elsif count_timer > 0 then
                count_timer <= count_timer - 1;
            end if;
        end if;
    end process p_count_latch;

    ---------------------------------------------------------------------------
    -- LED mapping
    ---------------------------------------------------------------------------
    LED(0) <= led_single;
    LED(1) <= led_multi;
    LED(2) <= count_latch(0) when count_timer > 0 else '0';
    LED(3) <= count_latch(1) when count_timer > 0 else '0';
    LED(4) <= led_long;
    LED(5) <= led_repeat;
    LED(6) <= led_released;
    LED(7) <= btn0_raw;          -- buton basili (debug)

end architecture rtl;
