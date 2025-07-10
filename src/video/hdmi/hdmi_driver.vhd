-------------------------------------------------------------------------------
--
-- Copyright (c) 2020 Iain Waugh
-- All rights reserved.
--
-------------------------------------------------------------------------------
-- Project Name  : AX309 Project
-- Author(s)     : Iain Waugh, Emmanuel Koutsouklakis
-- File Name     : hdmi_driver.vhd
--
-- A HDMI output driver.
--   It has a pixel FIFO input that is 2^5 = 32 deep by default.
--
-- Use the CTA-861 Optimized Video Timing (OVT) Generator for values
--   https://www.cta.tech/Resources/Standards/CTA-861-OVT-Calculator
--
-- Build-time features:
--   Max X,Y resolution
--   Number of bits per RGB component
--
-- Run-time features:
--   Video timings
--   Picture size
--   Picture border (example use: aspect ration control)
--   Border colour
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.util_pkg.all;

entity hdmi_driver is
  generic(
    G_MAX_SIZE_X : natural := 1920;
    G_MAX_SIZE_Y : natural := 1200;

    G_BITS_RED   : natural := 8;
    G_BITS_GREEN : natural := 8;
    G_BITS_BLUE  : natural := 8;

    G_LOG2_PIXEL_FIFO_DEPTH : natural := 5
    );
  port(
    pixel_clk : in std_logic;
    pixel_clk_5x : in std_logic; -- must be 10x of pixel_clk

    -- Addressable video
    i_h_pic_size : in unsigned(num_bits(G_MAX_SIZE_X) - 1 downto 0);
    i_v_pic_size : in unsigned(num_bits(G_MAX_SIZE_Y) - 1 downto 0);

    -- Pixel data and handshaking signals
    o_pixel_ready : out std_logic;  -- Can only take data when 'ready' is high
    o_p_fifo_half : out std_logic;  -- Goes high when the pixel FIFO is half empty
    i_pixel_red   : in  unsigned(G_BITS_RED - 1 downto 0);
    i_pixel_green : in  unsigned(G_BITS_GREEN - 1 downto 0);
    i_pixel_blue  : in  unsigned(G_BITS_BLUE - 1 downto 0);
    i_pixel_dval  : in  std_logic;      -- Pixel data is valid

    -- Video signals
    i_frame_sync : in  std_logic;  -- Effectively resets the frame counters

    o_hdmi_channels : out std_logic_vector(2 downto 0);

    o_error : out std_logic
    );
end hdmi_driver;

architecture hdmi_driver_rtl of hdmi_driver is
  type t_tmds_channels is array (2 downto 0) of std_logic_vector(9 downto 0);
  -- The sequence for both horizontal and vertical is:
  --    front porch  sync  back porch   left/top border    picture     right/bottom border
  --  |-------------|----|------------|-----------------|------------|---------------------|
  --
  type t_video_state is (sync, pic);
  signal h_state    : t_video_state := sync;
  signal v_state_d1 : t_video_state := sync;
  signal h_state_d1 : t_video_state := sync;

  signal frame_start : std_logic := '0';

  signal h_pic_count : unsigned(num_bits(G_MAX_SIZE_X) - 1 downto 0) := (others => '0');
  signal v_pic_count : unsigned(num_bits(G_MAX_SIZE_Y) - 1 downto 0) := (others => '0');

  signal pixel_fifo_reset : std_logic;
  signal pixel_in_data    : std_logic_vector(G_BITS_RED + G_BITS_GREEN + G_BITS_BLUE - 1 downto 0);
  signal pixel_out_data   : std_logic_vector(G_BITS_RED + G_BITS_GREEN + G_BITS_BLUE - 1 downto 0);
  signal pixel_fifo_full  : std_logic;
  signal pixel_fifo_empty : std_logic;
  signal pic_valid_d1     : std_logic;
  signal pic_valid_d2     : std_logic;

  signal wr_error : std_logic;
  signal rd_error : std_logic;

  signal hs : std_logic;
  signal vs : std_logic;

  signal tmds_channels : t_tmds_channels;
