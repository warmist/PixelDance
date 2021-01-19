--[===[
some ideas:
	* voronoi centers with 1d CA outwards
	* CA with "rule switches"
		- on borders?
		- on smooth noise
		- on some value (e.g. region alive count >0.5)
	* more complicated N state CA
--]===]
require "common"
local size=STATE.size
visits=visits or make_flt_buffer(size[1],size[2])

function resize( w,h )
	visits=make_flt_buffer(size[1],size[2])
end

pos=pos or {STATE.size[1]/2,STATE.size[2]/2}

local draw_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;


uniform sampler2D tex_main;

uniform float current_y;

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	normed.y=1-normed.y;
	vec3 col=texture(tex_main,normed).xyz;
	//float min_v=0.9;
	//float d=clamp(1-max(-normed.y+current_y,0),min_v,1);
	//if(current_y<normed.y)
	//	d=min_v;
	//d=pow(d,10);
	float d=1;
	color = vec4(col*d,1);
}
]==]
local need_save
local visit_tex = textures.Make()
last_pos=last_pos or {0,0}
function save_img(tile_count)
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	image_no=image_no+1
end
local current_y=1
local min_r=5
local current_r=min_r
function draw_visits(  )

	draw_shader:use()
	visit_tex:use(0)
	visits:write_texture(visit_tex)
	draw_shader:set_i("tex_main",0)
	draw_shader:set("current_y",current_r/size[2])
	draw_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
end

function resize( w,h )
	image=make_image_buffer(w,h)
end
CA_rule={
	[1]=1,
	[2]=1,
	[3]=1,
	[5]=1,
	[6]=1,
}
local cx=math.floor(size[1]/2)
local cy=math.floor(size[2]/2)

function reset_buffer(  )
	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local c=visits:get(x,y)
		c.r=math.random()
			c.g=math.random()
			c.b=math.random()
	end
	end
	--[[
	for x=0,size[1]-1 do
		local c=visits:get(x,0)
		c.r=math.random()
		c.g=math.random()
		c.b=math.random()
	end
	]]
	local radius=min_r
	for r=0,radius do
		local step=math.atan(1/size[1],r)
		for phi=0,math.pi*2,step do
			local tx=math.floor(cx+math.cos(phi)*r)
			local ty=math.floor(cy+math.sin(phi)*r)
			local c=visits:get(tx,ty)
			c.r=math.random()
			c.g=math.random()
			c.b=math.random()
		end
	end
end
reset_buffer()
function get_points_rect(x,y)
	local ret={}
	local nx=x+1
	if nx>=size[1] then nx=0 end
	local px=x-1
	if px<0 then px=size[1]-1 end
	ret[1]=visits:get(px,y)
	ret[2]=visits:get(x,y)
	ret[3]=visits:get(nx,y)
	return ret
end
function get_points(phi,rad,phisize)
	local ret={}
	local a={
	phi+phisize,
	phi,
	phi-phisize
	}
	for i=1,3 do
		local tx=math.floor(cx+math.cos(a[i])*rad)
		local ty=math.floor(cy+math.sin(a[i])*rad)
		ret[i]=visits:get(tx,ty)
	end
	return ret
end
function get_rule( pts )
	local ret=0
	for i,v in ipairs(pts) do
		if v.r>0.5 then
			ret=ret+math.pow(2,i-1)
		end
	end
	return CA_rule[ret] or 0
end

function gui(  )
	imgui.Begin("CA")
	if imgui.Button("Reset") then
		reset_buffer()
		current_y=1
		current_r=min_r
	end
	imgui.End()
end

function update(  )
	__no_redraw()
	__clear()
	gui()
	for step=1,10 do
		local step_size=math.atan(1/size[1],current_r)
		for phi=0,math.pi*2,step_size do
			local tx=math.floor(cx+math.cos(phi)*current_r)
			local ty=math.floor(cy+math.sin(phi)*current_r)
			local c_out=visits:get(tx,ty)
			local pr=current_r-1
			if pr<min_r-1 then pr=math.floor(size[1]/2)-1 end
			local step_size_p=math.atan(1/size[1],pr)
			local input=get_points(phi,pr,step_size_p)
			local v=get_rule(input)
			if v>0.5 then
				c_out.r=1
				c_out.g=1
				c_out.b=1
			else
				c_out.r=0
				c_out.g=0
				c_out.b=0
			end
		end
		--[[
		for x=0,size[1]-1 do
			local py=current_y-1
			if py<0 then py=size[2]-1 end
			local input=get_points(x,py)
			local c_out=visits:get(x,current_y)
			local v=get_rule(input)
			if v>0.5 then
				c_out.r=1
				c_out.g=1
				c_out.b=1
			else
				c_out.r=0
				c_out.g=0
				c_out.b=0
			end
		end
		current_y=current_y+1
		if current_y>=size[2] then current_y=0 end
		--]]
		current_r=current_r+1
		if current_r>=size[1]/2 then current_r=min_r end
	end
	draw_visits()
end