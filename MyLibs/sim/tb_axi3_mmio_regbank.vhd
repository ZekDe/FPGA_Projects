-------------------------------------------------------------------------------
-- tb_axi3_mmio_regbank.vhd
-- Self-checking unit test for the reusable AXI3 MMIO register bank.
-- It deliberately sends W before AW once: AXI write-address and write-data
-- channels are independent, so the slave must handle either arrival order.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.mmio_pkg.all;

entity tb_axi3_mmio_regbank is
end entity;

architecture sim of tb_axi3_mmio_regbank is
    constant C_PERIOD : time := 10 ns;
    constant C_COUNT  : positive := 4;

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';

    signal awid    : std_logic_vector(11 downto 0) := (others => '0');
    signal awaddr  : std_logic_vector(20 downto 0) := (others => '0');
    signal awlen   : std_logic_vector(3 downto 0) := (others => '0');
    signal awsize  : std_logic_vector(2 downto 0) := "010";
    signal awburst : std_logic_vector(1 downto 0) := "01";
    signal awlock  : std_logic_vector(1 downto 0) := (others => '0');
    signal awcache : std_logic_vector(3 downto 0) := (others => '0');
    signal awprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal awvalid : std_logic := '0';
    signal awready : std_logic;

    signal wid     : std_logic_vector(11 downto 0) := (others => '0');
    signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb   : std_logic_vector(3 downto 0) := (others => '0');
    signal wlast   : std_logic := '1';
    signal wvalid  : std_logic := '0';
    signal wready  : std_logic;

    signal bid     : std_logic_vector(11 downto 0);
    signal bresp   : std_logic_vector(1 downto 0);
    signal bvalid  : std_logic;
    signal bready  : std_logic := '1';

    signal arid    : std_logic_vector(11 downto 0) := (others => '0');
    signal araddr  : std_logic_vector(20 downto 0) := (others => '0');
    signal arlen   : std_logic_vector(3 downto 0) := (others => '0');
    signal arsize  : std_logic_vector(2 downto 0) := "010";
    signal arburst : std_logic_vector(1 downto 0) := "01";
    signal arlock  : std_logic_vector(1 downto 0) := (others => '0');
    signal arcache : std_logic_vector(3 downto 0) := (others => '0');
    signal arprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal arvalid : std_logic := '0';
    signal arready : std_logic;

    signal rid     : std_logic_vector(11 downto 0);
    signal rdata   : std_logic_vector(31 downto 0);
    signal rresp   : std_logic_vector(1 downto 0);
    signal rlast   : std_logic;
    signal rvalid  : std_logic;
    signal rready  : std_logic := '1';

    signal write_mask  : t_mmio_word_array(0 to C_COUNT - 1) := (
        0 => (others => '1'),
        1 => (others => '1'),
        2 => (others => '0'),
        3 => (others => '1')
    );
    signal override_data : t_mmio_word_array(0 to C_COUNT - 1) := (others => (others => '0'));
    signal override_mask : t_mmio_word_array(0 to C_COUNT - 1) := (others => (others => '0'));
    signal regs          : t_mmio_word_array(0 to C_COUNT - 1);
    signal wr_pulse      : std_logic_vector(C_COUNT - 1 downto 0);
    signal wr_data       : t_mmio_word_array(0 to C_COUNT - 1);
    signal wr_strb       : std_logic_vector(C_COUNT * 4 - 1 downto 0);
