--------------------------------------------------------------------------------
--  tb_cdc_binary_compare.vhd  -- BINARY vs GRAY CDC karsilastirma testi
--
--  AMAC:
--    AYNI test mantigini (pencere kontrolu: dst yakaladigi deger src'nin
--    {prev, curr} penceresinde mi?) hem binary hem gray versiyona uygula.
--    Böylece ikisini adilce karsilastir.
--
--  BEKLENEN SONUC:
--    Binary: cok sayida hata (imkansiz degerler, src'nin uretmedigi degerler).
--    Gray  : 0 hata (sadece pencere icindeki degerler).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gray_pkg.all;

entity tb_cdc_binary_compare is
end entity tb_cdc_binary_compare;

architecture sim of tb_cdc_binary_compare is

    constant C_SRC_PERIOD : time := 5 ns;
    constant C_DST_PERIOD : time := 7 ns;

    signal src_clk : std_logic := '0';
    signal dst_clk : std_logic := '0';
    signal rst_n   : std_logic := '0';

    -- src domain: tek binary sayac (her iki teste de ayni sirayi uretir)
    signal cnt_src : unsigned(3 downto 0) := (others => '0');
    signal cnt_src_gray : unsigned(3 downto 0);

    -- src kayitli (prev/curr pencere)
    signal src_prev : unsigned(3 downto 0) := (others => '0');
    signal src_prev_gray : unsigned(3 downto 0) := (others => '0');

    -- SKEW MODELLERI (binary ve gray icin ayri, ayni delay degerleri)
    signal bin_skewed  : unsigned(3 downto 0);
    signal gray_skewed : unsigned(3 downto 0);

    -- dst domain kayitli
    signal bin_dst  : unsigned(3 downto 0) := (others => '0');
    signal gray_dst : unsigned(3 downto 0) := (others => '0');

    signal err_bin  : integer := 0;
    signal err_gray : integer := 0;

begin

    src_clk <= not src_clk after C_SRC_PERIOD / 2;
    dst_clk <= not dst_clk after C_DST_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- SRC DOMAIN: tek sayac (binary), gray karsiligi kombinasyonel
    ----------------------------------------------------------------------------
    p_src : process(src_clk, rst_n)
    begin
        if rst_n = '0' then
            cnt_src       <= (others => '0');
            src_prev      <= (others => '0');
            src_prev_gray <= (others => '0');
        elsif rising_edge(src_clk) then
            src_prev      <= cnt_src;                  -- prev binary
            src_prev_gray <= to_gray(cnt_src);         -- prev gray
            cnt_src       <= cnt_src + 1;
        end if;
    end process p_src;

    cnt_src_gray <= to_gray(cnt_src);

    ----------------------------------------------------------------------------
    -- SKEW MODELLERI (ayni delay degerleri - adil test)
    ----------------------------------------------------------------------------
    bin_skewed(0)  <= transport cnt_src(0)      after 0    ps;
    bin_skewed(1)  <= transport cnt_src(1)      after 600  ps;
    bin_skewed(2)  <= transport cnt_src(2)      after 1200 ps;
    bin_skewed(3)  <= transport cnt_src(3)      after 1800 ps;

    gray_skewed(0) <= transport cnt_src_gray(0) after 0    ps;
    gray_skewed(1) <= transport cnt_src_gray(1) after 600  ps;
    gray_skewed(2) <= transport cnt_src_gray(2) after 1200 ps;
    gray_skewed(3) <= transport cnt_src_gray(3) after 1800 ps;

    ----------------------------------------------------------------------------
    -- DST DOMAIN: hem binary hem gray'i ornekle + hata say
    ----------------------------------------------------------------------------
    p_dst : process(dst_clk, rst_n)
        variable v_bin_ok  : boolean;
        variable v_gray_ok : boolean;
    begin
        if rst_n = '0' then
            bin_dst  <= (others => '0');
            gray_dst <= (others => '0');
            err_bin  <= 0;
            err_gray <= 0;
        elsif rising_edge(dst_clk) then
            bin_dst  <= bin_skewed;
            gray_dst <= gray_skewed;

            -- BINARY pencere kontrolu: yakalanan, {prev, curr} binary'den biri mi?
            v_bin_ok := (bin_skewed = src_prev) or (bin_skewed = cnt_src);
            if not v_bin_ok then
                err_bin <= err_bin + 1;
                report "[BINARY] HATA: dst " & integer'image(to_integer(bin_skewed)) &
                       " - src penceresi {" & integer'image(to_integer(src_prev)) &
                       "," & integer'image(to_integer(cnt_src)) & "}" severity warning;
            end if;

            -- GRAY pencere kontrolu: yakalanan gray, {prev_gray, curr_gray}'den biri mi?
            v_gray_ok := (gray_skewed = src_prev_gray) or (gray_skewed = cnt_src_gray);
            if not v_gray_ok then
                err_gray <= err_gray + 1;
                report "[GRAY] HATA: dst binary=" &
                       integer'image(to_integer(to_binary(gray_skewed))) &
                       " - src penceresi {" &
                       integer'image(to_integer(to_binary(src_prev_gray))) & "," &
                       integer'image(to_integer(to_binary(cnt_src_gray))) & "}" severity warning;
            end if;
        end if;
    end process p_dst;

    ----------------------------------------------------------------------------
    -- STIMULUS
    ----------------------------------------------------------------------------
    p_stim : process
    begin
        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait for 2000 ns;
        report "==========================================" severity note;
        report "  KARSILASTIRMA SONUCU (2000 ns)" severity note;
        report "  BINARY hata sayisi: " & integer'image(err_bin) severity note;
        report "  GRAY   hata sayisi: " & integer'image(err_gray) severity note;
        report "==========================================" severity note;
        wait;
    end process p_stim;

end architecture sim;
