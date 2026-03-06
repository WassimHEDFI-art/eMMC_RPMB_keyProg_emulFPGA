library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rpmb_logic is
  port (
    clk            : in  std_logic;
    reset          : in  std_logic;
    frame_active   : in  std_logic;
    byte_valid     : in  std_logic;
    byte_in        : in  std_logic_vector(7 downto 0);
    frame_done     : in  std_logic;
    cmd23_reliable : in  std_logic;
    consume_result : in  std_logic;
    key_programmed : out std_logic;
    programmed_key : out std_logic_vector(255 downto 0);
    result_ready   : out std_logic;
    result_code    : out std_logic_vector(15 downto 0);
    resp_type      : out std_logic_vector(15 downto 0);
    req_type_last  : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of rpmb_logic is
  type rpmb_state_t is (IDLE, DATA_RX);
  signal state              : rpmb_state_t := IDLE;

  signal byte_index         : integer range 0 to 511 := 0;

  signal key_shadow         : std_logic_vector(255 downto 0) := (others => '0');
  signal otp_key            : std_logic_vector(255 downto 0) := (others => '0');
  signal key_programmed_reg : std_logic := '0';
  signal request_type       : std_logic_vector(15 downto 0) := (others => '0');
  signal result_ready_reg   : std_logic := '0';
  signal result_code_reg    : std_logic_vector(15 downto 0) := (others => '0');
  signal resp_type_reg      : std_logic_vector(15 downto 0) := (others => '0');
  signal req_type_last_reg  : std_logic_vector(15 downto 0) := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        state              <= IDLE;
        byte_index         <= 0;
        key_shadow         <= (others => '0');
        otp_key            <= (others => '0');
        key_programmed_reg <= '0';
        request_type       <= (others => '0');
        result_ready_reg   <= '0';
        result_code_reg    <= (others => '0');
        resp_type_reg      <= (others => '0');
        req_type_last_reg  <= (others => '0');
      else
        if consume_result = '1' then
          result_ready_reg <= '0';
        end if;

        case state is
          when IDLE =>
            byte_index   <= 0;
            request_type <= (others => '0');
            if frame_active = '1' then
              state <= DATA_RX;
            end if;

          when DATA_RX =>
            if byte_valid = '1' then
              -- RPMB frame byte layout (512 bytes):
              -- [0..195]   Stuff bytes
              -- [196..227] Authentication Key / MAC field (32 bytes)
              -- [228..483] Data field (256 bytes)
              -- [484..499] Nonce (16 bytes)
              -- [500..503] Write Counter (4 bytes)
              -- [504..505] Address (2 bytes)
              -- [506..507] Block Count (2 bytes)
              -- [508..509] Result (2 bytes)
              -- [510..511] Request/Response Type (2 bytes)

              if (byte_index >= 196) and (byte_index <= 227) then
                key_shadow((227 - byte_index) * 8 + 7 downto (227 - byte_index) * 8) <= byte_in;
              elsif byte_index = 510 then
                request_type(15 downto 8) <= byte_in;
              elsif byte_index = 511 then
                request_type(7 downto 0) <= byte_in;
              end if;

              if byte_index < 511 then
                byte_index <= byte_index + 1;
              end if;
            end if;

            if frame_done = '1' then
              req_type_last_reg <= request_type;

              if (request_type = x"0001") and (key_programmed_reg = '0') and (cmd23_reliable = '1') then
                otp_key            <= key_shadow;
                key_programmed_reg <= '1';
                result_code_reg    <= x"0000";
                resp_type_reg      <= x"0100";
                result_ready_reg   <= '1';
              elsif (request_type = x"0001") and (key_programmed_reg = '0') and (cmd23_reliable = '0') then
                -- Missing reliable-write precondition for key programming.
                result_code_reg    <= x"0001";
                resp_type_reg      <= x"0100";
                result_ready_reg   <= '1';
              elsif (request_type = x"0001") and (key_programmed_reg = '1') then
                -- Programming attempt after OTP is set => write failure.
                result_code_reg    <= x"0005";
                resp_type_reg      <= x"0100";
                result_ready_reg   <= '1';
              elsif request_type = x"0005" then
                if key_programmed_reg = '0' then
                  -- Authentication key not yet programmed.
                  result_code_reg    <= x"0007";
                  resp_type_reg      <= x"0100";
                  result_ready_reg   <= '1';
                else
                  -- Result read request frame received; keep previous result pending.
                  null;
                end if;
              end if;
              state <= IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;

  key_programmed <= key_programmed_reg;
  programmed_key <= otp_key;
  result_ready   <= result_ready_reg;
  result_code    <= result_code_reg;
  resp_type      <= resp_type_reg;
  req_type_last  <= req_type_last_reg;
end architecture;
