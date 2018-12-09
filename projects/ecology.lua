require 'common'
require 'bit'
local win_w=1920/2
local win_h=950
__set_window_size(win_w,win_h)
local aspect_ratio=win_w/1024
local size=STATE.size

local oversample=0.25
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
	{"pause",false,type="bool"},
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
--[[
	pixel flags:
		sand/liquid/wall (2 bits?)
		block light (1 bit)
	left:
		5 bits-> 32 types
--]]
ph_wall=0
ph_sand=1
ph_liquid=2
--ph_gas=3
local flag_sets={
	[0]=0,--wall_block
	0, --wall_pass
	--
	0, --sand_block
	0, --sand_pass
	--
	0, --liquid_block
	0, --liquid_pass
}
function is_block_light( id )
	return bit.band(bit.rshift(id,5),1)~=0
end
function get_physics( id )
	return bit.band(bit.rshift(id,6),3)
end
function next_pixel_type_id( pixel_physics,block_light )
	local flag_id=bit.bor(block_light,bit.lshift(pixel_physics,1))
	flag_sets[flag_id]=flag_sets[flag_id]+1
	return bit.bor(bit.lshift(flag_id,5),flag_sets[flag_id])
end
local pixel_types={ --alpha used to id types
	sand         ={124,100,80 ,next_pixel_type_id(ph_sand  ,1)},
	dead_plant   ={50 ,20 ,30 ,next_pixel_type_id(ph_sand  ,1)},
	water        ={70 ,70 ,150,next_pixel_type_id(ph_liquid,0)},
	wall         ={20 ,80 ,100,next_pixel_type_id(ph_wall  ,1)},
	plant_seed   ={10 ,150,50 ,next_pixel_type_id(ph_wall  ,0)},
	worm_body    ={255,100,80 ,next_pixel_type_id(ph_wall  ,1)},
	tree_trunk   ={40 ,10 ,255,next_pixel_type_id(ph_wall  ,1)},
	plant_body   ={50 ,180,20 ,next_pixel_type_id(ph_wall  ,1)},
	plant_fruit  ={230,90 ,20 ,next_pixel_type_id(ph_wall  ,1)},
}
for k,v in pairs(pixel_types) do
	print(k,v[4],get_physics(v[4]),is_block_light(v[4]))
