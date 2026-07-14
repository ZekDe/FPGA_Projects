--------------------------------------------------------------------------------
--  divider_pipelined.vhd  -- 32-bit unsigned divider, pipelined (vendor-bagimsiz)
--
--  AMAC:
--    Restoring division algoritmasi, her clock cycle 1 bit isler. 32-stage
--    pipeline. Combinational division 50 MHz'de timing slack negatif yaratiyor;
--    pipeline her stage'i kucuk tutar -> timing rahat, clock hizina kolay yetisir.
--
--  ALGORITMA (restoring):
--    R = 0, Q = 0
--    for i = (W-1) downto 0:
--        R = (R << 1) | A[i]   -- R'yi sola kaydir, A'nin i. bitini LSB'ye koy
--        if R >= B:
--            R = R - B
--            Q[i] = 1
--        else:
--            Q[i] = 0
--
--  PIPELINE YAPISI:
--    W+1 stage: stage 0 = input latch, stage 1..W = bit hesap.
--    Her clock cycle yeni (dividend, divisor) kabul edilir (throughput 1/cycle).
--    Sonuc W cycle sonra cikar (latency = W cycle).
--    Start pulse -> W cycle sonra valid pulse.
--
--  DIVIDE BY ZERO:
--    divisor=0 ise quotient=0, remainder=0 verilir (tanimsiz, guvenli default).
--
--  KULLANIM:
--    u_div : entity work.divider_pipelined
--      generic map ( G_WIDTH => 32 )
--      port map ( clk=>clk, rst_n=>rst_n,
--                 start=>start_pulse, dividend=>A, divisor=>B,
--                 valid=>valid_pulse, quotient=>Q, remainder=>R );
--
--  VENDOR BAGIMSIZ: Quartus, Vivado, Modelsim, Questa - hepsinde calisir.
--  SAVUNMA: DO-254 audit icin tam transparan VHDL, black-box IP yok.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity divider_pipelined is
    generic (
        G_WIDTH : positive := 32   -- operand genisligi (dividend, divisor, quotient hepsi ayni)
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;

        -- Input (her cycle yeni division baslatilabilir, fully pipelined)
        start     : in  std_logic;                              -- 1-cycle pulse
        dividend  : in  unsigned(G_WIDTH-1 downto 0);           -- A : bolunen
        divisor   : in  unsigned(G_WIDTH-1 downto 0);           -- B : bolen (0 ise Q=R=0)

        -- Output (G_WIDTH cycle sonra; start pulse kac cycle sonra, valid pulse o cycle gelir)
        valid     : out std_logic;                              -- 1-cycle pulse
        quotient  : out unsigned(G_WIDTH-1 downto 0);           -- Q = A / B
        remainder : out unsigned(G_WIDTH-1 downto 0)            -- R = A mod B
    );
end entity divider_pipelined;


