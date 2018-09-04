--[[ Example:
imgui_config=make_config{
	{"debug_display",false},
	{"complexity",0.5,type="float"}, --implied min=0,max=1
	{"shapes","3"},
	{"w",3,type="int",min=1,max=5},
}

Begin
End
Bullet
BulletText
RadioButton
CollapsingHeader
SliderFloat
SliderAngle
SliderInt
InputText
]]
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
local max_size=math.min(size[1],size[2])/2

ffi.cdef[[
typedef struct { uint8_t r, g, b, a; } rgba_pixel;
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
	return img
end

img_buf=img_buf or make_image_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
end



tick=tick or 0
config=make_config({
	{"color",{0.5,0,0,1},type="color"},
	{"back",{0.0,0,0,1},type="color"},
	{"k",0.2,type="float"},
	{"l",0.4,type="float"},
	{"R",400,type="int",min=0,max=max_size},
	{"ticking",100,type="float",min=1,max=10000},
	{"ticking2",100,type="float",min=1,max=10000},
	{"scale",10,type="float",min=0,max=25000},
	{"cx",0,type="float",min=-1,max=1},
	{"cy",0,type="float",min=-1,max=1},
	{"ss",1,type="int",min=1,max=8},
	{"ss_dist",0,type="float",min=0,max=0.2},
},config)
image_no=image_no or 0
function draw_config( tbl )
	for _,entry in ipairs(tbl) do
		local name=entry[1]
		local v=tbl[name]
		local k=name
		if type(v)=="boolean" then
			if imgui.Button(k) then
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
function iterate( x,y ,n,dist)
	local zx=0
	local zy=0
	for i=1,n do
		local nzx=zx*zx+x-zy*zy
		local nzy=2*zx*zy+y
		if nzx*nzx+nzy*nzy>dist then
			return i
		end
		zx=nzx
		zy=nzy
	end
	return 0
end
function super_sample(x,y,n,dist,samples_count,sample_dist )
	local ret=0
	for i=1,samples_count do
		local dx=(math.random()-0.5)*2*sample_dist
		local dy=(math.random()-0.5)*2*sample_dist
		ret=ret+iterate( x+dx,y+dy ,n,dist)
	end
	return ret/samples_count
end
function mix(out, c1,c2,t )
	local it=1-t
	out.r=c1.r*it+c2.r*t
	out.g=c1.g*it+c2.g*t
	out.b=c1.b*it+c2.b*t
	out.a=c1.a*it+c2.a*t
end
last_pos=last_pos or {0,0}
function is_mouse_down(  )
	return __mouse.clicked0 and not __mouse.owned0, __mouse.x,__mouse.y
end
function map_to_screen( x,y )
	local s=STATE.size
	return (x-s[1]/2)/config.scale+config.cx,(y-s[2]/2)/config.scale+config.cy
end
function update(  )
	local m,x,y=is_mouse_down()
	if m then
		local sx,sy=map_to_screen(x,y)
		print("T",x,y,sx,sy)
		config.cx=config.cx-sx
		config.cy=config.cy-sy
	end
	imgui.Begin("Fractal")
	local s=STATE.size
	draw_config(config)
	local c_u8=pixel{config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	local c_back=pixel{config.back[1]*255,config.back[2]*255,config.back[3]*255,config.back[4]*255}
	if imgui.Button("Clear image") then
		print("Clearing:"..s[1].."x"..s[2])
		for x=0,s[1]-1 do
			for y=0,s[2]-1 do
				img_buf:set(x,y,{0,0,0,0})
			end
		end
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		img_buf:save("saved_"..image_no..".png","Saved by PixelDance")
		image_no=image_no+1
	end
	imgui.End()
	local col_out=pixel()
	for i=1,config.ticking do
		local x = last_pos[1]
		local y = last_pos[2]
		if x<s[1]-1 then
			x=x+1
		else
			y=y+1
			x=0
		end

		if y>=s[2]-1 then y=0 end
		last_pos={x,y}
		local ret= super_sample((x-s[1]/2)/config.scale+config.cx,(y-s[2]/2)/config.scale+config.cy,config.ticking2,4,config.ss,config.ss_dist)
		--local ret=iterate((x-s[1]/2)/config.scale+config.cx,(y-s[2]/2)/config.scale+config.cy,config.ticking2,4)
		local t=ret/config.ticking2
		mix(col_out,c_u8,c_back,math.abs(1-t))
		img_buf:set(x,y,col_out)
	end
	img_buf:present()
end