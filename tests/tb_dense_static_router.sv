`timescale 1ns/1ps
module tb_dense_static_router;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,cfg_valid=0;
    wire cfg_ready,idle;
    reg [3:0] cfg_enable=0,in_valid=0,out_ready=0;
    reg [7:0] cfg_source=0;
    reg [95:0] in_data=0;
    wire [3:0] in_ready,out_valid;
    wire [95:0] out_data;
    integer counts[0:3]; integer i;
    integer sequence_count[0:3];reg stream_check=0;
    dense_static_router dut(.*);
    task tick; begin @(posedge clk); #1; end endtask
    task configure(input [7:0] routes);
        begin @(negedge clk); cfg_valid=1; cfg_enable=15; cfg_source=routes;
        tick(); @(negedge clk); cfg_valid=0; end
    endtask
    always @(posedge clk) if(rst_n)
        for(integer j=0;j<4;j=j+1) if(out_valid[j] && out_ready[j]) begin
            counts[j]=counts[j]+1;
            if(stream_check) begin
                if(out_data[j*24+:24]!=24'(100+sequence_count[j])) $fatal(1,"stream ordering");
                sequence_count[j]=sequence_count[j]+1;
            end
        end
    initial begin
        for(i=0;i<4;i=i+1) counts[i]=0;
        tick(); @(negedge clk); rst_n=1;
        // Broadcast with destination 3 blocked: each fast destination receives once.
        configure(0);
        in_data[23:0]=24'h123456; in_valid=1; tick();
        @(negedge clk); in_valid=0; out_ready=7;
        repeat(5) tick();
        for(i=0;i<3;i=i+1) if(counts[i]!=1) $fatal(1,"duplicate/missing multicast");
        if(out_valid!=8 || cfg_ready || out_data[95:72]!=24'h123456) $fatal(1,"blocked destination lost");
        @(negedge clk); out_ready=15; tick();
        if(!idle || counts[3]!=1) $fatal(1,"drain failed");
        // Four concurrent independent unicasts.
        configure(8'b11_10_01_00);
        in_data={24'd44,24'd33,24'd22,24'd11}; in_valid=15;
        tick(); @(negedge clk); in_valid=0;
        if(out_valid!=15 || out_data!=in_data) $fatal(1,"unicast mapping");
        tick();
        // Two grouped multicasts, then interleaved multicasts.
        configure(8'b01_01_00_00); in_valid=3; tick();
        @(negedge clk); in_valid=0;
        if(out_data!={24'd22,24'd22,24'd11,24'd11}) $fatal(1,"group mapping");
        tick(); configure(8'b01_00_01_00); in_valid=3; tick();
        @(negedge clk); in_valid=0;
        if(out_data!={24'd22,24'd11,24'd22,24'd11}) $fatal(1,"interleaved mapping");
        tick();
        // Hold A for a slow destination while B occupies the shadow slot.
        configure(0);out_ready=7;
        for(i=0;i<4;i=i+1) sequence_count[i]=0;
        stream_check=1;in_valid=1;in_data[23:0]=100;tick();
        @(negedge clk);in_data[23:0]=101;
        if(!in_ready[0]) $fatal(1,"Shadow slot not available");
        tick();@(negedge clk);in_valid=0;#1;
        if(in_ready[0]) $fatal(1,"Full shadow slot did not backpressure input");
        repeat(3) tick();
        for(i=0;i<3;i=i+1) if(sequence_count[i]!=1) $fatal(1,"Repeated fast delivery");
        if(sequence_count[3]!=0) $fatal(1,"Blocked output advanced");
        @(negedge clk);out_ready=15;tick();tick();tick();
        for(i=0;i<4;i=i+1) if(sequence_count[i]!=2) $fatal(1,"Shadow word lost or reordered");
        if(!idle) $fatal(1,"Shadow did not drain");
        stream_check=0;
        @(negedge clk);configure(0);out_ready=15;
        for(i=0;i<4;i=i+1) sequence_count[i]=0;
        stream_check=1;in_valid=1;
        for(i=0;i<20;i=i+1) begin
            in_data[23:0]=24'(100+i);
            #1;if(!in_ready[0]) $fatal(1,"throughput bubble");
            tick();@(negedge clk);
        end
        in_valid=0;repeat(5) tick();
        for(i=0;i<4;i=i+1) if(sequence_count[i]!=20) $fatal(1,"stream count");
        stream_check=0;
        out_ready=0; tick(); @(negedge clk); rst_n=0; tick();
        if(out_valid || !idle) $fatal(1,"reset did not flush");
        $display("PASS router: multicast backpressure, unicast, grouped, interleaved, shadow, stream, reset"); $finish;
    end
    initial begin #10000; $fatal(1,"timeout"); end
endmodule
