`timescale 1ns/1ps
// M2M video_mixer, scandoubler on (Standard VGA), fed by the ZX Next raster as
// main.vhd delivers it: 28 MHz clock, 14 MHz pixel enable (2 clocks/pixel),
// 912 pixels per line (zxula_timing 50 Hz: hc 0..455 at 7 MHz), hblank on
// pixels 0..191, 720 active, hsync on pixels 32..95; 311 lines, vblank on
// lines 0..7, vsync on lines 1..4. RGB, syncs and blanks change in the cycle
// of the enable, as in main.vhd's video_proc.
// Each input pixel carries the ID {line[8:0], col[9:0]} in {B,G,R}.
// Output: out.txt, one record per output pixel under DE ("P t id") and one per
// DE edge ("D t de").
module tb_zxn_sd;
parameter LD     = 1;
parameter HPIX   = 912;
parameter HBEND  = 192;   // first active pixel
parameter HSON   = 32;
parameter HSOFF  = 96;
parameter VLINES = 311;
parameter VBEND  = 7;
parameter FRAMES = 3;

reg clk = 0;
always #17.857 clk = ~clk;

reg [10:0] hcnt = 0;               // clock in line, 0 .. 2*HPIX-1
reg [8:0]  vcnt = 0;
integer    frame = 0;
wire [9:0] px = hcnt[10:1];
reg        ce = 0, hs = 0, vs = 0, hb = 1, vb = 1;
reg [23:0] pix = 0;
// values of the pixel that starts on the next clock
wire       eol = (hcnt == 2*HPIX-1);
wire [9:0] np  = eol ? 10'd0 : px + 1'd1;
wire [8:0] nl  = eol ? ((vcnt == VLINES-1) ? 9'd0 : vcnt + 1'd1) : vcnt;
wire [9:0] nc  = (np >= HBEND) ? np - HBEND : 10'd1023;   // 10-bit column ID

always @(posedge clk) begin
   if (hcnt == 2*HPIX-1) begin
      hcnt <= 0;
      if (vcnt == VLINES-1) begin vcnt <= 0; frame <= frame + 1; end
      else vcnt <= vcnt + 1'd1;
   end else hcnt <= hcnt + 1'd1;
   ce <= (hcnt[0] == 1'b1);        // first cycle of the next pixel
   if (hcnt[0] == 1'b1) begin
      hb  <= (np < HBEND);
      hs  <= (np >= HSON && np < HSOFF);
      vb  <= (nl <= VBEND);
      vs  <= (nl >= 1 && nl <= 4);
      pix <= {5'd0, nl, nc};
   end
end

wire [7:0] R, G, B;
wire VS, HS, DE, CE_PIXEL;
video_mixer #(.LINEDOUBLER(LD)) dut (
   .CLK_VIDEO(clk), .CE_PIXEL(CE_PIXEL), .ce_pix(ce), .scandoubler(1'b1), .hq2x(1'b0),
   .gamma_bus(),
   .R(pix[7:0]), .G(pix[15:8]), .B(pix[23:16]),
   .HSync(hs), .VSync(vs), .HBlank(hb), .VBlank(vb),
   .HDMI_FREEZE(1'b0), .freeze_sync(),
   .VGA_R(R), .VGA_G(G), .VGA_B(B), .VGA_VS(VS), .VGA_HS(HS), .VGA_DE(DE));

integer f, t = 0;
reg de_d = 0, vs_d = 0;
initial f = $fopen("out.txt", "w");
always @(posedge clk) begin
   t <= t + 1;
   if (frame >= 1) begin
      if (DE !== de_d) $fwrite(f, "D %0d %0d\n", t, DE);
      if (VS && !vs_d) $fwrite(f, "V %0d\n", t);
      if (DE && CE_PIXEL) $fwrite(f, "P %0d %h\n", t, {B, G, R});
   end
   de_d <= DE;
   vs_d <= VS;
   if (frame == FRAMES) begin $fclose(f); $finish; end
end
endmodule
