--------------------------------------------------------------------------------
--  fifo_async.vhd  -- Asenkron FIFO (iki clock domain arasi)
--
--  AMAC:
--    FARKLI clock domain'ler arasinda veri tamponu olmak. Uretici (wr_clk) ve
--    alici (rd_clk) farkli frekans/faz'da calisir. Hiz farkini ve CDC'yi yonetir.
--
--  IMU SENARYOSU (bu modul neden yazildi):
--    IMU sensör (SPI clock ~10 MHz) -> [bu FIFO] -> FPGA fabric (50 MHz)
--    Write domain = SPI clock, Read domain = FPGA clock. Iki domain iliskisiz.
--
--  MIMARI (Cliff Cummings async FIFO):
--    Sync FIFO'nun (fifo_sync.vhd) temel pointer matematiğinin üstüne:
--      1) Pointer'lari GRAY kodla (to_gray) -> CDC güvenli (1 bit degisim)
--      2) Gray pointer'lari 2-FF ile karsi domain'e tasi (synchronizer)
--      3) Karsi domain'de gray'i binary'ye cevir (to_binary) -> full/empty kontrolü
--
--  NEDEN GRAY?
--    Binary pointer artarken cok bit degisir (0111->1000 = 4 bit). 2-FF skew'i
--    ile alici "hic var olmamis" deger görür. Gray'de ardısık degerlerde 1 bit
--    degisir -> alici ya eski ya yeni görür, ikisi de gecerli. (Faz 2.2 ispat)
--
--  N+1 BIT HILESI (sync FIFO'dan geldi):
--    Pointer'lara 1 ekstra bit (tur biti) eklendi. DEPTH=8 (3 bit) icin pointer
--    4 bit. Bu bit "full mu, empty mi?" belirsizligini cozer:
--      empty: wr_gray_sync == rd_gray (ayni tur, ayni index)
--      full : alt N bit ayni, tur biti farkli (bir tur dolandi)
--
--  SAFE FULL/EMPTY (optimistic, konservativ):
--    empty: read domain, write pointer'in SENKRONIZE EDEGİNİ görür. Write yeni
--           veri koymus olabilir ama read henüz görmemis olabilir -> empty'i
--           "agirlikli" (gec kmil) bildirir -> guvenli (okumaya calismaz).
--    full : write domain, read pointer'in SENKRONIZE DEGERINI görür. Read veri
--           cikarmis olabilir ama write henüz görmemis olabilir -> full'u
--           "erken" bildirir -> guvenli (yazmaya calismaz, overflow yok).
--
--  KULLANIM:
--    u_fifo : entity work.fifo_async
--      generic map ( G_WIDTH => 32, G_DEPTH => 16 )
--      port map (
--          rst_n    => rst_n,
--          -- write side (wr_clk domain)
--          wr_clk   => wr_clk,
--          wr_en    => wr_en,
--          wr_data  => wr_data,
--          full     => full,
--          -- read side (rd_clk domain)
--          rd_clk   => rd_clk,
--          rd_en    => rd_en,
--          rd_data  => rd_data,
--          empty    => empty
--      );
--
--  ONEMli: G_DEPTH mutlaka 2^n olmali (4, 8, 16, 32, ...). Wrap islemi mask ile.
--  rst_n HER IKI domain tarafindan gorulmeli (kart reset'i, senkron olmasa da OK
--  cunku reset asenkron).
--
--  BAĞIMLILIKLAR:
--    - gray_pkg       (to_gray / to_binary)
--    - synchronizer   (2-FF CDC)
--    Bu modul bu ikisini BIRLIKTE kullanir - Faz 2 + Faz 3.1'in sentezi.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.gray_pkg.all;                    -- to_gray / to_binary

entity fifo_async is
    generic (
        G_WIDTH : positive := 32;         -- veri genisligi (bit)
        G_DEPTH : positive := 16          -- kac eleman (2^n OLMALI)
    );
    port (
        rst_n   : in  std_logic;          -- asenkron reset (her iki domain)

        -- Write side (wr_clk domain)
        wr_clk  : in  std_logic;
        wr_en   : in  std_logic;
        wr_data : in  std_logic_vector(G_WIDTH-1 downto 0);
        full    : out std_logic;

        -- Read side (rd_clk domain)
        rd_clk  : in  std_logic;
        rd_en   : in  std_logic;
        rd_data : out std_logic_vector(G_WIDTH-1 downto 0);
        empty   : out std_logic
    );
end entity fifo_async;


architecture rtl of fifo_async is

    --------------------------------------------------------------------------
    -- POINTER GENISLIKLERI (N+1 bit hilesi - sync FIFO ile ayni)
    --------------------------------------------------------------------------
    constant C_PTR_W  : positive := integer(ceil(log2(real(G_DEPTH))));  -- index
    constant C_FULL_W : positive := C_PTR_W + 1;                         -- + tur biti

    --------------------------------------------------------------------------
    -- DAIRESELAL RAM (inferred BRAM)
    -- Write ve read farkli clock'larda -> Quartus "simple-dual-port RAM"
    -- olarak sentezler (ayri write/read clock'lari). Yine M10K bloklari.
    --------------------------------------------------------------------------
    type t_ram is array(0 to G_DEPTH-1) of std_logic_vector(G_WIDTH-1 downto 0);
    signal ram : t_ram := (others => (others => '0'));

    --------------------------------------------------------------------------
    -- WRITE DOMAIN sinyalleri
    --------------------------------------------------------------------------
    -- wr_ptr : write domain'in binary pointer'i (N+1 bit)
    -- wr_gray : wr_ptr'nin gray karsiligi (karsi domain'e gonderilecek)
    -- rd_gray_sync : read domain'den gelip 2-FF ile senkronize edilmis gray rd ptr
    -- rd_bin_wr : senkronize gray'i binary'ye cevirmis hali (full kontrolu icin)
    signal wr_ptr      : unsigned(C_FULL_W-1 downto 0) := (others => '0');
    signal wr_gray     : unsigned(C_FULL_W-1 downto 0);
    signal rd_gray_sync: unsigned(C_FULL_W-1 downto 0);
    signal rd_bin_wr   : unsigned(C_FULL_W-1 downto 0);
    signal full_i      : std_logic;

    --------------------------------------------------------------------------
    -- READ DOMAIN sinyalleri
    --------------------------------------------------------------------------
    -- rd_ptr : read domain'in binary pointer'i (N+1 bit)
    -- rd_gray : rd_ptr'nin gray karsiligi (karsi domain'e gonderilecek)
    -- wr_gray_sync : write domain'den gelip 2-FF ile senkronize edilmis gray wr ptr
    -- wr_bin_rd : senkronize gray'i binary'ye cevirmis hali (empty kontrolu icin)
    signal rd_ptr      : unsigned(C_FULL_W-1 downto 0) := (others => '0');
    signal rd_gray     : unsigned(C_FULL_W-1 downto 0);
    signal wr_gray_sync: unsigned(C_FULL_W-1 downto 0);
    signal wr_bin_rd   : unsigned(C_FULL_W-1 downto 0);
    signal empty_i     : std_logic;

