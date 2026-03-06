# 50 MHz system clock constraint
create_clock -name clk_50MHz -period 20.000 [get_ports {clk_50MHz}]

# The eMMC clock is input from host and used as a sampling clock domain.
# Uncomment and adjust if you want explicit timing closure on this domain.
# create_clock -name emmc_clk -period 40.000 [get_ports {emmc_clk}]
