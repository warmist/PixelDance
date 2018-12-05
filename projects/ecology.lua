require 'common'

__set_window_size(1024,1024)
local aspect_ratio=1024/1024
local size=STATE.size

local oversample=0.25

function update_img_buf(  )
	local nw=math.floor(size[1]*oversample)
	local nh=math.floor(size[2]*oversample)
	if imgbuf==nil or img_buf.w~=nw or img_buf.h~=nh then
		img_buf=make_image_buffer(nw,nh)
		img_buf_back=make_image_buffer(nw,nh)
		sun_buffer=make_float_buffer(nw,1)
	end
end

update_img_buf()
config=make_config({
	{"color",{0.4,0.4,0.3,0.1},type="color"},
	},config)
local draw_shader=shaders.Make[==[
#version 330
#line 24
out vec4 color;
in vec3 pos;

uniform vec2 rez;
uniform vec4 sun_color;
uniform sampler2D tex_main;
uniform sampler2D tex_sun;
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float hsun=texture(tex_sun,vec2(normed.x,0)).x;
	float v=1;
	//v=1-smoothstep(normed.y,hsun-0.005,1);
	v=1-step(normed.y,hsun);
	//if(normed.y<hsun)
	//	v=0;
	float light=clamp(v,sun_color.a,1);
	color=vec4(texture(tex_main,normed).xyz+sun_color.xyz*light,1);
}
]==]

local pixel_types={ --alpha used to id types
	sand={124,100,80,255},
	wall={20,80,100,100},
	dead_plant={50,20,30,255},
	plant_seed={10,150,50,1},
}
function pixel_init(  )
	local w=img_buf.w
	local h=img_buf.h
	local cx = math.floor(w/2)
	local cy = math.floor(h/2)

	for i=1,5000 do
		local x=math.random(0,w-1)
		local y=math.random(0,h-1)
		img_buf:set(x,y,pixel_types.sand)
	end
	local platform_size=8
	for i=1,5 do
		local x=math.random(0,w-1-platform_size)
		local y=math.random(0,h-1)
		for i=0,platform_size do
			img_buf:set(x+i,y,pixel_types.wall)
		end
		
	end
	local wall_size = 8
	for i=1,5 do
		local x=math.random(0,w-1)
		local y=math.random(0,h-1-wall_size)
		for i=0,wall_size do
			img_buf:set(x,y+i,pixel_types.wall)
		end
		
	end
end
pixel_init()

function pixel_step(  )
	local w=img_buf.w
	local h=img_buf.h

	for x=0,w-1 do
		for y=1,h-1 do
			local c=img_buf:get(x,y)
			

			if c.a>200 then -->200 dropping
				local d=img_buf:get(x,y-1)
				if d.a==0 then
					img_buf:set(x,y-1,c)
					img_buf:set(x,y,{0,0,0,0})
				else
					local tx=x+1
					if math.random()>0.5 then
						tx=x-1
					end
					if tx>=0 and tx<=w-1 then
						local d=img_buf:get(tx,y-1)
						if d.a==0 then
							img_buf:set(tx,y-1,c)
							img_buf:set(x,y,{0,0,0,0})
						end
					end
				end
			end
		end
	end
	for x=0,w-1 do
		sun_buffer:set(x,0,0)
	end
	for x=0,w-1 do
		for y=h-1,0,-1 do
			local c=img_buf:get(x,y)
			if c.a>50 then
				sun_buffer:set(x,0,y/h)
				break
			end
		end
	end

	--[[
	local i=img_buf_back
	img_buf_back=img_buf
	img_buf=i
	--]]
end
plants={}
function add_plant(  )
	local w=img_buf.w
	local h=img_buf.h
	local x=math.random(0,w-1)
	local y=h-1--math.random(0,h-1)
	table.insert(plants,{x,y,pixel_types.plant_seed,food=10000,dead=false,growing=false})