begin

    --------------------------------------------------------------------------
    -- GRAY KODLAMA (kombinasyonel - her domain kendi pointer'ini kodlar)
    --------------------------------------------------------------------------
    -- to_gray: binary -> gray. Sentezde sadece XOR kapilari (gray_pkg.vhd).
    -- Bu gray deger karsi domain'e 2-FF ile gonderilir.
    wr_gray <= to_gray(wr_ptr);
    rd_gray <= to_gray(rd_ptr);

    --------------------------------------------------------------------------
    -- GRAY -> BINARY (kombinasyonel - senkronize gray'i çöz)
    --------------------------------------------------------------------------
    -- Karsi domain'den gelen gray pointer binary'ye cevrilir ki full/empty
    -- icin N+1 bit hilesi karsilastirmasi yapilabilsin.
    rd_bin_wr <= to_binary(rd_gray_sync);
    wr_bin_rd <= to_binary(wr_gray_sync);

    --------------------------------------------------------------------------
    -- 2-FF SENKRONIZATORU: gray pointer'i karsi domain'e tasi
    --------------------------------------------------------------------------
    -- Her pointer icin ayri synchronizer. gray pointer N+1 bit oldugu icin
    -- her bit ayri 2-FF zincirinden gecer. Ama gray oldugu icin güvenli:
    -- ardısık degerlerde sadece 1 bit degisir -> skew olsa bile tutarli.
    --
    -- Synchronizer her bit icin ayri cagriliyor (vector degil, bit-bit).
    -- Bu, sentezde her bit icin ayri 2-FF zinciri verir.
    --------------------------------------------------------------------------
    gen_sync_rd : for i in 0 to C_FULL_W-1 generate
        u_sync_rd : entity work.synchronizer
            generic map ( G_STAGES => 2, G_RST_VAL => '0' )
            port map ( clk => wr_clk, rst_n => rst_n,
                       async_in => rd_gray(i), sync_out => rd_gray_sync(i) );
    end generate gen_sync_rd;

    gen_sync_wr : for i in 0 to C_FULL_W-1 generate
        u_sync_wr : entity work.synchronizer
            generic map ( G_STAGES => 2, G_RST_VAL => '0' )
            port map ( clk => rd_clk, rst_n => rst_n,
                       async_in => wr_gray(i), sync_out => wr_gray_sync(i) );
    end generate gen_sync_wr;

    --------------------------------------------------------------------------
    -- FULL FLAG (write domain'de hesaplanir)
    --------------------------------------------------------------------------
    -- full: write domain, read pointer'in SENKRONIZE degerini görür.
    -- N+1 bit hilesi: alt N bit ayni, tur biti farkli -> dolu.
    -- Sync FIFO ile ayni karsilastirma, ama rd_bin_wr senkronize edilmis deger.
    --------------------------------------------------------------------------
    full_i <= '1' when (wr_ptr(C_PTR_W-1 downto 0) = rd_bin_wr(C_PTR_W-1 downto 0))
                       and (wr_ptr(C_PTR_W) /= rd_bin_wr(C_PTR_W))
              else '0';

    --------------------------------------------------------------------------
    -- EMPTY FLAG (read domain'de hesaplanir)
    --------------------------------------------------------------------------
    -- empty: read domain, write pointer'in SENKRONIZE degerini görür.
    -- Iki pointer tamamen ayni (tur + index) -> bos.
    --------------------------------------------------------------------------
    empty_i <= '1' when wr_bin_rd = rd_ptr else '0';

    --------------------------------------------------------------------------
    -- WRITE PROCESS (wr_clk domain)
    --------------------------------------------------------------------------
    -- Sync FIFO'ya cok benziyor - sadece clock wr_clk ve full kontrolu
    -- senkronize edilmis rd pointer'a göre yapiliyor.
    --------------------------------------------------------------------------
    p_write : process(wr_clk, rst_n)
    begin
        if rst_n = '0' then
            wr_ptr <= (others => '0');
        elsif rising_edge(wr_clk) then
            if wr_en = '1' and full_i = '0' then
                ram(to_integer(wr_ptr(C_PTR_W-1 downto 0))) <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end if;
        end if;
    end process p_write;

    --------------------------------------------------------------------------
    -- READ PROCESS (rd_clk domain)
    --------------------------------------------------------------------------
    -- rd_data FWFT (kombinasyonel) - sync FIFO ile ayni davranis.
    --------------------------------------------------------------------------
    rd_data <= ram(to_integer(rd_ptr(C_PTR_W-1 downto 0)));

    p_read : process(rd_clk, rst_n)
    begin
        if rst_n = '0' then
            rd_ptr <= (others => '0');
        elsif rising_edge(rd_clk) then
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
