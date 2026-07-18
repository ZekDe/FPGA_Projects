--------------------------------------------------------------------------------
--  system_top.vhd  (06_fifo_async)  -- ASYNC FIFO + PLL + CDC demo
--
--  DOSYA LISTESI (Quartus projesine eklenmesi gereken dosyalar):
--  ============================================================
--    set_global_assignment -name VHDL_FILE ../MyLibs/synchronizer.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/time_base_ms.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/ton.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/edge_detector.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/divider_pipelined.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/button_gesture.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/gray_pkg.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/fifo_async.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/cdc_pulse_sync.vhd
--    set_global_assignment -name VHDL_FILE src/system_top.vhd
--
--  BAGIMLILIK AGACI:
--    system_top
--    +-_ pll_2clk             <- IP: 50 MHz -> 100 MHz (wr) + 33 MHz (rd)
--    +-_ time_base_ms         <- systick (CLOCK_50 domain)
--    +-_ button_gesture (x2)  <- KEY[0]=yazma, KEY[1]=okuma (CLOCK_50 domain)
--    |   +- synchronizer
--    |   +- ton
--    |   +- divider_pipelined
--    +-_ cdc_pulse_sync (x2)  <- evt_single CLOCK_50 -> wr_clk / rd_clk
--    |   +- synchronizer
--    +-_ fifo_async           <- async FIFO (wr_clk / rd_clk domain'leri)
--        +- gray_pkg
--        +- synchronizer
--
--  MIMARI:
--    3 clock domain var:
--      CLOCK_50  (50 MHz)  -> button_gesture / systick / UI
--      wr_clk    (100 MHz) -> FIFO yazma tarafi
--      rd_clk    (33  MHz) -> FIFO okuma tarafi
--    3 domain karsilikli ASENKRON (SDC: set_clock_groups -asynchronous).
--
--  BUTON -> FIFO AKISI:
--    KEY[0] (CLOCK_50) -> evt_single0 -> cdc_pulse_sync -> wr_pulse (wr_clk)
--                                                            -> wr_en -> FIFO yaz
--    KEY[1] (CLOCK_50) -> evt_single1 -> cdc_pulse_sync -> rd_pulse (rd_clk)
--                                                            -> rd_en -> FIFO oku
--    SW[3:1] -> 2-FF vector sync (wr_clk) -> fifo_wr_data
--
--  KART GIRIS/CIKIS:
--    CLOCK_50 : 50 MHz saat (PLL referans + button_gesture domain)
--    KEY[0]   : buton (aktif-dusuk) -> yazma (FIFO'ya SW'den veri yaz)
--    KEY[1]   : buton (aktif-dusuk) -> okuma (FIFO'dan veri oku)
--    SW[0]    : reset (aktif-dusuk) -> SW[0]=0 iken reset
--    SW[3:1]  : 3-bit veri (FIFO'ya yazilacak deger)
--    LED[3:0] : okunan son veri (alt 4 bit)
--    LED[5]   : PLL locked
--    LED[6]   : FIFO empty
--    LED[7]   : FIFO full
--------------------------------------------------------------------------------
library ieee;
library pll_2clk;
use work.gray_pkg.all;  
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity system_top is
    generic (
        G_CLK_HZ : positive := 50_000_000
    );
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(1 downto 0);   -- KEY[0]=yaz, KEY[1]=oku
        SW       : in  std_logic_vector(3 downto 0);   -- SW[0]=reset, SW[3:1]=veri
        LED      : out std_logic_vector(7 downto 0)
    );
end entity system_top;


architecture rtl of system_top is

    -- =========================================================================
    --  SABITLER
    -- =========================================================================
    constant C_WIDTH : positive := 32;

    -- button_gesture config (kart gercegi icin makul degerler)
    constant C_DEBOUNCE_MS           : unsigned(C_WIDTH-1 downto 0) := to_unsigned(20,   C_WIDTH);
    constant C_LONG_PRESS_MS         : unsigned(C_WIDTH-1 downto 0) := to_unsigned(1000, C_WIDTH);
    constant C_MULTI_CLICK_WINDOW_MS : unsigned(C_WIDTH-1 downto 0) := to_unsigned(400,  C_WIDTH);
    constant C_REPEAT_START_MS       : unsigned(C_WIDTH-1 downto 0) := to_unsigned(500,  C_WIDTH);
    constant C_REPEAT_END_MS         : unsigned(C_WIDTH-1 downto 0) := to_unsigned(100,  C_WIDTH);
    constant C_REPEAT_RAMP_MS        : unsigned(C_WIDTH-1 downto 0) := to_unsigned(1000, C_WIDTH);

    -- =========================================================================
    --  CLOCK / RESET
    -- =========================================================================
    signal rst_n      : std_logic;     -- kart reset (SW[0])
    signal wr_clk     : std_logic;     -- PLL outclk_0 = 100 MHz (write domain)
    signal rd_clk     : std_logic;     -- PLL outclk_1 = 33  MHz (read domain)
    signal locked     : std_logic;     -- PLL kilitlendi mi
    signal fifo_rst_n : std_logic;     -- FIFO reset = kart reset AND locked

    -- =========================================================================
    --  BUTON DIZISI (for...generate ile iki buton)
    -- =========================================================================
    type sl_array_2_t is array (1 downto 0) of std_logic;
    signal btn_raw           : sl_array_2_t;
    signal evt_single        : sl_array_2_t;
    signal evt_multi         : sl_array_2_t;
    signal evt_long          : sl_array_2_t;
    signal evt_long_repeat   : sl_array_2_t;
    signal evt_long_released : sl_array_2_t;

    type t_click_count_array is array (1 downto 0) of unsigned(7 downto 0);
    signal click_count : t_click_count_array;

    signal systick : unsigned(C_WIDTH-1 downto 0);

    -- =========================================================================
    --  CDC: event pulse'lari CLOCK_50 -> wr_clk / rd_clk
    -- =========================================================================
    -- evt_single(0) CLOCK_50'de uretiliyor -> wr_clk domain'inde wr_pulse
    -- evt_single(1) CLOCK_50'de uretiliyor -> rd_clk domain'inde rd_pulse
    signal wr_pulse : std_logic;       -- wr_clk domain'inde 1-clock pulse
    signal rd_pulse : std_logic;       -- rd_clk domain'inde 1-clock pulse

    -- =========================================================================
    --  ASYNC FIFO sinyalleri
    -- =========================================================================
    signal fifo_wr_en   : std_logic;
    signal fifo_wr_data : std_logic_vector(7 downto 0);
    signal fifo_full    : std_logic;
    signal fifo_rd_en   : std_logic;
    signal fifo_rd_data : std_logic_vector(7 downto 0);
    signal fifo_empty   : std_logic;

    -- =========================================================================
    --  SW[3:1] -> wr_clk domain (2-FF vector sync)
    -- =========================================================================
    -- SW insandan gelir (yavas) ama yine de wr_clk domain'inde 2-FF ile
    -- oturtmak iyi pratik (metastability onlemi). synchronizer.vhd tek bit
    -- icin tasarlanmis, bu yuzden vector sync'i burada ayri yazdik.
    signal sw_data_meta : std_logic_vector(2 downto 0);
    signal sw_data_sync : std_logic_vector(2 downto 0);

    -- =========================================================================
    --  "Son okunan" register'i (LED'de gostermek icin)
    -- =========================================================================
    signal last_rd_data : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- =========================================================================
    --  COMBINATIONAL
    -- =========================================================================
    rst_n <= SW(0);

    btn_raw(0) <= not KEY(0);
    btn_raw(1) <= not KEY(1);

    -- FIFO reset: kart reset VE PLL kilitli. PLL kilitlenmeden FIFO'yu reset'te
    -- tutmak, gray pointer'larin stabil baslamasini saglar (Cummings onerisi).
    fifo_rst_n <= rst_n and locked;

    -- FIFO'ya yazilan veri: SW[3:1] 3-bit, FIFO 8-bit (alt 3 bit kullanilir).
    fifo_wr_data <= "00000" & sw_data_sync;

    -- =========================================================================
    --  LED MAPPING
    -- =========================================================================
    -- LED[3:0] = okunan son veri (alt 4 bit)
    -- LED[5]   = PLL locked (kilit durumu)
    -- LED[6]   = FIFO empty
    -- LED[7]   = FIFO full
    -- LED[4]   = bos (ileride wr/rd activity gostergesi yapilabilir)
    LED(3 downto 0) <= last_rd_data(3 downto 0);
    LED(4)          <= '0';
    LED(5)          <= locked;
    LED(6)          <= fifo_empty;
    LED(7)          <= fifo_full;

    -- =========================================================================
    --  SYSTICK (CLOCK_50 domain)
    -- =========================================================================
    u_systick : entity work.time_base_ms
        generic map ( G_CLK_HZ => G_CLK_HZ, G_WIDTH => C_WIDTH )
        port map ( clk => CLOCK_50, rst_n => rst_n, tick_ms => open, now_ms => systick );

    -- =========================================================================
    --  BUTON GESTURE FSM'leri (for...generate ile iki buton)
    -- =========================================================================
    -- Iki buton ayni config ile calisir, sadece raw_pressed ve evt cikislari
    -- farkli. for...generate bu tekrari tek blokta toplar.
    gen_buttons : for i in 0 to 1 generate
        u_button_gesture : entity work.button_gesture
            port map (
                clk                   => CLOCK_50,
                rst_n                 => rst_n,
                now_ms                => systick,
                raw_pressed           => btn_raw(i),
                require_repress       => '0',
                debounce_ms           => C_DEBOUNCE_MS,
                long_press_ms         => C_LONG_PRESS_MS,
                multi_click_window_ms => C_MULTI_CLICK_WINDOW_MS,
                repeat_start_ms       => C_REPEAT_START_MS,
                repeat_end_ms         => C_REPEAT_END_MS,
                repeat_ramp_ms        => C_REPEAT_RAMP_MS,
                evt_single            => evt_single(i),
                evt_multi             => evt_multi(i),
                evt_long              => evt_long(i),
                evt_long_repeat       => evt_long_repeat(i),
                evt_long_released     => evt_long_released(i),
                click_count           => click_count(i)
            );
    end generate gen_buttons;

    -- =========================================================================
    --  PLL (50 MHz -> 100 MHz wr_clk + 33 MHz rd_clk)
    -- =========================================================================
    -- rst => not rst_n: SW[0]=0 (reset) iken PLL reset, sonra release.
    -- PLL ~1 ms icinde kilitlenir (locked 0->1). fifo_rst_n = rst_n and locked
    -- sayesinde FIFO, PLL kilitlenene kadar reset.te kalir (Cummings onerisi).
    -- =========================================================================
    u_pll : entity pll_2clk.pll_2clk
        port map (
            refclk   => CLOCK_50,
            rst      => not rst_n,
            outclk_0 => wr_clk,
            outclk_1 => rd_clk,
            locked   => locked
        );

    -- =========================================================================
    --  CDC: evt_single -> wr_clk / rd_clk domain'leri
    -- =========================================================================
-- Her event, CLOCK_50 domain'inde 1 clock genislisinde bir pulse'dur.
-- Hedef domain farkli bir clock kullandigi icin, dogrudan 2-FF
-- senkronizasyonu pulse'u kacirabilir. Bu nedenle pulse, toggle +
-- 2-FF + XOR yontemiyle cdc_pulse_sync uzerinden guvenli sekilde
-- diger clock domain'ine tasinir. Bkz. cdc_pulse_sync.vhd basligi.
    u_cdc_wr : entity work.cdc_pulse_sync
        generic map ( G_STAGES => 2 )
        port map (
            src_clk   => CLOCK_50,
            pulse_in  => evt_single(0),
            dst_clk   => wr_clk,
            rst_n     => rst_n,
            pulse_out => wr_pulse
        );

    u_cdc_rd : entity work.cdc_pulse_sync
        generic map ( G_STAGES => 2 )
        port map (
            src_clk   => CLOCK_50,
            pulse_in  => evt_single(1),
            dst_clk   => rd_clk,
            rst_n     => rst_n,
            pulse_out => rd_pulse
        );

    -- =========================================================================
    --  SW[3:1] -> wr_clk domain (2-FF vector sync)
    -- =========================================================================
    p_sw_sync : process(wr_clk, rst_n)
    begin
        if rst_n = '0' then
            sw_data_meta <= (others => '0');
            sw_data_sync <= (others => '0');
        elsif rising_edge(wr_clk) then
            sw_data_meta <= SW(3 downto 1);
            sw_data_sync <= sw_data_meta;
        end if;
    end process p_sw_sync;

    -- =========================================================================
    --  ASYNC FIFO (wr_clk / rd_clk domain'leri arasi)
    -- =========================================================================
    u_fifo : entity work.fifo_async
        generic map ( G_WIDTH => 8, G_DEPTH => 16 )
        port map (
            rst_n   => fifo_rst_n,
            -- write side (wr_clk domain)
            wr_clk  => wr_clk,
            wr_en   => fifo_wr_en,
            wr_data => fifo_wr_data,
            full    => fifo_full,
            -- read side (rd_clk domain)
            rd_clk  => rd_clk,
            rd_en   => fifo_rd_en,
            rd_data => fifo_rd_data,
            empty   => fifo_empty
        );

    -- =========================================================================
    --  WRITE DOMAIN (wr_clk): wr_pulse -> wr_en (1-clock)
    -- =========================================================================
    -- wr_pulse zaten wr_clk domain'inde 1-clock pulse. full degilse yaz.
    -- full mask'i FIFO'yu override etmemek icin (fifo_async icinde de var
    -- ama disaridan da koruyalim).
    p_wr_en : process(wr_clk, rst_n)
    begin
        if rst_n = '0' then
            fifo_wr_en <= '0';
        elsif rising_edge(wr_clk) then
            fifo_wr_en <= wr_pulse and (not fifo_full);
        end if;
    end process p_wr_en;

    -- =========================================================================
    --  READ DOMAIN (rd_clk): rd_pulse -> rd_en (1-clock)
    -- =========================================================================
    p_rd_en : process(rd_clk, rst_n)
    begin
        if rst_n = '0' then
            fifo_rd_en <= '0';
        elsif rising_edge(rd_clk) then
            fifo_rd_en <= rd_pulse and (not fifo_empty);
        end if;
    end process p_rd_en;

    -- =========================================================================
    --  READ DOMAIN: okunan degeri yakala (LED icin)
    -- =========================================================================
    -- fifo_async FWFT (first-word-fall-through): rd_en=1 oldugu clock'ta
    -- rd_data gecerli. O degeri last_rd_data'ya kaydet -> LED surekli son
    -- okunan degeri gosterir.
	-- FWFT -> FIFO'ya veri geldiğinde ilk veri zaten çıkışta hazır bekler
    p_capture : process(rd_clk, rst_n)
    begin
        if rst_n = '0' then
            last_rd_data <= (others => '0');
        elsif rising_edge(rd_clk) then
            if fifo_rd_en = '1' and fifo_empty = '0' then
                last_rd_data <= fifo_rd_data;
            end if;
        end if;
    end process p_capture;

end architecture rtl;
