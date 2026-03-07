library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  signal reset_50            : std_logic := '1';
  signal reset_cnt           : unsigned(5 downto 0) := (others => '0');
  signal reset_sync_0        : std_logic := '1';
  signal reset_sync_1        : std_logic := '1';

  signal cmd_in              : std_logic;
  signal cmd_out             : std_logic;
  signal cmd_oe              : std_logic;
  signal cmd1_seen           : std_logic;
  signal cmd1_seen_latched   : std_logic := '0';
begin
  cmd_in <= emmc_cmd;
  emmc_cmd <= cmd_out when cmd_oe = '1' else 'Z';

  emmc_dat0 <= 'Z';

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
      cmd1_seen   => cmd1_seen
    );

  process (emmc_clk)
  begin
    if rising_edge(emmc_clk) then
      if reset_sync_1 = '1' then
        cmd1_seen_latched <= '0';
      else
        if cmd1_seen = '1' then
          cmd1_seen_latched <= '1';
        end if;
      end if;
    end if;
  end process;

  ledr <= (9 downto 1 => '0') & cmd1_seen_latched;
  hex0 <= "1111111";
  hex1 <= "1111111";
  hex2 <= "1111111";
  hex3 <= "1111111";
  hex4 <= "1111111";
  hex5 <= "1111111";
end architecture;
