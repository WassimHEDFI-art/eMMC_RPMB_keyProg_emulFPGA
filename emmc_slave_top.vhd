library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc_modules_pkg.all;

entity emmc_slave_top is
  port (
    clk_50MHz : in    std_logic;
    emmc_clk  : in    std_logic;
    emmc_cmd  : inout std_logic;
    emmc_dat0 : inout std_logic;
    btn_next  : in    std_logic;
    btn_restart : in  std_logic;
    ledr      : out   std_logic_vector(9 downto 0);
    hex0      : out   std_logic_vector(6 downto 0);
    hex1      : out   std_logic_vector(6 downto 0);
    hex2      : out   std_logic_vector(6 downto 0);
    hex3      : out   std_logic_vector(6 downto 0);
    hex4      : out   std_logic_vector(6 downto 0);
    hex5      : out   std_logic_vector(6 downto 0)
  );
end entity;

architecture rtl of emmc_slave_top is
  type data_state_t is (IDLE, DATA_RX, CRC_RX, WRITE_BUSY, DATA_TX, CRC_TX, END_BIT_TX);
  constant C_DATA_ONLY_MODE : std_logic := '1';

  signal reset_50            : std_logic := '1';
  signal reset_cnt           : unsigned(5 downto 0) := (others => '0');
  signal reset_sync_0        : std_logic := '1';
  signal reset_sync_1        : std_logic := '1';

  signal cmd_in              : std_logic;
  signal cmd_out             : std_logic;
  signal cmd_oe              : std_logic;
  signal cmd23_seen          : std_logic;
  signal cmd25_seen          : std_logic;
  signal cmd18_seen          : std_logic;
  signal cmd23_reliable      : std_logic;
  signal block_count         : std_logic_vector(15 downto 0);
  signal cmd25_pending       : std_logic := '0';
  signal cmd18_pending       : std_logic := '0';

  signal data_state          : data_state_t := IDLE;
  signal frame_active        : std_logic := '0';
  signal frame_done          : std_logic := '0';

  signal bit_count           : integer range 0 to 4095 := 0;
  signal crc_bit_count       : integer range 0 to 16 := 0;
  signal byte_shift          : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_in_byte         : integer range 0 to 7 := 0;
  signal rx_byte             : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_byte_valid       : std_logic := '0';

  signal tx_frame            : std_logic_vector(4095 downto 0) := (others => '0');
  signal tx_crc16            : std_logic_vector(15 downto 0) := (others => '0');
  signal dat0_out            : std_logic := '1';
  signal dat0_oe             : std_logic := '0';

  signal consume_result      : std_logic := '0';
  signal busy_count          : integer range 0 to 63 := 0;

  signal key_programmed      : std_logic;
  signal result_ready        : std_logic;
  signal result_code         : std_logic_vector(15 downto 0);
  signal resp_type           : std_logic_vector(15 downto 0);
  signal req_type_last       : std_logic_vector(15 downto 0);
  signal programmed_key      : std_logic_vector(255 downto 0);
