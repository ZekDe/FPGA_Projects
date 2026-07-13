--------------------------------------------------------------------------------
--  led_pulse.vhd  -- 1-clock pulse'i LED icin uzun (50 ms) seviyeye cevirir
--
--  AMAC:
--    FSM'lerden gelen event pulse'lari (evt_single, evt_long, vb.) sadece
--    1 clock (20 ns @ 50 MHz) surer - insan gozu bunu goremz. Bu modul pulse
--    geldiginde LED'i G_ON_MS boyunca '1' yapar, sonra sondurur.
--
--  RE-TRIGGERABLE: LED yanarken yeni pulse gelirse sayaci yeniden baslatir
--  (uzar). Bu, hizli event'lerde (LONG_REPEAT) LED'in surekli yanik kalmasini
--  saglar - ki bu ivmelenmeyi gormek icin iyi bir davranistir.
--
--  KULLANIM:
--    u_led : entity work.led_pulse
--      generic map (G_CLK_HZ => 50_000_000, G_ON_MS => 50)
--      port map (clk => clk, rst_n => rst_n, pulse => evt_xxx, led => LED(i));
--
--  DONANIM: 1 sayac (integer). 50 MHz * 50 ms = 2.500.000 cycle ~ 22 bit.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_pulse is
    generic (
        G_CLK_HZ : positive := 50_000_000;  -- clock frekansi (Hz)
        G_ON_MS  : positive := 50            -- LED yanik suresi (ms)
    );
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;
        pulse : in  std_logic;   -- 1-clock pulse (re-trigger)
        led   : out std_logic    -- '1' = yanik, G_ON_MS boyunca
    );
end entity led_pulse;

architecture rtl of led_pulse is
    -- G_ON_MS boyunca kac clock sayacagiz? 50 MHz * 50 ms = 2.500.000
    constant C_CYCLES_ON : positive := (G_CLK_HZ / 1000) * G_ON_MS;
    signal   counter     : integer range 0 to C_CYCLES_ON := 0;
begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            counter <= 0;
        elsif rising_edge(clk) then
            if pulse = '1' then
                counter <= C_CYCLES_ON;   -- re-trigger: pulse -> sayaci yenile
            elsif counter > 0 then
                counter <= counter - 1;   -- say
            end if;
            -- counter = 0 ise sabit (LED sondu)
        end if;
    end process;

    -- LED yanik = sayac henuz 0'a ulasmadi
    led <= '1' when counter > 0 else '0';

end architecture rtl;
