--------------------------------------------------------------------------------
--  button_module.vhd  -- iki butonun mantik alt-sistemi (BOARD-BAGIMSIZ)
--
--  Bu kutu SADECE mantik: sync -> ton -> edge, iki buton icin, DUZ (senin C'ndeki
--  gibi). Board'a dair hicbir sey bilmez -> pin, polarite (aktif-dusuk), reset
--  kaynagi hepsi ust seviyededir (system_top). Bu yuzden:
--    - 'systick'i URETMEZ, disaridan PORT ile alir (system_top'ta bir kez uretilir)
--    - butonu 'basili = 1' (aktif-yuksek) kabul eder; 'not KEY' cevrimi ustte yapilir
--  Sonuc: bu modul her board'a tasinabilir, tek basina test edilebilir.
--
--  Tum cikislar (btn_out ve btn_out_pulse) PORT olarak disari verilir -> ust
--  seviyeden hepsine ayri ayri erisirsin (birini seviye, digerini tetik olarak).
--
--  C ESLEMESI:
--    btn1_out       = TON(&ton1, btn1_raw, systick, PRESET1)  -> u_ton1
--    btn1_out_pulse = edgeDetection(&ed1, btn1_out)           -> u_ed1
--    btn2_out       = TON(&ton2, btn2_raw, systick, PRESET2)  -> u_ton2
--    btn2_out_pulse = edgeDetection(&ed2, btn2_out)           -> u_ed2
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity button_module is
    generic (
        G_WIDTH     : positive := 32;
        G_STAGES    : positive := 2;     -- senkronizer derinligi
        G_PRESET1_MS : natural := 100;   -- buton1 timeout (ms)
        G_PRESET2_MS : natural := 150    -- buton2 timeout (ms)
    );
    port (
        clk            : in  std_logic;
        rst_n          : in  std_logic;
        systick        : in  unsigned(G_WIDTH - 1 downto 0);  -- DISARIDAN gelir
        btn1_raw       : in  std_logic;                       -- basili = 1
        btn2_raw       : in  std_logic;
        btn1_out       : out std_logic;                       -- TON1 (seviye)
        btn1_out_pulse : out std_logic;                       -- ED1  (tek-tick)
        btn2_out       : out std_logic;                       -- TON2 (seviye)
        btn2_out_pulse : out std_logic                        -- ED2  (tek-tick)
    );
end entity button_module;

architecture rtl of button_module is
    signal btn1_sync : std_logic;
    signal btn2_sync : std_logic;
    signal btn1_lvl  : std_logic;   -- TON1 cikisi (ic; hem port hem ED girisi)
    signal btn2_lvl  : std_logic;
begin

    ----------------------------------------------------------------------------
    -- BUTON 1 zinciri
    ----------------------------------------------------------------------------
    u_sync1 : entity work.synchronizer
        generic map ( G_STAGES => G_STAGES, G_RST_VAL => '0' )
        port map    ( clk => clk, rst_n => rst_n, async_in => btn1_raw, sync_out => btn1_sync );

    u_ton1 : entity work.ton
        generic map ( G_WIDTH => G_WIDTH )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            in_sig      => btn1_sync,
            now_ms      => systick,
            preset_time => to_unsigned(G_PRESET1_MS, G_WIDTH),
            retval      => btn1_lvl,
            since       => open
        );

    u_ed1 : entity work.edge_detector
        port map ( clk => clk, rst_n => rst_n, val => btn1_lvl, retval => btn1_out_pulse );

    ----------------------------------------------------------------------------
    -- BUTON 2 zinciri
    ----------------------------------------------------------------------------
    u_sync2 : entity work.synchronizer
        generic map ( G_STAGES => G_STAGES, G_RST_VAL => '0' )
        port map    ( clk => clk, rst_n => rst_n, async_in => btn2_raw, sync_out => btn2_sync );

    u_ton2 : entity work.ton
        generic map ( G_WIDTH => G_WIDTH )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            in_sig      => btn2_sync,
            now_ms      => systick,
            preset_time => to_unsigned(G_PRESET2_MS, G_WIDTH),
            retval      => btn2_lvl,
            since       => open
        );

    u_ed2 : entity work.edge_detector
        port map ( clk => clk, rst_n => rst_n, val => btn2_lvl, retval => btn2_out_pulse );

    -- TON seviyelerini de disari ver
    btn1_out <= btn1_lvl;
    btn2_out <= btn2_lvl;

end architecture rtl;
