require "common"

local size=STATE.size
local max_size=math.min(size[1],size[2])/2
img_buf=img_buf or make_image_buffer(size[1],size[2])
visits=visits or make_flt_buffer(size[1],size[2])
function resize( w,h )
	visits=make_flt_buffer(size[1],size[2])
	img_buf=make_image_buffer(size[1],size[2])
end

local size=STATE.size


tick=tick or 0
config=make_config({
	{"prev_color",{0.5,0,0,1},type="color"},
	{"color",{0.5,0,0,1},type="color"},
	{"next_color",{0.79,0.59,0.59,1},type="color"},
	{"color_step",0,type="float",min=0,max=1},
	{"ppframe",100,type="int",min=1,max=10000}, --particles per frame
	{"seed_size",100,type="int",min=1,max=500},
	{"random_color",false,type="boolean"},
	{"square",true,type="boolean"},
	{"phase_offset",0.5,type="float"},
	{"radius",250,type="float",min=0,max=size[1]},
	{"rnd_offset",0.005,type="float",min=0,max=2},
	{"restart",0,type="int",min=0,max=10000},
	{"auto_scale_color",true,type="boolean"},
},config)
image_no=image_no or 0

function ray( sx,sy,tx,ty ,p)
	local dx=tx-sx
	local dy=ty-sy
	local dir_l=math.sqrt(dx*dx+dy*dy)
	dx=dx/dir_l
	dy=dy/dir_l
	local iter=0
	local lx=sx
	local ly=sy
	--local debug_ray=true
	local log_based=config.log_based

	while sx>=0 and sx<visits.w and
		sy>=0 and sy<visits.h and iter<10000 do
		
		if debug_ray then
			local pp=visits:get(math.floor(sx),math.floor(sy))
			pp.r=pp.r+p.r
			pp.g=pp.g+p.g
			pp.b=pp.b+p.b
			pp.a=1
		else
			local c=visits:get(math.floor(sx),math.floor(sy))

			if c.a>0 then
				pp=visits:get(math.floor(lx),math.floor(ly))
				pp.r=pp.r+p.r
				pp.g=pp.g+p.g
				pp.b=pp.b+p.b
				pp.a=1
				return
			end
		end
	
		lx=sx
		ly=sy
		sx=sx+dx
		sy=sy+dy
		iter=iter+1
	end
end
function rnd( r )
	return (r()*2-1)
end
function rgbToHsl(r, g, b, a)
  r, g, b = r , g , b

  local max, min = math.max(r, g, b), math.min(r, g, b)
  local h, s, l

  l = (max + min) / 2

  if max == min then
    h, s = 0, 0 -- achromatic
  else
    local d = max - min
    if l > 0.5 then s = d / (2 - max - min) else s = d / (max + min) end
    if max == r then
      h = (g - b) / d
      if g < b then h = h + 6 end
    elseif max == g then h = (b - r) / d + 2
    elseif max == b then h = (r - g) / d + 4
    end
    h = h / 6
  end

  return h, s, l, a or 1
end

--[[
 * Converts an HSL color value to RGB. Conversion formula
 * adapted from http://en.wikipedia.org/wiki/HSL_color_space.
 * Assumes h, s, and l are contained in the set [0, 1] and
 * returns r, g, and b in the set [0, 255].
 *
 * @param   Number  h       The hue
 * @param   Number  s       The saturation
 * @param   Number  l       The lightness
 * @return  Array           The RGB representation
]]
function hslToRgb(h, s, l, a)
  local r, g, b
  a=a or 1
  if s == 0 then
    r, g, b = l, l, l -- achromatic
  else
    function hue2rgb(p, q, t)
      if t < 0   then t = t + 1 end
      if t > 1   then t = t - 1 end
      if t < 1/6 then return p + (q - p) * 6 * t end
      if t < 1/2 then return q end
      if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
      return p
    end

    local q
    if l < 0.5 then q = l * (1 + s) else q = l + s - l * s end
    local p = 2 * l - q

    r = hue2rgb(p, q, h + 1/3)
    g = hue2rgb(p, q, h)
    b = hue2rgb(p, q, h - 1/3)
  end

  return r , g , b , a
