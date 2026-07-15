--------------------------------------------------------------------------------
--  fifo_sync.vhd  -- Senkron FIFO (tek clock domain)
--
--  AMAC:
--    Ayni clock domain'de uretici ve alici arasinda tampon (buffer) olmak.
--    Uretici (writer) veriyi yazar, alici (reader) ayni clock'ta okur.
--    Hiz farkini (burst'leri) emer.
--
--  NEDEN SYNC? (async FIFO'dan farki):
--    Tek clock var. Bu yuzden gray code'a, 2-FF'e, handshake'e GEREK YOK.
--    Pointer'lar dogrudan karsilastirilabilir (ayni clock domain'de).
--    Bu, FIFO'nun "saf" halidir - sadece pointer matematiği + full/empty.
--    Async FIFO'yu anlamak icin once bunu anlamak sart.
--
--  DAIRESELAL TAMPON (circular buffer):
--    RAM aslinda duz bir dizi: ram[0..DEPTH-1].
--    wr_ptr ve rd_ptr bu dizide dairesel olarak dolasir:
--      0 -> 1 -> 2 -> ... -> (DEPTH-1) -> 0 -> 1 -> ...
--    "% DEPTH" islemini mask ile yapariz (DEPTH 2^n ise sadece alt n bit).
--
--  "FULL MU, EMPTY MI?" SORUNU - N+1 BIT HILESI:
--    Eger wr_ptr == rd_ptr ise iki anlama gelebilir:
--      a) HIC veri yok (empty)
--      b) Tamamen dolu (writer, reader'i bir tur gecip yakaladi - full)
--    Bu belirsizligi cozmek icin pointer'lara 1 EKSTRA BIT ekleriz.
--    DEPTH=8 (3 bit) icin pointer 4 bit olur. Alt 3 bit = index, MSB = tur.
--      empty: wr_ptr == rd_ptr                  (ayni tur, ayni index)
--      full : wr_ptr(N-2:0) == rd_ptr(N-2:0)    (ayni index)
--             wr_ptr(N-1)   /= rd_ptr(N-1)      (farkli tur -> bir tur dolandi)
--    Yani full sartinda MSB farkli, alt bitler ayni.
--
--  INFERRED BRAM (RAM'i kendin tanimla, Quartus blok RAM yapsin):
--    Aşağıda "type t_ram is array..." ile bir dizi tanimliyoruz. Bu dizi
--    senzlendiğinde Quartus bunu otomatik olarak Cyclone V'in M10K bloklarina
--    (yerlesik RAM) donusturur. Bu sunedenir:
--      - ayni clock'ta write ve read adresleri ayri olabilir (simple-dual)
--      - write sirasinda eski deger (read-first) okunabilir
--    Bu yonteme "RAM inference" denir. Black-box IP kullanmadan, tam VHDL.
--
--  KULLANIM:
--    u_fifo : entity work.fifo_sync
--      generic map ( G_WIDTH => 32, G_DEPTH => 16 )   -- DEPTH 2^n olmali!
--      port map (
--          clk     => clk,
--          rst_n   => rst_n,
--          wr_en   => wr_en,    -- yazma yetkisi
--          wr_data => wr_data,  -- yazilacak veri
--          full    => full,     -- 1: dolu, yazma!
--          rd_en   => rd_en,    -- okuma yetkisi
--          rd_data => rd_data,  -- okunan veri
--          empty   => empty     -- 1: bos, okuma!
--      );
--
--  ONEMli: G_DEPTH mutlaka 2^n olmali (4, 8, 16, 32, ...). Cunku wrap
--  islemini mask (alt N bit) ile yapiyoruz, modul operatoru ile degil.
--  2^n olmazsa "mask" calismaz. Generic init'te bunu garanti edemiyoruz,
--  bu yuzden kullanan kisinin dikkatine birakiyoruz. (Ileride assert
--  ekleyebiliriz: assert G_DEPTH'is power of 2.)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;                    -- clog2 icin

entity fifo_sync is
    generic (
        G_WIDTH : positive := 32;       -- veri genisligi (bit)
        G_DEPTH : positive := 16        -- kac eleman (2^n OLMALI: 4,8,16,32,...)
    );
    port (
        clk     : in  std_logic;
        rst_n   : in  std_logic;

        -- Yazma tarafı (write side)
        wr_en   : in  std_logic;
        wr_data : in  std_logic_vector(G_WIDTH-1 downto 0);
        full    : out std_logic;

        -- Okuma tarafı (read side)
        rd_en   : in  std_logic;
        rd_data : out std_logic_vector(G_WIDTH-1 downto 0);
        empty   : out std_logic
    );
end entity fifo_sync;


architecture rtl of fifo_sync is

    --------------------------------------------------------------------------
    -- POINTER GENISLIKLERI - N+1 bit hilesi
    --------------------------------------------------------------------------
    -- G_DEPTH=16 -> index 4 bit (0..15). Pointer'a 1 ekstra bit ekliyoruz:
    -- 5 bit. Alt 4 bit = index, MSB (bit 4) = tur sayaci.
    -- Bu ekstra bit "full" tespiti icin sart (yukaridaki yoruma bak).
    --------------------------------------------------------------------------
    constant C_PTR_W   : positive := integer(ceil(log2(real(G_DEPTH))));  -- index genisligi
    constant C_ADDR_W  : positive := C_PTR_W;                 -- RAM adres genisligi
    constant C_FULL_W  : positive := C_PTR_W + 1;             -- pointer + tur biti (orn 5)

    --------------------------------------------------------------------------
    -- DAIRESELAL RAM (inferred BRAM)
    --------------------------------------------------------------------------
    -- Bu dizi sentezlendiğinde Quartus'un M10K bloklarina (yerlesik RAM)
    -- donusur. "Read-first" modunda (yazarken eski deger okunur).
    --------------------------------------------------------------------------
    type t_ram is array(0 to G_DEPTH-1) of std_logic_vector(G_WIDTH-1 downto 0);
    signal ram : t_ram := (others => (others => '0'));

    --------------------------------------------------------------------------
    -- POINTER'LAR (N+1 bit)
    --------------------------------------------------------------------------
    -- Her ikisi de N+1 bit. Alt N bit = index, MSB = tur.
    -- wr_ptr = su anki yazma konumu
    -- rd_ptr = su anki okuma konumu
    --------------------------------------------------------------------------
    signal wr_ptr : unsigned(C_FULL_W-1 downto 0) := (others => '0');
    signal rd_ptr : unsigned(C_FULL_W-1 downto 0) := (others => '0');

    --------------------------------------------------------------------------
    -- FULL / EMPTY hesabi (kombinasyonel)
    --------------------------------------------------------------------------
    -- empty: iki pointer tamamen ayni (ayni tur, ayni index) -> HIC veri yok
    -- full : alt N bit ayni (ayni index) ama MSB farkli (bir tur dolandi)
    --------------------------------------------------------------------------
    signal full_i  : std_logic;
    signal empty_i : std_logic;

begin

    --------------------------------------------------------------------------
    -- FULL / EMPTY flag'leri (kombinasyonel - pointer'lardan dogrudan)
    --------------------------------------------------------------------------
    empty_i <= '1' when wr_ptr = rd_ptr else '0';

    -- full: alt C_PTR_W bit ayni, MSB farkli
    full_i  <= '1' when (wr_ptr(C_PTR_W-1 downto 0) = rd_ptr(C_PTR_W-1 downto 0))
                       and (wr_ptr(C_PTR_W) /= rd_ptr(C_PTR_W))
               else '0';

    --------------------------------------------------------------------------
    -- RAM YAZMA (write) - sadece wr_en=1 ve full DEGILse
    --------------------------------------------------------------------------
    -- Quartus'a "bu bir RAM" ipucu: write ve read ayri islemler, clock'lanmis.
    --------------------------------------------------------------------------
    p_write : process(clk, rst_n)
    begin
        if rst_n = '0' then
            wr_ptr <= (others => '0');
        elsif rising_edge(clk) then
            if wr_en = '1' and full_i = '0' then
                -- veriyi RAM'e yaz (adres = alt N bit)
                ram(to_integer(wr_ptr(C_PTR_W-1 downto 0))) <= wr_data;
                -- pointer'i ilerlet (N+1 bit sayac, otomatik wrap)
                wr_ptr <= wr_ptr + 1;
            end if;
        end if;
    end process p_write;

    --------------------------------------------------------------------------
    -- RAM OKUMA (read) - sadece rd_en=1 ve empty DEGILse
    --------------------------------------------------------------------------
    -- rd_data'yi KOMBINASYONEL olarak cikariyoruz (rd_ptr adresinden).
    -- Bu, "first-word-fall-through" (FWFT) davranisi verir: rd_en=1 yapinca
    -- ayni clock'ta rd_data gecerli olur. (Bazı FIFO'lar registered rd_data
    -- verir, 1 clock gecikmeli - biz FWFT sectik, kullanmasi daha kolay.)
    --------------------------------------------------------------------------
    rd_data <= ram(to_integer(rd_ptr(C_PTR_W-1 downto 0)));

    p_read : process(clk, rst_n)
    begin
        if rst_n = '0' then
            rd_ptr <= (others => '0');
        elsif rising_edge(clk) then
            if rd_en = '1' and empty_i = '0' then
                rd_ptr <= rd_ptr + 1;
            end if;
        end if;
    end process p_read;

    --------------------------------------------------------------------------
    -- CIKISLARA bagla
    --------------------------------------------------------------------------
    full  <= full_i;
    empty <= empty_i;

end architecture rtl;
