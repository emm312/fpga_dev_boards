library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.util_pkg.all;

library unisim;
use unisim.vcomponents.all;

entity a7_lite_board is
    port (
        ------------------------------------------------------
        -- 50MHz clock
        i_clk_50 : in std_logic;

        ------------------------------------------------------
        -- Reset signal hooked up to K3
        i_nrst : in std_logic;

        ------------------------------------------------------
        -- Two output LEDs
        o_led1 : out std_logic;
        o_led2 : out std_logic;

        ------------------------------------------------------
        -- Push buttons 1 and 2
        i_key1 : in std_logic;
        i_key2 : in std_logic;

        ------------------------------------------------------
        -- UART Interface hooked up to a USB converter
        o_uart_tx : out std_logic;
        i_uart_rx : in std_logic;

        ------------------------------------------------------
        -- MicroSD card interface
        o_sd_clk   : out std_logic;
        io_sd_data : inout std_logic_vector(3 downto 0);
        io_sd_cmd  : inout std_logic;

        ------------------------------------------------------
        -- DDR3 Ram signals
        -- Note: use UG583
        o_ddr3_clk_p : out std_logic;
        o_ddr3_clk_n : out std_logic;
        o_ddr3_clken : out std_logic;

        o_ddr3_addr  : out std_logic_vector(14 downto 0);
        o_ddr3_ba    : out std_logic_vector(2 downto 0);

        io_ddr3_dq   : inout std_logic_vector(15 downto 0);
        o_ddr3_dm    : out std_logic_vector(1 downto 0);
        io_ddr3_dqs_p : inout std_logic_vector(1 downto 0);
        io_ddr3_dqs_n : inout std_logic_vector(1 downto 0);

        o_ddr3_nrst  : out std_logic;
        o_ddr3_n_wen : out std_logic;
        o_ddr3_n_ras : out std_logic;
        -- o_ddr3_n_cas : out std_logic;
        o_ddr3_odt   : out std_logic;

        ------------------------------------------------------
        -- HDMI Signals
        o_hdmi_scl : out std_logic;
        io_hdmi_sda : inout std_logic;

        o_hdmi_d_p : out std_logic_vector(2 downto 0);
        o_hdmi_d_n : out std_logic_vector(2 downto 0);
        o_hdmi_clk_p : out std_logic;
        o_hdmi_clk_n : out std_logic
    );
end entity;

architecture a7_lite_board_rtl of a7_lite_board is
    signal clk_50 : std_logic;
    signal rst_50 : std_logic;

    signal clk_250 : std_logic;
    signal clk_125 : std_logic;

    signal pulses : std_logic_vector(7 downto 0);

    signal frame_sync_local : std_logic;

    signal pixel_red : unsigned(7 downto 0);
    signal pixel_green : unsigned(7 downto 0);
    signal pixel_blue : unsigned(7 downto 0);

    signal pixel_dval : std_logic;
    signal pixel_in_ready : std_logic;

    signal hdmi_tmds_d : std_logic_vector(2 downto 0);
    signal hdmi_clk : std_logic;
