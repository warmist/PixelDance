
require "common"

local size=STATE.size
local max_size=math.min(size[1],size[2])/2

img_buf=img_buf or make_image_buffer(size[1],size[2])
visits=visits or make_flt_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
	visits=make_flt_buffer(size[1],size[2])
end

local max_size=math.min(STATE.size[1],STATE.size[2])/2
local size=STATE.size
function make_copy( tbl )
	local ret={}
	for k,v in pairs(tbl) do
		ret[k]=v
	end
	return ret
end

config=make_config({
	{"edit",false,type="boolean"},
	{"steps",100,type="int",min=1,max=1000},
	{"particle_steps",1000,type="int",min=100,max=100000},
	{"auto_draw",false,type="boolean"},
	{"auto_scale_color",true,type="boolean"},
	},config)
object_list=object_list or {}
image_no=image_no or 0

function is_mouse_down(  )
	return __mouse.clicked0 and not __mouse.owned0, __mouse.x,__mouse.y
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
	local auto_scale=0
	if config.auto_scale_color then auto_scale=1 end
	log_shader:set_i("auto_scale_color",auto_scale)
	log_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
end
function update_image()
	draw_visits()
	--[[
	local mm=0
	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local v=visits:get(x,y)
		local vv=v.r*v.r+v.g*v.g+v.b*v.b
		if mm<vv then mm=vv end
	end
	end
	mm=math.log(math.sqrt(mm))
	print(mm)
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
	--]]
end
function rand_color(  )
	return {math.random(),math.random(),math.random(),255}
end
function create_object( x,y,obj_type )
	local cfg={}
	for k,v in pairs(obj_type.config) do
		cfg[k]=v
	end
	table.insert(object_list,{x=x,y=y,config=cfg,apply=obj_type.apply,tick=obj_type.tick})
end
function apply_objects( v )
	for i,t in ipairs(object_list) do
		if t.apply then
			t.apply(t,v)
		end
	end
end
function iterate( v )
	for i=1,config.particle_steps do
		apply_objects(v)
		if not(v.x<0 or v.x>=size[1]-1 or v.y<0 or v.y>=size[2]-1) then
			local c=visits:get(math.floor(v.x),math.floor(v.y))
			c.r=c.r+v.color[1]
			c.g=c.g+v.color[2]
			c.b=c.b+v.color[3]
			c.a=c.a+v.color[4]
		end
	end
end
--[[
function iterate_mirror_x( v )
	for i=1,config.particle_steps do
		apply_objects(v)
		if v.x<0 or v.x>=size[1]-1 or v.y<0 or v.y>=size[2]-1 then
			break
		end

		local c=dbl_buf:get(math.floor(v.x),math.floor(v.y))
		c.r=c.r+v.color[1]
		c.g=c.g+v.color[2]
		c.b=c.b+v.color[3]
		c.a=c.a+v.color[4]
		local mx=size[1]-v.x
		if mx>=0 and mx<size[1]-1 and v.y>=0 and v.y<size[2]-1 then
			c=dbl_buf:get(math.floor(mx),math.floor(v.y))
			c.r=c.r+v.color[1]
			c.g=c.g+v.color[2]
			c.b=c.b+v.color[3]
			c.a=c.a+v.color[4]
		end
		
	end
end
function iterate_mirror_y( v )
	for i=1,config.particle_steps do
		apply_objects(v)
		if v.x<0 or v.x>=size[1]-1 or v.y<0 or v.y>=size[2]-1 then
			break
		end

		local c=dbl_buf:get(math.floor(v.x),math.floor(v.y))
		c.r=c.r+v.color[1]
		c.g=c.g+v.color[2]
		c.b=c.b+v.color[3]
		c.a=c.a+v.color[4]
		local my=size[2]-v.y
		if v.x>=0 and v.x<size[1]-1 and my>=0 and my<size[2]-1 then
			c=dbl_buf:get(math.floor(v.x),math.floor(my))
			c.r=c.r+v.color[1]
			c.g=c.g+v.color[2]
			c.b=c.b+v.color[3]
			c.a=c.a+v.color[4]
		end
		
	end
end
]]
function gaussian (mean, variance)
    return  math.sqrt(-2 * variance * math.log(math.random())) *
            math.cos(2 * math.pi * math.random()) + mean
