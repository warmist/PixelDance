--inspired : https://ciphered.xyz/2020/06/01/atomic-clusters-a-molecular-particle-based-simulation/


require 'common'
local win_w=1280
local win_h=1280
--[[
    agent is:
        pos (2)
        speed(2)
        angle, angular speed, type,??(4)

    fields is (i.e. signal buf)
        color (4)
--]]
__set_window_size(win_w,win_h)
local oversample=1
local agent_count=50--1e6

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)
is_remade=false
function update_buffers(  )
    local nw=map_w
    local nh=map_h

    if signal_buf==nil or signal_buf.w~=nw or signal_buf.h~=nh then
    	tex_pixel=textures:Make()
    	tex_pixel:use(0)
        signal_buf=make_flt_buffer(nw,nh)
        signal_buf:write_texture(tex_pixel)
        is_remade=true
    end
end
function make_double_buffer(  )
    return {buffer_data.Make(),buffer_data.Make(),current=1,other=2,flip=function( t )
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
end
if agent_data==nil or agent_data.count~=agent_count then
    agent_data={count=agent_count}
	agent_data.pos_speed=make_flt_buffer(agent_count,1)
    agent_data.angle_type=make_flt_buffer(agent_count,1)
    agent_buffers={}
	agent_buffers.pos_speed=make_double_buffer()
    agent_buffers.angle_type=make_double_buffer()

	for i=0,agent_count-1 do
        local ang=math.random()*math.pi*2
        local vx=math.cos(ang)
        local vy=math.sin(ang)
		agent_data.pos_speed:set(i,0,{math.random()*map_w,math.random()*map_h,vx,vy})
        agent_data.angle_type:set(i,0,{0,0,math.random()*255,0})
	end
	for i=1,2 do
		agent_buffers.pos_speed[i]:use()
		agent_buffers.pos_speed[i]:set(agent_data.pos_speed.d,agent_count*4*4)

        agent_buffers.angle_type[i]:use()
        agent_buffers.angle_type[i]:set(agent_data.angle_type.d,agent_count*4*4)
	end
    __unbind_buffer()
end

update_buffers()
config=make_config({
    {"pause",false,type="bool"},
    {"color_back",{0,0,0,1},type="color"},
    {"color_fore",{0.98,0.6,0.05,1},type="color"},
    --system
    {"friction",0.995181,type="floatsci",min=0.99,max=1},
    {"friction_angular",0.995181,type="floatsci",min=0.99,max=1},
    --agent
    {"ag_field_distance",100,type="int",min=1,max=500},
    },config)

add_fields_shader=shaders.Make(
[==[
#version 330
#line 105
layout(location = 0) in vec4 position;
layout(location = 1) in vec4 angle_type;

uniform int pix_size;
uniform float seed;
uniform float move_dist;
uniform vec4 params;
uniform vec2 rez;

out vec4 at;
void main()
{
	vec2 normed=(position.xy/rez)*2-vec2(1,1);
	gl_Position.xy = normed;//mod(normed,vec2(1,1));
	gl_PointSize=pix_size;
	gl_Position.z = 0;
    gl_Position.w = 1.0;

    at=angle_type;
}
]==],
[==[
#version 330
#line 125
in vec4 at;
out vec4 color;
uniform int pix_size;
uniform float trail_amount;
vec4 palette(float t,vec4 a,vec4 b,vec4 c,vec4 d)
{
    return a+b*cos(c+d*t*3.1459);
}
void main(){
    vec2 p = (gl_PointCoord - 0.5)*2;
 	float r = 1-length(p);
    r=clamp(r,0,1);
	color=palette(r,vec4(0.5),vec4(0.5),vec4(1.5*at.z,at.z,8*at.z,0),vec4(1,1,0,0))*r;
}
]==])
function add_fields_fbk(  )
	add_fields_shader:use()
	tex_pixel:use(0)
    add_fields_shader:blend_add()
	add_fields_shader:set_i("pix_size",config.ag_field_distance)
	add_fields_shader:set("rez",map_w,map_h)
	if not tex_pixel:render_to(map_w,map_h) then
		error("failed to set framebuffer up")
	end
    __clear()
	if need_clear then
		need_clear=false
		--print("Clearing")
	end
    agent_buffers.angle_type:get_current():use(1)
    add_fields_shader:push_attribute(0,"angle_type",4)
	agent_buffers.pos_speed:get_current():use()
	add_fields_shader:draw_points(0,agent_count,4)

	add_fields_shader:blend_default()
	__render_to_window()
	__unbind_buffer()
end
local draw_shader=shaders.Make[==[
#version 330
#line 167
out vec4 color;
in vec3 pos;

uniform ivec2 rez;
uniform sampler2D tex_main;

uniform vec4 color_back;
uniform vec4 color_fore;

void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    //normed=normed/zoom+translate;

    vec4 pixel=texture(tex_main,normed);
    color=pixel;
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

	//sensor_distance*=(1-tex_sample)*0.9+0.1;
	//sensor_distance*=normed_state.y;

	//sensor_distance*=1-cubicPulse(0.1,0.5,abs(normed_p.x));
	//sensor_distance=clamp(sensor_distance,2,15);

	//turn_around*=noise(state.xy/100);
	//turn_around-=cubicPulse(0.6,0.3,abs(normed_p.x));
	//turn_around*=tex_sample*0.3+0.7;
	//clamp(turn_around,0.2,5);
	//figure out new heading
	//sensor_angle*=(1-tex_sample)*.9+.1;
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


	///* turn head to center somewhat (really stupid way of doing it...)
	vec2 c=rez/2;
	vec2 d_c=(c-state.xy);
	d_c*=1/sqrt(dot(d_c,d_c));
	vec2 nh=vec2(cos(head),sin(head));
	float T_c=tex_sample*0.005;
	vec2 new_h=d_c*T_c+nh*(1-T_c);
	new_h*=1/sqrt(dot(new_h,new_h));
	head=atan(new_h.y,new_h.x);
	//*/
	//step_size*=1-clamp(cubicPulse(0,0.1,fow),0,1);
	//step_size*=1-cubicPulse(0,0.4,abs(pl))*0.5;
	//step_size*=(clamp(fow/turn_around,0,1))*0.95+0.05;
	step_size*=noise(state.xy/100);
	//step_size*=expStep(abs(pl-0.2),1,2);
	//step_size*=tex_sample*0.5+0.5;
    //step_size*=normed_state.x;
	//step_size=clamp(step_size,0.001,100);

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
	if background_tex~=nil then
	    background_tex.t:use(1)
	    agent_logic_shader_fbk:set_i("background",1)
	    agent_logic_shader_fbk:set("background_swing",background_minmax[1],background_minmax[2])
	end
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
	agent_buffers.pos_speed:get_current():use()
	agent_buffers.pos_speed:get_current():get(agent_data.pos_speed.d,agent_count*4*4)
end
function agents_togpu()
	--tex_agent:use(0)
	--agent_data:write_texture(tex_agent)

	agent_buffers.pos_speed:get_current():use()
	agent_buffers.pos_speed:get_current():set(agent_data.pos_speed.d,agent_count*4*4)
    agent_buffers.angle_type:get_current():use()
    agent_buffers.angle_type:get_current():set(agent_data.angle_type.d,agent_count*4*4)
	__unbind_buffer()
end
function fill_buffer(  )
	tex_pixel:use(0)
	signal_buf:read_texture(tex_pixel)
	for i=0,map_w-1 do
    	for j=0,map_h-1 do
    		signal_buf:set(math.floor(i),math.floor(j),{math.random(),math.random(),math.random(),math.random()})
    	end
    end
    signal_buf:write_texture(tex_pixel)
end
function agents_step_fbk(  )

	--do_agent_logic_fbk()
	add_fields_fbk()

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

    imgui.Begin("super-atomic")
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
            local ang=math.random()*math.pi*2
            local vx=math.cos(ang)
            local vy=math.sin(ang)
    		agent_data.pos_speed:set(i,0,
    			{math.random(0,map_w-1),
    			 math.random(0,map_h-1),
    			 vx,
    			 vy})
            agent_data.angle_type:set(i,0,
                {math.random()*math.pi*2,
                 0,
                 math.random()*255,
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
        --diffuse_and_decay()
    end
    --if config.draw then

    draw_shader:use()
    tex_pixel:use(0)

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("rez",map_w,map_h)
    draw_shader:set("color_back",config.color_back[1],config.color_back[2],config.color_back[3],config.color_back[4])
    draw_shader:set("color_fore",config.color_fore[1],config.color_fore[2],config.color_fore[3],config.color_fore[4])
    draw_shader:draw_quad()
    --end
    if need_save then
        save_img()
        need_save=false
    end

end
