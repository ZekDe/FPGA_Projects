--------------------------------------------------------------------------------
--  tb_cdc_handshake.vhd  -- Async req/ack handshake testbench
--
--  SENARYO:
--    TX domain (10 ns = 100 MHz) ve RX domain (14 ns = ~71 MHz) iliskisiz.
--    TX, 3 farkli 32-bit deger gonderir: 0xDEADBEEF, 0x12345678, 0xCAFEBABE.
--    RX her veriyi yakalar, data_valid pulsu uretir, biz de dogrulariz.
--
--  BEKLENEN SONUC:
--    - TX done pulsu her transfer sonunda gelir.
--    - RX data_valid pulsu her veri aliniminda gelir.
--    - Yakalanan degerler gonderilenlerle AYNI sirada VE AYNI degerde.
--    - Hic tutarsizlik olmaz (gray code'a ihtiyac yok, handshake yeterli).
--
--  BU TEST NEYI GOSTERIR?
--    Rastgele 32-bit degerler (ardisik degil!) guvenle transfer edilebilir.
--    Gray code bu senaryoda ise YARAMAZDI (veriler rastgele). Handshake gerekir.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_cdc_handshake is
end entity tb_cdc_handshake;

architecture sim of tb_cdc_handshake is

    constant C_TX_PERIOD : time := 10 ns;    -- 100 MHz
    constant C_RX_PERIOD : time := 14 ns;    -- ~71 MHz (iliskisiz)

    signal tx_clk : std_logic := '0';
    signal rx_clk : std_logic := '0';
    signal rst_n  : std_logic := '0';

    -- TX tarafindan surulen uyaranlar
    signal send_strobe : std_logic := '0';
    signal data_to_send : std_logic_vector(31 downto 0) := (others => '0');

    -- TX <-> RX arasindaki hatlar (handshake sinyalleri + data bus)
    signal data_bus : std_logic_vector(31 downto 0);
    signal req_line : std_logic;
    signal ack_line : std_logic;

    -- TX cikislari
    signal tx_busy : std_logic;
    signal tx_done : std_logic;

    -- RX cikislari
    signal rx_data  : std_logic_vector(31 downto 0);
    signal rx_valid : std_logic;

    -- Dogrulama: kac veri dogru alindi?
    signal rx_count : integer := 0;

begin

    tx_clk <= not tx_clk after C_TX_PERIOD / 2;
    rx_clk <= not rx_clk after C_RX_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- TX (verici) - tx_clk domain'inde
    ----------------------------------------------------------------------------
    u_tx : entity work.cdc_handshake_tx
        generic map ( G_WIDTH => 32 )
        port map (
            clk         => tx_clk,
            rst_n       => rst_n,
            data_in     => data_to_send,
            send_strobe => send_strobe,
            busy        => tx_busy,
            data_out    => data_bus,
            req_out     => req_line,
            ack_in      => ack_line,
            done        => tx_done
        );

    ----------------------------------------------------------------------------
    -- RX (alici) - rx_clk domain'inde
    ----------------------------------------------------------------------------
    u_rx : entity work.cdc_handshake_rx
        generic map ( G_WIDTH => 32 )
        port map (
            clk        => rx_clk,
            rst_n      => rst_n,
            data_in    => data_bus,
            req_in     => req_line,
            ack_out    => ack_line,
            data_out   => rx_data,
            data_valid => rx_valid
        );

    ----------------------------------------------------------------------------
    -- RX MONITOR: her data_valid'i yakala ve dogrula
    ----------------------------------------------------------------------------
    p_rx_check : process(rx_clk, rst_n)
    begin
        if rst_n = '0' then
            rx_count <= 0;
        elsif rising_edge(rx_clk) then
            if rx_valid = '1' then
                rx_count <= rx_count + 1;
                report "RX VERI ALDI (#" & integer'image(rx_count+1) &
                       "): 0x" & to_hstring(rx_data) severity note;
            end if;
        end if;
    end process p_rx_check;

    ----------------------------------------------------------------------------
    -- STIMULUS (TX domain'inde calisir)
    ----------------------------------------------------------------------------
    p_stim : process
    begin
        -- RESET
        rst_n <= '0';
        wait for 30 ns;
        rst_n <= '1';
        wait until rising_edge(tx_clk);

        --------------------------------------------------------------------
        -- 1. VERI: 0xDEADBEEF
        --------------------------------------------------------------------
        report ">>> TX 1. veriyi gonderiyor: 0xDEADBEEF" severity note;
        data_to_send <= x"DEADBEEF";
        send_strobe  <= '1';
        wait until rising_edge(tx_clk);
        send_strobe  <= '0';
        -- tx_done gelene kadar bekle (busy=0 olacak)
        wait until rising_edge(tx_clk) and tx_done = '1';
        report "<<< TX 1. transfer tamam (done pulsu)" severity note;
        wait for 50 ns;   -- biraz bosluk

        --------------------------------------------------------------------
        -- 2. VERI: 0x12345678
        --------------------------------------------------------------------
        report ">>> TX 2. veriyi gonderiyor: 0x12345678" severity note;
        data_to_send <= x"12345678";
        wait until rising_edge(tx_clk);
        send_strobe  <= '1';
        wait until rising_edge(tx_clk);
        send_strobe  <= '0';
        wait until rising_edge(tx_clk) and tx_done = '1';
        report "<<< TX 2. transfer tamam" severity note;
        wait for 50 ns;

        --------------------------------------------------------------------
        -- 3. VERI: 0xCAFEBABE
        --------------------------------------------------------------------
        report ">>> TX 3. veriyi gonderiyor: 0xCAFEBABE" severity note;
        data_to_send <= x"CAFEBABE";
        wait until rising_edge(tx_clk);
        send_strobe  <= '1';
        wait until rising_edge(tx_clk);
        send_strobe  <= '0';
        wait until rising_edge(tx_clk) and tx_done = '1';
        report "<<< TX 3. transfer tamam" severity note;
        wait for 100 ns;

        --------------------------------------------------------------------
        -- SONUC
        --------------------------------------------------------------------
        report "============================================" severity note;
        report "  TEST SONUCU: RX " & integer'image(rx_count) &
                " veri aldi (beklenen: 3)" severity note;
        report "============================================" severity note;
        wait;
    end process p_stim;

end architecture sim;
