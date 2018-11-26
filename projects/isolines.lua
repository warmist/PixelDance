require 'common'

__set_window_size(1024,1024)
local aspect_ratio=1024/1024
local size=STATE.size

local oversample=1
str_x=str_x or "last_v"

config=make_config({
	{"v0",0,type="float",min=0,max=1},
	{"v1",0,type="float",min=0,max=1},
	{"v2",0,type="float",min=0,max=1},
	{"v3",0,type="float",min=0,max=1},
	{"decay",0.5,type="float",min=0,max=1},
	{"evolution",0.5,type="float",min=0,max=1},
	{"complexity",1,type="int",min=1,max=10},
	{"line_w",0.01,type="float",min=0,max=1},
	},config)

function make_visits_texture()
	if values_tex==nil or values_tex.w~=size[1]*oversample or values_tex.h~=size[2]*oversample then
		print("making tex")
		values_tex={t=textures:Make(),t_alt=textures:Make(),w=size[1]*oversample,h=size[2]*oversample,
		buf=make_float_buffer(size[1]*oversample,size[2]*oversample)}

		values_tex.t:use(0,1)
		values_tex.t:set(size[1]*oversample,size[2]*oversample,2)

		values_tex.t_alt:use(0,1)
		values_tex.t_alt:set(size[1]*oversample,size[2]*oversample,2)
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

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float lv=log(abs(texture(values,normed).x)+1);

	float v=clamp((lv-limits.x)/(limits.y-limits.x),0,1);
	float w=line_w;
	float vv=clamp(smoothstep(0.5-w,0.5,v)-smoothstep(0.5,0.5+w,v),0,1);
	//color=vec4(vv*0.8,0,0,1);
	color=vec4(v*0.8,0,0,1);
}
]==]

function update_shader(  )

evolve_shader=shaders.Make(string.format([==[
#version 330

out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform vec4 params;
uniform float decay;
uniform float evolution;
uniform float init;

#define DX(dx,dy) textureOffset(values,normed,ivec2(dx,dy)).x
float calc_new_value(float last_v)
{
	vec2 normed=(pos.xy+vec2(1,1))/2;

	vec2 coord=pos.xy;
	float rad=length(coord);
	float ang=atan(coord.y,coord.x);

	coord=vec2(rad,ang);

	float a=DX(-1,0);
	float b=DX(0,1);
	float c=DX(0,-1);
	float d=DX(1,0);

	float e=DX(-1,-1);
	float f=DX(1,1);
	float g=DX(1,-1);
	float h=DX(-1,1);

	float ret=%s;
	return ret+last_v;
}
float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float last_v=DX(0,0);
	float in_v=calc_new_value(last_v);
	//float nv=clamp(in_v,0,1);
	float nv=in_v;
	nv=mix(nv,0,decay);
	nv=mix(last_v,nv,evolution);
	/*if(pos.x<-0.95)
		nv=0;
	if(pos.x>0.95)
		nv=1;*/

	if(init>0.5)
	{
		nv=rand(pos.xy);
	}
	color=vec4(nv,0,0,1);
}
]==],str_x))
end
update_shader()

function rnd( v )
	return math.random()*(v*2)-v
end

local terminal_symbols={["coord.x"]=5,["coord.y"]=5,
["a"]=1,["b"]=1,["c"]=1,["d"]=1,
["e"]=1,["f"]=1,["g"]=1,["h"]=1,
["last_v"]=3,
["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1}
local normal_symbols={["max(R,R)"]=0.05,["min(R,R)"]=0.05,["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,["abs(R)"]=0.1,["sqrt(R)"]=0.1,["exp(R)"]=0.01,["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,["log(R)"]=1,["(R)/(R)"]=2,["(R)*(R)"]=3,["(R)-(R)"]=3,["(R)+(R)"]=3}

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
	config_serial=config_serial..string.format("str_preamble=%q\n",str_preamble)
	config_serial=config_serial..string.format("str_postamble=%q\n",str_postamble)
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
		str_x=random_math(config.complexity)
		print(str_x)
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
	evolve_shader:set("decay",config.decay)
	evolve_shader:set("evolution",config.evolution)
	if not values_tex.t:render_to(values_tex.w,values_tex.h) then
		error("failed to set framebuffer up")
	end
	evolve_shader:draw_quad()
	__render_to_window()

	local low,high=calc_norms()

	draw_shader:use()
	values_tex.t:use(0)
	draw_shader:set("line_w",config.line_w)
	draw_shader:set_i("values",0)
	draw_shader:set("limits",low,high)
	draw_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end