`timescale 1ns/1ps
module tb_eyeriss_pe;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,load_en=0,launch=0,start_accumulate=0;
    reg [1:0] load_kind=0;
    reg [6:0] load_addr=0,weight_base=0;
    reg [19:0] load_data=0;
    reg [3:0] start_slot=0,run_slot=0,step=0;
    reg run_en=0,final_step=0,unsigned_iact=0;
    wire [19:0] result0,result1;
    integer expected0,expected1,i,saved0,saved1;
    eyeriss_pe dut(.*);
    task tick; begin @(posedge clk); #1; end endtask
    function automatic integer wrap20(input integer value);
        reg [19:0] bits;
        begin bits=value; wrap20=$signed(bits); end
    endfunction
    task write_spad(input [1:0] kind,input [6:0] address,input [19:0] value);
        begin
            @(negedge clk);load_en=1;load_kind=kind;load_addr=address;load_data=value;
            tick();@(negedge clk);load_en=0;
        end
    endtask
    task compute(input integer length,input reg uns,input reg restore,
                 input [3:0] source_slot,input [3:0] destination_slot,
                 input integer initial0,input integer initial1);
        integer k,activation;
        begin
            expected0=initial0;expected1=initial1;
            @(negedge clk);launch=1;start_accumulate=restore;start_slot=source_slot;
            run_slot=destination_slot;unsigned_iact=uns;
            tick();@(negedge clk);launch=0;run_en=1;
            for(k=0;k<length;k=k+1) begin
                step=4'(k);final_step=(k==length-1);
                activation=uns?(240+k):(k-16);
                expected0=wrap20(expected0+activation*127);
                expected1=wrap20(expected1-activation*128);
                tick();
                if($signed(result0)!==expected0 || $signed(result1)!==expected1)
                    $fatal(1,"PE arithmetic mismatch at step %0d",k);
                @(negedge clk);
            end
            run_en=0;final_step=0;
            repeat(2) tick();
            if($signed(result0)!==expected0 || $signed(result1)!==expected1)
                $fatal(1,"PE result changed while disabled");
        end
    endtask
    initial begin
        tick();@(negedge clk);rst_n=1;
        for(i=0;i<16;i=i+1) begin
            write_spad(0,7'(i),20'(240+i));
            write_spad(1,7'(i),20'h0807f);
        end
        compute(3,0,0,0,0,0,0);
        compute(16,1,0,0,1,0,0);
        write_spad(2,4,20'(500000));write_spad(2,5,20'(-500000));
        compute(16,1,1,2,3,500000,-500000);
        saved0=expected0;saved1=expected1;
        compute(3,0,1,3,4,saved0,saved1);
        $display("PASS pe: signed/unsigned SIMD2, restore, wraparound, final writeback and hold");
        $finish;
    end
    initial begin #100000; $fatal(1,"PE timeout"); end
endmodule
