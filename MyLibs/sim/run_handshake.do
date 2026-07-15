##############################################################################
#  run_handshake.do  -- Async req/ack handshake GUI demo
#
#  KULLANIM:
#     cd {C:/Users/user/Desktop/QUARTUS/VHDL_Projects/MyLibs/sim}
#     do run_handshake.do
#
#  GORULECEKLER:
#     - TX domain (100 MHz) 3 rastgele 32-bit deger gonderir
#     - RX domain (~71 MHz) hepsini dogru yakalar
#     - req/ack el sikismasini (4 faz) dalga formunda gorebilirsin
##############################################################################
if {[file exists work]} { vdel -all }
vlib work

vcom -2008 ../synchronizer.vhd
vcom -2008 ../cdc_handshake_tx.vhd
vcom -2008 ../cdc_handshake_rx.vhd
vcom -2008 tb_cdc_handshake.vhd

vsim -t 1ps -voptargs="+acc" work.tb_cdc_handshake

add wave -divider "CLOCK'LAR (iliskisiz domain'ler)"
add wave -label tx_clk  /tb_cdc_handshake/tx_clk
add wave -label rx_clk  /tb_cdc_handshake/rx_clk
add wave -label rst_n   /tb_cdc_handshake/rst_n

add wave -divider "TX DOMAIN (verici)"
add wave -label send_strobe   /tb_cdc_handshake/send_strobe
add wave -hex  -label data_to_send /tb_cdc_handshake/data_to_send
add wave -label tx_busy       /tb_cdc_handshake/tx_busy
add wave -label tx_done       /tb_cdc_handshake/tx_done
add wave -label "TX FSM"      /tb_cdc_handshake/u_tx/state

add wave -divider "TX <-> RX HAT (handshake + data bus)"
add wave -hex  -label data_bus  /tb_cdc_handshake/data_bus
add wave -label req_line        /tb_cdc_handshake/req_line
add wave -label ack_line        /tb_cdc_handshake/ack_line

add wave -divider "RX DOMAIN (alici)"
add wave -label "RX FSM"     /tb_cdc_handshake/u_rx/state
add wave -label rx_valid     /tb_cdc_handshake/rx_valid
add wave -hex  -label rx_data  /tb_cdc_handshake/rx_data

add wave -divider "DOGULAMA"
add wave -unsigned -label rx_count  /tb_cdc_handshake/rx_count

echo "===== BASLA ====="
run 600 ns
echo "===== BITIS ====="
wave zoom full
