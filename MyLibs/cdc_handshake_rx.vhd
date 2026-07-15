--------------------------------------------------------------------------------
--  cdc_handshake_rx.vhd  -- Async handshake'ın ALICI (RX) tarafı
--
--  AMAC:
--    Baska bir clock domain'deki (TX) verici tarafindan hazirlanan veriyi,
--    bu modulun clock domain'ine (RX) guvenle almak. "Guvenle" = veri
--    tutarsizligi (multi-bit CDC hatasi) olmamasi demek.
--
--  NASIL CALISIR (four-phase handshake - RX tarafindan gorulen kisim):
--    1) TX, req'yi 1 yapar (veri hazir) -> bizim domain'imize 2-FF ile gecer
--    2) Biz req_sync'i goruruz -> veriyi aliriz (register'lariz)
--    3) Biz ack'yi 1 yapariz (aldiM)
--    4) TX, ack'yi gorur, req'yi 0 yapar
--    5) Biz req_sync'in 0'a dustugunu goruruz
--    6) Biz ack'yi 0'a dusururuz -> TX bir sonraki veriyi hazirlayabilir
--
--  NEDEN GUVENLI?
--    - Veri bus'i req=1 oldugu surece TX tarafindan SABIT tutulur.
--    - Biz veriyi req_sync=1 gordugumuz AN aliriz, o anda veri kararli.
--    - req ve ack tek bit olduklari icin 2-FF ile guvenle senkronize edilirler.
--    - Cok bitli veri asla dogrudan senkronize EDILMEZ - sadece req/ack.
--
--  "REQ gorusu aninda veriyi al" desenindeki incelik:
--    p_state'te req'in YUKSELEN KENARINI yakalariz (req_sync'da 0->1 gecisi).
--    Boylece her req pulsu icin veriyi BIR KEZ aliriz. req_sync=1 oldugu
--    surece surekli almayiz (yoksa ayni veriyi defalarca yakalariz).
--
--  KULLANIM:
--    u_rx : entity work.cdc_handshake_rx
--      generic map ( G_WIDTH => 32 )
--      port map (
--          clk       => rx_clk,           -- bu modulun saati (RX domain)
--          rst_n     => rst_n,
--          data_in   => data_from_tx,     -- TX'den gelen data bus (async!)
--          req_in    => req_from_tx,      -- TX'den gelen req (async!)
--          ack_out   => ack_to_tx,        -- TX'e giden ack (RX domain)
--          data_out  => data_registered,  -- alinan veri (RX domain, kayitli)
--          data_valid => data_valid_pulse -- "yeni veri geldi" 1-clock pulsu
--      );
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cdc_handshake_rx is
    generic (
        G_WIDTH : positive := 32           -- data bus genisligi (bit)
    );
    port (
        clk        : in  std_logic;        -- RX domain saati (bizim sahimiz)
        rst_n      : in  std_logic;

        -- TX domain'den gelen (BU modul icin ASYNC)
        data_in    : in  std_logic_vector(G_WIDTH-1 downto 0);
        req_in     : in  std_logic;        -- TX: "veri hazir"

        -- TX domain'e giden (RX domain'de uretiliyor)
        ack_out    : out std_logic;        -- RX: "veriyi aldim"

        -- RX domain cikislari (bizim tarafimizda kayitli/guvenli)
        data_out   : out std_logic_vector(G_WIDTH-1 downto 0);
        data_valid : out std_logic         -- 1-clock pulse: "yeni veri yakalandi"
    );
end entity cdc_handshake_rx;


architecture rtl of cdc_handshake_rx is

    -- req'yi bu domain'e senkronize eden 2-FF zinciri
    signal req_sync     : std_logic;
    signal req_sync_d1  : std_logic;       -- req_sync'in bir onceki degeri (kenar icin)

    -- FSM durumlari (RX tarafinin el sikismasi):
    --   S_WAIT_REQ : req yukselene kadar bekle
    --   S_ACK_HIGH  : ack=1 tut, req dusene kadar bekle
    type state_t is (S_WAIT_REQ, S_ACK_HIGH);
    signal state : state_t := S_WAIT_REQ;

    -- Alinan veriyi tutan register
    signal data_reg : std_logic_vector(G_WIDTH-1 downto 0) := (others => '0');

    -- data_valid pulse'u (1-clock)
    signal valid_reg : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- req'yi 2-FF ile bu domain'e senkronize et (tek bit = guvenli)
    ----------------------------------------------------------------------------
    u_sync_req : entity work.synchronizer
        generic map ( G_STAGES => 2, G_RST_VAL => '0' )
        port map ( clk => clk, rst_n => rst_n,
                   async_in => req_in, sync_out => req_sync );

    ----------------------------------------------------------------------------
    -- RX FSM: four-phase handshake alici mantigi
    ----------------------------------------------------------------------------
    p_rx : process(clk, rst_n)
    begin
        if rst_n = '0' then
            state      <= S_WAIT_REQ;
            data_reg   <= (others => '0');
            valid_reg  <= '0';
            ack_out    <= '0';
            req_sync_d1 <= '0';
        elsif rising_edge(clk) then
            -- once req_sync'in bir onceki degerini kaydet (yukselen kenar icin)
            req_sync_d1 <= req_sync;

            -- data_valid default '0' (sadece aldim aninda pulse)
            valid_reg <= '0';

            case state is

                ----------------------------------------------------------------
                -- S_WAIT_REQ: req yukselen kenarini bekle
                --   req_sync 0->1 yaptiginda veriyi al, ack'yi kaldir
                ----------------------------------------------------------------
                when S_WAIT_REQ =>
                    ack_out <= '0';
                    if req_sync = '1' and req_sync_d1 = '0' then
                        -- req yukseldi! TX veriyi hazirlamis. Veriyi al.
                        data_reg  <= data_in;
                        valid_reg <= '1';        -- "yeni veri" pulsu
                        ack_out   <= '1';        -- "aldim" de
                        state     <= S_ACK_HIGH;
                    end if;

                ----------------------------------------------------------------
                -- S_ACK_HIGH: ack=1 tut, req dusene kadar bekle
                --   req_sync 1->0 yaptiginda (TX cevap verdi) ack'yi dusur
                ----------------------------------------------------------------
                when S_ACK_HIGH =>
                    ack_out <= '1';
                    if req_sync = '0' then
                        -- TX req'yi dusurdu -> el sikisma tamam. Basa don.
                        ack_out <= '0';
                        state   <= S_WAIT_REQ;
                    end if;

            end case;
        end if;
    end process p_rx;

    data_out   <= data_reg;
    data_valid <= valid_reg;

end architecture rtl;