begin

  ----------------------------------------------------------------------
  -- Assertion checks for correct input values
  -- pragma translate_off
  process
  begin
    wait for 10 ns;
    assert G_BITS_RED = 8 report "Colours must be 8 bit" severity error;
    assert G_BITS_GREEN = 8 report "Colours must be 8 bit" severity error;
    assert G_BITS_BLUE = 8 report "Colours must be 8 bit" severity error;
  end process;
  -- pragma translate_on


  ----------------------------------------------------------------------
  -- Horizontal state machine
  process (pixel_clk)
  begin
    if rising_edge(pixel_clk) then
      if i_frame_sync = '1' then
        h_state      <= sync;
        h_state_d1   <= sync;
      else
        case h_state is
          when sync =>
            h_state       <= pic;

          when pic =>
            if h_pic_count < i_h_pic_size then
              h_pic_count <= h_pic_count + 1;
            else
              h_state <= sync;
            end if;

          when others =>
            h_state <= sync;

        end case;

        h_state_d1 <= h_state;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------
  -- Vertical state machine
  process (pixel_clk)
  begin
    if rising_edge(pixel_clk) then
      if i_frame_sync = '1' then
        v_state_d1   <= sync;

        frame_start <= '0';
      else
        -- Assign a default value for 'frame_start' here
        frame_start <= '0';

        if h_state = sync then
          case v_state_d1 is
            when sync =>
              v_state_d1 <= pic;

            when pic =>
              if v_pic_count < i_v_pic_size then
                v_pic_count <= v_pic_count + 1;
              else
                v_state_d1 <= sync;
              end if;
          end case;
        end if;
      end if;
    end if;
  end process;


  ----------------------------------------------------------------------
  -- Generate strobes
  process (pixel_clk)
  begin
    if rising_edge(pixel_clk) then
      if h_state_d1 = sync then
        hs <= '1';
      else
        hs <= '0';
      end if;

      if v_state_d1 = sync then
        vs <= '1';
      else
        vs <= '0';
      end if;
    end if;
  end process;


  ----------------------------------------------------------------------
  -- Handle pixel input and output with a fifo
  -- Note: The FIFO gets reset at the start of each frame
  pixel_fifo_reset <= i_frame_sync or frame_start;

  pixel_in_data <= std_logic_vector(i_pixel_red) &
                   std_logic_vector(i_pixel_green) &
                   std_logic_vector(i_pixel_blue);

  pic_valid_d1 <= '1' when h_state_d1 = pic and v_state_d1 = pic
                  else '0';

  pixel_fifo : entity work.fifo_sync
    generic map (
      G_DATA_WIDTH => G_BITS_RED + G_BITS_GREEN + G_BITS_BLUE,
      G_LOG2_DEPTH => G_LOG2_PIXEL_FIFO_DEPTH,

      G_REGISTER_OUT => true,

      -- RAM styles:
      -- Xilinx: "block", "distributed", "registers" or "uram"
      -- Altera: "logic", "M512", "M4K", "M9K", "M20K", "M144K", "MLAB", or "M-RAM"
      -- Lattice: "registers", "distributed" or "block_ram"
      G_RAM_STYLE => "distributed")
    port map (
      -- Clock and Reset signals
      clk => pixel_clk,
      rst => pixel_fifo_reset,

      -- Write ports
      i_data        => pixel_in_data,
      i_wr_en       => i_pixel_dval,
      o_almost_full => open,
      o_full        => pixel_fifo_full,
      o_wr_error    => wr_error,

      -- Read ports
      o_almost_empty => open,
      o_empty        => pixel_fifo_empty,
      i_rd_en        => pic_valid_d1,
      o_data         => pixel_out_data,
      o_rd_error     => rd_error
      );

  ----------------------------------------------------------------------
  -- Register the outputs and hold the RGB output low when we're not
  -- within the addressable display area
  process (pixel_clk)
  begin
    if rising_edge(pixel_clk) then
      pic_valid_d2   <= pic_valid_d1;
    end if;
  end process;

  c0_tmds_encoder : entity work.tmds_encoder
   port map(
      clk => pixel_clk,
      rst => frame_start,

      i_data => pixel_out_data(G_BITS_RED + G_BITS_GREEN + G_BITS_BLUE - 1 downto G_BITS_RED + G_BITS_GREEN),

      i_control => hs & vs,
      i_video_en => pic_valid_d2,
      o_encoded => tmds_channels(0)
  );

  c1_tmds_encoder : entity work.tmds_encoder
   port map(
      clk => pixel_clk,
      rst => frame_start,

      i_data => pixel_out_data(G_BITS_RED + G_BITS_GREEN - 1 downto G_BITS_RED),
      i_control => "00",
      i_video_en => pic_valid_d2,
      o_encoded => tmds_channels(1)
  );

  c2_tmds_encoder : entity work.tmds_encoder
   port map(
      clk => pixel_clk,
      rst => frame_start,

      i_data => pixel_out_data(G_BITS_RED - 1 downto 0),
      i_control => "00",
      i_video_en => pic_valid_d2,
      o_encoded => tmds_channels(2)
  );

  g_seralizers : for i in 0 to 2 generate
    channel_seralizer : entity work.seralizer_10_1
    port map(
      clk => pixel_clk,
      clk_5x => pixel_clk_5x,
      rst => frame_start,
      
      i_data => tmds_channels(i),
      o_seralized => o_hdmi_channels(i)
    );
  end generate;

  o_pixel_ready <= not pixel_fifo_full;
  o_error       <= wr_error or rd_error;

end hdmi_driver_rtl;
