--from: https://sagejenson.com/physarum
--[[
	ideas:
		add other types of agents
		more interactive "world"
			* eatible food
			* sand-like sim?
			* more senses (negative?)
		mass and non-instant turning
--]]

require 'common'
local win_w=1024
local win_h=1024

__set_window_size(win_w,win_h)
local oversample=1
local agent_count=1e7
--[[ perf:
	oversample 2 768x768
		ac: 3000 -> 43fps
			no_steps ->113fps
			no_tracks ->43fps
		gpu: 200*200 (40k)->35 fps
	map: 1024x1024
		200*200 -> 180 fps
	feedback: 
		RTX 2060
			33554432 ~20fps
			1e7 ~60fps

]]
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)
is_remade=false
function update_buffers(  )
    local nw=map_w
    local nh=map_h

    if signal_buf==nil or signal_buf.w~=nw or signal_buf.h~=nh then
    	tex_pixel=textures:Make()
    	tex_pixel:use(0)
        signal_buf=make_float_buffer(nw,nh)
        signal_buf:write_texture(tex_pixel)
        is_remade=true
    end
end

if agent_data==nil or agent_data.w~=agent_count then
	agent_data=make_flt_buffer(agent_count,1)
	agent_buffers={buffer_data.Make(),buffer_data.Make(),current=1,other=2,flip=function( t )
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

	for i=0,agent_count-1 do
			agent_data:set(i,0,{math.random()*map_w,math.random()*map_h,math.random()*math.pi*2,0})
	end
	for i=1,2 do
		agent_buffers[i]:use()
		agent_buffers[i]:set(agent_data.d,agent_count*4*4)
	end
end
-- [[
local bwrite = require "blobwriter"
local bread = require "blobreader"
function read_background_buf( fname )
	local file = io.open(fname, 'rb')
	local b = bread(file:read('*all'))
	file:close()

	local sx=b:u32()
	local sy=b:u32()
	background_buf=make_float_buffer(sx,sy)
	background_minmax={}
	background_minmax[1]=b:f32()
	background_minmax[2]=b:f32()
	for x=0,background_buf.w-1 do
	for y=0,background_buf.h-1 do
		local v=(math.log(b:f32()+1)-background_minmax[1])/(background_minmax[2]-background_minmax[1])
		background_buf:set(x,y,v)
	end
	end
end
function make_background_texture()
	if background_tex==nil then
		print("making tex")
		read_background_buf("out.buf")
		background_tex={t=textures:Make(),w=background_buf.w,h=background_buf.h}
		background_tex.t:use(0,1)
		background_buf:write_texture(background_tex.t)
		__unbind_buffer()
	end
end
make_background_texture()
--]]
update_buffers()
config=make_config({
    {"pause",false,type="bool"},
    {"color_back",{0,0,0,1},type="color"},
    {"color_fore",{0.98,0.6,0.05,1},type="color"},
    {"color_turn_around",{0.99,0.99,0.991,1},type="color"},
    --system
    {"decay",0.995181,type="floatsci",min=0.99,max=1},
    --{"diffuse",0.5,type="float"},
    --agent
    {"ag_sensor_distance",4,type="float",min=0.1,max=10},
    --{"ag_sensor_size",1,type="int",min=1,max=3},
    {"ag_sensor_angle",math.pi/2,type="float",min=0,max=math.pi/2},
    {"ag_turn_angle",math.pi/8,type="float",min=-math.pi/2,max=math.pi/2},
    {"ag_turn_avoid",-math.pi/8,type="float",min=-math.pi/2,max=math.pi/2},
	{"ag_step_size",2.431,type="float",min=0.01,max=10},
	{"ag_trail_amount",0.013,type="float",min=0,max=0.5},
	{"trail_size",1,type="int",min=1,max=5},
	{"turn_around",10,type="float",min=0,max=5},
    },config)

local decay_diffuse_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform float diffuse;
uniform float decay;

uniform sampler2D tex_main;

float sample_around(vec2 pos)
{
	float ret=0;
	ret+=textureOffset(tex_main,pos,ivec2(-1,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,1)).x;

	ret+=textureOffset(tex_main,pos,ivec2(0,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(0,1)).x;
	return ret/8;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float r=sample_around(normed)*diffuse;
	r+=texture(tex_main,normed).x*(1-diffuse);
	r*=decay;
	//r=clamp(r,0,1);
	color=vec4(r,0,0,1);
}
]==]

