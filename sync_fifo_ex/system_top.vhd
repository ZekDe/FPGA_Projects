--------------------------------------------------------------------------------
--  system_top.vhd  (05_fifo_sync)  -- ILK UYGULAMA: button_gesture + FIFO
--
--  DOSYA LISTESI (Quartus projesine eklenmesi gereken dosyalar):
--  ============================================================
--  Bu system_top'u derlemek icin asagidaki dosyalarin QSF'ye eklenmesi
--  gerekir (bagimlilik sirasina gore, alt bloklar once). Yollar proje
--  klasoru (qpf'in bulundugu yer) gore GORECELIDIR:
--
--    set_global_assignment -name VHDL_FILE ../MyLibs/synchronizer.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/time_base_ms.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/ton.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/edge_detector.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/divider_pipelined.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/button_gesture.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/fifo_sync.vhd
--    set_global_assignment -name VHDL_FILE src/system_top.vhd
--
--  BAĞIMLILIK AGACI:
--    system_top
--    +-_ button_gesture       <- buton gesture FSM (Faz 1 + 6)
--    |   +- synchronizer
--    |   +- ton
--    |   +- divider_pipelined
--    +-_ time_base_ms         <- milisaniye zaman tabani (Faz 1)
--    +-_ fifo_sync            <- senkron FIFO (Faz 3.1)
--
--  AMAC (SEN YAZACAKSIN):
--    Bu projede tek buton (KEY[0]) ile FIFO'yu kontrol edecegiz. Butonun
--    gesture event'lerini FIFO komutlarina sen esleyeceksin.
--
--  KART GIRIS/CIKIS:
--    CLOCK_50 : 50 MHz saat
--    KEY[0]   : buton (aktif-dusuk) -> button_gesture'a baglanacak
--    SW[0]    : reset (aktif-dusuk) -> SW[0]=0 iken reset
--    SW[3:1]  : 3-bit veri (FIFO'ya yazilacak deger)
--    LED[3:0] : okunan son veri (FIFO rd_data)
--    LED[6]   : empty bayragi
--    LED[7]   : full bayragi
--
--  SENIN YAZACAGIN KISIMLAR (asagida "TODO" ile isaretli):
--    1) Event -> FIFO komut esleme:
--       - evt_single  -> wr_en + wr_data (SW'den FIFO'ya yaz)
--       - evt_long    -> rd_en (FIFO'dan oku)
--       - evt_long_repeat -> rd_en (basili tutunca hizlanarak oku)
--       - (evt_multi / evt_long_released -> istersen kullan)
--    2) LED mapping:
--       - LED[3:0] = rd_data (okunan son veri)
--       - LED[6]   = empty
--       - LED[7]   = full
--       - LED[5]   = (bos - istersen bir sey koy)
--
--  ONEMLI: button_gesture event'leri 1-CLOCK PULSE'dur. wr_en ve rd_en
--  ise level sinyalleridir. Event pulse'unu wr_en/rd_en'e dogrudan
--  baglayabilirsin cunku FIFO her clock'ta wr_en=1 gorurse yazar.
--  1-clock pulse = 1 eleman yaz/oku. Tam istedigimiz sey.
--
--  IPUCU: rd_data'yi LED'de gostermek icin bir register'a kaydetmen
--  gerekecek, cunku rd_data sadece rd_en=1 iken anlamlidir. Okudugun
--  degeri "son okunan" register'inda tut, LED onu goster.
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
        KEY      : in  std_logic_vector(1 downto 0);   -- KEY[0]=gonder, KEY[1]=oku
        SW       : in  std_logic_vector(3 downto 0);   -- SW[0]=reset, SW[3:1]=veri
        LED      : out std_logic_vector(7 downto 0)
    );
end entity system_top;


