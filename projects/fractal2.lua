
require "common"
require "colors"

local size=STATE.size
local max_size=math.min(size[1],size[2])/2
local max_palette_size=20
local sample_count=400
img_buf=img_buf or make_image_buffer(size[1],size[2])
visits=visits or make_float_buffer(size[1],size[2])
samples=make_flt_half_buffer(sample_count,sample_count)
samples2=make_flt_half_buffer(sample_count,sample_count)
palette_img=make_flt_buffer(max_size,1)
function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
	visits=make_float_buffer(size[1],size[2])
end



tick=tick or 0
config=make_config({
	{"render",true,type="boolean"},
	{"auto_scale_color",false,type="boolean"},
	{"ticking",100,type="int",min=1,max=1000},
	{"line_visits",1,type="int",min=1,max=100},
	{"arg_disp",0,type="float",min=0,max=1},
	{"v0",-0.211,type="float",min=-5,max=5},
	{"v1",-0.184,type="float",min=-5,max=5},
	{"v2",-0.211,type="float",min=-5,max=5},
	{"v3",-0.184,type="float",min=-5,max=5},
	{"ticking2",10,type="int",min=1,max=10000},
	{"move_dist",0.1,type="float",min=0.001,max=2},
	{"scale",1,type="float",min=0.00001,max=20},
	{"cx",0,type="float",min=-1,max=1},
	{"cy",0,type="float",min=-1,max=1},
	{"min_value",0,type="float",min=0,max=20},
	{"gen_radius",1,type="float",min=0,max=10},
--[[
	{"gamma",1,type="float",min=0,max=10},
	{"contrast",1,type="float",min=0,max=10},
	{"brightness",0,type="float",min=0,max=10},
--]]
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

local log_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec4 palette[15];
uniform int palette_size;

uniform vec2 min_max;
uniform sampler2D tex_main;
uniform sampler2D tex_palette;
uniform int auto_scale_color;

vec4 mix_palette(float value )
{
	if (palette_size==0)
		return vec4(0);

	//value=clamp(value,0,1);
	return texture(tex_palette,vec2(value,0));
}
vec4 mix_palette2(float value )
{
	if (palette_size==0)
		return vec4(0);
	value=clamp(value,0,1);
	float tg=value*(float(palette_size)-1); //[0,1]-->[0,#colors]
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
	return vec2(log(avg/10+1),log(avg*10+1));
}
void main_norm(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float nv=texture(tex_main,normed).x;
	vec2 lmm=min_max;
	//vec2 lmm=local_minmax(normed);
	if(auto_scale_color==1)
		nv=(nv-lmm.x)/(lmm.y-lmm.x);
	else
		nv=(nv)/lmm.y;
	nv=clamp(nv,0,1);
	color = mix_palette2(nv);
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
	color = mix_palette2(nv);
}
]==]
local need_save
local visit_tex = textures.Make()
local palette_tex=textures.Make()
last_pos=last_pos or {0,0}
function draw_visits(  )
	local lmax=0
	local lmin=math.huge
	local vst=visits

	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local v=vst:get(x,y)
		if v>math.exp(config.min_value)-1 then --skip non-visited tiles
			if lmax<v then lmax=v end
			if lmin>v then lmin=v end
		end
	end
	end
	-- [[
	lmax=math.log(lmax+1)
	lmin=math.log(lmin+1)
	--]]
	log_shader:use()
	visit_tex:use(0)
	visit_tex:set(visits.d,visits.w,visits.h,2)
	set_shader_palette(log_shader)
	
	--[[ Seems wrong for some reason ?
	update_palette_img()
	palette_tex:use(1,1,1)
	palette_img:write_texture(palette_tex)
	log_shader:set_i("tex_palette",1)
	]]
	log_shader:set("min_max",lmin,lmax)
	log_shader:set_i("tex_main",0)
	
	log_shader:set_i("palette_size",#palette.colors)
--[[
	log_shader:set("gamma",config.gamma)
	log_shader:set("brightness",config.brightness)
	log_shader:set("contrast",config.contrast)
--]]
	local auto_scale=0
	if config.auto_scale_color then auto_scale=1 end
	log_shader:set_i("auto_scale_color",auto_scale)
	log_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
end
--[[
iter_funcs={
	{0,1,function ( x,y,v0,v1 )
		local r = x*x+y*y
		return r*v0,(x*v1+y*(v0-v1))/r
	end},
	{0.8,-0.25,function(x,y,v0,v1 )
		local nx=x*v1-y*v0
		local ny=x*x
		return nx,ny
	end},
	{-0.86,-0.5,function(x,y,v0,v1 )
		local r = x*x+y*y
		return  x/r+math.sin(y-r*v0),y/r-math.cos(x-r*v1)
	end}
}
]]
function step_iter( x,y,v0,v1,v2,v3,sx,sy)
	--[[
	local min_dist=math.huge
	local min_id=1
	for i,v in ipairs(iter_funcs) do
		local dx=x-v[1]*config.fdist
		local dy=y-v[2]*config.fdist
		local dist=dx*dx+dy*dy
		if dist<min_dist then
			min_dist=dist
			min_id=i
		end
	end
	local nx,ny=iter_funcs[min_id][3](x,y,v0,v1)
	--]]
	--[[
	local nx,ny=x,y
	--]]
	--[[
	local nx=y*y/2+x*y*y+sx*v0*x
	local ny=*x-x*x*x+sy
	--]]
	--[[
	local nx=-(x+v0)/(v1*(sx*sx+sy*sy))-x/v1
	local ny=y*sy/(v1*(sx*sx+sy*sy))+y/v1
	--]]
	local nx=v0*sx+v1*x*x-v1*y*y+v2*x*sx-v2*y*sy
	local ny=v0*sy+v1*2*x*y+v2*x*sy*sx+v2*y*sy
	--[[
	local nx=x*x-y*y+sx
	local ny=2*x*y+sy
	--]]
	--[[
	local nx=x*x-y+v0
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
	--[[
	local x_1=x
	local x_2=x*x/2
	local x_3=x*x*x/6

	local y_1=y
	local y_2=y*y/2
	local y_3=y*y*y/6

	local x_i1=1/x
	local x_i2=1/(x*x*2)
	local x_i3=1/(x*x*x*6)

	local y_i1=1/y
	local y_i2=1/(y*y*2)
	local y_i3=1/(y*y*y*6)

	local r=math.sqrt(x*x+y*y)
	local a=math.atan(y,x)
	--]]
	--[[
	local nx=math.sin(v3)+r*(math.sin(v2))+a*(math.sin(v3))+y_i3*a*(math.log(math.abs(v1)+1))+x_i2*(math.log(math.abs(v3)+1))+y_i2*((v2)*(v0))+y_i2*x_i2*(math.sin(v1))+x_i1*(math.cos(v2))+y_i1*(math.cos(v3))+y_i1*x_i1*((v2)-(v0))+x_1*(math.cos(v0))+y_1*((v0)*(v2))+y_1*x_1*((v0)-(v0))+x_2*((v0)-(v3))+y_2*((v1)*(v1))+y_2*x_2*((v1)*(v0))+x_3*((v2)-(v1))+y_3*((v0)/(v1))+y_3*x_3*((v0)+(v3))
	local ny=(v0)+(v0)+x_i3*((v0)*(v0))+y_i3*(math.log(math.abs(v1)+1))+y_i3*x_i3*((v1)/(v1))+x_i2*(math.log(math.abs(v1)+1))+y_i2*((v1)-(v1))+y_i2*x_i2*((v0)*(v0))+x_i1*((v0)+(v0))+y_i1*((v1)-(v1))+y_i1*x_i1*(math.log(math.abs(v1)+1))+x_1*((v0)+(v0))+y_1*(math.cos(v0))+y_1*x_1*((v0)/(v1))+x_2*((v0)*(v1))+y_2*((v0)/(v1))+r*x_2*((v0)-(v1))+x_3*((v0)+(v1))+a*((v1)*(v0))+y_3*x_3*((a)-(v1))
	--]]
	--[[
	local nx=math.log(math.abs(v1)+1)+x_i3*(math.log(math.abs(v0)+1))+y_i3*(math.log(math.abs(v0)+1))+y_i3*x_i3*(math.cos(v0))+x_i2*(math.sin(v1))+y_i2*(math.cos(v1))+y_i2*x_i2*((v0)+(v0))+x_i1*(math.sin(v0))+y_i1*((v0)+(v0))+y_i1*x_i1*(math.log(math.abs(v0)+1))+x_1*((v0)-(v1))+y_1*((v1)-(v1))+y_1*x_1*(math.cos(v0))+x_2*(math.cos(v1))+y_2*((v1)*(v0))+y_2*x_2*(math.log(math.abs(v1)+1))+x_3*((v1)+(v0))+y_3*(math.cos(v0))+y_3*x_3*(math.log(math.abs(v0)+1))
	local ny=(v0)+(v0)+x_i3*((v0)*(v0))+y_i3*(math.log(math.abs(v1)+1))+y_i3*x_i3*((v1)/(v1))+x_i2*(math.log(math.abs(v1)+1))+y_i2*((v1)-(v1))+y_i2*x_i2*((v0)*(v0))+x_i1*((v0)+(v0))+y_i1*((v1)-(v1))+y_i1*x_i1*(math.log(math.abs(v1)+1))+x_1*((v0)+(v0))+y_1*(math.cos(v0))+y_1*x_1*((v0)/(v1))+x_2*((v0)*(v1))+y_2*((v0)/(v1))+y_2*x_2*((v0)-(v1))+x_3*((v0)+(v1))+y_3*((v1)*(v0))+y_3*x_3*((v1)-(v1))
	--]]
	--[[
	local nx=math.sin(v3)+x_i3*(math.sin(v2))+y_i3*(math.sin(v3))+y_i3*x_i3*(math.log(math.abs(v1)+1))+x_i2*(math.log(math.abs(v3)+1))+y_i2*((v2)*(v0))+y_i2*x_i2*(math.sin(v1))+x_i1*(math.cos(v2))+y_i1*(math.cos(v3))+y_i1*x_i1*((v2)-(v0))+x_1*(math.cos(v0))+y_1*((v0)*(v2))+y_1*x_1*((v0)-(v0))+x_2*((v0)-(v3))+y_2*((v1)*(v1))+y_2*x_2*((v1)*(v0))+x_3*((v2)-(v1))+y_3*((v0)/(v1))+y_3*x_3*((v0)+(v3))
	local ny=(v2)+(v3)+x_i3*((v0)+(v3))+y_i3*(math.sin(v3))+y_i3*x_i3*(math.cos(v1))+x_i2*((v0)*(v1))+y_i2*(math.sin(v3))+y_i2*x_i2*(math.log(math.abs(v2)+1))+x_i1*(math.cos(v2))+y_i1*(math.sin(v2))+y_i1*x_i1*((v0)/(v0))+x_1*(math.log(math.abs(v1)+1))+y_1*((v3)-(v1))+y_1*x_1*(math.log(math.abs(v1)+1))+x_2*(math.log(math.abs(v0)+1))+y_2*((v2)-(v2))+y_2*x_2*((v0)/(v0))+x_3*(math.log(math.abs(v0)+1))+y_3*((v1)-(v0))+y_3*x_3*(math.log(math.abs(v1)+1))
	--]]
	--[[
	local nx=math.log(math.abs(v1)+1)+x_i3*((v0)*(v2))+y_i3*((v0)*(v1))+y_i3*x_i3*(math.cos(v0))+x_i2*((v3)/(v0))+y_i2*((v1)*(v2))+y_i2*x_i2*((v3)+(v1))+x_i1*(math.log(math.abs(v1)+1))+y_i1*((v0)-(v1))+y_i1*x_i1*(math.cos(v2))+x_1*(math.sin(v1))+y_1*((v2)+(v3))+y_1*x_1*(math.cos(v1))+x_2*((v1)*(v1))+y_2*(math.cos(v0))+y_2*x_2*((v2)/(v0))+x_3*((v1)/(v1))+y_3*((v3)*(v3))+y_3*x_3*((v2)-(v2))
	local ny=math.log(math.abs(v2)+1)+x_i3*((v2)+(v0))+y_i3*(math.cos(v1))+y_i3*x_i3*((v3)/(v3))+x_i2*((v0)*(v2))+y_i2*((v1)/(v2))+y_i2*x_i2*((v1)/(v1))+x_i1*(math.cos(v0))+y_i1*(math.cos(v1))+y_i1*x_i1*(math.sin(v1))+x_1*((v2)-(v2))+y_1*((v2)/(v2))+y_1*x_1*((v3)-(v3))+x_2*((v2)+(v1))+y_2*((v2)-(v2))+y_2*x_2*((v2)-(v2))+x_3*(math.cos(v0))+y_3*(math.cos(v3))+y_3*x_3*(math.cos(v1))
	--]]
	--[[
	local nx=((v0)/(v2))-((v2)*(v0))+x_1*(((v0)-(v0))-((v0)*(v3)))+y_1*(((v1)+(v3))/((v0)*(v0)))+y_1*x_1*(((v3)+(v2))*((v3)/(v0)))+x_2*(((v1)/(v2))-((v2)/(v2)))+y_2*(((v2)+(v1))*((v3)/(v0)))+y_2*x_2*(((v0)+(v2))+((v1)+(v1)))+x_3*(((v1)+(v1))+((v3)+(v2)))+y_3*(((v2)*(v2))*((v3)+(v3)))+y_3*x_3*(((v1)/(v0))+((v3)*(v3)))
    local ny=((v1)-(v3))-((v0)+(v0))+x_1*(((v2)+(v1))+((v3)+(v3)))+y_1*(((v1)/(v3))-((v0)-(v0)))+y_1*x_1*(((v1)-(v2))+((v3)/(v1)))+x_2*(((v1)/(v2))-((v1)/(v0)))+y_2*(((v0)*(v2))-((v3)+(v2)))+y_2*x_2*(((v0)-(v3))+((v0)*(v3)))+x_3*(((v0)*(v3))/((v2)*(v0)))+y_3*(((v2)-(v2))*((v1)/(v3)))+y_3*x_3*(((v2)*(v0))+((v0)/(v3)))
    --]]
	--[[
	local nx=(v2)*(v2)+x_i3*((v3)+(v2))+y_i3*((v1)-(v2))+y_i3*x_i3*((v0)+(v2))+x_i2*((v1)+(v0))+y_i2*((v0)+(v1))+y_i2*x_i2*((v0)*(v3))+x_i1*((v0)+(v3))+y_i1*((v2)+(v1))+y_i1*x_i1*((v3)/(v0))+x_1*((v3)-(v1))+y_1*((v3)+(v2))+y_1*x_1*((v0)+(v3))+x_2*((v2)-(v2))+y_2*((v3)-(v0))+y_2*x_2*((v3)+(v0))+x_3*((v0)-(v1))+y_3*((v1)/(v1))+y_3*x_3*((v0)+(v0))
	local ny=(v1)/(v1)+x_i3*((v2)+(v2))+y_i3*((v3)*(v0))+y_i3*x_i3*((v2)*(v2))+x_i2*((v1)/(v2))+y_i2*((v3)*(v1))+y_i2*x_i2*((v0)+(v3))+x_i1*((v2)-(v0))+y_i1*((v2)*(v3))+y_i1*x_i1*((v3)/(v1))+x_1*((v3)*(v3))+y_1*((v3)/(v0))+y_1*x_1*((v0)/(v3))+x_2*((v2)*(v2))+y_2*((v0)*(v2))+y_2*x_2*((v0)-(v0))+x_3*((v1)*(v1))+y_3*((v0)*(v3))+y_3*x_3*((v2)/(v3))
	--]]
	--[[
	local nx=x_2*v0-y_2;
	local ny=y_2*v1/x_2+x_2*v1;
	--]]
	--[[
	local nx=(v1)-(v1)+x_1*(math.sin(v0))+y_1*((v0)/(v0))+y_1*x_1*(math.log(math.abs(v0)+1))+x_2*(math.sin(v0))+y_2*(math.sin(v0))+y_2*x_2*((v0)/(v1))+x_3*(math.sin(v0))+y_3*(math.sin(v0))+y_3*x_3*(math.log(math.abs(v1)+1))
	local ny=(v1)/(v0)+x_1*(math.log(math.abs(v1)+1))+y_1*(math.cos(v0))+y_1*x_1*(math.sin(v0))+x_2*((v1)-(v0))+y_2*(math.log(math.abs(v0)+1))+y_2*x_2*((v1)-(v1))+x_3*((v0)/(v1))+y_3*(math.cos(v0))+y_3*x_3*((v1)*(v0))
	--]]
	--[[
	local nx=v0+x_i3*(v0)+y_i3*(v0)+y_i3*x_i3*(v0)+x_i2*(v1)+y_i2*(v0)+y_i2*x_i2*(v0)+x_i1*(v0)+y_i1*(v0)+y_i1*x_i1*(v0)+x_1*(v1)+y_1*(v0)+y_1*x_1*(v0)+x_2*(v0)+y_2*(v0)+y_2*x_2*(v0)+x_3*(v0)+y_3*(v1)+y_3*x_3*(v0)
	local ny=v1+x_i3*(v0)+y_i3*(v1)+y_i3*x_i3*(v1)+x_i2*(v0)+y_i2*(v0)+y_i2*x_i2*(v1)+x_i1*(v0)+y_i1*(v1)+y_i1*x_i1*(v0)+x_1*(v1)+y_1*(v0)+y_1*x_1*(v0)+x_2*(v0)+y_2*(v0)+y_2*x_2*(v1)+x_3*(v1)+y_3*(v0)+y_3*x_3*(v0)
	--]]
	--[[
	local nx=((v1)+(v1))+((v1)/(v0))+x_1*(((v0)-(v1))-((v0)/(v1)))+y_1*(((v1)*(v1))+((v1)-(v1)))+y_1*x_1*(((v1)/(v1))*((v1)-(v0)))+x_2*(((v1)+(v1))*((v0)+(v0)))+y_2*(((v1)-(v0))*((v1)*(v0)))+y_2*x_2*(((v0)-(v1))*((v1)/(v0)))+x_3*(((v0)+(v1))*((v0)-(v0)))+y_3*(((v1)/(v0))/((v0)/(v1)))+y_3*x_3*(((v0)+(v0))+((v1)-(v0)))
	local ny=((v0)+(v1))+((v1)+(v1))+x_1*(((v0)+(v0))-((v0)*(v1)))+y_1*(((v0)/(v1))*((v0)+(v0)))+y_1*x_1*(((v0)+(v0))-((v1)+(v0)))+x_2*(((v0)+(v1))-((v0)*(v1)))+y_2*(((v0)-(v1))-((v0)-(v0)))+y_2*x_2*(((v1)-(v0))*((v0)*(v1)))+x_3*(((v1)/(v0))+((v0)-(v0)))+y_3*(((v1)-(v1))*((v1)/(v0)))+y_3*x_3*(((v0)/(v0))-((v1)+(v1)))
	--]]
	--[[
	local nx=math.sqrt(math.abs(math.cos(x_1-y_2)*v0+math.sin(y_2-x_3)*v1))-math.sqrt(math.abs(math.sin(x_1-y_2)*v1+math.cos(y_2-x_3)*v0))
	local ny=math.sin(y_1-x_2)*v1+math.cos(x_2-y_3)*v0
	--]]
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
	--[[
	local nx=math.log(math.abs(x_1/math.cos(y*y*v1))+1)*x
	local ny=math.log(math.abs(y_1/math.sin(x*x*v0))+1)*y
	--]]
	--[[
	local nx=x_1/(y_1-x_1*v0)
	local ny=x_2/(y_2-x_2*v1)
	--]]
	-- make a ring with radius v0
	--[[
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

	--[[
	local cs=math.cos(v1)
	local ss=math.sin(v1)
	local rx=nx*cs-ny*ss
	local ry=ny*cs+nx*ss
	nx=rx
	ny=ry
	--]]
	--[[
	local delta=math.sqrt(nx*nx+ny*ny)
	if delta<0.00001 then
		delta=1
	end
	local d=config.move_dist/delta
	nx=x+nx*d
	ny=y+ny*d
	--]]
	--end
	return nx,ny
	--return math.cos(x-y/v1)*x+math.sin(x*x*v0)*v1,math.sin(y-x/v0)*y+math.cos(y*y*v1)*v0
	--return x+v1,y*math.cos(x)-v0
end
function add_visit( x,y,v )
	visits:set(x,y, visits:get(x,y)+v)
end
function safe_visit( x,y,v )
	if x>=0 and x<STATE.size[1] and y>=0 and y<STATE.size[2] then
		add_visit(x,y,v)
	end
end
function smooth_visit( tx,ty,w )
	local lx=math.floor(tx)
	local ly=math.floor(ty)
	local hx=math.floor(tx+1)
	local hy=math.floor(ty+1)
	local fr_x=tx-lx
	local fr_y=ty-ly
	local gx11,gy11=coord_mapping(lx,ly)
	safe_visit(gx11,gy11,(1-fr_x)*(1-fr_y)*w)

	local gx12,gy12=coord_mapping(lx,hy)
	safe_visit(gx12,gy12,(1-fr_x)*fr_y*w)

	local gx21,gy21=coord_mapping(hx,ly)
	safe_visit(gx21,gy21,fr_x*(1-fr_y)*w)

	local gx22,gy22=coord_mapping(hx,hy)
	safe_visit(gx22,gy22,fr_x*fr_y*w)
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
	local len=250
	local terminal=function (  )
		local v=math.random(0,num_params-1)
		return 'v'..v
	end
	for i=start_pow,end_pow do
		if i>0 then
			cur_string=cur_string..string.format("+x_%d*(R)+y_%d*(R)+y_%d*x_%d*(R)",i,i,i,i)
		elseif i<0 then
			cur_string=cur_string..string.format("+x_i%d*(R)+y_i%d*(R)+y_i%d*x_i%d*(R)",-i,-i,-i,-i)
		end
	end

	local function M(  )
		local ch={--[["math.sin(R)","math.cos(R)","math.log(math.abs(R)+1)",]]"(R)/(R)",
		"(R)*(R)","(R)-(R)","(R)+(R)"}
		return ch[math.random(1,#ch)]
	end
	
	while #cur_string<len do
		cur_string=string.gsub(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",terminal)
	return cur_string
end
palette=palette or {show=false,colors={{0,0,0,1},{0.8,0,0,1},{0,0,0,1},{0,0.2,0.2,1},{0,0,0,1}}}
function update_palette_img(  )
	if palette_img.w~=#palette.colors then
		palette_img=make_flt_buffer(#palette.colors,1)
	end
	for i,v in ipairs(palette.colors) do
		palette_img:set(i-1,0,v)
	end
end
function set_shader_palette(s)
	s:set_i("palette_size",#palette.colors)
	for i=1,#palette.colors do
		local c=palette.colors[i]
		s:set(string.format("palette[%d]",i-1),c[1],c[2],c[3],c[4])
	end
end
function iterate_color(tbl, hsl1,hsl2,steps )
	local hd=hsl2[1]-hsl1[1]
	local sd=hsl2[2]-hsl1[2]
	local ld=hsl2[3]-hsl1[3]

	for i=0,steps-1 do
		local v=i/steps
		table.insert(tbl,hslToRgb_normed(hsl1[1]+hd*v,hsl1[2]+sd*v,hsl1[3]+ld*v,1))
	end
end
function gen_palette( )
	local ret={}
	palette.colors=ret

	local h1=math.random()
	local s=math.random()*0.6+0.2
	local l=math.random()*0.6+0.2
	
	local function gen_shades(tbl, h_start,s_start,l_start,l_end,count)
		local diff=l_end-l_start
		for i=0,count-1 do
			table.insert(tbl,hslToRgb_normed(h_start,s_start,l_start+diff*(i/(count-1)),1))
		end
	end
	-- [[ complementary2
	local s2=math.random()*0.6+0.2
	local l2=math.random()*0.6+0.2
	iterate_color(ret,{h1,s,l},{1-h1,s,l2},10)
	--]]
	--[[ triadic2
	local s2=math.random()*0.6+0.2
	local l2=math.random()*0.6+0.2
	local s3=math.random()*0.6+0.2
	local l3=math.random()*0.6+0.2
	local h2=math.fmod(h1+0.33,1)
	local h3=math.fmod(h1+0.66,1)
	iterate_color(ret,{h1,s,l},{h2,s2,l2},5)
	iterate_color(ret,{h2,s2,l2},{h3,s3,l3},5)
	--iterate_color(ret,{h3,s3,l3},{h1,s,l},5)
	--]]
	--[[ anologous2
	local h2=math.fmod(h1+0.05,1)
	local h3=math.fmod(h1+0.1,1)
	local h4=math.fmod(h1+0.2,1)
	local s2=s+math.random()*0.2-0.1
	if s2>1 then s2=1 end
	if s2<0 then s2=0 end
	local l2=l+math.random()*0.2-0.1
	if l2>1 then l2=1 end
	if l2<0 then l2=0 end
	iterate_color(ret,{h1,s,l},{h2,s,l},5)
	iterate_color(ret,{h2,s2,l},{h3,s2,l},5)
	iterate_color(ret,{h3,s2,l},{h4,s2,l2},5)
	--]]
	--[[ complementary
	gen_shades(ret,h1,s,l,0.15,5)
	gen_shades(ret,1-h1,s,0.15,l,5)
	--]]
	--[[ triadic
	gen_shades(ret,h1,s,l,0.2,5)
	gen_shades(ret,math.fmod(h1+0.33,1),s,0.2,l/2,5)
	gen_shades(ret,math.fmod(h1+0.66,1),s,l/2,l,3)
	--]]
	--[[ anologous
	gen_shades(ret,h1,s,0.2,l,3)
	gen_shades(ret,math.fmod(h1+0.05,1),s,0.2,l,3)
	gen_shades(ret,math.fmod(h1+0.1,1),s/2,l,0,3)
	gen_shades(ret,math.fmod(h1+0.15,1),s/2,l,0,3)
	gen_shades(ret,math.fmod(h1+0.2,1),s,l,0,3)
	--]]
	--TODO: compound
	--
end
function palette_chooser()
	if imgui.RadioButton("Show palette",palette.show) then
		palette.show=not palette.show
	end
	imgui.SameLine()
	if imgui.Button("Randomize") then
		gen_palette()
	end
	
	

	if palette.colors[palette.current]==nil then
		palette.current=1
	end
	palette.current=palette.current or 1
	
	if palette.show then
		if #palette.colors>0 then
			_,palette.current=imgui.SliderInt("Color id",palette.current,1,#palette.colors)
		end
		imgui.SameLine()
		if #palette.colors<max_palette_size then
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
	else
		img_buf:read_frame()
		local w=img_buf.w
		local h=img_buf.h
		local tile_image=make_image_buffer(w*tile_count,h*tile_count)
		for x=0,(w-1)*tile_count do
		for y=0,(h-1)*tile_count do
			local tx,ty=coord_mapping(x-w*tile_count/2+w/2,y-h*tile_count/2+h/2)
			tx=math.floor(tx)
			ty=math.floor(ty)
			if tx>=0 and math.floor(tx)<w and ty>=0 and math.floor(ty)<h then
				tile_image:set(x,y,img_buf:get(tx,ty))
			end
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
	if imgui.Button("Gen function") then
		local nx="local nx="..random_math_series(4,0,3).."\n    "
		local ny="local ny="..random_math_series(4,0,3).."\n"
		print("--[[\n"..nx..ny.."\n--]]")
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
	if imgui.Button("Tick") then
		do_samples=true
	end
	imgui.End()
end
function update( )
	gui()
	if config.render then
		update_real()
		--update_func()
	else
		update_func_shader()
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

local func_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec4 palette[15];
uniform int palette_size;

uniform vec2 params;
uniform vec2 center;
uniform float scale;
uniform float move_dist;

vec4 mix_palette2(float value )
{
	if (palette_size==0)
		return vec4(0);
	value=clamp(value,0,1);
	float tg=value*(float(palette_size)-1); //[0,1]-->[0,#colors]
	float tl=floor(tg);

	float t=tg-tl;
	vec4 c1=palette[int(tl)];
	int hidx=min(int(ceil(tg)),palette_size-1);
	vec4 c2=palette[hidx];
	return mix(c1,c2,t);
}

vec2 fun(vec2 pos)
{
	float v0=params.x;
	float v1=params.y;

	float x_1=pos.x;
	float x_2=pos.x*pos.x/2;
	float x_3=pos.x*pos.x*pos.x/6;

	float y_1=pos.y;
	float y_2=pos.y*pos.y/2;
	float y_3=pos.y*pos.y*pos.y/6;

	float nx=sqrt(abs(cos(x_1-y_2)*v0+sin(y_2-x_3)*v1))-sqrt(abs(sin(x_1-y_2)*v1+cos(y_2-x_3)*v0));
	float ny=sin(y_1-x_2)*v1+cos(x_2-y_3)*v0;

	vec2 ret=vec2(nx,ny);
	float r=length(ret);
	if (r<0.0001) r=1;
	float d=move_dist/r;
	return ret*d;
}

void main(){

	vec2 tpos=(pos.xy*0.5)*scale+center*vec2(1,-1);
	vec2 np=fun(tpos);

	float nv=length(np-tpos);
	nv=mod(nv,1);
	color=mix_palette2(nv);
}
]==]
function gl_mod( x,y )
	return x-y*math.floor(x/y)
end
function update_func(  )
	local s=STATE.size
	local hw=s[1]/2
	local hh=s[2]/2
	local iscale=1/config.scale
	local scale=config.scale

	local v0=config.v0
	local v1=config.v1
	local v2=config.v2
	local v3=config.v3

	local cx=config.cx
	local cy=config.cy

	-- [==[
	local vst=visits
	local max=0
	local min=999999999999
	local avg=0
	for x=0,s[1]-1 do
	for y=0,s[2]-1 do
		--[[
		local tx=((x-cx)*iscale+0.5)*s[1]
		local ty=((y-cy)*iscale+0.5)*s[2]
		--]]
		local tx=(x/s[1]-0.5)*scale+cx
		local ty=(y/s[2]-0.5)*scale+cy
		local nx,ny=step_iter(tx,ty,v0,v1,v2,v3)
		local dx=nx-tx
		local dy=ny-ty
		local dist=math.sqrt(dx*dx+dy*dy)
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
		mix_palette(pix_out,gl_mod(dist,1))
		--pix_out={0,0,0,1}
		img_buf:set(x,y,pix_out)
	end
	end
	--]==]
	--[==[
	local pix_out=pixel()
	for x=0,s[1]-1 do
	for y=0,s[2]-1 do
		local tx=(x/s[1]-0.5)*scale+cx
		local ty=(y/s[2]-0.5)*scale+cy
		mix_palette(pix_out,gl_mod(tx,1))
		img_buf:set(x,y,pix_out)
	end
	end
	--]==]
	img_buf:present()
end
function update_func_shader( ... )
	__no_redraw()
	__clear()
	func_shader:use()
	set_shader_palette(func_shader)
	func_shader:set_i("palette_size",#palette.colors)
	func_shader:set("params",config.v0,config.v1)
	func_shader:set("center",config.cx,config.cy)
	func_shader:set("scale",config.scale)
	func_shader:set("move_dist",config.move_dist)
	func_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
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
	for i=0,8 do
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
function simple_smooth( x,y,w )
	local s=size
	local tx,ty=coord_mapping(x,y)

	local lx=math.floor(tx)
	local ly=math.floor(ty)
	local fx=tx-lx
	local fy=ty-ly
	tx=math.floor(tx+0.5)
	ty=math.floor(ty+0.5)
	if tx>=0 and tx<s[1] and ty>=0 and ty<s[2] then
		add_visit(tx,ty,w*(1-fx)*(1-fy))
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

		--local tx=mod(x0+dx*r,size[1])
		--local ty=mod(y0+dy*r,size[2])

		--smooth_visit(tx,ty,1)
		--simple_visit(tx,ty,1)
		simple_smooth(x0+dx*r,y0+dy*r,1)
	end
end
function rot_coord( x,y,angle )
	local c=math.cos(angle)
	local s=math.sin(angle)
	--[[
		| c -s |
		| s  c |
	--]]
	return x*c-y*s,x*s+y*c
end
function reflect_coord( x,y,angle )
	local c=math.cos(2*angle)
	local s=math.sin(2*angle)
	--[[
		| c  s |
		| s -c |
	--]]
	return x*c+y*s,x*s-y*c
end
function Barycentric(px,py, ax,ay,bx,by,cx,cy)
	local v0x=bx-ax
	local v0y=by-ay

	local v1x=cx-ax
	local v1y=cy-ay

	local v2x=px-ax
	local v2y=py-ay
    
    local d00 = v0x*v0x+v0y*v0y
    local d01 = v0x*v1x+v0y*v1y
    local d11 = v1x*v1x+v1y*v1y
    local d20 = v2x*v0x+v2y*v0y
    local d21 = v2x*v1x+v2y*v1y
    
    local denom = d00 * d11 - d01 * d01
    local retx=(d11 * d20 - d01 * d21) / denom
    local rety=(d00 * d21 - d01 * d20) / denom
    local retz= 1.0 - retx - rety
    return retx,rety,retz
end
function to_barycentric(px,py)

	local angle_offset=0;
	local a_d=math.pi*2/3.0

	local p1x=math.cos(angle_offset)
	local p1y=math.sin(angle_offset)

	local p2x=math.cos(a_d+angle_offset)
	local p2y=math.sin(a_d+angle_offset)

	local p3x=math.cos(-a_d+angle_offset)
	local p3y=math.sin(-a_d+angle_offset)

	return Barycentric(px,py,p1x,p1y,p2x,p2y,p3x,p3y)
end
function from_barycentric(px,py)

	local angle_offset=0;

	local a_d=math.pi*2/3.0

	local p1x=math.cos(angle_offset)
	local p1y=math.sin(angle_offset)

	local p2x=math.cos(a_d+angle_offset)
	local p2y=math.sin(a_d+angle_offset)

	local p3x=math.cos(-a_d+angle_offset)
	local p3y=math.sin(-a_d+angle_offset)

	local rx=p1x*px+p2x*py+p3x*(1-px-py)
	local ry=p1y*px+p2y*py+p3y*(1-px-py)
	return rx,ry
end
function from_barycentric(px,py,pz)

	local angle_offset=0;
	local a_d=math.pi*2/3.0

	local p1x=math.cos(angle_offset)
	local p1y=math.sin(angle_offset)

	local p2x=math.cos(a_d+angle_offset)
	local p2y=math.sin(a_d+angle_offset)

	local p3x=math.cos(-a_d+angle_offset)
	local p3y=math.sin(-a_d+angle_offset)

	local rx=p1x*px+p2x*py+p3x*pz
	local ry=p1y*px+p2y*py+p3y*pz
	return rx,ry
end
function mod_reflect( a,max )
	local ad=math.floor(a/max)
	a=mod(a,max)
	if ad%2==1 then
		a=max-a
	end
	return a
end
function to_hex_coord( x,y )
	local size=300
	local q=(math.sqrt(3)/3*x-(1/3)*y)/size
	local r=((2/3)*y)/size
	return q,r
end
function from_hex_coord( q,r )
	local size=300
	local x=(math.sqrt(3)*q+(math.sqrt(3)/2)*r)*size
	local r=((3/2)*r)*size
	return x,r
end
function round( x )
	return math.floor(x+0.5)
end
function axial_to_cube( q,r )
	return q,-q-r,r
end
function cube_to_axial(x,y,z )
	return x,z
end
function cube_round( x,y,z )
	local rx = round(x)
    local ry = round(y)
    local rz = round(z)

    local x_diff = math.abs(rx - x)
    local y_diff = math.abs(ry - y)
    local z_diff = math.abs(rz - z)

    if x_diff > y_diff and x_diff > z_diff then
        rx = -ry-rz
    elseif y_diff > z_diff then
        ry = -rx-rz
    else
        rz = -rx-ry
    end

    return rx, ry, rz
end

function coord_mapping( tx,ty )
	local s=STATE.size
	local dist=s[1]
	local angle=(2*math.pi)/5

	local sx=s[1]/2
	local sy=s[2]/2
	local cx,cy=tx-sx,ty-sy
	--return tx,ty
	--return mod(tx,s[1]),mod(ty,s[2])
	--[[
	local a,b,c=to_barycentric(cx,cy)
	--a=(a-math.floor(a))*1000
	--b=(b-math.floor(b))*1000
	--c=(c-math.floor(c))*1000
	cx,cy=from_barycentric( a,b,c )
	return cx+sx,cy+sy
	--]]
	-- [[
	local r=math.sqrt(cx*cx+cy*cy)
	local a=math.atan2(cy,cx)

	r=mod_reflect(r,dist-1)
	r=r/(dist-1)
	r=r*s[1]

	a=mod(a,angle)
	a=a/angle
	a=a*s[2]

	return r,a
	--]]
	--https://www.redblobgames.com/grids/hexagons/#pixel-to-hex
	--[=[
	cx,cy=to_hex_coord(cx,cy)
	local rx,ry,rz=axial_to_cube(cx,cy)
	local rrx,rry,rrz=cube_round(rx,ry,rz)
	rx=rx-rrx
	ry=ry-rry
	rz=rz-rrz
	--]]
	--[[if rrx%2==1 and rrz%2==1 then
		rz=-rz
		rx=-rx
	end]]
	--print(max_rz,min_rz,math.sqrt(3))
	cx,cy=cube_to_axial(rx,ry,rz)
	cx,cy=from_hex_coord(cx,cy)
	return cx+sx,cy+sy
	--[=[
	local angle=2*math.pi/3
	

	local ax,ay=math.cos(angle)*dist,math.sin(angle)*dist
	local bx,by=math.cos(2*angle)*dist,math.sin(2*angle)*dist
	local cx,cy=math.cos(3*angle)*dist,math.sin(3*angle)*dist
	local v,w,u=barycentric(tx-sx,ty-sy,ax,ay,bx,by,cx,cy)
	--print(tx,ty,v,w,u)
	if v<0 then
		w=mod(w,1)
		u=mod(u,1)
		v=mod(1-w-u,1)
	elseif u<0 then
		v=mod(v,1)
		w=mod(w,1)
		u=mod(1-v-w,1)
	else
		v=mod(v,1)
		u=mod(u,1)
		w=mod(1-v-u,1)
	end

	local nx,ny=from_barycentric(v,w,u,ax,ay,bx,by,cx,cy)
	return nx+sx,ny+sy
	--]=]
	--[=[
	local nx = tx
	local ny = ty
	nx=nx-s[1]/2
	ny=ny-s[2]/2
	local dist=200
	local angle=math.pi/6
	local dx=math.cos(angle)*dist
	local dy=math.sin(angle)*dist
	nx=nx+dx
	ny=ny+dy
	--ny=ny-s[2]/2
	nx,ny=rot_coord(nx,ny,angle)
	nx=mod(nx,dist)
	--nx,ny=rot_coord(nx,ny,-angle)
	nx=nx-dx
	ny=ny-dy

	

	--[[dx=math.cos(-angle)*dist
	dy=math.sin(-angle)*dist
	nx=nx+dx
	ny=ny+dy
	nx,ny=rot_coord(nx,ny,-angle)
	nx=mod(nx,dist)
	nx,ny=rot_coord(nx,ny,angle)
	nx=nx-dx
	ny=ny-dy

	dx=math.cos(2*angle)*dist
	dy=math.sin(2*angle)*dist
	nx=nx+dx
	ny=ny+dy
	nx,ny=rot_coord(nx,ny,2*angle)
	nx=mod(nx,dist)
	nx,ny=rot_coord(nx,ny,-2*angle)
	nx=nx-dx
	ny=ny-dy
	]]
	nx=nx+s[1]/2
	ny=ny+s[2]/2
	
	--ny=ny+s[2]/2
	return nx,ny
	--]=]
	--[=[
	
	local cx=tx-s[1]/2
	local cy=ty-s[2]/2
	local rmax=math.min(s[1],s[2])/2
	

	
	--r=math.fmod(r,math.min(s[1],s[2])/2)
	
	local num=6
	local top=math.cos(math.pi/num)
	local bottom=math.cos(a-(math.pi*2/num)*math.floor((num*a+math.pi)/(math.pi*2)))

	local dr=top/bottom
	dr=(dr*rmax)
	local d=math.floor(r/dr)
	a=a-(math.pi*2/num)*d
	r=math.fmod(r,dr)
	if d%2==1 then
		r=dr-r
	end
	local nx=math.cos(a)*r+s[1]/2
	local ny=math.sin(a)*r+s[2]/2
	return nx,ny
	--]=]
	--[=[
	local rx,ry
	if tx>s[1]/2 then
		rx,ry=rot_coord(tx-s[1]/2,ty-s[2]/2,math.pi/4)
		rx=rx+s[1]/2
		ry=ry+s[2]/2
	else
		rx,ry=tx,ty
	end
	return math.fmod(rx,s[1]),math.fmod(ry,s[2])
	--]=]
	--[[ PENTAGON
	local k = {0.809016994,0.587785252,0.726542528};
	ty=-ty;
	tx=math.abs(tx)
	local ntx=tx
	local nty=ty
	local v=2*math.min((-k[1]*ntx+k[2]*nty),0)
	ntx=ntx-v*(-k[1])
	nty=nty-v*(k[2])
	local v2=2*math.min((k[1]*ntx+k[2]*nty),0)
	ntx=ntx-v*(k[1])
	nty=nty-v*(k[2])
	return ntx,nty
	--[=[

	void t_rot(inout vec2 st,float angle)
	{
		float c=cos(angle);
		float s=sin(angle);
		mat2 m=mat2(c,-s,s,c);
		st*=m;
	}
	void t_ref(inout vec2 st,float angle)
	{
		float c=cos(2*angle);
		float s=sin(2*angle);
		mat2 m=mat2(c,s,s,-c);
		st*=m;
	}

    p -= 2.0*min(dot(vec2(-k.x,k.y),p),0.0)*vec2(-k.x,k.y);
    p -= 2.0*min(dot(vec2( k.x,k.y),p),0.0)*vec2( k.x,k.y);
    --]=]
	--]]
	--return tx,ty
	--return mod(tx,s[1]),mod(ty,s[2])
	--[[
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
	--]]
	--[[
	local div=math.floor(tx/s[1]+ty/s[2])
	tx=mod(tx,s[1])
	ty=mod(ty,s[2])
	if div>0 then
		return s[1]-ty-1,tx
	end
	return tx,ty
	--]]
end
function rand_circl(  )
	local a=math.random()*math.pi*2
	local r=math.sqrt(math.random())*config.gen_radius
	return math.cos(a)*r,math.sin(a)*r
end
function simple_visit( tx,ty ,w)
	local s=STATE.size
	tx,ty=coord_mapping(tx,ty)
	tx=math.floor(tx+0.5)
	ty=math.floor(ty+0.5)
	if tx>=0 and tx<s[1] and ty>=0 and ty<s[2] then
		add_visit(tx,ty,w)
	end
end
function gauss_smooth_visit( tx,ty,w,n )
	local s=STATE.size
	for i=1,n do
		local gx=gaussian(0,1)
		local gy=gaussian(0,1)
		local w2=math.exp(-(gx*gx+gy*gy))
		simple_visit(tx+gx,ty+gy,w*w2)
	end
end
function circle_visit( tx,ty,w,r )
	for y=1,r-1 do
		local xs=math.sqrt(r*r-y*y)
		simple_visit(tx+xs,ty+y,w);
		simple_visit(tx-xs,ty+y,w);
		simple_visit(tx+xs,ty-y,w);
		simple_visit(tx-xs,ty-y,w);
	end
end
function cross_visit( tx,ty,w )
	simple_visit(tx+1,ty+1,w*0.25);
	simple_visit(tx-1,ty+1,w*0.2);
	simple_visit(tx+1,ty-1,w*0.1);
	simple_visit(tx-1,ty-1,w*0.133);
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
	local v2=config.v2
	local v3=config.v3
	local cx=config.cx
	local cy=config.cy


	local ad=config.arg_disp
	local gen_radius=config.gen_radius
	for i=1,config.ticking do
		--TODO: generate IN screen
		--[[local x = math.random()-0.5
		local y = math.random()-0.5]]
		--[[
		local x=math.random()*gen_radius-gen_radius/2
		local y=math.random()*gen_radius-gen_radius/2
		--]]
		local x=gaussian(0,gen_radius)
		local y=gaussian(0,gen_radius)
		local sx,sy=x,y
		local w=math.exp(-(x*x+y*y))
		--local w=1
		--local x,y=rand_circl()
		local lx=x
		local ly=y
		x=0
		y=0
		local escape_dist_sqr=1.2
		local escaped=false
		-- [[
		for i=1,config.ticking2 do
			x,y=step_iter(x,y,v0,v1,v2,v3,sx,sy)
			if x*x+y*y >escape_dist_sqr then
				escaped=true
				break
			end
		end
		--]]
		if escaped then
			for i=1,config.ticking2 do
				x,y=step_iter(x,y,v0,v1,v2,v3,sx,sy)

				local tx=((x-cx)*iscale+0.5)*s[1]
				local ty=((y-cy)*iscale+0.5)*s[2]
				--[==[
				if x*x+y*y>1e10 then
					break
				end
				--]==]
				--[[ LINE-ISH VISITING
				
				if i~=1 then
					--line_visit(lx,ly,tx,ty) --VERY SLOW!!
					rand_line_visit(lx,ly,tx,ty)
				end
				lx=tx
				ly=ty
				--]]
				--[[ TILING FRACTAL
				--smooth_visit(tx,ty,w)
				--]]
				simple_visit(tx,ty,w)
				--simple_smooth(tx,ty,w)
				--gauss_smooth_visit(tx,ty,w,5)
				--cross_visit(tx,ty,w)
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
	end



	draw_visits()
end