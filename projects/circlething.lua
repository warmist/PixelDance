--https://www.reddit.com/r/generative/comments/e12s8n/community_exhibition/
require "common"
local win_w=2560
local win_h=1440

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
tex_out =tex_out or textures.Make()
function update_image_buffer(force)
	local size=STATE.size
	if force or image_buffer==nil or image_buffer.w~=size[1] or image_buffer.h~=size[2] then
		print("new buffer:",size[1],size[2])
		win_w,win_h=size[1],size[2]
		tex_out=textures.Make()
		tex_out:use(0)
		image_buffer=make_float_buffer(size[1],size[2])
		image_buffer:write_texture(tex_out)
	end
end
config=make_config({
	{"draw",true,type="boolean"},
	{"a",{0.5,0.5,0.5},type="color"},
	{"b",{0.5,0.5,0.5},type="color"},
	{"c",{1.,1.,1.},type="color"},
	{"d",{0,0.1,0.2},type="color"},
	{"gamma",0.6,type="float",min=0.01,max=5},
	{"gain",1,type="float",min=-5,max=5},
	{"draw_cols",false,type="boolean"},
},config)
update_image_buffer()
function resize( w,h )
	print("resize",w,h)
	update_image_buffer()
end
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
uniform float aspect;
float sh_circle(in vec2 st,in float rad,in float fw)
{
	return 1-smoothstep(rad-fw*0.75,rad+fw*0.75,dot(st,st)*4);
}
float sh_ring(in vec2 st,in float rad1,in float rad2,in float fw)
{
	return sh_circle(st,rad1,fw)-sh_circle(st,rad2,fw);
}

void main(){
	//float fw=0.002;
	//float c_w=0.93;
	float c=0;
	float increment=0.00005;
	vec2 npos=pos.xy;
    for(int i=0;i<100;i++)
    {
    	vec2 p=(texelFetch(c_pos,ivec2(i,0),0).rg-npos)*vec2(aspect,1);

    	float r=texelFetch(c_sizes,ivec2(i,0),0).r;

    	//r*=r;
    	//float lsq=dot(p,p);
    	//c+=(1-smoothstep(r-fw*0.75,r+fw*0.75,dot(p,p)*4));
    	//c+=sh_ring(p,r,r*c_w,fw*r)*increment;
    	///*
    	float r2=r*0.02;
    	float d=abs(length(p)-r)-r2;
    	float distanceChange = fwidth(d) * 0.5;
    	float antialiasedCutoff = smoothstep(distanceChange, -distanceChange, d);
    	//float antialiasedCutoff=step(d,0);
    	c+=antialiasedCutoff*increment;
    	//*/
    }
    //color=vec4(max(pixel.x,pixel_c.x),pixel_c.y,pixel_c.z,1);
    c-=increment;
    c=clamp(c,0,increment*100);
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
uniform vec3 c_a;
uniform vec3 c_b;
uniform vec3 c_c;
uniform vec3 c_d;
uniform float gamma;
uniform float gain;
uniform float draw_cols;
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
vec3 plt(in float t)
{
	return palette(t,c_a,c_b,c_c,c_d);
}
float apply_gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
    float v=log(texture(image,normed).r+1);
    //float v=texture(image,normed).r;
    v-=rescale.x;
    v/=(rescale.y-rescale.x);
    v=apply_gain(v,gain);
    v=pow(v,gamma);
    vec3 pixel=plt(v);
    if(normed.y>0.9 && draw_cols>0)
    	color=vec4(plt(normed.x),1);
    else
    	color=vec4(pixel,1);
}
]==]
function find_min_max( txt )
	image_buffer:read_texture(txt)
	local vmin=math.huge
	local vmax=-math.huge
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
    draw_shader:set("gamma",config.gamma)
    draw_shader:set("gain",config.gain)
    draw_shader:set("c_a",config.a[1],config.a[2],config.a[3])
    draw_shader:set("c_b",config.b[1],config.b[2],config.b[3])
    draw_shader:set("c_c",config.c[1],config.c[2],config.c[3])
    draw_shader:set("c_d",config.d[1],config.d[2],config.d[3])
    if config.draw_cols then
    	draw_shader:set("draw_cols",1)
    else
    	draw_shader:set("draw_cols",0)
    end
    --draw_shader:set("rescale",mm,mx)
    draw_shader:draw_quad()

    return tex_out
end
function mrand( min,max )
	return math.random()*(max-min)+min
end
function reset_circle( i )
	local max_w=2/20
	local min_w=0.05
	local c_size=mrand(max_w,min_w)
	local x=mrand(-1-c_size,1+c_size)
	local y=mrand(-1-c_size,1+c_size)
	circle_pos:set(i,0,{x,y})
	circle_sizes:set(i,0,c_size)
	local r=--[[math.random()*0.00125+]]0.001
	local a=math.random()*math.pi*2
	circle_speed:set(i,0,{math.cos(a)*r,math.sin(a)*r})
end
function circle_tick(  )
	for i=0,count_circles-1 do
		local p=circle_pos:get(i,0)
		local s=circle_speed:get(i,0)
		local r=circle_sizes:get(i,0)
		p.r=p.r+s.r
		p.g=p.g+s.g
		if p.r+r<-1 or p.r-r>1 or p.g+r<-1 or p.g-r>1 then
			reset_circle(i)
		end
	end
	write_mat()
	add_shader:use()
	add_shader:blend_add()
	tex_sizes:use(0)
	add_shader:set_i("c_sizes",0)
	add_shader:set("aspect",win_w/win_h)
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
function save_img()
    img_buf_save=make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    img_buf_save:read_frame()
    img_buf_save:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Circles")
	local s=STATE.size
	draw_config(config)
	if imgui.Button("Clear image") then
		circle_init()
		update_image_buffer(true)
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
	--for i=1,5 do
		circle_tick()
	--end
	if config.draw then
		draw()
	end
	if need_save then
		save_img()
		need_save=false
	end
end