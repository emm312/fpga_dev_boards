library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.util_pkg.all;

entity tmds_encoder is
    port (
        clk : in std_logic;
        rst : in std_logic;

        i_data     : in std_logic_vector(7 downto 0);
        i_control  : in std_logic_vector(1 downto 0);
        i_video_en : in std_logic;

        o_encoded  : out std_logic_vector(9 downto 0)
    );
end entity tmds_encoder;

architecture tmds_encoder_rtl of tmds_encoder is
    signal ctrl_encoded : std_logic_vector(9 downto 0);

    signal i_data_unsigned : unsigned(7 downto 0);

    signal num_ones   : unsigned(3 downto 0);
    signal should_xor : std_logic;

    signal data_xnored : std_logic_vector(7 downto 0);
    signal data_xored  : std_logic_vector(7 downto 0);

    signal data : std_logic_vector(7 downto 0);

    signal encoded     : std_logic_vector(9 downto 0);
    signal inv_encoded : std_logic_vector(9 downto 0);

    signal dc_balance_acc : signed(3 downto 0);
    signal dc_balance     : signed(3 downto 0);
    signal dc_balance_inv : signed(3 downto 0);
begin
    with i_control select ctrl_encoded <= -- select output word based off of control singals
        "0010101011" when "00",
        "0010101010" when "01",
        "1101010100" when "10",
        "1101010101" when "11";

    i_data_unsigned <= unsigned(i_data);

    -- TODO: Figure out a way to make a more efficient bitcount
    num_ones <= count_ones(i_data);

    should_xor <= '0' when num_ones > 4
        else '0' when num_ones = 4 and i_data(0) = '0'
        else '1';

    data_xnored(0) <= i_data(0);
    g_data_xnored : for i in 1 to i_data'high generate
        data_xnored(i) <= i_data(i) xnor data_xnored(i-1);
    end generate;

    data_xored(0) <= i_data(0);
    g_data_xored : for i in 1 to i_data'high generate
        data_xored(i) <= i_data(i) xor data_xored(i-1);
    end generate;

    data <= data_xored when should_xor = '1' else data_xnored;

    encoded <= '0' & should_xor & data;
    inv_encoded <= '1' & should_xor & not data;
    
    dc_balance <= signed(count_ones(encoded)) - 4;
    dc_balance_inv <= signed(count_ones(inv_encoded)) - 4;

    process (clk) begin
        if rising_edge(clk) then
            if rst = '1' then
                dc_balance_acc <= (others => '0');
                o_encoded <= (others => '0');
            else
                if i_video_en then
                    if dc_balance_acc(dc_balance_acc'high) = '1' then -- if its negative choose the choice with more ones to balance it out
                        o_encoded <= encoded when dc_balance > dc_balance_inv else inv_encoded;
                        if dc_balance > dc_balance_inv then
                            dc_balance_acc <= dc_balance_acc + dc_balance;
                        else
                            dc_balance_acc <= dc_balance + dc_balance_inv;
                        end if;
                    else -- if its positive then choose the more negative one
                        o_encoded <= encoded when dc_balance < dc_balance_inv else inv_encoded;
                        if dc_balance > dc_balance_inv then
                            dc_balance_acc <= dc_balance_acc + dc_balance;
                        else
                            dc_balance_acc <= dc_balance_acc + dc_balance_inv;
                        end if;
                    end if;
                else
                    o_encoded <= ctrl_encoded;
                    dc_balance_acc <= dc_balance_acc + (signed(count_ones(ctrl_encoded)) - 4);
                end if;
            end if;
        end if;
    end process;
end architecture tmds_encoder_rtl;