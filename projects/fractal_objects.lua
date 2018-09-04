local ffi=require "ffi"
function make_config(tbl,defaults)
	local ret={}
	defaults=defaults or {}
	for i,v in ipairs(tbl) do
		ret[v[1]]=defaults[v[1]] or v[2]
		ret[i]=v
	end
	return ret
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
ffi.cdef[[
typedef struct { uint8_t r, g, b, a; } rgba_pixel;
typedef struct { double r, g, b,a; } dbl_pixel;
]]
function pixel(init)
	return ffi.new("rgba_pixel",init or {0,0,0,255})
end
function make_image_buffer(w,h)
	local img={d=ffi.new("rgba_pixel[?]",w*h),w=w,h=h}

	img.set=function ( t,x,y,v )
		t.d[x+t.w*y]=v
	end
	img.get=function ( t,x,y )
		return t.d[x+t.w*y]
	end
	img.present=function ( t )
		__present(t)
	end
	img.save=function ( t,path,suffix )
		__save_png(t,path,suffix)
	end
	img.clear=function (v, c )
		for x=0,w-1 do
		for y=0,h-1 do
			v:set(x,y,c or {0,0,0,0})
		end
		end
	end
	img:clear()
	return img
end
function make_dbl_buffer(w,h)
	local img={d=ffi.new("dbl_pixel[?]",w*h),w=w,h=h}

	img.set=function ( t,x,y,v )
		t.d[x+t.w*y]=v
	end
	img.get=function ( t,x,y )
		return t.d[x+t.w*y]
	end
	img.clear=function ( t,c )
		for x=0,w-1 do
		for y=0,h-1 do
			t:set(x,y,c or {0,0,0,0})
		end
		end
	end
	return img
end
img_buf=img_buf or make_image_buffer(size[1],size[2])
dbl_buf=dbl_buf or make_dbl_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
	dbl_buf=make_dbl_buffer(size[1],size[2])
end
config=make_config({
	{"steps",100,type="int",min=1,max=1000},
	{"particle_steps",1000,type="int",min=100,max=100000},
	{"randomize_steps",false,type="boolean"},
	{"auto_draw",false,type="boolean"},
	},config)
object_list=object_list or {}
image_no=image_no or 0
function draw_config( tbl )
	for _,entry in ipairs(tbl) do
		local name=entry[1]
		local v=tbl[name]
		local k=name
		if type(v)=="boolean" then
			if imgui.RadioButton(k,tbl[k]) then
				tbl[k]=not tbl[k]
			end
		elseif type(v)=="string" then
			local changing
			changing,tbl[k]=imgui.InputText(k,tbl[k])
			entry.changing=changing
		else --if type(v)~="table" then
			
			if entry.type=="int" then
				local changing
				changing,tbl[k]=imgui.SliderInt(k,tbl[k],entry.min or 0,entry.max or 100)
				entry.changing=changing
				imgui.SameLine()
				if imgui.Button("Random##"..k) then
					entry.changing=true
					tbl[k]=math.random(entry.min or 0,entry.max or 100)
				end
			elseif entry.type=="float" then
				local changing
				changing,tbl[k]=imgui.SliderFloat(k,tbl[k],entry.min or 0,entry.max or 1)
				entry.changing=changing
				imgui.SameLine()
				if imgui.Button("Random##"..k) then
					entry.changing=true
					local mm=entry.max or 1
					local mi=entry.min or 0
					tbl[k]=math.random()*(mm-mi)+mi
				end
			elseif entry.type=="angle" then
				local changing
				changing,tbl[k]=imgui.SliderAngle(k,tbl[k],entry.min or 0,entry.max or 360)
				entry.changing=changing
				imgui.SameLine()
				if imgui.Button("Random##"..k) then
					entry.changing=true
					local mm=entry.max or 360
					local mi=entry.min or 0
					tbl[k]=math.random()*(mm-mi)+mi
				end
			elseif entry.type=="color" then
				local changing
				changing,tbl[k]=imgui.ColorEdit4(k,tbl[k],true)
				entry.changing=changing
				imgui.SameLine()
				if imgui.Button("Random##"..k) then
					entry.changing=true
					local mm=entry.max or 1
					local mi=entry.min or 0
					tbl[k]={math.random(),math.random(),math.random(),1}
				end
			end
		
		end
	end
end
function is_mouse_down(  )
	return __mouse.clicked0 and not __mouse.owned0, __mouse.x,__mouse.y
end

