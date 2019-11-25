--https://www.reddit.com/r/generative/comments/e12s8n/community_exhibition/
require "common"
local win_w=1024
local win_h=1024

__set_window_size(win_w,win_h)
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local size=STATE.size

local count_circles=100
circle_sizes=circle_sizes or make_float_buffer(count_circles,1)
circle_pos=circle_pos or make_flt_half_buffer(count_circles,1)
circle_speed=circle_speed or make_flt_half_buffer(count_circles,1)

material=material or make_float_buffer(map_w,map_h)
function resize( w,h )
	material=make_float_buffer(map_w,map_h)
end

function draw(  )
	draw_shader:use()
	draw_shader:draw_quad()
end

function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Circles")
	local s=STATE.size
	draw_config(config)

	if imgui.Button("Clear image") then
		--clear_screen(true)
		for j=0,map_h-1 do
			for i=0,map_w-1 do
				material:set(i,j,0)
				img_buf:set(i,j,{0,0,0,0})
			end
		end
		for i=1,5 do
			img_buf:set(math.random(0,map_w-1),math.random(0,map_h-1),{255,255,255,255})
		end
		write_mat()
		write_img()
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
	if config.simulate then
		if config.add_mat >0 then
			mat_tex1:use(0)
			material:read_texture(mat_tex1)

			local rw=math.floor(map_w/15)
			local rh=math.floor(map_h/15)
			local cx=math.floor(map_w/2)
			local cy=math.floor(map_h/2)
			for x=cx-rw,cx+rw do
			for y=cy-rh,cy+rh do
				add_mat(x,y,config.add_mat)
			end
			end
			material:write_texture(mat_tex1)
		end

		diffuse_and_decay(mat_tex1,mat_tex2,map_w,map_h,0.5,config.decay,config.diffuse_steps,img_tex1)
		if(config.diffuse_steps%2==1) then
			local c=mat_tex1
			mat_tex1=mat_tex2
			mat_tex2=c
	    end
	    crystal_step()
	end
	draw()
	if need_save then
		save_img()
		need_save=false
	end
end