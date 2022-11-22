require "common"
require "colors"
require "ast_tree"

local luv=require "colors_luv"
local bwrite = require "blobwriter"
local bread = require "blobreader"
size_mult=size_mult or 0.5
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
			- multiplicative blending for "absorption" like thing DONE: not pretty :<
				- clear to blackbody
				- stamp with "multiply" and "pow(absorbtion,depth)" (actually it's exp(-depth*absorbtion))
		save hd buffer with tonemapping applied
--]]

win_w=win_w or 0
win_h=win_h or 0

aspect_ratio=aspect_ratio or 1
function update_size()
	--[[
	local trg_w=1024*2*size_mult
	local trg_h=1024*2*size_mult
	--]]
	-- [[
	local trg_w=2560*size_mult
	local trg_h=1440*size_mult
	--]]
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
local init_zero=true
local sample_count=math.pow(2,20)
local not_pixelated=0
str_x=str_x or "s.x"
str_y=str_y or "s.y"

str_cmplx=str_cmplx or "c_mul(s,vec2(prand.x,1)/sqrt(global_seeds.x*global_seeds.x+1))"

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
		visit_tex.t:use(0,not_pixelated)
		visit_tex.t:set(size[1]*oversample,size[2]*oversample,1)
		visit_buf=make_flt_buffer(size[1]*oversample,size[2]*oversample)
	end
end
-- samples i.e. random points that get transformed by IFS each step
function fill_rand_samples(data)
	local ss=ffi.cast("struct{uint32_t d[4];}*",data.d)
	for i=0,sample_count-1 do
		ss[i].d[0]=0
		ss[i].d[1]=0
		ss[i].d[2]=math.random(0,4294967295)
		ss[i].d[3]=math.random(0,4294967295)
	end
end
function fill_rand_samples_pure(data)
	local ss=ffi.cast("struct{uint32_t d[4];}*",data.d)
	for i=0,sample_count-1 do
		ss[i].d[0]=math.random(0,4294967295)
		ss[i].d[1]=math.random(0,4294967295)
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
	--[[ needs to duplicate the point init logic so dont
	for i=0,sample_count-1 do
		local x=0--math.random()
		local y=0--math.random()
		samples_data:set(i,0,{x,y,x,y})
	end
	--]]
	fill_rand_samples(samples_data)
	for i=1,2 do
		samples[i]:use()
		samples[i]:set(samples_data.d,sample_count*4*4)
	end
	__unbind_buffer()
	--]]
end
function fill_rand( )
	fill_rand_samples_pure(rnd_data)
	for i=1,2 do
		local s=rnd_samples:get(i)
		s:use()
		s:set(rnd_data.d,sample_count*4*4)
	end
	__unbind_buffer()
end
if rnd_samples == nil or rnd_samples.w~=sample_count then
	rnd_data=make_u32_buffer(sample_count,1)
	rnd_samples=multi_buffer(2)
	fill_rand()
	rnd_samples.w=sample_count
end

tick=tick or 0
config=make_config({
	{"normalize",false,type="boolean"},
	{"auto_normalize",true,type="boolean"},
	{"point_size",0,type="int",min=0,max=10},
	{"size_mult",false,type="boolean"},

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
	{"shuffle_size",200,type="int",min=1,max=200},
	--{"min_value",0,type="float",min=0,max=20},
	--{"gen_radius",2,type="float",min=0,max=10},

	{"gamma",1,type="float",min=0.01,max=5},
	{"exposure",1,type="float",min=-13,max=10},
	{"white_point",1,type="float",min=-0.01,max=10},
	--[[ other(uchimura) tonemapping

	{"max_bright",1.0,type="float",min=0,max=2},
	{"contrast",1.0,type="float",min=0,max=2},
	{"linear_start",0.22,type="float",min=0,max=2},
	{"linear_len",0.4,type="float",min=0,max=1},
	{"black_tight",1.33,type="float",min=0,max=2},
	{"black_off",0,type="float",min=0,max=1},
	--]]
	{"animation",0,type="float",min=0,max=1},
	{"reshuffle",false,type="boolean"},
	{"use_ast",false,type="boolean"},
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
#define SHOW_PALETTE 0
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
//http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
//TODO: works bad when out of bounds
vec3 xyz2rgb( vec3 c ) {
    vec3 v =  c / 100.0 * mat3(
        3.2406255, -1.5372080, -0.4986286,
        -0.9689307, 1.8757561, 0.0415175,
        0.0557101, -0.2040211, 1.0569959
    );
    vec3 r;
    r=v;
    /* srgb conversion
    r.x = ( v.r > 0.0031308 ) ? (( 1.055 * pow( v.r, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.r;
    r.y = ( v.g > 0.0031308 ) ? (( 1.055 * pow( v.g, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.g;
    r.z = ( v.b > 0.0031308 ) ? (( 1.055 * pow( v.b, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.b;
    //*/
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
float Tonemap_ACES2(float x,float wp) {
    // Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
    float a = 2.51+wp;
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
vec3 tonemap(vec3 light,float cur_exp)
{
	float lum_white =white_point*white_point;// pow(10,white_point);
	//lum_white*=lum_white;
	float Y=light.y;
#if SHOW_PALETTE
	Y=Y*exp(cur_exp)/(9.6);
#else
	Y=Y*exp(cur_exp)/(avg_lum);
#endif
	//Y=Y*exp(cur_exp);
	//Y=(Y-min_max.x)/(min_max.y-min_max.x);
	//Y=(log(Y+1)-log(min_max.x+1))/(log(min_max.y+1)-log(min_max.x+1));
	//Y=log(Y+1)/log(min_max.y+1);
#if 0
	//Y=Tonemap_Uchimura(Y);
	if(white_point<0)
		Y=Tonemap_ACES(Y);
	else
		Y=Tonemap_ACES2(Y,lum_white);
#else
	if(white_point<0)
    	Y = Y / (1 + Y); //simple compression
	else
    	Y = (Y*(1 + Y / lum_white)) / (Y + 1); //allow to burn out bright areas
#endif

	float m=Y/light.y;
	light.y=Y;
	light.xz*=m;

    //light=clamp(light,0,2);
    //float mm=max(light.x,max(light.y,light.z));
    vec3 ret=xyz2rgb((light)*100);
    //float s=smoothstep(0,1,length(light));
    //float s=smoothstep(0,1,dot(light,light));
    //float s=smoothstep(0,1,max(light.x,max(light.y,light.z)));//length(light));
    //float s=smoothstep(0.8,1.2,max(light.x,max(light.y,light.z))-1);//length(light));
    //float s=0;
    //float s=smoothstep(1,8,dot(ret,ret));
    float s=smoothstep(1,8,length(ret));
	///*
    if(ret.x>1)ret.x=1;
    if(ret.y>1)ret.y=1;
    if(ret.z>1)ret.z=1;
	//*/
    return mix(ret,vec3(1),s);
    //return ret;
}
vec3 tonemap_simple(vec3 light,float cur_exp)
{
	float lum_white =white_point*white_point;// pow(10,white_point);
	//lum_white*=lum_white;
	float Y=light.y;

	//Y=Y*exp(cur_exp)/(avg_lum);

    Y = Y / (1 + Y); //simple compression


	float m=Y/light.y;
	light.y=Y;
	light.xz*=m;

    //light=clamp(light,0,2);
    //float mm=max(light.x,max(light.y,light.z));
    vec3 ret=xyz2rgb((light)*100);
    //float s=smoothstep(0,1,length(light));
    //float s=smoothstep(0,1,dot(light,light));
    //float s=smoothstep(0,1,max(light.x,max(light.y,light.z)));//length(light));
    //float s=smoothstep(0.8,1.2,max(light.x,max(light.y,light.z))-1);//length(light));
    //float s=0;
    //float s=smoothstep(1,8,dot(ret,ret));
    float s=smoothstep(1,8,length(ret));
	///*
    if(ret.x>1)ret.x=1;
    if(ret.y>1)ret.y=1;
    if(ret.z>1)ret.z=1;
	//*/
    //return mix(ret,vec3(1),s);
    return ret;
}
vec3 YxyToXyz(vec3 v)
{
	vec3 ret;
	ret.y=v.x;
    float small_x = v.y;
    float small_y = v.z;
    ret.x = ret.y*(small_x / small_y);
    float small_z=1-small_x-small_y;

    //all of these are the same
    ret.z = ret.x/small_x-ret.x-ret.y;
    return ret;
}
void main_normal(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
#if SHOW_PALETTE
	vec3 ccol=mix_palette2(normed.x).xyz;
#else
	vec3 ccol=texture(tex_main,normed).xyz;
#endif

	/*
	if(ccol.x<0)ccol.x=log(1-ccol.x);
	if(ccol.y<0)ccol.y=log(1-ccol.y);
	if(ccol.z<0)ccol.z=log(1-ccol.z);
	//*/

	//ccol=abs(ccol);
	ccol=max(vec3(0),ccol);
	ccol=pow(ccol,vec3(v_gamma));
	//ccol*=exp(v_gamma);
#if 0
	float e1=exposure;
	float e2=exposure+1;
	float lerp_w=0.1;
	float band_w=0.3;
	float v=1-smoothstep(band_w-lerp_w/2,band_w+lerp_w/2,abs(pos.x));

	color = vec4(tonemap(ccol,mix(e1,e2,v)),1);
#elif 0
	float auto_exp=-5.8*v_gamma+3.93;
	color = vec4(tonemap(ccol,auto_exp),1);
#else
	color = vec4(tonemap(ccol,exposure),1);
#endif
	//color.xyz=pow(color.xyz,vec3(v_gamma));
	//color.xyz=pow(color.xyz,vec3(2.4));
	color.a=1;
}
void main_complex()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 complex_value=texture(tex_main,normed).xy;
	float lum_white=white_point*white_point;
#if 0 //radius
	float Y=length(complex_value);
	//Y=(Y-min_max.x)/(min_max.y-min_max.x);
	Y=(log(Y+1)-log(min_max.x+1))/(log(min_max.y+1)-log(min_max.x+1));
	//Y=log(Y+2.8);
	Y=Y*exp(exposure);//(exp(avg_lum));
	//Y=Y*exposure;
	Y=pow(Y,v_gamma);
	//Y=Y/(Y+1);
	//Y = (Y*(1 + Y / lum_white)) / (Y + 1);
	vec3 ccol=mix_palette2(1-Y).xyz;
	//ccol.y=length(complex_value);
	color = vec4(tonemap_simple(ccol,1),1);
	//color.xyz=vec3(Y);
#elif 1 //mixed
	float Y=length(complex_value);
	float T=atan(complex_value.y,complex_value.x)/M_PI+0.5;

	//Y=(Y-min_max.x)/(min_max.y-min_max.x);
	Y=(log(Y+1)-log(min_max.x+1))/(log(min_max.y+1)-log(min_max.x+1));
	//Y=log(Y+2.8);
	Y=Y*exp(exposure);//(exp(avg_lum));
	//Y=Y*exposure;
	Y=pow(Y,v_gamma);
	//Y=Y/(Y+1);
	//Y = (Y*(1 + Y / lum_white)) / (Y + 1);
	vec3 ccol=mix_palette2(T).xyz*Y;
	//ccol.y*=Y;
	color = vec4(tonemap(ccol,exposure),1);
#else //angle
	float Y=atan(complex_value.y,complex_value.x)/M_PI+0.5;
	color.xyz=vec3(Y);
#endif
	color.a=1;
}
#define COMPLEX_POINT_OUTPUT 0
void main()
{
#define COMPLEX_POINT_OUTPUT 0
#if COMPLEX_POINT_OUTPUT
	main_complex();
#else
	main_normal();
#endif
}
]==]


local need_save
local need_buffer_save
function buffer_save( name ,min,max,avg)
	local b=bwrite()
	b:u32(visit_buf.w)
	b:u32(visit_buf.h)
	b:u32(4)--channels
	b:u32(0)--do log norm
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
	tex:use(0,not_pixelated)
	local lmin={math.huge,math.huge,math.huge}
	local lmax={-math.huge,-math.huge,-math.huge}

	local llmin=math.huge
	local llmax=-math.huge
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
		--local lum=math.sqrt(v.g*v.g+v.r*v.r+v.b*v.b)--math.abs(v.g+v.r+v.b)
		--local lum=math.sqrt(v.g*v.g+v.r*v.r)
		local lum=v.g
		if llmin>lum then llmin=lum end
		if llmax<lum then llmax=lum end
		--avg_lum=avg_lum+lum
		--local lum=math.abs(v.g)
		--local lum=math.abs(v.g)+math.abs(v.r)+math.abs(v.b)
		--if lum > config.min_value then
			avg_lum=avg_lum+math.log(1+lum)
			count=count+1
		--end
	end
	end
	avg_lum = avg_lum / count;
	--avg_lum = math.exp(avg_lum / count);
	--[[print(avg_lum)
	for i,v in ipairs(lmax) do
		print(i,v)
	end
	--]]
	return lmin,lmax,avg_lum,llmin,llmax
end
count_visits=0
function draw_visits(  )

	make_visits_texture()
	local lmin,lmax,lavg,llmin,llmax=unpack(visits_minmax)
	if config.normalize or need_buffer_save or lmin==nil or 
		(count_visits>1000 and config.auto_normalize) then
		lmin,lmax,lavg,llmin,llmax=find_min_max(visit_tex.t,visit_buf)
		visits_minmax={lmin,lmax,lavg,llmin,llmax}
		count_visits=0
	end
	count_visits=count_visits+1
	if need_buffer_save then
		buffer_save(need_buffer_save,visits_minmax[1],visits_minmax[2],lavg)
		need_buffer_save=nil
	end

	display_shader:use()
	visit_tex.t:use(0,not_pixelated)
	set_shader_palette(display_shader)
	display_shader:set("min_max",llmin or 0,llmax or 0)
	--display_shader:set("min_max",lmin[2],lmax[2])

	--[[ uchimura tonemapping
	display_shader:set("uchimura_params[0]",config.max_bright)
	display_shader:set("uchimura_params[1]",config.contrast)
	display_shader:set("uchimura_params[2]",config.linear_start)
	display_shader:set("uchimura_params[3]",config.linear_len)
	display_shader:set("uchimura_params[4]",config.black_tight)
	display_shader:set("uchimura_params[5]",config.black_off)
	--]]
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
current_gen=8,
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
function mix_color_xyz( c1,c2,v )
	local c1_v=c1[5]
	local c2_v=c2[5]
	local c_v=c2_v-c1_v
	local my_v=v-c1_v
	local local_v=my_v/c_v

	local c1_rgb={c1[1],c1[2],c1[3]}
	local c2_rgb={c2[1],c2[2],c2[3]}
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
		if palette.is_xyz then
			s:set_i("palette_xyz",1)
			c=mix_color_xyz(palette.colors_input[cur_color-1],palette.colors_input[cur_color],i)
		else
			s:set_i("palette_xyz",0)
			if palette.rgb_lerp then
				c=mix_color_rgb(palette.colors_input[cur_color-1],palette.colors_input[cur_color],i)
			else
				c=mix_color_hsl(palette.colors_input[cur_color-1],palette.colors_input[cur_color],i)
			end
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
function mix( v_low,v_high,v )
	return v_low*(1-v)+v_high*v
end
function black_body_spectrum( l,temperature)
	--[[
	float h=6.626070040e-34; //Planck constant
	float c=299792458; //Speed of light
	float k=1.38064852e-23; //Boltzmann constant
	--]]
	local const_1=5.955215e-17;--h*c*c
	local const_2=0.0143878;--(h*c)/k
	local top=(2*const_1);
	local bottom=(math.exp((const_2)/(temperature*l))-1)*l*l*l*l*l;
	return top/bottom;
end
function black_body(iter, temp)
	return black_body_spectrum(mix(380*1e-9,740*1e-9,iter),temp);
end
function D65_approx(iter)
	--3rd order fit on D65
	local wl=mix(380,740,iter);
	--return (-1783+9.98*wl-(0.0171)*wl*wl+(9.51e-06)*wl*wl*wl)*1e12;
	return (-1783.1047729784+9.977734354*wl-(0.0171304983)*wl*wl+(0.0000095146)*wl*wl*wl);
end
function D65_blackbody(iter, temp)
	--local wl=mix(380,740,iter);
	--[[
	float mod=-5754+27.3*wl-0.043*wl*wl+(2.26e-05)*wl*wl*wl;
	return black_body(wl*1e-9,temp)-mod;
	]]
	--6th order poly fit on black_body/D65
	--[[
	float mod=6443-67.8*wl*(
			1-0.004365781*wl*(
				1-(2.31e-3)*wl*(
					1-(1.29e-03)*wl*(
						1-(6.68e-04)*wl*(
							1-(2.84e-04)*wl
										)
									)
								)
						  	 )
						  	);
	]]
	--float mod=6443-67.8*wl+0.296*wl*wl-(6.84E-04)*wl*wl*wl+(8.84E-07)*wl*wl*wl*wl-
	--	6.06E-10*wl*wl*wl*wl*wl+1.72E-13*wl*wl*wl*wl*wl*wl;

	--[[float mod=6449.3916465248
	+wl*(
		-67.868524542
		+wl*(0.2960426028
			+wl*((-0.0006846726)
				+wl*((8.852e-7)+
					wl*((-6e-10)+0*wl)
					)
				)
			)
		);

	return black_body(wl*1e-9,temp)*mod*1e-8;]]
	local b65=black_body(iter,6503.5);
	return D65_approx(iter)*(black_body(iter,temp)/b65);
end
function gaussian_value( x, alpha,  mu, sigma1,  sigma2) 
	local s=sigma1
	if x>=mu then
		s=sigma2
	end
  	local squareRoot = (x - mu)/(s);
  	return alpha * math.exp( -(squareRoot * squareRoot)/2 );
end

function xyz_from_normed_waves(v_in)
	local ret={}
	ret.x = gaussian_value(v_in,  1.056, 0.6106, 0.10528, 0.0861)
		+ gaussian_value(v_in,  0.362, 0.1722, 0.04444, 0.0742)
		+ gaussian_value(v_in, -0.065, 0.3364, 0.05667, 0.0728);

	ret.y = gaussian_value(v_in,  0.821, 0.5244, 0.1303, 0.1125)
	    + gaussian_value(v_in,  0.286, 0.4192, 0.0452, 0.0864);

	ret.z = gaussian_value(v_in,  1.217, 0.1583, 0.0328, 0.1)
	    + gaussian_value(v_in,  0.681, 0.2194, 0.0722, 0.0383);

	return ret;
end
function gen_layers( min,max,count )
	local ret={}
	for i=1,count do
		--local d=math.random()*(max-min)+min
		local d=gaussian((max-min)/2,max-min)
		table.insert(ret,d)
	end
	return ret
end
function phase_difference(layers,n1,n0,angle,wavelen,layer_count)
	layer_count=layer_count or #layers
	local ret=0
	for i=1,layer_count do
		local d=layers[i]
		ret=ret+d*(n1/n0)*math.cos(angle)/wavelen
	end
	return ret*math.pi*4
end
palette.generators={
	{"random",function (ret, hue_range,sat_range,lit_range )
		local count=math.random(3,10)
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
	end},{"fullspectrum",function (ret, hue_range,sat_range,lit_range )
		palette.is_xyz=true
		for i=0,max_palette_size-1 do
			local h=i/(max_palette_size-1)
			local w=xyz_from_normed_waves(h)
			local b=D65_blackbody(h,6503.5)
			--local b=black_body(h,6503.5)
			--local b=1
			w.x=w.x*b
			w.y=w.y*b
			w.z=w.z*b
			table.insert(ret,new_color(w.x,w.y,w.z,(i/(max_palette_size-1))*(max_palette_size-1)))
		end
	end},{"full_temperature",function (ret, hue_range,sat_range,lit_range )
		palette.is_xyz=true
		local max_temp=8000
		local min_temp=6100
		for i=0,max_palette_size-1 do
			local h=i/(max_palette_size-1)
			--h=math.pow(h,4)
			local s={x=0,y=0,z=0}
			local step_size=0.001
			for j=0,1,step_size do
				local w=xyz_from_normed_waves(j)
				--local b=D65_blackbody(j,min_temp+(max_temp-min_temp)*i)--6503.5)
				local b=black_body(j,min_temp+(max_temp-min_temp)*h)
				--local b=1
				s.x=s.x+w.x*b*step_size
				s.y=s.y+w.y*b*step_size
				s.z=s.z+w.z*b*step_size
			end
			table.insert(ret,new_color(s.x,s.y,s.z,(i/(max_palette_size-1))*(max_palette_size-1)))
		end
	end},{"pearl",function (ret, hue_range,sat_range,lit_range )
		palette.is_xyz=true
		local layers=gen_layers(400,700,1000)
		for i=0,max_palette_size-1 do
			local s={x=0,y=0,z=0}
			local h=i/(max_palette_size-1)
			local angle=h*math.pi/4
			local step_size=0.01
			for nw=0,1,step_size do
				local w=xyz_from_normed_waves(nw)
				local b=D65_blackbody(nw,6503.5)--6503.5)
				--local b=black_body(h,6503.5)--6503.5)
				--thickness 400->700nm
				local wl=mix(380,740,nw);
				--function phase_difference(layer_thickness_min,layer_thickness_max,count,n1,n0,angle,wavelen)
				local eta=phase_difference(layers,1.53,1.0,math.pi/8,wl,math.floor(800*h)+200)
				b=b*(math.cos(eta)+1)*step_size
				s.x=s.x+w.x*b
				s.y=s.y+w.y*b
				s.z=s.z+w.z*b
			end
			table.insert(ret,new_color(s.x,s.y,s.z,(i/(max_palette_size-1))*(max_palette_size-1)))
		end
	end
	}
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
	palette.is_xyz=false
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
	if animate then
		img_buf:save(string.format("video/saved_%d.png",os.time(os.date("!*t"))),config_serial)
	else
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	end
end