begin
    clk_gen_inst: entity work.clk_gen
     generic map (
        G_CLOCKS_USED => 3,
        G_CLKFBOUT_MULT => 20, -- 1GHz interal freq
        G_CLKFBOUT_PHASE => 0.0,
        G_CLKIN_PERIOD => 20.0,

        G_CLKOUT0_DIVIDE => 40,  -- 25MHz pixel clk
        G_CLKOUT0_DUTY_CYCLE => 0.5,
        G_CLKOUT0_PHASE => 0.0,

        G_CLKOUT1_DIVIDE => 4,  -- 250MHz tmds clk
        G_CLKOUT1_DUTY_CYCLE => 0.5,
        G_CLKOUT1_PHASE => 0.0,

        G_CLKOUT2_DIVIDE => 2,  -- 125MHz oserdes clk
        G_CLKOUT2_DUTY_CYCLE => 0.5,
        G_CLKOUT2_PHASE => 0.0
    )
     port map(
        clk => i_clk_50,
        rst => "not"(i_nrst),

        o_clk_0 => clk_50,
        o_rst_0 => rst_50,

        o_clk_1 => clk_250,
        o_clk_2 => clk_125
    );


    inst_pulse_gen: entity work.pulse_gen
     generic map(
        G_POWERS_OF_100NS => 8,
        G_CLKS_IN_100NS => 25,
        G_ALIGN_OUTPUTS => true
    )
     port map(
        clk => clk_50,
        rst => rst_50,
        o_pulse_at_100ns_x_10e => pulses
    );

    hello_world_inst: entity work.hello_world
     port map(
        clk => clk_50,
        i_pulse => pulses(7),
        o_toggle => o_led1
    );

    process (clk_50) begin
        if (rising_edge(clk_50)) then
            if (frame_sync_local = '1') then
                pixel_red   <= (others => '0');
                pixel_green <= (others => '0');
                pixel_blue  <= (others => '0');
            else
                if (pixel_in_ready = '1') then
                    pixel_red <= pixel_red + 1;
        
                    if (pixel_red = unsigned(all_ones(7))) then
                        pixel_green <= pixel_green + 1;
        
                        if (pixel_green = unsigned(all_ones(7))) then
                            pixel_blue <= pixel_blue + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
    pixel_dval <= pixel_in_ready;

    i_hdmi_driver: entity work.hdmi_driver -- 1080p50
     generic map(
        G_MAX_SIZE_X => 1920,
        G_MAX_SIZE_Y => 1080,
        G_BITS_RED => 8,
        G_BITS_GREEN => 8,
        G_BITS_BLUE => 8
    )
     port map(
        pixel_clk => clk_50,
        pixel_clk_5x => clk_125,

        i_h_pic_size => to_unsigned(640, 11),
        i_v_pic_size => to_unsigned(480, 11),

        o_pixel_ready => pixel_in_ready,
        o_p_fifo_half => open,

        i_pixel_red => pixel_red,
        i_pixel_green => pixel_green,
        i_pixel_blue => pixel_blue,
        i_pixel_dval => pixel_dval,

        i_frame_sync => frame_sync_local,

        o_hdmi_channels => hdmi_tmds_d,
        o_error => open
    );

    o_led2 <= '1';

    o_uart_tx <= '0';
    
    o_sd_clk <= '0';
    io_sd_data <= (others => '0');
    io_sd_cmd <= '0';

    o_ddr3_clk_p <= '0';
    o_ddr3_clk_n <= '0';
    o_ddr3_clken <= '0';
    o_ddr3_addr <= (others => '0');
    o_ddr3_ba <= (others => '0');
    io_ddr3_dq <= (others => '0');
    o_ddr3_dm <= (others => '0');
    io_ddr3_dqs_p <= (others => '0');
    io_ddr3_dqs_n <= (others => '0');
    o_ddr3_nrst <= '0'; -- keep the DDR3 resetting as its not in use
    o_ddr3_n_wen <= '1';
    o_ddr3_n_ras <= '1';
    -- o_ddr3_n_cas <= '1';
    o_ddr3_odt <= '0';

    o_hdmi_scl <= '0';
    io_hdmi_sda <= '0';

    g_buf_hdmi_tmds : for i in 0 to 2 generate
        hdmi_tmds_buf : OBUFDS
        port map(
            O  => o_hdmi_d_p(i),
            OB => o_hdmi_d_n(i),
            I => hdmi_tmds_d(i)
        );
    end generate g_buf_hdmi_tmds;
    
    hdmi_clk_buf : OBUFDS
    port map(
        O => o_hdmi_clk_p,
        OB => o_hdmi_clk_n,
        I => clk_250
    );
end architecture a7_lite_board_rtl;
