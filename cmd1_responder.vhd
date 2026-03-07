library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cmd1_responder is
  port (
    emmc_clk  : in  std_logic;
    reset     : in  std_logic;
    cmd_in    : in  std_logic;
    cmd_out   : out std_logic;
    cmd_oe    : out std_logic;
    cmd1_seen : out std_logic
  );
end entity;

architecture rtl of cmd1_responder is
  type state_t is (IDLE, CMD_RX, RESP_TX);

  constant C_OCR_RESPONSE : std_logic_vector(31 downto 0) := x"C0FF8000";

  signal state         : state_t := IDLE;
  signal rx_shift      : std_logic_vector(47 downto 0) := (others => '1');
  signal rx_cnt        : integer range 0 to 47 := 0;

  signal resp_shift    : std_logic_vector(47 downto 0) := (others => '1');
  signal resp_cnt      : integer range 0 to 47 := 0;

  signal cmd_out_reg   : std_logic := '1';
  signal cmd_oe_reg    : std_logic := '0';
  signal cmd1_seen_reg : std_logic := '0';
begin
  process (emmc_clk)
    variable cmd_frame : std_logic_vector(47 downto 0);
    variable cmd_index : unsigned(5 downto 0);
    variable resp      : std_logic_vector(47 downto 0);
  begin
    if rising_edge(emmc_clk) then
      if reset = '1' then
        state         <= IDLE;
        rx_shift      <= (others => '1');
        rx_cnt        <= 0;
        resp_shift    <= (others => '1');
        resp_cnt      <= 0;
        cmd_out_reg   <= '1';
        cmd_oe_reg    <= '0';
        cmd1_seen_reg <= '0';
      else
        cmd1_seen_reg <= '0';

        case state is
          when IDLE =>
            cmd_oe_reg  <= '0';
            cmd_out_reg <= '1';

            if cmd_in = '0' then
              rx_shift <= (others => '0');
              rx_shift(47) <= '0';
              rx_cnt   <= 1;
              state    <= CMD_RX;
            end if;

          when CMD_RX =>
            cmd_frame := rx_shift;
            cmd_frame(47 - rx_cnt) := cmd_in;
            rx_shift <= cmd_frame;

            if rx_cnt = 47 then
              cmd_index := unsigned(cmd_frame(45 downto 40));

              if cmd_index = to_unsigned(1, 6) then
                resp := (others => '1');
                resp(47) := '0';
                resp(46) := '0';
                resp(45 downto 40) := (others => '0');
                resp(39 downto 8)  := C_OCR_RESPONSE;
                resp(7 downto 1)   := (others => '1');
                resp(0)            := '1';

                resp_shift    <= resp;
                cmd_oe_reg    <= '1';
                cmd_out_reg   <= resp(47);
                resp_cnt      <= 46;
                cmd1_seen_reg <= '1';
                state         <= RESP_TX;
              else
                state <= IDLE;
              end if;
            else
              rx_cnt <= rx_cnt + 1;
            end if;

          when RESP_TX =>
            cmd_out_reg <= resp_shift(resp_cnt);

            if resp_cnt = 0 then
              cmd_oe_reg  <= '0';
              cmd_out_reg <= '1';
              state       <= IDLE;
            else
              resp_cnt <= resp_cnt - 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  cmd_out   <= cmd_out_reg;
  cmd_oe    <= cmd_oe_reg;
  cmd1_seen <= cmd1_seen_reg;
end architecture;
