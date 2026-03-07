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
  type dat_state_t is (IDLE, TX_WAIT, TX_START, TX_DATA, TX_CRC, TX_END, RX_WAIT, RX_DATA, RX_CRC, RX_END);
  type tx_kind_t is (TX_NONE, TX_EXT_CSD, TX_RPMB);

  signal reset_50            : std_logic := '1';
  signal reset_cnt           : unsigned(5 downto 0) := (others => '0');
  signal reset_sync_0        : std_logic := '1';
  signal reset_sync_1        : std_logic := '1';

  signal cmd_in              : std_logic;
  signal dat0_in             : std_logic;
  signal cmd_out             : std_logic;
  signal cmd_oe              : std_logic;
  signal cmd1_seen           : std_logic;
  signal cmd8_seen           : std_logic;
  signal cmd23_seen          : std_logic;
  signal cmd25_seen          : std_logic;
  signal cmd18_seen          : std_logic;
  signal cmd23_reliable      : std_logic;
  signal block_count         : std_logic_vector(15 downto 0);
  signal cmd1_seen_latched   : std_logic := '0';
  signal cmd8_seen_latched   : std_logic := '0';
  signal ext_csd_req_latched : std_logic := '0';
  signal ext_csd_req_pending : std_logic := '0';
  signal cmd25_pending       : std_logic := '0';
  signal cmd18_pending       : std_logic := '0';
  signal dat_tx_active       : std_logic;
  signal ext_csd_read_req    : std_logic;
  signal ext_csd_power_class : std_logic_vector(7 downto 0);
  signal ext_csd_bus_width   : std_logic_vector(7 downto 0);
  signal ext_csd_hs_timing   : std_logic_vector(7 downto 0);

  signal dat_state           : dat_state_t := IDLE;
  signal dat0_out            : std_logic := '1';
  signal dat0_oe             : std_logic := '0';
  signal tx_kind             : tx_kind_t := TX_NONE;
  signal tx_frame            : std_logic_vector(4095 downto 0) := (others => '0');
  signal tx_crc16            : std_logic_vector(15 downto 0) := (others => '0');
  signal tx_bit_count        : integer range 0 to 4095 := 0;
  signal tx_crc_count        : integer range 0 to 15 := 0;
  signal rx_bit_count        : integer range 0 to 4095 := 0;
  signal rx_crc_count        : integer range 0 to 15 := 0;
  signal rx_subbit_count     : integer range 0 to 7 := 0;
  signal rx_byte_shift       : std_logic_vector(7 downto 0) := (others => '0');
  signal wait_count          : integer range 0 to 31 := 0;

  signal rpmb_frame_active   : std_logic;
  signal rpmb_byte_valid     : std_logic := '0';
  signal rpmb_byte_in        : std_logic_vector(7 downto 0) := (others => '0');
  signal rpmb_frame_done     : std_logic := '0';
  signal rpmb_consume_result : std_logic := '0';
  signal rpmb_key_programmed : std_logic;
  signal rpmb_programmed_key : std_logic_vector(255 downto 0);
  signal rpmb_result_ready   : std_logic;
  signal rpmb_result_code    : std_logic_vector(15 downto 0);
  signal rpmb_resp_type      : std_logic_vector(15 downto 0);
  signal rpmb_req_type_last  : std_logic_vector(15 downto 0);
  signal write_xfer_done     : std_logic := '0';
  signal read_xfer_done      : std_logic := '0';
