require 'common'

__set_window_size(1024,1024)
local aspect_ratio=1024/1024
local size=STATE.size

local oversample=1
local org_str="last_v.x*last_v.y*last_v.y"
local str_inner="(last_v.y*last_v.y*last_v.x/coord.x)"
local str_inner=org_str
str_x=str_x or string.format("last_v.x+(adif.x*lap.x-%s+feed*(1-last_v.x))*dt",str_inner)
str_y=str_y or string.format("last_v.y+(adif.y*lap.y+%s-(kill+feed)*(last_v.y))*dt",str_inner)
config=make_config({
	{"line_w",0.01,type="float",min=0,max=1},
	{"color",{0.4,0,0,1},type="color"},

	{"v0",0,type="float",min=-0.2,max=0.2},
	{"v1",0,type="float",min=-0.2,max=0.2},
	{"v2",0,type="float",min=-0.2,max=0.2},
	{"v3",0,type="float",min=0,max=1},

	{"diffuse_x",1,type="float",min=0,max=1},
	{"diffuse_y",0.5,type="float",min=0,max=1},
	{"dt",1,type="float",min=0,max=5},
	{"feed",0.055,type="float",min=0,max=1},
	{"kill",0.062,type="float",min=0,max=1},
	{"complexity",2,type="int",min=1,max=10},
	
	},config)

function make_visits_texture()
	if values_tex==nil or values_tex.w~=size[1]*oversample or values_tex.h~=size[2]*oversample then
		print("making tex")
		values_tex={t=textures:Make(),t_alt=textures:Make(),w=size[1]*oversample,h=size[2]*oversample,
		buf=make_flt_half_buffer(size[1]*oversample,size[2]*oversample)}

		values_tex.t:use(0,1)
		values_tex.t:set(size[1]*oversample,size[2]*oversample,3)

		values_tex.t_alt:use(0,1)
		values_tex.t_alt:set(size[1]*oversample,size[2]*oversample,3)
	end
end
function make_img_buf(  )
	if img_buf==nil or img_buf.w~=size[1] or img_buf.h~=size[2] then
		img_buf=make_image_buffer(size[1],size[2])
	end
end
draw_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float line_w;
uniform vec2 limits;
uniform vec4 in_col;

void main(){
	
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 lv=texture(values,normed).xy;

	//float v=clamp((lv-limits.x)/(limits.y-limits.x),0,1);

	float w=line_w;
	float v=lv.x;
	float c=0.5;
	float vv=clamp(smoothstep(c-w,c,v)-smoothstep(c,c+w,v),0,1);
	color=vec4(vv*in_col);
	
	//color=vec4(lv.y*in_col,1);
}
]==]

function update_shader(  )

evolve_shader=shaders.Make(string.format([==[
#version 330

out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform vec4 params;
uniform float dt;
uniform vec2 diffuse;
uniform float kill;
uniform float feed;
uniform float init;

#define DX(dx,dy) textureOffset(values,normed,ivec2(dx,dy)).xy
vec2 actual_diffuse(vec2 dif,vec2 pos)
{
	float r=length(pos);

	return vec2(dif.x*(1-pos.x*pos.x),dif.y*(1-r));
}
vec2 calc_new_value(vec2 last_v)
{
	vec2 normed=(pos.xy+vec2(1,1))/2;

	/*
	vec2 coord=pos.xy;
	float rad=length(coord);
	float ang=atan(coord.y,coord.x);
	coord=vec2(rad,ang);
	*/

	vec2 a=DX(-1,0);
	vec2 b=DX(0,1);
	vec2 c=DX(0,-1);
	vec2 d=DX(1,0);

	vec2 e=DX(-1,-1);
	vec2 f=DX(1,1);
	vec2 g=DX(1,-1);
	vec2 h=DX(-1,1);
	float main_dir_power=0.8;
	vec2 lap=(main_dir_power/4)*(a+b+c+d)+(1-main_dir_power)/4*(e+f+g+h)-last_v;

	vec2 adif=actual_diffuse(diffuse,pos.xy);

	vec2 ret=vec2(%s,%s);
	return ret;
}
float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}
float rand2(vec2 n) { 
	return fract(sin(dot(n, vec2(974.2111, 8777.2444))) * 20123.5453);
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 last_v=DX(0,0);
	vec2 in_v=calc_new_value(last_v);
	vec2 nv=in_v;
	/*if(pos.x<-0.95)
		nv=vec2(0,0);
	if(pos.x>0.95)
		nv=vec2(1,0);*/

	//nv+=vec2(0,clamp(1-length(pos),0,1)/2000);

	if(init>0.5)
	{
		if(length(pos)<0.05 && length(pos)>0.025)
			nv=vec2(0.0,1);
		else
			nv=vec2(1,0);
		//nv=vec2(rand(pos.xy),rand2(pos.xy));
	}
	nv=clamp(nv,0,1);
	color=vec4(nv.x,nv.y,0,1);
}
]==],str_x,str_y))
end
update_shader()

