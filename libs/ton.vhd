--------------------------------------------------------------------------------
--  ton.vhd  -- IEC 61131-3 "On-Delay Timer" (TON), C koduyla BIREBIR
--  Referans: ton.c / ton.h  (Author: Emrah Duatepe)
--
--  C IMZASI:
--     uint8_t TON(ton_t *obj, uint8_t in, uint32_t now, uint32_t preset_time)
--     struct: { uint32_t since; uint32_t aux; }
--
--  C MANTIGI (birebir):
--     if(in) {
--         if(!obj->aux)      { obj->since = now + preset_time; obj->aux = 1; }
--         else if(TIME_OVER(obj->since, now)) { ret_val = 1; }
--     } else { obj->aux = 0; }
--     TIME_OVER(target,time) = ((uint32_t)((time)-(target)) < 0x80000000U)
--
--  ISIM ESLESMESI (VHDL kisitlari):
--     C 'in'   -> in_sig   ('in' VHDL anahtar kelimesi, kullanilamaz)
--     C 'now'  -> now_ms   ('now' VHDL'de onceden tanimli fonksiyon)
--     C 'since','aux','preset_time' -> ayni isim
--     C donus  -> retval
--
--  ZAMAN: now_ms ve preset_time artik MILISANIYE cinsinden (time_base_ms saglar).
--         Boylece TON'a "100" yazip 100 ms dersin -- clock tick hesabi yok.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ton is
    generic (
        G_WIDTH : positive := 32                         -- C: uint32_t
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        in_sig     : in  std_logic;                       -- C: in
        now_ms     : in  unsigned(G_WIDTH - 1 downto 0);  -- C: now (ortak zaman)
        preset_time: in  unsigned(G_WIDTH - 1 downto 0);  -- C: preset_time (ms)
        retval     : out std_logic;                       -- C: ret_val
        since      : out unsigned(G_WIDTH - 1 downto 0)   -- gozlem: hedef zaman (C: obj->since)
    );
end entity ton;

architecture rtl of ton is
    signal since_reg  : unsigned(G_WIDTH - 1 downto 0);   -- C: obj->since
    signal aux        : std_logic;                        -- C: obj->aux (0/1 kenar bayragi)
    signal retval_reg : std_logic;

    -- C'deki TIME_OVER makrosunun donanim hali:
    --   (now - since) MSB=0  ->  now, since'i gecti (sure doldu). Wrap-safe.
    signal diff : unsigned(G_WIDTH - 1 downto 0);
begin

    diff <= now_ms - since_reg;   -- modulo 2^32 cikarma (numeric_std)

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            since_reg  <= (others => '0');
            aux        <= '0';
            retval_reg <= '0';

        elsif rising_edge(clk) then
            if in_sig = '1' then                          -- C: if(in)
                if aux = '0' then                         -- C: if(!obj->aux)
                    since_reg  <= now_ms + preset_time;   -- C: obj->since = now + preset_time
                    aux        <= '1';                    -- C: obj->aux = 1
                    retval_reg <= '0';
                else                                      -- C: else if(TIME_OVER(since, now))
                    if diff(G_WIDTH - 1) = '0' then       -- (now-since) MSB=0 -> now >= since
                        retval_reg <= '1';                -- C: ret_val = 1 (bir daha dusmez, in dusene dek)
                    end if;
                end if;
            else                                          -- C: else { obj->aux = 0 }
                aux        <= '0';
                retval_reg <= '0';
            end if;
        end if;
    end process;

    retval <= retval_reg;
    since  <= since_reg;

end architecture rtl;
