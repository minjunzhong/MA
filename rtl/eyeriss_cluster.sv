`timescale 1ns/1ps
// One physical hierarchy instance: 3 rows x 4 columns, two MAC lanes per PE.
module eyeriss_cluster (
    input wire clk, rst_n, load_en,
    input wire [11:0] load_pe_mask,
    input wire [1:0] load_kind,
    input wire [6:0] load_addr,
    input wire [19:0] load_data,
    input wire launch, start_accumulate,
    input wire [3:0] start_slot,
    input wire run_en, final_step, unsigned_iact,
    input wire [3:0] step,
    input wire [6:0] weight_base,
    input wire [3:0] run_slot,
    output wire [239:0] result0, result1
);
    genvar p;
    generate for (p = 0; p < 12; p = p + 1) begin : pe_array
        eyeriss_pe pe (
            .clk(clk), .rst_n(rst_n), .load_en(load_en && load_pe_mask[p]),
            .load_kind(load_kind), .load_addr(load_addr), .load_data(load_data),
            .launch(launch), .start_accumulate(start_accumulate), .start_slot(start_slot),
            .run_en(run_en), .final_step(final_step), .unsigned_iact(unsigned_iact),
            .step(step), .weight_base(weight_base), .run_slot(run_slot),
            .result0(result0[p*20 +: 20]), .result1(result1[p*20 +: 20])
        );
    end endgenerate
endmodule
