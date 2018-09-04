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

ffi.cdef[[
typedef struct { uint8_t r, g, b, a; } rgba_pixel;
typedef struct { double r, g, b; } dbl_pixel;
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
			v:set(x,y,c or {0,0,0,255})
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
			t:set(x,y,c or {0,0,0})
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
			elseif entry.type=="float" then
				local changing
				changing,tbl[k]=imgui.SliderFloat(k,tbl[k],entry.min or 0,entry.max or 1)
				entry.changing=changing
			elseif entry.type=="angle" then
				local changing
				changing,tbl[k]=imgui.SliderAngle(k,tbl[k],entry.min or 0,entry.max or 360)
				entry.changing=changing
			elseif entry.type=="color" then
				local changing
				changing,tbl[k]=imgui.ColorEdit4(k,tbl[k],true)
				entry.changing=changing
			end
		
		end
	end
end
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
		if config.dt>10 then
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

	local pix_out = pixel()
	

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
	if config.do_log_normed then
		return {math.random(),math.random(),math.random(),255}
	else
		return {math.random(0,255),math.random(0,255),math.random(0,255),255}
	end
end
function create_object( x,y,color,vx,vy )
	table.insert(object_list,{x=x,y=y,color=color or rand_color(),vx=vx or 0, vy=vy or 0,ax=0,ay=0,lx=x,ly=y})
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
		dbl_buf:clear()
	end
	if imgui.Button("Clear Objects") then
		object_list={}
	end
	if imgui.Button("Add") then
		local cx=size[1]/2
		local cy=size[2]/2
		local count=6
		for i=0,math.pi*2-0.01,math.pi*2/count do
			create_object(cx+math.cos(i)*size[1]/8,cy+math.sin(i)*size[2]/8)
		end
	end
	for i=1,config.steps do
		update_objects()
		if config.do_log_normed then
			for i,v in ipairs(object_list) do
				local c=dbl_buf:get(math.floor(v.x),math.floor(v.y))
				c.r=c.r+v.color[1]
				c.g=c.g+v.color[2]
				c.b=c.b+v.color[3]

				--img_buf:set(math.floor(v.x),math.floor(v.y),c)
			end
		else
			for i,v in ipairs(object_list) do
				img_buf:set(math.floor(v.x),math.floor(v.y),v.color)
			end
		end
	end
	if config.do_log_normed then
		if tick_num%100==0 then
			update_image()
		end
	else
		img_buf:present()
	end
	imgui.End()
end