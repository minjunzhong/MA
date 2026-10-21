# Technology-mapped Genus Common UI flow. Technology libraries stay external.
set root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(LIBERTY_FILE)] || ![file isfile $::env(LIBERTY_FILE)]} {
    error "Set LIBERTY_FILE to a readable, authorized Liberty timing library."
}
set out [file join $root build genus]
if {[info exists ::env(REPORT_DIR)]} {set out [file normalize $::env(REPORT_DIR)]}
file mkdir $out
set lib [file normalize $::env(LIBERTY_FILE)]
read_libs [list $lib]
read_hdl -sv [list [file join $root rtl eyeriss_pe.sv] \
                  [file join $root rtl eyeriss_cluster.sv] \
                  [file join $root rtl eyeriss_four_cluster.sv]]
elaborate eyeriss_four_cluster
check_design -unresolved
source [file join $root synth constraints.sdc]
set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium
syn_generic
syn_map
syn_opt
report_timing > [file join $out timing.rpt]
report_area > [file join $out area.rpt]
# No SAIF supplied: vectorless activity assumptions, NOT measured workload power.
report_power > [file join $out power-vectorless.rpt]
report_qor > [file join $out qor.rpt]
write_hdl > [file join $out mapped.v]
write_sdc > [file join $out mapped.sdc]
set manifest [open [file join $out assumptions.txt] w]
puts $manifest "Library (external): $lib"
puts $manifest "Clock period (library time units): $ma_period"
puts $manifest "Input/output delay: 10% of clock period"
puts $manifest "Clock uncertainty: 5% of clock period"
puts $manifest "Power: vectorless estimate; no measured switching activity"
puts $manifest "Memories: register inferred; no SRAM macro mapping"
close $manifest
puts "MA_SYNTHESIS_COMPLETED"
exit
