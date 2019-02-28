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
local win_w=768
local win_h=768

__set_window_size(win_w,win_h)
local oversample=1
local agent_count=30000
--[[ perf:
	oversample 2 768x768
		ac: 3000 -> 43fps
			no_steps ->113fps
			no_tracks ->43fps
]]
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

function update_buffers(  )
    local nw=map_w
    local nh=map_h

    if signal_buf==nil or signal_buf.w~=nw or signal_buf.h~=nh then
        signal_buf=make_float_buffer(nw,nh)
        is_remade=true
    end
end

if agent_coords==nil or agent_coords.w~=agent_count then
	agent_coords=make_flt_half_buffer(agent_count,1)
	agent_headings=make_float_buffer(agent_count,1)
	for i=0,agent_count-1 do
		agent_coords:set(i,0,{math.random()*map_w,math.random()*map_h})
		agent_headings:set(i,0,math.random()*math.pi*2)
	end
end

tex_pixel=tex_pixel or textures:Make()

update_buffers()
config=make_config({
    {"pause",false,type="bool"},
    {"color",{0.63,0.59,0.511,0.2},type="color"},
    --system
    {"decay",0.999,type="float"},
    {"diffuse",0.5,type="float"},
    --agent
    {"ag_sensor_distance",9,type="float",min=0.1,max=10},
    {"ag_sensor_size",1,type="int",min=1,max=3},
    {"ag_sensor_angle",math.pi/4,type="float",min=0,max=math.pi/2},
    {"ag_turn_angle",math.pi/4,type="float",min=0,max=math.pi/2},
	{"ag_step_size",1,type="float",min=0.1,max=10},
	{"ag_trail_amount",0.1,type="float",min=0,max=10},
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

local draw_shader=shaders.Make[==[
#version 330
#line 40
out vec4 color;
in vec3 pos;

uniform ivec2 rez;
uniform sampler2D tex_main;


void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    //normed=normed/zoom+translate;

    vec4 pixel=texture(tex_main,normed);
    color=vec4(pixel.xxx,1);
}
]==]
function fill_buffer(  )
	tex_pixel:use(0)
	signal_buf:read_texture(tex_pixel)
	for i=map_w*0.2,map_w*0.8 do
    	for j=map_h*0.2,map_h*0.8 do
    		signal_buf:set(math.floor(i),math.floor(j),math.random())
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
function agent_set( id,x,y,heading )
	agent_coords:set(id,0,{x,y})
	agent_headings:set(id,0,heading)
end

function agent_steps(  )
	local sensor_distance=config.ag_sensor_distance
	local sensor_size=config.ag_sensor_size
	local sensor_angle=config.ag_sensor_angle
	local turn_size=config.ag_turn_angle
	local step_size=config.ag_step_size
	for id=0,agent_count-1 do
		--sense
		local heading=agent_headings:get(id,0)
		local pos=agent_coords:get(id,0)
		local ppos=Point(pos.r,pos.g)
		local fw_pos=ppos+sensor_distance*Point(math.cos(heading),math.sin(heading))
		wrap_pos(fw_pos)
		local fow=sense(fw_pos,sensor_size)

		local left_pos=ppos+sensor_distance*Point(math.cos(heading-sensor_angle),math.sin(heading-sensor_angle))
		wrap_pos(left_pos)
		local left=sense(left_pos,sensor_size)

		local right_pos=ppos+sensor_distance*Point(math.cos(heading+sensor_angle),math.sin(heading+sensor_angle))
		wrap_pos(right_pos)
		local right=sense(right_pos,sensor_size)
		--rotate
		if fow< left and fow < right then
			heading=heading+(math.random()-0.5)*turn_size*2
		elseif right> fow then
			heading=heading+turn_size
			--self.heading=self.heading+turn_size*math.random()
		elseif left>fow then
			heading=heading-turn_size
			--self.heading=self.heading-turn_size*math.random()
		end
		--step
		agent_headings:set(id,0,heading)
		ppos=ppos+step_size*Point(math.cos(heading),math.sin(heading))
		wrap_pos(ppos)
		pos.r=ppos[1]
		pos.g=ppos[2]
	end
end
function agent_tracks(  )
	local agent_track_amount=config.ag_trail_amount
	for id=0,agent_count-1 do
		local p=agent_coords:get(id,0)
		local tx=math.floor(p.r)
		local ty=math.floor(p.g)
		local new_val=signal_buf:get(tx,ty)+agent_track_amount
		--if new_val>1 then new_val=1 end
		signal_buf:set(tx,ty,new_val)
	end
end
function agents_step(  )
	tex_pixel:use(0)
	signal_buf:read_texture(tex_pixel)
	agent_steps()
	agent_tracks()
	signal_buf:write_texture(tex_pixel)
end
function diffuse_and_decay(  )
	if tex_pixel_alt==nil then
		tex_pixel_alt=textures:Make()
		tex_pixel_alt:use(1)
		tex_pixel_alt:set(signal_buf.w,signal_buf.h,2)
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
    		agent_coords:set(i,0,
    			{rnd(map_w/8)+map_w/2,
    			 rnd(map_h/8)+map_h/2})
			agent_headings:set(i,0,math.random()*math.pi*2)
    	end
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