--------------------------------------------------------------------------------
--  edge_detector.vhd  -- yukselen kenar algilayici, C koduyla BIREBIR
--  Referans: edge_detection.c / .h
--
--  C IMZASI:
--     uint8_t edgeDetection(edge_detection_t *obj, uint8_t val)
--     struct: { uint32_t aux; }
--
--  C MANTIGI:
--     if(val) { if(!obj->aux) { obj->aux = 1; retval = 1; } }
--     else    { obj->aux = 0; }
--     -> retval sadece val'in 0->1 gectigi ANDA (tek sefer) 1 olur.
--
--  DONANIM KARSILIGI:
--     C'deki 'obj->aux' = val'in bir onceki degeri (bir flip-flop).
--     Kenar = val AND (NOT aux). Bu tek satir, C'deki if bloklarinin esdegeri
--     ve tek saat vurusluk (pulse) uretir -> start/stop tetigi icin ideal.
--
--  ISIM ESLESMESI:  C 'val' -> val,  C 'aux' -> aux,  C donus -> retval
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity edge_detector is
    port (
        clk    : in  std_logic;
        rst_n  : in  std_logic;
        val    : in  std_logic;   -- C: val (izlenen sinyal; senkron olmali)
        retval : out std_logic    -- C: retval (kenar aninda tek-tick '1')
    );
end entity edge_detector;

architecture rtl of edge_detector is
    signal aux : std_logic;       -- C: obj->aux = val'in bir onceki degeri
begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            aux <= '0';
        elsif rising_edge(clk) then
            aux <= val;            -- her saatte "onceki deger"i guncelle
        end if;
    end process;

    -- val=1 ve onceki=0 -> yukselen kenar (C: !obj->aux iken val -> retval=1)
    retval <= val and not aux;

end architecture rtl;
