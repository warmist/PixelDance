require "common"
require "colors"

local luv=require "colors_luv"
local bwrite = require "blobwriter"
local bread = require "blobreader"
local size_mult=1
local ffi = require("ffi")
--[[
	TODO:
		some way of fitting a function to have a "fixed target"
		per-vertex "local_seed" for function selection for more fractal flame like work
		way to animate the shuffling...
		split very changing and non-changing (s/p) parts
		add LAB based color placement
			- start point has color, add it to end point
			- do real (from chrom. abber.) tonemapping
			- maybe 2d map of colors?
			- multiplicative blending for "absorption" like thing
--]]

win_w=win_w or 0
win_h=win_h or 0

aspect_ratio=aspect_ratio or 1
function update_size()
	local trg_w=1024*size_mult
	local trg_h=1024*size_mult
	--this is a workaround because if everytime you save
	--  you do __set_window_size it starts sending mouse through windows. SPOOKY
	if win_w~=trg_w or win_h~=trg_h then
		win_w=trg_w
		win_h=trg_h
		aspect_ratio=win_w/win_h
		__set_window_size(win_w,win_h)
	end
end
update_size()
local size=STATE.size

local max_palette_size=50
local need_clear=false
local oversample=1
local complex=true
local init_zero=false
local sample_count=math.pow(2,20)

str_x=str_x or "s.x"
str_y=str_y or "s.y"

str_cmplx=str_cmplx or "s"

str_other_code=str_other_code or ""
str_preamble=str_preamble or ""
str_postamble=str_postamble or ""
img_buf=make_image_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	print("new size:",w,h)
end

--i.e. the accumulation buffer
function make_visits_texture()
	if visit_tex==nil or visit_tex.w~=size[1]*oversample or visit_tex.h~=size[2]*oversample then
		visit_tex={t=textures:Make(),w=size[1]*oversample,h=size[2]*oversample}
		visit_tex.t:use(0,1)
		visit_tex.t:set(size[1]*oversample,size[2]*oversample,1)
		visit_buf=make_flt_buffer(size[1]*oversample,size[2]*oversample)
	end
end
-- samples i.e. random points that get transformed by IFS each step
function fill_rand_samples()
	local ss=ffi.cast("struct{uint32_t d[4];}*",samples_data.d)
	for i=0,sample_count-1 do
		ss[i].d[2]=math.random(0,4294967295)
		ss[i].d[3]=math.random(0,4294967295)
	end
end

if samples_data==nil or samples_data.w~=sample_count then
	samples_data=make_flt_buffer(sample_count,1)
	samples={buffer_data.Make(),buffer_data.Make(),current=1,other=2,flip=function( t )
		if t.current==1 then
			t.current=2
			t.other=1
		else
			t.current=1
			t.other=2
		end
	end,
	get_current=function (t)
		return t[t.current]
	end,
	get_other=function ( t )
		return t[t.other]
	end}
	need_clear=true
	-- [[ needs to duplicate the point init logic so dont
	for i=0,sample_count-1 do
		local x=0--math.random()
		local y=0--math.random()
		samples_data:set(i,0,{x,y,x,y})
	end
	fill_rand_samples()
	for i=1,2 do
		samples[i]:use()
		samples[i]:set(samples_data.d,sample_count*4*4)
	end
	__unbind_buffer()
	--]]
end

tick=tick or 0
config=make_config({
	{"draw",true,type="boolean"},
	{"point_size",0,type="int",min=0,max=10},
	{"size_mult",true,type="boolean"},

	{"v0",0,type="float",min=-1,max=1},
	{"v1",0,type="float",min=-1,max=1},
	{"v2",0,type="float",min=-1,max=1},
	{"v3",0,type="float",min=-1,max=1},

	

	{"IFS_steps",50,type="int",min=1,max=1000},
	{"smart_reset",false,type="boolean"},
	{"move_dist",0.4,type="float",min=0.001,max=2},
	{"scale",1,type="float",min=0.00001,max=2},

	{"cx",0,type="float",min=-10,max=10},
	{"cy",0,type="float",min=-10,max=10},
	{"shuffle_size",5,type="int",min=1,max=200},
	--{"min_value",0,type="float",min=0,max=20},
	--{"gen_radius",2,type="float",min=0,max=10},

	{"gamma",1,type="float",min=0.01,max=5},
	{"exposure",1,type="float",min=0,max=10},
	{"white_point",1,type="float",min=0,max=10},

	{"max_bright",1.0,type="float",min=0,max=2},
	{"contrast",1.0,type="float",min=0,max=2},
	{"linear_start",0.22,type="float",min=0,max=2},
	{"linear_len",0.4,type="float",min=0,max=1},
	{"black_tight",1.33,type="float",min=0,max=2},
	{"black_off",0,type="float",min=0,max=1},
	{"animation",0,type="float",min=0,max=1},
	{"reshuffle",false,type="boolean"},
},config)

