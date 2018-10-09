
require "common"

local size=STATE.size
local max_size=math.min(size[1],size[2])/2

img_buf=img_buf or make_image_buffer(size[1],size[2])
visits=visits or make_float_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
	visits=make_float_buffer(size[1],size[2])
end



tick=tick or 0
config=make_config({
	{"render",false,type="boolean"},
	{"auto_scale_color",false,type="boolean"},
	{"ticking",100,type="int",min=1,max=10000},
	{"ticking2",10,type="int",min=1,max=100},
	{"line_visits",1,type="int",min=1,max=100},
	{"arg_disp",0,type="float",min=0,max=1},
	{"v0",-0.211,type="float",min=-5,max=5},
	{"v1",-0.184,type="float",min=-5,max=5},
	{"move_dist",0.1,type="float",min=0.001,max=2},
	{"scale",1,type="float",min=0.00001,max=2},
	--{"one_step",false,type="boolean"},
	--{"super_sample",1,type="int",min=1,max=4},
	{"cx",0,type="float",min=-1,max=1},
	{"cy",0,type="float",min=-1,max=1},
	{"gen_radius",1,type="float",min=0,max=10},
},config)
image_no=image_no or 0
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
--[[
 * Converts an RGB color value to HSL. Conversion formula
 * adapted from http://en.wikipedia.org/wiki/HSL_color_space.
 * Assumes r, g, and b are contained in the set [0, 255] and
 * returns h, s, and l in the set [0, 1].
 *
 * @param   Number  r       The red color value
 * @param   Number  g       The green color value
 * @param   Number  b       The blue color value
 * @return  Array           The HSL representation
]]
function rgbToHsl(r, g, b, a)
  r, g, b = r / 255, g / 255, b / 255

  local max, min = math.max(r, g, b), math.min(r, g, b)
  local h, s, l

  l = (max + min) / 2

  if max == min then
    h, s = 0, 0 -- achromatic
  else
    local d = max - min
    local s
    if l > 0.5 then s = d / (2 - max - min) else s = d / (max + min) end
    if max == r then
      h = (g - b) / d
      if g < b then h = h + 6 end
    elseif max == g then h = (b - r) / d + 2
    elseif max == b then h = (r - g) / d + 4
    end
    h = h / 6
  end

  return h, s, l, a or 255
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

  return r * 255, g * 255, b * 255, a * 255
end
function hslToRgb_normed(h, s, l, a)
  local r, g, b

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

  return {r , g , b , a}
end
--[[
 * Converts an RGB color value to HSV. Conversion formula
 * adapted from http://en.wikipedia.org/wiki/HSV_color_space.
 * Assumes r, g, and b are contained in the set [0, 255] and
 * returns h, s, and v in the set [0, 1].
 *
 * @param   Number  r       The red color value
 * @param   Number  g       The green color value
 * @param   Number  b       The blue color value
 * @return  Array           The HSV representation
]]
function rgbToHsv(r, g, b, a)
  r, g, b, a = r / 255, g / 255, b / 255, a / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local h, s, v
  v = max

  local d = max - min
  if max == 0 then s = 0 else s = d / max end

  if max == min then
    h = 0 -- achromatic
  else
    if max == r then
    h = (g - b) / d
    if g < b then h = h + 6 end
    elseif max == g then h = (b - r) / d + 2
    elseif max == b then h = (r - g) / d + 4
    end
    h = h / 6
  end

  return h, s, v, a
end

--[[
 * Converts an HSV color value to RGB. Conversion formula
 * adapted from http://en.wikipedia.org/wiki/HSV_color_space.
 * Assumes h, s, and v are contained in the set [0, 1] and
 * returns r, g, and b in the set [0, 255].
 *
 * @param   Number  h       The hue
 * @param   Number  s       The saturation
 * @param   Number  v       The value
 * @return  Array           The RGB representation
]]
function hsvToRgb(h, s, v, a)
  local r, g, b

  local i = math.floor(h * 6);
  local f = h * 6 - i;
  local p = v * (1 - s);
  local q = v * (1 - f * s);
  local t = v * (1 - (1 - f) * s);

  i = i % 6

  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  elseif i == 5 then r, g, b = v, p, q
  end

  return r * 255, g * 255, b * 255, a * 255
end

