-------------------------------------------------------------------------------
-- system_top.vhd
--
-- Board composition layer.  It does not implement AXI itself.
--
--   HPS pins + DDR3 pins
--           │
--           ▼
--      soc_system (Platform Designer generated HPS system)
--           │ AXI3 lightweight HPS-to-FPGA bridge
--           ▼
--      axi3_mmio_regbank (generic, reusable MyLibs module)
--           │ 16 x 32-bit registers
--           ▼
--      button_gesture (this project's application logic)
--
-- The generic register bank has no button-specific knowledge.  This top-level
-- assigns the first registers to this particular application:
--   0x00 debounce_ms               RW
--   0x04 long_press_ms             RW
--   0x08 multi_click_window_ms     RW
--   0x0C repeat_start_ms           RW
--   0x10 repeat_end_ms             RW
--   0x14 repeat_ramp_ms            RW
--   0x18 button status             RO (FPGA overrides readback)
--   0x1C event clear command       WO (write-one-to-clear status bits)
--   0x20..0x3C                     general-purpose RW registers for later use
--
-- Linux physical address basis: HPS lightweight bridge base + these offsets.
-- The bridge base is 0xFF200000 on Cyclone V; detailed Linux bring-up comes
-- after FPGA compilation/programming.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.mmio_pkg.all;

entity system_top is
    generic (
        G_CLK_HZ : positive := 50_000_000
    );
    port (
        -- FPGA board I/O
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(0 downto 0);
        SW       : in  std_logic_vector(0 downto 0);
        LED      : out std_logic_vector(7 downto 0);

        -- HPS DDR3 physical interface (names intentionally match the .qsf)
        HPS_DDR3_ADDR    : out   std_logic_vector(14 downto 0);
        HPS_DDR3_BA      : out   std_logic_vector(2 downto 0);
        HPS_DDR3_CK_P    : out   std_logic;
        HPS_DDR3_CK_N    : out   std_logic;
        HPS_DDR3_CKE     : out   std_logic;
        HPS_DDR3_CS_N    : out   std_logic;
        HPS_DDR3_RAS_N   : out   std_logic;
        HPS_DDR3_CAS_N   : out   std_logic;
        HPS_DDR3_WE_N    : out   std_logic;
        HPS_DDR3_RESET_N : out   std_logic;
        HPS_DDR3_DQ      : inout std_logic_vector(31 downto 0);
        HPS_DDR3_DQS_P   : inout std_logic_vector(3 downto 0);
        HPS_DDR3_DQS_N   : inout std_logic_vector(3 downto 0);
        HPS_DDR3_ODT     : out   std_logic;
        HPS_DDR3_DM      : out   std_logic_vector(3 downto 0);
        HPS_DDR3_RZQ     : in    std_logic;

        -- The HPS peripherals enabled in Platform Designer
        HPS_SD_CMD       : inout std_logic;
        HPS_SD_DATA      : inout std_logic_vector(3 downto 0);
        HPS_SD_CLK       : out   std_logic;
        HPS_UART_RX      : in    std_logic;
        HPS_UART_TX      : out   std_logic
    );
end entity system_top;

architecture rtl of system_top is
    constant C_REG_COUNT : positive := 16;
    constant C_WIDTH     : positive := 32;

    constant C_MMIO_RESET_VALUES : t_mmio_word_array(0 to C_REG_COUNT - 1) := (
        0      => x"00000014", -- debounce: 20 ms
        1      => x"000003E8", -- long press: 1000 ms
        2      => x"00000190", -- multi-click window: 400 ms
        3      => x"000001F4", -- repeat start: 500 ms
        4      => x"00000064", -- repeat end: 100 ms
        5      => x"000003E8", -- repeat ramp: 1000 ms
        others => (others => '0')
    );

    constant C_WRITE_MASKS : t_mmio_word_array(0 to C_REG_COUNT - 1) := (
        0 to 5 => (others => '1'), -- configuration
        6      => (others => '0'), -- status is read-only
        7      => (others => '0'), -- command register has pulse semantics
        others => (others => '1')  -- future general-purpose registers
    );

    -- HPS-generated AXI3 signals.  Direction is from HPS master to our slave.
    signal h2f_awid    : std_logic_vector(11 downto 0);
    signal h2f_awaddr  : std_logic_vector(20 downto 0);
    signal h2f_awlen   : std_logic_vector(3 downto 0);
    signal h2f_awsize  : std_logic_vector(2 downto 0);
    signal h2f_awburst : std_logic_vector(1 downto 0);
    signal h2f_awlock  : std_logic_vector(1 downto 0);
    signal h2f_awcache : std_logic_vector(3 downto 0);
    signal h2f_awprot  : std_logic_vector(2 downto 0);
    signal h2f_awvalid : std_logic;
    signal h2f_awready : std_logic;
    signal h2f_wid     : std_logic_vector(11 downto 0);
    signal h2f_wdata   : std_logic_vector(31 downto 0);
    signal h2f_wstrb   : std_logic_vector(3 downto 0);
    signal h2f_wlast   : std_logic;
    signal h2f_wvalid  : std_logic;
    signal h2f_wready  : std_logic;
    signal h2f_bid     : std_logic_vector(11 downto 0);
    signal h2f_bresp   : std_logic_vector(1 downto 0);
    signal h2f_bvalid  : std_logic;
    signal h2f_bready  : std_logic;
    signal h2f_arid    : std_logic_vector(11 downto 0);
    signal h2f_araddr  : std_logic_vector(20 downto 0);
    signal h2f_arlen   : std_logic_vector(3 downto 0);
    signal h2f_arsize  : std_logic_vector(2 downto 0);
    signal h2f_arburst : std_logic_vector(1 downto 0);
    signal h2f_arlock  : std_logic_vector(1 downto 0);
    signal h2f_arcache : std_logic_vector(3 downto 0);
    signal h2f_arprot  : std_logic_vector(2 downto 0);
    signal h2f_arvalid : std_logic;
    signal h2f_arready : std_logic;
    signal h2f_rid     : std_logic_vector(11 downto 0);
    signal h2f_rdata   : std_logic_vector(31 downto 0);
    signal h2f_rresp   : std_logic_vector(1 downto 0);
    signal h2f_rlast   : std_logic;
    signal h2f_rvalid  : std_logic;
    signal h2f_rready  : std_logic;

    signal h2f_reset_n : std_logic;
    signal bus_rst_n   : std_logic;
    signal app_rst_n   : std_logic;
    signal btn0_raw    : std_logic;
    signal systick     : unsigned(C_WIDTH - 1 downto 0);

    signal mmio_regs            : t_mmio_word_array(0 to C_REG_COUNT - 1);
    signal mmio_read_override   : t_mmio_word_array(0 to C_REG_COUNT - 1);
    signal mmio_read_mask       : t_mmio_word_array(0 to C_REG_COUNT - 1);
    signal mmio_wr_pulse        : std_logic_vector(C_REG_COUNT - 1 downto 0);
    signal mmio_wr_data         : t_mmio_word_array(0 to C_REG_COUNT - 1);
    signal mmio_wr_strb         : std_logic_vector(C_REG_COUNT * 4 - 1 downto 0);

    signal evt_single        : std_logic;
    signal evt_multi         : std_logic;
    signal evt_long          : std_logic;
    signal evt_long_repeat   : std_logic;
    signal evt_long_released : std_logic;
    signal click_count       : unsigned(7 downto 0);
    signal button_status_reg : std_logic_vector(31 downto 0) := (others => '0');
begin
    -- SW0 keeps the independent FPGA application resettable.  h2f_reset_n is
    -- additionally applied to the bus/register bank, because it belongs to the
    -- HPS-to-FPGA bridge reset domain.
    app_rst_n <= SW(0);
    bus_rst_n <= SW(0) and h2f_reset_n;
    btn0_raw <= not KEY(0); -- DE0-Nano KEY is active-low

    -- Platform Designer output: generated code, never handwritten.
    u_soc_system : entity work.soc_system
        port map (
            clk_clk                     => CLOCK_50,
            reset_reset_n               => SW(0),
            h2f_lw_axi_awid             => h2f_awid,
            h2f_lw_axi_awaddr           => h2f_awaddr,
            h2f_lw_axi_awlen            => h2f_awlen,
            h2f_lw_axi_awsize           => h2f_awsize,
            h2f_lw_axi_awburst          => h2f_awburst,
            h2f_lw_axi_awlock           => h2f_awlock,
            h2f_lw_axi_awcache          => h2f_awcache,
            h2f_lw_axi_awprot           => h2f_awprot,
            h2f_lw_axi_awvalid          => h2f_awvalid,
            h2f_lw_axi_awready          => h2f_awready,
            h2f_lw_axi_wid              => h2f_wid,
            h2f_lw_axi_wdata            => h2f_wdata,
            h2f_lw_axi_wstrb            => h2f_wstrb,
            h2f_lw_axi_wlast            => h2f_wlast,
            h2f_lw_axi_wvalid           => h2f_wvalid,
            h2f_lw_axi_wready           => h2f_wready,
            h2f_lw_axi_bid              => h2f_bid,
            h2f_lw_axi_bresp            => h2f_bresp,
            h2f_lw_axi_bvalid           => h2f_bvalid,
            h2f_lw_axi_bready           => h2f_bready,
            h2f_lw_axi_arid             => h2f_arid,
            h2f_lw_axi_araddr           => h2f_araddr,
            h2f_lw_axi_arlen            => h2f_arlen,
            h2f_lw_axi_arsize           => h2f_arsize,
            h2f_lw_axi_arburst          => h2f_arburst,
            h2f_lw_axi_arlock           => h2f_arlock,
            h2f_lw_axi_arcache          => h2f_arcache,
            h2f_lw_axi_arprot           => h2f_arprot,
            h2f_lw_axi_arvalid          => h2f_arvalid,
            h2f_lw_axi_arready          => h2f_arready,
            h2f_lw_axi_rid              => h2f_rid,
            h2f_lw_axi_rdata            => h2f_rdata,
            h2f_lw_axi_rresp            => h2f_rresp,
            h2f_lw_axi_rlast            => h2f_rlast,
            h2f_lw_axi_rvalid           => h2f_rvalid,
            h2f_lw_axi_rready           => h2f_rready,
            h2f_reset_reset_n           => h2f_reset_n,
            hps_io_hps_io_sdio_inst_CMD => HPS_SD_CMD,
            hps_io_hps_io_sdio_inst_D0  => HPS_SD_DATA(0),
            hps_io_hps_io_sdio_inst_D1  => HPS_SD_DATA(1),
            hps_io_hps_io_sdio_inst_CLK => HPS_SD_CLK,
            hps_io_hps_io_sdio_inst_D2  => HPS_SD_DATA(2),
            hps_io_hps_io_sdio_inst_D3  => HPS_SD_DATA(3),
            hps_io_hps_io_uart0_inst_RX => HPS_UART_RX,
            hps_io_hps_io_uart0_inst_TX => HPS_UART_TX,
            memory_mem_a                => HPS_DDR3_ADDR,
            memory_mem_ba               => HPS_DDR3_BA,
            memory_mem_ck               => HPS_DDR3_CK_P,
            memory_mem_ck_n             => HPS_DDR3_CK_N,
            memory_mem_cke              => HPS_DDR3_CKE,
            memory_mem_cs_n             => HPS_DDR3_CS_N,
            memory_mem_ras_n            => HPS_DDR3_RAS_N,
            memory_mem_cas_n            => HPS_DDR3_CAS_N,
            memory_mem_we_n             => HPS_DDR3_WE_N,
            memory_mem_reset_n          => HPS_DDR3_RESET_N,
            memory_mem_dq               => HPS_DDR3_DQ,
            memory_mem_dqs              => HPS_DDR3_DQS_P,
            memory_mem_dqs_n            => HPS_DDR3_DQS_N,
            memory_mem_odt              => HPS_DDR3_ODT,
            memory_mem_dm               => HPS_DDR3_DM,
            memory_oct_rzqin            => HPS_DDR3_RZQ
        );

    -- Generic AXI3-to-register-bank layer.  The AXI3 master is the HPS bridge;
    -- this module is its FPGA-side AXI3 slave.
    u_mmio : entity work.axi3_mmio_regbank
        generic map (
            G_REG_COUNT    => C_REG_COUNT,
            G_RESET_VALUES => C_MMIO_RESET_VALUES
        )
        port map (
            clk                      => CLOCK_50,
            rst_n                    => bus_rst_n,
            s_axi_awid               => h2f_awid,
            s_axi_awaddr             => h2f_awaddr,
            s_axi_awlen              => h2f_awlen,
            s_axi_awsize             => h2f_awsize,
            s_axi_awburst            => h2f_awburst,
            s_axi_awlock             => h2f_awlock,
            s_axi_awcache            => h2f_awcache,
            s_axi_awprot             => h2f_awprot,
            s_axi_awvalid            => h2f_awvalid,
            s_axi_awready            => h2f_awready,
            s_axi_wid                => h2f_wid,
            s_axi_wdata              => h2f_wdata,
            s_axi_wstrb              => h2f_wstrb,
            s_axi_wlast              => h2f_wlast,
            s_axi_wvalid             => h2f_wvalid,
            s_axi_wready             => h2f_wready,
            s_axi_bid                => h2f_bid,
            s_axi_bresp              => h2f_bresp,
            s_axi_bvalid             => h2f_bvalid,
            s_axi_bready             => h2f_bready,
            s_axi_arid               => h2f_arid,
            s_axi_araddr             => h2f_araddr,
            s_axi_arlen              => h2f_arlen,
            s_axi_arsize             => h2f_arsize,
            s_axi_arburst            => h2f_arburst,
            s_axi_arlock             => h2f_arlock,
            s_axi_arcache            => h2f_arcache,
            s_axi_arprot             => h2f_arprot,
            s_axi_arvalid            => h2f_arvalid,
            s_axi_arready            => h2f_arready,
            s_axi_rid                => h2f_rid,
            s_axi_rdata              => h2f_rdata,
            s_axi_rresp              => h2f_rresp,
            s_axi_rlast              => h2f_rlast,
            s_axi_rvalid             => h2f_rvalid,
            s_axi_rready             => h2f_rready,
            reg_write_mask_i         => C_WRITE_MASKS,
            reg_read_override_i      => mmio_read_override,
            reg_read_override_mask_i => mmio_read_mask,
            regs_o                   => mmio_regs,
            wr_pulse_o               => mmio_wr_pulse,
            wr_data_o                => mmio_wr_data,
            wr_strb_o                => mmio_wr_strb
        );

    -- Application-controlled status replaces the stored value only at 0x18.
    p_readback_sources : process(button_status_reg)
    begin
        for i in 0 to C_REG_COUNT - 1 loop
            mmio_read_override(i) <= (others => '0');
            mmio_read_mask(i)     <= (others => '0');
        end loop;
        mmio_read_override(6) <= button_status_reg;
        mmio_read_mask(6)     <= (others => '1');
    end process p_readback_sources;

    u_systick : entity work.time_base_ms
        generic map (G_CLK_HZ => G_CLK_HZ, G_WIDTH => C_WIDTH)
        port map (
            clk     => CLOCK_50,
            rst_n   => app_rst_n,
            tick_ms => open,
            now_ms  => systick
        );

    u_button_gesture : entity work.button_gesture
        port map (
            clk                   => CLOCK_50,
            rst_n                 => app_rst_n,
            now_ms                => systick,
            raw_pressed           => btn0_raw,
            require_repress       => '0',
            debounce_ms           => unsigned(mmio_regs(0)),
            long_press_ms         => unsigned(mmio_regs(1)),
            multi_click_window_ms => unsigned(mmio_regs(2)),
            repeat_start_ms       => unsigned(mmio_regs(3)),
            repeat_end_ms         => unsigned(mmio_regs(4)),
            repeat_ramp_ms        => unsigned(mmio_regs(5)),
            evt_single            => evt_single,
            evt_multi             => evt_multi,
            evt_long              => evt_long,
            evt_long_repeat       => evt_long_repeat,
            evt_long_released     => evt_long_released,
            click_count           => click_count
        );

    -- Status is sticky so a one-clock event is observable by Linux.  Software
    -- clears selected bits by writing ones to command register 0x1C.
    p_button_status : process(CLOCK_50, app_rst_n)
        variable v_status : std_logic_vector(31 downto 0);
    begin
        if app_rst_n = '0' then
            button_status_reg <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            v_status := button_status_reg;
            if mmio_wr_pulse(7) = '1' then
                v_status := v_status and not mmio_wr_data(7);
            end if;
            if evt_single        = '1' then v_status(0) := '1'; end if;
            if evt_multi         = '1' then v_status(1) := '1'; end if;
            if evt_long          = '1' then v_status(2) := '1'; end if;
            if evt_long_repeat   = '1' then v_status(3) := '1'; end if;
            if evt_long_released = '1' then v_status(4) := '1'; end if;
            v_status(10 downto 8) := std_logic_vector(click_count(2 downto 0));
            button_status_reg <= v_status;
        end if;
    end process p_button_status;

    -- FPGA-side visual debugger; it remains useful before Linux software exists.
    LED(0) <= evt_single;
    LED(1) <= evt_multi;
    LED(2) <= evt_long;
    LED(3) <= evt_long_repeat;
    LED(4) <= evt_long_released;
    LED(7 downto 5) <= (others => '0');
end architecture rtl;