function rnd( v )
	return math.random()*(v*2)-v
end
--last_v.x+(diffuse.x*lap.x-last_v.x*last_v.y*last_v.y+feed*(1-last_v.x))*dt
local terminal_symbols={
--["coord.x"]=5,--[[["coord.y"]=5,]]
--["a"]=1,["b"]=1,["c"]=1,["d"]=1,
--["e"]=1,["f"]=1,["g"]=1,["h"]=1,
--["lap.x"]=1,["lap.y"]=1,
["last_v.x"]=25,["last_v.y"]=25,
["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,
--["dt"]=1,["feed"]=1,["kill"]=1,
}
local normal_symbols={["max(R,R)"]=0.05,["min(R,R)"]=0.05,["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,["abs(R)"]=0.1,["sqrt(R)"]=0.1,["exp(R)"]=0.01,["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,["log(R)"]=1,["(R)/(R)"]=2,["(R)*(R)"]=15,["(R)-(R)"]=10,["(R)+(R)"]=10}

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
function random_math( steps,seed )
	local cur_string=seed or "R"

	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end

	for i=1,steps do
		cur_string=string.gsub(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
function random_math_react_diffuse( steps,seed )
	local cur_string=seed or "R"
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end

	for i=1,steps do
		cur_string=string.gsub(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
noise=false
local need_save
function save_img(  )
	make_img_buf()
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	config_serial=config_serial..string.format("str_x=%q\n",str_x)
	config_serial=config_serial..string.format("str_y=%q\n",str_y)
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function calc_norms(  )
	values_tex.t:use(0,1)
	values_tex.buf:read_texture(values_tex.t)

	local lmax=0
	local lmin=math.huge
	for x=0,values_tex.buf.w-1 do
	for y=0,values_tex.buf.h-1 do
		local v=values_tex.buf:get(x,y)
		if v>0 then --skip non-visited tiles
			if lmax<v then lmax=v end
			if lmin>v then lmin=v end
		end
	end
	end

	lmax=math.log(math.abs(lmax)+1)
	lmin=math.log(math.abs(lmin)+1)
	return lmax,lmin
end
function update()
	make_visits_texture()

	__no_redraw()
	__clear()
	imgui.Begin("isolines")
	draw_config(config)
	if imgui.Button("RandMath") then
		print("===============================")
		local tstr=random_math(config.complexity)

		str_x=string.format("last_v.x+(adif.x*lap.x-%s+feed*(1-last_v.x))*dt",tstr)
		str_y=string.format("last_v.y+(adif.y*lap.y+%s-(kill+feed)*(last_v.y))*dt",tstr)
		print(str_x)
		print(str_y)
		update_shader()
		noise=true
	end
	imgui.SameLine()
	if imgui.Button("NOISE!") then
		noise=true
	end
	imgui.SameLine()
	if imgui.Button("save") then
		need_save=true
	end
	imgui.End()
	for i=3,#config do
		if config[i].changing then
			noise=true
			break
		end
	end
	local tt=values_tex.t
	values_tex.t=values_tex.t_alt
	values_tex.t_alt=tt

	evolve_shader:use()
	values_tex.t_alt:use(0)
	if noise then
		evolve_shader:set_f("init",1)
		noise=false
	else
		evolve_shader:set_f("init",0)
	end
	evolve_shader:set_i("values",0)
	evolve_shader:set("params",config.v0,config.v1,config.v2,config.v3)
	evolve_shader:set("dt",config.dt)
	evolve_shader:set("diffuse",config.diffuse_x,config.diffuse_y)
	evolve_shader:set("kill",config.kill)
	evolve_shader:set("feed",config.feed)
	if not values_tex.t:render_to(values_tex.w,values_tex.h) then
		error("failed to set framebuffer up")
	end
	evolve_shader:draw_quad()
	__render_to_window()

	--local low,high=calc_norms()

	draw_shader:use()
	values_tex.t:use(0)
	draw_shader:set("line_w",config.line_w)
	draw_shader:set_i("values",0)
	--draw_shader:set("limits",low,high)
	draw_shader:set("in_col",config.color[1],config.color[2],config.color[3],config.color[4])
	draw_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end