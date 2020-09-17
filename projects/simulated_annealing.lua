--try some simulated annealing image-stuff
--[[
	idea: pixels/objects get "score" due to near objects, anneal to maximize
--]]

require "common"

local size=STATE.size
local zoom=3

grid=grid or make_float_buffer(math.floor(size[1]/zoom),math.floor(size[2]/zoom))
function resize( w,h )
	grid=make_float_buffer(math.floor(w/zoom),math.floor(h/zoom))
end

config=make_config({
	{"temperature",1,type="float"},
	{"dt",0.002,type="floatsci",min=0.000001,max=0.005},
	{"percent_update",0.3,type="float"},
	{"max_dist_moved",10, type="int",min=0,max=grid.w},
	{"fixed_colors",false, type="boolean"},
	{"paused",true, type="boolean"},
	},config)

local draw_shader=shaders.Make[==[
#version 330
#line 22
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float count_steps;

vec3 palette(float v)
{
	vec3 a=vec3(0.5,0.5,0.5);
	vec3 b=vec3(0.5,0.5,0.5);
	vec3 c=vec3(1,1,0.5);
	vec3 d=vec3(0.8,0.9,0.3);
	return a+b*cos(3.1459*2*(c*v+d));
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float col=texture(tex_main,normed).x;
	if(count_steps>0)
		col=floor(col*count_steps)/count_steps;
	color = vec4(palette(col),1);
	//color.xyz=vec3(col);
	//color.w=1;
}
]==]
local ruleset={
	[1]={-0.1,0.1,0,1,4},
	[2]={1,1,0,-1,1},
	[3]={0,1,1,1,-4},
	[4]={-0.1,0.1,1,-0.2,0},
	--[5]={-0.1,0.1,1,0.2,0.1},
}
function randomize_ruleset(count )
	local ret={}
	for i=1,count do
		local tbl={}
		for i=1,count do
			tbl[i]={math.random()*8-4,math.random()*2-1}
		end
		ret[i]=tbl
	end
	ruleset=ret
end
--randomize_ruleset(4)
function parse_ruleset(  )
	local ret={}
	for k,v in pairs(ruleset) do
		if type(v)=="table" then
			local tbl={}
			for i,vv in ipairs(v) do
				if type(vv)=="number" then
					tbl[i]={const=vv,mult=1}
				else
					tbl[i]={const=vv[1],mult=vv[2]}
				end
			end
			ret[k]=tbl
		else
			ret[k]=v
		end
	end
	return ret
end
local parsed_ruleset=parse_ruleset()

local num_values=#ruleset

function coord_edge( x,y )
	--[[ loop
	if x<0 then x=grid.w+x end
	if y<0 then y=grid.h+y end
	if x>=grid.w then x=x-grid.w end
	if y>=grid.h then y=y-grid.h end
	--]]
	-- [[ bounce
	if x<0 then x=-x end
	if y<0 then y=-y end
	if x>=grid.w then x=grid.w*2-x-1 end
	if y>=grid.h then y=grid.h*2-y-1 end
	--]]
	--[[ mixed
	if x<0 then x=-x end
	if y<0 then y=grid.h+y end
	if x>=grid.w then x=grid.w*2-x-1 end
	if y>=grid.h then y=y-grid.h end
	--]]
	return x,y

end
function get_around( x,y )
	local ret={}
	local dx={-1,-1,-1,0,0,1,1,1}
	local dy={-1,0,1,-1,1,-1,0,1}
	for i=1,#dx do
		local tx=x+dx[i]
		local ty=y+dy[i]
		tx,ty=coord_edge(tx,ty)

		--if tx<grid.w or ty<grid.h or tx>=0 or ty>=0 then
			local v=math.floor(grid:get(tx,ty)*num_values)
			ret[i]=v
		--else
		--ret[i]=0
		--end
	end
	return ret
end
function calculate_value( x,y,v)
	local a=get_around(x,y)
	local r=parsed_ruleset[v+1]
	local ret=0
	if type(r)=="function" then
		return r(a,v,x,y)
	end

	for i,vv in ipairs(a) do
		local rule=r[vv+1]
		ret=rule.const+rule.mult*ret
	end
	return ret
