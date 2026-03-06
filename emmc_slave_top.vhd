library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity emmc_slave_top is
  port (
    clk_50MHz : in    std_logic;
    emmc_clk  : in    std_logic;
    emmc_cmd  : inout std_logic;
    emmc_dat0 : inout std_logic
  );
end entity;

architecture rtl of emmc_slave_top is
  type data_state_t is (IDLE, DATA_RX, CRC_RX);

  signal reset_50            : std_logic := '1';
  signal reset_cnt           : unsigned(5 downto 0) := (others => '0');
  signal reset_sync_0        : std_logic := '1';
  signal reset_sync_1        : std_logic := '1';

  signal cmd_in              : std_logic;
  signal cmd_out             : std_logic;
  signal cmd_oe              : std_logic;
  signal cmd23_seen          : std_logic;
  signal cmd25_seen          : std_logic;
  signal block_count         : std_logic_vector(15 downto 0);

  signal data_state          : data_state_t := IDLE;
  signal frame_active        : std_logic := '0';
  signal frame_done          : std_logic := '0';

  signal bit_count           : integer range 0 to 4095 := 0;
  signal crc_bit_count       : integer range 0 to 16 := 0;
  signal byte_shift          : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_in_byte         : integer range 0 to 7 := 0;
  signal rx_byte             : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_byte_valid       : std_logic := '0';

  signal key_programmed      : std_logic;
begin
  cmd_in <= emmc_cmd;
  emmc_cmd <= cmd_out when cmd_oe = '1' else 'Z';

  -- DAT0 is only sampled in this key-programming emulator; no data transmit path.
  emmc_dat0 <= 'Z';

  process (clk_50MHz)
  begin
    if rising_edge(clk_50MHz) then
      if reset_cnt = to_unsigned(63, reset_cnt'length) then
        reset_50 <= '0';
      else
        reset_cnt <= reset_cnt + 1;
        reset_50 <= '1';
      end if;
    end if;
  end process;

  process (emmc_clk)
  begin
    if rising_edge(emmc_clk) then
      reset_sync_0 <= reset_50;
      reset_sync_1 <= reset_sync_0;
    end if;
  end process;

  u_cmd_decoder : entity work.cmd_decoder
    port map (
      emmc_clk    => emmc_clk,
      reset       => reset_sync_1,
      cmd_in      => cmd_in,
      cmd_out     => cmd_out,
      cmd_oe      => cmd_oe,
      cmd23_seen  => cmd23_seen,
      cmd25_seen  => cmd25_seen,
      block_count => block_count
    );

  process (emmc_clk)
  begin
    if rising_edge(emmc_clk) then
      if reset_sync_1 = '1' then
        data_state    <= IDLE;
        frame_active  <= '0';
        frame_done    <= '0';
        bit_count     <= 0;
        crc_bit_count <= 0;
        byte_shift    <= (others => '0');
        bit_in_byte   <= 0;
        rx_byte       <= (others => '0');
        rx_byte_valid <= '0';
      else
        frame_done    <= '0';
        rx_byte_valid <= '0';

        case data_state is
          when IDLE =>
            frame_active <= '0';
            if cmd25_seen = '1' and unsigned(block_count) /= 0 then
              -- Wait for start bit on DAT0 for one 512-byte RPMB data frame.
              if emmc_dat0 = '0' then
                data_state   <= DATA_RX;
                frame_active <= '1';
                bit_count    <= 0;
                bit_in_byte  <= 0;
              end if;
            end if;

          when DATA_RX =>
            byte_shift <= byte_shift(6 downto 0) & emmc_dat0;

            if bit_in_byte = 7 then
              rx_byte <= byte_shift(6 downto 0) & emmc_dat0;
              rx_byte_valid <= '1';
              bit_in_byte <= 0;
            else
              bit_in_byte <= bit_in_byte + 1;
            end if;

            if bit_count = 4095 then
              data_state <= CRC_RX;
              crc_bit_count <= 0;
            else
              bit_count <= bit_count + 1;
            end if;

          when CRC_RX =>
            -- Skip 16 CRC bits and one trailing end bit from host.
            if crc_bit_count = 16 then
              frame_done   <= '1';
              frame_active <= '0';
              data_state   <= IDLE;
            else
              crc_bit_count <= crc_bit_count + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  u_rpmb_logic : entity work.rpmb_logic
    port map (
      clk            => emmc_clk,
      reset          => reset_sync_1,
      frame_active   => frame_active,
      byte_valid     => rx_byte_valid,
      byte_in        => rx_byte,
      frame_done     => frame_done,
      key_programmed => key_programmed
    );
end architecture;