local display_shader=shaders.Make[==[
#version 330
#line 139

out vec4 color;
in vec3 pos;

uniform vec4 palette[50];
uniform int palette_size;

uniform vec2 min_max;
uniform sampler2D tex_main;
uniform sampler2D tex_palette;
uniform int auto_scale_color;
uniform float v_gamma;

uniform float avg_lum;
uniform float exposure;
uniform float white_point;

uniform float uchimura_params[6];

#define M_PI   3.14159265358979323846264338327950288

vec4 mix_palette(float value )
{
	if (palette_size==0)
		return vec4(0);

	//value=clamp(value,0,1);
	return texture(tex_palette,vec2(value,0));
}
vec4 mix_palette2(float value )
{
	if (palette_size==0)
		return vec4(0);
	value=clamp(value,0,1);
	float tg=value*(float(palette_size)-1); //[0,1]-->[0,#colors]
	float tl=floor(tg);

	float t=tg-tl;
	vec4 c1=palette[int(tl)];
	int hidx=min(int(ceil(tg)),palette_size-1);
	vec4 c2=palette[hidx];
	return mix(c1,c2,t);
}

float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}

vec3 rgb2xyz( vec3 c ) {
    vec3 tmp;
    tmp.x = ( c.r > 0.04045 ) ? pow( ( c.r + 0.055 ) / 1.055, 2.4 ) : c.r / 12.92;
    tmp.y = ( c.g > 0.04045 ) ? pow( ( c.g + 0.055 ) / 1.055, 2.4 ) : c.g / 12.92,
    tmp.z = ( c.b > 0.04045 ) ? pow( ( c.b + 0.055 ) / 1.055, 2.4 ) : c.b / 12.92;
    return 100.0 * tmp *
        mat3( 0.4124, 0.3576, 0.1805,
              0.2126, 0.7152, 0.0722,
              0.0193, 0.1192, 0.9505 );
}

vec3 xyz2lab( vec3 c ) {
    vec3 n = c / vec3( 95.047, 100, 108.883 );
    vec3 v;
    v.x = ( n.x > 0.008856 ) ? pow( n.x, 1.0 / 3.0 ) : ( 7.787 * n.x ) + ( 16.0 / 116.0 );
    v.y = ( n.y > 0.008856 ) ? pow( n.y, 1.0 / 3.0 ) : ( 7.787 * n.y ) + ( 16.0 / 116.0 );
    v.z = ( n.z > 0.008856 ) ? pow( n.z, 1.0 / 3.0 ) : ( 7.787 * n.z ) + ( 16.0 / 116.0 );
    return vec3(( 116.0 * v.y ) - 16.0, 500.0 * ( v.x - v.y ), 200.0 * ( v.y - v.z ));
}

vec3 rgb2lab(vec3 c) {
    vec3 lab = xyz2lab( rgb2xyz( c ) );
    return vec3( lab.x / 100.0, 0.5 + 0.5 * ( lab.y / 127.0 ), 0.5 + 0.5 * ( lab.z / 127.0 ));
}

vec3 lab2xyz( vec3 c ) {
    float fy = ( c.x + 16.0 ) / 116.0;
    float fx = c.y / 500.0 + fy;
    float fz = fy - c.z / 200.0;
    return vec3(
         95.047 * (( fx > 0.206897 ) ? fx * fx * fx : ( fx - 16.0 / 116.0 ) / 7.787),
        100.000 * (( fy > 0.206897 ) ? fy * fy * fy : ( fy - 16.0 / 116.0 ) / 7.787),
        108.883 * (( fz > 0.206897 ) ? fz * fz * fz : ( fz - 16.0 / 116.0 ) / 7.787)
    );
}

vec3 xyz2rgb( vec3 c ) {
    vec3 v =  c / 100.0 * mat3(
        3.2406, -1.5372, -0.4986,
        -0.9689, 1.8758, 0.0415,
        0.0557, -0.2040, 1.0570
    );
    vec3 r;
    r.x = ( v.r > 0.0031308 ) ? (( 1.055 * pow( v.r, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.r;
    r.y = ( v.g > 0.0031308 ) ? (( 1.055 * pow( v.g, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.g;
    r.z = ( v.b > 0.0031308 ) ? (( 1.055 * pow( v.b, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.b;
    return r;
}

vec3 lab2rgb(vec3 c) {
    return xyz2rgb( lab2xyz( vec3(100.0 * c.x, 2.0 * 127.0 * (c.y - 0.5), 2.0 * 127.0 * (c.z - 0.5)) ) );
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 tonemap_old(vec3 light)
{
	float lum_white = pow(10,white_point);
	//lum_white*=lum_white;

	//tocieYxy
	float sum=light.x+light.y+light.z;
	float x=light.x/sum;
	float y=light.y/sum;
	float Y=light.y;

	Y = (Y* exposure )/avg_lum;
	if(white_point<0)
    	Y = Y / (1 + Y); //simple compression
	else
    	Y = (Y*(1 + Y / lum_white)) / (Y + 1); //allow to burn out bright areas


    //transform back to cieXYZ
    light.y=Y;
    float small_x = x;
    float small_y = y;
    light.x = light.y*(small_x / small_y);
    light.z = light.x / small_x - light.x - light.y;

    return light;
}
float Tonemap_ACES(float x) {
    // Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}
//https://www.shadertoy.com/view/WdjSW3
float Tonemap_Uchimura(float x, float P, float a, float m, float l, float c, float b) {
    // Uchimura 2017, "HDR theory and practice"
    // Math: https://www.desmos.com/calculator/gslcdxvipg
    // Source: https://www.slideshare.net/nikuque/hdr-theory-and-practicce-jp
    float l0 = ((P - m) * l) / a;
    float L0 = m - m / a;
    float L1 = m + (1.0 - m) / a;
    float S0 = m + l0;
    float S1 = m + a * l0;
    float C2 = (a * P) / (P - S1);
    float CP = -C2 / P;

    float w0 = 1.0 - smoothstep(0.0, m, x);
    float w2 = step(m + l0, x);
    float w1 = 1.0 - w0 - w2;

    float T = m * pow(x / m, c) + b;
    float S = P - (P - S1) * exp(CP * (x - S0));
    float L = m + a * (x - m);

    return T * w0 + L * w1 + S * w2;
}

float Tonemap_Uchimura(float x) {
    float P = uchimura_params[0];  // max display brightness
    float a = uchimura_params[1];  // contrast
    float m = uchimura_params[2]; // linear section start
    float l = uchimura_params[3];  // linear section length
    float c = uchimura_params[4]; // black
    float b = uchimura_params[5];  // pedestal
    return Tonemap_Uchimura(x, P, a, m, l, c, b);
}
vec3 tonemap(vec3 light)
{
	float lum_white =white_point*white_point;// pow(10,white_point);
	//lum_white*=lum_white;

	//tocieYxy
	float sum=light.x+light.y+light.z;
	float x=light.x/sum;
	float y=light.y/sum;
	float Y=light.y;

	Y=Y/(9.6*avg_lum);
	//Y=(Y-min_max.x)/(min_max.y-min_max.x);
	//Y=(log(Y+1)-log(min_max.x+1))/(log(min_max.y+1)-log(min_max.x+1));
	//Y=log(Y+1)/log(min_max.y+1);
#if 0
	Y=Tonemap_Uchimura(Y);
#else
	if(white_point<0)
    	Y = Y / (1 + Y); //simple compression
	else
    	Y = (Y*(1 + Y / lum_white)) / (Y + 1); //allow to burn out bright areas
#endif

    //transform back to cieXYZ
    light.y=Y;
    float small_x = x;
    float small_y = y;
    light.x = light.y*(small_x / small_y);
    light.z = light.x / small_x - light.x - light.y;
    //light=clamp(light,0,1);
    return xyz2rgb(light*100);
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec3 ccol=texture(tex_main,normed).xyz;

	/*
	if(ccol.x<0)ccol.x=log(1-ccol.x);
	if(ccol.y<0)ccol.y=log(1-ccol.y);
	if(ccol.z<0)ccol.z=log(1-ccol.z);
	//*/

	//ccol=abs(ccol);
	ccol=max(vec3(0),ccol);
	ccol=pow(ccol,vec3(v_gamma));
	color = vec4(tonemap(ccol),1);
	color.xyz=pow(color.xyz,vec3(2.2));
	color.a=1;
}
]==]


local need_save
local need_buffer_save
function buffer_save( name ,min,max,avg)
	local b=bwrite()
	b:u32(visit_buf.w)
	b:u32(visit_buf.h)
	b:f32(min[1])
	b:f32(min[2])
	b:f32(min[3])
	b:f32(max[1])
	b:f32(max[2])
	b:f32(max[3])
	b:f32(avg)
	for x=0,visit_buf.w-1 do
	for y=0,visit_buf.h-1 do
		local v=visit_buf:get(x,y)
		b:f32(v.r)
		b:f32(v.g)
		b:f32(v.b)
		b:f32(v.a)
	end
	end
	local f=io.open(name,"wb")
	f:write(b:tostring())
	f:close()
end

visits_minmax=visits_minmax or {}
function find_min_max( tex,buf )
	tex:use(0,1)
	local lmin={math.huge,math.huge,math.huge}
	local lmax={-math.huge,-math.huge,-math.huge}

	buf:read_texture(tex)
	local avg_lum=0
	local count=0
	for x=0,buf.w-1 do
	for y=0,buf.h-1 do
		local v=buf:get(x,y)
		if v.r<lmin[1] then lmin[1]=v.r end
		if v.g<lmin[2] then lmin[2]=v.g end
		if v.b<lmin[3] then lmin[3]=v.b end

		if v.r>lmax[1] then lmax[1]=v.r end
		if v.g>lmax[2] then lmax[2]=v.g end
		if v.b>lmax[3] then lmax[3]=v.b end
		local lum=math.abs(v.g)
		--if lum > config.min_value then
			avg_lum=avg_lum+math.log(1+lum)
			count=count+1
		--end
	end
	end
	avg_lum = math.exp(avg_lum / count);
	--[[print(avg_lum)
	for i,v in ipairs(lmax) do
		print(i,v)
	end
	--]]
	return lmin,lmax,avg_lum
end
function draw_visits(  )

	make_visits_texture()
	local lmin,lmax,lavg=find_min_max(visit_tex.t,visit_buf)

	visits_minmax={lmin,lmax}

	if need_buffer_save then
		buffer_save(need_buffer_save,visits_minmax[1],visits_minmax[2],lavg)
		need_buffer_save=nil
	end

	display_shader:use()
	visit_tex.t:use(0,1)
	set_shader_palette(display_shader)
	display_shader:set("min_max",lmin[2],lmax[2])

	display_shader:set("uchimura_params[0]",config.max_bright)
	display_shader:set("uchimura_params[1]",config.contrast)
	display_shader:set("uchimura_params[2]",config.linear_start)
	display_shader:set("uchimura_params[3]",config.linear_len)
	display_shader:set("uchimura_params[4]",config.black_tight)
	display_shader:set("uchimura_params[5]",config.black_off)

	display_shader:set("avg_lum",lavg)
	display_shader:set_i("tex_main",0)
	display_shader:set("v_gamma",config.gamma)

	display_shader:set("exposure",config.exposure)
	display_shader:set("white_point",config.white_point)
	display_shader:draw_quad()

	if need_save then
		save_img()
		need_save=nil
	end
end

palette=palette or {show=false,
rgb_lerp=false,
current_gen=1,
colors_input={{0.01, 0.01, 0.01, 0,0},{0.25,0.25,0.25,1,math.floor(max_palette_size*0.5)},{.99, .99, .99, 1,max_palette_size-1}}}
function update_palette_img(  )
	if palette_img.w~=#palette.colors_input then
		palette_img=make_flt_buffer(#palette.colors_input,1)
	end
	for i,v in ipairs(palette.colors_input) do
		palette_img:set(i-1,0,v)
	end
end
function lerp_hue( h1,h2,local_v )

	if math.abs(h1-h2)>0.5 then
		--loop around lerp (i.e. modular lerp)

		local v=(h1-h2)*local_v+h1
		if v<0 then
			local a1=h2-h1
			local a=((1-h2)*a1)/(h1-a1)
			local b=h2-a
			v=(a)*(local_v)+b
		end
		return v
	else
		--normal lerp
		return (h2-h1)*local_v+h1
	end
end
function mix_color_hsl(c1,c2,v)
	local c1_v=c1[5]
	local c2_v=c2[5]
	local c_v=c2_v-c1_v
	local my_v=v-c1_v
	local local_v=my_v/c_v

	local ret={}
	ret[1]=lerp_hue(c1[1],c2[1],local_v)
	for i=2,4 do --normal lerp for s/l args
		ret[i]=(c2[i]-c1[i])*local_v+c1[i]
	end
	local r2=luv.hsluv_to_rgb{ret[1]*360,ret[2]*100,ret[3]*100}
	r2[4]=ret[4]
	return r2
end
function mix_color_rgb( c1,c2,v )
	local c1_v=c1[5]
	local c2_v=c2[5]
	local c_v=c2_v-c1_v
	local my_v=v-c1_v
	local local_v=my_v/c_v

	local c1_rgb=luv.hsluv_to_rgb{c1[1]*360,c1[2]*100,c1[3]*100}
	local c2_rgb=luv.hsluv_to_rgb{c2[1]*360,c2[2]*100,c2[3]*100}
	local ret={}
	for i=1,3 do
		ret[i]=(c2_rgb[i]-c1_rgb[i])*local_v+c1_rgb[i]
	end
	ret[4]=(c2[4]-c1[4])*local_v+c1[4]
	return ret
end
function set_shader_palette(s)
	s:set_i("palette_size",max_palette_size)
	local cur_color=2
	for i=0,max_palette_size-1 do
		if palette.colors_input[cur_color][5] < i then
			cur_color=cur_color+1
		end
		local c
		if palette.rgb_lerp then
			c=mix_color_rgb(palette.colors_input[cur_color-1],palette.colors_input[cur_color],i)
		else
			c=mix_color_hsl(palette.colors_input[cur_color-1],palette.colors_input[cur_color],i)
		end
		s:set(string.format("palette[%d]",i),c[1],c[2],c[3],c[4])
	end
end
function rand_range( t )
	return math.random()*(t[2]-t[1])+t[1]
end
function new_color( h,s,l,pos )
	local r={h,s,l}--luv.hsluv_to_rgb{(h)*360,(s)*100,(l)*100}
	r[4]=1
	r[5]=pos
	return r
end

palette.generators={
	{"random",function (ret, hue_range,sat_range,lit_range )
		local count=math.random(2,10)
		--local count=2
		for i=1,count do
			local nh,ns,nl
			nh=rand_range(hue_range)
			ns=rand_range(sat_range)
			nl=rand_range(lit_range)
			local pos=math.floor(((i-1)/(count-1))*(max_palette_size-1))
			local r=new_color(nh,ns,nl,pos)

			r[4]=1
			if i==count then
				r[5]=max_palette_size-1
			end
			table.insert(ret,r)
		end

	end
	},{"shades",function(ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)

		local r1=new_color(h1,s,l,0)
		local r2=new_color(h1,s2,l2,max_palette_size-1)

		table.insert(ret,r1)
		table.insert(ret,r2)
	end,
	},{"complementary",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)
		local r1={(h1),(s),(l)}
		r1[4]=1
		local r2={(1-h1),(s2),(l2)}
		r2[4]=1
		r1[5]=0
		r2[5]=max_palette_size-1
		table.insert(ret,r1)
		table.insert(ret,r2)
	end,
	},{"complementary_dark",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)
		local r1={(h1),(s),(l)}
		r1[4]=1
		local r2={(1-h1),(s2),(l2)}
		r2[4]=1
		r1[5]=0
		r2[5]=max_palette_size-1
		table.insert(ret,r1)
		table.insert(ret,{0,0,0,1,math.floor(max_palette_size/2)})
		table.insert(ret,r2)
	end,
	},{"triadic",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)
		local s3=rand_range(sat_range)
		local l3=rand_range(lit_range)
		local h2=math.fmod(h1+0.33,1)
		local h3=math.fmod(h1+0.66,1)

		table.insert(ret,new_color(h1,s,l,0))
		table.insert(ret,new_color(h2,s2,l2,math.floor(max_palette_size/2)))
		table.insert(ret,new_color(h3,s3,l3,max_palette_size-1))
	end,
	},{"compound",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)
		local s3=rand_range(sat_range)
		local l3=rand_range(lit_range)
		local d=math.random()*0.3
		local h2=math.fmod(h1+0.5-d,1)
		local h3=math.fmod(h1+0.5+d,1)

		table.insert(ret,new_color(h1,s,l,0))
		table.insert(ret,new_color(h2,s2,l2,math.floor(max_palette_size/2)))
		table.insert(ret,new_color(h3,s3,l3,max_palette_size-1))
	end,
	},{"anologous",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)
		local hue_step=0.05
		local max_step=3
		for i=0,max_step do
			local h2=math.fmod(h1+hue_step*i,1)
			local s2=s+math.random()*0.4-0.2
			if s2>1 then s2=1 end
			if s2<0 then s2=0 end
			local l2=l+math.random()*0.4-0.2
			if l2>1 then l2=1 end
			if l2<0 then l2=0 end

			table.insert(ret,new_color(h2,s2,l2,((i)/max_step)*(max_palette_size-1)))
		end
	end}
}
function gen_palette( )
	local ret={}
	palette.colors_input=ret
	local hue_range={0,1}
	local sat_range={0,1}
	local lit_range={0,1}

	local h1=rand_range(hue_range)
	local s=rand_range(sat_range)
	local l=rand_range(lit_range)

	palette.generators[palette.current_gen][2](ret,hue_range,sat_range,lit_range)
end
function print_col( c )
	for i,v in ipairs(c) do
		print(i,v)
	end
end
function color_edit_luv(key, col ,alpha)

	local changing,new_col
	local ncol=luv.hsluv_to_rgb{col[1]*360,col[2]*100,col[3]*100}
	ncol[4]=col[4]

	changing,new_col=imgui.ColorEdit4(key,ncol,alpha)

	local ret=luv.rgb_to_hsluv(new_col)
	ret[1]=ret[1]/360
	ret[2]=ret[2]/100
	ret[3]=ret[3]/100
	ret[4]=new_col[4]

	return changing,ret
end
function palette_chooser()
	if imgui.RadioButton("Show palette",palette.show) then
		palette.show=not palette.show
	end
	imgui.SameLine()
	if imgui.Button("Randomize") then
		gen_palette()
		need_clear=true
	end
	imgui.SameLine()
	local generators={
	}
	for k,v in ipairs(palette.generators) do
		table.insert(generators,v[1])
	end
	local changing = false
	changing,palette.current_gen=imgui.Combo("Generator",palette.current_gen-1,generators)
	palette.current_gen=palette.current_gen+1
	if palette.colors_input[palette.current]==nil then
		palette.current=1
	end
	palette.current=palette.current or 1

	if palette.show then
		if #palette.colors_input>0 then
			_,palette.current=imgui.SliderInt("Color id",palette.current,1,#palette.colors_input)
		end
		imgui.SameLine()
		if #palette.colors_input<max_palette_size then
			if imgui.Button("Add") then
				table.insert(palette.colors_input,{0,0,0,1})
				if palette.current<1 then
					palette.current=1
				end
			end
		end
		if #palette.colors_input>0 then
			imgui.SameLine()
			if imgui.Button("Remove") then
				table.remove(palette.colors_input,palette.current)
				palette.current=1
			end
			if imgui.Button("Print") then
				for i,v in ipairs(palette.colors_input) do
					print(string.format("%g %g %g %g %d",v[1],v[2],v[3],v[4],v[5]))

				end
			end
			imgui.SameLine()
			if imgui.RadioButton("rgb lerp",palette.rgb_lerp) then
				palette.rgb_lerp=not palette.rgb_lerp
			end
		end
		if #palette.colors_input>0 then
			local cur_v=palette.colors_input[palette.current]
			local new_col,ne_pos
			_,new_col=color_edit_luv("Current color",cur_v,false)
			_,new_pos=imgui.SliderInt("Color place",cur_v[5],0,max_palette_size-1)
			if palette.current==1 then
				new_pos=0
			elseif palette.current==#palette.colors_input then
				new_pos=max_palette_size-1
			end
			for i=1,4 do
				cur_v[i]=new_col[i]
			end
			cur_v[5]=new_pos
		end
	end
end
function palette_serialize(  )
	local ret="palette={show=false,rgb_lerp=%s,current_gen=%d,colors_input={%s}}\n"
	local pal=""
	for i,v in ipairs(palette.colors_input) do
		pal=pal..string.format("{%f,%f,%f,%f,%d},",v[1],v[2],v[3],v[4],v[5])
	end
	return string.format(ret,palette.rgb_lerp,palette.current_gen,pal)
end
function save_img()
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	config_serial=config_serial..string.format("str_other_code=%q\n",str_other_code)
	config_serial=config_serial..string.format("str_x=%q\n",str_x)
	config_serial=config_serial..string.format("str_y=%q\n",str_y)
	config_serial=config_serial..string.format("str_cmplx=%q\n",str_cmplx)
	config_serial=config_serial..string.format("str_preamble=%q\n",str_preamble)
	config_serial=config_serial..string.format("str_postamble=%q\n",str_postamble)
	config_serial=config_serial..palette_serialize()
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end


local terminal_symbols={
["s.x"]=3,["s.y"]=3,["p.x"]=3,["p.y"]=3,
["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,
["normed_iter"]=0.05,
["1.0"]=0.1,["0.0"]=0.1
}
local terminal_symbols_alt={
["p.x"]=3,["p.y"]=3
}
local terminal_symbols_param={
["s.x"]=10,["s.y"]=10,
["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,
["normed_iter"]=0.05
}
local normal_symbols={
["max(R,R)"]=0.05,["min(R,R)"]=0.05,
["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,
["abs(R)"]=0.1,["sqrt(R)"]=0.1,["exp(R)"]=0.01,
["atan(R,R)"]=0.1,["acos(R)"]=0.1,["asin(R)"]=0.1,
["tan(R)"]=0.1,["sin(R)"]=0.1,["cos(R)"]=0.1,["log(R)"]=0.1,
["(R)/(R)"]=2,["(R)*(R)"]=6,
["(R)-(R)"]=2,["(R)+(R)"]=2
}

local terminal_symbols_complex={
["s"]=3,["p"]=3,
["params.xy"]=1,["params.zw"]=1,
["(c_one()*normed_iter)"]=0.05,["(c_i()*normed_iter)"]=0.05,["c_one()"]=0.1,["c_i()"]=0.1,
}
local terminal_symbols_complex_const={
["c_one()"]=1,["c_i()"]=0.1,
["vec2(0.25,0)"]=0.1,["vec2(0,0.25)"]=0.01,
["vec2(0.25,0.25)"]=0.01,["vec2(0.15,0.125)"]=0.01,
["vec2(-0.5)"]=0.01,["vec2(-1,0)"]=0.1,
["vec2(0,-1)"]=0.03
}
local normal_symbols_complex={
-- [=[
["c_sqrt(R)"]=1,
["c_ln(R)"]=0.1,["c_exp(R)"]=0.01,
["c_acos(R)"]=0.1,["c_asin(R)"]=0.1,["c_atan(R)"]=0.1,
["c_tan(R)"]=1,["c_sin(R)"]=1,["c_cos(R)"]=1,
["c_conj(R)"]=1,
--]=]
["c_div(R,R)"]=0.01,["c_inv(R)"]=1,
["c_mul(R,R)"]=2,
["(R)-(R)"]=3,["(R)+(R)"]=3
}
local terminal_symbols_FT={
["t"]=0.5,["c"]=0.5,
["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,
["1.0"]=0.01,["0.0"]=0.01
}
local terminal_symbols_complex_FT={
["vec2(t,0)"]=1,
["vec2(0,t)"]=1,
["vec2(c,0)"]=1,
["vec2(0,c)"]=1,
["vec2(t,c)"]=3,
["vec2(c,t)"]=3,
["params.xy"]=1,["params.zw"]=1,
["c_one()"]=0.1,["c_i()"]=0.1,
}
local normal_symbols_FT={
["max(R,R)"]=0.05,["min(R,R)"]=0.05,["mod(R,R)"]=0.1,
["fract(R)"]=0.1,["floor(R)"]=0.1,["abs(R)"]=0.1,
["sqrt(R)"]=0.1,["exp(R)"]=0.01,
["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,
["log(R)"]=1,["(R)/(R)"]=2,["(R)*(R)"]=4,["(R)-(R)"]=2,["(R)+(R)"]=2
}
function normalize( tbl )
	local sum=0
	for i,v in pairs(tbl) do
		sum=sum+v
	end
	for i,v in pairs(tbl) do
		tbl[i]=tbl[i]/sum
	end
end
normalize(terminal_symbols)
normalize(terminal_symbols_alt)
normalize(terminal_symbols_param)

normalize(normal_symbols)

normalize(terminal_symbols_complex)
normalize(terminal_symbols_complex_const)
normalize(normal_symbols_complex)

normalize(terminal_symbols_FT)
normalize(terminal_symbols_complex_FT)
normalize(normal_symbols_FT)

function rand_weighted(tbl)
	local r=math.random()
	local sum=0
	for i,v in pairs(tbl) do
		sum=sum+v
		if sum>= r then
			return i
		end
	end
end
function replace_random( s,substr,rep )
	local num_match=0
	local function count(  )
		num_match=num_match+1
		return false
	end
	string.gsub(s,substr,count)
	num_rep=math.random(0,num_match-1)
	function rep_one(  )
		if num_rep==0 then
			num_rep=num_rep-1
			if type(rep)=="function" then
				return rep()
			else
				return rep
			end
		else
			num_rep=num_rep-1
			return false
		end
	end
	local ret=string.gsub(s,substr,rep_one)
	return ret
end
function make_rand_math( normal_s,terminal_s,forced_s )
	forced_s=forced_s or {}
	return function ( steps,seed,force_values)
		local cur_string=seed or "R"
		force_values=force_values or forced_s
		function M(  )
			return rand_weighted(normal_s)
		end
		function MT(  )
			return rand_weighted(terminal_s)
		end

		for i=1,steps do
			cur_string=replace_random(cur_string,"R",M)
		end
		for i,v in ipairs(force_values) do
			cur_string=replace_random(cur_string,"R",v)
		end
		cur_string=string.gsub(cur_string,"R",MT)
		return cur_string
	end
end
random_math=make_rand_math(normal_symbols,terminal_symbols)
random_math_complex=make_rand_math(normal_symbols_complex,terminal_symbols_complex)
random_math_complex_const=make_rand_math(normal_symbols_complex,terminal_symbols_complex_const)

random_math_x=make_rand_math(normal_symbols,terminal_symbols,{"s.x","params.x","p.x"})
random_math_y=make_rand_math(normal_symbols,terminal_symbols,{"s.y","params.y","p.y"})

random_math_FT=make_rand_math(normal_symbols_FT,terminal_symbols_FT,{"c","t"})
random_math_complex_FT=make_rand_math(normal_symbols_complex,terminal_symbols_complex_FT,{"vec2(c,t)","params.xy","params.zw"})

function random_math_complex_pts(steps,pts,seed )
	local cur_string=seed or "R"

	function M(  )
		return rand_weighted(normal_symbols_complex)
	end
	function MT(  )
		local p=pts[math.random(1,#pts)]
		return rand_weighted(terminal_symbols_complex)..string.format("+vec2(%.3f,%.3f)",p[1],p[2])
	end

	for i=1,steps do
		cur_string=replace_random(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
function random_math_complex_intervals(steps,count_intervals,seed,force_values )
	local cur_string=seed or "R"
	local rc=random_math_complex(steps,seed,force_values)
	local ret=""
	for i=1,count_intervals do
		local istart=(i-1)/count_intervals
		local iend=(i)/count_intervals
		--[[
		local dx=math.random()*2-1
		local dy=math.sqrt(1-dx*dx)--math.random()*0.5-0.25
		if math.random()>0.5 then
			dy=-dy
		end
		local dx2=math.random()*0.5-0.25
		local dy2=math.random()*0.5-0.25
		--]]
		--[[
		local dx=math.cos(istart*math.pi*2)*1
		local dy=math.sin(istart*math.pi*2)*1
		--]]
		-- [[
		local dx=0
		local dy=0
		--]]
		ret=ret.."("..rc..string.format("+vec2(%g,%g))*value_inside(global_seed,%g,%g)",dx,dy,istart,iend)
		--[[
		if i==1 then
			ret=ret..string.format("(c_mul(%s,vec2(%g,%g))+vec2(%g,%g))*value_inside(global_seed,%g,%g)",rc,dx,dy,dx2,dy2,istart,iend)
		else
			ret=ret..string.format("(c_mul(s,vec2(%g,%g))+vec2(%g,%g))*value_inside(global_seed,%g,%g)",dx,dy,dx2,dy2,istart,iend)
		end
		--]]
		--ret=ret..string.format("(c_pow(s,%d)+p+vec2(%g,%g))*value_inside(global_seed,%g,%g)",i+1,dx,dy,istart,iend)
		if i~=count_intervals then
			ret=ret.."+"
		end
		--rc="c_mul("..rc..","..random_math_complex(3,seed)..")"
		rc=random_math_complex(math.random(math.min(5,steps),steps),seed,force_values)
	end
	return ret
end
function random_math_intervals(is_dx,steps,count_intervals,seed,force_values )
	local cur_string=seed or "R"
	local rc=random_math(steps,seed,force_values)
	local ret=""
	for i=1,count_intervals do
		local istart=(i-1)/count_intervals
		local iend=(i)/count_intervals
		-- [[
		local dx=math.random()*2-1
		local dy=math.sqrt(1-dx*dx)--math.random()*0.5-0.25
		if math.random()>0.5 then
			dy=-dy
		end
		local dx2=math.random()*0.5-0.25
		local dy2=math.random()*0.5-0.25
		--]]
		--[[
		local dx=math.cos(istart*math.pi*2)*1
		local dy=math.sin(istart*math.pi*2)*1
		--]]
		--[[x
		local dx=0
		local dy=0
		--]]
		local delta=dx
		if not is_dx then delta=dy end

		ret=ret.."("..rc..string.format("+%g)*value_inside(global_seed,%g,%g)",dy,istart,iend)
		if i~=count_intervals then
			ret=ret.."+"
		end
		--rc="c_mul("..rc..","..random_math(3,seed)..")"
		rc=random_math(steps,seed,force_values)
	end
	return ret
end
function factorial( n )
	if n<=1 then return 1 end
	return n*factorial(n-1)
end
function random_math_complex_series( steps,seed )
	local cur_string= seed or "0"
	function MT(  )
		return rand_weighted(terminal_symbols_complex)
	end
	--local id1=math.random(1,steps)
	--local id2=math.random(1,steps)
	--local comp=random_math_complex(steps)
	for i=1,steps do
		local comp=MT()
		local sub_s=comp
		for i=1,i do
			sub_s=string.format("c_mul(%s,%s)",comp,sub_s)
		end
		sub_s=string.format("%s*%g",sub_s,1/factorial(i))
		--[[
		if i==id1 then
			cur_string=cur_string..string.format("+c_mul(%s,params.xy)",sub_s)
		elseif i==id2 then
			cur_string=cur_string..string.format("+c_mul(%s,params.zw)",sub_s)
		else
			cur_string=cur_string..string.format("+c_mul(%s,vec2(%.3f,%.3f))",sub_s,math.random()*2-1,math.random()*2-1)
		end
		--]]

		-- [[
		if i==id1 then
			cur_string=cur_string..string.format("+%s*params.xy",sub_s)
		elseif i==id2 then
			cur_string=cur_string..string.format("+%s*params.zw",sub_s)
		else
			cur_string=cur_string..string.format("+%s*vec2(%.3f,%.3f)",sub_s,1+math.random()*0.25-0.125,1+math.random()*0.25-0.125)
		end
		--]]
	end
	return cur_string
end
function random_math_complex_series_t( steps,seed,offset )
	offset=offset or 0
	seed=seed or "p"
	local cur_string=seed
	function MT(  )
		return rand_weighted(terminal_symbols_complex)
	end

	for i=1,steps do
		local sub_s=seed
		for i=1,i do
			sub_s=string.format("c_mul(%s,%s)",sub_s,seed)
		end
		sub_s=string.format("%s*%g",sub_s,1/factorial(i))

		cur_string=cur_string..string.format("+c_mul(%s,FT(normed_iter,%g))",sub_s,(i-1)/steps+offset)
	end
	return cur_string
end

function random_math_centered(steps,complications,seed )
	local cur_string=("R+%.3f"):format(math.random()*2-1) or seed
	for i=1,steps do
		cur_string=cur_string..("+R*%.3f"):format(math.random()*2-1)
	end

	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end

	for i=1,complications do
		cur_string=replace_random(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end

function random_math_fourier( steps,complications ,seed)
	local cur_string=seed or "(R)/2"
	for i=1,steps do
		cur_string=cur_string..("+(R)*sin(2*%d*M_PI*(Q)+R)"):format(i)
	end
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end
	function MQT( )
		return rand_weighted(terminal_symbols_alt)
	end

	for i=1,complications do
		cur_string=replace_random(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"Q",MQT)
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
function random_math_fourier_complex( steps,complications ,seed,force_values)
	local cur_string=seed or "(R)/2"
	local period=1
	for i=1,steps do
		cur_string=cur_string..("+(R)*c_exp(vec2(0,2*%d*M_PI/%g))"):format(i,period)
	end
	function M(  )
		return rand_weighted(normal_symbols_complex)
	end
	function MT(  )
		return rand_weighted(terminal_symbols_complex)
	end
	for i=1,complications do
		cur_string=replace_random(cur_string,"R",M)
	end
	for i,v in ipairs(force_values or {}) do
		cur_string=replace_random(cur_string,"R",v)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
function random_math_power( steps,complications,seed )
	local cur_string=seed or "R"
	for i=1,steps do
		local QS=""
		for j=1,i do
			QS=QS.."*(Q)"
		end
		cur_string=cur_string..("+(R)%s"):format(QS)
	end
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols_param)
	end
	function MQT( )
		return rand_weighted(terminal_symbols_alt)
	end

	for i=1,complications do
		cur_string=replace_random(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"Q",MQT)
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
animate=false
function rand_function(  )
	local s=random_math(rand_complexity)
	--str_cmplx=random_math_complex(rand_complexity,nil,{"s","p","vec2(cos(global_seed*2*M_PI),sin(global_seed*2*M_PI))","params.xy","params.zw"})--{"vec2(global_seed,0)","vec2(0,1-global_seed)"})
	--str_cmplx=random_math_complex(rand_complexity,nil,{"s","p*vec2(move_dist,global_seed)","params.xy","params.zw"})
	--str_cmplx=random_math_complex_const(rand_complexity,nil,{"s","p*vec2(move_dist,global_seed)","params.xy","params.zw"})
	str_cmplx=random_math_complex_intervals(rand_complexity,7,nil,{"s","p","params.xy","params.zw"})
	--str_cmplx=random_math_complex_intervals(rand_complexity,15,"(R)/2+(R)*c_sin(vec2(2*M_PI,1)*(R)+R)")
	--str_cmplx=random_math_fourier_complex(7,rand_complexity)
	--str_cmplx=random_math_complex_series(4,random_math_complex_intervals(rand_complexity,5))
	--str_cmplx="c_inv(((s)-((c_cos((vec2(global_seed,0))+(s)))-(c_asin(s))))-(c_conj(c_cos(c_inv(s)))))"
	--str_cmplx="c_inv((s-c_cos(vec2(global_seed,0)+s)+c_asin(s+params.xy))-c_conj(c_mul(c_cos(c_inv(s)),params.zw)))"
	--str_cmplx="c_cos(c_inv(s-params.zw+p*vec2(move_dist,global_seed)))-params.xy"
	--str_cmplx=random_math_complex(rand_complexity,nil,{"c_pow(s,vec2(1,global_seed*2))"})
	--str_cmplx=random_math_complex_intervals(rand_complexity,10)
	--str_cmplx="c_mul(params.xy,c_inv(c_mul(c_conj(c_cos(s)),p*vec2(move_dist,global_seed)+params.zw)))"
	--str_cmplx=str_cmplx.."*value_inside(global_seed,0,0.5)+(s-(s*move_dist)/length(s))*value_inside(global_seed,0.5,1)+(s*floor(global_seed*5)/5)/length(s)"
	--str_cmplx="c_tan(c_cos(c_tan((((params.xy)-(s))-(c_cos(c_mul(c_atan(params.zw),c_tan((params.zw)+(params.xy))))))-(p*vec2(move_dist*(1-global_seed*global_seed),global_seed)))))"
	str_x=random_math_intervals(true,rand_complexity,6,nil,{"s.x","p.y","params.x","params.y"})
	str_y=random_math_intervals(false,rand_complexity,6,nil,{"s.y","p.x","params.z","params.w"})
	--str_cmplx="c_mul(s,s)+from_polar(to_polar(p)+vec2(0,global_seed*move_dist*M_PI*2))"
	--str_cmplx="c_cos(s)+p*global_seed+c_mul(s,s)*(1-global_seed)"
	--str_cmplx=random_math_complex(rand_complexity,"c_mul(R,last_s/length(last_s)+c_one())")
	--local FT=random_math_complex(rand_complexity)
	--[[
	--str_cmplx="c_mul(c_div((c_div(s,c_cos((params.xy)-(s))))-(s),(c_div((c_conj(s))+(c_div(p,c_cos(p))),((s)-(s))+(c_atan((params.xy)-(p)))))-(c_conj(p))),c_tan(((c_div((s)+(p),(s)+(params.xy)))-((p)+(c_conj(s))))-(p)))"
	--str_cmplx="c_conj(c_tan(((p)+(c_conj((s)-(c_conj((p)+(p))))))+((((c_inv(c_inv(s)))-(c_conj(s)))-(c_sin((c_mul(c_sin((params.zw)+(p)),p))+(s))))-(((s)+(s))+((p)+(((c_div(p,p))+(s))+(s)))))))"
	--]]
	--[[ nice tri-lobed shape
		str_cmplx="c_div(c_conj(p),(s)-(p))"
	--]]
	--[[
	local pts={}
	local num_roots=7
	for i=1,num_roots do
		local angle=((i-1)/num_roots)*math.pi*2
		table.insert(pts,{math.cos(angle)*config.move_dist,math.sin(angle)*config.move_dist})
	end
	str_cmplx=random_math_complex_pts(rand_complexity,pts)
	--]]
	--[=[
	other_code=string.format([[
	vec2 FT(float t,float c)
	{
		return %s;
	}]],random_math_complex_FT(rand_complexity))

	str_cmplx=random_math_complex_series_t(4).."+"..random_math_complex_series_t(4,"s",1)
	--]=]
	
	--[=[ http://www.fractalsciencekit.com/topics/mobius.htm maybe?
	--str_cmplx="c_div(c_mul(params.xy,s)+vec2(-0.1,0.2),c_mul(vec2(0.2,0.1),s)+params.zw)"
	str_cmplx=random_math_complex(rand_complexity,"c_div(c_mul(R,s)+R,c_mul(R,s)+R)")
	--]=]
	--mandelbrot?
	--[=[
	str_cmplx="c_mul(s,s)+p"
	--]=]

	--[[ julia
	str_cmplx="c_mul(s,s)+params.xy"
	--]]
	--[[ cubebrot julian
	str_cmplx="c_mul(s,c_mul(s,s))+c_mul(p,params.zw)+params.xy"
	--]]
	--[[
	str_x="s.x*s.x-s.y*s.y+params.x"
	str_y="s.x*s.y-s.y*s.y+params.y"
	--]]
	--[[
	--str_x="p.x*params.x+s.y*s.x*params.y"
	--str_y="s.y+p.x*s.y*params.w"
	--]]
	--local s="((p.y)+(p.x))+((tan(tan((normed_iter)/(params.w))))*(s.y))"
	--str_x="sin("..s.."-s.x*s.y)"
	--str_y="cos("..s.."-s.y*s.x)"
	--str_x=random_math_centered(3,rand_complexity)
	--str_y=random_math_centered(3,rand_complexity)
	--str_x=random_math(rand_complexity)
	--str_y=random_math(rand_complexity)

	--[[
	local str1="p.x"
	local str2="p.y"
	local max_i=3
	for i=0,max_i-1 do
		local s=random_math(rand_complexity)
		str1=str1..("+(%s)*(%.3f)"):format(s,math.cos((i/max_i)*math.pi*2))
		str2=str2..("+(%s)*(%.3f)"):format(s,math.sin((i/max_i)*math.pi*2))
	end
	str_x=str1--random_math(rand_complexity,str1)
	str_y=str2--random_math(rand_complexity,str2)
	--]]
	--str_x=random_math(rand_complexity,"(R)*length(s)")
	--str_y=random_math(rand_complexity,"(R)*length(s)")

	--str_x=s.."*(length(p)/(length(s)+1))"
	--str_y=s.."*(length(s)/(length(p)+1))"

	--str_x=random_math(rand_complexity,"log(abs(R))")
	--str_y=random_math(rand_complexity,"log(abs(R))")

	--str_x=random_math(rand_complexity,"exp(R)")
	--str_y=random_math(rand_complexity,"exp(R)")

	--str_x=random_math(rand_complexity,"exp(1/(-s.x*s.x))*R")
	--str_y=random_math(rand_complexity,"exp(1/(-s.y*s.y))*R")

	--str_x="exp(1/(-s.x*s.x))*"..s
	--str_y="exp(1/(-s.y*s.y))*"..s
	--str_x=random_math_fourier(3,rand_complexity)
	--str_y=random_math_fourier(3,rand_complexity)

	--str_x=random_math_power(8,rand_complexity)
	--str_y=random_math_power(8,rand_complexity)

	--str_x=random_math(rand_complexity,"(R)*s.x*s.x-(R)*s.y*s.y")
	--str_y=random_math(rand_complexity,"(R)*s.x*s.x-(R)*s.y*s.y")


	--str_x=random_math(rand_complexity,"R+(R)*s.x+R*s.y+(R)*s.x*s.y*params.x")
	--str_y=random_math(rand_complexity,"R+(R)*s.x+R*s.y+(R)*s.x*s.y*params.y")
	--str_x="s.x"
	--str_y="s.y"

	--str_y="-"..str_x
	--str_x=random_math(rand_complexity,"cos(R)*(R)")
	--str_y=random_math(rand_complexity,"sin(R)*(R)")
	--str_y="sin("..str_x..")"
	--str_x="cos("..str_x..")"
	--str_x=random_math_power(2,rand_complexity).."/"..random_math_power(2,rand_complexity)
	--str_y=random_math_fourier(2,rand_complexity).."/"..str_x
	str_preamble=""
	str_postamble=""
	--str_preamble="vec2 FT="..FT..";"
	--[[ gravity
	str_preamble=str_preamble.."s*=1/move_dist;"
	--]]
	--[[ weight1
	--str_postamble=str_postamble.."float ll=length(s);s/=weight1;weight1*=1/ll;"
	--str_postamble=str_postamble.."float ll=length(s);s*=weight1;weight1=min(weight1,1/ll);"
	str_postamble=str_postamble.."float ll=length(s);s/=weight1;weight1=max(weight1,ll);"
	--str_postamble=str_postamble.."float ll=length(s);s/=weight1;weight1+=ll;"
	--]]
	--[[ rand scale/offset

	local r1=math.random()*2-1
	local r2=math.random()*2-1
	local l=math.sqrt(r1*r1+r2*r2)
	local r3=math.random()*2-1
	local r4=math.random()*2-1
	local l2=math.sqrt(r3*r3+r4*r4)
	local r5=math.random()*2-1
	local r6=math.random()*2-1
	local l3=math.sqrt(r5*r5+r6*r6)
	str_preamble=str_preamble..("s=vec2(dot(s,vec2(%.3f,%.3f)),dot(s,vec2(%.3f,%.3f)))+vec2(%3.f,%.3f);"):format(r1/l,r2/l,r3/l2,r4/l2,r5/l3,r6/l3)

	--]]

	--[[ complex seriesize
	local series_size=5
	local rand_offset=0.01
	local rand_size=0.025
	local input_s=""
	for i=1,series_size do
		local sub_s="s"
		for i=1,i do
			sub_s=string.format("c_mul(%s,%s)","s",sub_s)
		end
		sub_s=string.format("%s*%g",sub_s,1/factorial(i))
		--input_s=input_s..string.format("+%s*vec2(%.3f,%.3f)",sub_s,rand_offset+math.random()*rand_size-rand_size/2,rand_offset+math.random()*rand_size-rand_size/2)
		local v_start=(i-1)/series_size
		local v_end=i/series_size
		input_s=input_s..string.format("+%s*vec2(%.3f,%.3f)*value_inside(global_seed,%g,%g)",sub_s,rand_offset+math.random()*rand_size-rand_size/2,rand_offset+math.random()*rand_size-rand_size/2,v_start,v_end)

		local dx=math.cos((i/series_size)*math.pi*2)
		local dy=math.sin((i/series_size)*math.pi*2)
		--input_s=input_s..string.format("+%s*vec2(cos(global_seed*M_PI*2),sin(global_seed*M_PI*2))",sub_s)
	end
	str_postamble=str_postamble.."s=s"..input_s..";"
	--]]
	--[[ polar gravity
	--str_postamble=str_postamble.."float ls=length(s);s*=1-atan(ls*move_dist)/(M_PI/2);"
	--str_postamble=str_postamble.."float ls=length(s);s*=1-atan(ls*move_dist)/(M_PI/2)*move_dist;"
	--str_postamble=str_postamble.."float ls=length(s-vec2(1,1));s=s*(1-atan(ls*move_dist)/(M_PI/2)*move_dist)+vec2(1,1);"
	--str_postamble=str_postamble.."float ls=length(s);s*=(1+sin(ls*move_dist))/2*move_dist;"
	str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);s=last_s+ds*(move_dist/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=1-atan(ls*move_dist)/(M_PI/2);s=last_s+ds*(move_dist*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=1-atan(ls*(global_seed*8))/(M_PI/2);s=last_s+ds*((global_seed*7)*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-1/dot(s,s));s=last_s+ds*(move_dist*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-1/dot(p,p));s=last_s+ds*(move_dist*vv/ls);"
	--]]
	--[[ move towards circle
	str_postamble=str_postamble.."vec2 tow_c=s+vec2(cos(normed_iter*M_PI*2),sin(normed_iter*M_PI*2))*move_dist;s=(dot(tow_c,s)*tow_c/length(tow_c));"
	--]]
	--[[ boost
	str_preamble=str_preamble.."s*=move_dist;"
	--]]
	--[[ boost less with distance
	--str_preamble=str_preamble.."s*=move_dist*exp(-1/dot(s,s));"
	str_preamble=str_preamble.."s*=global_seed*exp(-1/dot(s,s));"
	--]]
	--[[SINK!
	str_postamble=str_postamble.."p=p*(2-normed_iter);"
	--]]
	--[[ 4fold mirror
	str_postamble=str_postamble.."s=abs(s);"
	--]]
	--[[ center PRE
	str_preamble=str_preamble.."s=s-p;"
	--]]
	--[[ cosify
	--str_preamble=str_preamble.."s=cos(s);"
	str_preamble=str_preamble.."s=c_cos(s);"
	--]]
	--[[ tanify
	--str_preamble=str_preamble.."s=tan(s);"
	str_preamble=str_preamble.."s=c_tan(s);"
	--]]
	--[[ logitify PRE
	str_preamble=str_preamble.."s=log(abs(s));"
	--]]
	-- [[ gaussination
	--str_postamble=str_postamble.."s=vec2(exp(1/(-s.x*s.x)),exp(1/(-s.y*s.y)));"
	--str_postamble=str_postamble.."s=s*vec2(exp(move_dist/(-p.x*p.x)),exp(move_dist/(-p.y*p.y)));"
	--str_postamble=str_postamble.."s=vec2(exp(global_seed/(-s.x*s.x)),exp(global_seed/(-s.y*s.y)));"
	--]]
	--[[ invert-ination
	str_preamble=str_preamble.."s=c_inv(s);"
	str_postamble=str_postamble.."s=c_inv(s);"
	--]]
	--[[ Chebyshev polynomial
	str_preamble=str_preamble.."s=floor(global_seed*move_dist+1)*c_acos(s);"
	str_postamble=str_postamble.."s=c_cos(s);"
	--]]
	--[[ Chebyshev polynomial2
	str_preamble=str_preamble.."s=move_dist*c_cos(s);"
	str_postamble=str_postamble.."s=c_acos(s);"
	--]]
	--[[ Chebyshev polynomial3
	str_preamble=str_preamble.."s=move_dist*c_sin(s);"
	str_postamble=str_postamble.."s=c_asin(s);"
	--]]
	--[[ offset
	str_preamble=str_preamble.."s+=params.xy;"
	--]]
	--[[ rotate
	--str_preamble=str_preamble.."s=vec2(cos(params.z)*s.x-sin(params.z)*s.y,cos(params.z)*s.y+sin(params.z)*s.x);"
	str_preamble=str_preamble.."p=vec2(cos(params.z*M_PI*2)*p.x-sin(params.z*M_PI*2)*p.y,cos(params.z*M_PI*2)*p.y+sin(params.z*M_PI*2)*p.x);"

	--]]
	--[[ offset_complex
	--str_preamble=str_preamble.."s+=params.xy*floor(seed*move_dist+1)/move_dist;s=c_mul(s,params.zw);"
	str_preamble=str_preamble.."s+=vec2(0.125,-0.25);s=c_mul(s,vec2(global_seed,floor(global_seed*move_dist+1)/move_dist));"
	--]]
	--[[ unoffset_complex
	--str_postamble=str_postamble.."s=c_div(s,params.zw);s-=params.xy*floor(seed*move_dist+1)/move_dist;"
	str_postamble=str_postamble.."s=c_mul(s,c_inv(params.zw));s-=params.xy*floor(global_seed*move_dist+1)/move_dist;"
	--]]
	--[[ rotate (p)
	--str_preamble=str_preamble.."s=vec2(cos(p.x)*s.x-sin(p.x)*s.y,cos(p.x)*s.y+sin(p.x)*s.x);"
	--str_preamble=str_preamble.."s=vec2(cos(p.y)*s.x-sin(p.y)*s.y,cos(p.y)*s.y+sin(p.y)*s.x);"
	str_preamble=str_preamble.."s=vec2(cos(normed_iter*M_PI*2)*s.x-sin(normed_iter*M_PI*2)*s.y,cos(normed_iter*M_PI*2)*s.y+sin(normed_iter*M_PI*2)*s.x);"
	--]]
	--[[ const-delta-like
	str_preamble=str_preamble.."vec2 os=s;"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist*exp(1/-dot(p,p));"
	str_postamble=str_postamble.."s/=length(s);s=os+s*exp(-dot(p,p)/move_dist);"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist;"
	--str_postamble=str_postamble.."s/=length(s);s=os+c_mul(s,vec2(params.zw));"
	--str_postamble=str_postamble.."s/=length(s);s=os+c_mul(s,vec2(params.zw)*floor(global_seed*move_dist+1)/move_dist);"
	--]]
	--[[ const-delta-like complex
	str_preamble=str_preamble.."vec2 os=s;"
	str_postamble=str_postamble.."s=c_div(s,os);"
	--]]
	--[[ normed-like
	str_preamble=str_preamble.."float l=length(s);"
	str_postamble=str_postamble.."s/=l;s*=move_dist;"
	--]]
	--[[ normed-like2
	str_preamble=str_preamble..""
	str_postamble=str_postamble.."s/=length(s);s*=move_dist;s+=p;"
	--]]
	--[[ polar-like
	str_preamble=str_preamble.."s=to_polar(s);p=to_polar(p);"
	str_postamble=str_postamble.."s=from_polar(s);p=from_polar(p);"
	--]]
	--[[ centered-polar
	str_preamble=str_preamble.."s=to_polar(s-p);"
	str_postamble=str_postamble.."s=from_polar(s)+p;"
	--]]
	--[[ logitify POST
	str_postamble=str_postamble.."s=log(abs(s));"
	--]]
	--[[ exp post
	str_postamble=str_postamble.."s=exp(s);"
	--]]
	--[[ unrotate POST
	--str_postamble=str_postamble.."s=vec2(cos(-params.z)*s.x-sin(-params.z)*s.y,cos(-params.z)*s.y+sin(-params.z)*s.x);"
	--str_postamble=str_postamble.."s=vec2(cos(-0.7853981)*s.x-sin(-0.7853981)*s.y,cos(-0.7853981)*s.y+sin(-0.7853981)*s.x);"
	--str_postamble=str_postamble.."p=vec2(cos(-params.z*M_PI*2)*p.x-sin(-params.z*M_PI*2)*p.y,cos(-params.z*M_PI*2)*p.y+sin(-params.z*M_PI*2)*p.x);"
	str_postamble=str_postamble.."s=vec2(cos(-normed_iter*M_PI*2)*s.x-sin(-normed_iter*M_PI*2)*s.y,cos(-normed_iter*M_PI*2)*s.y+sin(-normed_iter*M_PI*2)*s.x);"
	--]]
	--[[ unoffset POST
	str_postamble=str_postamble.."s-=params.xy;"
	--]]
	--[[ untan POST
	str_postamble=str_postamble.."s=atan(s);"
	--]]
	--[[ uncosify POST
	str_postamble=str_postamble.."s=acos(s);"
	--]]
	--[[ uncenter POST
	str_postamble=str_postamble.."s=s+p;"
	--]]
	--[[ crazyness
	str_postamble=str_postamble.."p=tp;"
	--]]
	print("==============")
	print(other_code)
	print(str_preamble)
	if complex then
		print(str_cmplx)
	else
		print(str_x)
		print(str_y)
	end
	print(str_postamble)

	make_visit_shader(true)
	need_clear=true
end

local cur_visit_iter=0
function gui()
	imgui.Begin("IFS play")
	palette_chooser()
	draw_config(config)
	if config.size_mult then
		size_mult=1
	else
		size_mult=0.5
	end
	update_size()
	local s=STATE.size
	if imgui.Button("Clear image") then
		need_clear=true
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.SameLine()
	if imgui.Button("Save buffer") then
		need_buffer_save="out.buf"
	end
	imgui.SameLine()
	if imgui.Button("regen shuffling") then
		global_seed_shuffling={}
	end

	rand_complexity=rand_complexity or 3
	if imgui.Button("Rand function") then
		rand_function()
	end
	imgui.SameLine()

	_,rand_complexity=imgui.SliderInt("Complexity",rand_complexity,1,15)

	if imgui.Button("Animate") then
		animate=true
		need_clear=true
		config.animation=0
	end
	imgui.SameLine()
	if imgui.Button("Update frame") then
		update_animation_values()
	end
	imgui.Text(string.format("Done: %d %s",(cur_visit_iter/config.IFS_steps)*100,reset_stats or ""))
	imgui.End()
end

function update( )
	gui()
	update_real()
end

function auto_clear(  )
	local pos_start=0
	local pos_end=0
	local pos_anim=0;
	for i,v in ipairs(config) do
		if v[1]=="v0" then
			pos_start=i
		end
		if v[1]=="cy" then
			pos_end=i
		end
		if v[1]=="animation" then
			pos_anim=i
		end
	end

	for i=pos_start,pos_end do
		if config[i].changing then
			need_clear=true
			break
		end
	end
end


function make_coord_change(  )
	if complex then
		return string.format("s=%s;",str_cmplx)
	else
		return string.format("s=vec2(%s,%s);",str_x,str_y)
	end
end
function make_init_cond(  )
	if init_zero then
		return "vec2(0,0)"
	else
		return "p"
	end
end
function escape_mode_str(  )
	if escape_fractal then
		return "1"
	else
		return "0"
	end
end


function make_visit_shader( force )

if transform_shader==nil or force then
	transform_shader=shaders.Make(
string.format([==[
#version 330
#line 1226
//escape_mode_str
#define ESCAPE_MODE %s
layout(location = 0) in vec4 position;
//out vec3 pos;
out vec4 point_out;

#define M_PI 3.1415926535897932384626433832795

uniform vec2 center;
uniform vec2 scale;
uniform int pix_size;
uniform float global_seed;
uniform float move_dist;
uniform vec4 params;
uniform float normed_iter;
uniform float gen_radius;

float value_inside(float x,float a,float b){return step(a,x)-step(b,x);}

float rand1(float n){return fract(sin(n) * 43758.5453123);}
float rand2(float n){return fract(sin(n) * 78745.6326871);}
float cosh(float val) {
  float tmp = exp(val);
  return (tmp + 1.0 / tmp) / 2.0;
}

float tanh(float val) {
  float tmp = exp(val);
  return (tmp - 1.0 / tmp) / (tmp + 1.0 / tmp);
}

float sinh(float val) {
  float tmp = exp(val);
  return (tmp - 1.0 / tmp) / 2.0;
}

vec2 cosh(vec2 val) {
  vec2 tmp = exp(val);
  return(tmp + 1.0 / tmp) / 2.0;
}

vec2 tanh(vec2 val) {
  vec2 tmp = exp(val);
  return (tmp - 1.0 / tmp) / (tmp + 1.0 / tmp);
}

vec2 sinh(vec2 val) {
  vec2 tmp = exp(val);
  return (tmp - 1.0 / tmp) / 2.0;
}

vec2 c_one() { return vec2(1., 0.); }
vec2 c_i() { return vec2(0., 1.); }

vec2 c_conj(vec2 c) {
  return vec2(c.x, -c.y);
}

float arg(vec2 c) {
  return atan(c.y, c.x);
}


vec2 c_from_polar(float r, float theta) {
  return vec2(r * cos(theta), r * sin(theta));
}

vec2 c_to_polar(vec2 c) {
  return vec2(length(c), atan(c.y, c.x));
}

/// Computes `e^(c)`, where `e` is the base of the natural logarithm.
vec2 c_exp(vec2 c) {
  return c_from_polar(exp(c.x), c.y);
}


/// Raises a floating point number to the complex power `c`.
vec2 c_exp(float base, vec2 c) {
  return c_from_polar(pow(base, c.x), c.y * log(base));
}

/// Computes the principal value of natural logarithm of `c`.
vec2 c_ln(vec2 c) {
  vec2 polar = c_to_polar(c);
  return vec2(log(polar.x), polar.y);
}

/// Returns the logarithm of `c` with respect to an arbitrary base.
vec2 c_log(vec2 c, float base) {
  vec2 polar = c_to_polar(c);
  return vec2(log(polar.r), polar.y) / log(base);
}

vec2 c_sqrt(vec2 c) {
  vec2 p = c_to_polar(c);
  return c_from_polar(sqrt(p.x), p.y/2.);
}

/// Raises `c` to a floating point power `e`.
vec2 c_pow(vec2 c, float e) {
  vec2 p = c_to_polar(c);
  return c_from_polar(pow(p.x, e), p.y*e);
}

/// Raises `c` to a complex power `e`.
vec2 c_pow(vec2 c, vec2 e) {
  vec2 polar = c_to_polar(c);
  return c_from_polar(
     pow(polar.x, e.x) * exp(-e.y * polar.y),
     e.x * polar.y + e.y * log(polar.x)
  );
}

vec2 c_mul(vec2 self, vec2 other) {
    return vec2(self.x * other.x - self.y * other.y, 
                self.x * other.y + self.y * other.x);
}

vec2 c_div(vec2 self, vec2 other) {
    float norm = length(other);
    return vec2(self.x * other.x + self.y * other.y,
                self.y * other.x - self.x * other.y)/(norm * norm);
}

vec2 c_sin(vec2 c) {
  return vec2(sin(c.x) * cosh(c.y), cos(c.x) * sinh(c.y));
}

vec2 c_cos(vec2 c) {
  // formula: cos(a + bi) = cos(a)cosh(b) - i*sin(a)sinh(b)
  return vec2(cos(c.x) * cosh(c.y), -sin(c.x) * sinh(c.y));
}

vec2 c_tan(vec2 c) {
  vec2 c2 = 2. * c;
  return vec2(sin(c2.x), sinh(c2.y))/(cos(c2.x) + cosh(c2.y));
}

vec2 c_atan(vec2 c) {
  // formula: arctan(z) = (ln(1+iz) - ln(1-iz))/(2i)
  vec2 i = c_i();
  vec2 one = c_one();
  vec2 two = one + one;
  if (c == i) {
    return vec2(0., 1./0.0);
  } else if (c == -i) {
    return vec2(0., -1./0.0);
  }

  return c_div(
    c_ln(one + c_mul(i, c)) - c_ln(one - c_mul(i, c)),
    c_mul(two, i)
  );
}

vec2 c_asin(vec2 c) {
 // formula: arcsin(z) = -i ln(sqrt(1-z^2) + iz)
  vec2 i = c_i(); vec2 one = c_one();
  return c_mul(-i, c_ln(
    c_sqrt(c_one() - c_mul(c, c)) + c_mul(i, c)
  ));
}

vec2 c_acos(vec2 c) {
  // formula: arccos(z) = -i ln(i sqrt(1-z^2) + z)
  vec2 i = c_i();

  return c_mul(-i, c_ln(
    c_mul(i, c_sqrt(c_one() - c_mul(c, c))) + c
  ));
}

vec2 c_sinh(vec2 c) {
  return vec2(sinh(c.x) * cos(c.y), cosh(c.x) * sin(c.y));
}

vec2 c_cosh(vec2 c) {
  return vec2(cosh(c.x) * cos(c.y), sinh(c.x) * sin(c.y));
}

vec2 c_tanh(vec2 c) {
  vec2 c2 = 2. * c;
  return vec2(sinh(c2.x), sin(c2.y))/(cosh(c2.x) + cos(c2.y));
}

vec2 c_asinh(vec2 c) {
  // formula: arcsinh(z) = ln(z + sqrt(1+z^2))
  vec2 one = c_one();
  return c_ln(c + c_sqrt(one + c_mul(c, c)));
}

vec2 c_acosh(vec2 c) {
  // formula: arccosh(z) = 2 ln(sqrt((z+1)/2) + sqrt((z-1)/2))
  vec2 one = c_one();
  vec2 two = one + one;
  return c_mul(two,
      c_ln(
        c_sqrt(c_div((c + one), two)) + c_sqrt(c_div((c - one), two))
      ));
}

vec2 c_atanh(vec2 c) {
  // formula: arctanh(z) = (ln(1+z) - ln(1-z))/2
  vec2 one = c_one();
  vec2 two = one + one;
  if (c == one) {
      return vec2(1./0., vec2(0.));
  } else if (c == -one) {
      return vec2(-1./0., vec2(0.));
  }
  return c_div(c_ln(one + c) - c_ln(one - c), two);
}

// Attempts to identify the gaussian integer whose product with `modulus`
// is closest to `c`
vec2 c_rem(vec2 c, vec2 modulus) {
  vec2 c0 = c_div(c, modulus);
  // This is the gaussian integer corresponding to the true ratio
  // rounded towards zero.
  vec2 c1 = vec2(c0.x - mod(c0.x, 1.), c0.y - mod(c0.y, 1.));
  return c - c_mul(modulus, c1);
}

vec2 c_inv(vec2 c) {
  float norm = length(c);
	return vec2(c.x, -c.y) / (norm * norm);
}

vec2 cell_pos(int id,int max_id,float dist)
{
	float v=float(id)/float(max_id);
	return vec2(rand1(v)-0.5,rand2(v)-0.5)*dist*2;
}
vec2 to_polar(vec2 p)
{
	return vec2(length(p),atan(p.y,p.x));
}
vec2 from_polar(vec2 p)
{
	return vec2(cos(p.y)*p.x,sin(p.y)*p.x);
}

//str_other_code
%s

vec3 func_actual(vec2 s,vec2 p)
{
	//init condition
	vec2 last_s=s;
	float e=1;
	%s
#if ESCAPE_MODE
			if(e>normed_iter && dot(s,s)>4)
				{
				e=normed_iter;
				break;
				}
#endif
	last_s=s;
	return vec3(s.x,s.y,e);
}
vec2 tRotate(vec2 p, float a) {
	float c=cos(a);
	float s=sin(a);
	mat2 m=mat2(c,-s,s,c);
	return m*p;
}
vec2 tReflect(vec2 p,float a){
	float c=cos(2*a);
	float s=sin(2*a);
	mat2 m=mat2(c,s,s,-c);
	return m*p;
}

vec3 func(vec2 s,vec2 p)
{
	const float ang=(M_PI/20)*2;
#if 1
	return func_actual(s,p);
#endif
#if 0
	vec2 v=to_polar(p);
	vec3 r=func_actual(s,v);
	return vec3(from_polar(r.xy),r.z);
#endif
#if 0
	vec2 v=to_polar(p);
	vec3 r=func_actual(s,v);
	v+=r.xy;
	return vec3(from_polar(v),r.z);
#endif
#if 0
	vec2 r=func_actual(s,p);
	//float d=atan(r.y,r.x);
	return (p/*+vec2(cos(d),sin(d))*/)/length(r);
#endif
#if 0
	vec2 r=func_actual(s,p);
	return (p/length(p))*length(r);
	//return p/length(p-r);
#endif
#if 0
	vec3 r=func_actual(s,p);
	//vec2 delta=p-r;
	//return p*exp(1/-dot(delta,delta));
	return vec3(p*exp(1/-dot(r.xy,r.xy)),r.z);
	//return r*exp(1/-dot(p,p));
	//return vec2(exp(1/-(r.x*r.x)),exp(1/-(r.y*r.y)))*p;
	//return vec2(exp(1/-(p.x*p.x)),exp(1/-(p.y*p.y)))+r;
	//return (vec2(exp(1/-(p.x*p.x)),exp(1/-(p.y*p.y)))+r)/2;
#endif
#if 0
	//vec2 vp=p*exp(1/-dot(p,p));
	vec2 vp=p;
	float l=length(p);
	if(l>1)
		vp/=l;
	vec2 r=func_actual(s,vp);
	return p*exp(1/-dot(r,r));
	//return vp;
#endif
#if 0
	
	vec2 r=func_actual(s,p);
	float lr=length(r);

	r*=exp(1/-(dot(r,r)+1));
	return r;
#endif
#if 0
	const float symetry_defect=0.02;
	vec2 v=to_polar(p);
	
	float av=floor((v.y+M_PI)/ang);
	float pv=mod(v.y,ang);
	const float dist_div=0.5;
	vec2 c=vec2(cos(av*ang),sin(av*ang))*dist_div;
	
	p-=c;
	p-=c*symetry_defect*av; //sort of shell-like looking

	p=tRotate(p,ang*av+symetry_defect*av);
	//p=tReflect(p,ang*av/2+symetry_defect*av);
	vec3 r=func_actual(s,p);//+vec2(0,-dist_div);
	//r=tReflect(r,ang*av/2);
	r.xy=tRotate(r.xy,-ang*av);

	//r+=c*0.25*av;
	r.xy+=c;
	//r=to_polar(r);
	//r.x+=dist_div;
	//r.y+=av*ang;
	//r=from_polar(r);
	return r;
#endif
#if 0
	const float symetry_defect=0;
	const float rotate_amount=0;//M_PI/3;
	const float cell_size=5;
	vec2 av_v=vec2(floor(p.x*cell_size+0.5),floor(p.y*cell_size+0.5));

	float av=abs(av_v.x)+abs(av_v.y);//length(av_v);
	const float dist_div=1;
	vec2 c=av_v*dist_div*(1/cell_size);
	
	//p-=c;
	p-=c*symetry_defect*av;
	//p=tRotate(p,rotate_amount*av);
	p=tReflect(p,rotate_amount*av/2+symetry_defect*av);
	vec2 r=func_actual(s,p);//+vec2(0,-dist_div);
	r=tReflect(r,rotate_amount*av/2);
	//r=tRotate(r,-rotate_amount*av);
	r+=c;
	return r;
#endif
}
float hash(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x)))); }
vec2 gaussian(float mean,float var,vec2 rnd)
{
    return vec2(sqrt(-2 * var * log(rnd.x)) *
            cos(2 * 3.14159265359 * rnd.y) + mean,
            sqrt(-2 * var * log(rnd.x)) *
            sin(2 * 3.14159265359 * rnd.y) + mean);
}

vec2 float_from_floathash(vec2 val)
{
	return floatBitsToUint(val)/vec2(4294967295.0);
}
vec2 gaussian2 (vec2 seed,vec2 mean,vec2 var)
{
    return  vec2(
    sqrt(-2 * var.x * log(seed.x)) * cos(2 * M_PI * seed.y),
    sqrt(-2 * var.y * log(seed.x)) * sin(2 * M_PI * seed.y))+mean;
}
uniform int non_hashed_random;
void main()
{
	float d=0;
	vec2 start_pos;
	if (non_hashed_random==1)
		start_pos=position.zw;
	else
	{
		vec2 seed=float_from_floathash(position.zw);
		start_pos=gaussian2(seed,vec2(0),vec2(gen_radius));
	}
#if ESCAPE_MODE
	vec2 inp_p=mapping((position.xy-center)/scale);
    vec3 rez= func(inp_p);//*scale+center;
    //pos.xy=position.xy;//*scale+center;
    //gl_Position.xy=position.xy;//*scale+center;
    //pos.z=rez.z;//length(rez);
    point_out.xy=position.xy;
#else
	//in add shader: pos.xy*scale+center
	vec2 p=func(position.xy,start_pos).xy;
	//p=(mapping(p*scale+center)-center)/scale;
	point_out.xy=p;
	point_out.zw=position.zw;
#endif

}
]==],
--Args to format
	escape_mode_str(),
	other_code or "",
	str_preamble.."\n"..make_coord_change().."\n"..str_postamble
),
[==[ void main(){} ]==],"point_out"
)
end

end
make_visit_shader(true)

add_visits_shader=shaders.Make(
[==[
#version 330
#line 2032
layout(location = 0) in vec4 pos;

#define M_PI 3.1415926535897932384626433832795

out vec4 pos_f;
uniform vec2 center;
uniform vec2 scale;
uniform int pix_size;
vec2 pMod2(inout vec2 p,float size)
{
	vec2 halfsize=vec2(size*0.5);
	vec2 c= floor((p+halfsize)/size);
	p=mod(p+halfsize,size)-halfsize;
	return c;
}
vec2 tRotate(vec2 p, float a) {
	float c=cos(a);
	float s=sin(a);
	mat2 m=mat2(c,-s,s,c);
	return m*p;
}
vec2 tReflect(vec2 p,float a){
	float c=cos(2*a);
	float s=sin(2*a);
	mat2 m=mat2(c,s,s,-c);
	return m*p;
}
vec2 mapping(vec2 p)
{
	return p; //normal - do nothing
	//return abs(p)-vec2(1);
	//return mod(p+vec2(1),2)-vec2(1); //modulo, has ugly artifacts when point is HUGE
	/*
	if(length(p)<50) //modulo, but no artifacts because far away points are far away
	{
		float size=2.005; //0.005 overdraw as it smooths the tiling when using non 1 sized points
		return mod(p+vec2(size/2),size)-vec2(size/2);
	}
	else
		return p;
	//*/
#if 1
	//TODO: https://en.wikipedia.org/wiki/Wallpaper_group most of these would be fun...
	if(length(p)<50) //modulo, but no artifacts because far away points are far away
	{
		//float size=2.005; //0.005 overdraw as it smooths the tiling when using non 1 sized points
		float size=2;
		vec2 r=pMod2(p,size);

		/*
		float index=abs(r.x)+abs(r.y);
		if(mod(index,2)!=0) //make more interesting tiling: each second tile is flipped
			p*=-1;
		//*/


		///* code for group p4
		float index=mod(r.x,2)+mod(r.y,2)*2;
		float rot=0;
		if(index==1)
			rot=1;
		else if(index==2)
			rot=3;
		else if(index==3)
			rot=2;
		else if(index==-1)
			rot=-1;
		else if(index==-2)
			rot=-3;
		else if(index==-3)
			rot=-2;

		p=tRotate(p,rot*M_PI/2.0);
		//*/

		/*
		if(mod(r.x,2)!=0)
		{
			p.x*=-1;
			p.y+=1;
			pMod2(p,size);
		}
		//*/

		/*
		if(mod(r.y,2)!=0)
		{
			p.y*=-1;
			pMod2(p,size);
		}
		//*/

		return p;

		//return mod(p+vec2(size/2),size)-vec2(size/2);
	}
	else
		return p;
#endif
	//return mod(p+vec2(1),2)-vec2(1)+vec2(0.001)*log(dot(p,p)+1);
	//return c_rem(p+vec2(1),vec2(2,0))-vec2(1);
	/* polar
	float angle=(2*M_PI)/3;
	float r=length(p);
	float a=atan(p.y,p.x);
	r=mod(r,2);
	a=mod(a,angle);
	a/=angle;
	return vec2(r-1,a*2-1);
	//*/
	//spherical... needs compression in poles
	///*
	float w=2;
	float h=2;

	p+=vec2(w/2,h/2);
	float d=floor(p.y/h);
	if(mod(d,2)<1)
	{
		p.y=mod(p.y,h);
	}
	else
	{
		p.y=h-mod(p.y,h);
		p.x+=w/2;
	}
	p.x=mod(p.x,w);
	return p-vec2(w/2,h/2);
	//*/
}
void main()
{
	vec2 p=mapping(pos.xy*scale+center);
    gl_Position.xyz = vec3(p,0);
    gl_Position.w = 1.0;
    gl_PointSize=pix_size;
    pos_f=pos;
}
]==],
string.format(
[==[
#version 330
#line 1763
#define M_PI   3.14159265358979323846264338327950288
#define ESCAPE_MODE %s

out vec4 color;
in vec4 pos_f;

uniform sampler2D img_tex;
uniform int pix_size;
uniform float normed_iter;
uniform float global_seed;

uniform vec4 palette[50];
uniform int palette_size;


vec4 mix_palette(float value )
{
	if (palette_size==0)
		return vec4(0);
	value=clamp(value,0,1);
	float tg=value*(float(palette_size)-1); //[0,1]-->[0,#colors]
	float tl=floor(tg);

	float t=tg-tl;
	vec4 c1=palette[int(tl)];
	int hidx=min(int(ceil(tg)),palette_size-1);
	vec4 c2=palette[hidx];
	return mix(c1,c2,t);
}

float shape_point(vec2 pos)
{
	float rr=dot(pos.xy,pos.xy);
	rr=clamp(rr,0,1);
	float delta_size=(1-0.2)*rr+0.2;
	return delta_size;
}
vec3 rgb2xyz( vec3 c ) {
    vec3 tmp;
    tmp.x = ( c.r > 0.04045 ) ? pow( ( c.r + 0.055 ) / 1.055, 2.4 ) : c.r / 12.92;
    tmp.y = ( c.g > 0.04045 ) ? pow( ( c.g + 0.055 ) / 1.055, 2.4 ) : c.g / 12.92,
    tmp.z = ( c.b > 0.04045 ) ? pow( ( c.b + 0.055 ) / 1.055, 2.4 ) : c.b / 12.92;
    return 100.0 * tmp *
        mat3( 0.4124, 0.3576, 0.1805,
              0.2126, 0.7152, 0.0722,
              0.0193, 0.1192, 0.9505 );
}
vec2 float_from_floathash(vec2 val)
{
	return floatBitsToUint(val)/vec2(4294967295.0);
}
vec2 gaussian2 (vec2 seed,vec2 mean,vec2 var)
{
    return  vec2(
    sqrt(-2 * var.x * log(seed.x)) * cos(2 * M_PI * seed.y),
    sqrt(-2 * var.y * log(seed.x)) * sin(2 * M_PI * seed.y))+mean;
}

uint triple32(uint x)
{
    x ^= x >> 17;
    x *= 0xed5ad4bbU;
    x ^= x >> 11;
    x *= 0xac4c1b51U;
    x ^= x >> 15;
    x *= 0x31848babU;
    x ^= x >> 14;
    return x;
}
vec2 hash22(vec2 seed)
{	
	uint x=triple32(floatBitsToUint(seed.x));
	uint y=triple32(floatBitsToUint(seed.y));
	return uvec2(x,y)/vec2(4294967295.0);
}
float color_value_vornoi(vec2 pos)
{
	int num_domains=30;
	float cur_dom=0;
	float min_dist=999999;
	vec2 seed=vec2(1.8779,0.99932);
	uvec2 useed=uvec2(floatBitsToUint(seed.x),floatBitsToUint(seed.y));
	for(int i=0;i<num_domains;i++)
	{
		useed.x=triple32(useed.x);
		useed.y=triple32(useed.y);

		vec2 loc=useed/vec2(4294967295.0);
		loc-=pos;
		/*vec2 loc;
		if(i==0)
			loc=vec2(0,0)-pos;
		else
			loc=vec2(1,1)-pos;
		*/
		float d=dot(loc,loc);
		if(d<min_dist)
		{
			min_dist=d;
			cur_dom=i/float(num_domains);
		}
	}
	return cur_dom;
}
float value_inside(float x,float a,float b){return step(a,x)-step(b,x);}
void main(){
	vec2 pos=pos_f.xy;
#if ESCAPE_MODE
	//if(pos.z>float(it_count)/10)
	//	discard;
	float v=pos.z;
	//float v=log(pos.z*exp(1)+1);
	//float v=exp(pos.z-0.5);
	//v=smoothstep(v,0,0.5);
	v=clamp(v,0,1);
	//float v=1;
#else
	float v=1;
#endif
	//vec4 txt=texture(img_tex,mod(pos.xy*vec2(0.5,-0.5)+vec2(0.5,0.5),1));
#if 0
	float delta_size=shape_point(pos.xy);
#else
	float delta_size=1;
#endif
	//float delta_size=txt.r;
 	float r = 2*length(gl_PointCoord - 0.5)/(delta_size);
	float a = 1 - smoothstep(0, 1, r);
	//float a=1; //uncomment this for line mode
	float intensity=1/float(pix_size);

	vec2 seed=float_from_floathash(pos_f.zw);
	vec2 start_pos=gaussian2(seed,vec2(0),vec2(2));
	vec2 delta_pos=start_pos-pos;

	float start_l=length(start_pos);
	start_l=clamp(start_l,0,1);
	start_l=1-exp(-start_l*start_l);
	float dist_traveled=length(delta_pos);
	float color_value=global_seed;
	//float color_value=color_value_vornoi(delta_pos);
	//float color_value=cos(seed.x)*0.5+0.5;
	//float color_value=cos(seed.y*4*M_PI)*0.5+0.5;
	//float color_value=start_l;
	//float color_value=length(pos);
	//float color_value=dot(delta_pos,delta_pos)/10;
	//float color_value=exp(-start_l*start_l);
	//float color_value=normed_iter;
	//float color_value=cos(normed_iter*M_PI*2*20)*0.5+0.5;
	//float color_value=smoothstep(0,1,start_l);
	//float color_value=sin(start_l*M_PI*2/4)*0.5+0.5;
	//float color_value=normed_iter*exp(-start_l*start_l);
	//float color_value=1-exp(-dot(delta_pos,delta_pos)/2.5);
	//float color_value=mix(start_l,dist_traveled,normed_iter);
	vec3 c=rgb2xyz(mix_palette(color_value).xyz);
	c*=a*intensity;
	//c*=(sin(start_l*M_PI*16)+0.6);
	//c*=(sin(normed_iter*M_PI*8)+0.1);
	//c*=(sin(start_l*M_PI*8)+0.0);
	//c*=(start_l-0.5)*2;
	//c*=sin(global_seed*M_PI*8)+0.3;
	color=vec4(c,1);

}
]==],escape_mode_str()))


randomize_points=shaders.Make(
[==[
#version 330
#define M_PI   3.14159265358979323846264338327950288
#line 1835
layout(location = 0) in vec4 position;
out vec4 point_out;

uniform float radius;
uniform float rand_number;

uniform int smart_reset;
//uniform vec4 params;
float random(vec2 co)
{
    float a = 12.9898;
    float b = 78.233;
    float c = 43758.5453;
    float dt= dot(co.xy ,vec2(a,b));
    float sn= mod(dt,3.14);
    return fract(sin(sn) * c);
}
vec2 random2(vec2 co)
{
    return vec2(random(co),random(co.yx*vec2(11.231,7.1)+vec2(2.5,-1.7)));
}
vec2 gaussian2 (vec2 seed,vec2 mean,vec2 var)
{
    return  vec2(
    sqrt(-2 * var.x * log(seed.x)) * cos(2 * M_PI * seed.y),
    sqrt(-2 * var.y * log(seed.x)) * sin(2 * M_PI * seed.y))+mean;
}
vec2 hash22(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

uint wang_hash(uint seed)
{
    seed = (seed ^ 61U) ^ (seed >> 16U);
    seed *= 9U;
    seed = seed ^ (seed >> 4U);
    seed *= 0x27d4eb2dU;
    seed = seed ^ (seed >> 15U);
    return seed;
}

//from: https://www.shadertoy.com/view/WttXWX
//bias: 0.17353355999581582 ( very probably the best of its kind )
uint lowbias32(uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

// bias: 0.020888578919738908 = minimal theoretic limit
uint triple32(uint x)
{
    x ^= x >> 17;
    x *= 0xed5ad4bbU;
    x ^= x >> 11;
    x *= 0xac4c1b51U;
    x ^= x >> 15;
    x *= 0x31848babU;
    x ^= x >> 14;
    return x;
}
#define HASH triple32
uvec2 wang_hash_seed(uvec2 v)
{
	return uvec2(HASH(v.x),HASH(v.y));
}
vec2 float_from_hash(uvec2 val)
{
	return val/vec2(4294967295.0);
}
vec2 float_from_floathash(vec2 val)
{
	return floatBitsToUint(val)/vec2(4294967295.0);
}
vec2 seed_from_hash(uvec2 val)
{
	return uintBitsToFloat(val);
}
bool need_reset(vec2 p,vec2 s)
{
#if 1
	if(isnan(s.x) || isnan(s.y))
		return true;
#endif
#if 1
	float move_dist=length(s-p);
	if(move_dist<0.000001)
		return true;
#endif
#if 1
	float dist=length(s);
	if(dist>2)
		return true;
#endif
	return false;
}
void main()
{
	uvec2 wseed=floatBitsToUint(position.zw);
	wseed+=uvec2(gl_VertexID);
	wseed.x+=uint(rand_number*4294967295.0);
	wseed=wang_hash_seed(wseed);
	vec2 seed=float_from_hash(wseed);
	vec2 old_seed=float_from_floathash(position.zw);
	float par_point=10000.0;
	float par_uniform=1000.0;
	float par_id=0.05;

	//vec2 seed=hash22(position.zw*params.x+hash22(vec2(rand_number*params.y,gl_VertexID*params.z))*params.w);
	//vec2 seed=hash22(vec2(rand_number*par_uniform,gl_VertexID*par_id)+position.zw*par_point);

	//vec2 seed=hash22(position.zw*params.x+vec2(rand_number*params.y,gl_VertexID*params.z));
	//vec2 seed=vec2(rand(rand_number*999999),rand(position.x*789789+position.w*rand_number*45648978));
	//vec2 seed=vec2(1-random(vec2(random_number,random_number)));//*2-vec2(1);
	//vec2 g =(seed*2-vec2(1))*radius;

	vec2 g=gaussian2(seed,vec2(0),vec2(radius));
	vec2 old_g=gaussian2(old_seed,vec2(0),vec2(radius));
	if((smart_reset==0) ||  need_reset(old_g,position.xy))
	{
		point_out.xy=g;
		point_out.zw=seed_from_hash(wseed);
	}
	else
	{
		point_out=position;
	}
}
]==],
[==[
void main()
{

}
]==],
"point_out")
visit_call_count=0
local visit_plan={
	{30,1},
	{10,2},
	{1,6},
}
function get_visit_size( vcount )
	local sum=0
	for i,v in ipairs(visit_plan) do
		sum=sum+v[1]
	end
	local cmod=vcount%sum
	sum=0
	for i,v in ipairs(visit_plan) do
		sum=sum+v[1]
		if sum>cmod then
			return v[2]
		end
	end
	return visit_plan[#visit_plan][2]
end
function divmod( a,b )
	local d=math.floor(a/b)
	return d,a - d*b
end
function vdc( n,base )
 	local ret,denom=0,1
 	while n>0 do
 		denom=denom*base
 		local remainder
 		n,remainder=divmod(n,base)
 		ret=ret+remainder/denom
 	end
 	return ret
end

local cur_sample=0
function test_point_for_random( p )
	local dx=p.r-p.b
	local dy=p.g-p.a
	if dx~=dx or dy~=dy then --nan check
		return 1
	end

	local dist=math.sqrt(dx*dx+dy*dy) --distance from start point
	if dist<0.000005 then
		return 2
	end
	local cdist=math.sqrt(p.r*p.r+p.g*p.g) --distance from center
	if cdist>2 then
		return 3
	end
end

function sample_rand( numsamples,max_count )
	local cs=samples:get_current()
	cs:use()
	cs:read(samples_data.d,max_count*4*4)
	__unbind_buffer()
	for i=1,numsamples do
		local id=math.random(0,max_count-1)
		local ss=ffi.cast("uint32_t*",samples_data.d)
		local s=samples_data.d[id]
		print(ss[id*4+2]/4294967295)
		print(ss[id*4+3]/4294967295)
		print(string.format("Id:%d %g %g %g %g",id,s.r,s.g,s.b,s.a))
	end
end
global_seed_shuffling=global_seed_shuffling or {}
function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end
function generate_shuffling( num_steps )
	global_seed_shuffling={}
	--[[ random centers with spread around
	local spread=0.0005
	local num_spread=10
	local id=1
	for i=1,num_steps do
		local c=math.random()
		for i=1,num_spread do
			global_seed_shuffling[id]=c+(math.random()*spread-0.5*spread)
			id=id+1
		end
	end
	--]]
	-- [[ vanilla
	for i=1,num_steps do
		global_seed_shuffling[i]=math.random()
	end
	--]]
	--[[ constantly biggening
	local v=math.random()
	for i=1,num_steps do
		global_seed_shuffling[i]=v
		v=v+math.random()
	end
	for i=1,num_steps do
		global_seed_shuffling[i]=global_seed_shuffling[i]/v
	end
	-- [=[ flip every second one
	for i=1,num_steps do
		if i%2==0 then
			global_seed_shuffling[i]=1-global_seed_shuffling[i]
		end
	end
	--]=]
	--]]
	-- [[ add shufflings of the original
	local num_shuffles=5
	local tmp=global_seed_shuffling
	local ret={}
	for i=1,num_shuffles do
		shuffle(tmp)
		for i,v in ipairs(tmp) do
			table.insert(ret,v)
		end
	end
	global_seed_shuffling=tmp
	--]]
end

function visit_iter()
	local shader_randomize=true
	local psize=config.point_size
	if psize<=0 then
		psize=get_visit_size(visit_call_count)
	end
	make_visits_texture()
	make_visit_shader()

	local gen_radius=config.gen_radius or 2

	local draw_sample_count=sample_count
	if config.draw and not shader_randomize then
		draw_sample_count=math.min(1e5,sample_count)
	end

	local count_reset={0,0,0,0}

	local sample_count_w=math.floor(math.sqrt(draw_sample_count))
	if cur_visit_iter>config.IFS_steps or need_clear then
		visit_call_count=visit_call_count+1
		cur_visit_iter=0
		-- [===[
		if not shader_randomize then
			if config.smart_reset then
				local cs=samples:get_current()
				cs:use()
				cs:read(samples_data.d,draw_sample_count*4*4)
				__unbind_buffer()
			end
			local last_pos={0,0}
			local samples_int=ffi.cast("struct{uint32_t d[4];}*",samples_data.d)
			for i=0,draw_sample_count-1 do
				--gaussian blob
			 	local x,y=gaussian2(0,gen_radius,0,gen_radius)
				--[[ exact grid
				local x=((i%sample_count_w)/sample_count_w-0.5)*2
				local y=(math.floor(i/sample_count_w)/sample_count_w-0.5)*2
				--]]
				--[[ halton sequence
				cur_sample=cur_sample+1
				if cur_sample>max_sample then cur_sample=0 end

				local x=vdc(cur_sample,2)*gen_radius-gen_radius/2
				local y=vdc(cur_sample,3)*gen_radius-gen_radius/2
				--]]
				--[[ box muller transform on halton sequence i.e. guassian halton?
				cur_sample=cur_sample+1
				if cur_sample>max_sample then cur_sample=0 end

				local u1=vdc(cur_sample,2)
				local u2=vdc(cur_sample,3)*math.pi*2
				local x=math.sqrt(-2*gen_radius*math.log(u1))*math.cos(u2)
				local y=math.sqrt(-2*gen_radius*math.log(u1))*math.sin(u2)
				--]]
				--[[
				local cc=i/draw_sample_count
				local pix_id=cc*win_w*win_h

				local x=(math.floor(pix_id%win_w)/win_w)*2-1
				local y=(math.floor(pix_id/win_w)/win_h)*2-1
				local blur_x=0.05/win_w
				local blur_y=0.05/win_h
				--[=[
				x=x+math.random()*blur_x-blur_x/2
				y=y+math.random()*blur_y-blur_y/2
				--]=]
				x,y=gaussian2(x,blur_x,y,blur_y)
				--print(x,y,i)
				--]]
				--[[ square
				local x=math.random()*gen_radius-gen_radius/2
				local y=math.random()*gen_radius-gen_radius/2
				--]]
				--gaussian blob with moving center
				--local x,y=gaussian2(-config.cx/config.scale,gen_radius,-config.cy/config.scale,gen_radius)
				
				--[[ n gaussian blobs
				local count=3
				local rad=2+gen_radius*gen_radius
				local n=math.random(0,count-1)
				local a=(n/count)*math.pi*2
				local cx=math.cos(a)*rad
				local cy=math.sin(a)*rad
				local x,y=gaussian2(cx,gen_radius,cy,gen_radius)
				--]]
				--[[ circle perimeter
				local a=math.random()*math.pi*2
				local x=math.cos(a)*gen_radius
				local y=math.sin(a)*gen_radius
				--]]
				--[[ random walk
				last_pos[1]=last_pos[1]+(math.random()*2-1)*gen_radius/10000
				last_pos[2]=last_pos[2]+(math.random()*2-1)*gen_radius/10000
				if math.abs(last_pos[1])>gen_radius then last_pos[1]=0 end
				if math.abs(last_pos[2])>gen_radius then last_pos[2]=0 end
				local x=last_pos[1]
				local y=last_pos[2]
				--]]
				--[[ circle area
				local a = math.random() * 2 * math.pi
				local r = gen_radius *math.sqrt(math.random())
				local x = r * math.cos(a)
				local y = r * math.sin(a)
				--]]
				--[[ spiral
				local angle_speed=500;
				local t=math.random();
				local x=math.cos(t*angle_speed)*math.sqrt(t)*gen_radius;
				local y=math.sin(t*angle_speed)*math.sqrt(t)*gen_radius;
				--]]
				-------------mods
				--[[ polar grid mod
				local r=math.sqrt(x*x+y*y)
				local a=math.atan2(y,x)
				local grid_r=0.05
				local grid_a=math.pi/21
				r=math.floor(r/grid_r)*grid_r
				--a=math.floor(a/grid_a)*grid_a

				x=math.cos(a)*r
				y=math.sin(a)*r
				--]]
				--[[ grid mod
				--local gr=math.sqrt(x*x+y*y)
				local grid_size=0.05
				x=math.floor(x/grid_size)*grid_size
				y=math.floor(y/grid_size)*grid_size
				--]]
				--[[ blur mod
				local blur_str=0.0000005
				x,y=gaussian2(x,blur_str,y,blur_str*aspect_ratio)
				--]]
				--[[ blur mod linear
				local blur_str=0.1
				x=x+math.random()*blur_str-blur_str/2
				y=y+math.random()*blur_str-blur_str/2
				--]]
				--[[ circles mod
				local circle_size=0.001
				local a2 = math.random() * 2 * math.pi
				x=x+math.cos(a2)*circle_size
				y=y+math.sin(a2)*circle_size
				--]]
				if escape_fractal then
					x=math.random()*2-1
					y=math.random()*2-1
				end
				local need_reset=test_point_for_random(samples_data.d[i])
				if need_clear or not config.smart_reset or need_reset  then
					samples_data.d[i]={x,y,x,y}
					if need_reset then
						count_reset[need_reset]=count_reset[need_reset]+1
					end
					count_reset[4]=count_reset[4]+1
				end
				--[[ for lines
				local a2 = math.random() * 2 * math.pi
				x=x+math.cos(a2)*config.move_dist
				y=y+math.sin(a2)*config.move_dist
				--samples.d[i+1]={x,y}
				--]]
			end
			reset_stats=string.format("Reset: NAN=%.3g TOO_CLOSE:%.3g TOO_FAR:%.3g Total:%.3g",count_reset[1]/draw_sample_count,count_reset[2]/draw_sample_count,count_reset[3]/draw_sample_count,count_reset[4]/draw_sample_count)
			local cs=samples:get_current()
			cs:use()
			cs:set(samples_data.d,draw_sample_count*4*4)
		else
			--]===]
			-- [===[
			randomize_points:use()
			randomize_points:set("rand_number",math.random())
			randomize_points:set("radius",config.gen_radius or 2)
			--randomize_points:set("params",config.v0,config.v1,config.v2,config.v3)
			if config.smart_reset and not need_clear then
				randomize_points:set_i("smart_reset",1)
			else
				randomize_points:set_i("smart_reset",0)
			end
			local so=samples:get_other()
			so:use()
			so:bind_to_feedback()

			samples:get_current():use()
			randomize_points:raster_discard(true)
			randomize_points:draw_points(0,draw_sample_count,4,1)
			__unbind_buffer()
			randomize_points:raster_discard(false)
			samples:flip()
			--sample_rand(10,draw_sample_count)
			--]===]
		end
	end
-- [==[
	transform_shader:use()
	transform_shader:set("center",config.cx,config.cy)
	transform_shader:set("scale",config.scale,config.scale*aspect_ratio)
	transform_shader:set("params",config.v0,config.v1,config.v2,config.v3)
	transform_shader:set("move_dist",config.move_dist)
	if shader_randomize then
		transform_shader:set_i("non_hashed_random",0)
	else
		transform_shader:set_i("non_hashed_random",1)
	end
	if #global_seed_shuffling==0 and config.shuffle_size>0 then
		generate_shuffling(config.shuffle_size)
	end
	if config.shuffle_size<=0 then
		global_seed=math.random()
	else

		global_seed_id=global_seed_id or 1
		global_seed_id=global_seed_id+1
		if global_seed_id>#global_seed_shuffling then
			if config.reshuffle then
				shuffle(global_seed_shuffling)
			end
			global_seed_id=1
		end

		global_seed=global_seed_shuffling[global_seed_id]
	end
	local max_iter=1
	if not config.draw then
		--max_iter=8
	end
	for i=1,max_iter do

		local so=samples:get_other()
		so:use()
		so:bind_to_feedback()

		samples:get_current():use()

		transform_shader:set("global_seed",global_seed)
		transform_shader:set("normed_iter",cur_visit_iter/config.IFS_steps)
		transform_shader:set("gen_radius",config.gen_radius or 2)
		transform_shader:raster_discard(true)
		transform_shader:draw_points(0,draw_sample_count,4,1)
		transform_shader:raster_discard(false)
		samples:flip()
		cur_visit_iter=cur_visit_iter+1
	end
--]==]
	if need_clear or cur_visit_iter>3 then
		add_visits_shader:use()
		local cs=samples:get_current()
		cs:use()

		add_visits_shader:raster_discard(false)
		visit_tex.t:use(0)
		add_visits_shader:push_attribute(0,"pos",4,nil,4*4)
		add_visits_shader:blend_add()
		add_visits_shader:set_i("img_tex",1)
		add_visits_shader:set_i("pix_size",psize)
		add_visits_shader:set("center",config.cx,config.cy)
		add_visits_shader:set("scale",config.scale,config.scale*aspect_ratio)
		add_visits_shader:set("normed_iter",cur_visit_iter/config.IFS_steps)
		add_visits_shader:set("global_seed",global_seed)
		set_shader_palette(add_visits_shader)
		if not visit_tex.t:render_to(visit_tex.w,visit_tex.h) then
			error("failed to set framebuffer up")
		end
		add_visits_shader:draw_points(0,draw_sample_count,4)
		if need_clear then
			__clear()
			cur_visit_iter=0
			need_clear=false
		end
	end

	__unbind_buffer()
	__render_to_window()
end

local draw_frames=600
local frame_count=30
function update_scale( new_scale )
	local old_scale=config.scale

	pfact=new_scale/old_scale

	config.scale=config.scale*pfact
	config.cx=config.cx*pfact
	config.cy=config.cy*pfact
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function lerp( x,y,v )
	return x*(1-v)+y*v
end

function update_animation_values( )
	local a=config.animation*math.pi*2
	--update_scale(math.cos(a)*0.25+0.75)
	--v2:-5,2 =>7
	--v3:-3,3

	--[[config.v1=math.random()*10-5
	config.v2=math.random()*10-5
	config.v3=math.random()*10-5
	config.v4=math.random()*10-5
	]]
	--gen_palette()
	--rand_function()
	config.move_dist=lerp(0.0001,0.1,config.animation)
	config.gamma=lerp(0.4,0.89,config.animation)
end

function update_real(  )
	__no_redraw()
	if animate then
		__clear()
		tick=tick or 0
		--
		tick=tick+1
		if tick%draw_frames==0 then
			update_animation_values()
			need_save=true
			draw_visits()
			need_clear=true
			config.animation=config.animation+1/frame_count
			if config.animation>1 then
				animate=false
			end
			draw_visits()
		end
	else
		__clear()
		if config.draw then
			draw_visits()
		end
	end
	auto_clear()
	visit_iter()
	local scale=config.scale
	local cx,cy=config.cx,config.cy

	local c,x,y= is_mouse_down()
	if c then
		--mouse to screen
		x=(x/size[1]-0.5)*2
		y=(-y/size[2]+0.5)*2
		if x>-1 and x<1 and
		   y>-1 and y<1 then
			--screen to world
			x=(x-cx)/scale
			y=(y-cy)/(scale*aspect_ratio)

			--now set that world pos so that screen center is on it
			config.cx=(-x)*scale
			config.cy=(-y)*(scale*aspect_ratio)
			need_clear=true
		end
	end
	if __mouse.wheel~=0 then
		local pfact=math.exp(__mouse.wheel/10)
		config.scale=config.scale*pfact
		config.cx=config.cx*pfact
		config.cy=config.cy*pfact
		need_clear=true
	end
end
