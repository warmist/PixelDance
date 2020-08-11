require "common"

local size=STATE.size
local max_size=math.min(size[1],size[2])/2
img_buf=img_buf or make_image_buffer(size[1],size[2])
visits=visits or make_flt_buffer(size[1],size[2])
function resize( w,h )
	visits=make_flt_buffer(size[1],size[2])
	img_buf=make_image_buffer(size[1],size[2])
end

config=make_config({
	{"k",1,type="float"},
	{"dt",0.002,type="float"},
	{"decay",0,type="float"},
	{"auto_dt",true,type="boolean"},
	{"steps",1,type="int"},
	{"do_log_normed",false,type="boolean"},
	{"verlet",false, type="boolean"},
	},config)
object_list=object_list or {}
image_no=image_no or 0

function is_mouse_down(  )
	return __mouse.clicked0 and not __mouse.owned0, __mouse.x,__mouse.y
end
function interact_objects(o1,o2,dt)
	local m=1
	local q1=o1.q or 1
	local q2=o2.q or 1
	--F=ma => a=F/m
	--v=v+a*dt
	local offset_to_check={
		{0,0},
		{ size[1],0},
		{-size[1],0},
		{ 0,-size[2]},
		{ 0,size[2]},
		{ -size[1],-size[2]},
		{ size[1],size[2]},
		{ -size[1],size[2]},
		{ size[1],-size[2]},
		--TODO add more?
	}
	local fx,fy=0,0
	for i,v in ipairs(offset_to_check) do
		local dx=o2.x-o1.x+v[1]
		local dy=o2.y-o1.y+v[2]
		local r2=dx*dx+dy*dy
		fx=fx+dx/r2
		fy=fy+dy/r2
	end
	fx=fx*config.k*q1*q2
	fy=fy*config.k*q1*q2
	local ax=fx/m
	local ay=fy/m
	o1.ax=o1.ax+ax
	o1.ay=o1.ay+ay

	o2.ax=o2.ax-ax
	o2.ay=o2.ay-ay
end
function update_objects(  )
	--local static_obj={x=size[1]/2,y=size[2]/2,ax=0,ay=0,q=-1}
	for i,v in ipairs(object_list) do
		v.ax=0
		v.ay=0
		--interact_objects(object_list[i],static_obj,config.dt)
	end
	for i=1,#object_list-1 do
		for j=i+1,#object_list do
			interact_objects(object_list[i],object_list[j],config.dt)
		end
	end
	if config.auto_dt then
		local max_dv2=0
		for i,v in ipairs(object_list) do
			local dv=v.vx*v.vx+v.vy*v.vy
			if max_dv2<dv then max_dv2=dv end
		end
		max_dv2=math.sqrt(max_dv2)
		config.dt=(1-0.0001)/max_dv2
		if config.dt>1 then
			config.dt=1
		end
	end
	local dt=config.dt

	for i,v in ipairs(object_list) do
		if config.verlet then
			local nx=v.x*2-v.lx+v.ax*dt*dt
			local ny=v.y*2-v.ly+v.ay*dt*dt

			v.lx=v.x
			v.ly=v.y
			v.x=nx
			v.y=ny
		else
			v.vx=v.vx+v.ax*dt
			v.vy=v.vy+v.ay*dt

			v.x=v.x+v.vx*dt
			v.y=v.y+v.vy*dt
		end
		v.vx=v.vx*(1-config.decay)
		v.vy=v.vy*(1-config.decay)
		if v.x>=size[1] then
			v.x=v.x-size[1]
		end
		if v.y>=size[2] then
			v.y=v.y-size[2]
		end
		if v.x<0 then
			v.x=v.x+size[1]
		end
		if v.y<0 then
			v.y=v.y+size[2]
		end
	end
	
end
local log_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec2 min_max;
uniform sampler2D tex_main;
uniform int auto_scale_color;