end

object_types={
	attractor={
		config={
			{"strength",10,type="float",min=-100,max=100},
			{"strength_var",0,type="float",min=0,max=1000},
			{"pow",0,type="float",min=-10,max=10},
			{"p",0.5,type="float"},
			},
		apply=function ( self,particle )
			if self.config.p < math.random() then
				return
			end
			local dx=self.x-particle.x
			local dy=self.y-particle.y
			local r=dx*dx+dy*dy
			local var=self.config.strength_var
			local s=self.config.strength
			if var>0.0001 then
				s=gaussian(self.config.strength,var)
			end
			local pow=self.config.pow
			local step_x=(dx/r)*s*math.pow(r,pow)
			local step_y=(dy/r)*s*math.pow(r,pow)
			particle.x=particle.x+step_x
			particle.y=particle.y+step_y
			if s > 0 then --attracting
				--we might overshoot the attractor, then just clip it?
				--this is so there would not be a halo
				if r<step_x*step_x+step_y*step_y then
					--[[particle.x=self.x
					particle.y=self.y]]
					particle.x=math.huge
				end
			end
		end
	},
	wind={
		config={
			{"strength",10,type="float",min=-1,max=1},
			{"strength_var",0,type="float",min=0,max=1},
			{"angle",0,type="angle"},
			{"p",0.5,type="float"},
			},
		apply=function ( self,particle )
			if self.config.p < math.random() then
				return
			end
			local dx=self.x-particle.x
			local dy=self.y-particle.y
			local r=dx*dx+dy*dy
			local var=self.config.strength_var
			local s=self.config.strength
			if var>0.0001 then
				s=gaussian(self.config.strength,var)
			end
			local dir_x=math.cos(self.config.angle)
			local dir_y=math.sin(self.config.angle)
			particle.x=particle.x+(dir_x)*s
			particle.y=particle.y+(dir_y)*s
		end
	},
	rotator={
		config={
			{"strength",10,type="float",min=-100,max=100},
			{"strength_var",0,type="float",min=0,max=1000},
			{"pow",0,type="float",min=-10,max=10},
			{"p",0.5,type="float"},
			},
		apply=function ( self,particle )
			if self.config.p < math.random() then
				return
			end
			local dx=self.x-particle.x
			local dy=self.y-particle.y
			local r=dx*dx+dy*dy
			
			local var=self.config.strength_var
			local s=self.config.strength
			if var>0.0001 then
				s=gaussian(self.config.strength,var)
			end
			local pow=self.config.pow
			particle.x=particle.x-(dy/r)*s*math.pow(r,pow)
			particle.y=particle.y+(dx/r)*s*math.pow(r,pow)
		end
	},
	painter={
		config={
			{"color",{0,0,1,1},type="color"},
			{"strength",0.1,type="float",min=0,max=1},
			{"strength_var",0,type="float",min=0,max=1},
			{"pow",0,type="float",min=-10,max=10},
			{"p",0.5,type="float"},
			},
		apply=function ( self,particle )
			if self.config.p < math.random() then
				return
			end
			local dx=self.x-particle.x
			local dy=self.y-particle.y
			local r=dx*dx+dy*dy
			
			local var=self.config.strength_var
			local s=self.config.strength
			if var>0.0001 then
				s=gaussian(self.config.strength,var)
			end
			local pow=self.config.pow
			local t=s*math.pow(r,pow)/r
			if t > 1 then t=1 end
			if t <0 then t=0 end
			for i=1,4 do
				particle.color[i]=particle.color[i]*(1-t)+self.config.color[i]*t
			end
		end
	},

	emitter={
		config={
			{"color",{1,0,0,1},type="color"},
			{"radius",25,type="float",min=0,max=1000},
			{"p",0.5,type="float"},
			},
		tick=function ( self )
			if self.config.p < math.random() then
				return
			end
			local R=self.config.radius

			local a=math.random()*2*math.pi
			local r=gaussian(0,R*R)
			--local r=R*math.sqrt(math.random())

			local pix={color=make_copy(self.config.color)}
			pix.x=r*math.cos(a)+self.x
			pix.y=r*math.sin(a)+self.y
			iterate(pix)
		end
	},
	emitter_uniform={
		config={
			{"color",{1,0,0,1},type="color"},
			{"p",0.5,type="float"},
			},
		tick=function ( self )
			if self.config.p < math.random() then
				return
			end
			local pix={color=make_copy(self.config.color)}
			--note: 1 pixel overdraw
			pix.x=math.random(-1,size[1])
			pix.y=math.random(-1,size[2])
			iterate(pix)
		end
	},
	emitter_grid={
		config={
			{"color",{1,0,0,1},type="color"},
			{"grid_size",10,type="float",min=1,max=100},
			{"p",0.5,type="float"},
			},
		tick=function ( self )
			if self.config.p < math.random() then
				return
			end
			local pix={color=make_copy(self.config.color)}
			--note: 1 pixel overdraw
			local g=self.config.grid_size
			pix.x=math.floor(math.random(-1,size[1])/g)*g
			pix.y=math.floor(math.random(-1,size[2])/g)*g
			iterate(pix)
		end
	},
}
function make_configs(  )
	for k,v in pairs(object_types) do
		v.config=make_config(v.config,v.config)
	end
