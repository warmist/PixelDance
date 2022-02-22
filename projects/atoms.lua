--inspired : https://ciphered.xyz/2020/06/01/atomic-clusters-a-molecular-particle-based-simulation/


require 'common'
local win_w=1000
local win_h=1000
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
local agent_count=1000
local use_grad_directly=1

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
    {"gravity",0.01,type="floatsci",min=0,max=1},
    {"max_speed",1,type="floatsci",min=0,max=10},
    --agent
    {"ag_field_distance",100,type="int",min=1,max=500},
    {"param_p",0.01,type="float",min=0.01,max=5},
    {"param_s",0.01,type="float",min=0.01,max=5},
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
out vec2 pos;
uniform float offscreen_draw;
uniform vec2 offscreen_offset;
void main()
{
	vec2 offset;
	if(offscreen_draw!=0.0)
	{
		offset=offscreen_offset*rez;
	}
	vec2 real_pos=position.xy+offset;
	vec2 normed=(real_pos/rez)*2-vec2(1,1);
	gl_Position.xy = normed;//mod(normed,vec2(1,1));
	gl_PointSize=pix_size;
	gl_Position.z = 0;
    gl_Position.w = 1.0;

    at=angle_type;
    pos=real_pos;
}
]==],
[==[
#version 330
#line 125
in vec4 at;
in vec2 pos;
out vec4 color;
uniform vec2 rez;
uniform int pix_size;
uniform float trail_amount;
uniform float offscreen_draw;
uniform vec2 potential_params;
vec4 palette(float t,vec4 a,vec4 b,vec4 c,vec4 d)
{
    return a+b*cos(c+d*t*3.1459);
}
#define M_PI 3.14159
void main(){
	float max_range=3;
    //center
	vec2 p = (gl_PointCoord - 0.5)*2;
	p*=max_range;
 	float r = length(p);//*(-1.25)+1.25;
    //r=clamp(r,0,1);
    //r*=max_range;
    r=clamp(r,0,max_range);
	if(offscreen_draw!=0.0)
	{
	    //if(pos.x>0 && pos.y>0 && pos.x<rez.x && pos.y<rez.y)
	    //	discard;
	}
	else
	{

	}
    //p1
    float mult=0;
    if(at.z>128)
        mult=-1;
    else if(at.z<64)
        mult=1;
    float rinv=1/r;
    float s=potential_params.y;
    float eps=potential_params.x;
#if 0
    //* lenard jones potential
    float A=4*eps*pow(s,12);
    float B=4*eps*pow(s,6);
    float v=A*pow(rinv,12)-B*pow(rinv,6);
    //*/
#elif 0
    float A=4*eps*pow(s,4);
    float B=4*eps*pow(s,2);
    float imr=1/max_range;
    float max_range_fix=A*imr*imr*imr-B*imr*imr; //this fix that the potential at max_range==0
    float v=A*rinv*rinv*rinv-B*rinv*rinv-max_range_fix;
    v=clamp(v,-100,1000);
    color=vec4(v,0,0,0);
#else
	//precalc derivate
	float A=4*eps*pow(s,4);
    float B=4*eps*pow(s,2);
    //float imr=1/max_range;
    //float max_range_fix=A*imr*imr*imr-B*imr*imr; //this fix that the potential at max_range==0
    float max_range_fix=0;

    //float rsq=r*r;
    float rsq_inv=rinv*rinv;
 	float v=A*rinv*rinv*rinv*rinv-B*rinv*rinv;//-max_range_fix;
 	float max_inv=1/(max_range*max_range);
 	vec2 vd_max=2*p.xy*(B*max_inv*max_inv-2*A*max_inv*max_inv*max_inv);
    vec2 vd=2*p.xy*(B*rsq_inv*rsq_inv-2*A*rsq_inv*rsq_inv*rsq_inv)-vd_max;
    vd*=vec2(1,-1); 
    //vec2 vd=2*p.xy*(B/(rsq*rsq)-2*A/(rsq*rsq*rsq))*rinv;
    vd*=step(0.05,r);//smoothstep(0.05,0.2,r); //zero out the center, as we dont want to influence ourself
    //vd*=1-smoothstep(max_range*0.95,max_range,r);
    v=clamp(v,-100,1000);

    /*
    float vdl=length(vd);
    float max_l=10;
    if(vdl>max_l)
	{
		vd/=vdl/max_l;
	}
	*/
    //vd=clamp(vd,vec2(-1),vec2(1));
    color=vec4(vd.xy,v,0);
#endif

    //float v=r*r*r-r*r;
    
    vec2 p1=p+vec2(cos(at.x),sin(at.x))*0.5;
    float r2=1-length(p1)*length(p1)*4;
    r2=clamp(r2,0,1);
    r2*=mult;

    //p2
    float mult2=0;
    if(at.z>192)
        mult2=-1;
    else if(at.z<32)
        mult2=1;

    vec2 p2=p+vec2(cos(at.x+M_PI),sin(at.x+M_PI))*0.5;
    float r3=1-length(p2)*length(p2)*4;
    r3=clamp(r3,0,1);
    r3*=mult2;
	//palette(r,vec4(0.5),vec4(0.5),vec4(1.5*at.z,at.z,8*at.z,0),vec4(1,1,0,0))*r;
	//
}
]==])
function add_fields_fbk(  )
	add_fields_shader:use()
	tex_pixel:use(0)
    add_fields_shader:blend_add()
	add_fields_shader:set_i("pix_size",config.ag_field_distance)
	add_fields_shader:set("rez",map_w,map_h)
	add_fields_shader:set("potential_params",config.param_p,config.param_s)
	if not tex_pixel:render_to(map_w,map_h) then
		error("failed to set framebuffer up")
	end
    __clear()
	if need_clear then
		need_clear=false
		--print("Clearing")
	end
    if true then
        agent_buffers.angle_type:get_current():use()
        add_fields_shader:push_attribute(0,1,4)
    	agent_buffers.pos_speed:get_current():use()
    	add_fields_shader:set("offscreen_draw",0)
    	add_fields_shader:draw_points(0,agent_count,4)
    end
    --[[
    agent_buffers.angle_type:get_current():use()
    add_fields_shader:push_attribute(0,"angle_type",4)
    add_fields_shader:set("offscreen_offset",1,0)
    agent_buffers.pos_speed:get_current():use()
	add_fields_shader:set("offscreen_draw",1)
	add_fields_shader:draw_points(0,agent_count,4)
	--]]
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
uniform float use_grad_directly;

