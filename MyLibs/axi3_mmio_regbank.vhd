-------------------------------------------------------------------------------
-- axi3_mmio_regbank.vhd
--
-- Reusable AXI3 memory-mapped register bank.
--
-- Design scope (intentional v1 boundary):
--   * 32-bit word accesses only (AxSIZE = 2).
--   * Single-beat accesses only (AxLEN = 0, WLAST = 1).
--   * One outstanding read and one outstanding write at a time.
--   * AXI3 IDs are captured and returned unchanged.
--
-- This is exactly the useful subset for control/status MMIO peripherals.
-- A burst request is not silently misinterpreted: it receives SLVERR.
--
-- Application-side register model:
--   regs_o               : software-writable storage, visible to FPGA logic.
--   reg_write_mask_i     : one bit means software may change that bit.
--   reg_read_override_*  : FPGA status bits that replace stored readback bits.
--   wr_pulse_o(i)        : one clk pulse after a valid write to register i.
--   wr_data_o/wr_strb_o  : original write payload for W1C/command semantics.
--
-- Every register occupies four bytes: register i is at byte offset 4*i.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.mmio_pkg.all;

entity axi3_mmio_regbank is
    generic (
        G_REG_COUNT : positive := 16;
        G_RESET_VALUES : t_mmio_word_array(0 to G_REG_COUNT - 1) := (others => (others => '0'))
    );
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;

        -- AXI3 write-address channel
        s_axi_awid    : in  std_logic_vector(11 downto 0);
        s_axi_awaddr  : in  std_logic_vector(20 downto 0);
        s_axi_awlen   : in  std_logic_vector(3 downto 0);
        s_axi_awsize  : in  std_logic_vector(2 downto 0);
        s_axi_awburst : in  std_logic_vector(1 downto 0);
        s_axi_awlock  : in  std_logic_vector(1 downto 0);
        s_axi_awcache : in  std_logic_vector(3 downto 0);
        s_axi_awprot  : in  std_logic_vector(2 downto 0);
        s_axi_awvalid : in  std_logic;
        s_axi_awready : out std_logic;

        -- AXI3 write-data channel
        s_axi_wid     : in  std_logic_vector(11 downto 0);
        s_axi_wdata   : in  std_logic_vector(31 downto 0);
        s_axi_wstrb   : in  std_logic_vector(3 downto 0);
        s_axi_wlast   : in  std_logic;
        s_axi_wvalid  : in  std_logic;
        s_axi_wready  : out std_logic;

        -- AXI3 write-response channel
        s_axi_bid     : out std_logic_vector(11 downto 0);
        s_axi_bresp   : out std_logic_vector(1 downto 0);
        s_axi_bvalid  : out std_logic;
        s_axi_bready  : in  std_logic;

        -- AXI3 read-address channel
        s_axi_arid    : in  std_logic_vector(11 downto 0);
        s_axi_araddr  : in  std_logic_vector(20 downto 0);
        s_axi_arlen   : in  std_logic_vector(3 downto 0);
        s_axi_arsize  : in  std_logic_vector(2 downto 0);
        s_axi_arburst : in  std_logic_vector(1 downto 0);
        s_axi_arlock  : in  std_logic_vector(1 downto 0);
        s_axi_arcache : in  std_logic_vector(3 downto 0);
        s_axi_arprot  : in  std_logic_vector(2 downto 0);
        s_axi_arvalid : in  std_logic;
        s_axi_arready : out std_logic;

        -- AXI3 read-data channel
        s_axi_rid     : out std_logic_vector(11 downto 0);
        s_axi_rdata   : out std_logic_vector(31 downto 0);
        s_axi_rresp   : out std_logic_vector(1 downto 0);
        s_axi_rlast   : out std_logic;
        s_axi_rvalid  : out std_logic;
        s_axi_rready  : in  std_logic;

        -- Protocol-independent application interface
        reg_write_mask_i        : in  t_mmio_word_array(0 to G_REG_COUNT - 1);
        reg_read_override_i     : in  t_mmio_word_array(0 to G_REG_COUNT - 1);
        reg_read_override_mask_i: in  t_mmio_word_array(0 to G_REG_COUNT - 1);
        regs_o                  : out t_mmio_word_array(0 to G_REG_COUNT - 1);
        wr_pulse_o              : out std_logic_vector(G_REG_COUNT - 1 downto 0);
        wr_data_o               : out t_mmio_word_array(0 to G_REG_COUNT - 1);
        wr_strb_o               : out std_logic_vector(G_REG_COUNT * 4 - 1 downto 0)
    );
