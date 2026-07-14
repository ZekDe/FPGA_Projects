--------------------------------------------------------------------------------
--  button_gesture.vhd  -- buton gesture (single/multi/long/long-repeat/release)
--                         algilayici, C kodundan BIREBIR FSM port'u
--  Referans: button_gesture.c / button_gesture.h  (Author: Emrah Duatepe)
--
--  C IMZASI:
--     void buttonGestureInit(button_gesture_t *obj,
--                            uint32_t debounce_ms,
--                            uint32_t long_press_ms,
--                            uint32_t multi_click_window_ms,
--                            uint32_t repeat_start_ms,
--                            uint32_t repeat_end_ms,
--                            uint32_t repeat_ramp_ms);
--
--     button_event_t buttonGestureProcess(button_gesture_t *obj,
--                                          uint8_t raw_pressed,
--                                          uint32_t now,
--                                          uint32_t *click_count_out);
--
--     void buttonGestureRequireRepress(button_gesture_t *obj);  -- IGNORE'a sok
--
--  C EVENT ENUM (one-hot cikislara ayri ayri karsilik gelir; NONE ayri hat degil):
--     BTN_EVT_SINGLE / MULTI / LONG / LONG_REPEAT / LONG_RELEASED
--
--  ISIM ESLESMESI (C -> VHDL):
--     Tum timing alanlari (debounce_ms, long_press_ms, vb.) -> RUNTIME PORT
--         (C'de struct alani -> menü degisince guncellenir; VHDL'de generic
--          DEGIL, config port'u -- system_top runtime'da veya Faz 5'te AXI
--          register'dan degistirebilir. A menu=600ms window, B menu=300ms gibi.)
--     now                         -> now_ms
--     raw_pressed                 -> raw_pressed  (async; sync ICERIDE)
--     buttonGestureRequireRepress -> require_repress (pulse)
--     BTN_EVT_*                   -> evt_* (one-hot, 1-clock pulse)
--     click_count_out             -> click_count
--     buttonGestureReset          -> rst_n (runtime sifirlama)
--
--  ZAMAN: now_ms MILISANIYE cinsinden (time_base_ms'ten gelir). Tum timer'lar
--         systick uzerinden calisir; clock-cycle sayaci yoktur.
--
--  STATE'ler (5 durum, switch-case C equivalent'i case-when):
--     S_IDLE         - bosta, pending yok
--     S_PRESSED      - basili, long threshold bekleniyor (click sayiliyor)
--     S_WINDOW_WAIT  - birakildi, multi-click window bekleniyor
--     S_LONG_HELD    - long gecildi, repeat ramp kosuyor
--     S_IGNORE       - require_repress ile disaridan tetiklendi, release'a kadar yut
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity button_gesture is
    port (
        clk                : in  std_logic;
        rst_n              : in  std_logic;
        now_ms             : in  unsigned(31 downto 0);
        raw_pressed        : in  std_logic;   -- async; sync'lenmesi ICERIDE
        require_repress    : in  std_logic;   -- pulse: IGNORE moduna sok

        -- runtime config portlari (C'deki struct alanlari; menü degisince guncellenir)
        -- Dikkat: generic DEGIL - system_top runtime'da (veya AXI register'dan)
        -- degistirebilir. C'deki 'obj->multi_click_window_ms = 300' karsiligi.
        debounce_ms             : in  unsigned(31 downto 0);
        long_press_ms           : in  unsigned(31 downto 0);
        multi_click_window_ms   : in  unsigned(31 downto 0);
        repeat_start_ms         : in  unsigned(31 downto 0);  -- 0 = repeat kapali
        repeat_end_ms           : in  unsigned(31 downto 0);
        repeat_ramp_ms          : in  unsigned(31 downto 0);  -- 0 = end hemen

        -- one-hot event cikislari (her biri 1-clock pulse)
        evt_single         : out std_logic;
        evt_multi          : out std_logic;
        evt_long           : out std_logic;
        evt_long_repeat    : out std_logic;
        evt_long_released  : out std_logic;

        -- MULTI olayinda kac click oldugu (diger zamanlarda 0)
        click_count        : out unsigned(7 downto 0)
    );
end entity button_gesture;


architecture rtl of button_gesture is

    -- FSM durumlari (case-when bunun uzerine kurulur)
    type state_t is (S_IDLE, S_PRESSED, S_WINDOW_WAIT, S_LONG_HELD, S_IGNORE);

    --------------------------------------------------------------------------
    -- PIPED DIVIDER entegrasyonu
    --------------------------------------------------------------------------
    -- Onceki versiyonda calc_period COMBINATIONAL function idi. 50 MHz'de
    -- timing slack negatif -> glitch'li period -> LED[5] parazit titremesi.
    -- Cozum: pipelined divider (vendor-bagimsiz, MyLibs/divider_pipelined).
    --
    -- Hesap: period = start_ms +/- (delta * elapsed) / ramp_ms
    --   delta = |start_ms - end_ms|
    --   elapsed = now_ms - long_started_at
    --   delta * elapsed = 64-bit carpim (numeric_std auto-widening)
    --   divider'a alt 32 bit verilir (pratikte tasma yok: delta<2^16, elapsed<2^16)
    --
    -- Divider 32 cycle latency'li. period_reg divider valid pulse geldikce
    -- guncellenir (S_LONG_HELD icinde, p_state tarafindan - TEK driver).
    -- S_LONG_HELD'ye giriste period_reg = repeat_start_ms (initial, p_state'te set).
    --------------------------------------------------------------------------
    signal delta         : unsigned(31 downto 0);   -- |start_ms - end_ms| (comb)
    signal elapsed_raw   : unsigned(31 downto 0);   -- now_ms - long_started_at (comb, clamp'onmemis)
    signal elapsed_calc  : unsigned(31 downto 0);   -- elapsed_raw, repeat_ramp_ms ile clamp'lenmis
    signal product_64    : unsigned(63 downto 0);   -- delta * elapsed (comb, 64-bit)
    signal div_start     : std_logic;               -- divider start pulse (comb)
    signal div_dividend  : unsigned(31 downto 0);   -- divider'a giden (product alt 32 bit)
    signal div_valid     : std_logic;               -- divider valid pulse
    signal div_quotient  : unsigned(31 downto 0);   -- divider cikisi (delta*elapsed/ramp)
    signal period_reg    : unsigned(31 downto 0);   -- guncel period (registered)

    signal state           : state_t := S_IDLE;     -- FSM durumu (registered)
    signal raw_sync        : std_logic;             -- 2-FF sync cikisi (synchronizer'dan)
    signal stable          : std_logic;             -- debounce cikisi (simetrik)
    signal stable_prev     : std_logic;             -- stable'in bir onceki degeri (rise icin)
    signal rise            : std_logic;             -- stable yukselen kenar (tek-tick pulse)
    signal last_raw        : std_logic;             -- C: ton_debounce.aux
    signal raw_since       : unsigned(31 downto 0); -- C: ton_debounce.since
    signal long_level      : std_logic;             -- TON(long_press_ms) cikisi

    -- FSM'in register tuttugu degiskenler (C'deki struct runtime alanlari)
    signal click_count_reg : unsigned(7 downto 0)  := (others => '0');  -- C: click_count
    signal window_start    : unsigned(31 downto 0) := (others => '0');  -- C: window_start
    signal long_started_at : unsigned(31 downto 0) := (others => '0');  -- C: long_started_at
    signal last_repeat     : unsigned(31 downto 0) := (others => '0');  -- C: last_repeat

begin

    --------------------------------------------------------------------------
    -- COMBINATIONAL HESAPLAMALAR (delta, elapsed, product, div_start)
    --------------------------------------------------------------------------
    -- elapsed: S_LONG_HELD'deyken long baslangicina kadar gecen sure.
    --   C CLAMP (satir 104): elapsed >= repeat_ramp_ms ise ramp bitmistir,
    --   period = end_ms'de sabit kalmali. elapsed'i repeat_ramp_ms ile
    --   clamp'lersek dividend (delta*elapsed_clamped) <= delta*ramp_ms olur,
    --   quotient <= delta olur, period >= end_ms olur. Underflow IMKANSIZ.
    --   Ramp bitince dividend degismez -> quotient degismez -> period SABIT.
    elapsed_raw   <= now_ms - long_started_at when state = S_LONG_HELD
                     else (others => '0');
    elapsed_calc  <= elapsed_raw when elapsed_raw <= repeat_ramp_ms
                     else repeat_ramp_ms;

    -- delta: |start_ms - end_ms| (mutlak deger)
    delta <= repeat_start_ms - repeat_end_ms when repeat_start_ms >= repeat_end_ms
             else repeat_end_ms - repeat_start_ms;

    -- product: delta * elapsed (numeric_std auto-widen 32x32 -> 64 bit)
    product_64 <= delta * elapsed_calc;

    -- divider'a alt 32 bit (clamp sayesinde tasma garanti yok: delta<2^16,
    -- ramp_ms<2^16 oldugu surece delta*ramp_ms < 2^32)
    div_dividend <= product_64(31 downto 0);

    -- divider start: sadece S_LONG_HELD'de ve repeat aktifken
    div_start <= '1' when (state = S_LONG_HELD) and (repeat_start_ms /= 0)
                 else '0';

    --------------------------------------------------------------------------
    -- PIPED DIVIDER (vendor-bagimsiz, 32-cycle latency, 1/cycle throughput)
    --------------------------------------------------------------------------
    u_div : entity work.divider_pipelined
        generic map ( G_WIDTH => 32 )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            start     => div_start,
            dividend  => div_dividend,
            divisor   => repeat_ramp_ms,
            valid     => div_valid,
            quotient  => div_quotient,
            remainder => open
        );

    u_sync : entity work.synchronizer
        generic map ( G_STAGES => 2, G_RST_VAL => '0' )
        port map ( clk => clk, rst_n => rst_n,
                   async_in => raw_pressed, sync_out => raw_sync );

    ----------------------------------------------------------------------------
    -- p_debounce: simetrik debounce (C satir 36-44)
    --   raw_sync degisti mi sayaci sifirla; debounce_ms boyunca sabit kaldıysa
    --   yeni degeri kabul et, yoksa stable'i oldugu gibi birak (VHDL'de atama
    --   yapmazsan sinyal otomatik korunur).
    ----------------------------------------------------------------------------
    p_debounce : process(clk, rst_n)
    begin
        if rst_n = '0' then
            last_raw   <= '0';
            raw_since  <= (others => '0');
            stable     <= '0';
        elsif rising_edge(clk) then
            -- C: if (raw_pressed != obj->ton_debounce.aux) { .aux=raw; .since=now; }
            if raw_sync /= last_raw then
                last_raw  <= raw_sync;
                raw_since <= now_ms;
            end if;

            -- C: if ((now - since) >= debounce_ms) stable = raw_pressed;
            --    else stable = btn_stable;   (eski korumali)
            if (now_ms - raw_since) >= debounce_ms then
                stable <= raw_sync;
            end if;
            -- else: stable <= stable;  <-- VHDL'de yazmaya gerek yok, otomatik korunur
        end if;
    end process p_debounce;

    ----------------------------------------------------------------------------
    -- p_edge: stable_prev register + combinational rise
    --   C'deki 'edgeDetection(ed_rise, stable)' karsiligi. stable 0->1 yaptigi
    --   anda rise bir clock icin '1' olur, sonra otomatik '0'.
    ----------------------------------------------------------------------------
    p_edge : process(clk, rst_n)
    begin
        if rst_n = '0' then
            stable_prev <= '0';
        elsif rising_edge(clk) then
            stable_prev <= stable;
        end if;
    end process p_edge;

    rise <= stable and not stable_prev;   -- combinational yukselen kenar

    ----------------------------------------------------------------------------
    -- u_ton_long: long_press_ms threshold (C: ton_long TON cagrisi)
    --   stable=1 olduktan long_press_ms sonra long_level='1' olur. Cikis seviye,
    --   kenar degil. S_LONG_HELD gecisi icin bu yeterli (state degisince bir daha
    --   tetiklenmez).
    ----------------------------------------------------------------------------
    u_ton_long : entity work.ton
        generic map ( G_WIDTH => 32 )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            in_sig      => stable,
            now_ms      => now_ms,
            preset_time => long_press_ms,
            retval      => long_level,
            since       => open
        );

    ----------------------------------------------------------------------------
    -- p_state: FSM durum saklayicisi (case-when)
    --   require_repress GLOBAL: her durumda S_IGNORE'a zorlar (C'deki
    --   buttonGestureRequireRepress buton durumu ne olursa olsun gecerli).
    ----------------------------------------------------------------------------
    p_state : process(clk, rst_n)
    begin
        if rst_n = '0' then
            state           <= S_IDLE;
            click_count_reg <= (others => '0');
            window_start    <= (others => '0');
            long_started_at <= (others => '0');
            last_repeat     <= (others => '0');
            period_reg      <= (others => '0');
        elsif rising_edge(clk) then
            if require_repress = '1' then
                -- C: buttonGestureRequireRepress -> click_count=0, window kapali
                state           <= S_IGNORE;
                click_count_reg <= (others => '0');

            else
                case state is

                    ----------------------------------------------------------------
                    -- S_IDLE: buton birakilmis, pending yok. Ilk click'i bekle.
                    ----------------------------------------------------------------
                    when S_IDLE =>
                        if rise = '1' then
                            -- C satir 69-74: window_ac, count=1
                            state           <= S_PRESSED;
                            click_count_reg <= to_unsigned(1, 8);
                            window_start    <= now_ms;
                        end if;

                    ----------------------------------------------------------------
                    -- S_PRESSED: buton basili, long threshold bekleniyor.
                    --   long_level=1 olunca -> S_LONG_HELD (LONG olayi Adim 4'te)
                    --   stable=0 olunca    -> S_WINDOW_WAIT (multi-click bekle)
                    ----------------------------------------------------------------
                    when S_PRESSED =>
                        if stable = '0' then
                            -- buton birakildi, multi-click window beklemeye gec
                            state <= S_WINDOW_WAIT;

                        elsif long_level = '1' then
                            -- C satir 82-95: long threshold gecildi
                            state           <= S_LONG_HELD;
                            click_count_reg <= (others => '0');  -- C: click_count=0
                            long_started_at <= now_ms;            -- C: long_started_at=now
                            last_repeat     <= now_ms;            -- C: last_repeat=now
                            -- period_reg initial degeri: elapsed=0 iken period=start_ms
                            -- (divider 32 cycle sonra gercek degeri uretecek)
                            period_reg      <= repeat_start_ms;
                        end if;

                    ----------------------------------------------------------------
                    -- S_WINDOW_WAIT: buton birakilmis, multi-click window aktif.
                    --   FSM yapisi geregi stable=0 garantili (S_PRESSED'dan ancak
                    --   release ile cikilir). Bu yuzden C'deki ekstra (stable==0)
                    --   kontrolu burada gerekmez - FSM'in kazanci.
                    --
                    --   rise  (yeni basış)  -> S_PRESSED + click_count++
                    --   window timeout      -> S_IDLE (SINGLE/MULTI olayi p_outputs
                    --                                   ayni tick'te state'i hala
                    --                                   S_WINDOW_WAIT gorur, cunku
                    --                                   state registered - bir
                    --                                   sonraki tick'te S_IDLE olur)
                    ----------------------------------------------------------------
                    when S_WINDOW_WAIT =>
                        if rise = '1' then
                            -- C satir 76-79: multi-click, click_count++
                            state           <= S_PRESSED;
                            click_count_reg <= click_count_reg + 1;

                        elsif (now_ms - window_start) >= multi_click_window_ms then
                            -- C satir 136-164: window timeout -> SINGLE/MULTI
                            -- Event'in kendisi Adim 4'te p_outputs'ta uretilir;
                            -- burada sadece state ve sayac guncellenir.
                            state           <= S_IDLE;
                            click_count_reg <= (others => '0');
                        end if;

                    ----------------------------------------------------------------
                    -- S_LONG_HELD: long threshold gecildi, buton hala basili.
                    --   stable=0           -> S_IDLE + evt_long_released (Adim 4)
                    --   repeat_start_ms=0  -> repeat kapali, sadece bekle (release'i bekle)
                    --   aksi               -> repeat ramp calistir, period dolunca
                    --                        last_repeat guncelle + evt_long_repeat (Adim 4)
                    --
                    --   PERIOD HESABI: pipelined divider (u_div) 32 cycle once
                    --   baslattigimiz (delta*elapsed) / ramp_ms bolumunu tamamlayip
                    --   period_reg'i guncelliyor. p_state burada period_reg'i
                    --   COMPARISON icin okur - calc_period function'i YOK artik.
                    --
                    --   Divider start yukarida (div_start) sadece bu state'te '1'.
                    --   32 cycle latency: S_LONG_HELD'ye girdikten 32 cycle sonra
                    --   gercek period degeri gelir. O zamana kadar period_reg =
                    --   repeat_start_ms (initial, elapsed=0 icin dogru).
                    ----------------------------------------------------------------
                    when S_LONG_HELD =>
                        -- PERIOD GUNCELLEME: pipelined divider 32 cycle once
                        -- baslattigimiz bolumun sonucu (div_valid) burada cikar.
                        -- once guncelle, sonra karsilastir -> yeni period bir
                        -- sonraki tick'ten itibaren gecerli. (period_reg artik
                        -- TEK process'ten - p_period_reg'a driver cakismasi yok.)
                        --
                        -- C CLAMP (satir 104-106): elapsed >= ramp_ms ise period =
                        -- end_ms'de SABITLENIR, ramp bitince ivme durur, end_ms
                        -- periyoduyla sonsuza kadar tekrarlar. Bu clamp
                        -- dividend (delta*elapsed) ramp_ms*delta'ya clamp'lenerek
                        -- SAGLANIR: boylece quotient asla delta'yi gecemez, dolayisiyla
                        -- (start - quotient) asla end'in altina inemez. Underflow
                        -- IMKANSIZ. (Combinational div versiyonunda da ayni sekilde
                        -- elapsed clamp'leniyordu - birebir C davranisi.)
                        if div_valid = '1' then
                            if repeat_start_ms >= repeat_end_ms then
                                period_reg <= repeat_start_ms - div_quotient;
                            else
                                period_reg <= repeat_start_ms + div_quotient;
                            end if;
                        end if;

                        if stable = '0' then
                            -- C satir 130-134: buton birakildi -> LONG_RELEASED olayi
                            state <= S_IDLE;

                        elsif repeat_start_ms /= 0 then
                            -- C satir 120-124: period doldu mu?
                            if (now_ms - last_repeat) >= period_reg then
                                last_repeat <= now_ms;
                                -- evt_long_repeat p_outputs'ta ayni tick'te uretilir
                            end if;
                        end if;

                    ----------------------------------------------------------------
                    -- S_IGNORE: require_repress ile girildi. Buton release olana
                    -- kadar tum olaylar yutulur (C satir 55-65). Edge dedektorleri
                    -- (p_edge) ve TON yukarida HALA calisir - bu, "release aninda
                    -- bayat edge patlamasin" C'deki tekniğin birebir karsiligi.
                    -- C'de yorum: "Edge dedektorleri yukarida guncellendi (bayat
                    -- edge patlamasin diye)"
                    --
                    --   stable=0 -> S_IDLE (release -> temiz donus)
                    --   stable=1 -> S_IGNORE'da kal (yut)
                    ----------------------------------------------------------------
                    when S_IGNORE =>
                        if stable = '0' then
                            state <= S_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process p_state;

    ----------------------------------------------------------------------------
    -- p_outputs: event pulse cikislari (default + override deseni)
    --   p_state ile AYNI clock'ta calisir. State registered oldugu icin, p_outputs
    --   bu tick'te state'in ESKI (current) degerini gorur - bu, "gecis aninda event
    --   uret" davranisini saglar:
    --     Tick N: p_state, S_PRESSED'de long_level=1 gorur, state <= S_LONG_HELD
    --            p_outputs, state = S_PRESSED gorur, long_level=1 -> evt_long<='1'
    --     Tick N+1: state = S_LONG_HELD, evt_long default '0'
    ----------------------------------------------------------------------------
    p_outputs : process(clk, rst_n)
    begin
        if rst_n = '0' then
            evt_single        <= '0';
            evt_multi         <= '0';
            evt_long          <= '0';
            evt_long_repeat   <= '0';
            evt_long_released <= '0';
            click_count       <= (others => '0');
        elsif rising_edge(clk) then
            -- DEFAULT: her tick once "hic event yok" (C'deki return NONE)
            evt_single        <= '0';
            evt_multi         <= '0';
            evt_long          <= '0';
            evt_long_repeat   <= '0';
            evt_long_released <= '0';
            click_count       <= (others => '0');

            -- Sonra state'e gore OVERRIDE - sadece gecis/tesvik aninda 1 tick
            case state is

                ----------------------------------------------------------------
                -- S_PRESSED: long_level=1 aninda LONG olayi
                --   (p_state ayni tick'te state -> S_LONG_HELD yapar)
                ----------------------------------------------------------------
                when S_PRESSED =>
                    if long_level = '1' then
                        evt_long <= '1';
                    end if;

                ----------------------------------------------------------------
                -- S_WINDOW_WAIT: window timeout aninda SINGLE veya MULTI
                --   click_count_reg=1   -> SINGLE
                --   click_count_reg>=2  -> MULTI + click_count'u disari ver
                ----------------------------------------------------------------
                when S_WINDOW_WAIT =>
                    if (now_ms - window_start) >= multi_click_window_ms then
                        if click_count_reg = 1 then
                            evt_single <= '1';
                        elsif click_count_reg >= 2 then
                            evt_multi   <= '1';
                            click_count <= click_count_reg;  -- MULTI ile count
                        end if;
                    end if;

                ----------------------------------------------------------------
                -- S_LONG_HELD: buton basili iken LONG_REPEAT, birakilinca
                --              LONG_RELEASED. period_reg pipelined divider
                --              tarafindan guncellenir (p_state ile ayni signal).
                ----------------------------------------------------------------
                when S_LONG_HELD =>
                    if stable = '0' then
                        -- C satir 130-134: buton birakildi
                        evt_long_released <= '1';
                    elsif repeat_start_ms /= 0 then
                        if (now_ms - last_repeat) >= period_reg then
                            evt_long_repeat <= '1';
                        end if;
                    end if;

                when others => null;
            end case;
        end if;
    end process p_outputs;

end architecture rtl;
