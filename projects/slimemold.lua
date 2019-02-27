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
local oversample=0.5

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

update_buffers()
config=make_config({
    {"pause",false,type="bool"},
    {"color",{0.63,0.59,0.511,0.2},type="color"},
    --system
    {"decay",0,type="float"},
    {"diffuse",0.9999,type="float"},
    --agent
    {"ag_sensor_distance",1,type="float",min=0.1,max=10},
    {"ag_sensor_size",1,type="int",min=1,max=3},
    {"ag_sensor_angle",math.pi/8,type="angle"},
    {"ag_turn_angle",math.pi/16,type="angle"},
	{"ag_step_size",1,type="float",min=0.1,max=10},
    },config)

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
	for i=map_w*0.2,map_w*0.8 do
    	for j=map_h*0.2,map_h*0.8 do
    		signal_buf:set(math.floor(i),math.floor(j),math.random())
    	end
    end
end
agents=agents or {}
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
local agent=class(function ( ag,x,y,heading )
	ag:set(x,y,heading)
end)
function agent:set( x,y,heading )
	self.pos=Point(x or math.random(),y or math.random())
	self.heading=math.random()*math.pi*2
end
function agent:step(  )
	local sensor_distance=config.ag_sensor_distance
	local sensor_size=config.ag_sensor_size
	local sensor_angle=config.ag_sensor_angle
	local turn_size=config.ag_turn_angle
	local step_size=config.ag_step_size
	--sense
	local heading=self.heading
	local fw_pos=self.pos+sensor_distance*Point(math.cos(heading),math.sin(heading))
	wrap_pos(fw_pos)
	local fow=sense(fw_pos,sensor_size)

	local left_pos=self.pos+sensor_distance*Point(math.cos(heading-sensor_angle),math.sin(heading-sensor_angle))
	wrap_pos(left_pos)
	local left=sense(left_pos,sensor_size)

	local right_pos=self.pos+sensor_distance*Point(math.cos(heading+sensor_angle),math.sin(heading+sensor_angle))
	wrap_pos(right_pos)
	local right=sense(right_pos,sensor_size)
	--rotate
	if fow< left and fow < right then
		self.heading=self.heading+(math.random()-0.5)*turn_size
	elseif right> fow then
		self.heading=self.heading+turn_size
	elseif left>fow then
		self.heading=self.heading-turn_size
	end
	--step
	heading=self.heading
	self.pos=self.pos+step_size*Point(math.cos(heading),math.sin(heading))
	local w=signal_buf.w
	local h=signal_buf.h
	wrap_pos(self.pos)
end
function agent:leave_track(  )
	local agent_track_amount=0.01
	local tx=math.floor(self.pos[1])
	local ty=math.floor(self.pos[2])
	signal_buf:set(tx,ty,signal_buf:get(tx,ty)+agent_track_amount)
end
function agents_step(  )
	for _,v in ipairs(agents) do
		v:step()
	end
	for _,v in ipairs(agents) do
		v:leave_track()
	end
end
function diffuse_and_decay(  )
	if signal_buf_alt == nil or signal_buf_alt.w~=signal_buf.w or
			signal_buf_alt.h~=signal_buf.h then
		signal_buf_alt=make_float_buffer(signal_buf.w,signal_buf.h)
	end

	for i=0,signal_buf.w-1 do
		for j=0,signal_buf.h-1 do
			local sum=0
			local wsum=0
			for di=-1,1 do
				for dj=-1,1 do
					local ti=i+di
					local tj=j+dj
					if ti <0 then ti = signal_buf.w-1 end
					if ti >=signal_buf.w then ti = 0 end
					if tj <0 then tj = signal_buf.h-1 end
					if tj >=signal_buf.h then tj = 0 end
					local w=config.diffuse
					if di==0 and dj==0 then
						w=1
					end
					sum=sum+signal_buf:get(ti,tj)*w
					wsum=wsum+w
				end
			end
			local decay_value=math.exp(-config.decay)
			signal_buf_alt:set(i,j,sum*decay_value/wsum)
		end
	end

	local ss=signal_buf
	signal_buf=signal_buf_alt
	signal_buf_alt=ss
end
tex_pixel=tex_pixel or textures:Make()
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
    	agents={}
    end
     imgui.SameLine()
    if imgui.Button("Agentswarm") then
    	for i=1,1000 do
    		table.insert(agents,
    			agent(map_w/2,map_h/2,math.random()*math.pi*2))
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
    tex_pixel:use(0,0,1)

    --tex_pixel.t:set(size[1]*oversample,size[2]*oversample,3)
    signal_buf:write_texture(tex_pixel)

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