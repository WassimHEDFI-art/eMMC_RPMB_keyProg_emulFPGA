library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc_modules_pkg.all;

entity cmd_decoder is
  port (
    emmc_clk      : in  std_logic;
    reset         : in  std_logic;
    cmd_in        : in  std_logic;
    cmd_out       : out std_logic;
    cmd_oe        : out std_logic;
    cmd23_seen    : out std_logic;
    cmd25_seen    : out std_logic;
    cmd18_seen    : out std_logic;
    block_count   : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of cmd_decoder is
  type cmd_state_t is (IDLE, CMD_RX, RESP_TX);
  signal state          : cmd_state_t := IDLE;

  signal rx_shift       : std_logic_vector(47 downto 0) := (others => '1');
  signal rx_bit_cnt     : integer range 0 to 47 := 0;

  signal resp_shift     : std_logic_vector(47 downto 0) := (others => '1');
  signal resp_bit_cnt   : integer range 0 to 47 := 0;

  signal cmd_out_reg    : std_logic := '1';
  signal cmd_oe_reg     : std_logic := '0';

  signal cmd23_seen_reg : std_logic := '0';
  signal cmd25_seen_reg : std_logic := '0';
  signal cmd18_seen_reg : std_logic := '0';
  signal block_count_reg: std_logic_vector(15 downto 0) := (others => '0');

  signal r1_status      : std_logic_vector(31 downto 0) := (others => '0');
begin
  process (emmc_clk)
    variable cmd_index   : unsigned(5 downto 0);
    variable cmd_arg     : std_logic_vector(31 downto 0);
    variable cmd_frame   : std_logic_vector(47 downto 0);
    variable r1_header   : std_logic_vector(39 downto 0);
    variable r1_crc      : std_logic_vector(6 downto 0);
    variable r1_frame    : std_logic_vector(47 downto 0);
  begin
    if rising_edge(emmc_clk) then
      if reset = '1' then
        state           <= IDLE;
        rx_shift        <= (others => '1');
        rx_bit_cnt      <= 0;
        resp_shift      <= (others => '1');
        resp_bit_cnt    <= 0;
        cmd_out_reg     <= '1';
        cmd_oe_reg      <= '0';
        cmd23_seen_reg  <= '0';
        cmd25_seen_reg  <= '0';
        cmd18_seen_reg  <= '0';
        block_count_reg <= (others => '0');
        r1_status       <= (others => '0');
      else
        cmd23_seen_reg <= '0';
        cmd25_seen_reg <= '0';
        cmd18_seen_reg <= '0';

        case state is
          when IDLE =>
            cmd_oe_reg  <= '0';
            cmd_out_reg <= '1';
            if cmd_in = '0' then
              rx_shift <= (others => '0');
              rx_shift(47) <= cmd_in;
              rx_bit_cnt <= 1;
              state <= CMD_RX;
            end if;

          when CMD_RX =>
            cmd_frame := rx_shift(46 downto 0) & cmd_in;
            rx_shift <= cmd_frame;
            if rx_bit_cnt = 47 then
              cmd_index := unsigned(cmd_frame(45 downto 40));
              cmd_arg   := cmd_frame(39 downto 8);

              if cmd_index = to_unsigned(23, 6) then
                block_count_reg <= cmd_arg(15 downto 0);
                cmd23_seen_reg  <= '1';
              elsif cmd_index = to_unsigned(25, 6) then
                cmd25_seen_reg  <= '1';
              elsif cmd_index = to_unsigned(18, 6) then
                cmd18_seen_reg  <= '1';
              end if;

              r1_header(39)           := '0';
              r1_header(38)           := '0';
              r1_header(37 downto 32) := std_logic_vector(cmd_index);
              r1_header(31 downto 0)  := r1_status;

              r1_crc := crc7_calc(r1_header);

              r1_frame(47)            := '0';
              r1_frame(46)            := '0';
              r1_frame(45 downto 40)  := std_logic_vector(cmd_index);
              r1_frame(39 downto 8)   := r1_status;
              r1_frame(7 downto 1)    := r1_crc;
              r1_frame(0)             := '1';

              resp_shift   <= r1_frame;
              resp_bit_cnt <= 47;
              cmd_oe_reg   <= '1';
              cmd_out_reg  <= r1_frame(47);
              state        <= RESP_TX;
            else
              rx_bit_cnt <= rx_bit_cnt + 1;
            end if;

          when RESP_TX =>
            cmd_out_reg <= resp_shift(resp_bit_cnt);
            if resp_bit_cnt = 0 then
              cmd_oe_reg <= '0';
              cmd_out_reg <= '1';
              state <= IDLE;
            else
              resp_bit_cnt <= resp_bit_cnt - 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  cmd_out     <= cmd_out_reg;
  cmd_oe      <= cmd_oe_reg;
  cmd23_seen  <= cmd23_seen_reg;
  cmd25_seen  <= cmd25_seen_reg;
  cmd18_seen  <= cmd18_seen_reg;
  block_count <= block_count_reg;
end architecture;
