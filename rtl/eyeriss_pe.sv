`timescale 1ns/1ps
// Dense SIMD2 PE. Scratchpads intentionally have no bulk reset.
module eyeriss_pe (
    input wire clk, rst_n,
    input wire load_en,
    input wire [1:0] load_kind,
    input wire [6:0] load_addr,
    input wire [19:0] load_data,
    input wire launch, start_accumulate,
    input wire [3:0] start_slot,
    input wire run_en, final_step, unsigned_iact,
    input wire [3:0] step,
    input wire [6:0] weight_base,
    input wire [3:0] run_slot,
    output wire [19:0] result0, result1
);
    reg [7:0] iact [0:15];
    reg [15:0] weight [0:95];
    reg [19:0] psum [0:31];
    reg signed [19:0] acc0, acc1;
    wire [6:0] weight_addr = weight_base + {3'b000, step};
    wire signed [8:0] activation = unsigned_iact
        ? $signed({1'b0, iact[step]}) : $signed({iact[step][7], iact[step]});
    wire signed [7:0] weight0 = $signed(weight[weight_addr][7:0]);
    wire signed [7:0] weight1 = $signed(weight[weight_addr][15:8]);
    wire signed [16:0] product0 = activation * weight0;
    wire signed [16:0] product1 = activation * weight1;
    wire signed [19:0] sum0 = acc0 + {{3{product0[16]}}, product0};
    wire signed [19:0] sum1 = acc1 + {{3{product1[16]}}, product1};
    assign result0 = acc0;
    assign result1 = acc1;

    always @(posedge clk) begin
        if (rst_n) begin
            if (load_en) begin
                case (load_kind)
                    2'd0: iact[load_addr[3:0]] <= load_data[7:0];
                    2'd1: weight[load_addr] <= load_data[15:0];
                    2'd2: psum[load_addr[4:0]] <= load_data;
                    default: begin end
                endcase
            end
            if (run_en && final_step) begin
                psum[{run_slot, 1'b0}] <= sum0;
                psum[{run_slot, 1'b1}] <= sum1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc0 <= 20'sd0;
            acc1 <= 20'sd0;
        end else if (launch) begin
            acc0 <= start_accumulate ? $signed(psum[{start_slot, 1'b0}]) : 20'sd0;
            acc1 <= start_accumulate ? $signed(psum[{start_slot, 1'b1}]) : 20'sd0;
        end else if (run_en) begin
            acc0 <= sum0;
            acc1 <= sum1;
        end
    end
endmodule
