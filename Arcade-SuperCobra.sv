//============================================================================
//  Arcade: Super Cobra by gaz68 (Sept 2019)
//  https://github.com/gaz68
//
//  Scramble Port to MiSTer
//  Copyright (C) 2017 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S    // 1 - signed audio samples, 0 - unsigned
);

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd3 : 8'd4;

`include "build_id.v" 
localparam CONF_STR = {
	"A.SCOBRA;;",
	"F,rom;", // allow loading of alternate ROMs
	"-;",
	"O1,Aspect Ratio,Original,Wide;",
	"O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O8,Lives,3,4;",
	"O9,Allow Continue,No,Yes;",
	"OC,Cabinet,Upright,Cocktail;",	
	//"OE,Test,Off,On;",	
	"-;",
	"R0,Reset;",
	"J1,Fire,Bomb,Start 1P,Start 2P;",
	"V,v",`BUILD_DATE
};
wire [5:1] m_dip = {status[12],2'b01,status[9:8]};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

reg ce_6p, ce_6n, ce_12, ce_1p79;
always @(negedge clk_sys) begin
	reg [1:0] div = 0;
	reg [3:0] div179 = 0;
	
	div <= div + 1'd1;

	ce_12 <= div[0];
	ce_6p <= div[0] & ~div[1];
	ce_6n <= div[0] &  div[1];
	
   ce_1p79 <= 0;
   div179 <= div179 - 1'd1;
   if(!div179) begin
		div179 <= 13;
		ce_1p79 <= 1;
   end
end

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy = joystick_0 | joystick_1;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.forced_scandoubler(forced_scandoubler),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_fire2       <= pressed; // space
			'h014: btn_fire1       <= pressed; // ctrl

			//'h005: btn_one_player  <= pressed; // F1
			//'h006: btn_two_players <= pressed; // F2
			// JPAC/IPAC/MAME Style Codes

			'h005: btn_one_player  <= pressed; // F1
			'h006: btn_two_players <= pressed; // F2
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_fire1_2     <= pressed; // A
         'h01B: btn_fire2_2     <= pressed; // S			
			'h02C: btn_test        <= pressed; // T
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_fire1 = 0;
reg btn_fire2 = 0;
reg btn_one_player  = 0;
reg btn_two_players = 0;

reg btn_start_1=0;
reg btn_start_2=0;
reg btn_coin_1=0;
reg btn_coin_2=0;
reg btn_up_2=0;
reg btn_down_2=0;
reg btn_left_2=0;
reg btn_right_2=0;
reg btn_fire1_2=0;
reg btn_fire2_2=0;
reg btn_test=0;

wire m_up,m_down,m_left,m_right;
joy8way joy1
(
	clk_sys,
	{
		status[2] ? btn_left  | joy[1] : btn_up    | joy[3],
		status[2] ? btn_right | joy[0] : btn_down  | joy[2],
		status[2] ? btn_down  | joy[2] : btn_left  | joy[1],
		status[2] ? btn_up    | joy[3] : btn_right | joy[0]
	},
	{m_up,m_down,m_left,m_right}
);

wire m_up_2,m_down_2,m_left_2,m_right_2;
joy8way joy2
(
	clk_sys,
	{
		status[2] ? btn_left_2  | joy[1] : btn_up_2    | joy[3],
		status[2] ? btn_right_2 | joy[0] : btn_down_2  | joy[2],
		status[2] ? btn_down_2  | joy[2] : btn_left_2  | joy[1],
		status[2] ? btn_up_2    | joy[3] : btn_right_2 | joy[0]
	},
	{m_up_2,m_down_2,m_left_2,m_right_2}
);

wire m_fire1  = btn_fire1 | joy[4];
wire m_fire2  = btn_fire2 | joy[5];

wire m_fire1_2  = btn_fire1_2|joy[4];
wire m_fire2_2  = btn_fire2_2|joy[5];


wire m_start1 = btn_one_player  | joy[6];
wire m_start2 = btn_two_players | joy[7];
wire m_coin   = m_start1 | m_start2;


wire hblank, vblank;
//wire ce_vid = clk_sys;
wire hs, vs;
wire [3:0] r,g;
wire [3:0] b;


reg ce_pix;
always @(posedge clk_sys) begin
        reg old_clk;

        old_clk <= ce_6p;
        ce_pix <= old_clk & ~ce_6p;
end

arcade_rotate_fx #(266,224,12,0) arcade_video
(
        .*,

        .clk_video(clk_sys),

        .RGB_in({r,g,b}),
        .HBlank(hblank),
        .VBlank(vblank),
        .HSync(hs),
        .VSync(vs),

        .fx(status[5:3]),
        .no_rotate(status[2])
);
//screen_rotate #(264,224,12) screen_rotate

wire [9:0] audio;
assign AUDIO_L = {audio, 6'd0};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;

scobra_top scobra
(
	.O_VIDEO_R(r),
	.O_VIDEO_G(g),
	.O_VIDEO_B(b),
	.O_HSYNC(hs),
	.O_VSYNC(vs),
	.O_HBLANK(hblank),
	.O_VBLANK(vblank),

	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr),

	.O_AUDIO(audio),

	//.button_in(~{m_fire2, m_start2, m_fire1, m_coin, m_start1, m_right, m_left, m_down, m_up}),
	.ip_1p(~{m_start1|btn_start_1,m_fire2,m_fire1,m_left,m_right,m_up,m_down}),
	.ip_2p(~{m_start2|btn_start_2,m_fire2_2,m_fire1_2,m_left_2,m_right_2,m_up_2,m_down_2}),
   .ip_service(~status[14]),
	.ip_dip_switch(m_dip),
   .ip_coin1(m_coin|btn_coin_1|btn_coin_2),
   .ip_coin2(1'b0),

	.RESET(RESET | status[0] | ioctl_download | buttons[1]),
	.clk(clk_sys),
	.ena_12(ce_12),
	.ena_6(ce_6p),
	.ena_6b(ce_6n),
	.ena_1_79(ce_1p79)
);

endmodule

// Handle case where Up and Down are pressed simultaneously.
// Same for Left and Right.
module joy8way
(
	input        clk,
	input  [3:0] indir,
	output [3:0] outdir
);

reg  [3:0] out = 0;
reg  [3:0] in1,in2;
wire [3:0] innew = in1 & ~in2;
reg  [1:0] last_h,last_v;

assign outdir = out;

always @(posedge clk) begin
	
	in1 <= indir;
	in2 <= in1;
	
	if(innew[0]) last_h <= 2'b01; // R
	if(innew[1]) last_h <= 2'b10; // L
	if(innew[2]) last_v <= 2'b01; // D
	if(innew[3]) last_v <= 2'b10; // U
	
	out[1:0] <= in1[1:0] == 2'b11 ? last_h : in1[1:0]; 
	out[3:2] <= in1[3:2] == 2'b11 ? last_v : in1[3:2]; 
end

endmodule

