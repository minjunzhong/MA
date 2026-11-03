`timescale 1ns/1ps
module tb_rs_spad_cluster;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    reg [2:0] a_valid=0,w_valid=0;
    wire [2:0] a_ready,w_ready;
    reg [71:0] a_data=0,w_data=0;
    reg [35:0] a_mask=0;
    reg [11:0] a_addr=0,w_mask=12'hfff;
    reg [20:0] w_addr=0;
    reg start=0,unsigned_iact=0;
    wire start_ready,busy,done;
    reg [4:0] length=3;
    reg [6:0] weight_base=0;
    reg [3:0] seed_valid=0,out_ready=0;
    wire [3:0] seed_ready,out_valid;
    reg [159:0] seeds=0;
    wire [159:0] results;
    reg checking=0;
    reg [3:0] seed_seen=0,received=0,stalled=0;
    reg [159:0] previous=0;
    integer expected=0,i,c;
    rs_spad_cluster dut(.*);
    task tick;begin @(posedge clk);#1;end endtask
    always @(posedge clk) if(rst_n && checking) begin
        for(integer col=0;col<4;col=col+1) begin
            if(stalled[col] && (!out_valid[col] || results[col*40+:40]!==previous[col*40+:40]))
                $fatal(1,"Stalled column %0d changed",col);
            if(seed_valid[col]&&seed_ready[col]) begin
                if(seed_seen[col]) $fatal(1,"Repeated seed");
                seed_seen[col]=1;
            end
            if(out_valid[col]&&out_ready[col]) begin
                if(received[col]) $fatal(1,"Repeated column result");
                if($signed(results[col*40+:20])!==expected+col*10 ||
                   $signed(results[col*40+20+:20])!==-expected-col*10)
                    $fatal(1,"Cluster arithmetic mismatch, column %0d length %0d",col,length);
                received[col]=1;
            end
        end
        stalled=out_valid&~out_ready;previous=results;
    end
    task load_packet(input integer address);
        integer lane,k;
        begin
            @(negedge clk);a_valid=7;
            for(lane=0;lane<3;lane=lane+1) begin
                a_mask[lane*12+:12]=12'(15<<(lane*4));
                a_addr[lane*4+:4]=4'(address);
                for(k=0;k<3;k=k+1)
                    a_data[lane*24+k*8+:8]=8'(lane*5+address+k+1);
            end
            #1;if(a_ready!=7) $fatal(1,"Activation packet not accepted");
            tick();@(negedge clk);a_valid=0;
            repeat(3) tick();@(negedge clk);
        end
    endtask
    task job(input integer n);
        integer count;
        reg finished;
        begin
            length=5'(n);expected=3*n*(n+1)/2+15*n;
            seed_seen=0;received=0;stalled=0;checking=1;finished=0;
            for(integer col=0;col<4;col=col+1)
                seeds[col*40+:40]={20'(-col*10),20'(col*10)};
            @(negedge clk);if(!start_ready) $fatal(1,"Cluster not ready");start=1;
            tick();@(negedge clk);start=0;
            for(count=0;count<60&&!finished;count=count+1) begin
                seed_valid=~seed_seen;
                out_ready={(count>2),(count%2==0),(count>5),(count>12)};
                tick();
                if(done) begin
                    if(received!=15 || seed_seen!=15 || busy)
                        $fatal(1,"Premature cluster completion");
                    finished=1;
                end
                @(negedge clk);
            end
            if(!finished) $fatal(1,"Cluster job did not finish");
            checking=0;seed_valid=0;out_ready=0;
            tick();if(done) $fatal(1,"Done must be a pulse");
        end
    endtask
    initial begin
        tick();@(negedge clk);rst_n=1;
        // Two activation inputs cannot load the same PE in the same cycle.
        a_valid=3;a_mask=36'h000001001;#1;
        if(a_ready!=0) $fatal(1,"Overlapping activation masks accepted");
        tick();@(negedge clk);a_valid=0;a_mask=0;
        // High weight padding must be zero.
        w_valid=1;w_data[23:0]=24'h010001;#1;
        if(w_ready[0]) $fatal(1,"Invalid weight padding accepted");
        tick();@(negedge clk);w_valid=0;w_data=0;
        // Prepare all sixteen weight pairs once; reuse them across jobs.
        for(i=0;i<16;i=i+1) begin
            @(negedge clk);w_valid=7;
            for(c=0;c<3;c=c+1) begin w_addr[c*7+:7]=7'(i);w_data[c*24+:24]=24'h00ff01;end
            #1;if(w_ready!=7) $fatal(1,"Weights not accepted");
            tick();@(negedge clk);w_valid=0;
        end
        load_packet(0);job(3);
        load_packet(3);job(6);
        load_packet(6);load_packet(9);load_packet(12);load_packet(13);job(16);
        $display("PASS cluster: masks, unpacking, lengths 3/6/16, SIMD seeds, stalls and completion");
        $finish;
    end
    initial begin #100000; $fatal(1,"Cluster timeout"); end
endmodule
