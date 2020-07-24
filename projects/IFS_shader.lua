
require "common"
require "colors"
--[[ idea: 
		use a texture WxH that is a "random function from IFS"
			each point would be a e.g. 4xfloat to a F(x,y) params 
			- that would give would bring this closer to fractal flame?
			]]
local luv=require "colors_luv"
local bwrite = require "blobwriter"
local bread = require "blobreader"
local size_mult=1
local win_w
local win_h
local aspect_ratio
function update_size(  )
	win_w=1280*size_mult
	win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
update_size()

local size=STATE.size
local max_palette_size=50
local sample_count=131072
local max_sample=1000000000 --for halton seq.
local need_clear=false
local oversample=1
local render_lines=false
local complex=true
local init_zero=false
local escape_fractal=false

str_x=str_x or "s.x"
str_y=str_y or "s.y"

str_cmplx=str_cmplx or "c_mul(s,s)+p"

str_preamble=str_preamble or ""
str_postamble=str_postamble or ""
img_buf=make_image_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	print("new size:",w,h)
end
function make_visits_texture()
	if visit_tex==nil or visit_tex.w~=size[1]*oversample or visit_tex.h~=size[2]*oversample then
		print("making tex")
		visit_tex={t=textures:Make(),w=size[1]*oversample,h=size[2]*oversample}
		visit_tex.t:use(0,1)
		visit_tex.t:set(size[1]*oversample,size[2]*oversample,2)
	end
end
function make_visits_buf(  )
	if visit_buf==nil or visit_buf.w~=size[1]*oversample or visit_buf.h~=size[2]*oversample then
		visit_buf=make_float_buffer(size[1]*oversample,size[2]*oversample)
	end
end
tick=tick or 0
config=make_config({
	{"only_last",true,type="boolean"},
	{"auto_scale_color",false,type="boolean"},
	{"draw",true,type="boolean"},
	{"point_size",0,type="int",min=0,max=10},
	{"ticking",1,type="int",min=1,max=2},
	{"size_mult",true,type="boolean"},
	{"v0",-0.211,type="float",min=-1,max=1},
	{"v1",-0.184,type="float",min=-1,max=1},
	{"v2",-0.184,type="float",min=-1,max=1},
	{"v3",-0.184,type="float",min=-1,max=1},
	{"IFS_steps",10,type="int",min=1,max=100},
	{"move_dist",0.1,type="float",min=0.001,max=2},
	{"scale",1,type="float",min=0.00001,max=2},
	--[[{"rand_angle",0,type="float",min=0,max=math.pi*2},
	{"rand_dist",0.01,type="float",min=0.00001,max=1},]]
	{"cx",0,type="float",min=-10,max=10},
	{"cy",0,type="float",min=-10,max=10},
	{"min_value",0,type="float",min=0,max=20},
	{"gen_radius",2,type="float",min=0,max=10},
	{"animation",0,type="float",min=0,max=1},
	{"gamma",1,type="float",min=0.01,max=5},
	{"gain",1,type="float",min=-5,max=5},
},config)


local log_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec4 palette[50];
uniform int palette_size;

uniform vec2 min_max;
uniform sampler2D tex_main;
uniform sampler2D tex_palette;
uniform int auto_scale_color;
uniform float v_gamma;
uniform float v_gain;
#define M_PI   3.14159265358979323846264338327950288

