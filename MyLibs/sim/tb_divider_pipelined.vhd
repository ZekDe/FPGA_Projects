--------------------------------------------------------------------------------
--  tb_divider_pipelined.vhd  -- pipelined divider testbench
--
--  SENARYOLAR:
--    1) 13 / 3         = quotient 4,      remainder 1     (basit, kağıt örnek)
--    2) 1000000 / 7    = quotient 142857, remainder 1     (orta büyüklük)
--    3) 4294967295 / 1 = quotient 4294967295, remainder 0 (max dividend)
--    4) 100 / 0        = quotient 0,      remainder 0     (divide-by-zero)
--    5) Back-to-back   = 10/2, 20/4, 30/6 pespese (pipeline throughput test)
--
--  GÖZLEM:
--    - Transcript'te RESULT mesajları: valid pulse geldikçe sonuç yazılır
--    - Wave'de pipeline register'larının shift edişini görebilirsin
--    - Latency: start'tan 32 cycle sonra valid
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_divider_pipelined is
end entity tb_divider_pipelined;

architecture sim of tb_divider_pipelined is

    constant C_CLK_PERIOD : time     := 20 ns;
    constant C_WIDTH      : positive := 32;

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal start    : std_logic := '0';
    signal dividend : unsigned(C_WIDTH-1 downto 0) := (others => '0');
    signal divisor  : unsigned(C_WIDTH-1 downto 0) := (others => '0');

    signal valid     : std_logic;
    signal quotient  : unsigned(C_WIDTH-1 downto 0);
    signal remainder : unsigned(C_WIDTH-1 downto 0);

    -- Helper: kaç sonuç geldi say (gözlem)
    signal result_count : integer := 0;

begin

    ----------------------------------------------------------------------------
    -- Saat
    ----------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- DUT (Device Under Test)
    ----------------------------------------------------------------------------
    dut : entity work.divider_pipelined
        generic map ( G_WIDTH => C_WIDTH )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            start     => start,
            dividend  => dividend,
            divisor   => divisor,
            valid     => valid,
            quotient  => quotient,
            remainder => remainder
        );

    ----------------------------------------------------------------------------
    -- RESULT LOGGER: valid pulse geldikçe sonucu transcript'e yaz
    ----------------------------------------------------------------------------
    p_log : process(clk)
    begin
        if rising_edge(clk) then
            if valid = '1' then
                result_count <= result_count + 1;
                report "RESULT #" & integer'image(result_count + 1) &
                       "  Q=" & integer'image(to_integer(quotient)) &
                       "  R=" & integer'image(to_integer(remainder))
                    severity note;
            end if;
        end if;
    end process p_log;

    ----------------------------------------------------------------------------
    -- UYARAN (stimulus)
    ----------------------------------------------------------------------------
    stim : process
    begin
        -- RESET
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        --------------------------------------------------------------------
        -- TEST 1: 13 / 3 = 4 remainder 1
        --------------------------------------------------------------------
        report "TEST 1: 13 / 3";
        dividend <= to_unsigned(13, C_WIDTH);
        divisor  <= to_unsigned(3, C_WIDTH);
        start    <= '1';
        wait until rising_edge(clk);
        start    <= '0';
        -- valid 32 cycle sonra gelir + biraz marjın
        wait for (C_WIDTH + 2) * C_CLK_PERIOD;

        --------------------------------------------------------------------
        -- TEST 2: 1000000 / 7 = 142857 remainder 1
        --------------------------------------------------------------------
        report "TEST 2: 1000000 / 7";
        dividend <= to_unsigned(1000000, C_WIDTH);
        divisor  <= to_unsigned(7, C_WIDTH);
        start    <= '1';
        wait until rising_edge(clk);
        start    <= '0';
        wait for (C_WIDTH + 2) * C_CLK_PERIOD;

        --------------------------------------------------------------------
        -- TEST 3: max dividend / 1
        -- 4294967295 / 1 = 4294967295 remainder 0
        --------------------------------------------------------------------
        report "TEST 3: 4294967295 / 1 (max dividend)";
        dividend <= x"FFFFFFFF";
        divisor  <= to_unsigned(1, C_WIDTH);
        start    <= '1';
        wait until rising_edge(clk);
        start    <= '0';
        wait for (C_WIDTH + 2) * C_CLK_PERIOD;

        --------------------------------------------------------------------
        -- TEST 4: 100 / 0 = divide-by-zero -> 0, 0
        --------------------------------------------------------------------
        report "TEST 4: 100 / 0 (divide-by-zero, 0,0 beklenir)";
        dividend <= to_unsigned(100, C_WIDTH);
        divisor  <= to_unsigned(0, C_WIDTH);
        start    <= '1';
        wait until rising_edge(clk);
        start    <= '0';
        wait for (C_WIDTH + 2) * C_CLK_PERIOD;

        --------------------------------------------------------------------
        -- TEST 5: BACK-TO-BACK pipeline throughput test
        -- Arka arkaya 3 division. start pulse 3 cycle üstte kalsın, her cycle
        -- yeni dividend/divisor. Pipeline gerçekten "1/cycle throughput"
        -- göstersin.
        --   cycle 1: 10/2 -> 32 cycle sonra Q=5 R=0
        --   cycle 2: 20/4 -> 33 cycle sonra Q=5 R=0
        --   cycle 3: 30/6 -> 34 cycle sonra Q=5 R=0
        --------------------------------------------------------------------
        report "TEST 5: BACK-TO-BACK 3 division (pipeline throughput)";
        dividend <= to_unsigned(10, C_WIDTH);
        divisor  <= to_unsigned(2, C_WIDTH);
        start    <= '1';
        wait until rising_edge(clk);

        dividend <= to_unsigned(20, C_WIDTH);
        divisor  <= to_unsigned(4, C_WIDTH);
        -- start hâlâ '1'
        wait until rising_edge(clk);

        dividend <= to_unsigned(30, C_WIDTH);
        divisor  <= to_unsigned(6, C_WIDTH);
        -- start hâlâ '1'
        wait until rising_edge(clk);

        -- 3. division da pipeline'a girdi, start düş
        start    <= '0';
        wait for (C_WIDTH + 5) * C_CLK_PERIOD;

        report "Simulasyon bitti." severity note;
        wait;
    end process stim;

end architecture sim;