begin
    clk <= not clk after C_PERIOD / 2;

    dut : entity work.axi3_mmio_regbank
        generic map (
            G_REG_COUNT => C_COUNT,
            G_RESET_VALUES => (
                0 => x"00000000",
                1 => x"11223344",
                2 => x"DEADBEEF",
                3 => x"00000000"
            )
        )
        port map (
            clk => clk, rst_n => rst_n,
            s_axi_awid => awid, s_axi_awaddr => awaddr, s_axi_awlen => awlen,
            s_axi_awsize => awsize, s_axi_awburst => awburst, s_axi_awlock => awlock,
            s_axi_awcache => awcache, s_axi_awprot => awprot,
            s_axi_awvalid => awvalid, s_axi_awready => awready,
            s_axi_wid => wid, s_axi_wdata => wdata, s_axi_wstrb => wstrb,
            s_axi_wlast => wlast, s_axi_wvalid => wvalid, s_axi_wready => wready,
            s_axi_bid => bid, s_axi_bresp => bresp, s_axi_bvalid => bvalid,
            s_axi_bready => bready,
            s_axi_arid => arid, s_axi_araddr => araddr, s_axi_arlen => arlen,
            s_axi_arsize => arsize, s_axi_arburst => arburst, s_axi_arlock => arlock,
            s_axi_arcache => arcache, s_axi_arprot => arprot,
            s_axi_arvalid => arvalid, s_axi_arready => arready,
            s_axi_rid => rid, s_axi_rdata => rdata, s_axi_rresp => rresp,
            s_axi_rlast => rlast, s_axi_rvalid => rvalid, s_axi_rready => rready,
            reg_write_mask_i => write_mask,
            reg_read_override_i => override_data,
            reg_read_override_mask_i => override_mask,
            regs_o => regs, wr_pulse_o => wr_pulse, wr_data_o => wr_data,
            wr_strb_o => wr_strb
        );

    p_stimulus : process
        procedure send_w_first(
            constant addr : std_logic_vector(20 downto 0);
            constant id   : std_logic_vector(11 downto 0);
            constant data : std_logic_vector(31 downto 0);
            constant strb : std_logic_vector(3 downto 0)
        ) is
        begin
            wid <= id; wdata <= data; wstrb <= strb; wlast <= '1'; wvalid <= '1';
            wait until rising_edge(clk) and wready = '1';
            wvalid <= '0';
            awid <= id; awaddr <= addr; awlen <= "0000"; awsize <= "010"; awvalid <= '1';
            wait until rising_edge(clk) and awready = '1';
            awvalid <= '0';
            wait until bvalid = '1';
            assert bresp = "00" report "write must receive OKAY" severity error;
            assert bid = id report "write response ID mismatch" severity error;
            wait until rising_edge(clk);
        end procedure;

        procedure read_word(
            constant addr : std_logic_vector(20 downto 0);
            constant id   : std_logic_vector(11 downto 0);
            constant len  : std_logic_vector(3 downto 0);
            constant expected_resp : std_logic_vector(1 downto 0);
            constant expected_data : std_logic_vector(31 downto 0)
        ) is
        begin
            arid <= id; araddr <= addr; arlen <= len; arsize <= "010"; arvalid <= '1';
            wait until rising_edge(clk) and arready = '1';
            arvalid <= '0';
            wait until rvalid = '1';
            assert rresp = expected_resp report "read response mismatch" severity error;
            assert rid = id report "read response ID mismatch" severity error;
            assert rlast = '1' report "single-beat read must assert RLAST" severity error;
            assert rdata = expected_data report "read data mismatch" severity error;
            wait until rising_edge(clk);
        end procedure;
    begin
        wait for 3 * C_PERIOD;
        rst_n <= '1';
        wait until rising_edge(clk);

        report "TEST 1: reset readback" severity note;
        read_word(std_logic_vector(to_unsigned(4, 21)), x"001", "0000", "00", x"11223344");

        report "TEST 2: W then AW, partial byte write" severity note;
        send_w_first(std_logic_vector(to_unsigned(4, 21)), x"052", x"AA55CC33", "0101");
        read_word(std_logic_vector(to_unsigned(4, 21)), x"052", "0000", "00", x"11553333");

        report "TEST 3: read-only mask prevents storage change" severity note;
        send_w_first(std_logic_vector(to_unsigned(8, 21)), x"123", x"00000000", "1111");
        read_word(std_logic_vector(to_unsigned(8, 21)), x"123", "0000", "00", x"DEADBEEF");

        report "TEST 4: burst request is explicitly rejected" severity note;
        read_word((others => '0'), x"055", "0001", "10", x"00000000");

        report "AXI3 MMIO REGBANK TEST PASSED" severity note;
        wait;
    end process;
end architecture sim;
