--------------------------------------------------------------------------------
--  tb_fifo_async.vhd  -- Asenkron FIFO testbench (minimal, robust)
--
--  AMAC:
--    fifo_async'in CALISTIGINI kanitlamak. Iki iliskisiz clock domain.
--    Write-then-read yaklasimi: once yaz, bekle, sonra oku. Paralel stimulus YOK,
--    deadlock olasiligi YOK.
--
--  TESTLER:
--    1) 3 eleman yaz -> bekle -> 3 eleman oku (sira + veri bütünlügü)
--    2) FIFO'yu doldur (16) -> bekle -> 16 eleman oku (full/empty flag'leri)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_fifo_async is
end entity tb_fifo_async;

architecture sim of tb_fifo_async is

    constant C_WR_PERIOD : time := 10 ns;
    constant C_RD_PERIOD : time := 14 ns;

    signal wr_clk  : std_logic := '0';
    signal rd_clk  : std_logic := '0';
    signal rst_n   : std_logic := '0';

    signal wr_en   : std_logic := '0';
    signal wr_data : std_logic_vector(7 downto 0) := (others => '0');
    signal full    : std_logic;

    signal rd_en   : std_logic := '0';
    signal rd_data : std_logic_vector(7 downto 0);
    signal empty   : std_logic;

    signal check_cnt : integer := 0;

begin

    wr_clk <= not wr_clk after C_WR_PERIOD / 2;
    rd_clk <= not rd_clk after C_RD_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    u_dut : entity work.fifo_async
        generic map ( G_WIDTH => 8, G_DEPTH => 16 )
        port map (
            rst_n   => rst_n,
            wr_clk  => wr_clk,
            wr_en   => wr_en,
            wr_data => wr_data,
            full    => full,
            rd_clk  => rd_clk,
            rd_en   => rd_en,
            rd_data => rd_data,
            empty   => empty
        );

    ----------------------------------------------------------------------------
    -- TEK STIMULUS PROCESS (write, bekle, read - sirayla, deadlock-free)
    ----------------------------------------------------------------------------
    p_stim : process
        variable v_expected : std_logic_vector(7 downto 0);
    begin
        -----------------------------------------------------------------------
        -- RESET
        -----------------------------------------------------------------------
        rst_n <= '0';
        wr_en <= '0';
        rd_en <= '0';
        wait for 50 ns;
        rst_n <= '1';
        wait for 100 ns;

        -----------------------------------------------------------------------
        -- TEST 1: 3 eleman yaz (wr_clk domain)
        -----------------------------------------------------------------------
        report "TEST 1: 3 eleman yaziliyor (0x10,0x11,0x12)" severity note;
        for i in 0 to 2 loop
            -- wr_clk rising edge bekle, data koy, wr_en pulse
            wait until rising_edge(wr_clk);
            wr_data <= std_logic_vector(to_unsigned(16#10# + i, 8));
            wr_en   <= '1';
            wait until rising_edge(wr_clk);
            wr_en   <= '0';
        end loop;

        -- Write domain'in gray pointer'inin read domain'e gecmesini bekle
        -- (2-FF CDC gecikmesi). 5 rd_clk cycle yeterli.
        for i in 0 to 5 loop
            wait until rising_edge(rd_clk);
        end loop;

        -----------------------------------------------------------------------
        -- TEST 1 oku: 3 elemani sirayla oku (rd_clk domain)
        -----------------------------------------------------------------------
        report "TEST 1: okuma basliyor" severity note;
        assert empty = '0' report "TEST1: empty=0 olmaliydi (veri yazildi)" severity error;

        for i in 0 to 2 loop
            v_expected := std_logic_vector(to_unsigned(16#10# + i, 8));
            -- FWFT: rd_data rd_ptr'nin gosterdigi elemani verir.
            -- rd_en=1 yap, bir clock bekle (rd_ptr ilerler), dogrula.
            wait until rising_edge(rd_clk);
            rd_en <= '1';
            wait for 1 ps;   -- delta cycle
            assert rd_data = v_expected
                report "TEST1 FAIL: okuma " & integer'image(i) &
                       " beklenen 0x" & to_hstring(v_expected) &
                       " gercek 0x" & to_hstring(rd_data)
                severity error;
            check_cnt <= check_cnt + 1;
        end loop;
        wait until rising_edge(rd_clk);
        rd_en <= '0';

        -- empty settle bekle
        for i in 0 to 5 loop
            wait until rising_edge(rd_clk);
        end loop;
        assert empty = '1' report "TEST1: 3 okuma sonrasi empty=1 olmali" severity error;
        report "TEST 1 TAMAM: 3 okuma dogrulandi" severity note;

        -----------------------------------------------------------------------
        -- TEST 2: 16 eleman yaz (doldur)
        -----------------------------------------------------------------------
        report "TEST 2: 16 eleman yaziliyor (0x30..0x3F)" severity note;
        for i in 0 to 15 loop
            wait until rising_edge(wr_clk);
            wr_data <= std_logic_vector(to_unsigned(16#30# + i, 8));
            wr_en   <= '1';
            wait until rising_edge(wr_clk);
            wr_en   <= '0';
        end loop;

        -- CDC settle
        for i in 0 to 5 loop
            wait until rising_edge(rd_clk);
        end loop;

        -----------------------------------------------------------------------
        -- TEST 2 oku: 16 elemani oku
        -----------------------------------------------------------------------
        report "TEST 2: okuma basliyor (16 eleman)" severity note;
        for i in 0 to 15 loop
            v_expected := std_logic_vector(to_unsigned(16#30# + i, 8));
            wait until rising_edge(rd_clk);
            rd_en <= '1';
            wait for 1 ps;
            assert rd_data = v_expected
                report "TEST2 FAIL: okuma " & integer'image(i) &
                       " beklenen 0x" & to_hstring(v_expected) &
                       " gercek 0x" & to_hstring(rd_data)
                severity error;
            check_cnt <= check_cnt + 1;
        end loop;
        wait until rising_edge(rd_clk);
        rd_en <= '0';

        for i in 0 to 5 loop
            wait until rising_edge(rd_clk);
        end loop;
        assert empty = '1' report "TEST2: 16 okuma sonrasi empty=1 olmali" severity error;
        report "TEST 2 TAMAM: 16 okuma dogrulandi" severity note;

        -----------------------------------------------------------------------
        -- SONUC
        -----------------------------------------------------------------------
        report "==========================================" severity note;
        report "  TUM TESTLER BITTI: " & integer'image(check_cnt) &
               " okuma dogrulandi (beklenen 19)" severity note;
        report "==========================================" severity note;
        wait;
    end process p_stim;

end architecture sim;