add_visit_shader=shaders.Make(
[==[
#version 330
#line 105
layout(location = 0) in vec4 position;

uniform int pix_size;
uniform float seed;
uniform float move_dist;
uniform vec4 params;
uniform vec2 rez;

void main()
{
	vec2 normed=(position.xy/rez)*2-vec2(1,1);
	gl_Position.xy = normed;//mod(normed,vec2(1,1));
	gl_PointSize=pix_size;
	gl_Position.z = 0;
    gl_Position.w = 1.0;
}
]==],
[==[
#version 330
#line 125

out vec4 color;
//in vec3 pos;
uniform int pix_size;
uniform float trail_amount;
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
#if 0
	float delta_size=shape_point(pos.xy);
#else
	float delta_size=1;
#endif
 	float r = 2*length(gl_PointCoord - 0.5)/(delta_size);
	float a = 1 - smoothstep(0, 1, r);
	float intensity=1/float(pix_size);
	//rr=clamp((1-rr),0,1);
	//rr*=rr;
	//color=vec4(a,0,0,1);
	color=vec4(a*intensity*trail_amount,0,0,1);
	//color=vec4(1,0,0,1);
}
]==])
function add_trails_fbk(  )
	add_visit_shader:use()
	tex_pixel:use(0)
	add_visit_shader:blend_add()
	add_visit_shader:set_i("pix_size",config.trail_size)
	add_visit_shader:set("trail_amount",config.ag_trail_amount)
	add_visit_shader:set("rez",map_w,map_h)
	if not tex_pixel:render_to(map_w,map_h) then
		error("failed to set framebuffer up")
	end
	if need_clear then
		__clear()
		need_clear=false
		--print("Clearing")
	end
	agent_buffers:get_current():use()
	add_visit_shader:draw_points(0,agent_count,4)

	add_visit_shader:blend_default()
	__render_to_window()
	__unbind_buffer()
