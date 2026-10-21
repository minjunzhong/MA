`timescale 1ns/1ps
// Four-cluster dense baseline; see docs/spec-v1.md for paper deviations.
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
    output reg [1:0] out_cluster, output reg [3:0] out_pe,
    output reg out_lane, output wire [19:0] out_psum,
    output wire out_last, output reg done, error,
    output reg [31:0] compute_cycles, mac_count
);
    localparam [1:0] IDLE=2'd0, COMPUTE=2'd1, DRAIN=2'd2;
    reg [1:0] state;
    reg [3:0] cluster_mask_r, psum_slot_r;
    reg [4:0] len_r;
    reg [6:0] weight_base_r;
    reg unsigned_r, reduce_r;
    reg [3:0] step_r;
    wire [239:0] results0 [0:3];
    wire [239:0] results1 [0:3];

    function [1:0] first_cluster(input [3:0] mask);
        begin
            if (mask[0]) first_cluster = 0;
            else if (mask[1]) first_cluster = 1;
            else if (mask[2]) first_cluster = 2;
            else if (mask[3]) first_cluster = 3;
            else first_cluster = 0; // unreachable for an accepted configuration
        end
    endfunction

    function [31:0] active_macs(input [3:0] mask);
        integer i;
        begin
            active_macs = 0;
            for (i=0; i<4; i=i+1)
                if (mask[i]) active_macs = active_macs + 32'd24;
        end
    endfunction

    wire config_legal = (cfg_cluster_mask != 0) && (cfg_len >= 1)
        && (cfg_len <= 16)
        && (({1'b0, cfg_weight_base} + {3'b000, cfg_len}) <= 8'd96);
    wire load_legal = ((load_kind == 0) && (load_addr < 16))
                   || ((load_kind == 1) && (load_addr < 96))
                   || ((load_kind == 2) && (load_addr < 32));
    assign start_ready = state == IDLE;
    assign load_ready = (state == IDLE) && !start_valid;
    assign busy = state != IDLE;
    assign out_valid = state == DRAIN;
    wire launch = start_valid && start_ready && config_legal;
    wire load_fire = load_valid && load_ready && load_legal;
    wire final_step = ({1'b0, step_r} + 5'd1) == len_r;

    reg next_found;
    reg [1:0] next_cluster;
    integer n;
    always @* begin
        next_found = 0;
        next_cluster = 0;
        for (n=0; n<4; n=n+1) begin
            if ((n > out_cluster) && cluster_mask_r[n] && !next_found) begin
                next_found = 1;
                next_cluster = n[1:0];
            end
        end
    end
    wire [3:0] last_pe = reduce_r ? 4'd3 : 4'd11;
    assign out_last = out_valid && !next_found && (out_pe == last_pe) && out_lane;
    wire [239:0] selected_results = out_lane ? results1[out_cluster] : results0[out_cluster];
    wire [19:0] raw_value = selected_results[out_pe*20 +: 20];
    wire [19:0] row1_value = selected_results[(out_pe+4)*20 +: 20];
    wire [19:0] row2_value = selected_results[(out_pe+8)*20 +: 20];
    assign out_psum = out_valid ? (reduce_r ? raw_value+row1_value+row2_value : raw_value) : 20'd0;

    genvar c;
    generate for (c=0; c<4; c=c+1) begin : cluster_array
        eyeriss_cluster cluster (
            .clk(clk), .rst_n(rst_n), .load_en(load_fire && load_cluster_mask[c]),
            .load_pe_mask(load_pe_mask), .load_kind(load_kind), .load_addr(load_addr),
            .load_data(load_data), .launch(launch && cfg_cluster_mask[c]),
            .start_accumulate(cfg_accumulate), .start_slot(cfg_psum_slot),
            .run_en((state == COMPUTE) && cluster_mask_r[c]),
            .final_step(final_step), .unsigned_iact(unsigned_r), .step(step_r),
            .weight_base(weight_base_r), .run_slot(psum_slot_r),
            .result0(results0[c]), .result1(results1[c])
        );
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cluster_mask_r <= 0;
            psum_slot_r <= 0;
            len_r <= 0;
            weight_base_r <= 0;
            unsigned_r <= 0;
            reduce_r <= 0;
            step_r <= 0;
            out_cluster <= 0;
            out_pe <= 0;
            out_lane <= 0;
            done <= 0;
            error <= 0;
            compute_cycles <= 0;
            mac_count <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    if (load_valid && load_ready && !load_legal) error <= 1;
                    if (start_valid) begin
                        if (!config_legal) error <= 1;
                        else begin
                            error <= 0;
                            cluster_mask_r <= cfg_cluster_mask;
                            psum_slot_r <= cfg_psum_slot;
                            len_r <= cfg_len;
                            weight_base_r <= cfg_weight_base;
                            unsigned_r <= cfg_unsigned_iact;
                            reduce_r <= cfg_reduce_rows;
                            step_r <= 0;
                            out_cluster <= first_cluster(cfg_cluster_mask);
                            out_pe <= 0;
                            out_lane <= 0;
                            compute_cycles <= 0;
                            mac_count <= 0;
                            state <= COMPUTE;
                        end
                    end
                end
                COMPUTE: begin
                    compute_cycles <= compute_cycles + 32'd1;
                    mac_count <= mac_count + active_macs(cluster_mask_r);
                    if (final_step) state <= DRAIN;
                    else step_r <= step_r + 4'd1;
                end
                DRAIN: begin
                    if (out_ready) begin
                        if (!out_lane) out_lane <= 1;
                        else begin
                            out_lane <= 0;
                            if (out_pe != last_pe) out_pe <= out_pe + 4'd1;
                            else begin
                                out_pe <= 0;
                                if (next_found) out_cluster <= next_cluster;
                                else begin
                                    state <= IDLE;
                                    done <= 1;
                                end
                            end
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