local terminal_symbols={
--[[
["s.x"]=3,["s.y"]=3,["p.x"]=3,["p.y"]=3,
["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,
["normed_iter"]=0.05,
--]]
["1.0"]=0.1,
--["0.0"]=0.1,
["-1.0"]=0.1,
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
-- [[
["max(R,R)"]=0.05,["min(R,R)"]=0.05,
["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,
["abs(R)"]=0.1,["sqrt(abs(R))"]=0.1,["exp(R)"]=0.01,
["atan(R,R)"]=0.1,
["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,
["acos(R)"]=0.001,["asin(R)"]=0.001,
["log(R)"]=0.001,
--]]
["(R)/(R)"]=0.05,["(R)*(R)"]=2,
["(R)-(R)"]=3,["(R)+(R)"]=3
}

local terminal_symbols_complex={
--["s"]=0.005,["p"]=0.005,
--["params.xy"]=1,["params.zw"]=1,
--["(c_one()*normed_iter)"]=0.05,["(c_i()*normed_iter)"]=0.05,
--["(c_one()*global_seed)"]=0.05,["(c_i()*global_seed)"]=0.05,
--["(c_one()*prand.x)"]=0.05,["(c_i()*prand.x)"]=0.05,
--["vec2(cos(prand.x*2*M_PI),sin(prand.x*2*M_PI))*move_dist"]=0.5,
["c_one()"]=0.1,["c_i()"]=0.1,
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
["(R)-(R)"]=3,["(R)+(R)"]=3,
--["cheb_eval(R)"]=1
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
		ret=ret.."("..rc..string.format("+vec2(%g,%g))*value_inside(prand.x,%g,%g)",dx,dy,istart,iend)
		--[[
		if i==1 then
			ret=ret..string.format("(c_mul(%s,vec2(%g,%g))+vec2(%g,%g))*value_inside(global_seeds.x,%g,%g)",rc,dx,dy,dx2,dy2,istart,iend)
		else
			ret=ret..string.format("(c_mul(s,vec2(%g,%g))+vec2(%g,%g))*value_inside(global_seeds.x,%g,%g)",dx,dy,dx2,dy2,istart,iend)
		end
		--]]
		--ret=ret..string.format("(c_pow(s,%d)+p+vec2(%g,%g))*value_inside(global_seeds.x,%g,%g)",i+1,dx,dy,istart,iend)
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
		--[[
		local dx=math.random()*2-1
		local dy=math.sqrt(1-dx*dx)--math.random()*0.5-0.25
		if math.random()>0.5 then
			dy=-dy
		end
		local dx2=math.random()*0.5-0.25
		local dy2=math.random()*0.5-0.25
		--]]
		-- [[
		local dx=math.cos(istart*math.pi*2)*1
		local dy=math.sin(istart*math.pi*2)*1
		--]]
		--[[x
		local dx=0
		local dy=0
		--]]
		local delta=dx
		if not is_dx then delta=dy end

		ret=ret.."("..rc..string.format("+%g)*value_inside(global_seeds.x,%g,%g)",dy,istart,iend)
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
function rand_poly( degree )
	local ret={}
	for i=1,degree do
		local x=1
		local y=0
		--[[
		x=math.random()-0.5
		y=math.random()-0.5
		--]]
		-- [[
		x=math.random()-0.5
		y=math.sqrt(1-x*x)
		if math.random()>0.5 then
			y=-y
		end
		--]]
		ret[i-1]=string.format("vec2(%g,%g)",x,y)--math.random()-0.5,math.random()-0.5)
	end
	return ret
end
function derivate( poly )
	local ret={}
	for i=2,#poly do
		ret[i-2]=poly[i-1].."*"..i
	end
	return ret
end
function poly_to_string(poly)
	local ret=""
	local s_str="vec2(1,0)"
	for i=0,#poly do
		ret=ret..string.format("c_mul(%s,%s)",s_str,poly[i])
		if i~=#poly then
			ret=ret.."+"
		end
		s_str=string.format("c_mul(%s,s)",s_str)
	end
	return ret
end
function newton_fractal( degree )
	local ret=""
	local p=rand_poly(degree)
	local pder=derivate(p)
	local f1=poly_to_string(p)
	local f2=poly_to_string(pder)
	local fract=string.format("c_div(%s,%s)",f1,f2)
	local prot="vec2(cos(global_seeds.x*2*M_PI),sin(global_seeds.x*2*M_PI))"
	--ret=ret..string.format("s-c_mul(c_mul(params.xy,%s),%s)+c_mul(params.zw,p)",prot,fract)
	ret=ret..string.format("s-c_mul(params.xy,%s)+c_mul(params.zw,p)",fract)
	return ret
end
function chebyshev_poly_series( degree )
	local values={}
	local sum_value={0,0}
	for i=1,degree do
		local v={math.random()*2-1,math.random()*2-1}--{math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1}--{i-degree/2,-i+degree/2}--{math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1}
		--v[2]=v[1]*(-1)
		local l=math.sqrt(v[1]*v[1]+v[2]*v[2])
		v[1]=v[1]/l
		v[2]=v[2]/l
		values[i]=v
		for i=1,2 do
			sum_value[i]=sum_value[i]+v[i]*v[i]
		end
	end
	local function insert_vec2( v )
		return string.format("vec2(%g,%g)",v[1],v[2])
	end
	for i=1,degree do
		for j=1,2 do
			values[i][j]=values[i][j]/math.sqrt(sum_value[j])
		end
		print(i,insert_vec2(values[i]))
	end
	
	str_other_code="vec2 cheb_eval(vec2 x){ vec2 ret=vec2(0); vec2 pure_chb_1=x;vec2 pure_chb_0=vec2(0);vec2 tmp_chb;\n"
	str_other_code=str_other_code..string.format("ret+=%s*pure_chb_0;\n",insert_vec2(values[1]))
	str_other_code=str_other_code..string.format("ret+=%s*pure_chb_1;\n",insert_vec2(values[2]))
	for i=3,degree do
		str_other_code=str_other_code.."tmp_chb=2*x*pure_chb_1-pure_chb_0;\npure_chb_0=pure_chb_1;pure_chb_1=tmp_chb;"
		str_other_code=str_other_code..string.format("ret+=%s*pure_chb_1;\n",insert_vec2(values[i]))
	end
	str_other_code=str_other_code.."return ret;}"
	--print(str_other_code)
	--str_cmplx="cheb_eval(s*params.xy+p*params.zw)*global_seeds.x+vec2(atan(tex_s.y,tex_s.x),atan(tex_p.y,tex_p.x))/M_PI"
end
animate=false
--ast_tree=ast_tree or ast_node(normal_symbols_complex,terminal_symbols_complex)

function get_forced_insert_complex(  )
	--local tbl_insert={}
	local tbl_insert={"s","p"}
	--local tbl_insert={"s","p","params.xy","params.zw"}
	--{"s","p","vec2(cos(global_seeds.x*2*M_PI),sin(global_seeds.x*2*M_PI))","params.xy","params.zw"})--{"vec2(global_seeds.x,0)","vec2(0,1-global_seeds.x)"})
	--{"s","c_mul(p,vec2(exp(-npl),1-exp(-npl)))","c_mul(params.xy,vec2(cos(global_seeds.x*2*M_PI),sin(global_seeds.x*2*M_PI)))","params.zw"})
	--{"vec2(cos(length(s)*M_PI*5+move_dist),sin(length(s)*M_PI*5+move_dist))*(0.25+global_seeds.x)","vec2(cos(length(p)*M_PI*4+global_seeds.x),sin(length(p)*M_PI*4+global_seeds.x))*(move_dist)","params.xy","params.zw","vec2(s.x,p.y)","vec2(p.x,s.y)"}
	--"mix(p,p/length(p),global_seeds.x)"
	--vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2))*move_dist
	--local tbl_insert_cmplx={"mix(s,s/length(s),1-global_seeds.x)","mix(p,p/length(p),global_seeds.x)","params.xy","params.zw"}--"mix(p,p/length(p),global_seeds.x)"

	--local tbl_insert={"s","c_mul(p,vec2(-1,1+(global_seeds.x-0.5)*move_dist))","params.xy","params.zw"} --"(p*(global_seeds.x+0.5))/length(p)"
	--local tbl_insert={"c_mul(s,s)","c_mul(p,p)","c_mul(s,p)","params.xy","params.zw","vec2(cos((global_seeds.x-0.5)*M_PI*2*move_dist),sin((global_seeds.x-0.5)*M_PI*2*move_dist))"} --"(p*(global_seeds.x+0.5))/length(p)"
	--local tbl_insert={"mix(c_mul(s,s),c_mul(p,p),global_seeds.x)","c_mul(s,p)","params.xy","params.zw"}
	--local tbl_insert={"mix(c_mul(c_mul(s,s),s),c_mul(c_mul(p,p),p),global_seeds.x)","c_mul(s,p)","params.xy","params.zw"}
	--local tbl_insert={"s","p","mix(params.xy,params.zw,exp(-global_seeds.x*global_seeds.x*8))"} --"(p*(global_seeds.x+0.5))/length(p)"

	--local tbl_insert={"s*(length(s-p)*prand.x)","p","params.xy","params.zw"}
	--local tbl_insert={"params.xy+s*params.z+p*params.w+c_mul(s,p)*global_seeds.x"}
	--local tbl_insert={"c_mul(s,s)","c_mul(p,p)","c_mul(s,p)","params.xy","params.zw","vec2(cos((global_seeds.x-0.5)*M_PI*2*move_dist),sin((global_seeds.x-0.5)*M_PI*2*move_dist))"} --"(p*(global_seeds.x+0.5))/length(p)"
	--local tbl_insert={"s","p","mix(params.xy,params.zw,exp(-global_seeds.x*global_seeds.x*3))"} --"(p*(global_seeds.x+0.5))/length(p)"
	--local tbl_insert={"vec2(s.y,mix(s.x,move_dist,global_seeds.x))","p","params.xy","params.zw"}
	--local tbl_insert={"s","p","mix(s*params.xy,s*params.zw,global_seeds.x)","mix(p*params.zw,p*params.xy,global_seeds.x)"}
	--local tbl_insert={"s","p","mix(s*params.xy,s*params.zw,prand.x)","mix(p*params.zw,p*params.xy,prand.x)"}
	--local tbl_insert={"c_mul(mix(s,p,global_seeds.x),mix(p,s,global_seeds.x))","c_mul(mix(c_mul(s,s),c_mul(p,p),global_seeds.x*global_seeds.x),mix(c_mul(p,p),c_mul(s,s),global_seeds.x*global_seeds.x))","params.xy","params.zw"}
	table.insert(tbl_insert,"params.xy")
	table.insert(tbl_insert,"params.zw")
	--table.insert(tbl_insert,"vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2))*prand.x")
	--table.insert(tbl_insert,"vec2(cos(prand.x*M_PI*2+tex_s.x),sin(prand.x*M_PI*2+tex_s.x))*move_dist")
	--table.insert(tbl_insert,"vec2(cos(prand.y*M_PI*2),sin(prand.y*M_PI*2))*move_dist")
	--table.insert(tbl_insert,"vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2))")
	--table.insert(tbl_insert,"vec2(cos(prand.x*prand.x*4),sin(prand.x*prand.x*4))")
	--table.insert(tbl_insert,"vec2(cos(prand.y*M_PI*2),sin(prand.y*M_PI*2))*(1-prand.x)*move_dist")
	--table.insert(tbl_insert,"vec2(prand.x,0)")
	--table.insert(tbl_insert,"prand.x*s+prand.x*prand.x*p+prand.x*prand.x*prand.x")
	-- [[
	--table.insert(tbl_insert,"mix(c_mul(s,params.xy),c_mul(s,params.zw),prand.x)")
	--table.insert(tbl_insert,"mix(c_mul(s,params.xy),c_mul(s,params.zw),prand.x*prand.x)")
	--table.insert(tbl_insert,"mix(c_mul(s-p,params.xy),c_mul(s-p,params.zw),prand.x)")
	--table.insert(tbl_insert,"mix(c_mul(s,params.xy),c_mul(s,params.zw),1-prand.x)")
	--table.insert(tbl_insert,"mix(c_mul(p,params.xy),c_mul(p,params.zw),prand.x)")
	--table.insert(tbl_insert,"mix(c_mul(mix(s,p,prand.y),params.xw),c_mul(mix(s,p,prand.y),params.xy),prand.x)")
	--table.insert(tbl_insert,"rotate(s-p,M_PI*2*prand.x)+p")
	--table.insert(tbl_insert,"rotate(s/(0.01+length(s)),M_PI*2*prand.x*move_dist)")
	--table.insert(tbl_insert,"(normalize(p-s)*prand.x*move_dist)")
	--table.insert(tbl_insert,"(dot(normalize(s),normalize(p))*prand.x*move_dist*s)")
	table.insert(tbl_insert,"((last_s-s)*prand.x*move_dist)")

	--]]
	--[==[
	local rand_choices={
		"s","c_mul(s,s)","c_mul(c_mul(s,s),s)","c_mul(c_mul(s,s),c_mul(s,s))",
		"p","c_mul(p,p)","c_mul(c_mul(p,p),p)","c_mul(c_mul(p,p),c_mul(p,p))",
		"c_mul(p,s)","c_mul(c_mul(p,s),p)","c_mul(c_mul(p,s),c_mul(p,s))",
		"c_mul(p,s)","c_mul(c_mul(p,s),s)","c_mul(c_mul(p,s),c_mul(s,s))",
	}
	local NO_PICKS=5
	for i=1,NO_PICKS do
		table.insert(tbl_insert,rand_choices[math.random(1,#rand_choices)])
	end
	--]==]
	--[=[
	local mob_count=8
	local mob={}
	for i=1,8*mob_count do
		table.insert(mob,math.random()*2-1)
	end
	--params.xy=a params.zw=b, m1,m2=c,gvec=d
	-- [[
	for i=0,mob_count-1 do
		local cval=i/mob_count
		local nval=(i+1)/mob_count
		table.insert(tbl_insert,string.format("mix(vec2(1,0),mobius(vec2(%g,%g),vec2(%g,%g),vec2(%g,%g),vec2(%g,%g),s),value_inside(prand.x,%g,%g))",
			mob[i*8+1],mob[i*8+2],mob[i*8+3],mob[i*8+4],mob[i*8+5],mob[i*8+6],mob[i*8+7],mob[i*8+8],cval,nval))
	end
	--[[
	for i=1,10 do
	table.insert(tbl_insert,
		string.format("mobius(vec2(%g,%g),vec2(%g,%g),vec2(%g,%g),vec2(%g,%g),s)",
			math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1))
	end
	--]]
	-- [[
	table.insert(tbl_insert,
		string.format("mobius(params.xy,params.zw,vec2(%g,%g),vec2(%g,%g),s)",
			math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1))
	--]]
	--[[
	table.insert(tbl_insert,
		string.format("mobius(vec2(%g,%g),vec2(prand.x,0),vec2(%g,%g),vec2(%g,%g),s)",
			math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1,math.random()*2-1))
	--]]
	--]=]
	-- [[
	--table.insert(tbl_insert,"vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2))*move_dist")
	--table.insert(tbl_insert,"vec2(cos(prand.y*M_PI*2),sin(prand.y*M_PI*2))*move_dist")
	--table.insert(tbl_insert,"vec2(prand.x,0)")
	--table.insert(tbl_insert,"vec2(prand.y,0)")
	--table.insert(tbl_insert,"vec2(0,1-prand.x)")
	--]]
	--table.insert(tbl_insert,"vec2(length(tex_p),length(tex_s))*prand.x")
	--table.insert(tbl_insert,"vec2(length(p),length(s))")
	--table.insert(tbl_insert,"mix(params.xy,params.zw,global_seeds.x)")
	--table.insert(tbl_insert,"mix(s,p,global_seeds.x)")
	--table.insert(tbl_insert,"c_mul(mix(s,p,global_seeds.x),mix(s,p,1-global_seeds.x))")
	--table.insert(tbl_insert,"((global_seeds.x*2-1)*(move_dist*c_mul(s,s)+s+p))")
	--table.insert(tbl_insert,"((prand.x*2-1)*(move_dist*c_mul(s,s)+s+p))")
	--[[
	table.insert(tbl_insert,"vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2))")
	--]]
	--[[
	local num_roots=5
	local dist=1
	for i=1,num_roots do
		local v=((i-1)/num_roots)*math.pi*2
		--table.insert(tbl_insert,string.format("vec2(%g,%g)",math.cos(v)*dist,math.sin(v)*dist))
		table.insert(tbl_insert,string.format("vec2(%g,%g)*global_seeds.x",math.cos(v)*dist,math.sin(v)*dist))
	end
	--]]
	--[==[
	local tex_variants={
		-- [[
		"tex_p.xy","tex_p.yz","tex_p.zx",
		"tex_s.xy","tex_s.yz","tex_s.zx",
		"vec2(tex_s.x,tex_p.x)","vec2(tex_s.y,tex_p.y)","vec2(tex_s.z,tex_p.z)",
		"vec2(tex_s.x,tex_p.y)","vec2(tex_s.y,tex_p.z)","vec2(tex_s.z,tex_p.x)",
		"vec2(tex_s.x,tex_p.z)","vec2(tex_s.y,tex_p.x)","vec2(tex_s.z,tex_p.y)",
		--]]
		-- [[
		"vec2(atan(tex_s.y,tex_s.x),atan(tex_p.y,tex_p.x))/M_PI","vec2(atan(tex_p.y,tex_p.x),atan(tex_s.y,tex_s.x))/M_PI",
		"vec2(atan(tex_s.x,tex_s.z),atan(tex_p.x,tex_p.z))/M_PI","vec2(atan(tex_p.x,tex_p.z),atan(tex_s.x,tex_s.z))/M_PI"
		--]]
		--[[ COMPLEX output tex sampling
		"vec2(atan(tex_s.y,tex_s.x),atan(tex_p.y,tex_p.x))/M_PI",
		"vec2(length(tex_s.xy),length(tex_p.xy))",
		--]]
	}

	local num_tex=2
	for i=1,num_tex do
		table.insert(tbl_insert,"(("..tex_variants[math.random(1,#tex_variants)].."))")
		--table.insert(tbl_insert,"(("..tex_variants[math.random(1,#tex_variants)]..")*prand.x)")
		--table.insert(tbl_insert,"(("..tex_variants[math.random(1,#tex_variants)]..")*move_dist*prand.x)")
		--table.insert(tbl_insert,"c_mul("..tex_variants[math.random(1,#tex_variants)]..",vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2))*move_dist)")
		--table.insert(tbl_insert,"c_mul("..tex_variants[math.random(1,#tex_variants)]..",vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2)))")
		--table.insert(tbl_insert,tex_variants[math.random(1,#tex_variants)])
		--table.insert(tbl_insert,"c_mul("..tex_variants[math.random(1,#tex_variants)]..",vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2)))")
		--table.insert(tbl_insert,tex_variants[math.random(1,#tex_variants)])
		--table.insert(tbl_insert_x,tex_variants[math.random(1,#tex_variants)])
		--table.insert(tbl_insert_y,tex_variants[math.random(1,#tex_variants)])
	end
	--]==]
	--table.insert(tbl_insert,"vec2(cos(tex_p.x*global_seeds.x*2*M_PI),sin(tex_p.y*global_seeds.x*2*M_PI))")
	--table.insert(tbl_insert,"vec2(cos(tex_p.x*move_dist*global_seeds.x*2*M_PI),sin(tex_p.y*move_dist*global_seeds.x*2*M_PI))")
	--table.insert(tbl_insert,"vec2(cos(tex_s.x*global_seeds.x*2*M_PI),sin(tex_s.y*global_seeds.x*2*M_PI))")
	--table.insert(tbl_insert,"vec2(cos(tex_p.y*global_seeds.x*2*M_PI),sin(tex_p.z*global_seeds.x*2*M_PI))")
	--table.insert(tbl_insert,"vec2(cos(tex_s.y*global_seeds.x*2*M_PI),sin(tex_s.z*global_seeds.x*2*M_PI))")
	--table.insert(tbl_insert,"(c_mul(s-p,vec2(cos(tex_s.x*global_seeds.x*2*M_PI),sin(tex_s.y*global_seeds.x*2*M_PI)))+p)")
	--table.insert(tbl_insert,"(c_mul(s-p,vec2(cos(tex_s.x*global_seeds.x*2*M_PI),sin(tex_s.x*global_seeds.x*2*M_PI)))+p)")
	--table.insert(tbl_insert,"(c_mul(s-p,vec2(cos(tex_sl*global_seeds.x*2*M_PI),sin(tex_sl*global_seeds.x*2*M_PI)))+p)")
	--table.insert(tbl_insert,"(c_mul(s-p,vec2(cos(tex_pl*move_dist*global_seeds.x*2*M_PI),sin(tex_pl*move_dist*global_seeds.x*2*M_PI)))+p)")
	--[==[

	local num_parts=10
	for i=1,num_parts do
		table.insert(tbl_insert,string.format("(vec2(global_seeds.x,global_seeds.x)*value_inside(global_seeds.x,%g,%g))",(i-1)/num_parts,i/num_parts))
	end
	--]==]
	--[==[
	local num_parts=10
	for i=1,num_parts do
		table.insert(tbl_insert,string.format("(vec2(1,0)*value_inside(prand.x,%g,%g))",(i-1)/num_parts,i/num_parts))
	end
	--]==]
	return tbl_insert
end
function get_forced_insert( )
	local tbl_insert_x={}
	local tbl_insert_y={}
	-- [[ random picks
	local choices={
		"s.x","s.x*s.x","s.x*s.x*s.x","s.x*s.x*s.x*s.x",
		"s.y","s.y*s.y","s.y*s.y*s.y","s.y*s.y*s.y*s.y",
		"p.x","p.x*p.x","p.x*p.x*p.x","p.x*p.x*p.x*p.x",
		"p.y","p.y*p.y","p.y*p.y*p.y","p.y*p.y*p.y*p.y",
	}
	local NO_PICKS=5
	for i=1,NO_PICKS do
		if math.random()>0.5 then
			table.insert(tbl_insert_x,choices[math.random(1,#choices)])
		else
			table.insert(tbl_insert_y,choices[math.random(1,#choices)])
		end
	end
	--]]
	--[[ direct stuff
		table.insert(tbl_insert_x,"s.x")
		table.insert(tbl_insert_x,"p.x")
		table.insert(tbl_insert_y,"s.y")
		table.insert(tbl_insert_y,"p.y")
	--]]
	-- [[ direct params
		table.insert(tbl_insert_x,"params.x")
		table.insert(tbl_insert_x,"params.z")
		table.insert(tbl_insert_y,"params.y")
		table.insert(tbl_insert_y,"params.w")
	--]]
	--[[ flipped stuff
		table.insert(tbl_insert_x,"s.y")
		table.insert(tbl_insert_x,"p.y")
		table.insert(tbl_insert_y,"s.x")
		table.insert(tbl_insert_y,"p.x")
	--]]
	--[[ flipped params
		table.insert(tbl_insert_x,"params.y")
		table.insert(tbl_insert_x,"params.w")
		table.insert(tbl_insert_y,"params.x")
		table.insert(tbl_insert_y,"params.z")
	--]]
	--[[ global seed stuff
		table.insert(tbl_insert_x,"mix(s.x,s.y,global_seeds.x)")
		table.insert(tbl_insert_x,"mix(p.x,p.y,global_seeds.x)")
		table.insert(tbl_insert_y,"mix(s.x,s.y,1-global_seeds.x)")
		table.insert(tbl_insert_y,"mix(p.x,p.y,1-global_seeds.x)")
	--]]
	-- [[ global seed stuff2
		table.insert(tbl_insert_x,"mix(s.y*s.y,s.x*s.x,global_seeds.x)")
		table.insert(tbl_insert_x,"mix(p.y*p.y,p.x*p.x,global_seeds.x)")
		--table.insert(tbl_insert_y,"mix(s.y,s.y*s.y,1-global_seeds.x)")
		--table.insert(tbl_insert_y,"mix(p.y,p.y*p.y,1-global_seeds.x)")
	--]]
	--[[ global seed params
		table.insert(tbl_insert_x,"mix(params.x,params.y,global_seeds.x)")
		table.insert(tbl_insert_y,"mix(params.x,params.y,global_seeds.x)")
		table.insert(tbl_insert_x,"mix(params.z,params.w,global_seeds.x)")
		table.insert(tbl_insert_y,"mix(params.z,params.w,global_seeds.x)")
	--]]
	--[[
	local tbl_insert_x={"s.x+cos(global_seeds.x*M_PI*2)","p.y+params.x","params.x","params.y"}
	local tbl_insert_y={"s.y+sin(global_seeds.x*M_PI*2)","p.x+params.y","params.z","params.w"}
	]]--

	--local tbl_insert={"s","p","mix(s*params.xy,s*params.zw,global_seeds.x)","mix(p*params.zw,p*params.xy,global_seeds.x)"}
	--[[
	local point_count=3
	for i=1,point_count do
		local v=(i-1)/point_count
		local vr=v*math.pi*2
		local r=0.1
		table.insert(tbl_insert_cmplx,string.format("vec2(%g,%g)",math.cos(vr)*r,math.sin(vr)*r))
	end
	--]]
	
	--[=[
	local tex_variants_real={
		-- [[
		"tex_p.x","tex_p.y","tex_p.z",
		"tex_s.x","tex_s.y","tex_s.z",

		--]]
		"atan(tex_s.y,tex_s.x)/M_PI","atan(tex_p.y,tex_p.x)/M_PI",
		"atan(tex_s.x,tex_s.z)/M_PI","atan(tex_p.x,tex_p.z)/M_PI"
	}
	local num_tex=2
	for i=1,num_tex do
		table.insert(tbl_insert_x,tex_variants_real[math.random(1,#tex_variants_real)])
		table.insert(tbl_insert_y,tex_variants_real[math.random(1,#tex_variants_real)])
	end
	--]=]
	return tbl_insert_x,tbl_insert_y
end
function new_ast_tree()
	ast_tree= ast_node(normal_symbols_complex,terminal_symbols_complex)
	ast_tree.forced=get_forced_insert_complex()
	ast_tree.random_forced=true
	print(ast_tree:to_string())
end
function ast_mutate(  )
	ast_tree:mutate()
	print(ast_tree:to_string())
end
function ast_trim(  )
	ast_tree:trim()
	print(ast_tree:to_string())
end
function ast_terminate( reterm )
	if reterm then
		ast_tree.forced=get_forced_insert_complex()
		ast_tree:clear_terminal()
	end
	ast_tree:terminate_all(ast_tree.forced)

	str_cmplx=ast_tree:to_string()
	print(str_cmplx)
	str_preamble=""
	str_postamble=""
	--str_preamble=str_preamble.."p=mod(p+move_dist/2,move_dist)-move_dist/2;"
	--[[ centered-polar
	str_preamble=str_preamble.."s=to_polar(s-p);"
	str_postamble=str_postamble.."s=from_polar(s)+p;"
	--]]
	--[[ polar gravity
	--str_preamble=str_preamble.."vec2 np=s;float npl=abs(sqrt(dot(np,np))-0.5)+1;npl*=npl;"
	--str_preamble=str_preamble.."vec2 np=p;float npl=abs(sqrt(dot(np,np))-0.5)+1;npl*=npl;"
	--str_preamble=str_preamble.."vec2 np=tex_s.yz;float npl=abs(sqrt(dot(np,np)))+0.5;npl*=npl;"
	str_preamble=str_preamble.."vec2 np=c_mul(p-s,last_s);float npl=abs(sqrt(dot(np,np))-0.5)+1;npl*=npl;"
	--str_preamble=str_preamble.."float ang_xx=atan(last_s.y,last_s.x);vec2 np=s-p*vec2(cos(ang_xx),sin(ang_xx))/length(p);float npl=cos((sqrt(dot(np,np))-0.5)*M_PI*2)*0.5+1.25;npl*=npl;"
	--str_postamble=str_postamble.."float ls=length(s);s*=1-atan(ls*move_dist)/(M_PI/2);"
	--str_postamble=str_postamble.."float ls=length(s);s*=1-atan(ls*move_dist)/(M_PI/2)*move_dist;"
	--str_postamble=str_postamble.."float ls=length(s-vec2(1,1));s=s*(1-atan(ls*move_dist)/(M_PI/2)*move_dist)+vec2(1,1);"
	--str_postamble=str_postamble.."float ls=length(s);s*=(1+sin(ls*move_dist))/2*move_dist;"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);s=last_s+ds*(move_dist/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=1-atan(ls*move_dist)/(M_PI/2);s=last_s+ds*(move_dist*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=1-atan(ls*(global_seeds.x*8))/(M_PI/2);s=last_s+ds*((global_seeds.x*7)*vv/ls);"
	str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-1/dot(s,s));s=last_s+ds*(move_dist*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-1/npl);s=last_s+ds*(move_dist*vv/ls);"
	--]]
	--[[ const-delta-like
	str_preamble=str_preamble.."vec2 os=s;"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist*exp(1/-dot(p,p));"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*exp(-dot(p,p)/move_dist);"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*dot(tex_s,tex_s)/move_dist;"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist;"
	--str_postamble=str_postamble.."s/=length(s);s=os+c_mul(s,vec2(params.zw));"
	str_postamble=str_postamble.."s/=length(s);s=os+c_mul(s,vec2(params.zw)*floor(global_seeds.x*move_dist+1)/move_dist);"
	--]]
	-- [[ symmetry

	str_preamble=str_preamble.."float pry=(floor(prand.y*9)/8);vec2 ppr=(1-step(pry,0))*vec2(round(cos(pry*M_PI*2)),round(sin(pry*M_PI*2)));"
	--str_preamble=str_preamble.."s=rotate(mod(rotate(s,M_PI/4)+0.5,1)-0.5+ppr,-M_PI/4);"
	str_preamble=str_preamble.."s=mod(rotate(s,-pry*M_PI*2)+0.5,1)-0.5+ppr;"
	--str_preamble=str_preamble.."s=from_barycentric(mod_barycentric(to_barycentric(s).xy+0.5)-0.5);"
	--str_postamble=str_postamble.."float pry=(floor(prand.y*4)/3);vec2 ppr=(1-step(pry,0))*vec2(cos(pry*M_PI*2),sin(pry*M_PI*2));"
	--str_postamble=str_postamble.."s=s+ppr;"
	--str_preamble=str_preamble.."float pry=(floor(prand.y*9)/8);vec2 ppr=(1-step(pry,0))*vec2(round(cos(pry*M_PI*2)),round(sin(pry*M_PI*2)));"
	--str_preamble=str_preamble.."s=rotate(mod(rotate(s,M_PI/4)+0.5,1)-0.5+ppr,-M_PI/4);"
	--]]
	-- [[ ORBIFY!
	--Idea: project to circle inside with sigmoid like func
	local circle_radius=1
	str_preamble=str_preamble..string.format("float DC=length(s)-%g;",circle_radius)
	-- [==[
	str_preamble=str_preamble.."vec2 VC=-normalize(s);"
	str_preamble=str_preamble..string.format("s+=step(0,DC)*VC*(DC+%g*2*(sigmoid(DC*move_dist)));",circle_radius)
	--str_postamble=str_postamble..string.format("s=(1-step(0,DC))*s+step(0,DC)*(%g)*rotate(VC,M_PI*move_dist*global_seeds.x)*sigmoid(DC*global_seeds.x);",circle_radius)
	--]==]
	--[==[
	local angle=2*math.pi/3
	str_postamble=str_postamble..string.format("vec2 m=-normalize(s)*%g;",circle_radius)
	--str_postamble=str_postamble..string.format("vec2 n=rotate(m,%g);",angle)
	str_postamble=str_postamble..string.format("vec2 n=rotate(m,M_PI*global_seeds.x);",angle)
	--str_postamble=str_postamble.."vec2 n=rotate(m,M_PI*(sigmoid(length(p))+1)/2);"
	--str_postamble=str_postamble.."vec2 n=rotate(m,M_PI*normed_iter);"
	str_postamble=str_postamble.."s=(1-step(0,DC))*s+step(0,DC)*mix(m,n,(sigmoid(DC*move_dist)+1)/2);"
	--str_postamble=str_postamble.."s=mix(m,n,sigmoid(DC*move_dist));"
	--]==]
	--]]
	print("==============")
	print(other_code)
	print(str_preamble)
	print(str_cmplx)
	print(str_postamble)

	make_visit_shader(true)
	need_clear=true
end
function rand_function(  )
	local s=random_math(rand_complexity)
	
	local tbl_insert_cmplx=get_forced_insert_complex()
	local tbl_insert_x,tbl_insert_y=get_forced_insert()
	--]==]
	--chebyshev_poly_series(10)
	--str_cmplx=random_math_complex(rand_complexity,nil,tbl_insert)
	--str_cmplx="(s/length(s)+p/length(p))*(0.5+global_seeds.x)"
	str_cmplx=random_math_complex(rand_complexity,nil,tbl_insert_cmplx)

	--str_cmplx=random_math_complex(15,"cheb_eval(R)",tbl_insert)
	--str_cmplx=random_math_complex(15,"c_mul(cheb_eval(c_mul(vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2)),(s-p))),R)",tbl_insert)
	--str_cmplx=newton_fractal(rand_complexity)
	--str_cmplx=random_math_complex_const(rand_complexity,nil,{"s","p*vec2(move_dist,global_seeds.x)","params.xy","params.zw"})
	--str_cmplx=random_math_complex_intervals(rand_complexity,2,nil,{"s","c_mul(p,vec2(move_dist,global_seeds.x))","params.xy","params.zw"})
	--str_cmplx=random_math_complex_intervals(rand_complexity,15,"(R)/2+(R)*c_sin(vec2(2*M_PI,1)*(R)+R)")
	--str_cmplx=random_math_fourier_complex(7,rand_complexity)
	--str_cmplx=random_math_complex_series(4,random_math_complex_intervals(rand_complexity,5))
	--str_cmplx="c_inv(((s)-((c_cos((vec2(global_seeds.x,0))+(s)))-(c_asin(s))))-(c_conj(c_cos(c_inv(s)))))"
	--str_cmplx="c_inv((s-c_cos(vec2(global_seeds.x,0)+s)+c_asin(s+params.xy))-c_conj(c_mul(c_cos(c_inv(s)),params.zw)))"
	--str_cmplx="c_cos(c_inv(s-params.zw+p*vec2(move_dist,global_seeds.x)))-params.xy"
	--str_cmplx=random_math_complex(rand_complexity,nil,{"c_pow(s,vec2(1,global_seeds.x*2))"})
	--str_cmplx=random_math_complex_intervals(rand_complexity,10)
	--str_cmplx="c_mul(params.xy,c_inv(c_mul(c_conj(c_cos(s)),p*vec2(move_dist,global_seeds.x)+params.zw)))"
	--str_cmplx=str_cmplx.."*value_inside(global_seeds.x,0,0.5)+(s-(s*move_dist)/length(s))*value_inside(global_seeds.x,0.5,1)+(s*floor(global_seeds.x*5)/5)/length(s)"
	--str_cmplx="c_tan(c_cos(c_tan((((params.xy)-(s))-(c_cos(c_mul(c_atan(params.zw),c_tan((params.zw)+(params.xy))))))-(p*vec2(move_dist*(1-global_seeds.x*global_seeds.x),global_seeds.x)))))"

	--str_x=random_math_intervals(true,rand_complexity,6,nil,{"s.x","p.y","params.x","params.y"})
	--str_y=random_math_intervals(false,rand_complexity,6,nil,{"s.y","p.x","params.z","params.w"})

	--str_cmplx="c_mul(s,s)+from_polar(to_polar(p)+vec2(0,prand.x*move_dist*M_PI*2))"
	--str_cmplx="c_cos(s+params.xy)+p*prand.x+c_mul(s,s)*(1-prand.x)"
	--str_cmplx=random_math_complex(rand_complexity,"c_mul(R,last_s/length(last_s)+c_one())")
	--local FT=random_math_complex(rand_complexity)
	--[[
	--str_cmplx="c_mul(c_div((c_div(s,c_cos((params.xy)-(s))))-(s),(c_div((c_conj(s))+(c_div(p,c_cos(p))),((s)-(s))+(c_atan((params.xy)-(p)))))-(c_conj(p))),c_tan(((c_div((s)+(p),(s)+(params.xy)))-((p)+(c_conj(s))))-(p)))"
	--str_cmplx="c_conj(c_tan(((p)+(c_conj((s)-(c_conj((p)+(p))))))+((((c_inv(c_inv(s)))-(c_conj(s)))-(c_sin((c_mul(c_sin((params.zw)+(p)),p))+(s))))-(((s)+(s))+((p)+(((c_div(p,p))+(s))+(s)))))))"
	--]]

	--[[ nice tri-lobed shape
		--str_cmplx="c_div(c_conj(p),(s)-(p))"
		str_cmplx="c_div(c_conj(p),(s)-c_mul(p,vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2))))"
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
	--str_cmplx="c_conj(c_cos(s+vec2(prand.x*M_PI*2,0))-c_mul(p,params.xy))"
	--str_cmplx="c_conj(c_cos(s*(0.5+prand.x))-c_mul(p,params.xy))"
	--mandelbrot?
	--str_cmplx="c_mul(s,s)+p"

	--str_cmplx="c_mul(vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2)),c_mul(s,s))+p"
	--str_cmplx="vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2))*move_dist+c_mul(s,s)+p"
	--str_cmplx="mix(c_mul(s,s),c_mul(s,c_mul(s,s)),prand.x)+p+vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2))*move_dist"
	--str_cmplx="vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2))*move_dist+c_mul(s,s)+p"
	--tr_cmplx="c_mul(s,s)+c_mul(vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2)),params.xy)"
	--str_cmplx="c_mul(c_mul(vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2)),s),s)+p"

	--str_cmplx="vec2(0)"
	--[==[
	str_cmplx="c_mul(s,s)"
	local num_copies=10
	for i=1,num_copies do
		local v=((i-1)/num_copies)
		local v2=((i)/num_copies)
		local a=v*math.pi*2
		local vv=-1
		if i%2==0 then
			vv=1
		end
		--str_cmplx=str_cmplx..string.format("+c_mul(vec2(%g,%g)*(1+global_seeds.x),c_mul(s,s)+p)",math.cos(a),math.sin(a))
		str_cmplx=str_cmplx..string.format("+value_inside(global_seeds.x,%g,%g)*c_mul(vec2(cos(%g),sin(%g)),p)",v,v2,a,a)
	end
	--]==]
	--[==[
	str_cmplx="p"
	local num_copies=10
	for i=1,num_copies do
		local v=((i-1)/num_copies)
		local v2=((i)/num_copies)
		local a=v*math.pi*2
		local vv=-1
		if i%2==0 then
			vv=1
		end
		--str_cmplx=str_cmplx..string.format("+c_mul(vec2(%g,%g),c_mul(s,s))",math.cos(a),math.sin(a))
		--str_cmplx=str_cmplx..string.format("+value_inside(global_seeds.x,%g,%g)*c_mul(vec2(cos(%g),sin(%g)),c_mul(s,s))",v,v2,a,a)
		str_cmplx=str_cmplx..string.format("+c_mul(vec2(cos(%g+global_seeds.x*M_PI*2),sin(%g+global_seeds.x*M_PI*2)),c_mul(s,s))",v,v2,a,a)
	end
	--]==]
		--[=[
	--[=[
	str_cmplx="c_mul(s,s)+p"
	--str_cmplx="c_mul(s,s)*value_inside(global_seeds.x,0,0.5)+c_mul(s,c_mul(s,s))*value_inside(global_seeds.x,0.5,1)+p"
	--str_cmplx="mix(c_mul(s,s)+p,c_mul(c_mul(s,s)+p,vec2(cos(2*M_PI*global_seeds.x),sin(2*M_PI*global_seeds.x))),tex_p.y)"
	--str_cmplx="c_mul(s*(tex_p.y+0.5),s*(tex_s.y+0.5))+p*(global_seeds.x+0.5)"
	--str_cmplx="c_mul(s,s)+p*(global_seeds.x+0.5)"
	--str_cmplx="c_mul(s*global_seeds.x,s*(1-global_seeds.x))+p"
	--str_cmplx="vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2))*c_mul(s,s)+c_mul(p,params.zw)"
	--spiral brot
	--str_cmplx="c_mul(vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2)),c_mul(s,s))+c_mul(p,params.zw)"

	--str_cmplx="c_mul(s,s)+c_mul(p,vec2(cos((global_seeds.x-0.5)*0.1),sin((global_seeds.x-0.5)*0.1)))"
	--str_cmplx="c_mul(s,s)+p"
	--[[str_cmplx=[[
	c_mul(
		c_mul(s,s),
		vec2(
				cos((global_seeds.x-0.5)*0.1),sin((global_seeds.x-0.5)*0.1)
			)
		)+p]]

	--]]
	--]=]

	--[[ julia
	--str_cmplx="c_mul(s,s)+params.xy"
	str_cmplx="c_mul(s,s)+c_mul(params.xy,vec2(cos(global_seeds.x*2*M_PI),sin(global_seeds.x*2*M_PI)))"
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
	str_x=random_math(rand_complexity,nil,tbl_insert_x)
	str_y=random_math(rand_complexity,nil,tbl_insert_y)

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
	--[[
	str_preamble=str_preamble.."vec2 last_s=s;"
	str_postamble=str_postamble.."s=mix(last_s,s,global_seeds.x);"
	--]]

	--[[

	--str_preamble=str_preamble.."p=p*0.8+vec2(cos(global_seeds.x*M_PI*2)*p.x-sin(global_seeds.x*M_PI*2)*p.y,cos(global_seeds.x*M_PI*2)*p.y+sin(global_seeds.x*M_PI*2)*p.x)*.2;"
	str_preamble=str_preamble.."s=s*0.0+vec2(cos(global_seeds.x*M_PI*2)*s.x-sin(global_seeds.x*M_PI*2)*s.y,cos(global_seeds.x*M_PI*2)*s.y+sin(global_seeds.x*M_PI*2)*s.x)*0.6;"
	--]]
	--str_preamble=str_preamble.."p=mod(p+move_dist/2,move_dist)-move_dist/2;"
	--str_preamble=str_preamble.."p=floor(p*move_dist)/move_dist;"
	--[[ gravity
	str_preamble=str_preamble.."s*=1/move_dist;"
	--]]
	--[[ weight1
	--str_postamble=str_postamble.."float ll=length(s);s/=weight1;weight1*=1/ll;"
	--str_postamble=str_postamble.."float ll=length(s);s*=weight1;weight1=min(weight1,1/ll);"
	str_postamble=str_postamble.."float ll=length(s);s/=weight1;weight1=max(weight1,ll);"
	--str_postamble=str_postamble.."float ll=length(s);s/=weight1;weight1+=ll;"
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
		input_s=input_s..string.format("+c_mul(%s,vec2(cos(prand.x*M_PI*2),sin(prand.x*M_PI*2))*move_dist)",sub_s)
		--input_s=input_s..string.format("+%s*c_mul(%s,vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2)))",sub_s,tex_variants[math.random(1,#tex_variants)])
		local v_start=(i-1)/series_size
		local v_end=i/series_size
		--input_s=input_s..string.format("+%s*vec2(%.3f,%.3f)*value_inside(global_seeds.x,%g,%g)",sub_s,rand_offset+math.random()*rand_size-rand_size/2,rand_offset+math.random()*rand_size-rand_size/2,v_start,v_end)

		local dx=math.cos((i/series_size)*math.pi*2)
		local dy=math.sin((i/series_size)*math.pi*2)
		--input_s=input_s..string.format("+%s*vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2))",sub_s)
	end
	str_postamble=str_postamble.."s=s"..input_s..";"
	--]]
	--[===[ ORBIFY!
	--Idea: project to circle inside with sigmoid like func
	local circle_radius=1
	local fixed_move_dist=0.6
	str_postamble=str_postamble..string.format("float DC=length(s)-%g;",circle_radius)
	-- [==[
	str_postamble=str_postamble.."vec2 VC=-normalize(s);"
	str_postamble=str_postamble..string.format("s+=step(0,DC)*VC*(DC+%g*2*(sigmoid(DC*%g)));",circle_radius,fixed_move_dist)
	--str_postamble=str_postamble..string.format("s=(1-step(0,DC))*s+step(0,DC)*(%g)*rotate(VC,M_PI*move_dist*global_seeds.x)*sigmoid(DC*global_seeds.x);",circle_radius)
	--]==]
	--]===]
	--[==[ polar gravity
	str_preamble=str_preamble.."vec2 np=s;float npl=abs(sqrt(dot(np,np))-0.5)+1;npl*=npl;"
	--str_preamble=str_preamble.."vec2 np=p;float npl=abs(sqrt(dot(np,np))-0.5)+1;npl*=npl;"
	--str_preamble=str_preamble.."vec2 np=tex_s.yz;float npl=abs(sqrt(dot(np,np)))+0.5;npl*=npl;"
	--str_preamble=str_preamble.."vec2 np=c_mul(p-s,last_s);float npl=abs(sqrt(dot(np,np))-0.5)+1;npl*=npl;"
	--str_preamble=str_preamble.."float ang_xx=atan(last_s.y,last_s.x);vec2 np=s-p*vec2(cos(ang_xx),sin(ang_xx))/length(p);float npl=cos((sqrt(dot(np,np))-0.5)*M_PI*2)*0.5+1.25;npl*=npl;"
	--str_postamble=str_postamble.."float ls=length(s);s*=1-atan(ls*move_dist)/(M_PI/2);"
	--str_postamble=str_postamble.."float ls=length(s);s*=1-atan(ls*move_dist)/(M_PI/2)*move_dist;"
	--str_postamble=str_postamble.."float ls=length(s-vec2(1,1));s=s*(1-atan(ls*move_dist)/(M_PI/2)*move_dist)+vec2(1,1);"
	--str_postamble=str_postamble.."float ls=length(s);s*=(1+sin(ls*move_dist))/2*move_dist;"
	str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);s=last_s+ds*(move_dist/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);s=last_s+ds*(move_dist/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);s=last_s+(ds/ls)*(prand.x-0.5)*move_dist;"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=1-atan(ls*move_dist)/(M_PI/2);s=last_s+ds*(move_dist*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=1-atan(ls*(global_seeds.x*8))/(M_PI/2);s=last_s+ds*((global_seeds.x*7)*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-dot(s,s)/global_seeds.x);s=last_s+ds*(move_dist*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-tex_p.y/npl);s=last_s+c_mul(ds,global_seeds.x_vec)*(vv/(ls*move_dist));"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-tex_p.y/npl);s=last_s+c_mul(ds,prand.xx)*(vv*(1-normed_iter)/(ls*move_dist));"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-tex_p.y/npl);s=last_s+ds*(vv/(ls*move_dist));"
	--]==]
	--[[ move towards circle
	str_postamble=str_postamble.."vec2 tow_c=s+vec2(cos(normed_iter*M_PI*2),sin(normed_iter*M_PI*2))*move_dist;s=(dot(tow_c,s)*tow_c/length(tow_c));"
	--]]
	--[[ rand scale/offset

	local r1=math.random()*2-1
	local r2=math.random()*2-1
	local l=math.sqrt(r1*r1+r2*r2)
	r1=r1/l
	r2=r2/l
	local r3=math.random()*2-1
	local r4=math.random()*2-1
	local l2=math.sqrt(r3*r3+r4*r4)
	r3=r3/l2
	r4=r4/l2
	local r5=math.random()*2-1
	local r6=math.random()*2-1
	local l3=math.sqrt(r5*r5+r6*r6)
	r5=r5/l3
	r6=r6/l3
	--str_preamble=str_preamble..("s=mix(s,vec2(dot(s,vec2(%.3f,%.3f)),dot(s,vec2(%.3f,%.3f)))+vec2(%.3f,%.3f),prand.x*move_dist);"):format(r1,r2,r3,r4,r5,r6)
	--str_preamble=str_preamble..("s=mix(s,vec2(dot(s,vec2(%.3f,%.3f)),dot(s,vec2(%.3f,%.3f)))+vec2(%.3f,%.3f),1-normed_iter);"):format(r1,r2,r3,r4,r5,r6)
	--str_preamble=str_preamble..("s=vec2(dot(s,vec2(%.3f,%.3f)),dot(s,vec2(%.3f,%.3f)))+vec2(%.3f,%.3f);"):format(r1,r2,r3,r4,r5,r6)
	--str_preamble=str_preamble..("s=s*vec2(%.3f,%.3f)+vec2(%.3f,%.3f);"):format(r1,r2,r5,r6)
	
	--str_preamble=str_preamble..("s=mix(s,s*vec2(%.3f,%.3f)+vec2(%.3f,%.3f),prand.x*move_dist);"):format(r1,r2,r5,r6)
	--str_postamble=str_postamble..("s=(s-vec2(%.3f,%.3f))*vec2(%.3f,%.3f);"):format(r5,r6,1/r1,1/r2)
	--TODO Revert the preamble transform str_postamble=str_postamble..("s=vec2(dot(s,vec2(%.3f,%.3f)),dot(s,vec2(%.3f,%.3f)))+vec2(%.3f,%.3f);"):format(r1/l,r2/l,r3/l2,r4/l2,r5,r6)
	--str_preamble=str_preamble..("s=s+vec2(%.4f,%.4f);"):format(r5,r6)
	--str_postamble=str_postamble..("s=s-vec2(%.4f,%.4f);"):format(r5,r6)
	--str_preamble=str_preamble..("s=s+vec2(%.4f,%.4f)*(tex_s.x+(prand.x-0.5)*0.05);"):format(r5,r6)
	--str_postamble=str_postamble..("s=s-vec2(%.4f,%.4f)*(tex_s.x+(prand.x-0.5)*0.05);"):format(r5,r6)
	str_preamble=str_preamble..("s=rotate(s,%.4f*M_PI*(tex_s.x+(prand.x-0.5)*0.05));"):format(math.random()*2-1)
	str_postamble=str_postamble..("s=rotate(s,(-1)*%.4f*M_PI*(tex_s.x+(prand.x-0.5)*0.05));"):format(math.random()*2-1)
	

	--]]
	--[[ const-delta-like
	str_preamble=str_preamble.."vec2 os=s;"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist*exp(1/-dot(p,p));"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*exp(-dot(p,p)/(1+global_seeds.x));"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*exp(-dot(p,p)/(1+prand.x));"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*dot(tex_s,tex_s)/(move_dist*cos(global_seeds.x*M_PI*2));"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist;"
	str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist*prand.x;"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist*(max(abs(tex_s.x-tex_p.x),abs(tex_s.y-tex_p.y))+0.5);"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist*(length(tex_s.xy));"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist*(length(tex_p.xy));"
	--str_postamble=str_postamble.."s/=length(s);s=os+c_mul(s,vec2(params.zw));"
	--str_postamble=str_postamble.."s/=length(s);s=os+c_mul(s,vec2(params.zw)*floor(global_seeds.x*move_dist+1)/move_dist);"
	--str_postamble=str_postamble.."s/=length(s);s=os+rotate(s,(prand.x-0.5)*M_PI*2)*move_dist;"
	--str_postamble=str_postamble.."s/=length(s);s=os+rotate(s,(prand.x-0.5)*M_PI*2*move_dist)*move_dist;"
	--str_postamble=str_postamble.."s/=length(s);s=rotate(rotate(os,(prand.x-0.5)*M_PI*2)+s*move_dist,-(prand.x-0.5)*M_PI*2);"
	--str_postamble=str_postamble.."s/=length(s);s=os+rotate(s,(prand.y-0.5)*M_PI*2*move_dist)*(prand.x-0.5)*move_dist;"
	--]]
	--[[ const-delta-like complex
	str_preamble=str_preamble.."vec2 os=s;"
	--str_postamble=str_postamble.."s=c_div(s,os)*move_dist;"
	str_postamble=str_postamble.."s=c_div(s,os)*(max(abs(tex_s.x-tex_p.x),abs(tex_s.y-tex_p.y))+0.5);"
	--]]
	--[[ normed-like
	str_preamble=str_preamble.."float l=length(s);"
	str_postamble=str_postamble.."s/=l;s*=move_dist;"
	--]]
	--[[ normed-like2
	str_preamble=str_preamble..""
	str_postamble=str_postamble.."s/=length(s);s*=move_dist;s+=p;"
	--]]
	--[[ mod triangle
	str_postamble=str_postamble.."s"
	--]]
	--[[ SU(2)
	local r1,r2=gaussian2(0,1,0,1)
	local r3,r4=gaussian2(0,1,0,1)
	local r=math.sqrt(r1*r1+r2*r2+r3*r3+r4*r4)
	r1=r1/r
	r2=r2/r
	r3=r3/r
	r4=r4/r
	--[[
	str_preamble=str_preamble..string.format("vec2 s2=c_one();su2_mat_mult(s,s2,vec2(%.3f,%.3f),vec2(%.3f,%.3f));",r1,r2,r3,r4)
	str_postamble=str_postamble..string.format("su2_mat_mult(s,s2,vec2(%.3f,%.3f),vec2(%.3f,%.3f));",r1,-r2,-r3,-r4)
	--]]
	--str_postamble=str_postamble..string.format("vec2 sM=s;vec2 sM2=c_one();su2_mat_mult(sM,sM2,vec2(%.3f,%.3f),vec2(%.3f,%.3f));s-=(s-sM)*move_dist;",r1,r2,r3,r4)
	--str_postamble=str_postamble..string.format("vec2 al=vec2(%.3f,%.3f);vec2 be=vec2(%.3f,%.3f);s=c_div(c_mul(s,al)-c_conj(be),c_mul(s,be)+c_conj(al));",r1,r2,r3,r4)
	--str_postamble=str_postamble..string.format("vec2 al=global_seeds.xy;vec2 be=tex_s.xy;float ral=sqrt(dot(al,al)+dot(be,be)+0.1);al/=ral;be/=ral;s=c_div(c_mul(s,al)-c_conj(be),c_mul(s,be)+c_conj(al));")
	--str_postamble=str_postamble..string.format("vec2 al=global_seeds.xy;vec2 be=prand.xy;s=c_div(c_mul(s,al)-c_conj(be),c_mul(s,be)+c_conj(al));")
	--]]
	-- [[ symmetry

	--str_postamble=str_postamble.."float pry=(floor(prand.y*4)/3);vec2 ppr=(1-step(pry,0))*vec2(round(cos(pry*M_PI*2)),round(sin(pry*M_PI*2)));"
	str_postamble=str_postamble.."float pry=(floor(prand.y*4)/3);vec2 ppr=(1-step(pry,0))*vec2(cos(pry*M_PI*2),sin(pry*M_PI*2))*2;"
	--str_postamble=str_postamble.."s=rotate(mod(rotate(s,M_PI/4)+0.5,1)-0.5+ppr,-M_PI/4);"
	str_postamble=str_postamble.."s=from_barycentric(mod_barycentric(to_barycentric(s+p*prand.x).xy+0.5)-0.5)+ppr-p*prand.x;s=rotate(s,M_PI/3);"
	--str_postamble=str_postamble.."float pry=(floor(prand.y*4)/3);vec2 ppr=(1-step(pry,0))*vec2(cos(pry*M_PI*2),sin(pry*M_PI*2));"
	--str_postamble=str_postamble.."s=s+ppr;"
	--str_preamble=str_preamble.."float pry=(floor(prand.y*9)/8);vec2 ppr=(1-step(pry,0))*vec2(round(cos(pry*M_PI*2)),round(sin(pry*M_PI*2)));"
	--str_preamble=str_preamble.."s=rotate(mod(rotate(s,M_PI/4)+0.5,1)-0.5+ppr,-M_PI/4);"
	--]]
	--[[ mod
	--str_postamble=str_postamble.."s=mod(s+0.5,1)-0.5;"
	--str_postamble=str_postamble.."s=mod(s+0.5,max(abs(tex_s.x-tex_p.x),abs(tex_s.y-tex_p.y))*prand.x+1)-0.5;"
	--[=[str_postamble=str_postamble.."s=rotate(s,M_PI/4)+0.5;"
	str_postamble=str_postamble.."s=mod(s,1+(prand.x-0.5)*0.005)-0.5;"
	str_postamble=str_postamble.."s=rotate(s,M_PI/4)+0.5;"
	str_postamble=str_postamble.."s=mod(s,1+(prand.x-0.5)*0.005)-0.5;"
	str_postamble=str_postamble.."s=rotate(s,M_PI/2);"]=]
	--str_postamble=str_postamble.."s=rotate(mod(rotate(s,M_PI/4)+0.5,1)-0.5,-M_PI/4);"
	--str_postamble=str_postamble.."float ls=log(length(s)+1)/2;s=rotate(mod(rotate(s,M_PI/4)+ls,ls*2)-ls,-M_PI/4);"
	--str_postamble=str_postamble.."float ls=log(length(s)+1);s=mod(s+ls/2,1)-ls/2;"
	--str_postamble=str_postamble.."s=rotate(mod(rotate(s,M_PI/4)+0.5,1+(length(tex_p)*prand.x)*0.05)-0.5,-M_PI/4);"
	--str_postamble=str_postamble.."s=rotate(mod(rotate(s,M_PI/4)+0.5,1+(prand.x-0.5)*0.005)-0.5,-M_PI/4);"
	--str_postamble=str_postamble.."s=rotate(mod(rotate(s,M_PI/4)+0.5,(max(abs(tex_s.x-tex_p.x),abs(tex_s.y-tex_p.y)-1)*2+(prand.x)))-0.5,-M_PI/4);"
	--str_postamble=str_postamble.."vec2 ps=vec2(atan(s.y,s.x),length(s));ps.y=mod(ps.y,1+(prand.x-0.5)*0.005);s=vec2(cos(ps.x),sin(ps.x))*ps.y;"
	--str_postamble=str_postamble.."vec2 ps=vec2(atan(s.y,s.x),length(s));ps.y=mod(ps.y,1+(prand.x-0.5)*0.05)*2-1;s=vec2(cos(ps.x),sin(ps.x))*ps.y;"
	--str_postamble=str_postamble.."vec2 ps=vec2(atan(s.y,s.x),length(s));ps.y=mod(ps.y+1,2+(smoothstep(-1,1,prand.x-0.5)-0.5)*0.01)-1;s=vec2(cos(ps.x),sin(ps.x))*ps.y;"
	--str_postamble=str_postamble.."vec2 ps=vec2(atan(s.y,s.x),length(s));ps.y=mod(ps.y+1,2)-1;s=vec2(cos(ps.x),sin(ps.x))*ps.y;"
	--str_postamble=str_postamble.."vec2 ps=vec2(atan(s.y,s.x),length(s));ps.y=mod(ps.y+1,tex_s.x+1)-1;s=vec2(cos(ps.x),sin(ps.x))*ps.y;"
	--str_postamble=str_postamble.."vec2 ps=vec2(atan(s.y,s.x),length(s));ps.y=mod(ps.y+1,(max(abs(tex_s.x-tex_p.x),abs(tex_s.y-tex_p.y))+0.5*(prand.x)))-1;s=vec2(cos(ps.x),sin(ps.x))*ps.y;"
	--str_postamble=str_postamble.."vec2 ps1=vec2(atan(s.y,s.x),length(s));ps1.y=mod(ps1.y+1,2)-1;s=vec2(cos(ps1.x),sin(ps1.x))*ps1.y;"
	--]]

	--[[ boost
	str_preamble=str_preamble.."s*=move_dist;"
	--]]
	--[[ boost less with distance
	str_preamble=str_preamble.."s*=move_dist*exp(-1/dot(s,s));"
	--str_preamble=str_preamble.."s*=global_seeds.x*exp(-1/dot(s,s));"
	--]]
	--[[SINK!
	str_postamble=str_postamble.."p=p*(2-normed_iter);"
	--]]
	--[[ 4fold mirror
	str_postamble=str_postamble.."s=abs(s);"
	--]]
	--[[
	str_postamble=str_postamble.."s=mix(c_cos(s),c_sin(s),global_seeds.x);"
	--]]
	--[[ center PRE
	str_preamble=str_preamble.."s=s-p;"
	--]]
	--[[ cosify
	--str_preamble=str_preamble.."s=cos(s-p)*move_dist+p;"
	--str_preamble=str_preamble.."s=c_cos((s-p)*global_seeds.x)*move_dist+p;"
	str_preamble=str_preamble.."s=c_cos(s-p)*move_dist+p;"
	--]]
	--[[ tanify
	--str_preamble=str_preamble.."s=tan(s);"
	str_preamble=str_preamble.."s=c_tan(s);"
	--]]
	--[[ logitify PRE
	str_preamble=str_preamble.."s=log(abs(s));"
	--]]
	--[[ gaussination
	--str_postamble=str_postamble.."s=vec2(exp(1/(-s.x*s.x)),exp(1/(-s.y*s.y)));"
	--str_postamble=str_postamble.."s=s*vec2(exp(move_dist/(-p.x*p.x)),exp(move_dist/(-p.y*p.y)));"
	str_postamble=str_postamble.."s=vec2(exp(global_seeds.x/(-s.x*s.x)),exp(global_seeds.x/(-s.y*s.y)));"
	--]]
	--[[ invert-ination
	str_preamble=str_preamble.."s=c_inv(s);"--s=c_mul(s,vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2)));"
	str_postamble=str_postamble.."s=c_inv(s);"--s=c_mul(s,vec2(cos(-global_seeds.x*M_PI*2),sin(-global_seeds.x*M_PI*2)));"
	--]]
	--[[ Chebyshev polynomial
	str_preamble=str_preamble.."s=(move_dist+1)*acos(s+p);"
	str_postamble=str_postamble.."s=cos(s)-p;"
	--]]
	--[[ Chebyshev polynomial
	str_preamble=str_preamble.."s=(move_dist+1)*cos(s);"
	str_postamble=str_postamble.."s=acos(s);"
	--]]
	--[[ Chebyshev polynomial
	str_preamble=str_preamble.."s=floor(global_seeds.x*move_dist+1)*c_acos(s);"
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
	--[==[ mobius transform
	local mob_count=3
	local mob={}
	for i=1,8*mob_count do
		table.insert(mob,math.random()*2-1)
	end
	--params.xy=a params.zw=b, m1,m2=c,gvec=d
	-- [[
	for i=0,mob_count-1 do
		local cval=i/mob_count
		local nval=(i+1)/mob_count
		str_preamble=str_preamble..string.format("s=mix(s,mobius(vec2(%g,%g),vec2(%g,%g),vec2(%g,%g),vec2(%g,%g),s),value_inside(prand.x,%g,%g));",
			mob[i*8+1],mob[i*8+2],mob[i*8+3],mob[i*8+4],mob[i*8+5],mob[i*8+6],mob[i*8+7],mob[i*8+8],cval,nval)
	end
	--]]
	--riley recipe: https://github.com/timhutton/mobius-transforms/blob/gh-pages/dfs_recipes.html and Indra's Pearls, p. 258
	--str_preamble=str_preamble..string.format("s=mix(s,mobius(vec2(1,0),vec2(0,0),vec2(params.x,prand.x),vec2(1,0),s),value_inside(prand.y,0,0.5));")
	--str_preamble=str_preamble..string.format("s=mix(s,mobius(vec2(1,0),vec2(2,0),vec2(0,0),vec2(1,0),s),value_inside(prand.y,0.5,1));")
	--str_preamble=string.format("s=c_div(c_mul(params.xy,s)+params.zw,c_mul(vec2(%g,%g),s)+global_seed_vec*move_dist);",m1,m2)
	--str_preamble=string.format("s=c_div(c_mul(params.xy,s)+params.zw,c_mul(vec2(%g,%g),s)+vec2(%g,%g));",m1,m2,m3,m4)
	--str_postamble=string.format("s=c_div(c_mul(global_seed_vec,s)-params.zw,-c_mul(vec2(%g,%g),s)+params.xy);",m1,m2)
	--str_postamble="s=c_div(params.w*s-vec2(params.y,0),-params.z*s+vec2(params.x,0));"
	--]==]
	--[[ rotate
	--str_preamble=str_preamble.."s=vec2(cos(params.z)*s.x-sin(params.z)*s.y,cos(params.z)*s.y+sin(params.z)*s.x);"
	--str_preamble=str_preamble.."p=vec2(cos(params.z*M_PI*2)*p.x-sin(params.z*M_PI*2)*p.y,cos(params.z*M_PI*2)*p.y+sin(params.z*M_PI*2)*p.x);"
	--str_postamble=str_postamble.."p=vec2(cos(global_seeds.x*M_PI*2)*p.x-sin(global_seeds.x*M_PI*2)*p.y,cos(global_seeds.x*M_PI*2)*p.y+sin(global_seeds.x*M_PI*2)*p.x);"
	--str_postamble=str_postamble.."p=vec2(cos(prand.x*M_PI*2*move_dist)*s.x-sin(prand.x*M_PI*2*move_dist)*s.y,cos(prand.x*M_PI*2*move_dist)*s.y+sin(prand.x*M_PI*2*move_dist)*s.x);"
	str_postamble=str_postamble.."s=vec2(cos(prand.x*M_PI*2*move_dist)*s.x-sin(prand.x*M_PI*2*move_dist)*s.y,cos(prand.x*M_PI*2*move_dist)*s.y+sin(prand.x*M_PI*2*move_dist)*s.x);"
	--]]
	--[[ offset_complex
	--str_preamble=str_preamble.."s+=params.xy*floor(seed*move_dist+1)/move_dist;s=c_mul(s,params.zw);"
	str_preamble=str_preamble.."s+=vec2(0.125,-0.25);s=c_mul(s,vec2(global_seeds.x,floor(global_seeds.x*move_dist+1)/move_dist));"
	--]]
	--[[ unoffset_complex
	--str_postamble=str_postamble.."s=c_div(s,params.zw);s-=params.xy*floor(seed*move_dist+1)/move_dist;"
	str_postamble=str_postamble.."s=c_mul(s,c_inv(params.zw));s-=params.xy*floor(global_seeds.x*move_dist+1)/move_dist;"
	--]]
	--[[ rotate (p)
	--str_preamble=str_preamble.."s=vec2(cos(p.x)*s.x-sin(p.x)*s.y,cos(p.x)*s.y+sin(p.x)*s.x);"
	--str_preamble=str_preamble.."s=vec2(cos(p.y)*s.x-sin(p.y)*s.y,cos(p.y)*s.y+sin(p.y)*s.x);"
	str_preamble=str_preamble.."s=vec2(cos(normed_iter*M_PI*2)*s.x-sin(normed_iter*M_PI*2)*s.y,cos(normed_iter*M_PI*2)*s.y+sin(normed_iter*M_PI*2)*s.x);"
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
	str_postamble=str_postamble.."s=log(abs(s))*move_dist;"
	--]]
	--[[ exp post
	str_preamble=str_preamble.."s=exp(s);"
	--]]
	--[[ unrotate POST
	--str_postamble=str_postamble.."s=vec2(cos(-params.z)*s.x-sin(-params.z)*s.y,cos(-params.z)*s.y+sin(-params.z)*s.x);"
	--str_postamble=str_postamble.."s=vec2(cos(-0.7853981)*s.x-sin(-0.7853981)*s.y,cos(-0.7853981)*s.y+sin(-0.7853981)*s.x);"
	str_postamble=str_postamble.."p=vec2(cos(-params.z*M_PI*2)*p.x-sin(-params.z*M_PI*2)*p.y,cos(-params.z*M_PI*2)*p.y+sin(-params.z*M_PI*2)*p.x);"
	--str_postamble=str_postamble.."s=vec2(cos(-normed_iter*M_PI*2)*s.x-sin(-normed_iter*M_PI*2)*s.y,cos(-normed_iter*M_PI*2)*s.y+sin(-normed_iter*M_PI*2)*s.x);"
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
	-- [[noise
	--str_postamble=str_postamble.."s+=vec2(cos(prand.y*M_PI*2),sin(prand.y*M_PI*2))*(1-exp(-prand.x*prand.x*abs(s.x)))*move_dist;"
	--str_postamble=str_postamble.."s+=vec2(cos(prand.y*M_PI*2),sin(prand.y*M_PI*2))*(1-exp(-prand.x*prand.x))*move_dist;"
	--str_postamble=str_postamble.."s+=vec2(cos(prand.y*M_PI*2),sin(prand.y*M_PI*2))*prand.x*move_dist;"
	--]]
	--[[ clamp
	str_postamble=str_postamble.."s=clamp(s,vec2(-1),vec2(1));"
	--]]
	--[[ clamp len
	str_postamble=str_postamble.."s=s*(clamp(length(s),0,1)/length(s));"
	--]]
	--[[ clamp len log failed
	str_postamble=str_postamble.."float sll=length(s);"
	str_postamble=str_postamble.."s=s/(smoothstep(0.8,1,sll)*sll+(1-smoothstep(0.8,1,sll))*(1+log(sll)));"
	--]]
	--[[ clamp len log
	str_postamble=str_postamble.."float sll=length(s);"
	str_postamble=str_postamble.."s=s*((step(sll,1)*sll+(1-step(sll,1))*(1+log(sll)))/sll);"
	--]]
	--[[ clamp exp
	str_postamble=str_postamble.."float sll=length(s);float all=exp(move_dist);"
	str_postamble=str_postamble.."s=s*((step(sll,1)*sll+(1-step(sll,1))*(all*exp(-sll*move_dist)))/sll);"
	--]]
	--[[ clamp exp
	str_postamble=str_postamble.."float sll=length(s);float all=1/(0.001-move_dist*exp(-move_dist));float dll=1-all*(exp(-move_dist)+0.001);"
	str_postamble=str_postamble.."s=s*((step(sll,1)*sll+(1-step(sll,1))*(all*(exp(-move_dist*sll)+0.001*sll)+dll ))/sll);"
	--]]
	--[[ clamp 1/x
	str_postamble=str_postamble.."float sll=length(s);float all=move_dist-1;float cll=1-all-move_dist;"
	str_postamble=str_postamble.."s=s*((step(sll,1)*sll+(1-step(sll,1))*(all/sll+sll*move_dist+cll))/sll);"
	--]]
	--[[ force back?
	str_postamble=str_postamble.."float sll=length(s);"
	str_postamble=str_postamble.."s=s*((step(sll,1)*sll+(1-step(sll,1))*(sll*move_dist+(1-move_dist*1)))/sll);"
	--]]
	--[[ force back?
	str_postamble=str_postamble.."float sll=length(s);float bx=1-2*move_dist*1;float cx=1-move_dist*1*1-bx*1;"
	str_postamble=str_postamble.."s=s*((step(sll,1)*sll+(1-step(sll,1))*(move_dist*sll*sll+bx*sll+cx))/sll);"
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
local sim_thread
function find_bbox_img_buf()
	local min_val=5
	img_buf:read_frame()
	local bbox={img_buf.w-1,img_buf.h-1,0,0}

	for x=0,img_buf.w-1 do
	for y=0,img_buf.h-1 do
		local v=img_buf:get(x,y)
		local lv=(v.r+v.g+v.b)/3
		
		if lv>min_val then
			if bbox[1]>x then bbox[1]=x end
			if bbox[2]>y then bbox[2]=y end
			if bbox[3]<x then bbox[3]=x end
			if bbox[4]<y then bbox[4]=y end
		end
	end
	end
	print("BBOX:",bbox[1],bbox[2],bbox[3],bbox[4])
	return bbox
end
function find_bbox_tex( min_val )
	local bbox={visit_tex.w-1,visit_tex.h-1,0,0}

	for x=0,visit_tex.w-1 do
	for y=0,visit_tex.h-1 do
		local v=buf:get(x,y)
		local lv=math.log(v.g+1)
		--if math.random()>0.99 then
		--	print(lv,avg,x,y)
		--end
		if lv>min_val then
			if bbox[1]>x then bbox[1]=x end
			if bbox[2]>y then bbox[2]=y end
			if bbox[3]<x then bbox[3]=x end
			if bbox[4]<y then bbox[4]=y end
		end
	end
	end
	print("BBOX:",bbox[1],bbox[2],bbox[3],bbox[4])
	return bbox
end
function sim_zoom_center(  )
	local max_iter=100
	local max_zoom_iter=100
	local min_avg=1.5 --how much of avg to call non-empty-pixel
	local max_iter_save=1000
	--local border=math.floor(0.1*visit_tex.w)
	for mutate_iter=1,max_zoom_iter do
		ast_mutate()
		ast_terminate()
		config.scale=0.25
		need_clear=true
		for i=1,max_iter do
			if i==max_iter then
				count_visits=10000
			end
			coroutine.yield()
		end
		local tex=visit_tex.t
		local buf=visit_buf
		local _,_1,avg=find_min_max(tex,buf)

		tex:use(0,not_pixelated)
		buf:read_texture(tex)
		--local bbox=find_bbox_tex(min_avg*avg)
		local bbox=find_bbox_img_buf(min_avg*avg)
		print("BBOX:",bbox[1],bbox[2],bbox[3],bbox[4])

		local new_x=(bbox[1]+bbox[3])/2
		local new_y=(bbox[2]+bbox[4])/2

		new_x=(new_x/size[1]-0.5)*2
		new_y=(-new_y/size[2]+0.5)*2

		local new_scale=math.max(size[1]/(bbox[3]-bbox[1]),size[2]/(bbox[4]-bbox[2]))
		print(new_x,new_y,new_scale)
		config.scale=config.scale*new_scale
		config.cx=((-new_x)+config.cx)*new_scale
		config.cy=((new_y)+config.cy)*new_scale
		need_clear=true
		-- [[
		for k=1,max_iter_save do
			coroutine.yield()
		end
		need_save=true
		--]]
		print("Done, iter:",mutate_iter)
		coroutine.yield()
	end
	sim_thread=nil
end
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
		tick=0
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
	if config.use_ast then

		if imgui.Button("New function") then
			new_ast_tree()
		end
		imgui.SameLine()
		if imgui.Button("Mutate") then
			ast_mutate()
		end
		imgui.SameLine()
		if imgui.Button("Trim") then
			ast_trim()
		end
		imgui.SameLine()
		if imgui.Button("Reterminate") then
			ast_terminate(true)
		end
		imgui.SameLine()
		if imgui.Button("Terminate") then
			ast_terminate()
		end
	else

		rand_complexity=rand_complexity or 3
		if imgui.Button("Rand function") then
			rand_function()
		end
		imgui.SameLine()

		_,rand_complexity=imgui.SliderInt("Complexity",rand_complexity,1,15)
	end
	 if not sim_thread then
        if imgui.Button("Simulate") then
           sim_thread=coroutine.create(sim_zoom_center)
        end
    else
        if imgui.Button("Stop Simulate") then
            sim_thread=nil
        end
    end
    if imgui.Button("BBOX") then
    	find_bbox_img_buf()
    end
	if imgui.Button("Animate") then
		animate=true
		need_clear=true
		config.animation=0
	end
	imgui.SameLine()
	if imgui.Button("Update frame") then
		update_animation_values()
	end
	imgui.Text(string.format("Done: %d %d %s",(cur_visit_iter/config.IFS_steps)*100,(global_seed_id or 0),reset_stats or ""))
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

function escape_mode_str(  ) --BROKEN
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
#line 2801
//escape_mode_str
#define ESCAPE_MODE %s
layout(location = 0) in vec4 position;

layout(location = 1) in uvec4 rnd_data;

//out vec3 pos;
out vec4 point_out;

#define M_PI 3.1415926535897932384626433832795

uniform vec2 center;
uniform vec2 scale;
uniform int pix_size;
uniform vec4 global_seeds;
uniform float move_dist;
uniform vec4 params;
uniform float normed_iter;
uniform float gen_radius;

uniform sampler2D tex_img;

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
float sigmoid(float v)
{
#if 0
	float vv=clamp(v,-10000,10000);
	return vv/sqrt(1+vv*vv);
#else
	return atan(v*M_PI/2)*2/M_PI;
#endif
}
vec2 rotate(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	mat2 m = mat2(c, -s, s, c);
	return m * v;
}
vec4 get_rnd_floats(uvec4 p)
{
	return p/vec4(4294967295.0);
}
vec2 mobius(vec2 a, vec2 b, vec2 c, vec2 d, vec2 z)
{
	return c_div(c_mul(a,z)+b,c_mul(c,z)+d);
}
void su2_mat_mult(inout vec2 s,inout vec2 v,vec2 a,vec2 b)
{
	vec2 abar=c_conj(a);
	vec2 bbar=c_conj(b);
	vec2 s2=c_mul(s,a)-c_mul(v,bbar);
	vec2 v2=c_mul(s,b)+c_mul(v,abar);
	s=s2;
	v=v2;
}

vec3 Barycentric(vec2 p, vec2 a,vec2 b,vec2 c)
{
	vec2 v0=b-a;
	vec2 v1=c-a;
	vec2 v2=p-a;
    
    float d00 = dot(v0,v0);
    float d01 = dot(v0,v1);
    float d11 = dot(v1,v1);
    float d20 = dot(v2,v0);
    float d21 = dot(v2,v1);
    
    float denom = d00 * d11 - d01 * d01;
    float retx=(d11 * d20 - d01 * d21) / denom;
    float rety=(d00 * d21 - d01 * d20) / denom;
    float retz= 1.0 - retx - rety;
    return vec3(retx,rety,retz);
}
vec3 to_barycentric(vec2 p)
{
	float angle_offset=0;
	float a_d=M_PI*2/3.0;

	vec2 p1=vec2(cos(angle_offset),sin(angle_offset));
	vec2 p2=vec2(cos(a_d+angle_offset),sin(a_d+angle_offset));
	vec2 p3=vec2(cos(-a_d+angle_offset),sin(-a_d+angle_offset));

	return Barycentric(p,p1,p2,p3);
}
vec2 from_barycentric(vec2 p)
{
	float angle_offset=0;

	float a_d=M_PI*2/3.0;

	vec2 p1=vec2(cos(angle_offset),sin(angle_offset));
	vec2 p2=vec2(cos(a_d+angle_offset),sin(a_d+angle_offset));
	vec2 p3=vec2(cos(-a_d+angle_offset),sin(-a_d+angle_offset));

	float rx=p1.x*p.x+p2.x*p.y+p3.x*(1-p.x-p.y);
	float ry=p1.y*p.x+p2.y*p.y+p3.y*(1-p.x-p.y);
	return vec2(rx,ry);
}
//float mod(float x,float y) { return x-y*floor(x/y); }
vec2 mod_barycentric(vec2 p)
{
	p.x=mod(p.x,1);
	p.y=mod(p.y,1);
	if(p.x+p.y>1)
	{
		
		//p.y=0;
		float lx=p.x;
		p.x=p.y;
		p.y=lx;
		if(p.x>p.y)
			p.x=1-p.x;
		else
			p.y=1-p.y;

		//p.x-=above/2;
		//p.y-=above/2;
	}
	return p;
}
/*
function from_barycentric(px,py,pz)

	local angle_offset=0;
	local a_d=math.pi*2/3.0

	local p1x=math.cos(angle_offset)
	local p1y=math.sin(angle_offset)

	local p2x=math.cos(a_d+angle_offset)
	local p2y=math.sin(a_d+angle_offset)

	local p3x=math.cos(-a_d+angle_offset)
	local p3y=math.sin(-a_d+angle_offset)

	local rx=p1x*px+p2x*py+p3x*pz
	local ry=p1y*px+p2y*py+p3y*pz
	return rx,ry
end*/

//str_other_code
%s

vec3 func_actual(vec2 s,vec2 p)
{
	vec4 prand=get_rnd_floats(rnd_data);
#if 1
	vec2 normed_p=(p*scale*move_dist+vec2(1,1))/2;
	vec2 normed_s=(s*scale*move_dist+vec2(1,1))/2;
#else
	vec2 normed_p=(p*scale+vec2(1,1))/2;
	vec2 normed_s=(s*scale+vec2(1,1))/2;
#endif
	vec4 tex_p=texture(tex_img,normed_p);
	vec4 tex_s=texture(tex_img,normed_s);

	float tex_sl=length(tex_s);
	float tex_pl=length(tex_p);
#if 1
	tex_s=tex_s/(tex_sl+1);
	tex_p=tex_p/(tex_pl+1);
#endif
#if 0
	float lum_white=exp(move_dist);
	tex_s=(tex_s*(1 + tex_sl / lum_white)) / (tex_sl + 1);
	tex_p=(tex_p*(1 + tex_pl / lum_white)) / (tex_pl + 1);
#endif
	tex_sl/=(tex_sl+1);
	tex_pl/=(tex_pl+1);
	//tex_p*=move_dist;
	//tex_s*=move_dist;
	//tex_s=tex_s/(exp(-length(tex_s))+1);
	//tex_p=tex_p/(exp(-length(tex_p))+1);
	//tex_s=1/(exp(-tex_s)+1);
	//tex_p=1/(exp(-tex_p)+1);
	//init condition
	vec2 last_s=s;
	vec2 global_seed_vec=vec2(cos(global_seeds.x*M_PI*2),sin(global_seeds.x*M_PI*2));
	float e=1;
	%s
#if ESCAPE_MODE
			if(e>normed_iter && dot(s,s)>4)
				{
				e=normed_iter;
				//break;
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
	vec2 p=func(position.xy,start_pos).xy;
#if ESCAPE_MODE
    point_out.xy=position.xy;
    point_out.zw=position.zw;
#else
	//in add shader: pos.xy*scale+center
	//p=(mapping(p*scale+center)-center)/scale;
	point_out.xy=p;
	point_out.zw=position.zw;
#endif

}
]==],
--Args to format
	escape_mode_str(),
	str_other_code or "",
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
#line 3305
layout(location = 0) in vec4 pos;
layout(location = 1) in uvec4 rnd_data;

#define M_PI 3.1415926535897932384626433832795

out vec4 pos_f;
out vec4 rnd_f;

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
	//float aspect_ratio=scale.y/scale.x;
	//return tRotate(p,M_PI/2)*vec2(1,aspect_ratio);
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


		//* code for group p4
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
vec4 get_rnd_floats(uvec4 p)
{
	return p/vec4(4294967295.0);
}
void main()
{
	vec2 p=mapping(pos.xy*scale+center);
    rnd_f=get_rnd_floats(rnd_data);
    gl_Position.xyz = vec3(p,0);
    //gl_Position.xyz = vec3(rnd_f.x*2-1,rnd_f.y*2-1+pos.x*0.000001,0);
    gl_Position.w = 1.0;
    gl_PointSize=pix_size;
    pos_f=pos;
}
]==],
string.format(
[==[
#version 330
#line 2954
#define M_PI   3.14159265358979323846264338327950288
#define ESCAPE_MODE %s

out vec4 color;
in vec4 pos_f;
in vec4 rnd_f;

uniform sampler2D img_tex;
uniform int pix_size;
uniform float normed_iter;
uniform vec4 global_seeds;

uniform vec4 palette[50];
uniform int palette_size;
uniform int palette_xyz;


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
	start_l=clamp(start_l,0,1000);
	//start_l=1-exp(-start_l*start_l/100);
	float dist_traveled=length(delta_pos);
	//float color_value=global_seeds.x;
	//float color_value=abs(rnd_f.x*2-1);
	float color_value=rnd_f.x;
	//float color_value=abs(fract(rnd_f.x*3)*2-1);
	//float color_value=normed_iter;
	//float color_value=(cos((rnd_f.x*rnd_f.x+1)*3.14*3)*0.5+0.5);
	//float color_value=(cos(rnd_f.x*3.14*10)*0.5+0.5)*rnd_f.x;
	//float color_value=cos((1-rnd_f.x*rnd_f.x)*3.14*4)*0.5+0.5;
	//float color_value=1-fract(exp((1-rnd_f.x)*4));
	//float color_value=abs(rnd_f.x-0.5)*2;//;//cos(rnd_f.x*3.14*8)*0.5+0.5;
	//float color_value=color_value_vornoi(delta_pos);
	//float color_value=cos(seed.x)*0.5+0.5;
	//float color_value=cos(seed.y*4*M_PI)*0.5+0.5;
	//float color_value=start_l;
	//float color_value=length(pos);
	//float color_value=dot(delta_pos,delta_pos)/10;
	//float color_value=exp(-start_l*start_l);
	//float color_value=1-normed_iter;
	//float color_value=cos(normed_iter*M_PI*2*20)*0.5+0.5;
	//float color_value=smoothstep(0,1,start_l);
	//float color_value=sin(start_l*M_PI*2/4)*0.5+0.5;
	//float color_value=normed_iter*exp(-start_l*start_l);
	//float color_value=1-exp(-dot(delta_pos,delta_pos)/2.5);
	//float color_value=mix(start_l,dist_traveled,normed_iter);
	//float color_value=clamp(dist_traveled/(1+dist_traveled),0,1);

	float intensity2=1;
	//intensity2=1/clamp(dist_traveled,1,10);//1-clamp(dist_traveled/(1+dist_traveled),0,1);
	//intensity2=log(clamp(dist_traveled,0,10000)+3);
	//intensity2=1/clamp(dist_traveled,1,10000);
	//intensity2=start_l;
	//intensity2=global_seeds.y;
	//intensity2=rnd_f.y*2-1;
	//intensity2=rnd_f.y;
	//intensity2=rnd_f.x;
	//intensity2=cos(rnd_f.y*4)+cos(rnd_f.y*7)*0.5+cos(rnd_f.y*12)*0.25;
	//intensity2=smoothstep(0,0.1,1-normed_iter);
	//intensity2=1-normed_iter;
	//intensity2=normed_iter;
	vec3 c;
#define COMPLEX_POINT_OUTPUT 0
#if COMPLEX_POINT_OUTPUT
	c.x=cos(color_value*M_PI*2)*intensity*intensity2;
	c.y=sin(color_value*M_PI*2)*intensity*intensity2;
	c.z=0;
#else
	if(palette_xyz==1)
		c=mix_palette(color_value).xyz;
	else
		c=rgb2xyz(mix_palette(color_value).xyz);
	c*=a*intensity*intensity2;
#endif
	//c=max(vec3(0),c);
	//c+=vec3(0.01);
	//c*=(sin(start_l*M_PI*16)+0.6);
	//c*=(sin(normed_iter*M_PI*8)+0.1);
	//c*=(sin(start_l*M_PI*8)+0.0);
	//c*=(start_l-0.5)*2;
	//c*=sin(global_seeds.x*M_PI*8)+0.3;
	//color=vec4(exp(-c*0.0001),1);
	color=vec4(c,1);

}
]==],escape_mode_str()))

advance_random=shaders.Make(
[==[
#version 330
#line 3292
layout(location = 0) in uvec4 position;
out uvec4 point_out;

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
#define HASH lowbias32
uvec4 wang_hash_seed(uvec4 v)
{
	return uvec4(HASH(v.x),HASH(v.y),HASH(v.z),HASH(v.w));
}
vec4 float_from_hash(uvec4 val)
{
	return val/vec4(4294967295.0);
}
vec4 float_from_floathash(vec4 val)
{
	return floatBitsToUint(val)/vec4(4294967295.0);
}
vec4 seed_from_hash(uvec4 val)
{
	return uintBitsToFloat(val);
}
void main()
{
	/*
	uvec2 wseed=floatBitsToUint(position.zw);
	wseed+=uvec4(gl_VertexID);
	wseed.x+=uint(rand_number*4294967295.0);
	wseed=wang_hash_seed(wseed);
	vec2 seed=float_from_hash(wseed);
	vec2 old_seed=float_from_floathash(position.zw);
	*/
	point_out=wang_hash_seed(position+uvec4(gl_VertexID));
	//point_out=wang_hash_seed(position);
	//point_out=uvec4(0,0,position.xy);
}
]==],
[==[
void main()
{

}
]==],
"point_out")


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
#if 0
	float move_dist=length(s-p);
	if(move_dist<0.005)
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

	//vec2 seedu=hash22(position.zw*98.5789+vec2(rand_number*78.1547,gl_VertexID*484.0545));
	//vec2 seedu=vec2(rand(rand_number*999999),rand(position.x*789789+position.w*rand_number*45648978));
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
	local spread=0.00005
	local num_spread=10
	local id=1
	for i=1,math.floor(num_steps/num_spread) do
		local c=math.random()
		for i=1,num_spread do
			global_seed_shuffling[id]=c+(math.random()*spread-0.5*spread)
			id=id+1
		end
	end
	--]]
	--[[ vanilla
	for i=1,num_steps do
		global_seed_shuffling[i]=math.random()
	end
	--]]
	--[[ random walk
	local v=math.random()
	local min_value=v
	local max_value=v
	for i=1,num_steps do
		global_seed_shuffling[i]=v
		v=v+math.random()*2-1
		if min_value>v then min_value=v end
		if max_value<v then max_value=v end
	end
	for i=1,num_steps do
		global_seed_shuffling[i]=(global_seed_shuffling[i]-min_value)/(max_value-min_value)
	end
	--]]
	-- [[ constantly biggening
	local v=math.random()
	for i=1,num_steps do
		global_seed_shuffling[i]=v
		v=v+math.random()
	end
	for i=1,num_steps do
		global_seed_shuffling[i]=global_seed_shuffling[i]/v
	end

	--[=[ flip every second one
	for i=1,num_steps do
		if i%2==0 then
			global_seed_shuffling[i]=1-global_seed_shuffling[i]
		end
	end
	--]=]
	--]]
	--[[ add shufflings of the original
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
	if config.normalize and not shader_randomize then
		draw_sample_count=math.min(1e5,sample_count)
	end

	local count_reset={0,0,0,0}

	local sample_count_w=math.floor(math.sqrt(draw_sample_count))
	if cur_visit_iter>config.IFS_steps or need_clear or 
		(config.smart_reset and (cur_visit_iter%245==244)) then
		if  cur_visit_iter>config.IFS_steps or need_clear then
			visit_call_count=visit_call_count+1
			cur_visit_iter=0
		end
		-- [===[

		--]===]
		-- [===[
		randomize_points:use()
		randomize_points:set("rand_number",math.random())
		randomize_points:set("radius",config.gen_radius or 2)
		--randomize_points:set("params",config.v0,config.v1,config.v2,config.v3)
		if (config.smart_reset and not need_clear) and cur_visit_iter~=0 and math.random()<0.8 then
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
	-- [==[ Pure random per-point, per-iteration 4vec
	--if math.random()<0.01 then
	--	fill_rand()
	--else
		advance_random:use()
		local so=rnd_samples:get_next()
		so:use()
		so:bind_to_feedback()
		rnd_samples:get():use()
		advance_random:raster_discard(true)
		advance_random:draw_points(0,draw_sample_count,4,1)
		__unbind_buffer()
		advance_random:raster_discard(false)
		rnd_samples:advance()
	--end
	--]==]
	--fill_rand()
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
	local last_global_seed=0
	if config.shuffle_size<=0 then
		global_seed=math.random()
	else

		global_seed_id=global_seed_id or 1
		global_seed_id=global_seed_id+1
		if global_seed_id>#global_seed_shuffling then
			if config.reshuffle then
				--shuffle(global_seed_shuffling)
				generate_shuffling(config.shuffle_size)
			end
			global_seed_id=1
		end
		last_global_seed=global_seed or 0
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

		visit_tex.t:use(1,not_pixelated)
		transform_shader:set_i("img_tex",1)
		transform_shader:set("global_seeds",global_seed,last_global_seed,0,0)
		transform_shader:set("normed_iter",cur_visit_iter/config.IFS_steps)
		transform_shader:set("gen_radius",config.gen_radius or 2)
		transform_shader:raster_discard(true)

		rnd_samples:get():use()
		transform_shader:push_iattribute(0,1,4,GL_UNSIGNED_INT)

		samples:get_current():use()
		transform_shader:draw_points(0,draw_sample_count,4,1)
		transform_shader:raster_discard(false)
		samples:flip()
		__unbind_buffer()
		cur_visit_iter=cur_visit_iter+1
	end
--]==]
	if need_clear or cur_visit_iter>0 then
		add_visits_shader:use()
		local cs=samples:get_current()
		cs:use()

		add_visits_shader:raster_discard(false)
		visit_tex.t:use(0,not_pixelated)
		add_visits_shader:push_attribute(0,"pos",4,nil,4*4)
		--add_visits_shader:blend_multiply()
		add_visits_shader:blend_add()
		add_visits_shader:set_i("img_tex",1)
		add_visits_shader:set_i("pix_size",psize)
		add_visits_shader:set("center",config.cx,config.cy)
		add_visits_shader:set("scale",config.scale,config.scale*aspect_ratio)
		add_visits_shader:set("normed_iter",cur_visit_iter/config.IFS_steps)
		add_visits_shader:set("global_seeds",global_seed,1-cur_visit_iter/config.IFS_steps,0,0)

		rnd_samples:get():use()
		add_visits_shader:push_iattribute(0,1,4,GL_UNSIGNED_INT)

		set_shader_palette(add_visits_shader)
		if not visit_tex.t:render_to(visit_tex.w,visit_tex.h) then
			error("failed to set framebuffer up")
		end
		add_visits_shader:draw_points(0,draw_sample_count,4)
		if need_clear then
			--__setclear(95.047,100,108.883) XYZ of d65 blackbody
			__setclear(0,0,0)
			__clear()
			cur_visit_iter=0
			need_clear=false
			global_seed_id=1
		end
	end

	__unbind_buffer()
	__render_to_window()
end

local draw_frames=1200
local frame_count=300
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
function ncos( v )
	return math.cos(v)*0.5+0.5
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
	--[[
	global_seed_shuffling[1]=ncos(a*1+12.8)*0.5+0.5
	global_seed_shuffling[2]=ncos(a*2+31.1)*0.5
	global_seed_shuffling[3]=ncos(a*3+1)*0.125
	global_seed_shuffling[4]=ncos(a*4+77.014)*0.125
	global_seed_shuffling[5]=ncos(a*1+1.34)*0.75+0.25
	global_seed_shuffling[6]=ncos(a*2+3.4)*0.9+0.1
	global_seed_shuffling[7]=ncos(a*3+0.97)*0.1+0.9
	global_seed_shuffling[8]=ncos(a*2)*0.3+0.3
	--]]
	--config.v1=lerp(-0.6,-0.55,ncos(a))
	config.v0=lerp(-0.440,0.1,ncos(a))
	config.move_dist=lerp(0.1,0.165,ncos(a*2))
	--config.gamma=lerp(0.4,0.89,config.animation)
	--config.IFS_steps=lerp(1,1000,config.animation)
	--draw_frames=lerp(100,1000,config.animation)
end
function fake_tonemap( v )
	local Y=v.g
	Y=Y/(1+Y)
	return Y/v.g
end

function update_real(  )
	__no_redraw()
	if animate then
		__clear()
		tick=tick or 0
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
		draw_visits()
	end
	auto_clear()
	local anim_check=false
	if anim_check then
		update_animation_values( )
		tick=tick or 0
		--
		tick=tick+1
		if tick<draw_frames then
			visit_iter()
		end
	else
		visit_iter()
	end
    if sim_thread then
        --print("!",coroutine.status(sim_thread))
        local ok,err=coroutine.resume(sim_thread)
        if not ok then
            print("Error:",err)
            sim_thread=nil
        end
    end

	local scale=config.scale
	local cx,cy=config.cx,config.cy

	local c,x,y= is_mouse_down()
	if c then
		--mouse to screen
		--[=[
		x=(x/size[1]-0.5)*2
		y=(-y/size[2]+0.5)*
		if x>-1 and x<1 and
		   y>-1 and y<1 then
			--screen to world
			--[[
			x=(x-cx)/scale
			y=(y-cy)/(scale*aspect_ratio)
			--]]
			--screen to pixel
		
			x=math.floor(((x+1)/2)*visit_buf.w)
			y=math.floor(((y+1)/2)*visit_buf.h)
			if x>=0 and x<visit_buf.w and y>=0 and y<visit_buf.h then
				local v=visit_buf:get(x,y)
				local m=fake_tonemap(v)
				print(x,y,v.r*m,v.g*m,v.b*m)
			end
		end
		--]=]
		-- [[
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
		--]]
	end
	if __mouse.wheel~=0 then
		local pfact=math.exp(__mouse.wheel/10)
		config.scale=config.scale*pfact
		config.cx=config.cx*pfact
		config.cy=config.cy*pfact
		need_clear=true
	end
end

