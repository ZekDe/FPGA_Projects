--------------------------------------------------------------------------------
--  button_top.vhd  -- DE0-Nano ust seviye (top-level) demo
--
--  ZINCIR:
--    CLOCK_50 --> time_base_ms --now_ms--> ton --retval--> edge_detector --> pulse
--    KEY[0]   --> synchronizer --> ton.in_sig
--
--  DE0-Nano gercekleri:
--    CLOCK_50 = 50 MHz   (PIN_R8)
--    KEY[0]   : AKTIF-DUSUK  -> basiliyken '0', birakinca '1'
--               Bu yuzden butona basildi = "sinyal 1" olsun diye ters ceviriyoruz.
--    KEY[1]   : reset olarak kullanacagiz (basili tutunca sistemi resetler)
--    LED[0]   : buton 100 ms boyunca kesintisiz basili kalirsa yanar
--
--  Not: TON burada hem "debounce" (mekanik titresim filtresi) hem de
--       "uzun bas algila" gorevini ayni anda goruyor. 100 ms boyunca sinyal
--       gercekten sabit 1 kalmadiysa cikis yanmaz -> titresimler elenir.
--       Artik preset dogrudan MILISANIYE: 100 ms yaziyoruz, tick hesabi yok.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity button_top is
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(1 downto 0);
        LED      : out std_logic_vector(7 downto 0)
    );
end entity button_top;

architecture rtl of button_top is

    constant C_CLK_HZ    : positive := 50_000_000;   -- DE0-Nano CLOCK_50
    constant C_WIDTH     : positive := 32;
    constant C_PRESET_MS : natural  := 100;          -- 100 ms (artik dogrudan ms!)

    signal rst_n     : std_logic;
    signal btn_raw   : std_logic;                       -- butonun aktif-yuksek hali
    signal btn_sync  : std_logic;                       -- senkronize edilmis temiz buton
    signal now_ms    : unsigned(C_WIDTH - 1 downto 0);  -- ortak zaman tabani (=C'deki now)
    signal ton_q     : std_logic;                       -- 100 ms doldu bayragi (seviye)
    signal btn_pulse : std_logic;                       -- tek-tick tetik (start/stop icin)

begin

    -- KEY[1] basili = reset (aktif-dusuk zaten bizim istedigimiz polarite)
    rst_n <= KEY(1);

    -- KEY[0] aktif-dusuk: basinca 0. Biz "basili = 1" istiyoruz -> ters cevir.
    btn_raw <= not KEY(0);

    -- ZAMAN TABANI: 50 MHz'i ms'ye ceviren donanim SysTick -> now_ms uretir
    u_time : entity work.time_base_ms
        generic map (
            G_CLK_HZ => C_CLK_HZ,
            G_WIDTH  => C_WIDTH
        )
        port map (
            clk     => CLOCK_50,
            rst_n   => rst_n,
            tick_ms => open,
            now_ms  => now_ms
        );

    -- ADIM 1: senkronizasyon (2 flip-flop derinlik)
    u_sync : entity work.synchronizer
        generic map (
            G_STAGES  => 2,
            G_RST_VAL => '0'
        )
        port map (
            clk      => CLOCK_50,
            rst_n    => rst_n,
            async_in => btn_raw,
            sync_out => btn_sync
        );

    -- ADIM 2: TON ile 100 ms filtre / on-delay (preset dogrudan ms)
    u_ton : entity work.ton
        generic map (
            G_WIDTH => C_WIDTH
        )
        port map (
            clk         => CLOCK_50,
            rst_n       => rst_n,
            in_sig      => btn_sync,
            now_ms      => now_ms,
            preset_time => to_unsigned(C_PRESET_MS, C_WIDTH),
            retval      => ton_q,
            since       => open
        );

    -- ADIM 3: kenar algilayici -> TON cikisinin yukselen kenarinda tek-tick pulse
    u_edge : entity work.edge_detector
        port map (
            clk    => CLOCK_50,
            rst_n  => rst_n,
            val    => ton_q,
            retval => btn_pulse
        );

    -- LED[0]: seviye (buton 100 ms basili kaldigi surece yanar)
    -- LED[1]: pulse cok kisa (20 ns) oldugu icin gozle gorunmez; simdilik
    --         sadece zincir dogru kurulsun diye bagliyoruz. Ilerde bu pulse
    --         bir FSM'i (start/stop) tetikleyecek.
    LED(0)          <= ton_q;
    LED(1)          <= btn_pulse;
    LED(7 downto 2) <= (others => '0');

end architecture rtl;
