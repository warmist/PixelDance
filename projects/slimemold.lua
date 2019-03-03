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
local agent_count=1024
--[[ perf:
	oversample 2 768x768
		ac: 3000 -> 43fps
			no_steps ->113fps
			no_tracks ->43fps
		gpu: 200*200 (40k)->35 fps
	map: 1024x1024
		200*200 -> 180 fps

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

if agent_data==nil or agent_data.w~=agent_count or agent_data.h~=agent_count then
	agent_data=make_flt_buffer(agent_count,agent_count)
	for i=0,agent_count-1 do
		for j=0,agent_count-1 do
			agent_data:set(i,j,{math.random()*map_w,math.random()*map_h,math.random()*math.pi*2,0})
		end
	end
end



update_buffers()
config=make_config({
    {"pause",false,type="bool"},
    {"color_back",{0,0,0,1},type="color"},
    {"color_fore",{0.18,0,0.58,1},type="color"},
    {"color_turn_around",{0.54,0.80,0.71,1},type="color"},
    --system
    {"decay",0.99,type="float"},
    {"diffuse",0.5,type="float"},
    --agent
    {"ag_sensor_distance",9,type="float",min=0.1,max=10},
    --{"ag_sensor_size",1,type="int",min=1,max=3},
    {"ag_sensor_angle",math.pi/2,type="float",min=0,max=math.pi/2},
    {"ag_turn_angle",math.pi/2,type="float",min=0,max=math.pi/2},
	{"ag_step_size",1,type="float",min=0.1,max=10},
	{"ag_trail_amount",0.019,type="float",min=0,max=0.5},
	{"trail_size",2,type="int",min=1,max=5},
	{"turn_around",0.969,type="float",min=0,max=5},
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
	color=vec4(r*decay,0,0,1);
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
function add_trails(  )
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
	add_visit_shader:draw_points(agent_data.d,agent_data.w*agent_data.h,4)

	add_visit_shader:blend_default()
	__render_to_window()
end
local draw_shader=shaders.Make[==[
#version 330
#line 40
out vec4 color;
in vec3 pos;

uniform ivec2 rez;
uniform sampler2D tex_main;

uniform float turn_around;
uniform vec4 color_back;
uniform vec4 color_fore;
uniform vec4 color_turn_around;
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    //normed=normed/zoom+translate;

    vec4 pixel=texture(tex_main,normed);
    //float v=log(pixel.x+1);
    //float v=pow(pixel.x/3,2.4);
    float v=pixel.x/turn_around;
    if(v<1)
    	color=mix(color_back,color_fore,v);
    else
    	color=mix(color_fore,color_turn_around,clamp((v-1)*1,0,1));
}
]==]
local agent_logic_shader=shaders.Make[==[
#version 330
#line 121
out vec4 color;
in vec3 pos;

uniform vec2 rez;

#define M_PI 3.14159265358979323846

uniform sampler2D old_state; //old agent state
uniform sampler2D tex_main;  //signal buffer state
//agent settings uniforms
uniform float ag_sensor_distance;
uniform float ag_sensor_angle;
uniform float ag_turn_angle;
uniform float ag_step_size;
uniform float ag_turn_around;
//
float rand(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x))));}

#define M_PI 3.1415926535897932384626433832795

float sample_heading(vec2 p,float h,float dist)
{
	p+=vec2(cos(h),sin(h))*dist;
	return texture(tex_main,p/rez).x;
}
#define TURNAROUND
void main(){
	float step_size=ag_step_size;
	float sensor_distance=ag_sensor_distance;
	float sensor_angle=ag_sensor_angle;
	float turn_size=ag_turn_angle;
	float turn_around=ag_turn_around;

	vec2 normed=(pos.xy+vec2(1,1))/2;

	vec3 state=texture(old_state,normed).xyz;
	//figure out new heading
	float head=state.z;
	float fow=sample_heading(state.xy,head,sensor_distance);
	float lft=sample_heading(state.xy,head-sensor_angle,sensor_distance);
	float rgt=sample_heading(state.xy,head+sensor_angle,sensor_distance);

	if(fow<lft && fow<rgt)
	{
		head+=(rand(pos.xy+state.xy*4572)-0.5)*turn_size*2;
	}
	else if(rgt>fow)
	{
	#ifdef TURNAROUND
		if(rgt>=turn_around)
			head+=turn_size+M_PI;
		else
	#endif
			head+=turn_size;
	}
	else if(lft>fow)
	{
	#ifdef TURNAROUND
		if(lft>=turn_around)
			head-=turn_size+M_PI;
		else
	#endif
			head-=turn_size;
	}
	#ifdef TURNAROUND
	else if(fow>turn_around)
	{
		head+=M_PI;//(rand(pos.xy+state.xy*4572)-0.5)*turn_size*2;
	}
	#endif
	//step in heading direction
	state.xy+=vec2(cos(head)*step_size,sin(head)*step_size);
	state.z=head;
	state.xy=mod(state.xy,rez);
	color=vec4(state.xyz,1);
}
]==]
if tex_agent == nil then
	tex_agent=textures:Make()
	tex_agent:use(1)
	tex_agent:set(agent_count,agent_count,1)
