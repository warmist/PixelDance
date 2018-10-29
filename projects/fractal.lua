--simple mandelbrot with stuff from http://iquilezles.org/www/articles/distancefractals/distancefractals.htm (probably wrong though :|)
require "common"
local size=STATE.size
local max_size=math.min(size[1],size[2])/2

img_buf=img_buf or make_image_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
end

tick=tick or 0
config=make_config({
	{"color",{0.5,0,0,1},type="color"},
	{"back",{0.0,0,0,1},type="color"},
	{"ticking",100,type="float",min=1,max=10000},
	{"ticking2",100,type="int",min=1,max=500},
	{"scale",10,type="float",min=0.1,max=10},
	{"cx",-0.05,type="float",min=-5,max=5},
	{"cy",.6805,type="float",min=-5,max=5},
	{"ss",1,type="int",min=1,max=8},
	{"ss_dist",0,type="float",min=0,max=0.2},
},config)
image_no=image_no or 0

local draw_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec4 fore;
uniform vec4 back;
uniform int max_count;
uniform vec2 offset;
uniform float scale;
int iterate(vec2 cpos, float dist)
{
	vec2 pos=vec2(0,0);
	for(int i=0;i<max_count;i++)
	{
		vec2 npos;
		npos.x=pos.x*pos.x+cpos.x-pos.y*pos.y;
		npos.y=2*pos.x*pos.y+cpos.y;
		float d=length(npos);
		if(d>dist)
			return i;
		pos=npos;
	}
}
float calc_distance(vec2 cpos,out float v)
{
	vec2 z=vec2(0,0);
	vec2 dz=vec2(0,0);

	float m2;
	v=1;
	for(int i=0;i<1024;i++)
	{
		vec2 ndz;
		ndz.x=2*(z.x*dz.x-z.y*dz.y)+1;
		ndz.y=2*(z.x*dz.y+z.y*dz.x);
		vec2 nz;
		nz.x=z.x*z.x+cpos.x-z.y*z.y;
		nz.y=2*z.x*z.y+cpos.y;
		z=nz;
		dz=ndz;
		m2=dot(z,z);
		if(m2>1e10)
		{
			v=0;
			break;
		}
	}
	return sqrt(m2/dot(dz,dz))*0.5*log(m2);
}
void main(){
	vec2 normed=((pos.xy)/2)/scale+offset;
	//int p=iterate(normed,1000000);
	float v;
	float p=calc_distance(normed,v);
	if(v>0.5)p=0;
	//float t=log(float(p)+1)/log(float(max_count)+1);
	//float t=float(p)/max_count;
	float zoo = pow( 0.5, 13.0*scale );
	p=clamp(pow(4*p/zoo,0.2),0,1);
	color=mix(fore,back,p);
}
]==]
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
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function map_to_screen( x,y )
	local s=STATE.size
	return (x-s[1]/2)/config.scale+config.cx,(y-s[2]/2)/config.scale+config.cy
end
function update(  )
	__no_redraw()
	__clear()
	local scale=config.scale
	local cx,cy=config.cx,config.cy
	local c,x,y= is_mouse_down()
	if c then
		--mouse to screen
		x=(x/size[1]-0.5)*2
		y=(-y/size[2]+0.5)*2
		--screen to world
		x=(x-cx)/scale
		y=(y-cy)/scale

		print(x,y)
		--now set that world pos so that screen center is on it
		config.cx=(-x)*scale
		config.cy=(-y)*scale
		need_clear=true
	end
	if __mouse.wheel~=0 then
		local pfact=math.exp(__mouse.wheel/10)
		config.scale=config.scale*pfact
		--config.cx=config.cx*pfact
		--config.cy=config.cy*pfact
		need_clear=true
	end

	imgui.Begin("Fractal")
	local s=STATE.size
	draw_config(config)
	local c_u8=img_buf:pixel{config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	local c_back=img_buf:pixel{config.back[1]*255,config.back[2]*255,config.back[3]*255,config.back[4]*255}
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
	local col_out=img_buf:pixel()
	--[[for i=1,config.ticking do
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
	end]]
	draw_shader:use()
	draw_shader:set("fore",config.color[1],config.color[2],config.color[3],config.color[4])
	draw_shader:set("back",config.back[1],config.back[2],config.back[3],config.back[4])
	draw_shader:set("scale",config.scale)
	draw_shader:set("offset",config.cx,config.cy)
	draw_shader:set_i("max_count",config.ticking2)
	draw_shader:draw_quad()
end