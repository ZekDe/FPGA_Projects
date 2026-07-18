set_global_assignment -entity "pll_2clk" -library "lib_pll_2clk" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "pll_2clk" -library "lib_pll_2clk" -name IP_TOOL_VERSION "25.1"
set_global_assignment -entity "pll_2clk" -library "lib_pll_2clk" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_pll_2clk" -name SPD_FILE [file join $::quartus(sip_path) "pll_2clk.spd"]

set_global_assignment -library "lib_pll_2clk" -name MISC_FILE [file join $::quartus(sip_path) "pll_2clk_sim/pll_2clk.vho"]