end
function round(n)
    return n % 1 >= 0.5 and math.ceil(n) or math.floor(n)
end
function random_in_circle( dist )
	local r=math.sqrt(math.random())*dist
	local a=math.random()*math.pi*2
	return round(math.cos(a)*r),round(math.sin(a)*r)
end
function delta_substep( v )
	--return v
	return v-0.5
	--return math.sin(v*math.pi)*2+1.5
	--return (math.cos(v*math.pi*2)+1)*0.5*0.3+0.7
	--return 1
end
function do_grid_step(x,y)

	local rv=grid:get(x,y)
	local v=math.floor(rv*num_values)
	--[[
	local dx={-1,-1,-1,0,0,1,1,1}
	local dy={-1,0,1,-1,1,-1,0,1}

	local tx=x+dx[math.random(1,#dx)]
	local ty=y+dy[math.random(1,#dy)]
	--]]
	-- [[
	local max_dist=config.max_dist_moved*config.temperature+1
	--local max_dist=config.max_dist_moved
	local dx,dy=random_in_circle(max_dist)
	local tx=x+dx
	local ty=y+dy
	--]]
	tx,ty=coord_edge(tx,ty)
	--[[if tx>=grid.w or ty>=grid.h or tx<0 or ty<0 then
		return
	end]]
	local trv=grid:get(tx,ty)
	local tv=math.floor(trv*num_values)
	--if tv==0 then

		local old_value=calculate_value(x,y,v)*delta_substep(rv*num_values-v)
		local old_trg_value=calculate_value(tx,ty,tv)*delta_substep(trv*num_values-tv)
		local new_trg_value=calculate_value(tx,ty,v)*delta_substep(rv*num_values-v)
		local new_value=calculate_value(x,y,tv)*delta_substep(trv*num_values-tv)

		if (old_value+old_trg_value)*(1-config.temperature)<(new_value+new_trg_value)*(1-config.temperature)+config.temperature then
			--[[
			grid:set(x,y,tv/num_values)
			grid:set(tx,ty,v/num_values)
			--]]
			grid:set(x,y,trv)
			grid:set(tx,ty,rv)
			return tx,ty
		end
	--end

end
function update_grid(  )
	if config.temperature<=0 then
		return
	end

	for x=0,grid.w-1 do
		for y=0,grid.h-1 do
			if math.random()<config.percent_update then
				local nx=x
				local ny=y
				nx,ny=do_grid_step(nx,ny)
				--[[for i=1,config.max_dist_moved do
					if nx==nil then break end
					nx,ny=do_grid_step(nx,ny)

				end]]
			end
		end
	end
end
function save_img(  )
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    config_serial=config_serial..serialize_config(config)
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
grid_tex =grid_tex or textures.Make()
function draw_grid(  )
	draw_shader:use()
	grid_tex:use(0)
	grid:write_texture(grid_tex)
	draw_shader:set_i("tex_main",0)
	if config.fixed_colors then
		draw_shader:set("count_steps",num_values)
	else
		draw_shader:set("count_steps",-1)
	end
	draw_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end

function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Objects in space")
	draw_config(config)
	
	if imgui.Button("Restart") then
		for x=0,grid.w-1 do
		for y=0,grid.h-1 do
			--grid:set(x,y,math.random())
			--grid:set(x,y,(x*0.9/grid.w+math.random()*0.1))
			-- [[
			local dx=(x-grid.w/2)
			local dy=(y-grid.h/2)
			local len=math.sqrt(dx*dx+dy*dy)/(0.7*grid.w)
			if len>1 then len=1 end
			if y>grid.h/2 then
				grid:set(x,y,(len*0.9+math.random()*0.1))
			else
				grid:set(x,y,1-(len*0.9+math.random()*0.1))
			end
			--]]
		end
		end
		config.temperature=1
		--config.paused=false
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
	if not config.paused then
		update_grid()
		--config.temperature=config.temperature-config.dt --linear cooling
		config.temperature=config.temperature*(1-config.dt) --exponential cooling
		if config.temperature<=0.000001 then
			config.paused=true
		end
	end
	draw_grid()
end