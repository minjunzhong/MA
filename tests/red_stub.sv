// Test-first behavioral stub. Never synthesize or use as the real implementation.
module eyeriss_four_cluster (
 input wire clk, rst_n,
 input wire load_valid, output wire load_ready,
 input wire [1:0] load_kind, input wire [3:0] load_cluster_mask,
 input wire [11:0] load_pe_mask, input wire [6:0] load_addr,
 input wire [19:0] load_data,
 input wire start_valid, output wire start_ready,
 input wire [3:0] cfg_cluster_mask, input wire [4:0] cfg_len,
 input wire [6:0] cfg_weight_base, input wire [3:0] cfg_psum_slot,
 input wire cfg_accumulate, cfg_unsigned_iact, cfg_reduce_rows,
 output wire busy, out_valid, input wire out_ready,
 output wire [1:0] out_cluster, output wire [3:0] out_pe,
 output wire out_lane, output wire [19:0] out_psum,
 output wire out_last, done, error,
 output wire [31:0] compute_cycles, mac_count
);
assign load_ready = !start_valid;
assign start_ready = 1'b1;
assign busy = 0;
assign out_valid = 0;
assign out_cluster = 0;
assign out_pe = 0;
assign out_lane = 0;
assign out_psum = 0;
assign out_last = 0;
assign done = 0;
assign error = 0;
assign compute_cycles = 0;
assign mac_count = 0;
endmodule