end
local draw_shader=shaders.Make[==[
#version 330
#line 209
out vec4 color;
in vec3 pos;

uniform ivec2 rez;
uniform sampler2D tex_main;

uniform float turn_around;
uniform vec4 color_back;
uniform vec4 color_fore;
uniform vec4 color_turn_around;

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

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
float lerp_hue(float h1,float h2,float v )
{
	if (abs(h1-h2)>0.5){
		//loop around lerp (i.e. modular lerp)
			float v2=(h1-h2)*v+h1;
			if (v2<0){
				float a1=h2-h1;
				float a=((1-h2)*a1)/(h1-a1);
				float b=h2-a;
				v2=(a)*(v)+b;
			}
			return v2;
		}
	else
		return mix(h1,h2,v);
}
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec4 mix_hsl(vec4 c1,vec4 c2,float v)
{
	vec3 c1hsv=rgb2hsv(c1.xyz);
	vec3 c2hsv=rgb2hsv(c2.xyz);

	vec3 ret;
	ret.x=lerp_hue(c1hsv.x,c2hsv.x,v);
	ret.yz=mix(c1hsv.yz,c2hsv.yz,v);
	float a=mix(c1.a,c2.a,v);
	return vec4(hsv2rgb(ret.xyz),a);
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    //normed=normed/zoom+translate;

    vec4 pixel=texture(tex_main,normed);
    //float v=log(pixel.x+1);
    float v=pow(pixel.x/turn_around,1);
    //float v=pixel.x/turn_around;
    //float v=gain(pixel.x/turn_around,-0.8);
    //v=noise(pos.xy*rez/100);
    ///*
    if(v<1)
    	color=mix(color_back,color_fore,v);
    else
    	color=mix(color_fore,color_turn_around,clamp((v-1)*1,0,1));
	//*/
    /*
    if(v<1)
    	color=mix_hsl(color_back,color_fore,v);
    else
    	color=mix_hsl(color_fore,color_turn_around,clamp((v-1)*1,0,1));
    //*/

    /*if(v<1)
    	color=vec4(palette(v,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.5,2.5,1.5),vec3(0.5,1.5,1.0)),1);
    else
    {
    	float tv=clamp((v-1),0,1);
    	color=vec4(palette(tv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.0,0.5,2.5),vec3(0.5,1.5,1.0)),1);
    }*/
}
]==]
local agent_logic_shader_fbk=shaders.Make(
[==[

#version 330
#line 388
layout(location = 0) in vec4 position;
out vec4 state_out;

uniform sampler2D tex_main;  //signal buffer state
uniform sampler2D background;
uniform vec2 background_swing;

uniform vec2 rez;

//agent settings uniforms
uniform float ag_sensor_distance;
uniform float ag_sensor_angle;
uniform float ag_turn_angle;
uniform float ag_step_size;
uniform float ag_turn_around;
uniform float ag_turn_avoid;
//
//float rand(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x))));}

#define M_PI 3.1415926535897932384626433832795
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
float sample_heading(vec2 p,float h,float dist)
{
	p+=vec2(cos(h),sin(h))*dist;
	return texture(tex_main,p/rez).x;
}
#define TURNAROUND
float cubicPulse( float c, float w, float x )
{
    x = abs(x - c);
    if( x>w ) return 0.0;
    x /= w;
    return 1.0 - x*x*(3.0-2.0*x);
}
float expStep( float x, float k, float n )
{
    return exp( -k*pow(x,n) );
}
float sample_back(vec2 pos)
{
	//return (log(texture(background,pos).x+1)-background_swing.x)/(background_swing.y-background_swing.x);
	return clamp(texture(background,pos).x,0,1);
}
void main(){
	float step_size=ag_step_size;
	float sensor_distance=ag_sensor_distance;
	float sensor_angle=ag_sensor_angle;
	float turn_size=ag_turn_angle;
	float turn_size_neg=ag_turn_around;
	float turn_around=ag_turn_around;


	vec3 state=position.xyz;
	vec2 normed_state=state.xy/rez;
	vec2 normed_p=(normed_state)*2-vec2(1,1);
	float tex_sample=sample_back(normed_state);//cubicPulse(0.6,0.3,abs(normed_p.x));//;

	float pl=length(normed_p);

	//sensor_distance*=tex_sample*0.8+0.2;
	//sensor_distance*=state.x/rez.x;

	//sensor_distance*=1-cubicPulse(0.1,0.5,abs(normed_p.x));
	//sensor_distance=clamp(sensor_distance,2,15);

	//turn_around*=noise(state.xy/100);
	//turn_around-=cubicPulse(0.6,0.3,abs(normed_p.x));
	//turn_around*=tex_sample+0.5;
	//clamp(turn_around,0.2,5);
	//figure out new heading
	sensor_angle*=tex_sample*.95+.05;
	//turn_size*=tex_sample*.9+0.1;
	//turn_size_neg*=tex_sample*.9+0.1;

	float head=state.z;
	float fow=sample_heading(state.xy,head,sensor_distance);

	float lft=sample_heading(state.xy,head-sensor_angle,sensor_distance);
	float rgt=sample_heading(state.xy,head+sensor_angle,sensor_distance);

	if(fow<lft && fow<rgt)
	{
		head+=(rand(position.xy*position.z*9999+state.xy*4572)-0.5)*turn_size*2;
	}
	else if(rgt>fow)
	{
		//float ov=(rgt-fow)/fow;
	#ifdef TURNAROUND
		if(rgt>=turn_around)
			//step_size*=-1;
			head+=turn_size_neg;
		else
	#endif
			head+=turn_size;
	}
	else if(lft>fow)
	{
		//float ov=(lft-fow)/fow;
	#ifdef TURNAROUND
		if(lft>=turn_around)
			//step_size*=-1;
			head-=turn_size_neg;
		else
	#endif
			head-=turn_size;
	}
	#ifdef TURNAROUND
	else 
	#endif
	if(fow>turn_around)
	{
		//head+=(rand(position.xy*position.z*9999+state.xy*4572)-0.5)*turn_size*2;
		//head+=M_PI;//turn_size*2;//(rand(position.xy+state.xy*4572)-0.5)*turn_size*2;
		//step_size*=-1;
		head+=rand(position.xy*position.z*9999+state.xy*4572)*turn_size_neg;
		//head+=turn_size_neg;

	}
	//step_size/=clamp(rgt/lft,0.5,2);


	/* turn head to center somewhat (really stupid way of doing it...)
	vec2 c=rez/2;
	vec2 d_c=(c-state.xy);
	d_c*=1/sqrt(dot(d_c,d_c));
	vec2 nh=vec2(cos(head),sin(head));
	float T_c=0.1;
	vec2 new_h=d_c*T_c+nh*(1-T_c);
	new_h*=1/sqrt(dot(new_h,new_h));
	head=atan(new_h.y,new_h.x);
	//*/
	//step_size*=1-clamp(cubicPulse(0,0.1,fow),0,1);
	//step_size*=1-cubicPulse(0,0.4,abs(pl))*0.5;
	//step_size*=(clamp(fow/turn_around,0,1))*0.95+0.05;
	//step_size*=noise(state.xy/100);
	//step_size*=expStep(abs(pl-0.2),1,2);
	step_size*=tex_sample*0.9+0.1;
	step_size=clamp(step_size,0.001,100);

	//step in heading direction
	state.xy+=vec2(cos(head)*step_size,sin(head)*step_size);
	state.z=head;
	state.xy=mod(state.xy,rez);
	state_out=vec4(state.xyz,position.w);

}
]==]
,[===[
void main()
{

}
]===],"state_out")

