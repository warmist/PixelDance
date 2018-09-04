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
local ffi = require("ffi")

function make_config(tbl,defaults)
	local ret={}
	defaults=defaults or {}
	for i,v in ipairs(tbl) do
		ret[v[1]]=defaults[v[1]] or v[2]
		ret[i]=v
	end
	return ret
end
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
function make_float_buffer(w,h)
	local img={d=ffi.new("double[?]",w*h),w=w,h=h}
	img.set=function ( t,x,y,v )
		t.d[x+t.w*y]=v
	end
	img.get=function ( t,x,y )
		return t.d[x+t.w*y]
	end
	return img
end

img_buf=img_buf or make_image_buffer(size[1],size[2])
visits=visits or make_float_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
	visits=make_float_buffer(size[1],size[2])
end



tick=tick or 0
config=make_config({
	{"render",false,type="boolean"},
	{"color",{0.5,0,0,0},type="color"},
	{"color2",{1,1,1,1},type="color"},
	{"ticking",100,type="int",min=1,max=10000},
	{"ticking2",10,type="int",min=1,max=100},
	{"v0",-0.211,type="float",min=-5,max=5},
	{"v1",-0.184,type="float",min=-5,max=5},
	{"scale",1,type="float",min=0.00001,max=2},
	--{"one_step",false,type="boolean"},
	--{"super_sample",1,type="int",min=1,max=4},
	{"cx",0,type="float",min=-1,max=1},
	{"cy",0,type="float",min=-1,max=1},
	{"gen_radius",1,type="float",min=0,max=10},
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
function draw_visits(  )
	local mm=0
	local vst=visits

	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local v=vst:get(x,y)
		if mm<v then mm=v end
	end
	end
	mm=math.log(mm)

	local pix_out = pixel()
	local c_u8=pixel{config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	local c_back=pixel{config.color2[1]*255,config.color2[2]*255,config.color2[3]*255,config.color2[4]*255}

	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local v=vst:get(x,y)
		local nv=math.log(v)/mm
		nv=math.min(math.max(nv,0),1)
		mix(pix_out,c_u8,c_back,nv)
		img_buf:set(x,y,pix_out)
	end
	end

	img_buf:present()
end
function step_iter( x,y,v0,v1)
	--[[local nzx=x*x+v0-y*y
	local nzy=2*x*y+v1
	return nzx,nzy]]
	--local nx=(((v0)-(v1)/((x)*(v0)))-(math.cos((v0)-(x))))*((math.cos((v1)*(y)))+(math.sin(x)/(math.cos(x))))
	--local ny=math.sin(((y)+(v1))*(math.sin(x))/(math.sin((x)*(x))))
	--local r = x*x+y*y
	--return x/r+math.sin(y-r*v0),y/r-math.cos(x-r*v1)
	local nx=math.sin(math.sin(y))/((math.cos(y))-(y/(x)))/(((math.sin(v0))-(v1/(x)))*(math.sin((y)+(v0))))
	local ny=math.cos((x/(x+v0)/(y))*(((v0)+(v1))+(math.cos(y))))*y
	return nx,ny
	--return math.cos(x-y/v1)*x+math.sin(x*x*v0)*v1,math.sin(y-x/v0)*y+math.cos(y*y*v1)*v0
	--return x+v1,y*math.cos(x)-v0
end

function smooth_visit( tx,ty )
	local lx=math.floor(tx)
	local hx=lx+1
	local ly=math.floor(ty)
	local hy=ly+1

	local fr_x=tx-lx
	local fr_y=ty-ly

	local ll=visits:get(lx,ly)
	local lh=visits:get(lx,hy)
	local hl=visits:get(hx,ly)
	local hh=visits:get(hx,hy)
	--TODO: writes to out of bounds (hx/hy out of bounds)
	visits:set(lx,ly,ll+(1-fr_x)*(1-fr_y))
	visits:set(lx,hy,lh+(1-fr_x)*fr_y)
	visits:set(hx,ly,hl+fr_x*(1-fr_y))
	visits:set(hx,hy,hh+fr_x*fr_y)
end
function clear_buffers(  )
	local s=size
	local vst=visits_ffi
	local clear=pixel{0,0,0,0}
	for x=0,s[1]-1 do
		for y=0,s[2]-1 do
			img_buf:set(x,y,clear)
		end
	end
	for i=0,(s[1]*s[2])-1 do
		visits.d[i]=0
	end
	img_buf:present();
end
function random_math( num_params,len )
	local cur_string="R"
	local terminal=function (  )
		if math.random()>0.3 then
			if math.random()>0.5 then
				return 'x'
			else
				return 'y'
			end
		else
			local v=math.random(0,num_params-1)
			return 'v'..v
		end
	end


	local function M(  )
		local ch={"math.sin(R)","math.cos(R)",--[["math.log(R)",]]"R/(R)",
		"(R)*(R)","(R)-(R)","(R)+(R)"}
		return ch[math.random(1,#ch)]
	end
	
	while #cur_string<len do
		cur_string=string.gsub(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",terminal)
	return cur_string
end
function gui(  )
	imgui.Begin("IFS play")
	
	draw_config(config)
	local s=STATE.size
	if imgui.Button("Clear image") then
		clear_buffers()
	end
	--imgui.SameLine()
	generate_num_params=generate_num_params or 1
	last_gen_function=last_gen_function or ""
	local changed
	changed,generate_num_params=imgui.SliderInt("Num params",generate_num_params,1,10)
	if imgui.Button("Gen function") then
		last_gen_function=random_math(generate_num_params,50)
	end
	imgui.InputText("Formula",last_gen_function)
	--imgui.SameLine()
	if imgui.Button("Save image") then
		local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
		for k,v in pairs(config) do
			if type(v)~="table" then
				config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
			end
		end
		img_buf:save("saved_"..image_no..".png",config_serial)
		image_no=image_no+1
	end
	imgui.End()
end
function update( )
	gui()
	if config.render then
		update_real()
	else
		update_func()
	end
end
function update_func(  )
	local s=STATE.size
	local hw=s[1]/2
	local hh=s[2]/2
	local iscale=1/config.scale
	local scale=config.scale
	local v0=config.v0
	local v1=config.v1

	local vst=visits
	local max=0
	local min=999999999999
	local avg=0
	for x=0,s[1]-1 do
	for y=0,s[2]-1 do
		local tx=(x/s[1]-0.5)*scale
		local ty=(y/s[2]-0.5)*scale
		local nx,ny=step_iter(tx,ty,v0,v1)
		local dx=nx-tx
		local dy=ny-ty
		local dist=dx*dx+dy*dy
		if dist>max then max=dist end
		if dist<min then min=dist end
		avg=avg+dist
		vst:set(x,y,dist)
	end
	end
	avg=avg/(s[1]*s[2])
	local pix_out=pixel()
	local c_u8=pixel{config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	local c_back=pixel{config.color2[1]*255,config.color2[2]*255,config.color2[3]*255,config.color2[4]*255}
	imgui.Begin("IFS play")
	imgui.Text(string.format("Stats:%g %g %g",min,avg,max))
	imgui.End()
	for x=0,s[1]-1 do
	for y=0,s[2]-1 do
		--[[local tx=(x/s[1]-0.5)*scale
		local ty=(y/s[2]-0.5)*scale
		local nx,ny=step_iter(tx,ty,v0,v1)
		local dx=nx-tx
		local dy=ny-ty
		local dist=dx*dx+dy*dy]]
		--local dist=visits:get(x,y)
		local dist=vst:get(x,y)
		mix(pix_out,c_u8,c_back,dist)
		img_buf:set(x,y,pix_out)
	end
	end

	img_buf:present()
end
function auto_clear(  )
	local cfg_pos=0
	for i,v in ipairs(config) do
		if v[1]=="scale" then
			cfg_pos=i
			break
		end
	end
	if config[cfg_pos].changing or config[cfg_pos+1].changing or config[cfg_pos+2].changing then
		clear_buffers()
	end
end
function mod(a,b)
	local r=math.fmod(a,b)
	if r<0 then
		return r+b
	else
		return r
    end
end
function update_real(  )
	local s=STATE.size
	auto_clear()

	local hw=s[1]/2
	local hh=s[2]/2
	local iscale=1/config.scale
	local scale=config.scale
	local v0=config.v0
	local v1=config.v1
	local cx=config.cx
	local cy=config.cy
	--[[if config.one_step then
		return
	end]]
	--config.one_step=true
	--local start_calc=os.time()
	local gen_radius=config.gen_radius
	for i=1,config.ticking do
		--TODO: generate IN screen
		--[[local x = math.random()-0.5
		local y = math.random()-0.5]]
		local x=math.random()*gen_radius-gen_radius/2
		local y=math.random()*gen_radius-gen_radius/2
		lv=0
		for i=1,config.ticking2 do
			x,y=step_iter(x,y,v0,v1)
			--[[
				local tx=math.fmod(math.abs((x*iscale+0.5)*s[1]),s[1])
				local ty=math.fmod(math.abs((y*iscale+0.5)*s[2]),s[2])
				local v=visits:get(tx,ty)
				visits:set(tx,ty,v+1)
			--]]
			--if x>=-0.5*scale and y>=-0.5*scale and x<0.5*scale and y<0.5*scale then
				local tx=((x-cx)*iscale+0.5)*s[1]
				local ty=((y-cy)*iscale+0.5)*s[2]
				tx=mod(tx,s[1])
				ty=mod(ty,s[2])
			--if tx>=1 and ty>=1 and tx<s[1]-1 and ty<s[2]-1 then
				smooth_visit(tx,ty)
				--local v=visits:get(tx,ty)
				--visits:set(tx,ty,v+1)
			--else
				--break
			--end
		end
	end
	--local end_calc=os.time()
	--local time_delta=os.difftime(end_calc,start_calc)
	--print("Calculation took:",time_delta," or:",time_delta/(config.ticking*config.ticking2), " per iteration")
	if math.fmod(tick,10)==0 then
		draw_visits()
	end
	tick=tick+1
end