library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.util_pkg.all;

entity seralizer_10_1 is
    port (
        clk : in std_logic;
        rst : in std_logic; -- rst must be in the clock domain of `clk`

        clk_5x : in std_logic; -- clk_10x must be 10x the freq of clk and phase matched

        i_data : in std_logic_vector(9 downto 0);
        o_seralized : out std_logic
    );
end entity seralizer_10_1;

architecture rtl of seralizer_10_1 is
    signal shift1 : std_ulogic;
    signal shift2 : std_ulogic;
begin
    serde_1 : OSERDESE2
     generic map(
        DATA_RATE_OQ => "DDR",
        DATA_WIDTH => 10,
        TBYTE_CTL => "FALSE",
        TBYTE_SRC => "FALSE",
        TRISTATE_WIDTH => 1,
        SERDES_MODE => "MASTER"
    )
     port map(
        CLK => clk_5x,
        CLKDIV => clk,
        RST => rst,

        OQ => o_seralized,
        D1 => i_data(0),
        D2 => i_data(1),
        D3 => i_data(2),
        D4 => i_data(3),
        D5 => i_data(4),
        D6 => i_data(5),
        D7 => i_data(6),
        D8 => i_data(7),
        OCE => '1',
        SHIFTIN1 => shift1,
        SHIFTIN2 => shift2,
        TCE => '0',

        t1 => '0',
        t2 => '0',
        t3 => '0',
        t4 => '0',
        tbytein => '0'
    );

    serde_2: OSERDESE2
     generic map(
        DATA_RATE_OQ => "DDR",
        DATA_WIDTH => 10,
        SERDES_MODE => "SLAVE",
        TBYTE_CTL => "FALSE",
        TBYTE_SRC => "FALSE",
        TRISTATE_WIDTH => 1
    )
     port map(
        CLK => clk_5x,
        CLKDIV => clk,
        RST => rst,

        SHIFTOUT1 => shift1,
        SHIFTOUT2 => shift2,
        D1 => '0',
        D2 => '0',
        D3 => i_data(8),
        D4 => i_data(9),
        D5 => '0',
        D6 => '0',
        D7 => '0',
        D8 => '0',
        OCE => '1',
        TCE => '0',

        t1 => '0',
        t2 => '0',
        t3 => '0',
        t4 => '0',
        tbytein => '0',
        SHIFTIN1 => '0',
        SHIFTIN2 => '0'
    );
end architecture;