function do_agent_logic_fbk(  )

	agent_logic_shader_fbk:use()

    tex_pixel:use(0)
    agent_logic_shader_fbk:set_i("tex_main",0)
	--if background_tex~=nil then
	    background_tex.t:use(1)
	    agent_logic_shader_fbk:set_i("background",1)
	    agent_logic_shader_fbk:set("background_swing",background_minmax[1],background_minmax[2])
	--end
	agent_logic_shader_fbk:set("ag_sensor_distance",config.ag_sensor_distance)
	agent_logic_shader_fbk:set("ag_sensor_angle",config.ag_sensor_angle)
	agent_logic_shader_fbk:set("ag_turn_angle",config.ag_turn_angle)
	agent_logic_shader_fbk:set("ag_step_size",config.ag_step_size)
	agent_logic_shader_fbk:set("ag_turn_around",config.turn_around)
	agent_logic_shader_fbk:set("ag_turn_avoid",config.ag_turn_avoid)
	agent_logic_shader_fbk:set("rez",map_w,map_h)

	agent_logic_shader_fbk:raster_discard(true)
	local ao=agent_buffers:get_other()
	ao:use()
	ao:bind_to_feedback()

	local ac=agent_buffers:get_current()
	ac:use()
	agent_logic_shader_fbk:draw_points(0,agent_count,4,1)
	__flush_gl()
	agent_logic_shader_fbk:raster_discard(false)
	--__read_feedback(agent_data.d,agent_count*agent_count*4*4)
	--print(agent_data:get(0,0).r)
	agent_buffers:flip()
	__unbind_buffer()
end
function agents_tocpu()
	--tex_agent:use(0)
	--agent_data:read_texture(tex_agent)
	agent_buffers:get_current():use()
	agent_buffers:get_current():get(agent_data.d,agent_count*4*4)
end
function agents_togpu()
	--tex_agent:use(0)
	--agent_data:write_texture(tex_agent)

	agent_buffers:get_current():use()
	agent_buffers:get_current():set(agent_data.d,agent_count*4*4)
	__unbind_buffer()
end
function fill_buffer(  )
	tex_pixel:use(0)
	signal_buf:read_texture(tex_pixel)
	for i=0,map_w-1 do
    	for j=0,map_h-1 do
    		signal_buf:set(math.floor(i),math.floor(j),math.random()*0.1)
    	end
    end
    signal_buf:write_texture(tex_pixel)
end
function agents_step_fbk(  )

	do_agent_logic_fbk()
	add_trails_fbk()

