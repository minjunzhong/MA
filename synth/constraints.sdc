# Units follow the supplied Liberty library. 10 means 10 ns ONLY for a 1 ns library.
set ma_period 10.0
if {[info exists ::env(CLOCK_PERIOD)]} {set ma_period $::env(CLOCK_PERIOD)}
if {![string is double -strict $ma_period] || $ma_period <= 0} {
    error "CLOCK_PERIOD must be a positive number in library time units"
}
create_clock -name core_clk -period $ma_period [get_ports clk]
set data_inputs [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay [expr {$ma_period * 0.10}] -clock core_clk $data_inputs
set_output_delay [expr {$ma_period * 0.10}] -clock core_clk [all_outputs]
set_clock_uncertainty [expr {$ma_period * 0.05}] [get_clocks core_clk]
set_false_path -from [get_ports rst_n]
