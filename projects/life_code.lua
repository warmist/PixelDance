--inspired by: https://github.com/hunar4321/life_code

require "common"
--CODECOPY: slimemold.lua

--[[
	basic logic:
		- texture holding all the coords
	  	- array holding all the coords
	  	- array holding all the types
	  	* vertex shader takes texture and array outputs array of new positions (feedback)
	  	* update the texture with new positions
	  	* draw the atoms
--]]

local max_atoms=1000000
local win_w=1280
local win_h=1280

__set_window_size(win_w,win_h)
local oversample=0.5
local agent_count=3e6
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)
local max_rad=map_w
local max_weight=100

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

update_buffers()
local color_names={"red","green","blue","white"}
local color_values={{1,0,0},{0,1,0},{0,0,1},{1,1,1}}
local num_colors=#color_names

local cfg_table={
    {"pause",false,type="bool"},
    }
--[[
for i,v in ipairs(color_names) do
	table.insert(cfg_table,{"count_"..v,100,type="int"})
	for _,vv in ipairs(color_names) do

		table.insert(cfg_table,{v.."_"..vv,type="float"})
		table.insert(cfg_table,{"rad_"..v.."_"..vv,type="float"})
	end
end
]]
config=make_config(cfg_table,config)
color_config=color_config or {}
function draw_color_config(  )
	current_color=current_color or 1
	_,current_color=imgui.SliderInt("Color",current_color,1,num_colors)
	imgui.Text(color_names[current_color])
	color_config[current_color]=color_config[current_color] or {count=100}
	local cfg=color_config[current_color]
	_,cfg.count=imgui.SliderInt("Count "..color_names[current_color],cfg.count,0,10000)
	if imgui.Button("Randomize weights") then
		for i,v in ipairs(color_names) do
			cfg[v]={r=math.random()*max_rad,v=math.random()*max_weight*2-max_weight}
		end
	end
	for i,v in ipairs(color_names) do
		cfg[v]=cfg[v] or {r=0,v=0}
		_,cfg[v].v=imgui.SliderFloat(v,cfg[v].v,-max_weight,max_weight,"%.3f",1)
		_,cfg[v].r=imgui.SliderFloat("rad "..v,cfg[v].r,0,max_rad,"%.3f",1)
	end
end
function logic_tick()
	
end
function draw()
	
end
function update()
	logic_tick()
	draw()
	imgui.Begin("Life Code")
	draw_config(config)
	draw_color_config()
	imgui.End()
end