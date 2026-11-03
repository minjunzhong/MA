`timescale 1ns/1ps
// Three elastic SIMD2 accumulation stages: bottom PE -> middle -> top.
module rs_vertical_accumulator(
 input wire clk,rst_n,valid,output wire ready,input wire [39:0] seed,
 input wire [119:0] rows,output wire out_valid,input wire out_ready,
 output wire [39:0] result
);
 reg [2:0] full;
 reg [39:0] data[0:2];
 reg [79:0] remaining0;
 reg [39:0] remaining1;
 wire [2:0] accept;
 assign accept[2]=!full[2]||out_ready;
 assign accept[1]=!full[1]||!full[2]||out_ready;
 assign accept[0]=!full[0]||!full[1]||!full[2]||out_ready;
 assign ready=accept[0];assign out_valid=full[2];assign result=data[2];
 function automatic [39:0] add_pair(input [39:0] a,b);
   add_pair={20'(a[39:20]+b[39:20]),20'(a[19:0]+b[19:0])};
 endfunction
 always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin full<=0;data[0]<=0;data[1]<=0;data[2]<=0;remaining0<=0;remaining1<=0;end
   else begin
     if(accept[0]) begin
       full[0]<=valid;
       if(valid) begin data[0]<=add_pair(seed,rows[119:80]);remaining0<=rows[79:0];end
     end
     if(accept[1]) begin
       full[1]<=full[0];
       if(full[0]) begin data[1]<=add_pair(data[0],remaining0[79:40]);remaining1<=remaining0[39:0];end
     end
     if(accept[2]) begin full[2]<=full[1];if(full[1]) data[2]<=add_pair(data[1],remaining1);end
   end
 end
endmodule
