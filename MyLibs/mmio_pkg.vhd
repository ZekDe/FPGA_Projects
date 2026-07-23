-------------------------------------------------------------------------------
-- mmio_pkg.vhd
-- Ortak MMIO tipleri. AXI3, Avalon veya baska bir bus on-yuzu ayni
-- register-bank uygulama tarafini kullanabilsin diye ayri tutulur.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package mmio_pkg is
    subtype t_mmio_word is std_logic_vector(31 downto 0);
    type t_mmio_word_array is array (natural range <>) of t_mmio_word;
end package mmio_pkg;

package body mmio_pkg is
end package body mmio_pkg;