end
for i=1,10 do
	add_plant(  )
end
function is_sunlit( x,y )
	if x<0 or x>img_buf.w-1 then
		return false
	end
	local sh=sun_buffer:get(x,0)
	return sh*img_buf.h<=y
end
function plant_step()
	--super config
	local sun_gain=1
	local grow_cost_const=1
	local grow_cost_buffer=1.2
	local max_food=20000
	local food_drain=3
	--

	local w=img_buf.w
	local h=img_buf.h
	for i,v in ipairs(plants) do
		local x=v[1]
		local y=v[2]
		local moved=false

		--remove old pos
		img_buf:set(x,y,{0,0,0,0})
		--drop down
		if not v.growing then
			if y>0 then
				local d=img_buf:get(x,y-1)
				if d.a==0 then
					y=y-1
					v[2]=y
					moved=true
				elseif d.a==pixel_types.sand[4] then
					if is_sunlit(x,y) then
						v[3][1]=255
						v.growing=true
					end
				end
			end
		else
			--growing logic
			local food_balance=0
			local tbl=v.path or {}
			v.path=tbl

			for i,v in ipairs(v.path) do
				if is_sunlit(v[1],v[2]) then
					food_balance=food_balance+1
				end
			end
			local tx = x
			local ty = y
			if #v.path >0 then
				tx=v.path[#v.path][1]
				ty=v.path[#v.path][2]
			end
			local grow_cost=grow_cost_const+(#v.path)*0.05--+math.max(ty*2-25,0)
			if ty<h-1 and (food_balance>grow_cost*grow_cost_buffer or #v.path<3) then

				if math.random()>0.2 then
					local right=is_sunlit(tx+1,ty)
					local left=is_sunlit(tx-1,ty)
					if not(left== right) then
						if left then
							tx=tx-1
						else
							tx=tx+1
						end
					else
						if math.random()>0.5 then
							tx=tx+1
						else
							tx=tx-1
						end
					end
				else
					ty=ty+1
				end
				if tx>=0 and tx<w and ty>=0 and ty<h then
					local d=img_buf:get(tx,ty)
					if d.a==0 then
						table.insert(v.path,{tx,ty})
						img_buf:set(tx,ty,{50,180,20,51})
						food_balance=food_balance-grow_cost
					end
				end
			else
				--v.dead=true
			end
			v.food=v.food+food_balance
			if v.food>max_food then
				v.food=max_food
			end
		end

		--ageing logic
		v.food=v.food-food_drain
		if v.food<=0 then
			v.dead=true
		end
		--readd new pos
		if v.dead then
			img_buf:set(x,y,pixel_types.dead_plant)
			for i,v in ipairs(v.path or {}) do
				img_buf:set(v[1],v[2],pixel_types.dead_plant)
			end
		else
			img_buf:set(x,y,v[3])
		end
	end
	local tplants=plants
	plants={}
	for i,v in ipairs(tplants) do
		if not v.dead then
			table.insert(plants,v)
		end
	end
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
tex_pixel=tex_pixel or textures:Make()
tex_sun=tex_sun or textures:Make()
function update()

	__no_redraw()
	__clear()
	imgui.Begin("ecology")
	draw_config(config)
	imgui.End()
	if is_mouse_down() then
		add_plant()
	end
	if math.random()>0.9 then
		add_plant()
	end
 	pixel_step( )
 	plant_step()
	draw_shader:use()
	tex_pixel:use(0)

	--tex_pixel.t:set(size[1]*oversample,size[2]*oversample,3)
	img_buf:write_texture(tex_pixel)
	tex_sun:use(1)
	sun_buffer:write_texture(tex_sun)

	draw_shader:set_i("tex_main",0)
	draw_shader:set_i("tex_sun",1)
	draw_shader:set("sun_color",config.color[1],config.color[2],config.color[3],config.color[4])
	draw_shader:draw_quad()
end