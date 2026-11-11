// stub: video_mixer instantiates gamma_fast only with GAMMA = 1 (not used in M2M)
module gamma_fast(input clk_vid, input ce_pix, inout [21:0] gamma_bus, input HSync, VSync, HBlank, VBlank, DE,
   input [23:0] RGB_in, output reg HSync_out, VSync_out, HBlank_out, VBlank_out, DE_out, output reg [23:0] RGB_out);
endmodule
