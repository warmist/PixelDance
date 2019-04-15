--[[
	* mass transfer and crystallization
	* block diffusion by other crystals
--]]
require "common"
local win_w=768
local win_h=768

__set_window_size(win_w,win_h)
local oversample=0.5
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local size=STATE.size

img_buf=img_buf or make_image_buffer(map_w,map_h)
material=material or make_float_buffer(map_w,map_h)
function resize( w,h )
	img_buf=make_image_buffer(map_w,map_h)
	material=make_float_buffer(map_w,map_h)
end

local size=STATE.size

tick=tick or 0
config=make_config({

	{"diffuse_steps",1,min=0,max=10,type="int"},
	{"diffuse",0.5,type="float"},
	{"decay",0.99,type="float"},
	{"simulate",true,type="boolean"},
	{"add_mat",true,type="boolean"},
},config)
image_no=image_no or 0

local decay_diffuse_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform float diffuse;
uniform float decay;

uniform sampler2D tex_main;
uniform sampler2D tex_mask;
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
function diffuse_and_decay( tex,tex_out,w,h,diffuse,decay,steps )
	steps=steps or 1
	--[[
	TODO:
		* add mask to block mass transfer
	--]]
	decay_diffuse_shader:use()
	for i=1,steps do
	    tex:use(0)
	    decay_diffuse_shader:set_i("tex_main",0)
	    decay_diffuse_shader:set("decay",decay)
	    decay_diffuse_shader:set("diffuse",diffuse)
	    if not tex_out:render_to(w,h) then
			error("failed to set framebuffer up")
		end
	    decay_diffuse_shader:draw_quad()
	    --swap textures
	    local c = tex
    	tex=tex_out
    	tex_out=c
	end
    __render_to_window()
    return tex_out
end


local need_save
local mat_tex1 = textures.Make()
local mat_tex2 = textures.Make()
function write_mat()
	mat_tex1:use(0)
	material:write_texture(mat_tex1)
	mat_tex2:use(0)
	material:write_texture(mat_tex2)
end
write_mat()
local img_tex1=textures.Make()
local img_tex2=textures.Make()
function write_img(  )
	img_tex1:use(0)
	img_buf:write_texture(img_tex1)
	img_tex2:use(0)
	img_buf:write_texture(img_tex2)
end
write_img()
function save_img()
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	image_no=image_no+1
end
local draw_shader=shaders.Make(
[==[
#version 330
#line 118
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;

void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    vec4 pixel=texture(tex_main,normed);
    color=vec4(pixel.x,0,0,1);
}
]==])
function draw(  )
	draw_shader:use()
    mat_tex1:use(0)
	draw_shader:set_i("tex_main",0)
	draw_shader:draw_quad()
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Crystals")
	local s=STATE.size
	draw_config(config)

	if imgui.Button("Clear image") then
		--clear_screen(true)
		for j=0,map_h-1 do
			for i=0,map_w-1 do
				material:set(i,j,0)
			end
		end
		write_mat()
	end
	imgui.End()
	if config.simulate then
		if config.add_mat then
			mat_tex1:use(0)
			material:read_texture(mat_tex1)
			for i=0,map_w-1 do
				material:set(i,math.floor(map_h/2),1+material:get(i,math.floor(map_h/2)))
			end
			material:write_texture(mat_tex1)
		end
		diffuse_and_decay(mat_tex1,mat_tex2,map_w,map_h,config.diffuse,config.decay,config.diffuse_steps)
		if(config.diffuse_steps%2==1) then
			local c=mat_tex1
			mat_tex1=mat_tex2
			mat_tex2=c
	    end
	end
	draw()

end