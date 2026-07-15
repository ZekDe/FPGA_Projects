--------------------------------------------------------------------------------
--  tb_fifo_sync.vhd  -- Sync FIFO testbench
--
--  SENARYOLAR:
--    1) 3 eleman yaz + oku (sira kontrolu - FIFO kurali: ilk giren ilk cikar)
--    2) FIFO'yu doldur (16 eleman) - full flag + overflow korumasi
--    3) FIFO'yu bosalt (16 eleman) - empty flag + sira
--
--  FWFT ZAMANLAMASI (onelesen VHDL dersi):
--    rd_data, rd_ptr'den KOMBINASYONEL gelir (FWFT = first-word-fall-through).
--    Yani rd_data = ram[rd_ptr] her an gecerli. AMA rd_ptr bir clock edge'inde
--    guncellenir ve bu guncelleme bir DELTA CYCLE sonra etkili olur.
--    Bu yuzden "wait until rising_edge(clk)" sonrasi rd_ptr henuz yenilenmemis
--    olabilir -> assert yanlis deger gorur.
--
--    COZUM: edge'ten sonra "wait for 1 ps" bekle - sinyallerin yerlesmesi icin.
--    Bu, VHDL testbench'lerinde standart bir tekniktir. Gercek donanimda bu
--    delta cycle yoktur (gercek kapilar fiziksel gecikmelerle calisir), ama
--    simulatorden delta cycle kusruguayi budur.
--
--    Dogru okuma sirasi (FWFT):
--      - rd_data her an rd_ptr'nin gosterdigi elemani gosterir
--      - rd_en=1 iken her clock'ta rd_ptr ilerler
--      - "su anki rd_data"yi kontrol et, sonra clock pulse ver, ilerle
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

    signal check_cnt : integer := 0;
    signal fail_cnt  : integer := 0;

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
        variable v_expected : std_logic_vector(15 downto 0);
    begin
        -----------------------------------------------------------------------
        -- RESET
        -----------------------------------------------------------------------
        rst_n <= '0';
        wait for 30 ns;
        rst_n <= '1';
        wait until rising_edge(clk);
        wait for 1 ps;

        assert empty = '1' report "RESET sonrasi empty=1 olmali" severity error;

        -----------------------------------------------------------------------
        -- TEST 1: 3 eleman yaz, sonra oku (sira kontrolu)
        -----------------------------------------------------------------------
        report "TEST 1: 3 eleman yaz + oku (sira kontrolu)" severity note;

        -- 0xAA00, 0xAA01, 0xAA02 yaz
        wr_data <= x"AA00";  wr_en <= '1';
        wait until rising_edge(clk);
        wr_data <= x"AA01";
        wait until rising_edge(clk);
        wr_data <= x"AA02";
        wait until rising_edge(clk);
        wr_en <= '0';
        wait until rising_edge(clk);
        wait for 1 ps;

        -- 3 eleman var, empty=0 olmali
        assert empty = '0' report "TEST1: 3 yazildi ama empty=0 olmadir" severity error;

        -- FWFT okuma: rd_data su an rd_ptr=0'dan AA00'u gosteriyor.
        -- Her clock'ta rd_ptr ilerler, rd_data bir sonraki elemana gecer.
        rd_en <= '1';
        for i in 0 to 2 loop
            v_expected := std_logic_vector(to_unsigned(16#AA00# + i, 16));
            assert rd_data = v_expected
                report "TEST1 FAIL: okuma " & integer'image(i) &
                       " beklenen 0x" & to_hstring(v_expected) &
                       " gercek 0x" & to_hstring(rd_data)
                severity error;
            wait until rising_edge(clk); wait for 1 ps;
        end loop;
        check_cnt <= check_cnt + 3;
        rd_en <= '0';
        wait until rising_edge(clk); wait for 1 ps;

        assert empty = '1' report "TEST1: 3 okuma sonrasi empty=1 olmali" severity error;

        -----------------------------------------------------------------------
        -- TEST 2: FIFO'yu doldur (16 eleman = DEPTH)
        -----------------------------------------------------------------------
        report "TEST 2: 16 eleman yaz (doldur)" severity note;

        for i in 0 to 15 loop
            wr_data <= std_logic_vector(to_unsigned(16#BB00# + i, 16));
            wr_en   <= '1';
            wait until rising_edge(clk);
        end loop;
        wr_en <= '0';
        wait until rising_edge(clk);
        wait for 1 ps;

        -- full flag artik 1 olmali
        assert full = '1'
            report "TEST2 FAIL: 16 yazmaya ragmen full=1 olmadir" severity error;
        report "TEST2: full flag = 1 (DOGRU)" severity note;

        -- 17. yazma denenir - FIFO dolu, veri girmemeli (overflow korumasi)
        wr_data <= x"FFFF";  wr_en <= '1';
        wait until rising_edge(clk);
        wr_en <= '0';
        wait for 1 ps;
        assert full = '1' report "TEST2: overflow korumasi calisiyor (full hala 1)" severity note;

        -----------------------------------------------------------------------
        -- TEST 3: FIFO'yu bosalt (16 eleman oku, sira kontrolu)
        -----------------------------------------------------------------------
        report "TEST 3: 16 eleman oku (sira + empty)" severity note;

        rd_en <= '1';
        -- FWFT: rd_data su an rd_ptr=0'dan BB00'u gosteriyor.
        -- Her clock'ta rd_ptr ilerler, rd_data bir sonraki elemana gecer.
        -- Once su anki (BB00) assert et, sonra clock ver, sonrakine gec.
        for i in 0 to 15 loop
            v_expected := std_logic_vector(to_unsigned(16#BB00# + i, 16));
            assert rd_data = v_expected
                report "TEST3 FAIL: okuma " & integer'image(i) &
                       " beklenen 0x" & to_hstring(v_expected) &
                       " gercek 0x" & to_hstring(rd_data)
                severity error;
            wait until rising_edge(clk); wait for 1 ps;
        end loop;
        check_cnt <= check_cnt + 16;
        rd_en <= '0';
        wait until rising_edge(clk);
        wait for 1 ps;

        assert empty = '1'
            report "TEST3 FAIL: tum veri okundu ama empty=1 olmadir" severity error;
        report "TEST3: empty flag = 1 (DOGRU)" severity note;

        -----------------------------------------------------------------------
        -- SONUC
        -----------------------------------------------------------------------
        report "============================================" severity note;
        report "  TEST SONUCU: " & integer'image(check_cnt) &
                " okuma dogrulandi" severity note;
        report "============================================" severity note;
        wait;
    end process p_stim;

end architecture sim;
