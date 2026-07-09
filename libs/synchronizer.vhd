--------------------------------------------------------------------------------
--  synchronizer.vhd
--  Author : (senin projen)  -- referans TON: Emrah Duatepe
--
--  AMAC:
--    Asenkron bir dis sinyali (buton, harici sensor, baska bir clock domain'den
--    gelen bit) bizim saat domainimize GUVENLI sekilde tasimak.
--
--    Buton ne zaman basilacagini bizim 50 MHz saatimiz bilmez. Eger bu sinyali
--    dogrudan bir flip-flop'a verirsek, tam "setup/hold" penceresinde degisirse
--    flip-flop METASTABLE (kararsiz, 0 da degil 1 de degil) olabilir. Cozum:
--    sinyali arka arkaya birkac flip-flop'tan gecirmek. Ilk FF metastable olsa
--    bile, bir sonraki saat kenarina kadar oturur; ikinci/ucuncu FF temiz alir.
--
--  Bu blok generic: kac FF derinliginde olacagini disaridan veriyorsun.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity synchronizer is
    generic (
        G_STAGES  : positive := 2;      -- kac flip-flop derinligi (min 2 onerilir)
        G_RST_VAL : std_logic := '0'    -- reset aninda zincirin alacagi deger
    );
    port (
        clk     : in  std_logic;        -- hedef saat domaini (50 MHz)
        rst_n   : in  std_logic;        -- asenkron reset, aktif-dusuk
        async_in: in  std_logic;        -- disaridan gelen senkronsuz sinyal
        sync_out: out std_logic         -- bizim domaine oturmus temiz sinyal
    );
end entity synchronizer;

architecture rtl of synchronizer is
    -- Zincir: G_STAGES adet flip-flop'u tek bir vektorde tutuyoruz.
    signal ff_chain : std_logic_vector(G_STAGES - 1 downto 0);
begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            -- Reset: tum zinciri bilinen bir degere cek.
            ff_chain <= (others => G_RST_VAL);

        elsif rising_edge(clk) then
            -- Her saat kenarinda zinciri bir kaydir:
            --  yeni giris -> FF0 -> FF1 -> ... -> cikis
            ff_chain(0) <= async_in;
            for i in 1 to G_STAGES - 1 loop
                ff_chain(i) <= ff_chain(i - 1);
            end loop;
        end if;
    end process;

    -- Zincirin en sonundaki (en oturmus) bit disari verilir.
    sync_out <= ff_chain(G_STAGES - 1);

end architecture rtl;