architecture rtl of system_top is

    -- ===========================================================================
    --  BOLUM 1: SABITLER (config degerleri)
    --  Bunlari sen degistirme, hazir geliyor.
    -- ===========================================================================

    constant C_WIDTH : positive := 32;
	
    -- button_gesture config (kart gercegi icin makul degerler)
    constant C_DEBOUNCE_MS           : unsigned(C_WIDTH-1 downto 0) := to_unsigned(20,   C_WIDTH);
    constant C_LONG_PRESS_MS         : unsigned(C_WIDTH-1 downto 0) := to_unsigned(1000, C_WIDTH);
    constant C_MULTI_CLICK_WINDOW_MS : unsigned(C_WIDTH-1 downto 0) := to_unsigned(400,  C_WIDTH);
    constant C_REPEAT_START_MS       : unsigned(C_WIDTH-1 downto 0) := to_unsigned(500,  C_WIDTH);
    constant C_REPEAT_END_MS         : unsigned(C_WIDTH-1 downto 0) := to_unsigned(100,  C_WIDTH);
    constant C_REPEAT_RAMP_MS        : unsigned(C_WIDTH-1 downto 0) := to_unsigned(1000, C_WIDTH);

    -- ===========================================================================
    --  BOLUM 2: SINYALLER
    --  Asagidaki signal'leri kullanacaksin. Hangi modul neyi bekliyor,
    --  yorumlarda belirtiliyor.
    -- ===========================================================================

    -- Board polaritesi (aktif-dusuk pinleri mantiga cevir)
    signal rst_n    : std_logic;
    signal btn0_raw : std_logic;
	signal btn1_raw : std_logic;

    -- Ortak zaman tabani 32 bit system tick 1 ms
    signal systick  : unsigned(C_WIDTH-1 downto 0);

    ---------------------------------------------------------------------------
    -- button_gesture cikislari (event'ler - 1-clock pulse)
    ---------------------------------------------------------------------------
	 -- KEY[0] icin (yazma butonu)
	signal evt_single0        : std_logic;
	signal evt_multi0         : std_logic;
	signal evt_long0          : std_logic;
	signal evt_long_repeat0   : std_logic;
	signal evt_long_released0 : std_logic;
	signal click_count0       : unsigned(7 downto 0);

	-- KEY[1] icin (okuma butonu)
	signal evt_single1        : std_logic;
	signal evt_multi1         : std_logic;
	signal evt_long1          : std_logic;
	signal evt_long_repeat1   : std_logic;
	signal evt_long_released1 : std_logic;
	signal click_count1       : unsigned(7 downto 0);

    ---------------------------------------------------------------------------
    -- FIFO sinyalleri
    ---------------------------------------------------------------------------
    -- SEN TANIMLA: wr_en, wr_data, full, rd_en, rd_data, empty
    -- (Ipucu: G_WIDTH kac olsun? SW[3:1] 3-bit, ama FIFO 8-bit secip
    --  alt 3 bit'i SW'den almak daha temiz. Ya da 4-bit, 8-bit, sen sec.)
    --
    signal fifo_wr_en   : std_logic;
    signal fifo_wr_data : std_logic_vector(7 downto 0);
    signal fifo_full    : std_logic;
    signal fifo_rd_en   : std_logic;
    signal fifo_rd_data : std_logic_vector(7 downto 0);
    signal fifo_empty   : std_logic;

    ---------------------------------------------------------------------------
    -- "Son okunan" register'i (LED'de gostermek icin)
    ---------------------------------------------------------------------------
    -- SEN TANIMLA: rd_data sadece rd_en=1 iken anlamlidir. Okudugun degeri
    -- bir register'da tutman lazim ki LED surekli son okunan degeri gosterir.
    --
    signal last_rd_data : std_logic_vector(7 downto 0) := (others => '0');
    signal cmd : std_logic_vector(1 downto 0);

