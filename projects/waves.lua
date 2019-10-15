require "common"


local size_mult=1
local win_w
local win_h
local aspect_ratio
function update_size(  )
	win_w=2560*size_mult
	win_h=1440*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
update_size()

local size=STATE.size


--[[ prob needed for saving
img_buf=make_image_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	print("new size:",w,h)
end
--]]

textures=textures or {}
function make_textures()
	if #textures==0 or textures[1].w~=size[1]*oversample or textures[1].h~=size[2]*oversample then
		print("making tex")
		for i=1,3 do
			local t={t=textures:Make(),w=size[1]*oversample,h=size[2]*oversample}
			t.t:use(0,1)
			t.t:set(size[1]*oversample,size[2]*oversample,2)
			textures[i]=t
		end
	end
end
make_textures()

function make_io_buffer(  )
	if io_buffer==nil or io_buffer.w~=size[1]*oversample or io_buffer.h~=size[2]*oversample then
		io_buffer=make_float_buffer(size[1]*oversample,size[2]*oversample)
	end
end

make_io_buffer()

config=make_config({
	{"draw",true,type="boolean"},
	{"ticking",1,type="int",min=1,max=2},
	{"size_mult",true,type="boolean"},
},config)

function gui()
	imgui.Begin("IFS play")
	draw_config(config)
	if config.size_mult then
		size_mult=1
	else
		size_mult=0.5
	end
	update_size()
	local s=STATE.size
	--[[
	if imgui.Button("Clear image") then
		clear_buffers()
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		need_save=true
	end
	]]
	imgui.SameLine()
	imgui.End()
end

function update( )
	gui()
	update_real()
end

function update_real(  )
	__no_redraw()
	if animate then
		tick=tick or 0
		tick=tick+1

	else
		__clear()
		if config.draw then
			draw_texture()
		end
	end
	auto_clear()
	visit_iter()
	local scale=config.scale
	--[[
	local c,x,y= is_mouse_down()
	if c then
		--mouse to screen
		x=(x/size[1]-0.5)*2
		y=(-y/size[2]+0.5)*2
		--screen to world
		x=(x-cx)/scale
		y=(y-cy)/(scale*aspect_ratio)

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
	]]
end
