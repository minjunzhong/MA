# Parse SystemVerilog without technology mapping or elaboration claims.
set root [file normalize [file join [file dirname [info script]] ..]]
read_hdl -sv [list [file join $root rtl eyeriss_pe.sv] \
                  [file join $root rtl eyeriss_cluster.sv] \
                  [file join $root rtl eyeriss_four_cluster.sv]]
puts "MA_RTL_READ_COMPLETED"
exit