end
make_configs()

function do_objects(  )
	for i,v in ipairs(object_list) do
		if v.tick then
			v.tick(v)
		end
	end
end
current_choice=current_choice or 0
object_choice=object_choice or 0
tick=tick or 0
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Fractal objects")
	local m,x,y=is_mouse_down()
	draw_config(config)
	if not config.edit then
		local choices={}
		for k,v in pairs(object_types) do
			table.insert(choices,k)
		end

		local _,cur_choice=imgui.ListBox("Type",current_choice,choices)
		current_choice=cur_choice
		local choice=object_types[choices[current_choice+1] ]
		draw_config(choice.config)

		if m then
			print("Adding:",choices[current_choice+1])
			create_object(x,y,choice)
		end

		if imgui.Button("Save image") then
			img_buf:save("saved_"..image_no..".png","Saved by PixelDance")
			image_no=image_no+1
		end
		imgui.SameLine()
		if imgui.Button("Clear") then
			img_buf:clear()
			img_buf:present()
			visits:clear()
		end
		imgui.SameLine()
		if imgui.Button("Clear Objects") then
			object_list={}
		end

		for i=1,config.steps do
			do_objects()
		end
		if imgui.Button("boost") then
			local max_i=50000
			for i=1,max_i do
				do_objects()
				print("Done:",i,i/max_i)
			end
			update_image()
		end
		--if config.auto_draw and (tick % 100==0) then
			update_image()
		--end
		if imgui.Button("draw") then
			update_image()
		end
	else
		local choices={}
		for k,v in pairs(object_list) do
			table.insert(choices,k)
		end

		local _,cur_choice=imgui.ListBox("Objects",object_choice,choices)
		object_choice=cur_choice
		local choice=object_list[choices[object_choice+1] ]
		if choice then
			draw_config(choice.config)
			local _,nx=imgui.SliderInt("x pos",choice.x,0,size[1])
			local _,ny=imgui.SliderInt("y pos",choice.y,0,size[2])
			choice.x=nx
			choice.y=ny
			if m then
				choice.x=x
				choice.y=y
			end
		end
		if imgui.Button("Remove") then
			table.remove(object_list,choices[object_choice+1])
		end
	end
	imgui.End()
	tick=tick+1
end