begin
  cmd_in <= emmc_cmd;
  emmc_cmd <= cmd_out when cmd_oe = '1' else 'Z';

  emmc_dat0 <= dat0_out when dat0_oe = '1' else 'Z';

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
      cmd18_seen  => cmd18_seen,
      cmd23_reliable => cmd23_reliable,
      block_count => block_count
    );

  process (emmc_clk)
    variable v_frame : std_logic_vector(4095 downto 0);
    variable v_crc16 : std_logic_vector(15 downto 0);
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
        cmd25_pending <= '0';
        cmd18_pending <= '0';
        tx_frame      <= (others => '0');
        tx_crc16      <= (others => '0');
        dat0_out      <= '1';
        dat0_oe       <= '0';
        consume_result <= '0';
        busy_count    <= 0;
      else
        frame_done    <= '0';
        rx_byte_valid <= '0';
        consume_result <= '0';

        if cmd25_seen = '1' then
          if unsigned(block_count) = 1 then
            cmd25_pending <= '1';
          else
            cmd25_pending <= '0';
          end if;
        end if;

        if cmd18_seen = '1' then
          if unsigned(block_count) = 1 then
            cmd18_pending <= '1';
          else
            cmd18_pending <= '0';
          end if;
        end if;

        case data_state is
          when IDLE =>
            frame_active <= '0';
            dat0_oe <= '0';
            dat0_out <= '1';

            if C_DATA_ONLY_MODE = '1' then
              -- Bring-up mode: capture one full 512-byte frame directly from DAT0.
              if emmc_dat0 = '0' then
                data_state   <= DATA_RX;
                frame_active <= '1';
                bit_count    <= 0;
                bit_in_byte  <= 0;
              end if;
            elsif cmd25_pending = '1' and unsigned(block_count) = 1 then
              -- Normal mode: wait for DAT0 data-start after valid CMD25 sequence.
              if emmc_dat0 = '0' then
                data_state    <= DATA_RX;
                frame_active  <= '1';
                bit_count     <= 0;
                bit_in_byte   <= 0;
                cmd25_pending <= '0';
              end if;
            elsif cmd18_pending = '1' and result_ready = '1' and req_type_last = x"0005" and unsigned(block_count) = 1 then
              -- Build one 512-byte result response frame (mostly zero).
              -- Tail bytes [508..509] = Result code (MSB first)
              -- Tail bytes [510..511] = Response type (MSB first)
              v_frame := (others => '0');
              v_frame((511 - 508) * 8 + 7 downto (511 - 508) * 8) := result_code(15 downto 8);
              v_frame((511 - 509) * 8 + 7 downto (511 - 509) * 8) := result_code(7 downto 0);
              v_frame((511 - 510) * 8 + 7 downto (511 - 510) * 8) := resp_type(15 downto 8);
              v_frame((511 - 511) * 8 + 7 downto (511 - 511) * 8) := resp_type(7 downto 0);
              tx_frame <= v_frame;

              -- Compute CRC16 over the 4096 data bits.
              v_crc16 := (others => '0');
              for i in 0 to 4095 loop
                v_crc16 := crc16_next(v_crc16, v_frame(4095 - i));
              end loop;
              tx_crc16 <= v_crc16;

              data_state    <= DATA_TX;
              bit_count     <= 0;
              dat0_oe       <= '1';
              dat0_out      <= '0'; -- data start bit
              cmd18_pending <= '0';
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
            -- Ignore 16 CRC bits and one trailing end bit from host.
            if crc_bit_count = 16 then
              frame_done   <= '1';
              frame_active <= '0';
              data_state   <= WRITE_BUSY;
              busy_count   <= 0;
            else
              crc_bit_count <= crc_bit_count + 1;
            end if;

          when WRITE_BUSY =>
            -- DAT0 busy indication after host write frame (programming/request busy).
            dat0_oe  <= '1';
            dat0_out <= '0';
            if busy_count = 31 then
              dat0_oe    <= '0';
              dat0_out   <= '1';
              data_state <= IDLE;
            else
              busy_count <= busy_count + 1;
            end if;

          when DATA_TX =>
            dat0_oe  <= '1';
            dat0_out <= tx_frame(4095 - bit_count);
            if bit_count = 4095 then
              data_state    <= CRC_TX;
              crc_bit_count <= 0;
            else
              bit_count <= bit_count + 1;
            end if;

          when CRC_TX =>
            dat0_oe  <= '1';
            dat0_out <= tx_crc16(15 - crc_bit_count);
            if crc_bit_count = 15 then
              data_state <= END_BIT_TX;
            else
              crc_bit_count <= crc_bit_count + 1;
            end if;

          when END_BIT_TX =>
            dat0_oe        <= '1';
            dat0_out       <= '1';
            consume_result <= '1';
            data_state     <= IDLE;
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
      cmd23_reliable => cmd23_reliable,
      data_only_mode => C_DATA_ONLY_MODE,
      consume_result => consume_result,
      key_programmed => key_programmed,
      programmed_key => programmed_key,
      result_ready   => result_ready,
      result_code    => result_code,
      resp_type      => resp_type,
      req_type_last  => req_type_last
    );

  u_led_status : entity work.led_status
    port map (
      clk            => clk_50MHz,
      reset          => reset_50,
      key_programmed => key_programmed,
      btn_restart    => not btn_restart,
      leds           => ledr
    );

  u_key_display_7seg : entity work.key_display_7seg
    port map (
      clk            => clk_50MHz,
      reset          => reset_50,
      key_programmed => key_programmed,
      key_value      => programmed_key,
      btn_next       => not btn_next,
      btn_restart    => not btn_restart,
      hex0           => hex0,
      hex1           => hex1,
      hex2           => hex2,
      hex3           => hex3,
      hex4           => hex4,
      hex5           => hex5
    );
end architecture;