end entity axi3_mmio_regbank;

architecture rtl of axi3_mmio_regbank is
    constant C_RESP_OKAY   : std_logic_vector(1 downto 0) := "00";
    constant C_RESP_SLVERR : std_logic_vector(1 downto 0) := "10";

    signal regs_q          : t_mmio_word_array(0 to G_REG_COUNT - 1);
    signal wr_data_q       : t_mmio_word_array(0 to G_REG_COUNT - 1);
    signal wr_pulse_q      : std_logic_vector(G_REG_COUNT - 1 downto 0) := (others => '0');
    signal wr_strb_q       : std_logic_vector(G_REG_COUNT * 4 - 1 downto 0) := (others => '0');

    signal aw_seen         : std_logic := '0';
    signal awid_q          : std_logic_vector(11 downto 0) := (others => '0');
    signal awaddr_q        : std_logic_vector(20 downto 0) := (others => '0');
    signal awlen_q         : std_logic_vector(3 downto 0) := (others => '0');
    signal awsize_q        : std_logic_vector(2 downto 0) := (others => '0');

    signal w_seen          : std_logic := '0';
    signal wid_q           : std_logic_vector(11 downto 0) := (others => '0');
    signal wdata_q         : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb_q         : std_logic_vector(3 downto 0) := (others => '0');
    signal wlast_q         : std_logic := '0';

    signal bvalid_q        : std_logic := '0';
    signal bid_q           : std_logic_vector(11 downto 0) := (others => '0');
    signal bresp_q         : std_logic_vector(1 downto 0) := C_RESP_OKAY;

    signal rvalid_q        : std_logic := '0';
    signal rid_q           : std_logic_vector(11 downto 0) := (others => '0');
    signal rdata_q         : std_logic_vector(31 downto 0) := (others => '0');
    signal rresp_q         : std_logic_vector(1 downto 0) := C_RESP_OKAY;

    signal awready_i       : std_logic;
    signal wready_i        : std_logic;
    signal arready_i       : std_logic;

    function is_word_request(
        len  : std_logic_vector(3 downto 0);
        size : std_logic_vector(2 downto 0);
        addr : std_logic_vector(20 downto 0)
    ) return boolean is
    begin
        return (len = "0000") and (size = "010") and (addr(1 downto 0) = "00");
    end function;

    function read_word(
        index : natural;
        stored : t_mmio_word_array;
        override_data : t_mmio_word_array;
        override_mask : t_mmio_word_array
    ) return t_mmio_word is
    begin
        return (stored(index) and not override_mask(index)) or
               (override_data(index) and override_mask(index));
    end function;
