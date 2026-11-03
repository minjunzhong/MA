`timescale 1ns/1ps
// Buffered static multicast crossbar. Configure only while idle.
// Each destination selects at most one source; unselected sources are blocked.
module dense_static_router #(
    parameter integer PORTS=4, WIDTH=24,
    parameter integer SEL_W=$clog2(PORTS)
) (
    input wire clk, rst_n,
    input wire cfg_valid,
    output wire cfg_ready,
    input wire [PORTS-1:0] cfg_enable,
    input wire [PORTS*SEL_W-1:0] cfg_source,
    input wire [PORTS-1:0] in_valid,
    output wire [PORTS-1:0] in_ready,
    input wire [PORTS*WIDTH-1:0] in_data,
    output wire [PORTS-1:0] out_valid,
    input wire [PORTS-1:0] out_ready,
    output wire [PORTS*WIDTH-1:0] out_data,
    output wire idle
);
    reg [PORTS-1:0] enabled;
    reg [PORTS*SEL_W-1:0] selected;
    reg [WIDTH-1:0] payload [0:PORTS-1];
    reg [PORTS-1:0] pending [0:PORTS-1];
    reg [WIDTH-1:0] shadow [0:PORTS-1];
    reg [PORTS-1:0] shadow_full;
    wire [PORTS-1:0] occupied;
    genvar s,d;
    assign idle = ~(|occupied);
    assign cfg_ready = idle;
    generate for(s=0;s<PORTS;s=s+1) begin: sources
        wire [PORTS-1:0] targets;
        for(d=0;d<PORTS;d=d+1) begin: target_decode
            assign targets[d] = enabled[d] && (selected[d*SEL_W+:SEL_W] == SEL_W'(s));
        end
        assign occupied[s] = (|pending[s]) || shadow_full[s];
        assign in_ready[s] = rst_n && !cfg_valid && !shadow_full[s] && (|targets);
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                pending[s] <= 0;
                payload[s] <= 0;
                shadow[s]<=0;shadow_full[s]<=0;
            end else if((pending[s]&~out_ready)==0) begin
                if(shadow_full[s]) begin
                    pending[s]<=targets;payload[s]<=shadow[s];shadow_full[s]<=0;
                end else if(in_valid[s]&&in_ready[s]) begin
                    pending[s]<=targets;payload[s]<=in_data[s*WIDTH+:WIDTH];
                end else pending[s]<=0;
            end else begin
                pending[s]<=pending[s]&~out_ready;
                if(in_valid[s]&&in_ready[s]) begin shadow[s]<=in_data[s*WIDTH+:WIDTH];shadow_full[s]<=1;end
            end
        end
    end
    for(d=0;d<PORTS;d=d+1) begin: destinations
        wire [SEL_W-1:0] sel = selected[d*SEL_W+:SEL_W];
        assign out_valid[d] = rst_n && enabled[d] && pending[sel][d];
        assign out_data[d*WIDTH+:WIDTH] = payload[sel];
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin enabled<=0; selected<=0; end
        else if(cfg_valid && cfg_ready) begin
            enabled<=cfg_enable;
            selected<=cfg_source;
        end
    end
endmodule