float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise(vec2 p){
	vec2 ip = floor(p);
	vec2 u = fract(p);
	u = u*u*(3.0-2.0*u);
	
	float res = mix(
		mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
		mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
	return res*res;
}
#define NUM_OCTAVES 5

float fbm(vec2 x) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100);
	// Rotate to reduce axial bias
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.50));
	for (int i = 0; i < NUM_OCTAVES; ++i) {
		v += a * noise(x);
		x = rot * x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

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
vec2 local_minmax(vec2 pos)
{
	float nv=texture(tex_main,pos).x;
	float min=nv;
	float max=nv;
	float avg=0;
	float wsum=0;
	int look_size=15;
	for(int i=-look_size;i<=look_size;i++)
		for(int j=-look_size;j<=look_size;j++)
		{
			vec2 delta=vec2(float(i)/1024,float(j)/1024);
			float dist=length(delta);
			float v=texture(tex_main,pos+delta).x;
			if(max<v)max=v;
			if(min>v)min=v;
			avg+=v*(1/(dist*dist+1));
			wsum+=(1/(dist*dist+1));
		}
	avg/=wsum;
	float avg_size=50;
	//return vec2(min+avg,max-avg);
	return vec2(log(avg/avg_size+1),log(avg*avg_size+1));
}
float dtex(vec2 p)
{
	float v1=0;
	v1+=textureOffset(tex_main,p,ivec2(-1,0)).x;
	v1+=textureOffset(tex_main,p,ivec2(1,0)).x;
	v1+=textureOffset(tex_main,p,ivec2(0,1)).x;
	v1+=textureOffset(tex_main,p,ivec2(0,-1)).x;

	v1+=textureOffset(tex_main,p,ivec2(-1,-1)).x;
	v1+=textureOffset(tex_main,p,ivec2(1,1)).x;
	v1+=textureOffset(tex_main,p,ivec2(-1,1)).x;
	v1+=textureOffset(tex_main,p,ivec2(1,-1)).x;

	v1+=textureOffset(tex_main,p,ivec2(-2,0)).x*0.5;
	v1+=textureOffset(tex_main,p,ivec2(2,0)).x*0.5;
	v1+=textureOffset(tex_main,p,ivec2(0,2)).x*0.5;
	v1+=textureOffset(tex_main,p,ivec2(0,-2)).x*0.5;
	return v1/10;
}
vec2 tRotate(vec2 p, float a) {
	float c=cos(a);
	float s=sin(a);
	mat2 m=mat2(c,-s,s,c);
	return m*p;
}
float sdBox( in vec2 p, in vec2 b )
{
    vec2 d = abs(p)-b;
    return length(max(d,vec2(0))) + min(max(d.x,d.y),0.0);
}
float sdEquilateralTriangle( in vec2 p )
{
    const float k = sqrt(3.0);
    
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0/k;
    if( p.x + k*p.y > 0.0 ) p = vec2( p.x - k*p.y, -k*p.x - p.y )/2.0;
    p.x -= clamp( p.x, -2.0, 0.0 );
    return -length(p)*sign(p.y);
}
float mask(vec2 pos)
{
	float phi=1.61803398875;
	float box_size=0.6;
	float blur=0.015;
	float min_value=0.4;
	float noise_scale=0.02;
	float noise_freq=70;
	pos.x*=phi;
	pos=tRotate(pos,M_PI*3/4);

	//vec2 n=vec2(fbm(pos*noise_freq),fbm(pos*noise_freq+vec2(1213,1099)));
	//pos+=n*noise_scale;


	float ret=sdBox(pos,vec2(box_size,box_size));
	
	ret=smoothstep(0.0,blur,ret);
	ret=clamp(1-ret,min_value,1);
	return 1;
}
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float nv=texture(tex_main,normed).x;
	//vec2 local_mm=local_minmax(normed);
	//float lnv=abs(nv-dtex(normed));
	vec2 lmm=min_max;
	if(auto_scale_color==1)
	{
		//lnv=(log(lnv+1)-lmm.x)/(lmm.y-lmm.x);
		nv=(log(nv+1)-lmm.x)/(lmm.y-lmm.x);
	}
	else
	{
		//lnv=log(lnv+1)/lmm.y;
		nv=log(nv+1)/lmm.y;
	}
	//lnv=clamp(lnv,0,1);
	nv=clamp(nv,0,1);

	/* compress everything a bit i.e. like gamma but for palette
	float pw=0.5;
	nv=pow(nv,pw);
	*/
	//nv=floor(nv*10)/10; //stylistic quantization
	//nv=pow(nv,1/pw);

	float l=mask(pos.xy);
	nv=gain(nv,v_gain);
	nv=pow(nv,v_gamma);

	//color = mix_palette2(lnv*l)*nv;
	color = mix_palette2(nv*l);//*lnv;
	color.a=1;
}
]==]
local need_save
local need_buffer_save
visits_minmax=visits_minmax or {}
function buffer_save( name )
	local b=bwrite()
	b:u32(visit_buf.w)
	b:u32(visit_buf.h)
	b:f32(visits_minmax[1])
	b:f32(visits_minmax[2])
	for x=0,visit_buf.w-1 do
	for y=0,visit_buf.h-1 do
		local v=visit_buf:get(x,y)
		b:f32(v)
	end
	end
	local f=io.open(name,"wb")
	f:write(b:tostring())
	f:close()
