--https://www.reddit.com/r/generative/comments/e12s8n/community_exhibition/
require "common"
local win_w=1024
local win_h=1024

__set_window_size(win_w,win_h)
local map_w=math.floor(win_w)
local map_h=math.floor(win_h)

local size=STATE.size

local count_circles=100
circle_sizes=circle_sizes or make_float_buffer(count_circles,1)
circle_pos=circle_pos or make_flt_half_buffer(count_circles,1)
circle_speed=circle_speed or make_flt_half_buffer(count_circles,1)


local tex_sizes = textures.Make()
local tex_pos = textures.Make()
local tex_out = textures.Make()

tex_out:use(0)
image_buffer=image_buffer or make_float_buffer(win_w,win_h)
image_buffer:write_texture(tex_out)
function write_mat()
	tex_sizes:use(0)
	circle_sizes:write_texture(tex_sizes)
	tex_pos:use(0)
	circle_pos:write_texture(tex_pos)
end

local add_shader=shaders.Make[==[
#version 330
#line 23
out vec4 color;
in vec3 pos;

uniform sampler2D c_sizes;
uniform sampler2D c_pos;

float sh_circle(in vec2 st,in float rad,in float fw)
{
	return 1-smoothstep(rad-fw*0.75,rad+fw*0.75,dot(st,st)*4);
}
float sh_ring(in vec2 st,in float rad1,in float rad2,in float fw)
{
	return sh_circle(st,rad1,fw)-sh_circle(st,rad2,fw);
}

void main(){
	float fw=0.02;
	float c_w=0.93;
	float c=0;
	float step=0.005;

    for(int i=0;i<100;i++)
    {
    	vec2 p=texelFetch(c_pos,ivec2(i,0),0).rg-pos.xy;
    	float r=texelFetch(c_sizes,ivec2(i,0),0).r;
    	//r*=r;
    	float lsq=dot(p,p);
    	//c+=(1-smoothstep(r-fw*0.75,r+fw*0.75,dot(p,p)*4));
    	c+=sh_ring(p,r,r*c_w,fw*r)*step;
    }
    //color=vec4(max(pixel.x,pixel_c.x),pixel_c.y,pixel_c.z,1);
    c-=step;
    c=clamp(c,0,1);
    color=vec4(c,c,c,1);
}
]==]
local draw_shader=shaders.Make[==[
#version 330
#line 70
out vec4 color;
in vec3 pos;

uniform sampler2D image;
uniform vec2 rescale;

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
    vec3 pixel=vec3(log(texture(image,normed).r+1));

    pixel-=rescale.x;
    pixel/=(rescale.y-rescale.x);

    color=vec4(pixel,1);
}
]==]
function find_min_max( txt )
	image_buffer:read_texture(txt)
	local vmin=0
	local vmax=0
	for x=0,image_buffer.w-1 do
		for y=0,image_buffer.h-1 do
			local v=image_buffer:get(x,y)
			if v>vmax then vmax=v end
			if v<vmin then vmin=v end
		end
	end
	return vmin,vmax
end
function draw(  )
	__render_to_window()
    draw_shader:use()
    draw_shader:blend_default()
    tex_out:use(0)
    local mm,mx=find_min_max(tex_out)
    --print(mm,mx)
    draw_shader:set_i("image",0)
    draw_shader:set("rescale",math.log(mm+1),math.log(mx+1))
    draw_shader:draw_quad()

    return tex_out
end
function reset_circle( i )
	local x=math.random()*2-1;
	local y=math.random()*2-1;
	local max_w=2/20
	local min_w=0.0005
	circle_pos:set(i,0,{x,y})
	circle_sizes:set(i,0,math.random()*(max_w-min_w)+min_w)
	local sx=(math.random()*2-1)*0.001;
	local sy=(math.random()*2-1)*0.001;
	circle_speed:set(i,0,{sx,sy})
end
function circle_tick(  )
	for i=0,count_circles-1 do
		local p=circle_pos:get(i,0)
		local s=circle_speed:get(i,0)
		p.r=p.r+s.r
		p.g=p.g+s.g
		if p.r<-1 or p.r>1 or p.g<-1 or p.g>1 then
			reset_circle(i)
		end
	end
	write_mat()
	add_shader:use()
	add_shader:blend_add()
	tex_sizes:use(0)
	add_shader:set_i("c_sizes",0)
	tex_pos:use(1)
	tex_out:use(2)
	add_shader:set_i("c_pos",1)
	add_shader:draw_quad()

	if not tex_out:render_to(win_w,win_h) then
		error("failed to set framebuffer up")
	end
    add_shader:draw_quad()
end
function circle_init(  )
	for i=0,count_circles-1 do
		reset_circle(i)
	end
	write_mat()
end
circle_init()
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Circles")
	local s=STATE.size

	if imgui.Button("Clear image") then
		circle_init()
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
	for i=1,10 do
		circle_tick()
	end
	draw()
	if need_save then
		save_img()
		need_save=false
	end
end