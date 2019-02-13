
require "common"
require "colors"
local luv=require "colors_luv"
local size_mult=1
local win_w=1024*size_mult
local win_h=win_w--math.floor(1024*size_mult*(1/math.sqrt(2)))
__set_window_size(win_w,win_h)
local aspect_ratio=win_w/win_h
local size=STATE.size
local max_palette_size=50
local sample_count=100000
local max_sample=100000000 --for halton seq.
local need_clear=false
local oversample=1
local render_lines=false --does not work :<
str_x=str_x or "s.x"
str_y=str_y or "s.y"
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
	{"only_last",false,type="boolean"},
	{"auto_scale_color",false,type="boolean"},
	{"draw",true,type="boolean"},
	{"point_size",0,type="int",min=0,max=10},
	{"ticking",1,type="int",min=1,max=2},
	{"v0",-0.211,type="float",min=-5,max=5},
	{"v1",-0.184,type="float",min=-5,max=5},
	{"v2",-0.184,type="float",min=-5,max=5},
	{"v3",-0.184,type="float",min=-5,max=5},
	{"IFS_steps",10,type="int",min=1,max=100},
	{"move_dist",0.1,type="float",min=0.001,max=2},
	{"scale",1,type="float",min=0.00001,max=2},
	--[[{"rand_angle",0,type="float",min=0,max=math.pi*2},
	{"rand_dist",0.01,type="float",min=0.00001,max=1},]]
	{"cx",0,type="float",min=-10,max=10},
	{"cy",0,type="float",min=-10,max=10},
	{"min_value",0,type="float",min=0,max=20},
	{"gen_radius",1,type="float",min=0,max=10},
	{"animation",0,type="float",min=0,max=1},
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
	for(int i=0;i<50;i++)
		for(int j=0;j<50;j++)
		{
			vec2 delta=vec2(float(i-25)/1024,float(j-25)/1024);
			float dist=length(delta);
			float v=texture(tex_main,pos+delta).x;
			if(max<v)max=v;
			if(min>v)min=v;
			avg+=v*(1/(dist*dist+1));
			wsum+=(1/(dist*dist+1));
		}
	avg/=wsum;
	return vec2(log(avg/10+1),log(avg*10+1));
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
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float nv=texture(tex_main,normed).x;

	vec2 lmm=min_max;
	//vec2 lmm=local_minmax(normed);
	if(auto_scale_color==1)
		nv=(log(nv+1)-lmm.x)/(lmm.y-lmm.x);
	else
		nv=log(nv+1)/lmm.y;

	/* compress everything a bit
	float pw=0.5;
	nv=pow(nv,pw);
	*/
	//nv=floor(nv*10)/10; //stylistic quantization
	//nv=pow(nv,1/pw);

	float l=mask(pos.xy);

	nv=clamp(nv,0,1);
	color = mix_palette2(nv*l);
}
]==]
local need_save
function draw_visits(  )
	local lmax=0
	local lmin=math.huge
	make_visits_texture()
	make_visits_buf()
	visit_tex.t:use(0,1)
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
	log_shader:use()
	visit_tex.t:use(0,1)
	--visits:write_texture(visit_tex)

	set_shader_palette(log_shader)
	log_shader:set("min_max",lmin,lmax)
	log_shader:set_i("tex_main",0)
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
current_gen=1,
colors_input={{1,0,0,1,0},{0,0,0,1,math.floor(max_palette_size*0.5)},{0,0.7,0.7,1,max_palette_size-1}}}
function update_palette_img(  )
	if palette_img.w~=#palette.colors_input then
		palette_img=make_flt_buffer(#palette.colors_input,1)
	end
	for i,v in ipairs(palette.colors_input) do
		palette_img:set(i-1,0,v)
	end
end
function mix_color(c1,c2,v)
	local c1_v=c1[5]
	local c2_v=c2[5]
	local c_v=c2_v-c1_v
	local my_v=v-c1_v
	local local_v=my_v/c_v

	local ret={}
	for i=1,4 do
		ret[i]=(c2[i]-c1[i])*local_v+c1[i]
	end
	return ret
end
function set_shader_palette(s)
	s:set_i("palette_size",max_palette_size)
	local cur_color=2
	for i=0,max_palette_size-1 do
		if palette.colors_input[cur_color][5] < i then
			cur_color=cur_color+1
		end
		local c=mix_color(palette.colors_input[cur_color-1],palette.colors_input[cur_color],i)

		s:set(string.format("palette[%d]",i),c[1],c[2],c[3],c[4])
	end
end
function rand_range( t )
	return math.random()*(t[2]-t[1])+t[1]
end
function new_color( h,s,l,pos )
	local r=luv.hsluv_to_rgb{(h)*360,(s)*100,(l)*100}
	r[4]=1
	r[5]=pos
	return r
end
palette.generators={
	{"random",function (ret, hue_range,sat_range,lit_range )
		local count=math.random(2,10)
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
		local r1=luv.hsluv_to_rgb{(h1)*360,(s)*100,(l)*100}
		r1[4]=1
		local r2=luv.hsluv_to_rgb{(1-h1)*360,(s2)*100,(l2)*100}
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
		local r1=luv.hsluv_to_rgb{(h1)*360,(s)*100,(l)*100}
		r1[4]=1
		local r2=luv.hsluv_to_rgb{(1-h1)*360,(s2)*100,(l2)*100}
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
	
	local function gen_shades(tbl, h_start,s_start,l_start,l_end,count)
		local diff=l_end-l_start
		for i=0,count-1 do
			table.insert(tbl,luv.hsluv_to_rgb({h_start,s_start,l_start+diff*(i/(count-1))}))
		end
	end
	palette.generators[palette.current_gen][2](ret,hue_range,sat_range,lit_range)
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
					print(string.format("#%02X%02X%02X%02X  %d",math.floor(v[1]*255),math.floor(v[2]*255),math.floor(v[3]*255),math.floor(v[4]*255),v[5]))
				end
			end
		end
		if #palette.colors_input>0 then
			local cur_v=palette.colors_input[palette.current]
			local new_col,ne_pos
			_,new_col=imgui.ColorEdit4("Current color",cur_v,true)
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
	local ret="palette={show=false,current_gen=%d,colors_input={%s}}\n"
	local pal=""
	for i,v in ipairs(palette.colors_input) do
		pal=pal..string.format("{%f,%f,%f,%f,%d},",v[1],v[2],v[3],v[4],v[5])
	end
	return string.format(ret,palette.current_gen,pal)
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
	config_serial=config_serial..string.format("str_preamble=%q\n",str_preamble)
	config_serial=config_serial..string.format("str_postamble=%q\n",str_postamble)
	config_serial=config_serial..palette_serialize()
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end

local terminal_symbols={["s.x"]=5,["s.y"]=5,["p.x"]=3,["p.y"]=3,["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,["normed_i"]=2}
local terminal_symbols_alt={["p.x"]=3,["p.y"]=3}
local terminal_symbols_param={["s.x"]=5,["s.y"]=5,["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,["normed_i"]=2}
local normal_symbols={["max(R,R)"]=0.05,["min(R,R)"]=0.05,["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,["abs(R)"]=0.1,["sqrt(R)"]=0.1,["exp(R)"]=0.01,["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,["log(R)"]=1,["(R)/(R)"]=8,["(R)*(R)"]=16,["(R)-(R)"]=60,["(R)+(R)"]=60}

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

	--str_x="sin("..s.."-s.x*s.y)"
	--str_y="cos("..s.."-s.y*s.x)"
	str_x=random_math(rand_complexity)
	str_y=random_math(rand_complexity)

	--str_x=random_math(rand_complexity,"R*length(s)")
	--str_y=random_math(rand_complexity,"R*length(s)")

	--str_x=s.."*(length(s-p))"
	--str_y=s.."*(-length(s-p))"

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

	--str_x=random_math_power(5,rand_complexity)
	--str_y=random_math_power(5,rand_complexity)

	--str_x=random_math(rand_complexity,"R*s.x*s.x-R*s.y*s.y")
	--str_y=random_math(rand_complexity,"R*s.x*s.x-R*s.y*s.y")


	--str_x=random_math(rand_complexity,"R+R*s.x+R*s.y+R*s.x*s.y")
	--str_y=random_math(rand_complexity,"R+R*s.x+R*s.y+R*s.x*s.y")
	--str_x="s.x"
	--str_y="s.y"

	--str_y="-"..str_x
	--str_x=random_math(rand_complexity,"cos(R)*R")
	--str_y=random_math(rand_complexity,"sin(R)*R")
	--str_y="sin("..str_x..")"
	--str_x="cos("..str_x..")"
	--str_x=random_math_power(2,rand_complexity).."/"..random_math_power(2,rand_complexity)
	--str_y=random_math_fourier(2,rand_complexity).."/"..str_x
	str_preamble=""
	str_postamble=""
	--[[ gravity
	str_preamble=str_preamble.."s*=1/move_dist;"
	--]]
	--[[ boost
	str_preamble=str_preamble.."s*=move_dist;"
	--]]
	--[[ center PRE
	str_preamble=str_preamble.."s=s-p;"
	--]]
	--[[ cosify
	str_preamble=str_preamble.."s=cos(s);"
	--]]
	--[[ tanify
	str_preamble=str_preamble.."s=tan(s);"
	--]]
	--[[ logitify PRE
	str_preamble=str_preamble.."s=log(abs(s));"
	--]]
	-- [[ gaussination
	str_postamble=str_postamble.."s=vec2(exp(1/(-s.x*s.x)),exp(1/(-s.y*s.y)));"
	--]]
	--[[ offset
	str_preamble=str_preamble.."s+=params.xy;"
	--]]
	--[[ rotate
	str_preamble=str_preamble.."s=vec2(cos(params.z)*s.x-sin(params.z)*s.y,cos(params.z)*s.y+sin(params.z)*s.x);"
	--]]
	-- [[ const-delta-like
	str_preamble=str_preamble.."vec2 os=s;"
	str_postamble=str_postamble.."s/=length(s);s=os+s*move_dist;"
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
	-- [[ unrotate POST
	str_postamble=str_postamble.."s=vec2(cos(-params.z)*s.x-sin(-params.z)*s.y,cos(-params.z)*s.y+sin(-params.z)*s.x);"
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
	print("==============")
	print(str_preamble)
	print(str_x)
	print(str_y)
	print(str_postamble)
	make_visit_shader(true)
	need_clear=true
end
function gui()
	imgui.Begin("IFS play")
	palette_chooser()
	draw_config(config)
	local s=STATE.size
	if imgui.Button("Clear image") then
		clear_buffers()
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		need_save=true
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
function mix_palette(out,input_t )
	if #palette.colors<=1 then
		return
	end
	if input_t>1 then input_t=1 end
	if input_t<0 then input_t=0 end

	local tg=input_t*(#palette.colors-1) -- [0,1]--> [0,#colors]
	local tl=math.floor(tg)

	local t=tg-tl
	local it=1-t
	local c1=palette.colors[tl+1]
	local c2=palette.colors[math.ceil(tg)+1]
	if c1==nil or c2==nil then
		out={0,0,0,255}
		return
	end
	--hsv mix
	if false then
		local hsv1={rgbToHsv(c1[1]*255,c1[2]*255,c1[3]*255,255)}
		local hsv2={rgbToHsv(c2[1]*255,c2[2]*255,c2[3]*255,255)}
		local hsv_out={}
		for i=1,3 do
			hsv_out[i]=hsv1[i]*it+hsv2[i]*t
		end
		local rgb_out={hsvToRgb(hsv_out[1],hsv_out[2],hsv_out[3],255)}
		out.r=rgb_out[1]
		out.g=rgb_out[2]
		out.b=rgb_out[3]
		--]]
	else
		out.r=(c1[1]*it+c2[1]*t)*255
		out.g=(c1[2]*it+c2[2]*t)*255
		out.b=(c1[3]*it+c2[3]*t)*255
	end
	out.a=(c1[4]*it+c2[4]*t)*255
end

function gl_mod( x,y )
	return x-y*math.floor(x/y)
end

function auto_clear(  )
	local pos_start=0
	local pos_end=0
	for i,v in ipairs(config) do
		if v[1]=="v0" then
			pos_start=i
		end
		if v[1]=="cy" then
			pos_end=i
		end
	end

	for i=pos_start,pos_end do
		if config[i].changing then
			need_clear=true
			break
		end
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
function make_visit_shader( force )
if add_visit_shader==nil or force then
	add_visit_shader=shaders.Make(
string.format([==[
#version 330
#line 1322
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
vec2 func_actual(vec2 p,int it_count)
{
	vec2 s=vec2(p.x,p.y);
	
	for(int i=0;i<it_count;i++)
		{
			float normed_i=float(i)/float(it_count);
			%s
			s=vec2(%s,%s);
			%s
		}
	return s;
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
vec2 func(vec2 p,int it_count)
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
	vec2 r=func_actual(p,it_count);
	//vec2 delta=p-r;
	//return p*exp(1/-dot(delta,delta));
	return p*exp(1/-dot(r,r));
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
	const float symetry_defect=0.002;
	vec2 v=to_polar(p);
	
	float av=floor((v.y+M_PI)/ang);
	float pv=mod(v.y,ang);
	const float dist_div=0.5;
	vec2 c=vec2(cos(av*ang),sin(av*ang))*dist_div;
	
	p-=c;
	p-=c*symetry_defect*av; //sort of shell-like looking

	p=tRotate(p,ang*av+symetry_defect*av);
	//p=tReflect(p,ang*av/2+symetry_defect*av);
	vec2 r=func_actual(p,it_count);//+vec2(0,-dist_div);
	//r=tReflect(r,ang*av/2);
	r=tRotate(r,-ang*av);

	//r+=c*0.25*av;
	r+=c;
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
	const float symetry_defect=0.000;//0.01;
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
	vec2 r=func_actual(p,it_count);//+vec2(0,-dist_div);
	//r=tReflect(r,rotate_amount*av/2);
	r=tRotate(r,-rotate_amount*av);
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
vec2 mapping(vec2 p)
{
	return p;
	//return mod(p+vec2(1),2)-vec2(1);

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
vec2 dfun(vec2 p,int iter,float h)
{
	vec2 x1=func(p+vec2(1,1)*h,iter);
	vec2 x2=func(p+vec2(1,-1)*h,iter);
	vec2 x3=func(p+vec2(-1,1)*h,iter);
	vec2 x4=func(p+vec2(-1,-1)*h,iter);
	
	return (x1-x2-x3+x4)/(4*h*h);

}
void main()
{
	float d=0;
	

	//float h1=hash(position.xy*seed);
	//float h2=hash(position.xy*5464+vec2(1244,234)*seed);
	//vec2 p_rnd=position.xy+gaussian(0,1,vec2(h1,h2));
	/*vec2 p_far=func(p_rnd,max_iters);
	if(d>1)
		pos.x=1;
	else
		pos.x=0;*/
	//gl_Position.xy = mapping(dfun(position.xy,iters,0.1)*scale+center);
	gl_Position.xy = mapping(func(position.xy,iters)*scale+center);
	gl_PointSize=pix_size;
	gl_Position.z = 0;
    gl_Position.w = 1.0;
    pos=gl_Position.xyz;
}
]==],str_preamble,str_x,str_y,str_postamble),
[==[
#version 330
#line 1228

out vec4 color;
in vec3 pos;
uniform sampler2D img_tex;
uniform int pix_size;

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
	//vec4 txt=texture(img_tex,mod(pos.xy*vec2(0.5,-0.5)+vec2(0.5,0.5),1));
#if 0
	float delta_size=shape_point(pos.xy);
#else
	float delta_size=1;
#endif

	//float delta_size=txt.r;
 	float r = 2*length(gl_PointCoord - 0.5)/(delta_size);
	float a = 1 - smoothstep(0, 1, r);
	float intensity=1/float(pix_size);
	//rr=clamp((1-rr),0,1);
	//rr*=rr;
	//color=vec4(a,0,0,1);
	color=vec4(a*intensity,0,0,1);
}
]==])
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
	{16,2},
	{8,4},
	{4,8},
	{2,16},
	{1,32},
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

		local step=1
		if draw_lines then
			step=2
		end
		local sample_count=samples.w*samples.h-1
		local sample_count_w=math.floor(math.sqrt(sample_count))
		for i=0,sample_count,step do
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
			--[[ square
			local x=math.random()*gen_radius-gen_radius/2
			local y=math.random()*gen_radius-gen_radius/2
			--]]
			--gaussian blob with moving center
			--local x,y=gaussian2(-config.cx/config.scale,gen_radius,-config.cy/config.scale,gen_radius)
			--gaussian blob
			--local x,y=gaussian2(0,gen_radius,0,gen_radius)
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

			-- [[ circle area
			local a = math.random() * 2 * math.pi
			local r = gen_radius * math.sqrt(math.random())
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
			local blur_str=0.005
			x,y=gaussian2(x,blur_str,y,blur_str)
			--]]
			--[[ blur mod linear
			local blur_str=0.01
			x=x+math.random()*blur_str-blur_str/2
			y=y+math.random()*blur_str-blur_str/2
			--]]
			--[[ circles mod
			local circle_size=0.001
			local a2 = math.random() * 2 * math.pi
			x=x+math.cos(a2)*circle_size
			y=y+math.sin(a2)*circle_size
			--]]
			local angle_off=math.atan2(y,x)
			samples.d[i]={x,y}
			if step==2 then
				local dx=math.cos(config.rand_angle+angle_off)*config.rand_dist
				local dy=math.sin(config.rand_angle+angle_off)*config.rand_dist
				samples.d[i+1]={x+dx,y+dy}
			end
		end

		if config.only_last then
			add_visit_shader:set("seed",math.random())
			add_visit_shader:set_i("iters",config.IFS_steps)
			if render_lines then
				add_visit_shader:draw_lines(samples.d,samples.w*samples.h,false)
			else
				add_visit_shader:draw_points(samples.d,samples.w*samples.h,false)
			end
		else
			for i=1,config.IFS_steps do
				add_visit_shader:set("seed",math.random())
				add_visit_shader:set_i("iters",i)
				if render_lines then
					add_visit_shader:draw_lines(samples.d,samples.w*samples.h,false)
				else
					add_visit_shader:draw_points(samples.d,samples.w*samples.h,false)
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
		--screen to world
		x=(x-cx)/scale
		y=(y-cy)/(scale*aspect_ratio)

		print(x,y)
		--now set that world pos so that screen center is on it
		config.cx=(-x)*scale
		config.cy=(-y)*(scale*aspect_ratio)
		need_clear=true
	end
	if __mouse.wheel~=0 then
		local pfact=math.exp(__mouse.wheel/10)
		config.scale=config.scale*pfact
		config.cx=config.cx*pfact
		config.cy=config.cy*pfact
		need_clear=true
	end
end