function mix(out, c1,c2,t )
	local it=1-t
	--hsv mix
	if false then
		local hsv1={rgbToHsv(c1.r,c1.g,c1.b,255)}
		local hsv2={rgbToHsv(c2.r,c2.g,c2.b,255)}
		local hsv_out={}
		for i=1,3 do
			hsv_out[i]=hsv1[i]*it+hsv2[i]*t
		end
		local rgb_out={hsvToRgb(hsv_out[1],hsv_out[2],hsv_out[3],255)}
		out.r=rgb_out[1]
		out.g=rgb_out[2]
		out.b=rgb_out[3]
		--]]
	else
		out.r=c1.r*it+c2.r*t
		out.g=c1.g*it+c2.g*t
		out.b=c1.b*it+c2.b*t
	end
	out.a=c1.a*it+c2.a*t
end

local log_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec4 palette[15];
uniform int palette_size;

uniform vec2 min_max;
uniform sampler2D tex_main;
uniform int auto_scale_color;

vec4 mix_palette(float value )
{
	if (palette_size==0)
		return vec4(0);
	value=clamp(value,0,1);
	float tg=value*(float(palette_size)); //[0,1]-->[0,#colors]
	float tl=floor(tg);

	float t=tg-tl;
	vec4 c1=palette[int(tl)];
	int hidx=min(int(ceil(tg)),palette_size-1);
	vec4 c2=palette[hidx];
	return mix(c1,c2,t);
}
vec2 local_minmax(vec2 pos)
{
	float nv=texture(tex_main,pos).x;
	float min=nv;
	float max=nv;
	float avg=0;
	float wsum=0;
	for(int i=0;i<50;i++)
		for(int j=0;j<50;j++)
		{
			vec2 delta=vec2(float(i-25)/1024,float(j-25)/1024);
			float dist=length(delta);
			float v=texture(tex_main,pos+delta).x;
			if(max<v)max=v;
			if(min>v)min=v;
			avg+=v*(1/(dist*dist+1));
			wsum+=(1/(dist*dist+1));
		}
	avg/=wsum;
	return vec2(log(avg/2+1),log(avg*2+1));
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float nv=texture(tex_main,normed).x;
	vec2 lmm=min_max;
	//vec2 lmm=local_minmax(normed);
	if(auto_scale_color==1)
		nv=(log(nv+1)-lmm.x)/(lmm.y-lmm.x);
	else
		nv=log(nv+1)/lmm.y;
	nv=clamp(nv,0,1);
	//nv=math.min(math.max(nv,0),1);
	//--mix(pix_out,c_u8,c_back,nv)
	//mix_palette(pix_out,nv)
	//img_buf:set(x,y,pix_out)
	color = mix_palette(nv);
}
]==]
local need_save
local visit_tex = textures.Make()
last_pos=last_pos or {0,0}
function draw_visits(  )
	local lmax=0
	local lmin=math.huge
	local vst=visits

	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local v=vst:get(x,y)
		if lmax<v then lmax=v end
		if lmin>v then lmin=v end
	end
	end
	lmax=math.log(lmax+1+0.5)
	lmin=math.log(lmin+1)

	log_shader:use()
	set_shader_palette()
	visit_tex:use(0)
	visit_tex:set(visits.d,visits.w,visits.h,2)
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

