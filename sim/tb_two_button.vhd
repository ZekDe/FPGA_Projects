--------------------------------------------------------------------------------
--  tb_two_button.vhd  -- iki butonlu paralel debounce zinciri testbench'i
--
--  two_button_top'u G_CLK_HZ=1000 ile orneklyoruz -> 1 clock = 1 ms, sim hizli.
--  Preset'ler 100 ms / 150 ms olarak kalir (= 100 / 150 clock).
--
--  SENARYO:
--    1) reset
--    2) buton1'de BOUNCE (kisa titresim) -> btn1_on_pressed 0 kalmali
--    3) buton1 UZUN bas -> ~100 ms sonra btn1_on_pressed=1 + btn1_pulse
--    4) buton2 UZUN bas -> ~150 ms sonra btn2_on_pressed=1 + btn2_pulse
--    5) IKISI BIRDEN bas -> btn1 100 ms'de, btn2 150 ms'de tetiklenir
--       (ayni anda basildilar ama farkli preset -> farkli anda tetik: paralellik)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_two_button is
end entity tb_two_button;

architecture sim of tb_two_button is

    constant C_CLK_PERIOD : time     := 20 ns;
    constant C_SIM_CLK_HZ : positive := 1000;   -- 1 clock = 1 ms

    signal clk : std_logic := '0';
    signal KEY : std_logic_vector(1 downto 0) := "11";  -- aktif-dusuk: basili degil = 1
    signal SW  : std_logic_vector(0 downto 0) := "0";   -- SW0=0 -> reset aktif (baslangicta)
    signal LED : std_logic_vector(7 downto 0);

    -- kolaylik: butona bas/birak yardimci prosedurleri icin takma adlar
    -- (KEY aktif-dusuk oldugu icin bas = '0', birak = '1')

begin

    ----------------------------------------------------------------------------
    -- Saat
    ----------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- DUT (Device Under Test): gercek ust seviye, sim frekansiyla
    ----------------------------------------------------------------------------
    dut : entity work.two_button_top
        generic map (
            G_CLK_HZ     => C_SIM_CLK_HZ,
            G_PRESET1_MS => 100,
            G_PRESET2_MS => 150
        )
        port map (
            CLOCK_50 => clk,
            KEY      => KEY,
            SW       => SW,
            LED      => LED
        );

    ----------------------------------------------------------------------------
    -- Uyaran
    ----------------------------------------------------------------------------
    stim : process
    begin
        -- 1) RESET: SW0=0 tut, sonra birak (SW0=1 -> normal calisma)
        SW  <= "0";
        KEY <= "11";
        wait for 500 ns;
        SW <= "1";
        wait for 500 ns;

        -- 2) BUTON1 BOUNCE: kisa kisa bas-birak (< 100 ms surekli). Tetiklememeli.
        report "TEST 2: buton1 bounce - btn1_on_pressed 0 kalmali";
        KEY(0) <= '0'; wait for 800 ns;   -- 40 clock ~ 40 ms (preset 100'un altinda)
        KEY(0) <= '1'; wait for 400 ns;
        KEY(0) <= '0'; wait for 1000 ns;  -- 50 clock ~ 50 ms (yine kesintili)
        KEY(0) <= '1'; wait for 1000 ns;

        -- 3) BUTON1 UZUN BAS: 3 us (~150 clock > 100) -> ~100 ms sonra tetik
        report "TEST 3: buton1 uzun bas - ~100 ms sonra btn1_on_pressed=1 + btn1_pulse";
        KEY(0) <= '0'; wait for 3000 ns;
        KEY(0) <= '1'; wait for 1000 ns;

        -- 4) BUTON2 UZUN BAS: 4 us (~200 clock > 150) -> ~150 ms sonra tetik
        report "TEST 4: buton2 uzun bas - ~150 ms sonra btn2_on_pressed=1 + btn2_pulse";
        KEY(1) <= '0'; wait for 4000 ns;
        KEY(1) <= '1'; wait for 1000 ns;

        -- 5) IKISI BIRDEN: ayni anda bas, 4 us tut. btn1 100 ms'de, btn2 150 ms'de
        --    tetiklenir -> ayni girise ragmen farkli anlarda cikis (paralellik)
        report "TEST 5: ikisi birden - btn1 100ms, btn2 150ms (farkli anlarda tetik)";
        KEY(0) <= '0'; KEY(1) <= '0'; wait for 4000 ns;
        KEY(0) <= '1'; KEY(1) <= '1'; wait for 1000 ns;

        report "Simulasyon bitti." severity note;
        wait;
    end process stim;

end architecture sim;
