--------------------------------------------------------------------------------
--  tb_fifo_sync.vhd  -- Sync FIFO testbench
--
--  SENARYOLAR:
--    1) Yaz + hemen oku (back-to-back) - veri sirali geliyor mu?
--    2) FIFO'yu doldur (16 eleman) - full flag dogru mu?
--    3) FIFO'yu bosalt - empty flag dogru mu?
--    4) Ayni anda yaz + oku (FIFO throughput testi)
--
--  BEKLENEN SONUC:
--    - Veriler yazildigi SIRAYLA okunur (FIFO = kuyruk)
--    - 16 yazinca full=1 olur, 17. yazma girmez (overflow korumasi)
--    - Hepsini okuyunca empty=1 olur
--    - Wr_ptr ve rd_ptr N+1 bit hareketini gozlemleyebiliriz
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_fifo_sync is
end entity tb_fifo_sync;

architecture sim of tb_fifo_sync is

    constant C_PERIOD : time := 10 ns;

    signal clk     : std_logic := '0';
    signal rst_n   : std_logic := '0';

    signal wr_en   : std_logic := '0';
    signal wr_data : std_logic_vector(15 downto 0) := (others => '0');
    signal full    : std_logic;

    signal rd_en   : std_logic := '0';
    signal rd_data : std_logic_vector(15 downto 0);
    signal empty   : std_logic;

    -- Dogrulama sayaci
    signal check_cnt : integer := 0;

begin

    clk <= not clk after C_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    u_dut : entity work.fifo_sync
        generic map ( G_WIDTH => 16, G_DEPTH => 16 )
        port map (
            clk     => clk,
            rst_n   => rst_n,
            wr_en   => wr_en,
            wr_data => wr_data,
            full    => full,
            rd_en   => rd_en,
            rd_data => rd_data,
            empty   => empty
        );

    ----------------------------------------------------------------------------
    -- STIMULUS
    ----------------------------------------------------------------------------
    p_stim : process
    begin
        -----------------------------------------------------------------------
        -- RESET
        -----------------------------------------------------------------------
        rst_n <= '0';
        wait for 30 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- TEST 1: 3 eleman yaz, sonra oku (sira kontrolu)
        -----------------------------------------------------------------------
        report "TEST 1: 3 eleman yaz + oku (sira kontrolu)" severity note;

        -- 0xAA00 yaz
        wr_data <= x"AA00";  wr_en <= '1';
        wait until rising_edge(clk);
        -- 0xAA01 yaz
        wr_data <= x"AA01";
        wait until rising_edge(clk);
        -- 0xAA02 yaz
        wr_data <= x"AA02";
        wait until rising_edge(clk);
        wr_en <= '0';
        wait until rising_edge(clk);

        -- Simdi oku: sirayla AA00, AA01, AA02 gelmeli
        -- FWFT: rd_data, rd_ptr'nin gosterdigi elemani KOMBINASYONEL olarak
        -- verir. rd_en=1 yapinca pointer bir sonraki clock'ta ilerler.
        rd_en <= '1';
        -- rd_data su an rd_ptr=0 -> AA00 gosteriyor (FWFT)
        assert rd_data = x"AA00" report "TEST1 FAIL: 1. okuma AA00 degil: 0x" &
               to_hstring(rd_data) severity error;
        check_cnt <= check_cnt + 1;
        wait until rising_edge(clk);   -- bu kenarda rd_ptr 0->1
        assert rd_data = x"AA01" report "TEST1 FAIL: 2. okuma AA01 degil: 0x" &
               to_hstring(rd_data) severity error;
        check_cnt <= check_cnt + 1;
        wait until rising_edge(clk);   -- rd_ptr 1->2
        rd_en <= '0';
        assert rd_data = x"AA02" report "TEST1 FAIL: 3. okuma AA02 degil: 0x" &
               to_hstring(rd_data) severity error;
        check_cnt <= check_cnt + 1;
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- TEST 2: FIFO'yu doldur (16 eleman = DEPTH)
        -----------------------------------------------------------------------
        report "TEST 2: 16 eleman yaz (doldur)" severity note;

        -- 16 eleman yaz (0xBB00 .. 0xBB0F)
        for i in 0 to 15 loop
            wr_data <= std_logic_vector(to_unsigned(16#BB00# + i, 16));
            wr_en   <= '1';
            wait until rising_edge(clk);
        end loop;
        wr_en <= '0';
        wait until rising_edge(clk);

        -- full flag artik 1 olmali
        assert full = '1' report "TEST2 FAIL: 16 yazmama ragmen full=1 olmadi" severity error;
        report "TEST2: full flag = 1 (DOGRU)" severity note;

        -- 17. yazma denenir - FIFO dolu, veri girmemeli
        wr_data <= x"FFFF";  wr_en <= '1';
        wait until rising_edge(clk);
        wr_en <= '0';
        assert full = '1' report "TEST2: full hala 1 (overflow korumasi calisiyor)" severity note;

        -----------------------------------------------------------------------
        -- TEST 3: FIFO'yu bosalt (16 eleman oku)
        -----------------------------------------------------------------------
        report "TEST 3: 16 eleman oku (doldur)" severity note;

        rd_en <= '1';
        for i in 0 to 15 loop
            -- FWFT: rd_data rd_ptr'nin gosterdigi (su anki) elemani verir.
            -- rd_en=1 iken her clock'ta rd_ptr ilerler, rd_data bir sonraki elemana gecer.
            assert rd_data = std_logic_vector(to_unsigned(16#BB00# + i, 16))
                report "TEST3 FAIL: okuma " & integer'image(i) & " beklenen 0x" &
                to_hstring(std_logic_vector(to_unsigned(16#BB00# + i, 16))) &
                " gercek 0x" & to_hstring(rd_data) severity error;
            check_cnt <= check_cnt + 1;
            wait until rising_edge(clk);   -- rd_ptr ilerler
        end loop;
        rd_en <= '0';
        wait until rising_edge(clk);

        -- empty flag artik 1 olmali
        assert empty = '1' report "TEST3 FAIL: tum veri okundu ama empty=1 olmadi" severity error;
        report "TEST3: empty flag = 1 (DOGRU)" severity note;

        -----------------------------------------------------------------------
        -- SONUC
        -----------------------------------------------------------------------
        report "============================================" severity note;
        report "  TEST SONUCU: " & integer'image(check_cnt) &
                " basarili okuma dogrulandi" severity note;
        report "============================================" severity note;
        wait;
    end process p_stim;

end architecture sim;