end
function draw_visits(  )
	local lmax=0
	local lmin=math.huge
	make_visits_texture()
	make_visits_buf()
	visit_tex.t:use(0,1)
	--if visits_minmax==nil or need_buffer_save then
		visit_buf:read_texture(visit_tex.t)
		for x=0,visit_buf.w-1 do
		for y=0,visit_buf.h-1 do
			local v=visit_buf:get(x,y)
			if v>math.exp(config.min_value)-1 then --skip non-visited tiles
				if lmax<v then lmax=v end
				if lmin>v then lmin=v end
			end
		end
		end
		lmax=math.log(lmax+1)
		lmin=math.log(lmin+1)
		visits_minmax={lmin,lmax}
	--end
	--lmax=visits_minmax[1]
	--lmin=visits_minmax[2]
	if need_buffer_save then
		buffer_save(need_buffer_save)
		need_buffer_save=nil
	end
	log_shader:use()
	visit_tex.t:use(0,1)
	--visits:write_texture(visit_tex)

	set_shader_palette(log_shader)
	log_shader:set("min_max",lmin,lmax)
	log_shader:set_i("tex_main",0)
	log_shader:set("v_gamma",config.gamma)
	log_shader:set("v_gain",config.gain)
	local auto_scale=0
	if config.auto_scale_color then auto_scale=1 end
	log_shader:set_i("auto_scale_color",auto_scale)
	log_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end

function clear_buffers(  )
	need_clear=true
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
function gaussian(x,alpha, mu, sigma1,sigma2)
  local squareRoot = (x - mu)/(sigma2)
  if x < mu then
  	squareRoot=(x-mu)/sigma1
  end
  return alpha * math.exp( -(squareRoot * squareRoot)/2 );
end

function luvFromWavelength(wavelength,sat)
	local ret={}
	ret[1] = gaussian(wavelength,  1.056, 5998, 379, 310)
	     + gaussian(wavelength,  0.362, 4420, 160, 267)
	     + gaussian(wavelength, -0.065, 5011, 204, 262);
	ret[1]=ret[1]*sat
	ret[2] = gaussian(wavelength,  0.821, 5688, 469, 405)
	     + gaussian(wavelength,  0.286, 5309, 163, 311);
	ret[2]=ret[2]*sat
	ret[3] = gaussian(wavelength,  1.217, 4370, 118, 360)
	     + gaussian(wavelength,  0.681, 4590, 260, 138);
	ret[3]=ret[3]*sat
  return hsluv.rgb_to_hsluv(luv.xyz_to_rgb(ret))
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
	end},
	{"rainbow",function ( ret,hue_range,sat_range,lit_range )
		local wv_range_size=7400-3800
		local wv1=rand_range({wv_range_size*hue_range[1],wv_range_size*hue_range[2]})+3800
		local wv2=rand_range({wv_range_size*hue_range[1],wv_range_size*hue_range[2]})+3800
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)
		local steps=math.random(4,25)
		local step_size=(wv2-wv1)/steps
		local i=1
		local max_sat=0
		local max_other=0
		for w=wv1,wv2,step_size do
			local col=luvFromWavelength(w,s)
			local pos=math.floor(((i-1)/(steps-1))*(max_palette_size-1))
			local sat=col[2]/100
			if sat>max_sat then max_sat=sat end
			if col[3]/100>max_other then max_other=col[3]/100 end
			table.insert(ret,new_color(col[1]/360,sat,col[3]/100,pos))
			i=i+1
		end
		for i,v in ipairs(ret) do
			v[2]=v[2]/max_sat
			--v[3]=(v[3]/max_other)*l
		end
	end},
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
	--ret[1]={1,1,1,1,0}
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
	config_serial=config_serial..string.format("str_x=%q\n",str_x)
	config_serial=config_serial..string.format("str_y=%q\n",str_y)
	config_serial=config_serial..string.format("str_cmplx=%q\n",str_cmplx)
	config_serial=config_serial..string.format("str_preamble=%q\n",str_preamble)
	config_serial=config_serial..string.format("str_postamble=%q\n",str_postamble)
	config_serial=config_serial..palette_serialize()
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end

