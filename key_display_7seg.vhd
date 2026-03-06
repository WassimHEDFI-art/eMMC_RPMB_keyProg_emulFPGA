library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity key_display_7seg is
  port (
    clk           : in  std_logic;
    reset         : in  std_logic;
    key_programmed: in  std_logic;
    key_value     : in  std_logic_vector(255 downto 0);
    btn_next      : in  std_logic;
    btn_restart   : in  std_logic;
    hex0          : out std_logic_vector(6 downto 0);
    hex1          : out std_logic_vector(6 downto 0);
    hex2          : out std_logic_vector(6 downto 0);
    hex3          : out std_logic_vector(6 downto 0);
    hex4          : out std_logic_vector(6 downto 0);
    hex5          : out std_logic_vector(6 downto 0)
  );
end entity;

architecture rtl of key_display_7seg is
  constant C_TOTAL_NIBBLES : integer := 64;
  constant C_PAGE_WIDTH    : integer := 6;
  constant C_LAST_PAGE     : integer := 10; -- ceil(64/6)-1
  constant C_GREETING_TICKS: natural := 150_000_000; -- 3 s @ 50 MHz

  signal key_latched        : std_logic_vector(255 downto 0) := (others => '0');
  signal key_programmed_d   : std_logic := '0';

  signal page_index         : integer range 0 to C_LAST_PAGE := 0;
  signal show_active        : std_logic := '0';

  signal btn_next_ff0       : std_logic := '0';
  signal btn_next_ff1       : std_logic := '0';
  signal btn_restart_ff0    : std_logic := '0';
  signal btn_restart_ff1    : std_logic := '0';

  signal next_pulse         : std_logic := '0';
  signal restart_pulse      : std_logic := '0';

  signal greeting_active    : std_logic := '1';
  signal greeting_count     : natural range 0 to C_GREETING_TICKS := 0;

  function nibble_to_7seg(n : std_logic_vector(3 downto 0)) return std_logic_vector is
  begin
    -- Active-low segments, order: g f e d c b a
    case n is
      when "0000" => return "1000000"; -- 0
      when "0001" => return "1111001"; -- 1
      when "0010" => return "0100100"; -- 2
      when "0011" => return "0110000"; -- 3
      when "0100" => return "0011001"; -- 4
      when "0101" => return "0010010"; -- 5
      when "0110" => return "0000010"; -- 6
      when "0111" => return "1111000"; -- 7
      when "1000" => return "0000000"; -- 8
      when "1001" => return "0010000"; -- 9
      when "1010" => return "0001000"; -- A
      when "1011" => return "0000011"; -- b
      when "1100" => return "1000110"; -- C
      when "1101" => return "0100001"; -- d
      when "1110" => return "0000110"; -- E
      when others => return "0001110"; -- F
    end case;
  end function;

  function key_nibble(key : std_logic_vector(255 downto 0); nibble_idx : integer) return std_logic_vector is
    variable hi : integer;
  begin
    if (nibble_idx < 0) or (nibble_idx >= C_TOTAL_NIBBLES) then
      return "0000";
    else
      hi := 255 - (nibble_idx * 4);
      return key(hi downto hi - 3);
    end if;
  end function;

  function digit_segs(
    key    : std_logic_vector(255 downto 0);
    active : std_logic;
    page   : integer;
    pos    : integer
  ) return std_logic_vector is
    variable idx : integer;
  begin
    if active = '0' then
      return "1111111";
    end if;

    idx := page * C_PAGE_WIDTH + pos;
    if idx >= C_TOTAL_NIBBLES then
      return "1111111";
    end if;

    return nibble_to_7seg(key_nibble(key, idx));
  end function;

  function greeting_segs(pos : integer) return std_logic_vector is
  begin
    -- Active-low segments, order: g f e d c b a
    -- Shows HELLO! on HEX5..HEX0 (left to right).
    case pos is
      when 0 => return "0001001"; -- H
      when 1 => return "0000110"; -- E
      when 2 => return "1000111"; -- L
      when 3 => return "1000111"; -- L
      when 4 => return "1000000"; -- O
      when others => return "1111001"; -- ! (approximated using '1')
    end case;
  end function;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        key_latched      <= (others => '0');
        key_programmed_d <= '0';
        page_index       <= 0;
        show_active      <= '0';
        btn_next_ff0     <= '0';
        btn_next_ff1     <= '0';
        btn_restart_ff0  <= '0';
        btn_restart_ff1  <= '0';
        greeting_active  <= '1';
        greeting_count   <= 0;
      else
        key_programmed_d <= key_programmed;

        btn_next_ff0    <= btn_next;
        btn_next_ff1    <= btn_next_ff0;
        btn_restart_ff0 <= btn_restart;
        btn_restart_ff1 <= btn_restart_ff0;

        if greeting_active = '1' then
          if restart_pulse = '1' then
            greeting_active <= '0';
            greeting_count  <= 0;
            show_active     <= '0';
            page_index      <= 0;
          elsif greeting_count = C_GREETING_TICKS - 1 then
            greeting_active <= '0';
            greeting_count  <= 0;
            show_active     <= '0';
            page_index      <= 0;
          else
            greeting_count <= greeting_count + 1;
          end if;
        else
          greeting_count <= 0;

          if key_programmed = '0' then
            -- Display must remain disabled until key is programmed.
            show_active <= '0';
            page_index  <= 0;
          else
            -- Auto-start display when key gets programmed.
            if (key_programmed_d = '0') and (key_programmed = '1') then
              key_latched <= key_value;
              page_index  <= 0;
              show_active <= '1';
            end if;

            -- Restart from beginning (only meaningful once key exists).
            if restart_pulse = '1' then
              key_latched <= key_value;
              page_index  <= 0;
              show_active <= '1';
            elsif next_pulse = '1' and show_active = '1' then
              if page_index = C_LAST_PAGE then
                -- End of key display: turn all HEX off until restart button.
                show_active <= '0';
              else
                page_index <= page_index + 1;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  next_pulse    <= btn_next_ff0 and (not btn_next_ff1);
  restart_pulse <= btn_restart_ff0 and (not btn_restart_ff1);

  -- Left-to-right display order: HEX5 ... HEX0
  hex5 <= greeting_segs(0) when greeting_active = '1' else digit_segs(key_latched, show_active, page_index, 0);
  hex4 <= greeting_segs(1) when greeting_active = '1' else digit_segs(key_latched, show_active, page_index, 1);
  hex3 <= greeting_segs(2) when greeting_active = '1' else digit_segs(key_latched, show_active, page_index, 2);
  hex2 <= greeting_segs(3) when greeting_active = '1' else digit_segs(key_latched, show_active, page_index, 3);
  hex1 <= greeting_segs(4) when greeting_active = '1' else digit_segs(key_latched, show_active, page_index, 4);
  hex0 <= greeting_segs(5) when greeting_active = '1' else digit_segs(key_latched, show_active, page_index, 5);
end architecture;
