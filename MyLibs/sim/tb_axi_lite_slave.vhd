--------------------------------------------------------------------------------
--  tb_axi_lite_slave.vhd  -- AXI-Lite Slave testbench (AXI Master modeli)
--
--  AMAC:
--    axi_lite_slave'i dogrula. Bir AXI Master davranisi taklit eder:
--      - 6 config register'ina farkli degerler YAZ
--      - 2 status register'ini OKU
--      - Yazdigi degerleri geri okuyup dogrular (read-after-write)
--
--  TESTLER:
--    TEST 1: DEBOUNCE_MS (0x00) = 100 yaz, geri oku (100 mu?)
--    TEST 2: LONG_PRESS_MS (0x04) = 2000 yaz, geri oku
--    TEST 3: Tüm config register'lara deger yaz, hepsini oku
--    TEST 4: Status register'larini oku (FIFO_STATUS)
--
--  AXI MASTER PROSEDÜRLERI (testbench helper):
--    axi_write(addr, data) - 5 kanalli write transaction
--    axi_read(addr) -> data - 2 kanalli read transaction
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_axi_lite_slave is
end entity tb_axi_lite_slave;

architecture sim of tb_axi_lite_slave is

    constant C_PERIOD : time := 10 ns;

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';

    -- AXI-Lite bus sinyalleri
    signal awvalid, awready : std_logic := '0';
    signal awaddr : std_logic_vector(31 downto 0) := (others => '0');
    signal awprot  : std_logic_vector(2 downto 0) := "000";

    signal wvalid, wready : std_logic := '0';
    signal wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb  : std_logic_vector(3 downto 0) := "1111";

    signal bvalid, bready : std_logic := '0';
    signal bresp : std_logic_vector(1 downto 0) := "00";

    signal arvalid, arready : std_logic := '0';
    signal araddr : std_logic_vector(31 downto 0) := (others => '0');
    signal arprot  : std_logic_vector(2 downto 0) := "000";

    signal rvalid, rready : std_logic := '0';
    signal rdata : std_logic_vector(31 downto 0) := (others => '0');
    signal rresp : std_logic_vector(1 downto 0) := "00";

    -- Status input'lar (FPGA'den gelir, biz suruyoruz testbench'te)
    signal sts_button_status : std_logic_vector(31 downto 0) := x"000000AB";
    signal sts_fifo_status   : std_logic_vector(31 downto 0) := x"00000003";

    -- Read prosedurunden donen deger (signal, çünkü procedure delta cycle girer)
    signal read_result : std_logic_vector(31 downto 0) := (others => '0');