uniform vec4 color_back;
uniform vec4 color_fore;
vec2 grad_tex(vec2 pos)
{
    vec2 ret;
    float v=textureOffset(tex_main,pos,ivec2(0,0)).x;
    ret.x=textureOffset(tex_main,pos,ivec2(1,0)).x-v;
    ret.y=textureOffset(tex_main,pos,ivec2(0,1)).x-v;
    return ret;
}
vec2 grad_tex2(vec2 pos)
{
    vec2 ret;
    ret.x=textureOffset(tex_main,pos,ivec2(1,0)).x-textureOffset(tex_main,pos,ivec2(-1,0)).x;
    ret.y=textureOffset(tex_main,pos,ivec2(0,1)).x-textureOffset(tex_main,pos,ivec2(0,-1)).x;
    return ret/2;
}
vec2 grad_tex3(vec2 pos)
{
    vec2 ret;
    ret.x=textureOffset(tex_main,pos,ivec2(1,0)).z-textureOffset(tex_main,pos,ivec2(-1,0)).z;
    ret.y=textureOffset(tex_main,pos,ivec2(0,1)).z-textureOffset(tex_main,pos,ivec2(0,-1)).z;
    return ret/2;
}
float sdfBox(vec2 p, vec2 size)
{
    vec2 d = abs(p) - size;  
	return length(min(-d, vec2(0))) + max(min(-d.x,-d.y), 0.0);
}
vec2 apply_limits(vec2 p)
{
	float edge_size=0.1;
	return vec2(-1,0)*smoothstep(1-edge_size,1,p.x)+vec2(1,0)*(1-smoothstep(0,edge_size,p.x))
	+vec2(0,1)*smoothstep(1-edge_size,1,p.y)+vec2(0,-1)*(1-smoothstep(0,edge_size,p.y));
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    //normed=normed/zoom+translate;
#if 0
    vec4 pixel=vec4(0,0,0,1);//texture(tex_main,normed);
    /*//pixel.xyz*=1;
    //pixel.x=pow(pixel.x,0.002);
    if(pixel.x>0)
    	color.xyz=pixel.xyz*0.005;
    else
    	color.xyz=vec3(0,0,-pixel.x*0.5);
    */
    //color.xyz=abs(pixel.xyz);
    //vec2 p=grad_tex2(normed);
    vec2 p=texture(tex_main,normed).xy;

    if(use_grad_directly==0)
    	p=grad_tex3(normed);

    float a=atan(p.y,p.x)/3.14;
    //float a=length(p);
    if(a>0)
    	color.x=a;
    else
    	color.y=-a;
    color.z=length(p.xy)*0.1;
    //color.xy*=length(p.xy);
    color.w=1;
    //color=abs(pixel*1);
    //color+=sdfBox(pos.xy,vec2(0.8));
#else
	float v=texture(tex_main,normed).z;
	if(v>0)
		color=vec4(v*0.001,0,0,1);
	else
		color=vec4(0,0,-v*0.05,1);
	color.xyz+=vec3(length(apply_limits(normed.xy)));
#endif
}
]==]
local agent_logic_shader_fbk=shaders.Make(
[==[

#version 330
#line 388
layout(location = 0) in vec4 position;
out vec4 state_out;

uniform sampler2D tex_main;  //signal buffer state
uniform vec2 rez;
uniform float friction;
uniform float gravity;
uniform float max_speed;
uniform float use_grad_directly;
//agent settings uniforms
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
vec2 grad_tex(vec2 pos)
{
    vec2 ret;
    float v=textureOffset(tex_main,pos,ivec2(0,0)).x;
    ret.x=textureOffset(tex_main,pos,ivec2(1,0)).x-v;
    ret.y=textureOffset(tex_main,pos,ivec2(0,1)).x-v;
    return ret;
}
vec2 grad_tex2(vec2 pos)
{
    vec2 ret;
    ret.x=textureOffset(tex_main,pos,ivec2(1,0)).x-textureOffset(tex_main,pos,ivec2(-1,0)).x;
    ret.y=textureOffset(tex_main,pos,ivec2(0,1)).x-textureOffset(tex_main,pos,ivec2(0,-1)).x;
    return ret/2;
}
vec2 grad_tex3(vec2 pos)
{
    vec2 ret;
    ret.x=textureOffset(tex_main,pos,ivec2(1,0)).z-textureOffset(tex_main,pos,ivec2(-1,0)).z;
    ret.y=textureOffset(tex_main,pos,ivec2(0,1)).z-textureOffset(tex_main,pos,ivec2(0,-1)).z;
    return ret/2;
}
float sdfBox(vec2 p, vec2 size)
{
    vec2 d = abs(p) - size;
	return length(min(-d, vec2(0))) + max(min(-d.x,-d.y), 0.0);
}
vec2 grad_sdf(vec2 pos)
{
	vec2 s=vec2(0.8);
	float dx=1/rez.x;
	vec2 ret;
    float v=sdfBox(pos,s);
    ret.x=sdfBox(pos+vec2(dx,0),s)-v;
    ret.y=sdfBox(pos+vec2(0,dx),s)-v;
    return ret;
}
vec2 apply_limits(vec2 p)
{
	float edge_size=0.1;
	return vec2(-1,0)*smoothstep(1-edge_size,1,p.x)+vec2(1,0)*(1-smoothstep(0,edge_size,p.x))
		+vec2(0,-1)*smoothstep(1-edge_size,1,p.y)+vec2(0,1)*(1-smoothstep(0,edge_size,p.y));
}
void main(){
	float max_l=max_speed;
	vec4 state=position;
    vec2 normed_state=(state.xy/rez);
	vec4 fields=texture(tex_main,normed_state);

	vec2 p=grad_tex3(normed_state);//vec2(dFdx(fields.x),dFdy(fields.x));

	//state.zw-=clamp(fields.xy,vec2(-1),vec2(1));
	if(use_grad_directly==0)
		state.zw-=p;
	else
		state.zw-=fields.xy;

	//vec2 ps=grad_sdf(normed_state-vec2(0.5));
	//state.zw-=ps;
	state.w-=gravity;
	state.zw+=apply_limits(clamp(normed_state,vec2(-1),vec2(1)))*10;
	state.zw*=friction;
	float l=length(state.zw);
	if(l>max_l)
	{
		state.zw/=l/max_l;
	}
	/*

	if(state.x+state.z>rez.x)
		state.z*=-1;
	if(state.y+state.w>rez.y)
		state.w*=-1;
	if(state.x+state.z<0)
		state.z*=-1;
	if(state.y+state.w<0)
		state.w*=-1;
	*/
	state.xy+=state.zw;

	state.xy=mod(state.xy,rez.xy);
	//state.xy=clamp(state.xy,vec2(0),rez);
	state_out=state;

}
]==]
,[===[
void main()
{

}
]===],"state_out")

