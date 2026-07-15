--------------------------------------------------------------------------------
--  time_base_ms.vhd  -- donanim "SysTick": clock -> milisaniye zaman tabani

--  NASIL CALISIR:
--    Clock frekansini biliyoruz (G_CLK_HZ). 1 ms'de kac clock vurusu var?
--       C_CYC_PER_MS = G_CLK_HZ / 1000
--    Bir on-bolucu (prescaler) sayaci 0'dan C_CYC_PER_MS-1'e sayar; doldugunda
--    "1 ms gecti" demektir -> tick_ms tek clock'luk pulse verir ve now_ms 1 artar.
--
--  YENIDEN KULLANIM:
--    Farkli kart/frekans -> sadece G_CLK_HZ degisir, ms arayuzu ayni kalir.
--    Simulasyonda G_CLK_HZ=1000 verilirse C_CYC_PER_MS=1 olur: her clock = 1 ms,
--    boylece ms beklemeden hizli sim yapariz (arayuz yine ms).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity time_base_ms is
    generic (
        G_CLK_HZ : positive := 50_000_000;   -- clock frekansi (DE0-Nano-SoC: 50 MHz)
        G_WIDTH  : positive := 32             -- now_ms bit genisligi (C: uint32_t)
    );
    port (
        clk    : in  std_logic;
        rst_n  : in  std_logic;
        tick_ms: out std_logic;                        -- her 1 ms'de 1 clock'luk pulse
        now_ms : out unsigned(G_WIDTH - 1 downto 0)    -- serbest kosan ms sayaci (=C'deki now)
    );
end entity time_base_ms;

architecture rtl of time_base_ms is
    -- 1 ms'deki clock vurusu sayisi. 50 MHz -> 50_000. Sim'de G_CLK_HZ=1000 -> 1.
    constant C_CYC_PER_MS : positive := G_CLK_HZ / 1000;

    -- On-bolucu sayaci: 0 .. C_CYC_PER_MS-1 arasi sayar.
    signal prescale : integer range 0 to C_CYC_PER_MS - 1;
    signal now_reg  : unsigned(G_WIDTH - 1 downto 0);
    signal tick_reg : std_logic;
begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            prescale <= 0;
            now_reg  <= (others => '0');
            tick_reg <= '0';

        elsif rising_edge(clk) then
            if prescale = C_CYC_PER_MS - 1 then
                -- 1 ms doldu: on-bolucuyu sifirla, ms sayacini artir, tek-tick pulse ver
                prescale <= 0;
                now_reg  <= now_reg + 1;       -- 32-bit; dolunca modulo 2^32 basa sarar (wrap)
                tick_reg <= '1';
            else
                prescale <= prescale + 1;
                tick_reg <= '0';               -- pulse yalnizca 1 clock genisliginde
            end if;
        end if;
    end process;

    now_ms  <= now_reg;
    tick_ms <= tick_reg;

end architecture rtl;
