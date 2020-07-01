require "common"
require "colors"
--DO THIS: https://imgur.com/gallery/NrphmDk
--[[
	add some diffusion to the rays (i.e how fluid sims do) thus getting something blurry?
]]
local luv=require "colors_luv"
local bwrite = require "blobwriter"
local bread = require "blobreader"

local size_mult=1
local size=STATE.size
local win_w
local win_h
local aspect_ratio

local accum_buffers=accum_buffers or multi_texture(size[1],size[2],2,FLTA_PIX)

function update_size(  )
	win_w=1280*size_mult
	win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
update_size()

img_buf=make_image_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	accum_buffers:update_size(w,h)
end

shoot_rays=shaders.Make(
[==[
#version 330
#line 37

uniform mat4 view_mat;
uniform vec2 rez;
in vec2 pos;
out vec4 color;
#define MAX_ITER 10
#define M_PI 3.14159
vec2 map(vec3 pos) //returns distance and material
{
	return vec2(length(pos)-1,1);
}
vec2 shoot_ray(vec3 ro,vec3 rd)
{
	float t_min=0.01;
	float tmax=300;
	float t=t_min;
	vec2 hit;
	for(int i=0;i<MAX_ITER;i++)
	{
		hit=map(ro+t*rd);
		if(abs(hit.x)<0.00002 || t>tmax)
		{
			break;
		}
		t+=hit.x;
		//count=i;
	}
	if(t>tmax)
		return vec2(0,0);
	return vec2(t,hit.y);
}

void main(){
	vec3 cur_pos=(vec4(0,0,0,1)*view_mat).xyz;
	vec3 ray_direction=(vec4(0,0,1,0)*view_mat).xyz;
	
	color=vec4(0.4,0,0,1);
}
]==])
function integrate(  )
	shoot_rays:use()
	shoot_rays:set("rez",size[1],size[2])
	shoot_rays:draw_quad()
end
function update(  )
    __clear()
    __no_redraw()
    __render_to_window()
	integrate()
end