function do_agent_logic_fbk(  )

	agent_logic_shader_fbk:use()
    tex_pixel:use(0,0,1)
    agent_logic_shader_fbk:set_i("tex_main",0)
	agent_logic_shader_fbk:set("rez",map_w,map_h)
	agent_logic_shader_fbk:set("friction",config.friction);
	agent_logic_shader_fbk:set("gravity",config.gravity);
	agent_logic_shader_fbk:set("max_speed",config.max_speed);
	agent_logic_shader_fbk:set("use_grad_directly",use_grad_directly)
	agent_logic_shader_fbk:raster_discard(true)
	local ao=agent_buffers.pos_speed:get_other()
	ao:use()
	ao:bind_to_feedback()

	local ac=agent_buffers.pos_speed:get_current()
	ac:use()
	agent_logic_shader_fbk:draw_points(0,agent_count,4,1)
	__flush_gl()
	agent_logic_shader_fbk:raster_discard(false)
	--__read_feedback(agent_data.d,agent_count*agent_count*4*4)
	--print(agent_data:get(0,0).r)
	agent_buffers.pos_speed:flip()
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

	do_agent_logic_fbk()
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
			signal_buf:set(x,y,{0,0,0,0})
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
        agents_step_fbk()
    end
    --if config.draw then

    draw_shader:use()
    tex_pixel:use(0,0,1)

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("rez",map_w,map_h)
    draw_shader:set("color_back",config.color_back[1],config.color_back[2],config.color_back[3],config.color_back[4])
    draw_shader:set("color_fore",config.color_fore[1],config.color_fore[2],config.color_fore[3],config.color_fore[4])
    draw_shader:set("use_grad_directly",use_grad_directly)
    draw_shader:draw_quad()
    --end
    if need_save then
        save_img()
        need_save=false
    end

end
