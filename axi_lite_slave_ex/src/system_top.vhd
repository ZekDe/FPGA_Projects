--------------------------------------------------------------------------------
--  system_top.vhd  (07_axi_button_gesture)  -- AXI-Lite + button_gesture
--
--  DOSYA LISTESI (Quartus projesine eklenmesi gereken dosyalar):
--  ============================================================
--    set_global_assignment -name VHDL_FILE ../MyLibs/synchronizer.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/time_base_ms.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/ton.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/edge_detector.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/divider_pipelined.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/button_gesture.vhd
--    set_global_assignment -name VHDL_FILE ../MyLibs/axi_lite_slave.vhd
--    set_global_assignment -name VHDL_FILE src/system_top.vhd
--
--  BAĞIMLILIK AGACI:
--    system_top
--    +-_ axi_lite_slave          <- HPS'ten config register'larina erisim
--    +-_ time_base_ms            <- systick
--    +-_ button_gesture          <- buton gesture FSM (config AXI'den gelir!)
--        +- synchronizer
--        +- ton
--        +- divider_pipelined
--
--  AMAC:
--    AXI-Lite Slave'in config register'larini button_gesture'a bagla. Boylece
--    HPS (Linux) runtime'da debounce_ms, long_press_ms gibi config degerlerini
--    degistirebilir. Bu, "memory-mapped config" deseninin demo'sudur.
--
--  VERI AKISI:
--    HPS -> AXI Slave -> reg_debounce_ms (cfg) -> button_gesture
--    button_gesture -> evt_single, evt_long (status) -> AXI Slave -> HPS okur
--
--  ONEMLI: button_gesture config port'lari unsigned(31 downto 0), ama AXI Slave
--  std_logic_vector(31 downto 0) cikis verir. Arada cast yapmak lazim:
--    unsigned(reg_debounce_ms)  <-  std_logic_vector
--  Bu cast sentezde hic donanim uretmez - sadece tip donusumu.
--
--  KART GIRIS/CIKIS:
--    CLOCK_50 : 50 MHz
--    KEY[0]   : buton (aktif-dusuk) -> button_gesture
--    SW[0]    : reset (aktif-dusuk)
--    LED[7:0] : {full, empty, evt_long, evt_multi, evt_single, 3'b0}
--
--  NOT: Bu system_top KART ICINDIR ama AXI portu testbench'te bir AXI Master
--  tarafindan surulmek uzere tasarlandi. Platform Designer entegrasyonu
--  (HPS baglantisi) sonraki adimda yapilacak.
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
        KEY      : in  std_logic_vector(0 downto 0);   -- KEY[0] buton
        SW       : in  std_logic_vector(0 downto 0);   -- SW[0] reset
        LED      : out std_logic_vector(7 downto 0);

        -- AXI-Lite bus (HPS'e baglanacak, su an testbench'te suruluyor)
        -- Write Address Channel (AW)
        s_axi_awvalid : in  std_logic;
        s_axi_awready : out std_logic;
        s_axi_awaddr  : in  std_logic_vector(31 downto 0);
        s_axi_awprot  : in  std_logic_vector(2 downto 0);
        -- Write Data Channel (W)
        s_axi_wvalid  : in  std_logic;
        s_axi_wready  : out std_logic;
        s_axi_wdata   : in  std_logic_vector(31 downto 0);
        s_axi_wstrb   : in  std_logic_vector(3 downto 0);
        -- Write Response Channel (B)
        s_axi_bvalid  : out std_logic;
        s_axi_bready  : in  std_logic;
        s_axi_bresp   : out std_logic_vector(1 downto 0);
        -- Read Address Channel (AR)
        s_axi_arvalid : in  std_logic;
        s_axi_arready : out std_logic;
        s_axi_araddr  : in  std_logic_vector(31 downto 0);
        s_axi_arprot  : in  std_logic_vector(2 downto 0);
        -- Read Data Channel (R)
        s_axi_rvalid  : out std_logic;
        s_axi_rready  : in  std_logic;
        s_axi_rdata   : out std_logic_vector(31 downto 0);
        s_axi_rresp   : out std_logic_vector(1 downto 0)
    );
end entity system_top;


architecture rtl of system_top is

    constant C_WIDTH : positive := 32;

    -- Clock / reset
    signal rst_n    : std_logic;
    signal btn0_raw : std_logic;

    -- SysTick
    signal systick  : unsigned(C_WIDTH-1 downto 0);

    -- AXI Slave'dan gelen config register'lari (std_logic_vector)
    signal cfg_debounce_ms           : std_logic_vector(31 downto 0);
    signal cfg_long_press_ms         : std_logic_vector(31 downto 0);
    signal cfg_multi_click_window_ms : std_logic_vector(31 downto 0);
    signal cfg_repeat_start_ms       : std_logic_vector(31 downto 0);
    signal cfg_repeat_end_ms         : std_logic_vector(31 downto 0);
    signal cfg_repeat_ramp_ms        : std_logic_vector(31 downto 0);

    -- button_gesture event'leri
    signal evt_single        : std_logic;
    signal evt_multi         : std_logic;
    signal evt_long          : std_logic;
    signal evt_long_repeat   : std_logic;
    signal evt_long_released : std_logic;
    signal click_count       : unsigned(7 downto 0);

    -- Status register (button_gesture event'leri toplanir)
    -- Bit 0: evt_single (latched - HPS okuyana kadar kalir)
    -- Bit 1: evt_multi
    -- Bit 2: evt_long
    -- Bit 3: evt_long_repeat
    -- Bit 4: evt_long_released
    -- Bit 7..5: click_count(2:0)
    signal button_status_reg : std_logic_vector(31 downto 0) := (others => '0');

begin

    -- ===========================================================================
    -- BOARD POLARITESI
    -- ===========================================================================
    rst_n    <= SW(0);
    btn0_raw <= not KEY(0);

    -- ===========================================================================
    -- SYSTICK
    -- ===========================================================================
    u_systick : entity work.time_base_ms
        generic map ( G_CLK_HZ => G_CLK_HZ, G_WIDTH => C_WIDTH )
        port map ( clk => CLOCK_50, rst_n => rst_n, tick_ms => open, now_ms => systick );

    -- ===========================================================================
    -- AXI-LITE SLAVE
    -- ===========================================================================
    -- Config register'lari (cfg_xxx) AXI Slave'dan gelir, button_gesture'a gider.
    -- Status register'i (button_status_reg) button_gesture'dan toplanir, AXI Slave'a gider.
    -- ===========================================================================
    u_axi : entity work.axi_lite_slave
        port map (
            clk => CLOCK_50, rst_n => rst_n,
            -- AW
            s_axi_awvalid => s_axi_awvalid, s_axi_awready => s_axi_awready,
            s_axi_awaddr  => s_axi_awaddr,  s_axi_awprot  => s_axi_awprot,
            -- W
            s_axi_wvalid  => s_axi_wvalid,  s_axi_wready  => s_axi_wready,
            s_axi_wdata   => s_axi_wdata,   s_axi_wstrb   => s_axi_wstrb,
            -- B
            s_axi_bvalid  => s_axi_bvalid,  s_axi_bready  => s_axi_bready,
            s_axi_bresp   => s_axi_bresp,
            -- AR
            s_axi_arvalid => s_axi_arvalid, s_axi_arready => s_axi_arready,
            s_axi_araddr  => s_axi_araddr,  s_axi_arprot  => s_axi_arprot,
            -- R
            s_axi_rvalid  => s_axi_rvalid,  s_axi_rready  => s_axi_rready,
            s_axi_rdata   => s_axi_rdata,   s_axi_rresp   => s_axi_rresp,
            -- Config cikislari (button_gesture'a)
            reg_debounce_ms           => cfg_debounce_ms,
            reg_long_press_ms         => cfg_long_press_ms,
            reg_multi_click_window_ms => cfg_multi_click_window_ms,
            reg_repeat_start_ms       => cfg_repeat_start_ms,
            reg_repeat_end_ms         => cfg_repeat_end_ms,
            reg_repeat_ramp_ms        => cfg_repeat_ramp_ms,
            -- Status girisleri (button_gesture'dan)
            sts_button_status_in      => button_status_reg,
            sts_fifo_status_in        => (others => '0')   -- FIFO yok bu projede
        );

    -- ===========================================================================
    -- BUTTON GESTURE FSM
    -- ===========================================================================
    -- Config degerleri AXI Slave'dan geliyor (std_logic_vector -> unsigned cast).
    -- Bu cast hic donanim uretmez - sadece reinterpret bits.
    -- ===========================================================================
    u_btn : entity work.button_gesture
        port map (
            clk                   => CLOCK_50,
            rst_n                 => rst_n,
            now_ms                => systick,
            raw_pressed           => btn0_raw,
            require_repress       => '0',
            debounce_ms           => unsigned(cfg_debounce_ms),
            long_press_ms         => unsigned(cfg_long_press_ms),
            multi_click_window_ms => unsigned(cfg_multi_click_window_ms),
            repeat_start_ms       => unsigned(cfg_repeat_start_ms),
            repeat_end_ms         => unsigned(cfg_repeat_end_ms),
            repeat_ramp_ms        => unsigned(cfg_repeat_ramp_ms),
            evt_single            => evt_single,
            evt_multi             => evt_multi,
            evt_long              => evt_long,
            evt_long_repeat       => evt_long_repeat,
            evt_long_released     => evt_long_released,
            click_count           => click_count
        );

    -- ===========================================================================
    -- STATUS REGISTER: button_gesture event'lerini topla (latched)
    -- ===========================================================================
    -- Event'ler 1-clock pulse. HPS'in onlari kacirmamasi icin latch'liyoruz.
    -- HPS status okuyunca latch'ler temizlenir (write-1-to-clear mantigi).
    -- Basit versiyon: sadece latch (temizleme yok - ileride eklenebilir).
    -- ===========================================================================
    p_status : process(CLOCK_50, rst_n)
    begin
        if rst_n = '0' then
            button_status_reg <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            if evt_single        = '1' then button_status_reg(0) <= '1'; end if;
            if evt_multi         = '1' then button_status_reg(1) <= '1'; end if;
            if evt_long          = '1' then button_status_reg(2) <= '1'; end if;
            if evt_long_repeat   = '1' then button_status_reg(3) <= '1'; end if;
            if evt_long_released = '1' then button_status_reg(4) <= '1'; end if;
            button_status_reg(10 downto 8) <= std_logic_vector(click_count(2 downto 0));
        end if;
    end process p_status;

    -- ===========================================================================
    -- LED MAPPING (debug)
    -- ===========================================================================
    LED(0) <= evt_single;
    LED(1) <= evt_multi;
    LED(2) <= evt_long;
    LED(3) <= evt_long_repeat;
    LED(4) <= evt_long_released;
    LED(7 downto 5) <= (others => '0');

end architecture rtl;