void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec3 col=texture(tex_main,normed).xyz;
	vec2 lmm=min_max;

	if(auto_scale_color==1)
		col=(log(col+vec3(1,1,1))-vec3(lmm.x))/(lmm.y-lmm.x);
	else
		col=log(col+vec3(1))/lmm.y;
	col=clamp(col,0,1);
	//nv=math.min(math.max(nv,0),1);
	//--mix(pix_out,c_u8,c_back,nv)
	//mix_palette(pix_out,nv)
	//img_buf:set(x,y,pix_out)
	color = vec4(col,1);
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
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	image_no=image_no+1
end
function draw_visits(  )
	local lmax=0
	local lmin=math.huge
	local vst=visits

	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local vp=vst:get(x,y)
		local v=vp.r*vp.r+vp.g*vp.g+vp.b*vp.b
		if lmax<v then lmax=v end
		if lmin>v then lmin=v end
	end
	end
	lmax=math.log(math.sqrt(lmax)+1)
	lmin=math.log(math.sqrt(lmin)+1)
	log_shader:use()
	visit_tex:use(0)
	visits:write_texture(visit_tex)
	log_shader:set("min_max",lmin,lmax)
	log_shader:set_i("tex_main",0)
	local auto_scale=1
	--if config.auto_scale_color then auto_scale=1 end
	log_shader:set_i("auto_scale_color",auto_scale)
	log_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
end
function update_image()
	local mm=0
	for x=0,size[1]-1 do
	for y=0,size[2]-1 do

		local v=visits:get(x,y)
		local vv=v.r*v.r+v.g*v.g+v.b*v.b
		if mm<vv then mm=vv end
	end
	end
	mm=math.log(math.sqrt(mm))

	local pix_out = pixel()
	

	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local v=visits:get(x,y)
		local nvr=math.log(v.r)/mm
		local nvg=math.log(v.g)/mm
		local nvb=math.log(v.b)/mm
		nvr=math.min(math.max(nvr,0),1)
		nvg=math.min(math.max(nvg,0),1)
		nvb=math.min(math.max(nvb,0),1)
		img_buf:set(x,y,{nvr*255,nvg*255,nvb*255,255})
	end
	end

	img_buf:present()
end
function rand_color(  )
	if config.do_log_normed then
		return {math.random(),math.random(),math.random(),255}
	else
		return {math.random(0,255),math.random(0,255),math.random(0,255),255}
	end
end

function create_object( x,y,color,vx,vy ,ax,ay)
	vx=vx or 0
	vy=vy or 0
	local lx=x-vx*config.dt
	local ly=y-vy*config.dt

	table.insert(object_list,{x=x,y=y,color=color or rand_color(),vx=vx, vy=vy,ax=ax or 0,ay=ay or 0,lx=lx,ly=ly})
end
tick_num=tick_num or 0
function update(  )
	
	local m,x,y=is_mouse_down()
	if m then
		create_object(x,y)
	end
	imgui.Begin("Objects in space")
	draw_config(config)
	if imgui.Button("Save image") then
		img_buf:save("saved_"..image_no..".png","Saved by PixelDance")
		image_no=image_no+1
	end
	if imgui.Button("Clear") then
		img_buf:clear()
		visits:clear()
	end
	if imgui.Button("Clear Objects") then
		object_list={}
	end
	if imgui.Button("Add") then
		local cx=size[1]/2
		local cy=size[2]/2
		local count=7
		for i=0,math.pi*2-0.01,math.pi*2/count do
			local speed=0.1
			create_object(cx+math.cos(i)*size[1]/8,cy+math.sin(i)*size[2]/8,nil,-math.sin(i)*speed,math.cos(i)*speed)
		end
	end
	for i=1,config.steps do
		update_objects()
		if config.do_log_normed then
			for i,v in ipairs(object_list) do
				local c=visits:get(math.floor(v.x),math.floor(v.y))
				c.r=c.r+v.color[1]
				c.g=c.g+v.color[2]
				c.b=c.b+v.color[3]

				--img_buf:set(math.floor(v.x),math.floor(v.y),c)
			end
		else
			for i,v in ipairs(object_list) do
				--if i==1 then
					img_buf:set(math.floor(v.x),math.floor(v.y),v.color)
				--end
			end
		end
	end
	if config.do_log_normed then
		__no_redraw()
		__clear()
		draw_visits()
	else
		img_buf:present()
	end
	imgui.End()
end