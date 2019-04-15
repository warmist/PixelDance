--[[
	* mass transfer and crystalization
	* block diffusion by other crystals
--]]
require "common"
local win_w=768
local win_h=768

__set_window_size(win_w,win_h)
local oversample=0.5
local map_w=(win_w*oversample)
local map_h=(win_h*oversample)

local size=STATE.size

img_buf=img_buf or make_image_buffer(map_w,map_h)
material=material or make_flt_buffer(map_w,map_h)
function resize( w,h )
	img_buf=make_image_buffer(map_w,map_h)
	material=make_flt_buffer(map_w,map_h)
end

local size=STATE.size

tick=tick or 0
config=make_config({
	{"simulate",true,type="boolean"},
},config)
image_no=image_no or 0

local decay_diffuse_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform float diffuse;
uniform float decay;

uniform sampler2D tex_main;
float sample_around(vec2 pos)
{
	float ret=0;
	ret+=textureOffset(tex_main,pos,ivec2(-1,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,1)).x;

	ret+=textureOffset(tex_main,pos,ivec2(0,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(0,1)).x;
	return ret/8;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float r=sample_around(normed)*diffuse;
	r+=texture(tex_main,normed).x*(1-diffuse);
	r*=decay;
	//r=clamp(r,0,1);
	color=vec4(r,0,0,1);
}
]==]
function diffuse_and_decay( tex,tex_out,w,h,diffuse,decay )
	--[[
	TODO:
		* add step count
		* add mask to block mass transfer
	--]]
	decay_diffuse_shader:use()
    tex:use(0)
    --tex_pixel.t:set(size[1]*oversample,size[2]*oversample,3)
    decay_diffuse_shader:set_i("tex_main",0)
    decay_diffuse_shader:set("decay",decay)
    decay_diffuse_shader:set("diffuse",diffuse)
    if not tex_out:render_to(w,h) then
		error("failed to set framebuffer up")
	end
    decay_diffuse_shader:draw_quad()
    __render_to_window()
end


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


function blend_rgb( c1,c2,t )
	local ret={}
	for i=1,4 do
		ret[i]=(c2[i]-c1[i])*t+c1[i]
	end
	return ret
end
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