local terminal_symbols={["s.x"]=10,["s.y"]=10,["p.x"]=3,["p.y"]=3,["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,["normed_i"]=0.05,["1"]=0.1,["0"]=0.1}
local terminal_symbols_alt={["p.x"]=3,["p.y"]=3}
local terminal_symbols_param={["s.x"]=10,["s.y"]=105,["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,["normed_i"]=0.05}
local normal_symbols={["max(R,R)"]=0.05,["min(R,R)"]=0.05,["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,["abs(R)"]=0.1,["sqrt(R)"]=0.1,["exp(R)"]=0.01,["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,["log(R)"]=1,["(R)/(R)"]=2,["(R)*(R)"]=4,["(R)-(R)"]=6,["(R)+(R)"]=6}

local terminal_symbols_complex={
["s"]=3,["p"]=3,["params.xy"]=1,["params.zw"]=1,["(c_one()*normed_i)"]=0.05,["(c_i()*normed_i)"]=0.05,["c_one()"]=0.1,["c_i()"]=0.1,
--["last_s"]=1,["normalize(s-last_s)"]=1
}
local normal_symbols_complex={
-- [=[
["c_sqrt(R)"]=1,
["c_ln(R)"]=0.1,["c_exp(R)"]=0.01,
["c_acos(R)"]=0.1,["c_asin(R)"]=0.1,["c_atan(R)"]=0.1,
["c_tan(R)"]=1,["c_sin(R)"]=1,["c_cos(R)"]=1,
["c_conj(R)"]=1,
--]=]
["c_div(R,R)"]=4,["c_inv(R)"]=1,
["c_mul(R,R)"]=1,
["(R)-(R)"]=6,["(R)+(R)"]=6}

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
normalize(normal_symbols_complex)
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
			return rep()
		else
			num_rep=num_rep-1
			return false
		end
	end
	local ret=string.gsub(s,substr,rep_one)
	return ret
end
function random_math( steps,seed )
	local cur_string=seed or "R"

	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end

	for i=1,steps do
		cur_string=replace_random(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
function random_math_complex( steps,seed )
	local cur_string=seed or "R"

	function M(  )
		return rand_weighted(normal_symbols_complex)
	end
	function MT(  )
		return rand_weighted(terminal_symbols_complex)
	end

	for i=1,steps do
		cur_string=replace_random(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
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
-- [[
function factorial( n )
	if n<=1 then return 1 end
	return n*factorial(n-1)
end
function random_math_complex_series( steps,seed )
	local cur_string="0" or seed
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
--]]
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
	str_cmplx=random_math_complex(rand_complexity)
	--str_cmplx=random_math_complex(rand_complexity,"c_mul(R,last_s/length(last_s)+c_one())")
	--str_cmplx=random_math_complex_series(rand_complexity)
	--[[
	--str_cmplx="c_mul(c_div((c_div(s,c_cos((params.xy)-(s))))-(s),(c_div((c_conj(s))+(c_div(p,c_cos(p))),((s)-(s))+(c_atan((params.xy)-(p)))))-(c_conj(p))),c_tan(((c_div((s)+(p),(s)+(params.xy)))-((p)+(c_conj(s))))-(p)))"
	--str_cmplx="c_conj(c_tan(((p)+(c_conj((s)-(c_conj((p)+(p))))))+((((c_inv(c_inv(s)))-(c_conj(s)))-(c_sin((c_mul(c_sin((params.zw)+(p)),p))+(s))))-(((s)+(s))+((p)+(((c_div(p,p))+(s))+(s)))))))"
	--]]
	--[[ nice tri-lobed shape

	str_cmplx="c_div(c_conj(p),(s)-(p))"
	--]]
	local pts={}
	local num_roots=7
	for i=1,num_roots do
		local angle=((i-1)/num_roots)*math.pi*2
		table.insert(pts,{math.cos(angle)*config.move_dist,math.sin(angle)*config.move_dist})
	end
	--str_cmplx=random_math_complex_pts(rand_complexity,pts)
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
	--local s="((p.y)+(p.x))+((tan(tan((normed_i)/(params.w))))*(s.y))"
	--str_x="sin("..s.."-s.x*s.y)"
	--str_y="cos("..s.."-s.y*s.x)"
	--str_x=random_math_centered(3,rand_complexity)
	--str_y=random_math_centered(3,rand_complexity)
	str_x=random_math(rand_complexity)
	str_y=random_math(rand_complexity)
	
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
	local series_size=7
	local rand_offset=1
	local rand_size=config.move_dist
	local input_s=""
	for i=1,series_size do
		local sub_s="s"
		for i=1,i do
			sub_s=string.format("c_mul(%s,%s)","s",sub_s)
		end
		sub_s=string.format("%s*%g",sub_s,1/factorial(i))
		input_s=input_s..string.format("+%s*vec2(%.3f,%.3f)",sub_s,rand_offset+math.random()*rand_size-rand_size/2,rand_offset+math.random()*rand_size-rand_size/2)
	end
	str_postamble=str_postamble.."s=s"..input_s..";"
	--]]
	-- [[ polar gravity
	--str_postamble=str_postamble.."float ls=length(s);s*=1-atan(ls*move_dist)/(M_PI/2);"
	--str_postamble=str_postamble.."float ls=length(s);s*=1-atan(ls*move_dist)/(M_PI/2)*move_dist;"
	--str_postamble=str_postamble.."float ls=length(s-vec2(1,1));s=s*(1-atan(ls*move_dist)/(M_PI/2)*move_dist)+vec2(1,1);"
	--str_postamble=str_postamble.."float ls=length(s);s*=(1+sin(ls*move_dist))/2*move_dist;"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);s=last_s+ds*(move_dist/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=1-atan(ls*move_dist)/(M_PI/2);s=last_s+ds*(move_dist*vv/ls);"
	--str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-1/dot(s,s));s=last_s+ds*(move_dist*vv/ls);"
	str_postamble=str_postamble.."vec2 ds=s-last_s;float ls=length(ds);float vv=exp(-1/dot(p,p));s=last_s+ds*(move_dist*vv/ls);"
	--]]
	--[[ boost
	str_preamble=str_preamble.."s*=move_dist;"
	--]]
	--[[ boost less with distance
	str_preamble=str_preamble.."s*=move_dist*exp(-1/dot(s,s));"
	--]]
	--[[ center PRE
	str_preamble=str_preamble.."s=s-p;"
	--]]
	--[[ cosify
	--str_preamble=str_preamble.."s=cos(s);"
	str_preamble=str_preamble.."s=c_cos(s);"
	--]]
	--[[ tanify
	str_preamble=str_preamble.."s=tan(s);"
	--]]
	--[[ logitify PRE
	str_preamble=str_preamble.."s=log(abs(s));"
	--]]
	-- [[ gaussination
	--str_postamble=str_postamble.."s=vec2(exp(1/(-s.x*s.x)),exp(1/(-s.y*s.y)));"
	--str_postamble=str_postamble.."s=s*vec2(exp(move_dist/(-p.x*p.x)),exp(move_dist/(-p.y*p.y)));"
	--]]
	--[[ invert-ination
	--str_preamble=str_preamble.."s=c_inv(s);"
	str_postamble=str_postamble.."s=c_inv(s);"
	--]]
	--[[ offset
	str_preamble=str_preamble.."s+=params.xy;"
	--]]
	--[[ rotate
	--str_preamble=str_preamble.."s=vec2(cos(params.z)*s.x-sin(params.z)*s.y,cos(params.z)*s.y+sin(params.z)*s.x);"
	str_preamble=str_preamble.."p=vec2(cos(params.z*M_PI*2)*p.x-sin(params.z*M_PI*2)*p.y,cos(params.z*M_PI*2)*p.y+sin(params.z*M_PI*2)*p.x);"

	--]]
	--[[ offset_complex
	str_preamble=str_preamble.."s+=params.xy;s=c_mul(s,params.zw);"
	--]]
	--[[ unoffset_complex
	str_postamble=str_postamble.."s=c_div(s,params.zw);s-=params.xy;"
	--]]
	--[[ rotate (p)
	str_preamble=str_preamble.."s=vec2(cos(p.x)*s.x-sin(p.x)*s.y,cos(p.x)*s.y+sin(p.x)*s.x);"
	--str_preamble=str_preamble.."s=vec2(cos(p.y)*s.x-sin(p.y)*s.y,cos(p.y)*s.y+sin(p.y)*s.x);"
	--str_preamble=str_preamble.."s=vec2(cos(normed_i*M_PI*2)*s.x-sin(normed_i*M_PI*2)*s.y,cos(normed_i*M_PI*2)*s.y+sin(normed_i*M_PI*2)*s.x);"
	--]]
	--[[ const-delta-like
	str_preamble=str_preamble.."vec2 os=s;"
	--str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist*exp(1/-dot(p,p));"
	str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist;"
	--str_postamble=str_postamble.."s/=length(s);s=os+c_mul(s,vec2(params.zw));"
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
	str_postamble=str_postamble.."s=vec2(cos(-0.7853981)*s.x-sin(-0.7853981)*s.y,cos(-0.7853981)*s.y+sin(-0.7853981)*s.x);"
	--str_postamble=str_postamble.."p=vec2(cos(-params.z*M_PI*2)*p.x-sin(-params.z*M_PI*2)*p.y,cos(-params.z*M_PI*2)*p.y+sin(-params.z*M_PI*2)*p.x);"
	--str_preamble=str_preamble.."s=vec2(cos(-normed_i*M_PI*2)*s.x-sin(-normed_i*M_PI*2)*s.y,cos(-normed_i*M_PI*2)*s.y+sin(-normed_i*M_PI*2)*s.x);"
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
		clear_buffers()
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.SameLine()
	if imgui.Button("Save buffer") then
		need_buffer_save="out.buf"
	end
	rand_complexity=rand_complexity or 3
	if imgui.Button("Rand function") then
		rand_function()
	end
	imgui.SameLine()

	_,rand_complexity=imgui.SliderInt("Complexity",rand_complexity,1,8)

	if imgui.Button("Animate") then
		animate=true
		need_clear=true
		config.animation=0
	end
	imgui.SameLine()
	if imgui.Button("Update frame") then
		update_animation_values()
	end
	imgui.End()
end
function update( )
	gui()
	update_real()
end

function gl_mod( x,y )
	return x-y*math.floor(x/y)
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
	if config[pos_anim].changing then
		need_clear=true
		update_animation_values()
	end
end
function mod(a,b)
	local r=math.fmod(a,b)
	if r<0 then
		return r+b
	else
		return r
    end
end




knock_buf=knock_buf or load_png("knock.png")
local knock_texture
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
if add_visit_shader==nil or force then
	add_visit_shader=shaders.Make(
string.format([==[
#version 330
#line 1092
#define ESCAPE_MODE %s
//Next three are "generalized complex numbers" with p=-1, p=0 and p=1
#define COMPLEX_NUMBERS
//#define DUAL_NUMBERS //aka boring numbers :<
//#define HYPERBOLIC_NUMBERS //aka split-complex
//#define STRANGE_NUMBERS1
//#define STRANGE_NUMBERS2
layout(location = 0) in vec3 position;
out vec3 pos;

#define M_PI 3.1415926535897932384626433832795

uniform vec2 center;
uniform vec2 scale;
uniform int iters;
uniform int max_iters;
uniform int pix_size;
uniform float seed;
uniform float move_dist;
uniform vec4 params;

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

#ifdef COMPLEX_NUMBERS
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
#endif
#ifdef DUAL_NUMBERS
float arg(vec2 z)
{
	return z.y/z.x;
}

vec2 c_mul(vec2 v1, vec2 v2) {
    return vec2(v1.x*v2.x,v1.x*v2.y+v2.x*v1.y);
}

vec2 c_div(vec2 v1, vec2 v2) {
    float norm = v1.x*v1.x;
    return vec2(v1.x*v2.x,(v1.x*v2.y-v2.x*v1.y))/norm;
}
vec2 c_inv(vec2 c) {
	return vec2(c.x, -c.y) / (c.x*c.x);
}
vec2 c_sin(vec2 z)
{
	return vec2(sin(z.x),cos(z.x)*z.y);
}
vec2 c_cos(vec2 z)
{
	return vec2(cos(z.x),-sin(z.x)*z.y);
}
vec2 c_tan(vec2 z)
{
	float cx=cos(z.x);
	return vec2(tan(z.x),-z.y/(cx*cx));
}
#endif
#ifdef HYPERBOLIC_NUMBERS
vec2 c_mul(vec2 z, vec2 w) {
    return vec2(z.x * w.x + z.y * w.y,
                z.x * w.y + z.y * w.x);
}

#endif


#ifdef STRANGE_NUMBERS1

vec2 c_mul(vec2 z, vec2 w) {
    return vec2(z.x * w.x - z.y * w.y,
                z.x * w.y - z.y * w.x);
}
vec2 c_inv(vec2 z)
{
	float v=1/(z.x*z.x-z.y*z.y);
	return vec2(z.x,z.y)*v;
}
vec2 c_div(vec2 z,vec2 w){
	return c_mul(z,c_inv(w));
}
#endif

#ifdef STRANGE_NUMBERS2

vec2 c_mul(vec2 z, vec2 w) {
    return vec2(z.x * w.x - z.y * w.y+0.5*w.x*w.x-0.5*z.x*z.x,
                z.x * w.y + z.y * w.x+0.5*w.y*w.y-0.5*z.y*z.y);
}

#endif

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
vec3 func_actual(vec2 p,int it_count)
{
	vec2 s = %s;
	vec2 last_s=s;
	float e=1;
	float weight1=1;
	for(int i=0;i<it_count;i++)
		{
			float normed_i=float(i)/float(it_count);
			%s
			%s
			%s
#if ESCAPE_MODE
			if(e>normed_i && dot(s,s)>4)
				{
				e=normed_i;
				break;
				}
#endif
			last_s=s;
		}
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
vec3 func(vec2 p,int it_count)
{
	const float ang=(M_PI/20)*2;
#if 1
	return func_actual(p,it_count);
#endif
#if 0
	vec2 v=to_polar(p);
	vec2 r=func_actual(v,it_count);
	return from_polar(r);
#endif
#if 0
	vec2 v=to_polar(p);
	vec2 r=func_actual(v,it_count);
	v+=r;
	return from_polar(v);
#endif
#if 0
	vec2 r=func_actual(p,it_count);
	//float d=atan(r.y,r.x);
	return (p/*+vec2(cos(d),sin(d))*/)/length(r);
#endif
#if 0
	vec2 r=func_actual(p,it_count);
	return (p/length(p))*length(r);
	//return p/length(p-r);
#endif
#if 0
	vec3 r=func_actual(p,it_count);
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
	vec2 r=func_actual(vp,it_count);
	return p*exp(1/-dot(r,r));
	//return vp;
#endif
#if 0
	
	vec2 r=func_actual(p,it_count);
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
	vec3 r=func_actual(p,it_count);//+vec2(0,-dist_div);
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
	vec2 r=func_actual(p,it_count);//+vec2(0,-dist_div);
	r=tReflect(r,rotate_amount*av/2);
	//r=tRotate(r,-rotate_amount*av);
	r+=c;
	return r;
#endif
#if 0
	const float symetry_defect=0.1;//0.01;
	const float rotate_amount=M_PI*2;//M_PI/3;

	const int cell_count=50;
	const float cell_dist=1;

	int nn=0;
	float min_dist=9999;
	for(int i=0;i<cell_count;i++)
	{
		vec2 c=cell_pos(i,cell_count,cell_dist);
		vec2 d=c-p;
		float dd=dot(d,d);
		if(dd<min_dist)
		{
			min_dist=dd;
			nn=i;
		}
	}

	vec2 cell=cell_pos(nn,cell_count,cell_dist);


	float av=nn;//abs(cell.x)+abs(cell.y);//length(av_v);
	av/=float(cell_count);
	const float dist_div=1;
	vec2 c=cell;//*dist_div*(1/cell_dist);

	p-=c;
	p-=c*symetry_defect*av;
	p=tRotate(p,rotate_amount*av);
	//p=tReflect(p,rotate_amount*av/2+symetry_defect*av);
	vec3 r=func_actual(p,it_count);//+vec2(0,-dist_div);
	//r=tReflect(r,rotate_amount*av/2);
	r.xy=tRotate(r.xy,-rotate_amount*av);
	r.xy+=c;
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
vec2 pMod2(inout vec2 p,float size)
{
	vec2 halfsize=vec2(size*0.5);
	vec2 c= floor((p+halfsize)/size);
	p=mod(p+halfsize,size)-halfsize;
	return c;
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
	//TODO: https://en.wikipedia.org/wiki/Wallpaper_group most of these would be fun...
	if(length(p)<50) //modulo, but no artifacts because far away points are far away
	{
		//float size=2.005; //0.005 overdraw as it smooths the tiling when using non 1 sized points
		float size=2;
		vec2 r=pMod2(p,size);
		//float index=abs(r.x)+abs(r.y);

		//if(mod(index,2)!=0) //make more interesting tiling: each second tile is flipped
		//p*=-1;
		float index=mod(r.x,2)+mod(r.y,2)*2;
		///* code for group p4
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
		*/
		/*
		if(mod(r.y,2)!=0)
		{
			p.y*=-1;
			pMod2(p,size);
		}
		*/
		return p;
		//return mod(p+vec2(size/2),size)-vec2(size/2);
	}
	else
		return p;
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
	/*
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
	float d=0;

#if ESCAPE_MODE
	vec2 inp_p=mapping((position.xy-center)/scale);
    vec3 rez= func(inp_p,iters);//*scale+center;
    pos.xy=position.xy;//*scale+center;
    gl_Position.xy=position.xy;//*scale+center;
    pos.z=rez.z;//length(rez);
#else
	gl_Position.xy = mapping(func(position.xy,iters).xy*scale+center);
	
    pos=gl_Position.xyz;
#endif

    gl_PointSize=pix_size;
	gl_Position.z = 0;
    gl_Position.w = 1.0;
}
]==],escape_mode_str(),make_init_cond(),str_preamble,make_coord_change(),str_postamble),
string.format([==[
#version 330
#line 1282

#define ESCAPE_MODE %s

out vec4 color;
in vec3 pos;
uniform sampler2D img_tex;
uniform int pix_size;
uniform int it_count;
float shape_point(vec2 pos)
{
	//float rr=clamp(1-txt.r,0,1);
	//float rr = abs(pos.y*pos.y);
	float rr=dot(pos.xy,pos.xy);
	//float rr = pos.y-0.5;
	//float rr = length(pos.xy)/5.0;
	rr=clamp(rr,0,1);
	float delta_size=(1-0.2)*rr+0.2;
	return delta_size;
}
void main(){
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
	//rr=clamp((1-rr),0,1);
	//rr*=rr;
	//color=vec4(a,0,0,1);
	color=vec4(a*intensity*v,0,0,1);
}
]==],escape_mode_str()))
end

end

make_visit_shader(true)

if samples==nil or samples.w~=sample_count then
	samples=make_flt_half_buffer(sample_count,1)
end
function math.sign(x)
   if x<0 then
     return -1
   elseif x>0 then
     return 1
   else
     return 0
   end
end
visit_call_count=0
local visit_plan={
	--[[
	{120,1},
	{24,2},
	{6,6},
	{2,24},
	--{1,120},
	--]]
	-- [[
	{75,2},
	{10,6},
	{1,24},
	--]]
	--[[
	{64,1},
	{128,2},
	{16,4},
	{4,8},
	{2,16},
	--{1,32},
	--]]
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
function visit_iter()
	local psize=config.point_size
	if psize<=0 then
		psize=get_visit_size(visit_call_count)--config.point_size
		visit_call_count=visit_call_count+1
	end
	make_visits_texture()
	make_visit_shader()
	add_visit_shader:use()
	if knock_texture==nil then
		knock_texture=textures:Make()
		knock_texture:use(0,1)
		knock_buf:write_texture(knock_texture)
	end
	add_visit_shader:set("center",config.cx,config.cy)
	add_visit_shader:set("scale",config.scale,config.scale*aspect_ratio)
	add_visit_shader:set("params",config.v0,config.v1,config.v2,config.v3)
	add_visit_shader:set("move_dist",config.move_dist)

	visit_tex.t:use(0)
	knock_texture:use(1)
	add_visit_shader:blend_add()
	add_visit_shader:set_i("max_iters",config.IFS_steps)
	add_visit_shader:set_i("img_tex",1)
	add_visit_shader:set_i("pix_size",psize)
	if not visit_tex.t:render_to(visit_tex.w,visit_tex.h) then
		error("failed to set framebuffer up")
	end
	local gen_radius=config.gen_radius

	for i=1,config.ticking do
		if need_clear then
			__clear()
			visit_call_count=0
			need_clear=false
			--print("Clearing")
		end

		local sample_count=samples.w*samples.h-1
		local sample_count_w=math.floor(math.sqrt(sample_count))
		

		for i=0,sample_count do
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
			local cc=i/sample_count
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
			--gaussian blob
		 	local x,y=gaussian2(0,gen_radius,0,gen_radius)
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
			samples.d[i]={x,y}
			--[[ for lines
			local a2 = math.random() * 2 * math.pi
			x=x+math.cos(a2)*config.move_dist
			y=y+math.sin(a2)*config.move_dist
			--samples.d[i+1]={x,y}
			--]]
		end

		if config.only_last then
			add_visit_shader:set("seed",math.random())
			add_visit_shader:set_i("iters",config.IFS_steps)
			if render_lines then
				add_visit_shader:draw_lines(samples.d,samples.w*samples.h,true)
			else
				add_visit_shader:draw_points(samples.d,samples.w*samples.h)
			end
		else
			for i=1,config.IFS_steps do
				add_visit_shader:set("seed",math.random())
				add_visit_shader:set_i("iters",i)
				if render_lines then
					add_visit_shader:draw_lines(samples.d,samples.w*samples.h,true)
				else
					add_visit_shader:draw_points(samples.d,samples.w*samples.h)
				end
			end
		end
	end
	add_visit_shader:blend_default()
	__render_to_window()
end

local draw_frames=100
local frame_count=10
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
function update_animation_values( )
	local a=config.animation*math.pi*2
	--update_scale(math.cos(a)*0.25+0.75)
	--v2:-5,2 =>7
	--v3:-3,3

	config.v1=math.random()*10-5
	config.v2=math.random()*10-5
	config.v3=math.random()*10-5
	config.v4=math.random()*10-5
	gen_palette()
	rand_function()
end

function update_real(  )
	__no_redraw()
	if animate then
		tick=tick or 0
		tick=tick+1
		if tick%draw_frames==0 then
			__clear()
			update_animation_values()
			need_clear=true
			need_save=true
			draw_visits()
			config.animation=config.animation+1/frame_count
			if config.animation>1 then
				animate=false
			end
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
