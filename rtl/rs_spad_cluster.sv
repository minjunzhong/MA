`timescale 1ns/1ps
// RS execution: kernel rows -> PE rows, spatial positions -> columns,
// output-channel pair -> SIMD lanes. Weights/activations remain in PE SPads.
module rs_spad_cluster(
 input wire clk,rst_n,
 input wire [2:0] a_valid,output wire [2:0] a_ready,input wire [71:0] a_data,
 input wire [35:0] a_mask,input wire [11:0] a_addr,
 input wire [2:0] w_valid,output wire [2:0] w_ready,input wire [71:0] w_data,
 input wire [11:0] w_mask,input wire [20:0] w_addr,
 input wire start,output wire start_ready,input wire [4:0] length,
 input wire [6:0] weight_base,input wire unsigned_iact,
 input wire [3:0] seed_valid,output wire [3:0] seed_ready,input wire [159:0] seeds,
 output wire [3:0] out_valid,input wire [3:0] out_ready,output wire [159:0] results,
 output wire busy,output reg done
);
 reg [1:0] state;
 reg [3:0] step;
 reg [4:0] len;
 reg [6:0] base;
 reg uns;
 reg [3:0] sent,received;
 wire [239:0] sums0,sums1;
 wire [3:0] inject_ready;
 reg [2:0] unpack;
 reg [1:0] phase[0:2];
 reg [23:0] packed_a[0:2];
 reg [11:0] masks[0:2];reg [3:0] addresses[0:2];
 wire launch=start&&start_ready&&(length>=1)&&(length<=16)&&({1'b0,weight_base}+{3'd0,length}<=96);
 assign start_ready=(state==0)&&!(|unpack);
 assign busy=(state!=0)||(|unpack);
 // Each PE may select at most one activation router per cycle.
 wire conflict=|(a_mask[11:0]&a_mask[23:12]&{12{a_valid[0]&&a_valid[1]}})
             |||(a_mask[11:0]&a_mask[35:24]&{12{a_valid[0]&&a_valid[2]}})
             |||(a_mask[23:12]&a_mask[35:24]&{12{a_valid[1]&&a_valid[2]}});
 assign a_ready={3{rst_n&&state==0&&!start&&!conflict&&!(|w_valid)&&!(|unpack)}};
 assign w_ready={3{rst_n&&state==0&&!start&&!(|unpack)}} &
                {w_data[71:64]==0,w_data[47:40]==0,w_data[23:16]==0};
 genvar p,c;
 generate for(p=0;p<12;p=p+1) begin: pes
   wire hit0=unpack[0]&&masks[0][p];
   wire hit1=unpack[1]&&masks[1][p];
   wire hit2=unpack[2]&&masks[2][p];
   wire wh=w_valid[p/4]&&w_ready[p/4]&&w_mask[p];
   wire [6:0] addr=wh?w_addr[(p/4)*7+:7]:{3'd0,(hit0?addresses[0]+4'(phase[0]):hit1?addresses[1]+4'(phase[1]):addresses[2]+4'(phase[2]))};
   wire [19:0] payload=wh?{4'd0,w_data[(p/4)*24+:16]}:
        {12'd0,(hit0?packed_a[0][phase[0]*8+:8]:hit1?packed_a[1][phase[1]*8+:8]:packed_a[2][phase[2]*8+:8])};
   eyeriss_pe pe(.clk(clk),.rst_n(rst_n),.load_en(wh||hit0||hit1||hit2),
    .load_kind(wh?2'd1:2'd0),.load_addr(addr),.load_data(payload),
    .launch(launch),.start_accumulate(1'b0),.start_slot(4'd0),
    .run_en(state==1),.final_step({1'b0,step}+1==len),.unsigned_iact(uns),
    .step(step),.weight_base(base),.run_slot(4'd0),
    .result0(sums0[p*20+:20]),.result1(sums1[p*20+:20]));
 end
 for(genvar l=0;l<3;l=l+1) begin: unpackers
   always @(posedge clk or negedge rst_n) begin
     if(!rst_n) begin unpack[l]<=0;phase[l]<=0;packed_a[l]<=0;masks[l]<=0;addresses[l]<=0;end
     else if(a_valid[l]&&a_ready[l]) begin
       unpack[l]<=1;phase[l]<=0;packed_a[l]<=a_data[l*24+:24];masks[l]<=a_mask[l*12+:12];addresses[l]<=a_addr[l*4+:4];
     end else if(unpack[l]) begin
       if(phase[l]==2) unpack[l]<=0;else phase[l]<=phase[l]+1;
     end
   end
 end
 for(c=0;c<4;c=c+1) begin: columns
   wire [119:0] rows={sums1[(c+8)*20+:20],sums0[(c+8)*20+:20],
      sums1[(c+4)*20+:20],sums0[(c+4)*20+:20],sums1[c*20+:20],sums0[c*20+:20]};
   wire valid=state==2&&!sent[c]&&seed_valid[c];
   assign seed_ready[c]=state==2&&!sent[c]&&inject_ready[c];
   rs_vertical_accumulator vertical(.clk(clk),.rst_n(rst_n),.valid(valid),.ready(inject_ready[c]),
    .seed(seeds[c*40+:40]),.rows(rows),.out_valid(out_valid[c]),.out_ready(out_ready[c]),.result(results[c*40+:40]));
 end endgenerate
 always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin state<=0;step<=0;len<=0;base<=0;uns<=0;sent<=0;received<=0;done<=0;end
   else begin
     done<=0;
     if(launch) begin state<=1;step<=0;len<=length;base<=weight_base;uns<=unsigned_iact;sent<=0;received<=0;end
     else if(state==1) begin
       if({1'b0,step}+1==len) state<=2;else step<=step+1;
     end else if(state==2) begin
       sent<=sent|(seed_valid&seed_ready);received<=received|(out_valid&out_ready);
       if(&(received|(out_valid&out_ready))) begin state<=0;done<=1;end
     end
   end
 end
endmodule
