require 'common'

__set_window_size(1024,1024)
local aspect_ratio=1024/1024
local size=STATE.size

local oversample=0.5
is_remade=false

function update_img_buf(  )
	local nw=math.floor(size[1]*oversample)
	local nh=math.floor(size[2]*oversample)

	if img_buf==nil or img_buf.w~=nw or img_buf.h~=nh then
		img_buf=make_image_buffer(nw,nh)
		img_buf_back=make_image_buffer(nw,nh)
		sun_buffer=make_float_buffer(nw,1)
		is_remade=true
	end
end

update_img_buf()
config=make_config({
	{"color",{0.4,0.4,0.3,0.1},type="color"},
	{"zoom",1,type="float",min=1,max=10},
	{"t_x",0,type="float",min=-1,max=1},
	{"t_y",0,type="float",min=-1,max=1},
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
uniform float zoom;
uniform vec2 translate;

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	normed=normed/zoom+translate;
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
function is_valid_coord( x,y )
	return x>=0 and y>=0 and x<img_buf.w and y<img_buf.h
end
local directions8={
	{-1,-1},
	{0,-1},
	{1,-1},
	{1,0},
	{1,1},
	{0,1},
	{-1,1},
	{-1,0},
}
local directions4={
	{0,-1},
	{1,0},
	{0,1},
	{-1,0},
}
local pixel_types={ --alpha used to id types
	sand={124,100,80,255},
	wall={20,80,100,100},
	dead_plant={50,20,30,190},
	plant_seed={10,150,50,48},
	worm_body={255,100,80,52},
}
function pixel_init(  )
	local w=img_buf.w
	local h=img_buf.h
	local cx = math.floor(w/2)
	local cy = math.floor(h/2)

	for i=1,w*h*0.1 do
		local x=math.random(0,w-1)
		local y=math.random(0,h-1)
		img_buf:set(x,y,pixel_types.sand)
	end
	
	for i=1,2 do
		local platform_size=math.random(10,20)
		local x=math.random(0,w-1)
		local y=math.random(0,h-1)
		for i=1,platform_size do
			local d=directions4[math.random(1,#directions4)]
			local tx=x+d[1]
			local ty=y+d[2]
			if is_valid_coord(tx,ty) then
				x=tx
				y=ty
				img_buf:set(tx,ty,pixel_types.wall)
			end
		end
		
		for i=0,platform_size do
			img_buf:set(x+i,y,pixel_types.wall)
		end
		
	end
	--[[ h wall
	local wall_size = 8
	for i=1,5 do
		local x=math.random(0,w-1)
		local y=math.random(0,h-1-wall_size)
		for i=0,wall_size do
			img_buf:set(x,y+i,pixel_types.wall)
		end
	end
	]]
end
if is_remade then
pixel_init()
end

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
			elseif c.a>180 then --> 180 liquidy
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
						local d=img_buf:get(tx,y)
						if d.a==0 then
							img_buf:set(tx,y,c)
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
plants=plants or {}
if is_remade then plants={} end
function add_plant(  )
	local w=img_buf.w
	local h=img_buf.h
	local x=math.random(0,w-1)
	local y=h-1--math.random(0,h-1)
	table.insert(plants,{x,y,pixel_types.plant_seed,food=500,dead=false,growing=false})
	img_buf:set(x,y,pixel_types.plant_seed)
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
	--growth stuff
	local chance_up=0.6
	local chance_sunlit=0.9
	--costs and food
	local sun_gain=1
	local grow_cost_const=1
	local grow_cost_buffer=1.2
	local max_food=20000
	local food_drain=5
	local food_drain_hibernate=0.5
	--

	local w=img_buf.w
	local h=img_buf.h
	for i,v in ipairs(plants) do
		local x=v[1]
		local y=v[2]
		local moved=false

		local mytile=img_buf:get(x,y)
		if mytile.a~=pixel_types.plant_seed[4] then --check if not removed
			v.dead=true
		else
			--remove old pos
			img_buf:set(x,y,{0,0,0,0})
		end
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

				if math.random()>chance_up then
					-- prefer sunlit directions
					local right=is_sunlit(tx+1,ty)
					local left=is_sunlit(tx-1,ty)
					if math.random()<chance_sunlit and not(left== right) then
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
		if not v.growing then
			v.food=v.food-food_drain_hibernate
		else
			v.food=v.food-food_drain
		end

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
worms=worms or {}
if is_remade then worms={} end

function add_worm( x,y )
	local w=img_buf.w
	local h=img_buf.h
	x=x or math.random(0,w-1)
	y=y or 0
	table.insert(worms,{pixel_types.worm_body,food=500,dead=false,tail={{x,y}}})
	img_buf:set(x,y,pixel_types.worm_body)
end


function worm_step( )
	local surface_bias=0.08
	local grow_cost_const=500
	local grow_cost_buffer=2
	local max_food=20000
	local food_drain=0.1
	local food_drain_sun=10 --burn in sun
	local food_gain_plant_matter=20
	local food_gain_plant_seed=200
	--

	local w=img_buf.w
	local h=img_buf.h
	for i,v in ipairs(worms) do
		local x=v.tail[1][1]
		local y=v.tail[1][2]

		local want_move=true
		local want_growth=false
		--growth logic
		if v.food>grow_cost_const*grow_cost_buffer then
			want_growth=true
		end
		--movement logic
		local d=directions4[math.random(1,#directions4)]
		if math.random()<surface_bias then
			d={0,1}
		end
		local tx=d[1]+x
		local ty=d[2]+y
		if #v.tail>1 then
			local tdx=v.tail[2][1]-tx
			local tdy=v.tail[2][2]-ty
			if tdx==0 and tdy==0 then
				want_move=false
			end
		end

		local food_balance=0

		if want_move and is_valid_coord(tx,ty) then
			local d=img_buf:get(tx,ty)
			local eat_type=d.a
			if eat_type==pixel_types.dead_plant[4] then
				food_balance=food_balance+food_gain_plant_matter
			elseif eat_type==pixel_types.plant_seed[4] then
				food_balance=food_balance+food_gain_plant_seed
			elseif eat_type~=pixel_types.sand[4] then
				want_move=false
			end

			if want_move then
				local px=tx
				local py=ty
				for i=1,#v.tail do
					local ttx=v.tail[i][1]
					local tty=v.tail[i][2]

					v.tail[i][1]=px
					v.tail[i][2]=py
					img_buf:set(px,py,pixel_types.worm_body)
					px=ttx
					py=tty
				end
				if eat_type==pixel_types.sand[4] then
					img_buf:set(px,py,pixel_types.sand)
				else
					if want_growth then
						table.insert(v.tail,{px,py})
						img_buf:set(px,py,pixel_types.worm_body)
						food_balance=food_balance-grow_cost_const
					else
						img_buf:set(px,py,{0,0,0,0})
					end
				end
			end
		end
		for i,v in ipairs(v.tail) do
			if is_sunlit(v[1],v[2]) then
				food_balance=food_balance-food_drain_sun
			end
		end
		--ageing logic
		food_balance=food_balance-food_drain
		--growing logic
		v.food=v.food+food_balance
		if v.food>max_food then
			v.food=max_food
		end

		if v.food<=0 then
			v.dead=true
		end
		--readd new pos
		if v.dead then
			for i,v in ipairs(v.tail or {}) do
				img_buf:set(v[1],v[2],pixel_types.sand)
			end
		end
	end
	local tworms=worms
	worms={}
	for i,v in ipairs(tworms) do
		if not v.dead then
			table.insert(worms,v)
		end
	end
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function save_img(  )
	img_buf_save=make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	img_buf_save:read_frame()
	img_buf_save:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
tex_pixel=tex_pixel or textures:Make()
tex_sun=tex_sun or textures:Make()
need_save=false
function update()

	__no_redraw()
	__clear()
	imgui.Begin("ecology")
	draw_config(config)
	if imgui.Button("Kill plants") then
		for i,v in ipairs(plants) do
			v.dead=true
		end
	end
	imgui.SameLine()
	if imgui.Button("Reset world") then
		img_buf=nil
		update_img_buf()
		pixel_init()
		plants={}
		worms={}
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
	local md,x,y=is_mouse_down(  )
	if md then
		local tx,ty=math.floor(x*oversample),math.floor(img_buf.h-y*oversample)
		if tx<0 then tx=0 end
		if ty<0 then ty=0 end
		add_worm(tx,ty)
		
	end
	if math.random()>0.8 then
		add_plant()
	end
	if math.random()>0.99 and #worms<50 then
		add_worm()
	end
 	pixel_step( )
 	plant_step()
 	worm_step()
	draw_shader:use()
	tex_pixel:use(0,0,1)

	--tex_pixel.t:set(size[1]*oversample,size[2]*oversample,3)
	img_buf:write_texture(tex_pixel)
	tex_sun:use(1,0,1)
	sun_buffer:write_texture(tex_sun)

	draw_shader:set_i("tex_main",0)
	draw_shader:set_i("tex_sun",1)
	draw_shader:set("zoom",config.zoom)
	draw_shader:set("translate",config.t_x,config.t_y)
	draw_shader:set("sun_color",config.color[1],config.color[2],config.color[3],config.color[4])
	draw_shader:draw_quad()
	if need_save then
		save_img()
		need_save=false
	end

end