function step_iter( x,y,v0,v1)
	--[[
	local nx=x*x+v0-y*y
	local ny=2*x*y+v1
	--print(x,y,nx,ny)
	--return nzx,nzy
	--]]
	--[[
	local nx=(((v0)-(v1)/((x)*(v0)))-(math.cos((v0)-(x))))*((math.cos((v1)*(y)))+(math.sin(x)/(math.cos(x))))
	local ny=math.sin(((y)+(v1))*(math.sin(x))/(math.sin((x)*(x))))
	--]]
	--local r = x*x+y*y
	--return x/r+math.sin(y-r*v0),y/r-math.cos(x-r*v1)
	--local nx=math.sin(math.sin(y))/((math.cos(y))-(y/(x)))/(((math.sin(v0))-(v1/(x)))*(math.sin((y)+(v0))))
	local x_1=x
	local x_2=x*x/2
	local x_3=x*x*x/6

	local y_1=y
	local y_2=y*y/2
	local y_3=y*y*y/6

	local r=math.sqrt(x_2+y_2)
	--[[
	local nx=((v0)+(v1))+((v1)-(v0))+x_1*(((v1)+(v1))*((v0)+(v0)))+y_1*(((v0)/(v0))*((v1)*(v0)))+y_1*x_1*(((v1)-(v0))*((v1)-(v0)))+x_2*(((v1)/(v0))-((v0)/(v1)))+y_2*(((v0)-(v1))*((v1)+(v1)))+y_2*x_2*(((v1)*(v1))/((v1)-(v0)))+x_3*(((v0)+(v1))*((v0)*(v1)))+y_3*(((v0)*(v0))-((v0)*(v1)))+y_3*x_3*(((v0)+(v0))-((v1)-(v0)))
	local ny=((v0)/(v0))+((v1)-(v0))+x_1*(((v1)+(v1))*((v0)+(v0)))+y_1*(((v0)+(v1))-((v1)/(v0)))+y_1*x_1*(((v1)/(v1))-((v0)+(v1)))+x_2*(((v1)+(v0))/((v0)-(v1)))+y_2*(((v0)*(v1))+((v0)-(v0)))+y_2*x_2*(((v1)+(v0))*((v1)+(v0)))+x_3*(((v1)-(v1))*((v1)*(v0)))+y_3*(((v1)-(v1))/((v0)*(v0)))+y_3*x_3*(((v0)*(v1))-((v1)/(v1)))
	--]]
	--[[
	local nx=((v1)*(v1))/((v0)/(v1))+x_1*(((v0)-(v0))*((v1)-(v1)))+y_1*(((v1)-(v1))*((v0)+(v1)))+y_1*x_1*(((v0)+(v0))+((v1)/(v0)))+x_2*(((v0)*(v1))+((v1)+(v0)))+y_2*(((v0)+(v1))+((v1)+(v1)))+y_2*x_2*(((v0)+(v0))*((v1)/(v1)))+x_3*(((v0)+(v0))-((v0)/(v1)))+y_3*(((v0)+(v0))*((v1)*(v1)))+y_3*x_3*(((v0)*(v0))-((v0)+(v0)))
	local ny=((v0)*(v0))+((v1)-(v1))+x_1*(((v0)-(v0))*((v1)*(v1)))+y_1*(((v1)*(v0))+((v0)*(v1)))+y_1*x_1*(((v1)-(v1))-((v1)+(v1)))+x_2*(((v0)/(v0))-((v0)-(v0)))+y_2*(((v1)*(v0))+((v1)*(v0)))+y_2*x_2*(((v0)*(v0))-((v0)/(v0)))+x_3*(((v1)*(v0))*((v0)+(v0)))+y_3*(((v1)*(v1))*((v1)*(v0)))+y_3*x_3*(((v1)*(v1))/((v0)+(v0)))
	--]]
	--[[
	local nx=((v0)-(v0))-((v1)-(v0))+x_1*(((v0)/(v0))-((v1)-(v1)))+y_1*(((v1)+(v0))-((v0)+(v1)))+y_1*x_1*(((v1)+(v0))*((v1)-(v1)))+x_2*(((v0)+(v1))+((v1)/(v0)))+y_2*(((v0)/(v0))+((v0)+(v1)))+y_2*x_2*(((v0)*(v1))*((v1)+(v1)))+x_3*(((v0)-(v0))+((v0)+(v0)))+y_3*(((v1)+(v1))/((v0)*(v1)))+y_3*x_3*(((v1)/(v1))+((v0)/(v1)))
	local ny=((v1)*(v0))/((v0)/(v1))+x_1*(((v1)*(v1))-((v1)-(v0)))+y_1*(((v0)+(v0))-((v0)-(v0)))+y_1*x_1*(((v1)/(v1))-((v1)/(v0)))+x_2*(((v0)/(v1))/((v0)+(v0)))+y_2*(((v0)/(v0))*((v0)-(v1)))+y_2*x_2*(((v0)*(v0))+((v0)+(v0)))+x_3*(((v0)/(v0))+((v0)/(v0)))+y_3*(((v0)-(v0))+((v1)/(v1)))+y_3*x_3*(((v0)*(v1))+((v0)-(v0)))
	--]]
	

	-- make a ring with radius v0
	-- [[
	local nx,ny
	if r>v0 then
		nx=x-(x/r)*v1
		ny=y-(y/r)*v1
	else
		nx=x+(x/r)*v1
		ny=y+(y/r)*v1
	end
	--]]
	--local ny=math.cos((x/(x+v0)/(y))*(((v0)+(v1))+(math.cos(y))))*y

	-- [[
	local cs=math.cos(v1)
	local ss=math.sin(v1)
	local rx=nx*cs-ny*ss
	local ry=ny*cs+nx*ss
	nx=rx
	ny=ry
	--]]

	if r<0.00001 then
		r=1
	end
	local d=config.move_dist/r
	nx=nx*d
	ny=ny*d
	--end
	return nx,ny
	--return math.cos(x-y/v1)*x+math.sin(x*x*v0)*v1,math.sin(y-x/v0)*y+math.cos(y*y*v1)*v0
	--return x+v1,y*math.cos(x)-v0
