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
    cmd1_seen : out std_logic;
    ext_csd_read_req : out std_logic
  );
end entity;

architecture rtl of cmd1_responder is
  type state_t is (IDLE, CMD_RX, RESP_TX);

  constant C_OCR_RESPONSE : std_logic_vector(31 downto 0) := x"C0FF8000";
  constant C_CID_PAYLOAD  : std_logic_vector(119 downto 0) := x"134650474131123456789ABCDEF240";
  constant C_CSD_PAYLOAD  : std_logic_vector(119 downto 0) := x"400E00325B590000123456789ABCDE";
  constant C_R1_STATUS    : std_logic_vector(31 downto 0) := x"00000900";

  signal state         : state_t := IDLE;
  signal rx_shift      : std_logic_vector(47 downto 0) := (others => '1');
  signal rx_cnt        : integer range 0 to 47 := 0;

  signal resp_shift    : std_logic_vector(135 downto 0) := (others => '1');
  signal resp_cnt      : integer range 0 to 135 := 0;

  signal cmd_out_reg   : std_logic := '1';
  signal cmd_oe_reg    : std_logic := '0';
  signal cmd1_seen_reg : std_logic := '0';
  signal ext_csd_read_req_reg : std_logic := '0';

  function crc7_any(data : std_logic_vector) return std_logic_vector is
    variable crc : std_logic_vector(6 downto 0) := (others => '0');
    variable fb  : std_logic;
  begin
    for i in data'range loop
      fb := data(i) xor crc(6);
      crc(6) := crc(5);
      crc(5) := crc(4);
      crc(4) := crc(3);
      crc(3) := crc(2) xor fb;
      crc(2) := crc(1);
      crc(1) := crc(0);
      crc(0) := fb;
    end loop;
    return crc;
  end function;
begin
  process (emmc_clk)
    variable cmd_frame : std_logic_vector(47 downto 0);
    variable cmd_index : unsigned(5 downto 0);
    variable cmd_arg   : std_logic_vector(31 downto 0);
    variable resp48    : std_logic_vector(47 downto 0);
    variable resp136   : std_logic_vector(135 downto 0);
    variable cid_reg   : std_logic_vector(127 downto 0);
    variable cid_crc   : std_logic_vector(6 downto 0);
    variable csd_reg   : std_logic_vector(127 downto 0);
    variable csd_crc   : std_logic_vector(6 downto 0);
    variable r1_header : std_logic_vector(39 downto 0);
    variable r1_crc    : std_logic_vector(6 downto 0);
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
        ext_csd_read_req_reg <= '0';
      else
        cmd1_seen_reg <= '0';
        ext_csd_read_req_reg <= '0';

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
              cmd_arg   := cmd_frame(39 downto 8);

              if cmd_index = to_unsigned(1, 6) then
                resp48 := (others => '1');
                resp48(47) := '0';
                resp48(46) := '0';
                resp48(45 downto 40) := (others => '0');
                resp48(39 downto 8)  := C_OCR_RESPONSE;
                resp48(7 downto 1)   := (others => '1');
                resp48(0)            := '1';

                resp_shift            <= (others => '1');
                resp_shift(47 downto 0) <= resp48;
                cmd_oe_reg    <= '1';
                cmd_out_reg   <= resp48(47);
                resp_cnt      <= 46;
                cmd1_seen_reg <= '1';
                state         <= RESP_TX;
              elsif cmd_index = to_unsigned(2, 6) then
                cid_crc := crc7_any(C_CID_PAYLOAD);
                cid_reg := C_CID_PAYLOAD & cid_crc & '1';

                resp136 := (others => '1');
                resp136(135) := '0';
                resp136(134) := '0';
                resp136(133 downto 128) := (others => '1');
                resp136(127 downto 0) := cid_reg;

                resp_shift  <= resp136;
                cmd_oe_reg  <= '1';
                cmd_out_reg <= resp136(135);
                resp_cnt    <= 134;
                state       <= RESP_TX;
              elsif cmd_index = to_unsigned(3, 6) then
                -- MMC CMD3: host assigns RCA through the command argument.
                -- For bring-up, accept the provided RCA and return a normal R1 status.
                r1_header(39)           := '0';
                r1_header(38)           := '0';
                r1_header(37 downto 32) := std_logic_vector(cmd_index);
                r1_header(31 downto 0)  := C_R1_STATUS;
                r1_crc := crc7_any(r1_header);

                resp48 := (others => '1');
                resp48(47) := '0';
                resp48(46) := '0';
                resp48(45 downto 40) := std_logic_vector(cmd_index);
                resp48(39 downto 8)  := C_R1_STATUS;
                resp48(7 downto 1)   := r1_crc;
                resp48(0)            := '1';

                resp_shift              <= (others => '1');
                resp_shift(47 downto 0) <= resp48;
                cmd_oe_reg              <= '1';
                cmd_out_reg             <= resp48(47);
                resp_cnt                <= 46;
                state                   <= RESP_TX;
              elsif cmd_index = to_unsigned(9, 6) then
                csd_crc := crc7_any(C_CSD_PAYLOAD);
                csd_reg := C_CSD_PAYLOAD & csd_crc & '1';

                resp136 := (others => '1');
                resp136(135) := '0';
                resp136(134) := '0';
                resp136(133 downto 128) := (others => '1');
                resp136(127 downto 0) := csd_reg;

                resp_shift  <= resp136;
                cmd_oe_reg  <= '1';
                cmd_out_reg <= resp136(135);
                resp_cnt    <= 134;
                state       <= RESP_TX;
              elsif cmd_index = to_unsigned(13, 6) then
                r1_header(39)           := '0';
                r1_header(38)           := '0';
                r1_header(37 downto 32) := std_logic_vector(cmd_index);
                r1_header(31 downto 0)  := C_R1_STATUS;
                r1_crc := crc7_any(r1_header);

                resp48 := (others => '1');
                resp48(47) := '0';
                resp48(46) := '0';
                resp48(45 downto 40) := std_logic_vector(cmd_index);
                resp48(39 downto 8)  := C_R1_STATUS;
                resp48(7 downto 1)   := r1_crc;
                resp48(0)            := '1';

                resp_shift              <= (others => '1');
                resp_shift(47 downto 0) <= resp48;
                cmd_oe_reg              <= '1';
                cmd_out_reg             <= resp48(47);
                resp_cnt                <= 46;
                state                   <= RESP_TX;
              elsif cmd_index = to_unsigned(8, 6) then
                r1_header(39)           := '0';
                r1_header(38)           := '0';
                r1_header(37 downto 32) := std_logic_vector(cmd_index);
                r1_header(31 downto 0)  := C_R1_STATUS;
                r1_crc := crc7_any(r1_header);

                resp48 := (others => '1');
                resp48(47) := '0';
                resp48(46) := '0';
                resp48(45 downto 40) := std_logic_vector(cmd_index);
                resp48(39 downto 8)  := C_R1_STATUS;
                resp48(7 downto 1)   := r1_crc;
                resp48(0)            := '1';

                resp_shift              <= (others => '1');
                resp_shift(47 downto 0) <= resp48;
                cmd_oe_reg              <= '1';
                cmd_out_reg             <= resp48(47);
                resp_cnt                <= 46;
                ext_csd_read_req_reg    <= '1';
                state                   <= RESP_TX;
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
  ext_csd_read_req <= ext_csd_read_req_reg;
end architecture;