end

function step_color_hsl( from,to,step )

	local hf={rgbToHsl(from[1],from[2],from[3])}
	local ht={rgbToHsl(unpack(to))}
	
	local dx=ht[1]-hf[1]
	local dy=ht[2]-hf[2]
	local dz=ht[3]-hf[3]
	local delta=math.sqrt(dx*dx+dy*dy+dz*dz)
	local full_delta=delta
	if delta<0.0001 then
		return from,delta
	end
	dx=dx/delta
	dy=dy/delta
	dz=dz/delta

	local nf={hf[1]+dx*step,hf[2]+dy*step,hf[3]+dz*step}
	for i=1,3 do
		if nf[i]>1 then nf[i]=1 end
		if nf[i]<0 then nf[i]=0 end
	end
	
	return {hslToRgb(unpack(nf))},full_delta
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

function rand_ray(rand,roff, c )

	local r=rand(1,4)
	
	local fx,fy
	if r==4 then
		fx=1
		fy=rand(1,size[2]-1)
	elseif r==3 then
		fx=rand(1,size[1]-1)
		fy=1
	elseif r==2 then
		fx=rand(1,size[1]-1)
		fy=size[2]-1
	else
		fx=size[1]-1
		fy=rand(1,size[2]-1)
	end
	local tx,ty
	if config.square then
		tx,ty=size[1]/2+rnd(rand)*config.radius,size[2]/2+rnd(rand)*config.radius
	else
		--[[local dx=fx-size[1]/2
		local dy=fy-size[2]/2
		local dd=math.sqrt(dx*dx+dy*dy)
		dx=dx/dd
		dy=dy/dd
		local a=math.atan(dy,dx)]]
		local a=rand()*math.pi*2
		local ph=config.phase_offset*math.pi*2
		tx,ty=size[1]/2+math.cos(a+ph)*config.radius,size[2]/2+math.sin(a+ph)*config.radius
	end

	tx=tx+(rnd(roff)-0.5)*config.rnd_offset
	ty=ty+(rnd(roff)-0.5)*config.rnd_offset
	ray(fx,fy,tx,ty,c)
end
function blend_rgb( c1,c2,t )
	local ret={}
	for i=1,4 do
		ret[i]=(c2[i]-c1[i])*t+c1[i]
	end
	return ret
end
restart_count=restart_count or 0
rand=rand or pcg_rand.Make()
rand_off=rand_off or pcg_rand.Make()
rand:seed(42)
rand_off:seed(102)
function clear_screen(full )
	local s=STATE.size
	if full then
		visits:clear()
	else
		for i=0,visits.w*visits.h-1 do
			visits.d[i].a=0
		end
	end
	local cc=config.prev_color
	local ss=math.floor(config.seed_size/2)
	for i=-ss,ss do
		for j=-ss,ss do
		local c=visits:get(math.floor(s[1]/2)+i,math.floor(s[2]/2)+j)
		c.r=c.r+cc[1]
		c.g=c.g+cc[2]
		c.b=c.b+cc[3]
		c.a=1
	end
	end
	
	restart_count=0
	counter=0
	rand:seed(42)
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Hello")
	local s=STATE.size
	draw_config(config)
	
	if imgui.Button("Clear image") then
		print("Clearing:"..s[1].."x"..s[2])
		clear_screen(true)
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		img_buf:save("saved_"..image_no..".png","Saved by PixelDance")
		need_save=true
	end
	imgui.End()
	local color_dt
	config.color,color_dt=step_color_hsl(config.color,config.next_color,config.color_step)
	--[[if color_dt <0.01 and config.random_color then
		config.next_color={math.random(),math.random(),math.random(),1}
	end]]
	
	
	
	for i=1,config.ppframe do
		config.color=blend_rgb(config.prev_color,config.next_color,(i-1)/config.ppframe)
		local c=flt_pixel(config.color)
		rand_ray(rand,rand_off, c)
	end
	restart_count=restart_count+1

	if restart_count>config.restart then
		clear_screen(false)
	end
	draw_visits()
	
end