end
if tex_agent_result==nil then
	tex_agent_result=textures:Make()
	tex_agent_result:use(1)
	tex_agent_result:set(agent_count,agent_count,1)
end

function do_agent_logic(  )
	agent_logic_shader:use()
    tex_pixel:use(0)
    agent_logic_shader:set_i("tex_main",0)
	tex_agent:use(1)
	agent_logic_shader:set_i("old_state",1)
	tex_agent_result:use(2)

	--set agent uniforms
	agent_logic_shader:set("ag_sensor_distance",config.ag_sensor_distance)
	agent_logic_shader:set("ag_sensor_angle",config.ag_sensor_angle)
	agent_logic_shader:set("ag_turn_angle",config.ag_turn_angle)
	agent_logic_shader:set("ag_step_size",config.ag_step_size)
	agent_logic_shader:set("ag_turn_around",config.turn_around)
	--
	agent_logic_shader:set("rez",map_w,map_h)
    if not tex_agent_result:render_to(agent_count,agent_count) then
		error("failed to set framebuffer up")
	end
    agent_logic_shader:draw_quad()
    __render_to_window()
    --swap buffers
    local t=tex_agent_result
    tex_agent_result=tex_agent
    tex_agent=t
end
function agents_tocpu()
	tex_agent:use(0)
	agent_data:read_texture(tex_agent)
end
function agents_togpu()
	tex_agent:use(0)
	agent_data:write_texture(tex_agent)
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

function wrap_pos( pos )
	local w=signal_buf.w
	local h=signal_buf.h
	if pos[1]<0 then pos[1]=pos[1]+w end
	if pos[1]>=w then pos[1]=pos[1]-w end
	if pos[2]<0 then pos[2]=pos[2]+h end
	if pos[2]>=h then pos[2]=pos[2]-h end
end
function sense( pos,size )
	local tx=math.floor(pos[1])
	local ty=math.floor(pos[2])

	local sum=0
	local wsum=0
	for di=-size,size do
		for dj=-size,size do
			local ti=tx+di
			local tj=ty+dj
			if ti <0 then ti = signal_buf.w-1 end
			if ti >=signal_buf.w then ti = 0 end
			if tj <0 then tj = signal_buf.h-1 end
			if tj >=signal_buf.h then tj = 0 end
			local w=1--todo: sensing decay due to distance
			if di==0 and dj==0 then
				w=1
			end
			sum=sum+signal_buf:get(ti,tj)*w
			wsum=wsum+w
		end
	end
	return sum/wsum
end

function agent_tracks(  )
	local agent_track_amount=config.ag_trail_amount
	for i=0,agent_count-1 do
		for j=0,agent_count-1 do
			local p=agent_data:get(i,j)
			local tx=math.floor(p.r) % signal_buf.w
			local ty=math.floor(p.g) % signal_buf.h

			local new_val=signal_buf:get(tx,ty)+agent_track_amount
			--if new_val>1 then new_val=1 end
			signal_buf:set(tx,ty,new_val)
		end
	end
end
function agents_step(  )


	do_agent_logic()

	agents_tocpu()
	-- [[
	add_trails()
	--]]
	--[[
	tex_pixel:use(0)
	signal_buf:read_texture(tex_pixel)
	agent_tracks()
	tex_pixel:use(0)
	signal_buf:write_texture(tex_pixel)
	--]]
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
    decay_diffuse_shader:set("diffuse",config.diffuse)
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
    		for j=0,agent_count-1 do
    		--[[
    		local r=map_w/5+rnd(10)
    		local phi=math.random()*math.pi*2
    		agent_data:set(i,j,
    			{math.cos(phi)*r+map_w/2,
    			 math.sin(phi)*r+map_h/2,
    			 math.random()*math.pi*2,
    			 0})
    		--]]
    		local a = math.random() * 2 * math.pi
			local r = map_w/8 * math.sqrt(math.random())
			local x = r * math.cos(a)
			local y = r * math.sin(a)
			agent_data:set(i,j,
    			{math.cos(a)*r+map_w/2,
    			 math.sin(a)*r+map_h/2,
    			 a+math.pi,
    			 0})
			end
    	end
    	agents_togpu()
    end
    imgui.End()
    -- [[
    if not config.pause then
        agents_step()
        diffuse_and_decay()
    end
    --if config.draw then

    draw_shader:use()
    tex_pixel:use(0)

    --tex_pixel.t:set(size[1]*oversample,size[2]*oversample,3)
    --signal_buf:write_texture(tex_pixel)

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