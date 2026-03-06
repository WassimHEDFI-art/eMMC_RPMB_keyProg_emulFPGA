library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_status is
  port (
    clk            : in  std_logic;
    reset          : in  std_logic;
    key_programmed : in  std_logic;
    leds           : out std_logic_vector(9 downto 0)
  );
end entity;

architecture rtl of led_status is
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        leds <= (others => '0');
      elsif key_programmed = '1' then
        leds <= (others => '1');
      else
        leds <= (others => '0');
      end if;
    end if;
  end process;
end architecture;