begin

    -- ===========================================================================
    --  BOLUM 3: combinational
    -- ===========================================================================
    rst_n    <= SW(0);
    btn0_raw <= not KEY(0);
	 btn1_raw <= not KEY(1);
    cmd <= evt_single1 & evt_single0; 
    fifo_wr_data <= "00000" & SW(3 downto 1);
    LED(3 downto 0) <= last_rd_data(3 downto 0);  -- okunan son veri
    LED(6)          <= fifo_empty;
    LED(7)          <= fifo_full;
    -- ===========================================================================
    --  BOLUM 4: MODUL INSTANCE'LARI
    --  Hazir geliyor, degistirme.
    -- ===========================================================================

    ---------------------------------------------------------------------------
    -- Ortak systick (button_gesture bunu kullanir)
    ---------------------------------------------------------------------------
    u_systick : entity work.time_base_ms
        generic map ( G_CLK_HZ => G_CLK_HZ, G_WIDTH => C_WIDTH )
        port map ( clk => CLOCK_50, rst_n => rst_n, tick_ms => open, now_ms => systick );

    ---------------------------------------------------------------------------
    -- BUTON GESTURE FSM
    ---------------------------------------------------------------------------
    u_btn0 : entity work.button_gesture
        port map (
            clk                   => CLOCK_50,
            rst_n                 => rst_n,
            now_ms                => systick,
            raw_pressed           => btn0_raw,
            require_repress       => '0',
            debounce_ms           => C_DEBOUNCE_MS,
            long_press_ms         => C_LONG_PRESS_MS,
            multi_click_window_ms => C_MULTI_CLICK_WINDOW_MS,
            repeat_start_ms       => C_REPEAT_START_MS,
            repeat_end_ms         => C_REPEAT_END_MS,
            repeat_ramp_ms        => C_REPEAT_RAMP_MS,
            evt_single            => evt_single0,
            evt_multi             => evt_multi0,
            evt_long              => evt_long0,
            evt_long_repeat       => evt_long_repeat0,
            evt_long_released     => evt_long_released0,
            click_count           => click_count0
        );
		
	u_btn1 : entity work.button_gesture
		port map (
		    clk                   => CLOCK_50,
            rst_n                 => rst_n,
            now_ms                => systick,
            raw_pressed           => btn1_raw,
            require_repress       => '0',
            debounce_ms           => C_DEBOUNCE_MS,
            long_press_ms         => C_LONG_PRESS_MS,
            multi_click_window_ms => C_MULTI_CLICK_WINDOW_MS,
            repeat_start_ms       => C_REPEAT_START_MS,
            repeat_end_ms         => C_REPEAT_END_MS,
            repeat_ramp_ms        => C_REPEAT_RAMP_MS,
            evt_single            => evt_single1,
            evt_multi             => evt_multi1,
            evt_long              => evt_long1,
            evt_long_repeat       => evt_long_repeat1,
            evt_long_released     => evt_long_released1,
            click_count           => click_count1
		);

    ---------------------------------------------------------------------------
    -- FIFO (SEN BOYUTU SEC - generic map'teki G_WIDTH ve G_DEPTH)
    ---------------------------------------------------------------------------
    u_fifo : entity work.fifo_sync
         generic map ( G_WIDTH => 8, G_DEPTH => 16 )
         port map (
             clk     => CLOCK_50,
             rst_n   => rst_n,
             wr_en   => fifo_wr_en,
             wr_data => fifo_wr_data,
             full    => fifo_full,
             rd_en   => fifo_rd_en,
             rd_data => fifo_rd_data,
             empty   => fifo_empty
         );

    -- ===========================================================================
    --  BOLUM 5: EVENT -> FIFO KOMUT ESLEME   (TODO: SEN YAZ)
    -- ===========================================================================
    --
    p_fifo_ctrl : process(CLOCK_50, rst_n)
        begin
        if rst_n = '0' then
            fifo_wr_en  <= '0';
            fifo_rd_en  <= '0';
        elsif rising_edge(CLOCK_50) then
            -- DEFAULT: her tick once temizle (1-clock pulse uretmek icin)
            -- Sonra case ile sadece ilgili komutu uygula. wr_en/rd_en sadece
            -- ilgili event geldigi tick'te '1' olur, sonra otomatik '0'.
            fifo_wr_en  <= '0';
            fifo_rd_en  <= '0';
            case cmd is
                when "01" =>  -- evt_single0 -> wr_en (SW'den FIFO'ya yaz)
                    fifo_wr_en <= '1';
                when "10" =>  -- evt_single1 -> rd_en (FIFO'dan oku)
                    fifo_rd_en <= '1';
                when others =>
                    null;     -- hicbir sey yapma (default yukarida zaten '0')
            end case;
        end if;
        end process;

    p_capture : process(CLOCK_50, rst_n)
    begin
        if rst_n = '0' then
            last_rd_data <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            if fifo_rd_en = '1' and fifo_empty = '0' then
                last_rd_data <= fifo_rd_data;
            end if;
        end if;
    end process;

end architecture rtl;
