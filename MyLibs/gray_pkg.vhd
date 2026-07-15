--------------------------------------------------------------------------------
--  gray_pkg.vhd  -- binary <-> gray code dönüşüm fonksiyonlari (CDC icin)
--
--  AMAC:
--    Clock-domain crossing (CDC) icin gray code uretmek. Gray code'un ozelligi:
--    ardışık iki deger arasinda TAM 1 bit degisir. Boylece bir sayaci gray
--    olarak kodlayip asenkron olarak baska bir domain'e gecirirsen, alici taraf
--    ya eski ya da yeni degeri gorur - asla ikisinin karisimi imkansiz bir
--    deger gormez. Bu, async FIFO pointer senkronizasyonunun temelidir.
--
--  NEDEN GRAY CODE CDC'YI COZER?
--    Binary 0111 -> 1000 gecisinde 4 bit birden degisir. Her bit'in FF
--    propagation delay'i farkli oldugu icin alici bazilarini yeni, bazilarini
--    eski gorur -> gercekte hic var olmamis deger (ornegin 1111).
--    Gray 0100 -> 1100 gecisinde SADECE 1 bit (MSB) degisir. O bit ya eski ya
--    yeni okunur; digerleri sabit. -> alici ya 0100 ya 1100 gorur, ikisi de
--    gecerli. Imkansiz deger YOK.
--
--  DONUSUM MANTIGI:
--    Binary -> Gray:  gray[i] = bin[i] XOR bin[i+1],  gray[MSB] = bin[MSB]
--                     (kisa formul: gray = bin XOR (bin >> 1))
--    Gray -> Binary:  bin[MSB] = gray[MSB],  bin[i] = gray[i] XOR bin[i+1]
--                     (MSB'den LSB'ye cascade XOR - prefix XOR)
--
--  KULLANIM:
--    library work;
--    use work.gray_pkg.all;
--    ...
--    gray_ptr <= to_gray(bin_ptr);
--    bin_ptr  <= to_binary(gray_ptr);
--
--  SENTEZ: her iki fonksiyon da tamamen XOR kapilarina sentezlenir. Sifir FF,
--          sifir counter - sadece kombinatorik mantik. Hardware maliyeti yok.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package gray_pkg is

    -- Binary -> Gray donusumu.
    -- gray = bin XOR (bin >> 1)
    -- Donusum saf XOR'dur; N bit icin N-1 XOR kapi, MSB direkt gecer.
    function to_gray (bin : unsigned) return unsigned;

    -- Gray -> Binary donusumu.
    -- bin[i] = gray[i] XOR bin[i+1] (MSB'den LSB'ye cascade)
    -- Bu "prefix XOR" olarakta bilinir. Her bit icin o bitten MSB'ye kadar
    -- gray bit'lerinin XOR'u. Sentzelemede cascade XOR zinciri olur.
    function to_binary (gray : unsigned) return unsigned;

end package gray_pkg;


package body gray_pkg is

    ----------------------------------------------------------------------
    -- to_gray: binary -> gray
    --   gray[i] = bin[i] XOR bin[i+1]  (i = 0..N-2)
    --   gray[N-1] = bin[N-1]            (MSB ayni kalir)
    --
    --   numeric_std'de shift_right unsigned icin logical shift yapar.
    --   'bin xor shift_right(bin,1)' tek satirda butun bit'leri hesaplar:
    --     - MSB: bin[N-1] xor 0 = bin[N-1]  (shift'in basina 0 gelir)
    --     - bit i: bin[i] xor bin[i+1]
    ----------------------------------------------------------------------
    function to_gray (bin : unsigned) return unsigned is
    begin
        return bin xor shift_right(bin, 1);
    end function to_gray;

    ----------------------------------------------------------------------
    -- to_binary: gray -> binary
    --   bin[N-1] = gray[N-1]
    --   bin[i]   = gray[i] xor bin[i+1]
    --
    --   Bu cascade'tir: her bit bir onceki (daha yuksek) sonucu kullanir.
    --   Bu yuzden MSB'den baslayip LSB'ye dogru bir loop ile hesaplanir.
    --   (Saf kombinasyonel - her iteration bir XOR kapi ekler.)
    ----------------------------------------------------------------------
    function to_binary (gray : unsigned) return unsigned is
        -- Sonucu her zaman [N-1:0] standard aralikta uretelim, boylece
        -- index hesabi (i, i+1) sorun cikarmaz. gray'in MUTLAK genisligi.
        constant C_W    : natural  := gray'length;
        variable v_bin  : unsigned(C_W - 1 downto 0);
        variable v_gray : unsigned(C_W - 1 downto 0) := gray;  -- normalize et
        variable v_bit  : std_logic;
    begin
        -- MSB'den LSB'ye cascade XOR:  bin[i] = gray[i] xor bin[i+1]
        -- (xor std_logic icin tanimli; her bit'i ayri std_logic'a cikartiyoruz)
        for i in C_W - 1 downto 0 loop
            if i = C_W - 1 then
                v_bin(i) := v_gray(i);                          -- MSB: direkt kopya
            else
                v_bit := v_gray(i) xor v_bin(i + 1);            -- std_logic xor std_logic
                v_bin(i) := v_bit;
            end if;
        end loop;
        return v_bin;
    end function to_binary;

end package body gray_pkg;