end
function diffuse_and_decay(  )
	if tex_pixel_alt==nil or is_remade then
		tex_pixel_alt=textures:Make()
		tex_pixel_alt:use(1)
		tex_pixel_alt:set(signal_buf.w,signal_buf.h,2)
		is_remade=false
	end
	decay_diffuse_shader:use()
    tex_pixel:use(0)
    --tex_pixel.t:set(size[1]*oversample,size[2]*oversample,3)
    decay_diffuse_shader:set_i("tex_main",0)
    decay_diffuse_shader:set("decay",config.decay)
    decay_diffuse_shader:set("diffuse",0.5)
    if not tex_pixel_alt:render_to(signal_buf.w,signal_buf.h) then
		error("failed to set framebuffer up")
	end
    decay_diffuse_shader:draw_quad()
    __render_to_window()
    local t=tex_pixel_alt
    tex_pixel_alt=tex_pixel
    tex_pixel=t
end
function save_img(  )
	img_buf=img_buf or make_image_buffer(win_w,win_h)
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function rnd( v )
	return math.random()*v*2-v
end
function update()
    __clear()
    __no_redraw()
    __render_to_window()

    imgui.Begin("slimemold")
    draw_config(config)
    if imgui.Button("Save") then
        need_save=true
    end
    imgui.SameLine()
    if imgui.Button("Fill") then
    	fill_buffer()
    end
     imgui.SameLine()
    if imgui.Button("Clear") then
    	tex_pixel:use(0)
		--signal_buf:read_texture(tex_pixel)
		for x=0,signal_buf.w-1 do
		for y=0,signal_buf.h-1 do
			signal_buf:set(x,y,0)
		end
		end
		signal_buf:write_texture(tex_pixel)
    end
    imgui.SameLine()
    if imgui.Button("Agentswarm") then
    	for i=0,agent_count-1 do
    		-- [[
    		agent_data:set(i,0,
    			{math.random(0,map_w-1),
    			 math.random(0,map_h-1),
    			 math.random()*math.pi*2,
    			 0})
    		--]]
    		--[[
    		local r=map_w/5+rnd(10)
    		local phi=math.random()*math.pi*2
    		agent_data:set(i,j,
    			{math.cos(phi)*r+map_w/2,
    			 math.sin(phi)*r+map_h/2,
    			 math.random()*math.pi*2,
    			 0})
    		--]]
    		--[[
    		local a = math.random() * 2 * math.pi
			local r = map_w/8 * math.sqrt(math.random())
			local x = r * math.cos(a)
			local y = r * math.sin(a)
			agent_data:set(i,0,
    			{math.cos(a)*r+map_w/2,
    			 math.sin(a)*r+map_h/2,
    			 a+math.pi/4,
    			 math.random()*10})
    		--]]
    		--[[
    		local side=math.random(1,4)
    		local x,y
    		if side==1 then
    			x=math.random()*map_w
    			y=0
    		elseif side==2 then
    			x=math.random()*map_w
    			y=map_h-1
			elseif side==3 then
    			x=map_w-1
				y=math.random()*map_h
			else
				x=0
				y=math.random()*map_h
			end
			--local d=math.sqrt(x*x+y*y)
			local a=math.atan(y-map_h/2,x-map_w/2)
			agent_data:set(i,j,
    			{x,
    			 y,
    			 a+math.pi,
    			 0})
			--]]
    	end
    	agents_togpu()
    end
    imgui.SameLine()
    if imgui.Button("ReloadBuffer") then
		background_tex=nil
		make_background_texture()
	end
    imgui.End()
    -- [[
    if not config.pause then
        --agents_step()
        agents_step_fbk()
        diffuse_and_decay()
    end
    --if config.draw then

    draw_shader:use()
    tex_pixel:use(0)

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("rez",map_w,map_h)
    draw_shader:set("turn_around",config.turn_around)
    draw_shader:set("color_back",config.color_back[1],config.color_back[2],config.color_back[3],config.color_back[4])
    draw_shader:set("color_fore",config.color_fore[1],config.color_fore[2],config.color_fore[3],config.color_fore[4])
    draw_shader:set("color_turn_around",config.color_turn_around[1],config.color_turn_around[2],config.color_turn_around[3],config.color_turn_around[4])
    --draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
    --draw_shader:set("translate",config.t_x,config.t_y)
    --draw_shader:set("sun_color",config.color[1],config.color[2],config.color[3],config.color[4])
    draw_shader:draw_quad()
    --end

    if need_save then
        save_img()
        need_save=false
    end

end
