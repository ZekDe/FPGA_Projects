--------------------------------------------------------------------------------
--  cdc_handshake_tx.vhd  -- Async handshake'ın VERİCİ (TX) tarafı
--
--  AMAC:
--    Bu modulun clock domain'indeki veriyi, baska bir domain'deki (RX) aliciya
--    guvenle gecirmek. "Guvenli" = veri tutarsizligi (multi-bit CDC) olmadan.
--
--  NASIL CALISIR (four-phase handshake - TX tarafindan gorunen kisim):
--    1) Kullanici yeni veri gondermek istediginde send_strobe=1 yapar
--    2) Biz veriyi bus'a koyariz (data_reg), req=1 yapariz
--    3) RX veriyi alip ack=1 yapar -> bizim domain'imize 2-FF ile gecer
--    4) Biz ack_sync=1 gorunce: veri alindi, req=0 yapariz
--    5) RX req=0 gorunce ack=0 yapar -> bizim domain'imize gecer
--    6) Biz ack_sync=0 gorunce: bitti, yeni veri gondermeye haziriz
--
--  NEDEN GUVENLI?
--    - Veri bus'i req=1 oldugu surece SABIT tutulur (data_reg degismez).
--    - RX veriyi alana kadar (ack verene kadar) bus degismez.
--    - Cok bitli veri asla dogrudan senkronize edilmez - sadece req/ack.
--
--  "BUSY" cikisi:
--    Kullanici (bizim domainimizdeki bir FSM) yeni veri gondermek istediginde
--    once busy'ye bakmali. busy=1 ise onceki transfer henuz bitmedi, beklemeli.
--    busy=0 ise send_strobe=1 + data_in gecerli olur.
--
--  KULLANIM:
--    u_tx : entity work.cdc_handshake_tx
--      generic map ( G_WIDTH => 32 )
--      port map (
--          clk        => tx_clk,          -- bu modulun saati (TX domain)
--          rst_n      => rst_n,
--          data_in    => data_to_send,    -- gonderilecek veri (TX domain)
--          send_strobe=> send_strobe,     -- "su veriyi gonder" 1-clock pulsu
--          busy       => tx_busy,         -- 1: henuz onceki transfer bitmedi
--          data_out   => data_to_rx,      -- RX'e giden data bus (RX domain)
--          req_out    => req_to_rx,       -- RX'e giden req (RX domain)
--          ack_in     => ack_from_rx,     -- RX'den gelen ack (async!)
--          done       => tx_done          -- 1-clock pulse: "transfer tamam"
--      );
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cdc_handshake_tx is
    generic (
        G_WIDTH : positive := 32
    );
    port (
        clk        : in  std_logic;        -- TX domain saati
        rst_n      : in  std_logic;

        -- TX domain (bizim tarafimizda guvenli)
        data_in     : in  std_logic_vector(G_WIDTH-1 downto 0);
        send_strobe : in  std_logic;       -- "su veriyi gonder" (1-clock pulse)
        busy        : out std_logic;       -- 1: onceki transfer henuz bitmedi

        -- RX domain'e giden (RX domain'de uretiliyor)
        data_out    : out std_logic_vector(G_WIDTH-1 downto 0);
        req_out     : out std_logic;       -- RX'e giden req

        -- RX domain'den gelen (BU modul icin ASYNC)
        ack_in      : in  std_logic;       -- RX: "veriyi aldim"

        -- TX domain cikislari
        done        : out std_logic        -- 1-clock pulse: "transfer tamam"
    );
end entity cdc_handshake_tx;


architecture rtl of cdc_handshake_tx is

    -- ack'yi 2-FF ile bu domain'e senkronize et
    signal ack_sync    : std_logic;
    signal ack_sync_d1 : std_logic;        -- ack_sync'un bir onceki degeri (dusen kenar icin)

    -- FSM durumlari (TX tarafinin el sikismasi):
    --   S_IDLE     : bosta, send_strobe bekle
    --   S_REQ_HIGH : req=1, ack=1 bekle (RX veriyi aldi demektir)
    --   S_REQ_LOW  : req=0, ack=0 bekle (RX yeni veriye hazir demektir)
    type state_t is (S_IDLE, S_REQ_HIGH, S_REQ_LOW);
    signal state : state_t := S_IDLE;

    -- Bus'a konan veriyi tutan register (req=1 oldugu surece SABIT)
    signal data_reg : std_logic_vector(G_WIDTH-1 downto 0) := (others => '0');
    signal req_reg  : std_logic := '0';
    signal done_reg : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- ack'yi 2-FF ile bu domain'e senkronize et
    -- (ack RX domain'inde uretiliyor, bizim icin async)
    ----------------------------------------------------------------------------
    u_sync_ack : entity work.synchronizer
        generic map ( G_STAGES => 2, G_RST_VAL => '0' )
        port map ( clk => clk, rst_n => rst_n,
                   async_in => ack_in, sync_out => ack_sync );

    ----------------------------------------------------------------------------
    -- TX FSM: four-phase handshake verici mantigi
    ----------------------------------------------------------------------------
    p_tx : process(clk, rst_n)
    begin
        if rst_n = '0' then
            state      <= S_IDLE;
            data_reg   <= (others => '0');
            req_reg    <= '0';
            done_reg   <= '0';
            ack_sync_d1 <= '0';
        elsif rising_edge(clk) then
            ack_sync_d1 <= ack_sync;
            done_reg    <= '0';            -- default '0'

            case state is

                ----------------------------------------------------------------
                -- S_IDLE: bosta, send_strobe bekle. busy = 0 (hazir).
                ----------------------------------------------------------------
                when S_IDLE =>
                    req_reg <= '0';
                    if send_strobe = '1' then
                        data_reg <= data_in;   -- veriyi bus'a koy
                        req_reg  <= '1';       -- "veri hazir" de
                        state    <= S_REQ_HIGH;
                    end if;

                ----------------------------------------------------------------
                -- S_REQ_HIGH: req=1 tut, ack=1 bekle (RX veriyi aldi demektir).
                ----------------------------------------------------------------
                when S_REQ_HIGH =>
                    req_reg <= '1';
                    if ack_sync = '1' then
                        -- RX veriyi aldi (ack geldi). req'yi dusur.
                        req_reg  <= '0';
                        done_reg <= '1';      -- "transfer tamam" pulsu
                        state    <= S_REQ_LOW;
                    end if;

                ----------------------------------------------------------------
                -- S_REQ_LOW: req=0, ack=0 bekle (RX yeni veriye hazir demektir).
                --   Bu adim KRITIK: ack 0'a donmeden yeni transfer baslatma,
                --   yoksa RX hala eski ack=1 goruyor olabilir -> karisiklik.
                ----------------------------------------------------------------
                when S_REQ_LOW =>
                    req_reg <= '0';
                    if ack_sync = '0' then
                        state <= S_IDLE;      -- el sikisma tamamen bitti
                    end if;

            end case;
        end if;
    end process p_tx;

    data_out <= data_reg;
    req_out  <= req_reg;
    busy     <= '0' when state = S_IDLE else '1';
    done     <= done_reg;

end architecture rtl;
