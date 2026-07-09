--------------------------------------------------------------------------------
--  system_top.vhd  -- SISTEM UST SEVIYESI (board katmani)
--
--  Bu dosyanin tek isi: BOARD ile MANTIK'i birlestirmek.
--    - Fiziksel pinler (CLOCK_50, KEY, SW, LED) burada
--    - Board polaritesi (KEY/SW aktif-dusuk -> ters cevirme) burada
--    - Ortak systick BURADA bir kez uretilir
--    - Alt-sistemler (su an sadece button_module) burada ornekleip tellenir
--
--  Mantik (buton isleme) system_top'ta DEGIL; board-bagimsiz button_module'de.
--  BUYUME: UART gelince buraya sadece 'u_uart : uart_module' eklenir ve ayni
--  systick ona da port'la verilir. button_module hic degismez. IMU icin de ayni.
--
--    CLOCK_50 -> u_systick -> systick --+--> u_buttons (button_module)
--    KEY/SW   -> polarite --------------/         (ileride) --> u_uart, u_imu ...
--
--  DE0-Nano-SoC: CLOCK_50=50 MHz; KEY[1:0] iki buton; SW[0] reset.
--  (Kesin pin atamalari .qsf'te DE0-Nano-SoC manualinden.)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity system_top is
    generic (
        G_CLK_HZ     : positive := 50_000_000;   -- clock frekansi (sim'de 1000)
        G_PRESET1_MS : natural  := 100;
        G_PRESET2_MS : natural  := 150
    );
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(1 downto 0);   -- iki buton (aktif-dusuk)
        SW       : in  std_logic_vector(0 downto 0);   -- SW[0] = reset (aktif-dusuk)
        LED      : out std_logic_vector(7 downto 0)
    );
end entity system_top;

architecture rtl of system_top is

    constant C_WIDTH : positive := 32;

    -- Board katmani sinyalleri
    signal rst_n    : std_logic;
    signal btn1_raw : std_logic;
    signal btn2_raw : std_logic;

    -- Ortak zaman tabani (C'deki global systick)
    signal systick  : unsigned(C_WIDTH - 1 downto 0);

    -- button_module cikislari (ust seviyeden erisilir)
    signal btn1_out, btn1_out_pulse : std_logic;
    signal btn2_out, btn2_out_pulse : std_logic;

begin

    -- BOARD POLARITESI (sadece burada): aktif-dusuk pinleri mantiga cevir
    rst_n    <= SW(0);
    btn1_raw <= not KEY(0);
    btn2_raw <= not KEY(1);

    -- ORTAK systick: TEK sefer uretilir
    u_systick : entity work.time_base_ms
        generic map ( G_CLK_HZ => G_CLK_HZ, G_WIDTH => C_WIDTH )
        port map    ( clk => CLOCK_50, rst_n => rst_n, tick_ms => open, now_ms => systick );

    -- BUTON ALT-SISTEMI: board-bagimsiz mantik; systick'i port'la alir
    u_buttons : entity work.button_module
        generic map (
            G_WIDTH => C_WIDTH, G_STAGES => 2,
            G_PRESET1_MS => G_PRESET1_MS, G_PRESET2_MS => G_PRESET2_MS
        )
        port map (
            clk            => CLOCK_50,
            rst_n          => rst_n,
            systick        => systick,
            btn1_raw       => btn1_raw,
            btn2_raw       => btn2_raw,
            btn1_out       => btn1_out,
            btn1_out_pulse => btn1_out_pulse,
            btn2_out       => btn2_out,
            btn2_out_pulse => btn2_out_pulse
        );

    -- Cikislar
    LED(0)          <= btn1_out;
    LED(1)          <= btn2_out;
    LED(2)          <= btn1_out_pulse;
    LED(3)          <= btn2_out_pulse;
    LED(7 downto 4) <= (others => '0');

end architecture rtl;
