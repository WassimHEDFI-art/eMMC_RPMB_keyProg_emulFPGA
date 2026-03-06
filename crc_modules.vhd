library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package crc_modules_pkg is
  function crc7_calc(data : std_logic_vector(39 downto 0)) return std_logic_vector;
  function crc16_next(crc : std_logic_vector(15 downto 0); din : std_logic) return std_logic_vector;
end package;

package body crc_modules_pkg is
  function crc7_calc(data : std_logic_vector(39 downto 0)) return std_logic_vector is
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

  function crc16_next(crc : std_logic_vector(15 downto 0); din : std_logic) return std_logic_vector is
    variable c  : std_logic_vector(15 downto 0) := crc;
    variable fb : std_logic;
  begin
    fb := din xor c(15);
    c(15) := c(14);
    c(14) := c(13);
    c(13) := c(12);
    c(12) := c(11) xor fb;
    c(11) := c(10);
    c(10) := c(9);
    c(9)  := c(8);
    c(8)  := c(7);
    c(7)  := c(6);
    c(6)  := c(5);
    c(5)  := c(4) xor fb;
    c(4)  := c(3);
    c(3)  := c(2);
    c(2)  := c(1);
    c(1)  := c(0);
    c(0)  := fb;
    return c;
  end function;
end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc_modules_pkg.all;

entity crc7_gen is
  generic (
    G_DATA_WIDTH : positive := 40
  );
  port (
    data_in : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    crc_out : out std_logic_vector(6 downto 0)
  );
end entity;

architecture rtl of crc7_gen is
  signal data_40 : std_logic_vector(39 downto 0);
begin
  data_40 <= data_in(39 downto 0);
  crc_out <= crc7_calc(data_40);
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.crc_modules_pkg.all;

entity crc16_gen is
  port (
    clk     : in  std_logic;
    reset   : in  std_logic;
    clear   : in  std_logic;
    enable  : in  std_logic;
    data_in : in  std_logic;
    crc_out : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of crc16_gen is
  signal crc_reg : std_logic_vector(15 downto 0) := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        crc_reg <= (others => '0');
      elsif clear = '1' then
        crc_reg <= (others => '0');
      elsif enable = '1' then
        crc_reg <= crc16_next(crc_reg, data_in);
      end if;
    end if;
  end process;

  crc_out <= crc_reg;
end architecture;