begin

    clk <= not clk after C_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    u_dut : entity work.axi_lite_slave
        port map (
            clk => clk, rst_n => rst_n,
            -- AW
            s_axi_awvalid => awvalid, s_axi_awready => awready,
            s_axi_awaddr  => awaddr,  s_axi_awprot  => awprot,
            -- W
            s_axi_wvalid  => wvalid,  s_axi_wready  => wready,
            s_axi_wdata   => wdata,   s_axi_wstrb   => wstrb,
            -- B
            s_axi_bvalid  => bvalid,  s_axi_bready  => bready,
            s_axi_bresp   => bresp,
            -- AR
            s_axi_arvalid => arvalid, s_axi_arready => arready,
            s_axi_araddr  => araddr,  s_axi_arprot  => arprot,
            -- R
            s_axi_rvalid  => rvalid,  s_axi_rready  => rready,
            s_axi_rdata   => rdata,   s_axi_rresp   => rresp,
            -- Register file
            reg_debounce_ms           => open,
            reg_long_press_ms         => open,
            reg_multi_click_window_ms => open,
            reg_repeat_start_ms       => open,
            reg_repeat_end_ms         => open,
            reg_repeat_ramp_ms        => open,
            sts_button_status_in      => sts_button_status,
            sts_fifo_status_in        => sts_fifo_status
        );

    ----------------------------------------------------------------------------
    -- AXI MASTER: write proseduru
    ----------------------------------------------------------------------------
    -- AXI write = AW + W + B
    -- Adres-önce modeli: once AW handshake, sonra W, sonra B.
    ----------------------------------------------------------------------------
    axi_write : process
        procedure do_write(addr : in std_logic_vector(31 downto 0);
                          data : in std_logic_vector(31 downto 0)) is
        begin
            -- AW kanali
            wait until rising_edge(clk);
            awaddr  <= addr;
            awvalid <= '1';
            -- AWREADY'yi bekle
            loop
                wait until rising_edge(clk);
                exit when awready = '1';
            end loop;
            awvalid <= '0';

            -- W kanali
            wdata  <= data;
            wvalid <= '1';
            loop
                wait until rising_edge(clk);
                exit when wready = '1';
            end loop;
            wvalid <= '0';

            -- B kanali (response)
            bready <= '1';
            loop
                wait until rising_edge(clk);
                exit when bvalid = '1';
            end loop;
            bready <= '0';
            assert bresp = "00"
                report "WRITE FAIL: BRESP not OKAY (" & integer'image(to_integer(unsigned(bresp))) & ")"
                severity error;
        end procedure;

        variable v_unused : integer;
    begin
        -- Reset sirasinda bekle
        wait until rst_n = '1';
        wait for 50 ns;

        -----------------------------------------------------------------------
        -- TEST 1: DEBOUNCE_MS = 100 yaz
        -----------------------------------------------------------------------
        report "TEST 1: 0x00 (DEBOUNCE_MS) = 100 yaziliyor" severity note;
        do_write(x"0000_0000", std_logic_vector(to_unsigned(100, 32)));
        report "TEST 1: write tamam" severity note;

        -----------------------------------------------------------------------
        -- TEST 2: LONG_PRESS_MS = 2000 yaz
        -----------------------------------------------------------------------
        report "TEST 2: 0x04 (LONG_PRESS_MS) = 2000 yaziliyor" severity note;
        do_write(x"0000_0004", std_logic_vector(to_unsigned(2000, 32)));
        report "TEST 2: write tamam" severity note;

        -----------------------------------------------------------------------
        -- TEST 3: Kalan config register'lari
        -----------------------------------------------------------------------
        report "TEST 3: diger config register'lari" severity note;
        do_write(x"0000_0008", std_logic_vector(to_unsigned(600, 32)));  -- MULTI_CLICK_WINDOW
        do_write(x"0000_000C", std_logic_vector(to_unsigned(800, 32)));  -- REPEAT_START
        do_write(x"0000_0010", std_logic_vector(to_unsigned(150, 32)));  -- REPEAT_END
        do_write(x"0000_0014", std_logic_vector(to_unsigned(2000, 32))); -- REPEAT_RAMP
        report "TEST 3: tum yazma islemleri tamam" severity note;

        wait for 100 ns;
        report "WRITE TESTLERI BITTI" severity note;
        wait;
    end process axi_write;

    ----------------------------------------------------------------------------
    -- AXI MASTER: read proseduru (write bittikten sonra calisir)
    ----------------------------------------------------------------------------
    axi_read : process
        -- do_read: AR+R handshake yapar, sonucu read_result signal'ine yazar.
        -- read_result signal oldugu icin delta cycle sonrasi guncellenir;
        -- bu yuzden do_read sonrasi "wait for 1 ps" beklenir, sonra assert.
        procedure do_read(addr : in std_logic_vector(31 downto 0)) is
        begin
            -- AR kanali
            wait until rising_edge(clk);
            araddr  <= addr;
            arvalid <= '1';
            loop
                wait until rising_edge(clk);
                exit when arready = '1';
            end loop;
            arvalid <= '0';

            -- R kanali
            rready <= '1';
            loop
                wait until rising_edge(clk);
                exit when rvalid = '1';
            end loop;
            read_result <= rdata;   -- signal'e yaz (delta cycle sonra生效)
            rready <= '0';
            assert rresp = "00"
                report "READ FAIL: RRESP not OKAY"
                severity error;
        end procedure;
    begin
        -- Write process'inin bitmesini bekle
        wait until rst_n = '1';
        wait for 1000 ns;  -- write'lar bitene kadar bekle

        -----------------------------------------------------------------------
        -- READ-BACK: yazilan degerleri oku ve dogrula
        -----------------------------------------------------------------------
        report "READ-BACK basliyor" severity note;

        do_read(x"0000_0000");
        wait for 1 ps;
        assert read_result = std_logic_vector(to_unsigned(100, 32))
            report "READ-BACK FAIL: 0x00 beklenen 100, gercek " & integer'image(to_integer(unsigned(read_result)))
            severity error;
        report "  0x00 DEBOUNCE_MS = 100 OK" severity note;

        do_read(x"0000_0004");
        wait for 1 ps;
        assert read_result = std_logic_vector(to_unsigned(2000, 32))
            report "READ-BACK FAIL: 0x04 beklenen 2000, gercek " & integer'image(to_integer(unsigned(read_result)))
            severity error;
        report "  0x04 LONG_PRESS_MS = 2000 OK" severity note;

        do_read(x"0000_0008");
        wait for 1 ps;
        assert read_result = std_logic_vector(to_unsigned(600, 32))
            report "READ-BACK FAIL: 0x08 beklenen 600, gercek " & integer'image(to_integer(unsigned(read_result)))
            severity error;
        report "  0x08 MULTI_CLICK_WINDOW_MS = 600 OK" severity note;

        do_read(x"0000_000C");
        wait for 1 ps;
        assert read_result = std_logic_vector(to_unsigned(800, 32))
            report "READ-BACK FAIL: 0x0C beklenen 800, gercek " & integer'image(to_integer(unsigned(read_result)))
            severity error;
        report "  0x0C REPEAT_START_MS = 800 OK" severity note;

        do_read(x"0000_0010");
        wait for 1 ps;
        assert read_result = std_logic_vector(to_unsigned(150, 32))
            report "READ-BACK FAIL: 0x10 beklenen 150, gercek " & integer'image(to_integer(unsigned(read_result)))
            severity error;
        report "  0x10 REPEAT_END_MS = 150 OK" severity note;

        do_read(x"0000_0014");
        wait for 1 ps;
        assert read_result = std_logic_vector(to_unsigned(2000, 32))
            report "READ-BACK FAIL: 0x14 beklenen 2000, gercek " & integer'image(to_integer(unsigned(read_result)))
            severity error;
        report "  0x14 REPEAT_RAMP_MS = 2000 OK" severity note;

        -----------------------------------------------------------------------
        -- STATUS register'lari oku
        -----------------------------------------------------------------------
        do_read(x"0000_0018");
        wait for 1 ps;
        assert read_result = x"000000AB"
            report "READ FAIL: 0x18 (BUTTON_STATUS) beklenen 0xAB, gercek 0x" & to_hstring(read_result)
            severity error;
        report "  0x18 BUTTON_STATUS = 0xAB OK" severity note;

        do_read(x"0000_001C");
        wait for 1 ps;
        assert read_result = x"00000003"
            report "READ FAIL: 0x1C (FIFO_STATUS) beklenen 0x03, gercek 0x" & to_hstring(read_result)
            severity error;
        report "  0x1C FIFO_STATUS = 0x03 OK" severity note;

        report "========================================" severity note;
        report "  TUM READ-BACK TESTLERI GECTI" severity note;
        report "========================================" severity note;
        wait;
    end process axi_read;

    ----------------------------------------------------------------------------
    -- RESET
    ----------------------------------------------------------------------------
    p_reset : process
    begin
        rst_n <= '0';
        wait for 50 ns;
        rst_n <= '1';
        wait;
    end process p_reset;

end architecture sim;