end
function add_visit( x,y,v )
	visits:set(x,y, visits:get(x,y)+v)
end
function smooth_visit( tx,ty )
	local lx=math.floor(tx)
	local ly=math.floor(ty)
	local hx,hy=coord_mapping(lx+1,ly+1)
	hx=math.floor(hx)
	hy=math.floor(hy)
	local fr_x=tx-lx
	local fr_y=ty-ly

	--TODO: writes to out of bounds (hx/hy out of bounds)
	add_visit(lx,ly,(1-fr_x)*(1-fr_y))
	add_visit(lx,hy,(1-fr_x)*fr_y)
	add_visit(hx,ly,fr_x*(1-fr_y))
	add_visit(hx,hy,fr_x*fr_y)
end
function clear_buffers(  )
	img_buf:clear()
	visits:clear()
	img_buf:present();
end
function random_math_old( num_params,len )
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
		local ch={--[["math.sin(R)","math.cos(R)",]]--[["math.log(R)",]]"(R)/(R)",
		"(R)*(R)","(R)-(R)","(R)+(R)"}
		return ch[math.random(1,#ch)]
	end
	
	while #cur_string<len do
		cur_string=string.gsub(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",terminal)
	return cur_string
end
function random_math_series( num_params,start_pow,end_pow )
	local cur_string="R"
	local len=150
	local terminal=function (  )
		local v=math.random(0,num_params-1)
		return 'v'..v
	end
	for i=start_pow,end_pow do
		if i>0 then
			cur_string=cur_string..string.format("+x_%d*(R)+y_%d*(R)+y_%d*x_%d*(R)",i,i,i,i)
		end
	end

	local function M(  )
		local ch={--[["math.sin(R)","math.cos(R)",]]--[["math.log(R)",]]"(R)/(R)",
		"(R)*(R)","(R)-(R)","(R)+(R)"}
		return ch[math.random(1,#ch)]
	end
	
	while #cur_string<len do
		cur_string=string.gsub(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",terminal)
	return cur_string
end
palette=palette or {colors={{0,0,0,1},{0.8,0,0,1},{0,0,0,1},{0,0.2,0.2,1},{0,0,0,1}}}

function gen_palette( )
	local ret={}
	palette.colors=ret

	local h1=math.random()
	local s=math.random()*0.3+0.7
	local l=math.random()*0.6+0.2
	local function gen_shades(tbl, h_start,s_start,l_start,l_end,count)
		local diff=l_end-l_start
		for i=0,count-1 do
			table.insert(tbl,hslToRgb_normed(h_start,s_start,l_start+diff*(i/(count-1)),1))
		end
	end
	-- [[ complementary
	gen_shades(ret,h1,s,l,0.05,5)
	gen_shades(ret,1-h1,s,0.05,l,5)
	--]]
	--[[ triadic
	gen_shades(ret,h1,s,0,l,5)
	gen_shades(ret,math.fmod(h1+0.33,1),s,l,0.1,5)
	gen_shades(ret,math.fmod(h1+0.66,1),s,0.1,l,3)
	--]]
	--[[ anologous
	gen_shades(ret,h1,s,0.2,l,3)
	gen_shades(ret,math.fmod(h1+0.05,1),s,0.2,l,3)
	gen_shades(ret,math.fmod(h1+0.1,1),s,l,0,3)
	gen_shades(ret,math.fmod(h1+0.15,1),s,l,0,3)
	gen_shades(ret,math.fmod(h1+0.2,1),s,l,0,3)
	--]]
	--TODO: compound
	--
end
function palette_chooser()
	if imgui.Button("Randomize") then
		gen_palette()
	end
	if palette.colors[palette.current]==nil then
		palette.current=1
	end
	palette.current=palette.current or 1
	if #palette.colors>0 then
		_,palette.current=imgui.SliderInt("Color id",palette.current,1,#palette.colors)
	end
	imgui.SameLine()
	if #palette.colors<15 then
		if imgui.Button("Add") then
			table.insert(palette.colors,{0,0,0,1})
			if palette.current<1 then
				palette.current=1
			end
		end
	end
	if #palette.colors>0 then
		imgui.SameLine()
		if imgui.Button("Remove") then
			table.remove(palette.colors,palette.current)
			palette.current=1
		end
		if imgui.Button("Print") then
			for i,v in ipairs(palette.colors) do
				print(string.format("#%02X%02X%02X%02X",math.floor(v[1]*255),math.floor(v[2]*255),math.floor(v[3]*255),math.floor(v[4]*255)))
			end
		end
	end
	if #palette.colors>0 then
		_,palette.colors[palette.current]=imgui.ColorEdit4("Current color",palette.colors[palette.current],true)
	end
end
function set_shader_palette()
	log_shader:set_i("palette_size",#palette.colors)
	for i=1,#palette.colors do
		local c=palette.colors[i]
		log_shader:set(string.format("palette[%d]",i-1),c[1],c[2],c[3],c[4])
	end
end
function is_mouse_down(  )
	return __mouse.clicked0 and not __mouse.owned0, __mouse.x,__mouse.y
end
function save_img(tile_count)
	if tile_count==1 then

		local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
		for k,v in pairs(config) do
			if type(v)~="table" then
				config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
			end
		end
		img_buf:read_frame()
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
		image_no=image_no+1
	else
		img_buf:read_frame()
		local w=img_buf.w
		local h=img_buf.h
		local tile_image=make_image_buffer(w*tile_count,h*tile_count)
		for x=0,(w-1)*tile_count do
		for y=0,(h-1)*tile_count do
			local tx,ty=coord_mapping(x,y)
			tile_image:set(x,y,img_buf:get(tx,ty))
		end
		end
		tile_image:save(string.format("tiled_%d.png",os.time(os.date("!*t"))),config_serial)
	end
end
function gui(  )
	imgui.Begin("IFS play")
	palette_chooser()
	draw_config(config)
	local s=STATE.size
	if imgui.Button("Clear image") then
		clear_buffers()
	end
	--imgui.SameLine()
	generate_num_params=generate_num_params or 1

	local changed
	changed,generate_num_params=imgui.SliderInt("Num params",generate_num_params,1,10)
	if imgui.Button("Gen function") then
		print(random_math_series(generate_num_params,0,3))
	end

	--imgui.SameLine()
	tile_count=tile_count or 1
	_,tile_count=imgui.SliderInt("tile count:",tile_count,1,8)
	if imgui.Button("Save image") then
		--this saves too much (i.e. all gui and stuff, we need to do it in correct place (or render to texture)
		--save_img(tile_count)
		need_save=tile_count
	end
	local m, mx,my=is_mouse_down() 
	--if m then
	if mx>=0 and mx< size[1] and my>=0 and my<size[2] then
		local mv=visits:get(math.floor(mx),math.floor(my))
		imgui.Text(string.format("Mouse: %d %d value:%g",mx,my,mv))
	end
	--end
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
function mix_palette(out,input_t )
	if #palette.colors<=1 then
		return
	end
	if input_t>1 then input_t=1 end
	if input_t<0 then input_t=0 end
--[[
	local tbin=input_t*20
	bins[math.floor(tbin)]=bins[math.floor(tbin)] or 0
	bins[math.floor(tbin)]=bins[math.floor(tbin)]+1
]]
	local tg=input_t*(#palette.colors-1) -- [0,1]--> [0,#colors]
	local tl=math.floor(tg)

	local t=tg-tl
	local it=1-t
	local c1=palette.colors[tl+1]
	local c2=palette.colors[math.ceil(tg)+1]
	if c1==nil or c2==nil then
		out={0,0,0,255}
		return
	end
	--hsv mix
	if false then
		local hsv1={rgbToHsv(c1[1]*255,c1[2]*255,c1[3]*255,255)}
		local hsv2={rgbToHsv(c2[1]*255,c2[2]*255,c2[3]*255,255)}
		local hsv_out={}
		for i=1,3 do
			hsv_out[i]=hsv1[i]*it+hsv2[i]*t
		end
		local rgb_out={hsvToRgb(hsv_out[1],hsv_out[2],hsv_out[3],255)}
		out.r=rgb_out[1]
		out.g=rgb_out[2]
		out.b=rgb_out[3]
		--]]
	else
		out.r=(c1[1]*it+c2[1]*t)*255
		out.g=(c1[2]*it+c2[2]*t)*255
		out.b=(c1[3]*it+c2[3]*t)*255
	end
	out.a=(c1[4]*it+c2[4]*t)*255
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
		--mix(pix_out,c_u8,c_back,dist)
		mix_palette(pix_out,math.fmod(dist,1))
		img_buf:set(x,y,pix_out)
	end
	end

	img_buf:present()
end
function auto_clear(  )
	local cfg_pos=0
	for i,v in ipairs(config) do
		if v[1]=="v0" then
			cfg_pos=i
			break
		end
	end
	local need_clear=false
	for i=0,5 do
		if config[cfg_pos+i].changing then
			need_clear=true
		end
	end
	if need_clear then
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

function line_visit( x0,y0,x1,y1 )
	local dx = x1 - x0;
    local dy = y1 - y0;
    if math.sqrt(dx*dx+dy*dy)>5000 then
    	return
    end
    add_visit(mod(x0,size[1]),mod(y0,size[1]),1)
    if (dx ~= 0) then
        local m = dy / dx;
        local b = y0 - m*x0;
        if x1 > x0 then
            dx = 1
        else
            dx = -1
        end
        while math.floor(x0) ~= math.floor(x1) do
            x0 = x0 + dx
            y0 = math.floor(m*x0 + b + 0.5);
            add_visit(mod(x0,size[1]),mod(y0,size[1]),1)
            --print(x0,y0)
        end

    end
end
function rand_line_visit( x0,y0,x1,y1 )
	local dx=x1-x0
	local dy=y1-y0
	local d=math.sqrt(dx*dx+dy*dy)
	dx=dx/d
	dy=dy/d
	for i=1,config.line_visits do
		local r=math.random()*d

		local tx=mod(x0+dx*r,size[1])
		local ty=mod(y0+dy*r,size[2])
		smooth_visit(tx,ty)
	end
end
function coord_mapping( tx,ty )
	local s=STATE.size
	--return x,y
	--return mod(x,s[1]),mod(y,s[2])
	local div_x=math.floor(tx/s[1])
	local div_y=math.floor(ty/s[2])
	tx=mod(tx,s[1])
	ty=mod(ty,s[2])
	if div_x%2==1 then
		tx=s[1]-tx-1
	end
	if div_y%2==1 then
		ty=s[2]-ty-1
	end
	return tx,ty
end
function update_real(  )
	__no_redraw()
	__clear()
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
	local ad=config.arg_disp
	local gen_radius=config.gen_radius
	for i=1,config.ticking do
		--TODO: generate IN screen
		--[[local x = math.random()-0.5
		local y = math.random()-0.5]]
		local x=math.random()*gen_radius-gen_radius/2
		local y=math.random()*gen_radius-gen_radius/2
		local lx
		local ly
		for i=1,config.ticking2 do
			local rv0=(math.random()-0.5)*2*v0*ad
			local rv1=(math.random()-0.5)*2*v1*ad
			x,y=step_iter(x,y,v0+rv0,v1+rv1)
			--[[
			x=mod(x,1000)
			y=mod(y,1000)
			--]]
			if x*x+y*y>1e2 then
				break
			end
			local tx=((x-cx)*iscale+0.5)*s[1]
			local ty=((y-cy)*iscale+0.5)*s[2]
			--[[ LINE-ISH VISITING
			if lx then
				--line_visit(lx,ly,tx,ty) --VERY SLOW!!
				rand_line_visit(lx,ly,tx,ty)
			end
			lx=tx
			ly=ty
			--]]
			-- [[ TILING FRACTAL
			tx,ty=coord_mapping(tx,ty)
			if tx>=0 and math.floor(tx)<s[1] and ty>=0 and math.floor(ty)<s[2] then
				smooth_visit(tx,ty)
			end
			--]]
			--[[ SIMPLE SMOOTH VISITING
			if tx>=0 and tx<s[1]-1 and ty>=0 and ty<s[2]-1 then
				smooth_visit(tx,ty)
			else
				break
			end
			--]]
			--[[ NON_SMOOTH VISITING
			local v=visits:get(math.floor(tx),math.floor(ty))
			visits:set(math.floor(tx),math.floor(ty),v+1)
			--]]
		end
		
		
	end
	--local end_calc=os.time()
	--local time_delta=os.difftime(end_calc,start_calc)
	--print("Calculation took:",time_delta," or:",time_delta/(config.ticking*config.ticking2), " per iteration")
	--if math.fmod(tick,10)==0 then
		draw_visits()
		--draw_visits_local()
	--end
	--[[if math.fmod(tick,100)==0 then
		save_img(1)
	end]]
	tick=tick+1
end