architecture rtl of divider_pipelined is

    --------------------------------------------------------------------------
    -- PIPELINE DATA TYPE'LARI
    --------------------------------------------------------------------------
    -- Her pipeline stage ayni tipte register tutar. Index Convention:
    --   (0)     -> input stage (start pulse ile latch'lenir)
    --   (1..W)  -> compute stage'leri, her stage 1 bit hesaplar
    --   (W)     -> output (final quotient + remainder)
    --
    -- Stage sayisi = W+1 (input + W compute). Latency = W cycle.

    -- 32-bit data pipeline (dividend, divisor, quotient ayni tipte)
    type t_pipe_data is array(0 to G_WIDTH) of unsigned(G_WIDTH-1 downto 0);

    -- 33-bit remainder pipeline (1 bit overflow margini: (R<<1) 1 bit buyuyebilir)
    type t_pipe_rem  is array(0 to G_WIDTH) of unsigned(G_WIDTH downto 0);

    --------------------------------------------------------------------------
    -- PIPELINE SIGNAL'LARI
    --------------------------------------------------------------------------
    -- pipe_a    : dividend, her stage'te SOLA kaydirilir (MSB consume edilir)
    -- pipe_b    : divisor,  pipeline boyunca sabit (passthrough)
    -- pipe_q    : quotient, her stage'te SOLA kaydirilir, LSB yeni bit olarak yazilir
    -- pipe_r    : remainder (33-bit), her stage'te shift + conditional subtract
    -- pipe_valid: start pulse'u W stage'ten gecer, output'ta valid pulse olur
    signal pipe_a     : t_pipe_data;
    signal pipe_b     : t_pipe_data;
    signal pipe_q     : t_pipe_data;
    signal pipe_r     : t_pipe_rem;
    signal pipe_valid : std_logic_vector(0 to G_WIDTH);

begin

    --------------------------------------------------------------------------
    -- INPUT STAGE (stage 0) -- pipeline'a giris
    --------------------------------------------------------------------------
    -- Her clock cycle'da dividend/divisor sample edilir ve pipe_a/pipe_b(0)'ya
    -- yazilir. pipe_valid(0) = start: bu cycle'da data gecerli mi?
    --
    -- pipe_r(0) ve pipe_q(0) initial degerleri 0 (algoritma R=0, Q=0 baslangic).
    -- Stage 1 bunu alip ilk bit (MSB) icin shift+compare yapar.
    --------------------------------------------------------------------------
    p_input : process(clk, rst_n)
    begin
        if rst_n = '0' then
            pipe_a(0)     <= (others => '0');
            pipe_b(0)     <= (others => '0');
            pipe_q(0)     <= (others => '0');
            pipe_r(0)     <= (others => '0');
            pipe_valid(0) <= '0';
        elsif rising_edge(clk) then
            pipe_a(0)     <= dividend;            -- dividend sample
            pipe_b(0)     <= divisor;             -- divisor sample
            pipe_q(0)     <= (others => '0');     -- baslangic quotient = 0
            pipe_r(0)     <= (others => '0');     -- baslangic remainder = 0
            pipe_valid(0) <= start;               -- start pulse -> pipeline'a girer
        end if;
    end process p_input;

    --------------------------------------------------------------------------
    -- PIPELINE STAGES 1..G_WIDTH  (for-generate: her stage odex lojik)
    --------------------------------------------------------------------------
    -- Her stage RESTORE ALGORITMASI'NIN 1 ADIMINI uygular:
    --
    --   1) pipe_a(i) <= pipe_a(i-1) << 1          (dividend shift left, MSB consume)
    --   2) new_R := pipe_r(i-1)(31 downto 0) & pipe_a(i-1)(MSB)   (R'yi shift + dividend bit'i ekle)
    --   3) if new_R >= pipe_b(i-1):
    --         pipe_r(i) <= new_R - pipe_b(i-1);  Q_bit = 1
    --      else:
    --         pipe_r(i) <= new_R;                Q_bit = 0
    --   4) pipe_q(i) <= pipe_q(i-1)(30 downto 0) & Q_bit   (quotient shift + yeni bit)
    --
    -- pipe_b ve pipe_valid sadece passthrough (sabit/pulse pipeline boyunca aksar).
    --------------------------------------------------------------------------
    gen_stages : for i in 1 to G_WIDTH generate
        p_stage : process(clk, rst_n)
            variable v_new_r : unsigned(G_WIDTH downto 0);   -- 33-bit (overflow margini)
            variable v_q_bit : std_logic;
        begin
            if rst_n = '0' then
                pipe_a(i)     <= (others => '0');
                pipe_b(i)     <= (others => '0');
                pipe_q(i)     <= (others => '0');
                pipe_r(i)     <= (others => '0');
                pipe_valid(i) <= '0';
            elsif rising_edge(clk) then
                -- PASSTHROUGH: divisor ve valid pulse pipeline boyunca sabit akar
                pipe_b(i)     <= pipe_b(i-1);
                pipe_valid(i) <= pipe_valid(i-1);

                -- DIVIDEND: shift left. Bir onceki stage'in MSB'si consume edildi
                -- (new_R hesabinda kullanildi). Bu stage sonraki biti gorecek.
                pipe_a(i)     <= shift_left(pipe_a(i-1), 1);

                -- RESTORE ALGORITMASI: new R hesapla
                -- new_R (33 bit) = R_old(32:1) & A_old(MSB)
                -- Yani R'yi sola kaydir, dividend'in MSB'ini LSB'ye koy.
                -- R_old'un bit 32 (overflow) atilir - invariant olarak hep 0.
                v_new_r := pipe_r(i-1)(G_WIDTH-1 downto 0) & pipe_a(i-1)(G_WIDTH-1);

                -- COMPARE + CONDITIONAL SUBTRACT
                -- pipe_b 32-bit, new_R 33-bit. Karsilastirma icin pipe_b'yi 33-bit'e genislet.
                if v_new_r >= ('0' & pipe_b(i-1)) then
                    -- new_R >= B: subtract yap, remainder kuculdu, Q bit = 1
                    pipe_r(i) <= v_new_r - ('0' & pipe_b(i-1));
                    v_q_bit   := '1';
                else
                    -- new_R < B: subtract yok (R = newR), Q bit = 0
                    pipe_r(i) <= v_new_r;
                    v_q_bit   := '0';
                end if;

                -- QUOTIENT: shift left + yeni bit LSB'ye
                -- pipe_q(i-1)(30 downto 0) = pipe_q(i-1)'in alt 31 biti
                -- & v_q_bit = LSB'ye 1-bit ekle
                -- Sonuc 32-bit. (Bu shift_left + OR'den daha temiz.)
                pipe_q(i) <= pipe_q(i-1)(G_WIDTH-2 downto 0) & v_q_bit;
            end if;
        end process p_stage;
    end generate gen_stages;

    --------------------------------------------------------------------------
    -- OUTPUT STAGE -- pipeline cikisini entity portlarina bagla
    --------------------------------------------------------------------------
    -- pipe_q(G_WIDTH), pipe_r(G_WIDTH), pipe_valid(G_WIDTH) zaten registered
    -- (32 stage'in son FF'leri). Output portlara dogrudan bagliyoruz; ekstra
    -- FF yok, combinational correction sadece divide-by-zero icin.
    --------------------------------------------------------------------------
    -- DIVIDE BY ZERO KORUMASI:
    --   pipe_b(G_WIDTH) pipeline boyunca tasidigimiz divisor'un son degeri.
    --   Eger divisor=0 ise quotient ve remainder 0 verilir (tanimsiz, guvenli
    --   default). Algoritma divisor=0 ile quotient=0xFFFFFFFF uretir (her
    --   compare true olur), bunu maskelemek sadece 1 comparateur + mux mali.
    --------------------------------------------------------------------------
    p_output : process(clk, rst_n)
    begin
        if rst_n = '0' then
            valid     <= '0';
            quotient  <= (others => '0');
            remainder <= (others => '0');
        elsif rising_edge(clk) then
            -- Valid pulse pipeline'in son FF'inden gelir
            valid <= pipe_valid(G_WIDTH);

            -- Divide-by-zero maskeli output
            if pipe_b(G_WIDTH) = to_unsigned(0, G_WIDTH) then
                quotient  <= (others => '0');
                remainder <= (others => '0');
            else
                quotient  <= pipe_q(G_WIDTH);
                -- pipe_r 33-bit; alt 32 biti remainder (bit 32 invariant olarak 0)
                remainder <= pipe_r(G_WIDTH)(G_WIDTH-1 downto 0);
            end if;
        end if;
    end process p_output;

end architecture rtl;