begin
  cmd_in <= emmc_cmd;
  dat0_in <= emmc_dat0;
  emmc_cmd <= cmd_out when cmd_oe = '1' else 'Z';

  emmc_dat0 <= dat0_out when dat0_oe = '1' else 'Z';

  rpmb_frame_active <= '1' when (dat_state = RX_WAIT) or (dat_state = RX_DATA) or (dat_state = RX_CRC) or (dat_state = RX_END) else '0';

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

  u_cmd1_responder : entity work.cmd1_responder
    port map (
      emmc_clk    => emmc_clk,
      reset       => reset_sync_1,
      cmd_in      => cmd_in,
      cmd_out     => cmd_out,
      cmd_oe      => cmd_oe,
      cmd1_seen   => cmd1_seen,
      cmd8_seen   => cmd8_seen,
      cmd23_seen  => cmd23_seen,
      cmd25_seen  => cmd25_seen,
      cmd18_seen  => cmd18_seen,
      cmd23_reliable => cmd23_reliable,
      block_count => block_count,
      write_xfer_done => write_xfer_done,
      read_xfer_done  => read_xfer_done,
      ext_csd_read_req => ext_csd_read_req,
      ext_csd_power_class => ext_csd_power_class,
      ext_csd_bus_width   => ext_csd_bus_width,
      ext_csd_hs_timing   => ext_csd_hs_timing
    );

  u_rpmb_logic : entity work.rpmb_logic
    port map (
      clk            => emmc_clk,
      reset          => reset_sync_1,
      frame_active   => rpmb_frame_active,
      byte_valid     => rpmb_byte_valid,
      byte_in        => rpmb_byte_in,
      frame_done     => rpmb_frame_done,
      cmd23_reliable => cmd23_reliable,
      data_only_mode => '0',
      consume_result => rpmb_consume_result,
      key_programmed => rpmb_key_programmed,
      programmed_key => rpmb_programmed_key,
      result_ready   => rpmb_result_ready,
      result_code    => rpmb_result_code,
      resp_type      => rpmb_resp_type,
      req_type_last  => rpmb_req_type_last
    );

  u_key_display_7seg : entity work.key_display_7seg
    port map (
      clk            => clk_50MHz,
      reset          => reset_50,
      key_programmed => rpmb_key_programmed,
      key_value      => rpmb_programmed_key,
      btn_next       => btn_next,
      btn_restart    => btn_restart,
      hex0           => hex0,
      hex1           => hex1,
      hex2           => hex2,
      hex3           => hex3,
      hex4           => hex4,
      hex5           => hex5
    );

  process (emmc_clk)
    variable v_frame : std_logic_vector(4095 downto 0);
    variable v_crc16 : std_logic_vector(15 downto 0);
    variable v_byte  : std_logic_vector(7 downto 0);
  begin
    if rising_edge(emmc_clk) then
      if reset_sync_1 = '1' then
        cmd1_seen_latched <= '0';
        cmd8_seen_latched <= '0';
        ext_csd_req_latched <= '0';
        ext_csd_req_pending <= '0';
        cmd25_pending     <= '0';
        cmd18_pending     <= '0';
        dat_state         <= IDLE;
        dat0_out          <= '1';
        dat0_oe           <= '0';
        tx_kind           <= TX_NONE;
        tx_frame          <= (others => '0');
        tx_crc16          <= (others => '0');
        tx_bit_count      <= 0;
        tx_crc_count      <= 0;
        rx_bit_count      <= 0;
        rx_crc_count      <= 0;
        rx_subbit_count   <= 0;
        rx_byte_shift     <= (others => '0');
        wait_count        <= 0;
        rpmb_byte_valid   <= '0';
        rpmb_byte_in      <= (others => '0');
        rpmb_frame_done   <= '0';
        rpmb_consume_result <= '0';
      else
        rpmb_byte_valid <= '0';
        rpmb_frame_done <= '0';
        rpmb_consume_result <= '0';
        write_xfer_done   <= '0';
        read_xfer_done    <= '0';

        if cmd1_seen = '1' then
          cmd1_seen_latched <= '1';
        end if;
        write_xfer_done <= '0';
        read_xfer_done  <= '0';
        if cmd8_seen = '1' then
          cmd8_seen_latched <= '1';
        end if;
        if ext_csd_read_req = '1' then
          ext_csd_req_latched <= '1';
          ext_csd_req_pending <= '1';
        end if;
        if cmd25_seen = '1' then
          cmd25_pending <= '1';
        end if;
        if cmd18_seen = '1' then
          cmd18_pending <= '1';
        end if;

        case dat_state is
          when IDLE =>
            dat0_oe  <= '0';
            dat0_out <= '1';
            if (ext_csd_req_pending = '1') and (cmd_oe = '0') then
              v_frame := (others => '0');
              -- EXT_CSD key fields used by host bring-up.
              -- Byte 183: BUS_WIDTH
              -- Byte 185: HS_TIMING
              -- Byte 187: POWER_CLASS
              -- Byte 192: EXT_CSD_REV
              -- Byte 196: CARD_TYPE
              -- Byte 202/203/239: supported power-class fields
              -- Bytes 212..215: SEC_COUNT (little-endian)
              v_frame((511 - 183) * 8 + 7 downto (511 - 183) * 8) := ext_csd_bus_width;
              v_frame((511 - 185) * 8 + 7 downto (511 - 185) * 8) := ext_csd_hs_timing;
              v_frame((511 - 187) * 8 + 7 downto (511 - 187) * 8) := ext_csd_power_class;
              v_frame((511 - 192) * 8 + 7 downto (511 - 192) * 8) := x"08";
              v_frame((511 - 196) * 8 + 7 downto (511 - 196) * 8) := x"01";
              v_frame((511 - 202) * 8 + 7 downto (511 - 202) * 8) := x"00";
              v_frame((511 - 203) * 8 + 7 downto (511 - 203) * 8) := x"00";
              v_frame((511 - 239) * 8 + 7 downto (511 - 239) * 8) := x"00";
              v_frame((511 - 212) * 8 + 7 downto (511 - 212) * 8) := x"00";
              v_frame((511 - 213) * 8 + 7 downto (511 - 213) * 8) := x"00";
              v_frame((511 - 214) * 8 + 7 downto (511 - 214) * 8) := x"01";
              v_frame((511 - 215) * 8 + 7 downto (511 - 215) * 8) := x"00";
              tx_frame <= v_frame;

              v_crc16 := (others => '0');
              for i in 0 to 4095 loop
                v_crc16 := crc16_next(v_crc16, v_frame(4095 - i));
              end loop;
              tx_crc16     <= v_crc16;
              tx_kind      <= TX_EXT_CSD;
              wait_count   <= 0;
              ext_csd_req_pending <= '0';
              dat_state    <= TX_WAIT;
            elsif (cmd25_pending = '1') and (block_count = x"0001") and (cmd_oe = '0') then
              cmd25_pending   <= '0';
              rx_bit_count    <= 0;
              rx_crc_count    <= 0;
              rx_subbit_count <= 0;
              rx_byte_shift   <= (others => '0');
              dat_state       <= RX_WAIT;
            elsif (cmd18_pending = '1') and (block_count = x"0001") and (rpmb_result_ready = '1') and (cmd_oe = '0') then
              v_frame := (others => '0');
              v_frame((511 - 508) * 8 + 7 downto (511 - 508) * 8) := rpmb_result_code(15 downto 8);
              v_frame((511 - 509) * 8 + 7 downto (511 - 509) * 8) := rpmb_result_code(7 downto 0);
              v_frame((511 - 510) * 8 + 7 downto (511 - 510) * 8) := rpmb_resp_type(15 downto 8);
              v_frame((511 - 511) * 8 + 7 downto (511 - 511) * 8) := rpmb_resp_type(7 downto 0);
              tx_frame <= v_frame;

              v_crc16 := (others => '0');
              for i in 0 to 4095 loop
                v_crc16 := crc16_next(v_crc16, v_frame(4095 - i));
              end loop;
              tx_crc16     <= v_crc16;
              tx_kind      <= TX_RPMB;
              wait_count   <= 0;
              cmd18_pending <= '0';
              dat_state    <= TX_WAIT;
            end if;

          when TX_WAIT =>
            dat0_oe  <= '0';
            dat0_out <= '1';
            if wait_count = 7 then
              tx_bit_count <= 0;
              dat_state    <= TX_START;
            else
              wait_count <= wait_count + 1;
            end if;

          when TX_START =>
            dat0_oe      <= '1';
            dat0_out     <= '0';
            dat_state    <= TX_DATA;

          when TX_DATA =>
            dat0_oe  <= '1';
            dat0_out <= tx_frame(4095 - tx_bit_count);
            if tx_bit_count = 4095 then
              tx_crc_count <= 0;
              dat_state    <= TX_CRC;
            else
              tx_bit_count <= tx_bit_count + 1;
            end if;

          when TX_CRC =>
            dat0_oe  <= '1';
            dat0_out <= tx_crc16(15 - tx_crc_count);
            if tx_crc_count = 15 then
              dat_state <= TX_END;
            else
              tx_crc_count <= tx_crc_count + 1;
            end if;

          when TX_END =>
            dat0_oe  <= '1';
            dat0_out <= '1';
            if tx_kind = TX_RPMB then
              rpmb_consume_result <= '1';
              read_xfer_done <= '1';
            end if;
            tx_kind   <= TX_NONE;
            dat_state <= IDLE;

          when RX_WAIT =>
            dat0_oe  <= '0';
            dat0_out <= '1';
            if dat0_in = '0' then
              rx_bit_count    <= 0;
              rx_subbit_count <= 0;
              rx_byte_shift   <= (others => '0');
              dat_state       <= RX_DATA;
            end if;

          when RX_DATA =>
            dat0_oe  <= '0';
            dat0_out <= '1';

            v_byte := rx_byte_shift;
            v_byte(7 - rx_subbit_count) := dat0_in;
            rx_byte_shift <= v_byte;

            if rx_subbit_count = 7 then
              rpmb_byte_in    <= v_byte;
              rpmb_byte_valid <= '1';
              rx_subbit_count <= 0;
            else
              rx_subbit_count <= rx_subbit_count + 1;
            end if;

            if rx_bit_count = 4095 then
              rx_crc_count <= 0;
              dat_state    <= RX_CRC;
            else
              rx_bit_count <= rx_bit_count + 1;
            end if;

          when RX_CRC =>
            dat0_oe  <= '0';
            dat0_out <= '1';
            if rx_crc_count = 15 then
              dat_state <= RX_END;
            else
              rx_crc_count <= rx_crc_count + 1;
            end if;

          when RX_END =>
            dat0_oe  <= '0';
            dat0_out <= '1';
            rpmb_frame_done <= '1';
            write_xfer_done <= '1';
            dat_state <= IDLE;
        end case;
      end if;
    end if;
  end process;

  dat_tx_active <= '1' when (dat_state = TX_WAIT) or (dat_state = TX_START) or (dat_state = TX_DATA) or (dat_state = TX_CRC) or (dat_state = TX_END) else '0';

  ledr <= (9 downto 5 => '0')
    & rpmb_key_programmed
    & dat_tx_active
    & ext_csd_req_latched
    & cmd8_seen_latched
    & cmd1_seen_latched;
end architecture;