begin
    -- READY is high only while the corresponding one-entry input buffer is free.
    -- AW and W are deliberately independent: either may arrive first.
    awready_i <= not aw_seen and not bvalid_q;
    wready_i  <= not w_seen  and not bvalid_q;
    arready_i <= not rvalid_q;
    s_axi_awready <= awready_i;
    s_axi_wready  <= wready_i;
    s_axi_arready <= arready_i;

    s_axi_bid    <= bid_q;
    s_axi_bresp  <= bresp_q;
    s_axi_bvalid <= bvalid_q;

    s_axi_rid    <= rid_q;
    s_axi_rdata  <= rdata_q;
    s_axi_rresp  <= rresp_q;
    s_axi_rlast  <= '1';       -- only single-beat reads are accepted
    s_axi_rvalid <= rvalid_q;

    regs_o     <= regs_q;
    wr_data_o  <= wr_data_q;
    wr_pulse_o <= wr_pulse_q;
    wr_strb_o  <= wr_strb_q;

    p_write : process(clk, rst_n)
        variable v_index : natural;
        variable v_new_word : t_mmio_word;
        variable v_byte : natural;
        variable v_write_ok : boolean;
    begin
        if rst_n = '0' then
            for i in 0 to G_REG_COUNT - 1 loop
                regs_q(i)    <= G_RESET_VALUES(i);
                wr_data_q(i) <= (others => '0');
            end loop;
            wr_pulse_q <= (others => '0');
            wr_strb_q  <= (others => '0');
            aw_seen    <= '0';
            w_seen     <= '0';
            bvalid_q   <= '0';
            bid_q      <= (others => '0');
            bresp_q    <= C_RESP_OKAY;
        elsif rising_edge(clk) then
            wr_pulse_q <= (others => '0');

            if (s_axi_awvalid = '1') and (awready_i = '1') then
                aw_seen  <= '1';
                awid_q   <= s_axi_awid;
                awaddr_q <= s_axi_awaddr;
                awlen_q  <= s_axi_awlen;
                awsize_q <= s_axi_awsize;
            end if;

            if (s_axi_wvalid = '1') and (wready_i = '1') then
                w_seen  <= '1';
                wid_q   <= s_axi_wid;
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                wlast_q <= s_axi_wlast;
            end if;

            if (bvalid_q = '1') and (s_axi_bready = '1') then
                bvalid_q <= '0';
                aw_seen  <= '0';
                w_seen   <= '0';
            elsif (bvalid_q = '0') and (aw_seen = '1') and (w_seen = '1') then
                -- Both independent write channels have been captured.  Now
                -- validate the MMIO subset before changing any register.
                bid_q <= awid_q;
                v_write_ok := is_word_request(awlen_q, awsize_q, awaddr_q) and
                              (wlast_q = '1') and (wid_q = awid_q);
                v_index := to_integer(unsigned(awaddr_q(20 downto 2)));

                if v_write_ok and (v_index < G_REG_COUNT) then
                    v_new_word := regs_q(v_index);
                    for byte_i in 0 to 3 loop
                        if wstrb_q(byte_i) = '1' then
                            for bit_i in 0 to 7 loop
                                v_byte := byte_i * 8 + bit_i;
                                if reg_write_mask_i(v_index)(v_byte) = '1' then
                                    v_new_word(v_byte) := wdata_q(v_byte);
                                end if;
                            end loop;
                        end if;
                    end loop;
                    regs_q(v_index) <= v_new_word;
                    wr_data_q(v_index) <= wdata_q;
                    wr_pulse_q(v_index) <= '1';
                    wr_strb_q(v_index * 4 + 3 downto v_index * 4) <= wstrb_q;
                    bresp_q <= C_RESP_OKAY;
                else
                    bresp_q <= C_RESP_SLVERR;
                end if;
                bvalid_q <= '1';
            end if;
        end if;
    end process p_write;

    p_read : process(clk, rst_n)
        variable v_index : natural;
    begin
        if rst_n = '0' then
            rvalid_q <= '0';
            rid_q    <= (others => '0');
            rdata_q  <= (others => '0');
            rresp_q  <= C_RESP_OKAY;
        elsif rising_edge(clk) then
            if (rvalid_q = '1') and (s_axi_rready = '1') then
                rvalid_q <= '0';
            elsif (rvalid_q = '0') and (s_axi_arvalid = '1') and (arready_i = '1') then
                rid_q   <= s_axi_arid;
                v_index := to_integer(unsigned(s_axi_araddr(20 downto 2)));

                if is_word_request(s_axi_arlen, s_axi_arsize, s_axi_araddr) and
                   (v_index < G_REG_COUNT) then
                    rdata_q <= read_word(v_index, regs_q, reg_read_override_i,
                                         reg_read_override_mask_i);
                    rresp_q <= C_RESP_OKAY;
                else
                    rdata_q <= (others => '0');
                    rresp_q <= C_RESP_SLVERR;
                end if;
                rvalid_q <= '1';
            end if;
        end if;
    end process p_read;
end architecture rtl;