end
--TODO: test for collisions

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
	for i=1,5 do
		local platform_size=math.random(100,200)
		local x=math.random(0,w-1)
		local y=math.random(0,h-1)
		for i=1,platform_size do
			local d=directions4[math.random(1,#directions4)]
			local tx=x+d[1]
			local ty=y+d[2]
			if is_valid_coord(tx,ty) then
				x=tx
				y=ty
				img_buf:set(tx,ty,pixel_types.water)
			end
		end
	end
	for i=1,10 do
		local platform_size=math.random(100,200)
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
function swap_pixels( x,y,tx,ty )
	local d=img_buf:get(tx,ty)
	local dd={d.r,d.g,d.b,d.a}
	img_buf:set(tx,ty,img_buf:get(x,y))
	img_buf:set(x,y,dd)
end
function pixel_step(  )
	local w=img_buf.w
	local h=img_buf.h

	for x=0,w-1 do
		for y=1,h-1 do
			local c=img_buf:get(x,y)
			local ph=get_physics(c.a)

			if ph==ph_sand then
				local d=img_buf:get(x,y-1)
				if d.a==0 then
					img_buf:set(x,y-1,c)
					img_buf:set(x,y,{0,0,0,0})
				elseif get_physics(d.a)==ph_liquid then
					swap_pixels(x,y,x,y-1)
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
			elseif ph==ph_liquid then
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
			if is_block_light(c.a) then
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
	table.insert(plants,{x,y,pixel_types.plant_seed,food=1000,dead=false,growing=false})
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
	local chance_drift=0.3
	--costs and food
	local sun_gain=5
	local grow_cost_const=1
	local grow_cost_buffer=1.5
	local grow_cost_size=0.00075
	local fruit_cost_const=1
	local fruit_cost_buffer=1.2
	local max_fruit_size=100
	local fruit_chance_seed=0.05
	local max_food=20000
	local food_drain=5
	local food_drain_hibernate=0.75
	--
	local newplants={}
	local w=img_buf.w
	local h=img_buf.h
	local drop_fruit = false
	for i,v in ipairs(plants) do
		local x=v[1]
		local y=v[2]

		local mytile=img_buf:get(x,y)
		if mytile.a~=pixel_types.plant_seed[4] then --check if not removed
			v.dead=true
		end
		local food_balance=0
		--drop down
		if not v.growing then
			if y>0 then
				local tx=x
				local ty=y-1
				if math.random()<chance_drift then
					if math.random()>0.5 then
						tx=x-1
					else
						tx=x+1
					end
				end
				local d=img_buf:get(tx,ty)
				local ph=get_physics(d.a)
				if ph==2 or d.a==0 then
					v[1]=tx
					v[2]=ty
					swap_pixels(x,y,tx,ty)
				elseif d.a==pixel_types.sand[4] then
					if is_sunlit(x,y) then
						v[3][1]=255
						v.growing=true
					end
				end
			end
		else
			--growing logic
			local tbl=v.path or {}
			v.path=tbl

			for i,v in ipairs(v.path) do
				if is_sunlit(v[1],v[2]) then
					food_balance=food_balance+sun_gain
				end
			end
			local tx = x
			local ty = y
			if #v.path >0 then
				tx=v.path[#v.path][1]
				ty=v.path[#v.path][2]
			end
			local grow_cost=grow_cost_const+(#v.path*#v.path)*grow_cost_size--+math.max(ty*2-25,0)
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
					local ph=get_physics(d.a)
					if d.a==0 or ph==2 then
						table.insert(v.path,{tx,ty})
						img_buf:set(tx,ty,pixel_types.plant_body)
						food_balance=food_balance-grow_cost
					end
				end
			elseif (#v.path>8 and food_balance>fruit_cost_const*fruit_cost_buffer) then
				local p
				local tx
				local ty
				
				if v.has_fruit then
					p=v.has_fruit[math.random(1,#v.has_fruit)]
					local dd=directions4[math.random(1,#directions4)]
					tx=p[1]+dd[1]
					ty=p[2]+dd[2]
				else
					p=v.path[math.random(1,#v.path)]
					tx=p[1]
					ty=p[2]-1
				end
				
				if is_valid_coord(tx,ty) and img_buf:get(tx,ty).a==0 then
					if v.has_fruit then
						table.insert(v.has_fruit,{tx,ty})
						if #v.has_fruit>=max_fruit_size then
							drop_fruit=true
						end
					else
						v.has_fruit={{tx,ty}}
					end
					food_balance=food_balance-fruit_cost_const
					img_buf:set(tx,ty,pixel_types.plant_fruit)
				end

			end
		end
		--ageing logic
		if not v.growing then
			food_balance=food_balance-food_drain_hibernate
		else
			food_balance=food_balance-food_drain
		end

		v.food=v.food+food_balance
		if v.food>max_food then
			v.food=max_food
		end
		if v.food<=0 then
			v.dead=true
		end
		

		if v.dead then
			img_buf:set(x,y,pixel_types.dead_plant)
			for i,v in ipairs(v.path or {}) do
				img_buf:set(v[1],v[2],pixel_types.dead_plant)
			end
		else
			--img_buf:set(x,y,v[3])
		end
		if drop_fruit or v.dead then
			if v.has_fruit then
				for i,v in ipairs(v.has_fruit) do
					img_buf:set(v[1],v[2],pixel_types.dead_plant)
				end
				local no_seeds=math.random(0,math.floor(#v.has_fruit*fruit_chance_seed))
				for i=1,no_seeds do
					local s=v.has_fruit[math.random(1,#v.has_fruit)]
					--TODO: do not overwrite seeds by seeds
					table.insert(newplants,{s[1],s[2],pixel_types.plant_seed,food=1000,dead=false,growing=false})
					img_buf:set(s[1],s[2],pixel_types.plant_seed)
				end
				v.has_fruit=nil
			end
		end
	end
	for i,v in ipairs(plants) do
		if not v.dead then
			table.insert(newplants,v)
		end
	end
	plants=newplants
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
	local food_drain_sun=20 --burn in sun
	local food_gain_plant_matter=20
	local chance_new_worm=0.2
	--
	local newworms={}
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
			elseif eat_type==pixel_types.worm_body[4] then
				for i,t in ipairs(v.tail) do
					if tx==t[1] and ty==t[2] then
						for i,v in ipairs(v.tail) do
							img_buf:set(v[1],v[2],pixel_types.sand)
						end
						local new_worm_count=math.random(0,#v.tail*chance_new_worm)
						for i=1,new_worm_count do
							local g=v.tail[math.random(1,#v.tail)]
							local tx=g[1]
							local ty=g[2]
							table.insert(worms,{pixel_types.worm_body,food=500,dead=false,tail={{tx,ty}}})
							img_buf:set(tx,ty,pixel_types.worm_body)
						end
						v.tail={{x,y}}
						img_buf:set(x,y,pixel_types.worm_body)
						want_move=false
						break
					end
				end
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
		for i,t in ipairs(v.tail) do
			if img_buf:get(t[1],t[2]).a~=pixel_types.worm_body[4] then
				v.dead=true
			end
			if is_sunlit(t[1],t[2]) then
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

	for i,v in ipairs(worms) do
		if not v.dead then
			table.insert(newworms,v)
		end
	end
	worms=newworms
end
trees=trees or {}
function add_tree( x,y )
	x=x or math.floor(img_buf.w/2)
	y=y or (img_buf.h-1)

	table.insert(trees,{pixel_types.plant_seed,growing=false,dead=false,
		cells={{pos=Point(x,y),type="seed"}},
		height=0,
		growth_ticks=500,
		})
	img_buf:set(x,y,pixel_types.plant_seed)
end
function concat_tables(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end
function norm_coord( t )
	local dist=math.sqrt(t[1]*t[1]+t[2]*t[2])
	t[1]=t[1]/dist
	t[2]=t[2]/dist
end
function try_grow( pcenter,dir, valid_a)
	local trg=pcenter+dir
	if not is_valid_coord(trg[1],trg[2]) then
		return false
	end
	local d=img_buf:get(trg[1],trg[2])
	if valid_a then
		return valid_a[d.a]
	else
		return d.a==0
	end
end
function read_directions8( pcenter )
	local ret={}
	for i,v in ipairs(directions8) do
		local x=pcenter[1]+v[1]
		local y=pcenter[2]+v[2]
		if is_valid_coord(x,y) then
			ret[i]=img_buf:get(x,y).a
		end
	end
	return ret
end
function read_directions4( pcenter )
	local ret={}
	for i,v in ipairs(directions4) do
		local x=pcenter[1]+v[1]
		local y=pcenter[2]+v[2]
		if is_valid_coord(x,y) then
			ret[i]=img_buf:get(x,y).a
		end
	end
	return ret
end
function max_w_stress_based( mydelta ,max_w,max_h,current_h)
	local grow_amount=current_h/max_h --how much current growth is
	local v=mydelta[2]/max_h
	return math.max(grow_amount*max_w*(1-v),1)
end
function fract_move(cell, dist,dir )
	cell.fract=cell.fract+dist*dir
	local step=Point(0,0)
	if cell.fract[1]>1 then
		step[1]=1
		cell.fract[1]=cell.fract[1]-1
	elseif cell.fract[1]<-1 then
		step[1]=-1
		cell.fract[1]=cell.fract[1]+1
	end

	if cell.fract[2]>1 then
		step[2]=1
		cell.fract[2]=cell.fract[2]-1
	elseif cell.fract[2]<-1 then
		step[2]=-1
		cell.fract[2]=cell.fract[2]+1
	end
	return step
end
function next_pixel( dir )
	local m=math.max(math.abs(dir[1]),math.abs(dir[2]))
	return Point(dir[1]/m,dir[2]/m)
end
function tree_step(  )
	--super config
	--growth stuff
	local height_per_tick=0.05
	local sun_bias=0.005

	local width_per_tick=0.01
	local chance_change_dir=0.1
	local chance_split=0.005
	local chance_bud = 0.01
	local bend_amount=0.2
	local split_amount=0.3
	local max_w=6
	local max_h=300
	--

	local w=img_buf.w
	local h=img_buf.h
	for i,v in ipairs(trees) do
		local moved=false

		--drop down
		if not v.growing then
			local pos=v.cells[1].pos
			
			if pos[2]>0 then
				local d=img_buf:get(pos[1],pos[2]-1)
				if d.a==0 then
					img_buf:set(pos[1],pos[2],{0,0,0,0})
					pos[2]=pos[2]-1
					img_buf:set(pos[1],pos[2],pixel_types.tree_trunk)
					moved=true
				elseif d.a==pixel_types.sand[4] then
					--if is_sunlit(pos[1],pos[2]) then
						v.growing=true
						v.cells[1].type="top"
						v.cells[1].delta=Point(0,0)
						v.cells[1].dir=Point(0,1)
						v.cells[1].fract=Point(0,0)
					--end
				end
			end
		else
			--growing logic
			local tbl=v.cells
			local to_add={}
			if v.growth_ticks>0 then
				for i,cell in ipairs(tbl) do
					if cell.type=="top" then
						local pos=cell.pos
						local dir=cell.dir

						if is_sunlit(pos[1],pos[2]) then
							dir[2]=dir[2]+sun_bias
						elseif math.random()<chance_change_dir then
							dir[1]=dir[1]+math.random()*bend_amount-bend_amount/2
						end
						dir:normalize()
						cell.dir=dir
						local step=fract_move(cell,height_per_tick,cell.dir)
						local new_pos=pos+step
						local do_grow=true
						--if not is_valid_coord(new_pos[1],new_pos[2]-1) or img_buf:get(new_pos[1],new_pos[2]-1).a==0 then
						--	do_grow=false
						--end
						if do_grow and try_grow(pos,step) then
							local t="skin"
							if math.random()<chance_bud then
								t="dorm_bud"
							end
							table.insert(to_add,
							{
								pos=Point(pos[1],pos[2]),
								delta=Point(0,v.height),
								type=t,
								dir=Point(-cell.dir[2],cell.dir[1]),
							})
							v.height=v.height+1
							cell.pos=new_pos
							if v.height>=max_h then
								cell.type="skin"
								cell.delta=Point(0,v.height)
							end
						end
					elseif cell.type=="skin" or cell.type=="dorm_bud" then
						local pos=cell.pos
						local d=read_directions4(pos)
						local inside=true

						for i=1,4 do
							if d[i]==0 then
								inside=false
							end
						end
						local max_w_act=max_w_stress_based(cell.delta,max_w,max_h,v.height)
						local do_grow=true
						local my_dir=Point(cell.dir[1],cell.dir[2])
						
						if math.random()>0.5 then
							my_dir=(-1)*my_dir
						end
						local step=next_pixel(my_dir)

						if is_valid_coord(step[1],step[2]) and img_buf:get(step[1],step[2]).a==0 then
							local dd=math.floor(step[1])
							
							local new_delta=cell.delta+Point(dd[1],dd[2])
							if dd[1]~=0 then
								if math.abs(new_delta[1])>max_w_act then
									do_grow=false
									if cell.type=="dorm_bud" then

									end
								end
							end
							if do_grow then
								table.insert(to_add,
								{
									pos=Point(pos[1],pos[2]),
									delta=cell.delta,
									type="skin"
								})
								cell.delta=new_delta
								cell.pos=Point(pos[1]+dd[1],pos[2]+dd[2])
							end
							
						end
						if inside then
							cell.type="inside"
						end
					end
				end

				v.cells=concat_tables(tbl,to_add)
				--v.growth_ticks=v.growth_ticks-1
			end
			for i,v in ipairs(v.cells) do
				if is_valid_coord(v.pos[1],v.pos[2]) then
					if v.type=="skin" then
						img_buf:set(v.pos[1],v.pos[2],pixel_types.tree_trunk)
					else
						img_buf:set(v.pos[1],v.pos[2],pixel_types.plant_seed)
					end
				end
			end
		end
		
	end

	local ttrees=trees
	trees={}
	for i,v in ipairs(ttrees) do
		if not v.dead then
			table.insert(trees,v)
		end
	end
end
function is_mouse_down(  )
	local ret=__mouse.clicked1 and not __mouse.owned1
	if ret then
		current_down=true
	end
	if __mouse.released1 then
		current_down=false
	end
	return current_down, __mouse.x,__mouse.y
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
		trees={}
	end

	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	--if imgui.Button("Add trees") then
	--	add_tree()
	--end
	imgui.End()
	local md,x,y=is_mouse_down(  )
	if md then
		local tx,ty=math.floor(x*oversample),math.floor(img_buf.h-y*oversample)
		if is_valid_coord(tx,ty) then
			img_buf:set(tx,ty,pixel_types.wall)
		end
	end
	--[[
	if md then
		if tx<0 then tx=0 end
		if ty<0 then ty=0 end
		add_worm(tx,ty)
	end
	]]
	-- [[
	if not config.pause then
		if math.random()>0.8 and #plants<50 then
			add_plant()
		end
		if math.random()>0.99 and #worms<50 then
			add_worm()
		end
		--print("Worms:",#worms)
		--print("Plants:",#plants)
	 	--]]
	 	pixel_step( )
	 	--tree_step()
	 	plant_step()
	 	worm_step()
	end
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
