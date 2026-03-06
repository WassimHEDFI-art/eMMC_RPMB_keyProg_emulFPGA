library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_status is
  port (
    clk            : in  std_logic;
    reset          : in  std_logic;
    key_programmed : in  std_logic;
    btn_restart    : in  std_logic;
    leds           : out std_logic_vector(9 downto 0)
  );
end entity;

architecture rtl of led_status is
  constant C_BLINK_HALF_PERIOD : natural := 5_000_000; -- 100 ms @ 50 MHz
  constant C_BLINK_TOGGLES     : natural := 6;         -- total 3 blinks

  signal btn_ff0         : std_logic := '0';
  signal btn_ff1         : std_logic := '0';
  signal restart_pulse   : std_logic := '0';

  signal blink_active    : std_logic := '0';
  signal blink_phase     : std_logic := '0';
  signal half_count      : natural range 0 to C_BLINK_HALF_PERIOD := 0;
  signal toggle_count    : natural range 0 to C_BLINK_TOGGLES := 0;

  signal leds_reg        : std_logic_vector(9 downto 0) := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        btn_ff0       <= '0';
        btn_ff1       <= '0';
        restart_pulse <= '0';
        blink_active  <= '0';
        blink_phase   <= '0';
        half_count    <= 0;
        toggle_count  <= 0;
        leds_reg      <= (others => '0');
      else
        btn_ff0 <= btn_restart;
        btn_ff1 <= btn_ff0;
        restart_pulse <= btn_ff0 and (not btn_ff1);

        if key_programmed = '1' then
          blink_active <= '0';
          blink_phase  <= '0';
          half_count   <= 0;
          toggle_count <= 0;
          leds_reg     <= (others => '1');
        else
          if (restart_pulse = '1') and (blink_active = '0') then
            blink_active <= '1';
            blink_phase  <= '1';
            half_count   <= 0;
            toggle_count <= 0;
            leds_reg     <= (others => '1');
          elsif blink_active = '1' then
            if half_count = C_BLINK_HALF_PERIOD - 1 then
              half_count  <= 0;
              blink_phase <= not blink_phase;

              if blink_phase = '1' then
                leds_reg <= (others => '0');
              else
                leds_reg <= (others => '1');
              end if;

              if toggle_count = C_BLINK_TOGGLES - 1 then
                blink_active <= '0';
                blink_phase  <= '0';
                toggle_count <= 0;
                leds_reg     <= (others => '0');
              else
                toggle_count <= toggle_count + 1;
              end if;
            else
              half_count <= half_count + 1;
            end if;
          else
            leds_reg <= (others => '0');
          end if;
        end if;
      end if;
    end if;
  end process;

  leds <= leds_reg;
end architecture;
