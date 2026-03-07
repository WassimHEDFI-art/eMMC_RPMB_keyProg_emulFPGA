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
  type dat_state_t is (IDLE, DATA_WAIT, DATA_TX, CRC_TX, END_BIT_TX);

  signal reset_50            : std_logic := '1';
  signal reset_cnt           : unsigned(5 downto 0) := (others => '0');
  signal reset_sync_0        : std_logic := '1';
  signal reset_sync_1        : std_logic := '1';

  signal cmd_in              : std_logic;
  signal cmd_out             : std_logic;
  signal cmd_oe              : std_logic;
  signal cmd1_seen           : std_logic;
  signal cmd8_seen           : std_logic;
  signal cmd1_seen_latched   : std_logic := '0';
  signal cmd8_seen_latched   : std_logic := '0';
  signal ext_csd_req_latched : std_logic := '0';
  signal dat_tx_active       : std_logic;
  signal ext_csd_read_req    : std_logic;

  signal dat_state           : dat_state_t := IDLE;
  signal dat0_out            : std_logic := '1';
  signal dat0_oe             : std_logic := '0';
  signal tx_frame            : std_logic_vector(4095 downto 0) := (others => '0');
  signal tx_crc16            : std_logic_vector(15 downto 0) := (others => '0');
  signal tx_bit_count        : integer range 0 to 4095 := 0;
  signal tx_crc_count        : integer range 0 to 15 := 0;
  signal wait_count          : integer range 0 to 31 := 0;
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

  u_cmd1_responder : entity work.cmd1_responder
    port map (
      emmc_clk    => emmc_clk,
      reset       => reset_sync_1,
      cmd_in      => cmd_in,
      cmd_out     => cmd_out,
      cmd_oe      => cmd_oe,
      cmd1_seen   => cmd1_seen,
      cmd8_seen   => cmd8_seen,
      ext_csd_read_req => ext_csd_read_req
    );

  process (emmc_clk)
    variable v_frame : std_logic_vector(4095 downto 0);
    variable v_crc16 : std_logic_vector(15 downto 0);
  begin
    if rising_edge(emmc_clk) then
      if reset_sync_1 = '1' then
        cmd1_seen_latched <= '0';
        cmd8_seen_latched <= '0';
        ext_csd_req_latched <= '0';
        dat_state         <= IDLE;
        dat0_out          <= '1';
        dat0_oe           <= '0';
        tx_frame          <= (others => '0');
        tx_crc16          <= (others => '0');
        tx_bit_count      <= 0;
        tx_crc_count      <= 0;
        wait_count        <= 0;
      else
        if cmd1_seen = '1' then
          cmd1_seen_latched <= '1';
        end if;
        if cmd8_seen = '1' then
          cmd8_seen_latched <= '1';
        end if;
        if ext_csd_read_req = '1' then
          ext_csd_req_latched <= '1';
        end if;

        case dat_state is
          when IDLE =>
            dat0_oe  <= '0';
            dat0_out <= '1';
            if ext_csd_read_req = '1' then
              v_frame := (others => '0');
              -- EXT_CSD key fields used by host bring-up.
              -- Byte 192: EXT_CSD_REV
              -- Byte 196: CARD_TYPE
              -- Bytes 212..215: SEC_COUNT (little-endian)
              v_frame((511 - 192) * 8 + 7 downto (511 - 192) * 8) := x"08";
              v_frame((511 - 196) * 8 + 7 downto (511 - 196) * 8) := x"01";
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
              wait_count   <= 0;
              dat_state    <= DATA_WAIT;
            end if;

          when DATA_WAIT =>
            dat0_oe  <= '0';
            dat0_out <= '1';
            if wait_count = 7 then
              dat0_oe      <= '1';
              dat0_out     <= '0';
              tx_bit_count <= 0;
              dat_state    <= DATA_TX;
            else
              wait_count <= wait_count + 1;
            end if;

          when DATA_TX =>
            dat0_oe  <= '1';
            dat0_out <= tx_frame(4095 - tx_bit_count);
            if tx_bit_count = 4095 then
              tx_crc_count <= 0;
              dat_state    <= CRC_TX;
            else
              tx_bit_count <= tx_bit_count + 1;
            end if;

          when CRC_TX =>
            dat0_oe  <= '1';
            dat0_out <= tx_crc16(15 - tx_crc_count);
            if tx_crc_count = 15 then
              dat_state <= END_BIT_TX;
            else
              tx_crc_count <= tx_crc_count + 1;
            end if;

          when END_BIT_TX =>
            dat0_oe  <= '1';
            dat0_out <= '1';
            dat_state <= IDLE;
        end case;
      end if;
    end if;
  end process;

  dat_tx_active <= '1' when dat_state /= IDLE else '0';

  ledr <= (9 downto 4 => '0')
    & dat_tx_active
    & ext_csd_req_latched
    & cmd8_seen_latched
    & cmd1_seen_latched;
  hex0 <= "1111111";
  hex1 <= "1111111";
  hex2 <= "1111111";
  hex3 <= "1111111";
  hex4 <= "1111111";
  hex5 <= "1111111";
end architecture;