function update_image()
	local mm=0
	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local v=dbl_buf:get(x,y)
		local vv=v.r*v.r+v.g*v.g+v.b*v.b
		if mm<vv then mm=vv end
	end
	end
	mm=math.log(math.sqrt(mm))
	print(mm)
	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local v=dbl_buf:get(x,y)
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
	if config.randomize_steps then
		if #object_list > 0 then
			local t=object_list[math.random(1,#object_list)]
			if t.apply then
				t.apply(t,v)
			end
		end
	else
		for i,t in ipairs(object_list) do
			if t.apply then
				t.apply(t,v)
			end
		end
	end
end
function iterate( v )
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
	end
end
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
function gaussian (mean, variance)
    return  math.sqrt(-2 * variance * math.log(math.random())) *
            math.cos(2 * math.pi * math.random()) + mean
end

object_types={
	--[[attractor={
		config={
			{"strength",10,type="float",min=-100,max=100},
			{"strength_var",0,type="float",min=0,max=1000},
			},
		apply=function ( self,particle )
			local dx=self.x-particle.x
			local dy=self.y-particle.y
			local r=dx*dx+dy*dy
			local var=self.config.strength_var
			local s=self.config.strength
			if var>0.0001 then
				s=gaussian(self.config.strength,var)
			end
			particle.x=particle.x+(dx/r)*s
			particle.y=particle.y+(dy/r)*s
		end
	},]]
	attractor_pow={
		config={
			{"strength",10,type="float",min=-100,max=100},
			{"strength_var",0,type="float",min=0,max=1000},
			{"pow",0,type="float",min=-10,max=10},
			},
		apply=function ( self,particle )
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
			{"strength_var",0,type="float",min=0,max=1000},
			{"angle",0,type="angle"},
			},
		apply=function ( self,particle )
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
	--[[attractor_borked={
		config={
			{"strength",10,type="float",min=-100,max=100},
			},
		apply=function ( self,particle )
			local dx=self.x-particle.x
			local dy=self.y-particle.y
			local r=dx*dx+dy*dy
			if dx>dy then
				particle.x=particle.x+(dx/r)*self.config.strength
			else
				particle.y=particle.y+(dy/r)*self.config.strength
			end
		end
	},]]
	--[[rotator={
		config={
			{"strength",10,type="float",min=-100,max=100},
			{"strength_var",0,type="float",min=0,max=1000},
			},
		apply=function ( self,particle )
			local dx=self.x-particle.x
			local dy=self.y-particle.y
			local r=dx*dx+dy*dy
			
			local var=self.config.strength_var
			local s=self.config.strength
			if var>0.0001 then
				s=gaussian(self.config.strength,var)
			end
			particle.x=particle.x-(dy/r)*s
			particle.y=particle.y+(dx/r)*s
		end
	},]]
	rotator_pow={
		config={
			{"strength",10,type="float",min=-100,max=100},
			{"strength_var",0,type="float",min=0,max=1000},
			{"pow",0,type="float",min=-10,max=10},
			},
		apply=function ( self,particle )
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
	painter_pow={
		config={
			{"color",{0,0,1,1},type="color"},
			{"strength",10,type="float",min=-100,max=100},
			{"strength_var",0,type="float",min=0,max=1000},
			{"pow",0,type="float",min=-10,max=10},
			},
		apply=function ( self,particle )
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
			},
		tick=function ( self )
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
			},
		tick=function ( self )
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
			},
		tick=function ( self )
			local pix={color=make_copy(self.config.color)}
			--note: 1 pixel overdraw
			local g=self.config.grid_size
			pix.x=math.floor(math.random(-1,size[1])/g)*g
			pix.y=math.floor(math.random(-1,size[2])/g)*g
			iterate(pix)
		end
	},

	--[[emitter_uniform_mx={
		config={
			{"color",{1,0,0,1},type="color"},
			},
		tick=function ( self )
			local pix={color=self.config.color}
			--note: 1 pixel overdraw
			pix.x=math.random(-1,size[1]/2)
			pix.y=math.random(-1,size[2])
			iterate_mirror_x(pix)
		end
	},
	emitter_uniform_my={
		config={
			{"color",{1,0,0,1},type="color"},
			},
		tick=function ( self )
			local pix={color=self.config.color}
			--note: 1 pixel overdraw
			pix.x=math.random(-1,size[1])
			pix.y=math.random(-1,size[2]/2)
			iterate_mirror_y(pix)
		end
	}]]
}
function make_configs(  )
	for k,v in pairs(object_types) do
		v.config=make_config(v.config,v.config)
	end
end
make_configs()

function do_objects(  )
	if config.randomize_steps then
		if #object_list > 0 then
			local v=object_list[math.random(1,#object_list)]
			if v.tick then
				v.tick(v)
			end
		end
	else
		for i,v in ipairs(object_list) do
			if v.tick then
				v.tick(v)
			end
		end
	end
end
current_choice=current_choice or 0
tick=tick or 0
function update(  )
	imgui.Begin("Fractal objects")
	local choices={}
	for k,v in pairs(object_types) do
		table.insert(choices,k)
	end

	local _,cur_choice=imgui.ListBox("Type",current_choice,choices)
	current_choice=cur_choice
	local choice=object_types[choices[current_choice+1] ]
	draw_config(choice.config)

	local m,x,y=is_mouse_down()
	if m then
		print("Adding:",choices[current_choice+1])
		create_object(x,y,choice)
	end

	draw_config(config)

	if imgui.Button("Save image") then
		img_buf:save("saved_"..image_no..".png","Saved by PixelDance")
		image_no=image_no+1
	end
	imgui.SameLine()
	if imgui.Button("Clear") then
		img_buf:clear()
		img_buf:present()
		dbl_buf:clear()
	end
	imgui.SameLine()
	if imgui.Button("Clear Objects") then
		object_list={}
	end

	for i=1,config.steps do
		do_objects()
	end
	if imgui.Button("boost") then
		for i=1,500000 do
			do_objects()
		end
		update_image()
	end
	if config.auto_draw and (tick % 100==0) then
		update_image()
	end
	if imgui.Button("draw") then
		update_image()
	end
	imgui.End()
	tick=tick+1
end