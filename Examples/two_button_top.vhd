--------------------------------------------------------------------------------
--  two_button_top.vhd  -- iki butonun PARALEL debounce zinciri (DUZ / C-birebir)
--
--  Bu dosya, kutuphane bloklarini (synchronizer, time_base_ms, ton, edge_detector)
--  senin C kullanimindaki gibi DUZ birlestirir -- ekstra sarmalayici yok. Tum ara
--  sinyaller (btn_out, btn_out_pulse) ust seviyede isimli ve erisilebilir; projenin
--  bir yerinde seviyeyi (btn_out), baska yerinde tetigi (btn_out_pulse) kullanirsin.
--
--  SENIN C KULLANIMIN  ->  BURADAKI VHDL:
--    systick  (global ms sayaci)                 -> signal systick (time_base_ms uretir)
--    btn1_out       = TON(&ton1, btn1_raw, systick, TIMEOUT)   -> u_ton1  (now_ms => systick)
--    btn1_out_pulse = edgeDetection(&ed1, btn1_out)            -> u_ed1
--    btn2_out       = TON(&ton2, btn2_raw, systick, TIMEOUT2)  -> u_ton2
--    btn2_out_pulse = edgeDetection(&ed2, btn2_out)            -> u_ed2
--
--  C'DE OLMAYAN EK: synchronizer. Asenkron dis pin (buton) dogrudan saatli
--  mantiga verilirse metastability olur. MCU'da GPIO donanimi bunu senin yerine
--  gizlice yapardi; FPGA'de acikca kuruyoruz (en bastaki "CPU'nun gizledigi
--  senkronizasyon" istegin). btn_raw -> synchronizer -> ton.in_sig.
--
--  DE0-Nano-SoC: CLOCK_50 = 50 MHz; KEY[1:0] iki buton (aktif-dusuk); SW[0] reset.
--  (Kesin pin atamalari .qsf'te DE0-Nano-SoC manualinden alinacak.)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity two_button_top is
    generic (
        G_CLK_HZ     : positive := 50_000_000;   -- clock frekansi (sim'de 1000)
        G_PRESET1_MS : natural  := 100;          -- buton1 timeout (ms)
        G_PRESET2_MS : natural  := 150           -- buton2 timeout (ms)
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

    -- C'deki #define'lar
    constant C_BTN_PRESSED_TIMEOUT  : natural := G_PRESET1_MS;   -- BTN_PRESSED_TIMEOUT
    constant C_BTN_PRESSED_TIMEOUT2 : natural := G_PRESET2_MS;   -- BTN_PRESSED_TIMEOUT2

    signal rst_n   : std_logic;

    -- C'deki global 'systick' -- surekli artan ms sayaci (time_base_ms uretir)
    signal systick : unsigned(C_WIDTH - 1 downto 0);

    -- Buton 1
    signal btn1_raw        : std_logic;
    signal btn1_sync       : std_logic;
    signal btn1_out        : std_logic;   -- C: btn1_out       (TON1 cikisi, seviye)
    signal btn1_out_pulse  : std_logic;   -- C: btn1_out_pulse (ED1 cikisi, tek-tick)

    -- Buton 2
    signal btn2_raw        : std_logic;
    signal btn2_sync       : std_logic;
    signal btn2_out        : std_logic;   -- C: btn2_out
    signal btn2_out_pulse  : std_logic;   -- C: btn2_out_pulse

begin

    -- Board polariteleri (aktif-dusuk): basili/reset istedigimiz mantiga cevir
    rst_n    <= SW(0);
    btn1_raw <= not KEY(0);
    btn2_raw <= not KEY(1);

    ----------------------------------------------------------------------------
    -- ORTAK systick: C'de global olarak artardi; burada tek bir SysTick uretir
    ----------------------------------------------------------------------------
    u_systick : entity work.time_base_ms
        generic map ( G_CLK_HZ => G_CLK_HZ, G_WIDTH => C_WIDTH )
        port map    ( clk => CLOCK_50, rst_n => rst_n, tick_ms => open, now_ms => systick );

    ----------------------------------------------------------------------------
    -- BUTON 1:  sync -> ton -> edge   (C'deki btn1 satirlarinin donanim hali)
    ----------------------------------------------------------------------------
    u_sync1 : entity work.synchronizer
        generic map ( G_STAGES => 2, G_RST_VAL => '0' )
        port map    ( clk => CLOCK_50, rst_n => rst_n, async_in => btn1_raw, sync_out => btn1_sync );

    -- C: btn1_out = TON(&ton1, btn1_raw, systick, BTN_PRESSED_TIMEOUT);
    u_ton1 : entity work.ton
        generic map ( G_WIDTH => C_WIDTH )
        port map (
            clk         => CLOCK_50,
            rst_n       => rst_n,
            in_sig      => btn1_sync,                                    -- (sync'lenmis btn1_raw)
            now_ms      => systick,
            preset_time => to_unsigned(C_BTN_PRESSED_TIMEOUT, C_WIDTH),
            retval      => btn1_out,
            since       => open
        );

    -- C: btn1_out_pulse = edgeDetection(&ed1, btn1_out);
    u_ed1 : entity work.edge_detector
        port map ( clk => CLOCK_50, rst_n => rst_n, val => btn1_out, retval => btn1_out_pulse );

    ----------------------------------------------------------------------------
    -- BUTON 2:  sync -> ton -> edge   (ayni yapi, farkli timeout)
    ----------------------------------------------------------------------------
    u_sync2 : entity work.synchronizer
        generic map ( G_STAGES => 2, G_RST_VAL => '0' )
        port map    ( clk => CLOCK_50, rst_n => rst_n, async_in => btn2_raw, sync_out => btn2_sync );

    -- C: btn2_out = TON(&ton2, btn2_raw, systick, BTN_PRESSED_TIMEOUT2);
    u_ton2 : entity work.ton
        generic map ( G_WIDTH => C_WIDTH )
        port map (
            clk         => CLOCK_50,
            rst_n       => rst_n,
            in_sig      => btn2_sync,
            now_ms      => systick,
            preset_time => to_unsigned(C_BTN_PRESSED_TIMEOUT2, C_WIDTH),
            retval      => btn2_out,
            since       => open
        );

    -- C: btn2_out_pulse = edgeDetection(&ed2, btn2_out);
    u_ed2 : entity work.edge_detector
        port map ( clk => CLOCK_50, rst_n => rst_n, val => btn2_out, retval => btn2_out_pulse );

    ----------------------------------------------------------------------------
    -- Cikislar
    ----------------------------------------------------------------------------
    LED(0)          <= btn1_out;
    LED(1)          <= btn2_out;
    LED(2)          <= btn1_out_pulse;
    LED(3)          <= btn2_out_pulse;
    LED(7 downto 4) <= (others => '0');

end architecture rtl;
