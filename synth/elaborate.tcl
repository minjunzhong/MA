# Genus requires a target library even for elaboration in this installation.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build genus-elaborate]
file mkdir $out
if {![info exists ::env(LIBERTY_FILE)] || ![file readable $::env(LIBERTY_FILE)]} {
    error "Set LIBERTY_FILE before elaboration; use synth/read_hdl.tcl for parse-only."
}
read_libs [list [file normalize $::env(LIBERTY_FILE)]]
read_hdl -sv [list [file join $root rtl eyeriss_pe.sv] \
                  [file join $root rtl eyeriss_cluster.sv] \
                  [file join $root rtl eyeriss_four_cluster.sv]]
elaborate eyeriss_four_cluster
check_design -unresolved
write_hdl > [file join $out elaborated.v]
puts "MA_ELABORATION_COMPLETED"
exit
