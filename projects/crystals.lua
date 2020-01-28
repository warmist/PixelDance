--[[
	* mass transfer and crystallization
	* block diffusion by other crystals
--]]
require "common"
local win_w=1024
local win_h=1024

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
	{"color",{1,1,1,1},type="color"},
	{"material_needed",1,min=0,max=10,type="float"},
	{"material_max",100,min=0,max=100,type="float"},
	{"material_melt",100,min=0,max=100,type="float"},
	{"diffuse_steps",1,min=0,max=10,type="int"},
	--{"cryst_pow",1,min=0.0001,max=5,type="float"},
	--{"diffuse",0.5,type="float"},
	{"decay",0.01,type="floatsci",min=0,max=1,power=10},
	{"add_mat",0.5,type="float"},
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
uniform sampler2D tex_mask;


float sample_around(vec2 pos)
{
	float ret=0;
	float w=0;
	float tw=0;

	#define sample_tex(dx,dy) tw=1-textureOffset(tex_mask,pos,ivec2(dx,dy)).w;\
	w+=tw;\
	ret+=textureOffset(tex_main,pos,ivec2(dx,dy)).x*tw

	/*sample_tex(-1,-1);
	sample_tex(-1,1);
	sample_tex(1,-1);
	sample_tex(1,1);*/

	sample_tex(0,-1);
	sample_tex(-1,0);
	sample_tex(1,0);
	sample_tex(0,1);

	if(w>0)
		return ret/w;
	else
		return 0;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float dist=0.01;
	if(normed.x<dist || normed.x>(1-dist) || normed.y<dist || normed.y>(1-dist))
		{
			color=vec4(0,0,0,1);
			return;
		}
	float r=sample_around(normed)*diffuse;
	r+=texture(tex_main,normed).x*(1-diffuse);
	r*=decay;
	//r=clamp(r,0,1);
	color=vec4(r,0,0,1);
}
]==]
function diffuse_and_decay( tex,tex_out,w,h,diffuse,decay,steps,mask )
	steps=steps or 1
	--[[
	TODO:
		* add mask to block mass transfer
	--]]
	decay_diffuse_shader:use()
	mask:use(1)
	decay_diffuse_shader:set_i("tex_mask",1)
	for i=1,steps do
	    tex:use(0)
	    decay_diffuse_shader:set_i("tex_main",0)
	    decay_diffuse_shader:set("decay",1-decay)
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
function write_img(  )
	img_tex1:use(0)
	img_buf:write_texture(img_tex1)
end
write_img()
--[===[
local img_tex2=textures.Make()
function write_img(  )
	img_tex1:use(0)
	img_buf:write_texture(img_tex1)
	img_tex2:use(0)
	img_buf:write_texture(img_tex2)
end
write_img()
local crystalize_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;
void main()
{

}
--]===]
function count_nn( x,y )
	-- [[
	local dx={1,1,0,-1,-1,-1,0,1}
	local dy={0,-1,-1,-1,0,1,1,1}
	--]]
	--[[
	local dx={1,0,-1,0}
	local dy={0,-1,0,1}
	--]]
	local ret=0
	for i=1,#dx do
		local tx=x+dx[i]
		if tx<0 then tx=map_w-1 end
		if tx>=map_w then tx=0 end
		local ty=y+dy[i]
		if ty<0 then ty=map_h-1 end
		if ty>=map_h then ty=0 end
		local v=img_buf:get(tx,ty)
		if v.a~=0 then
			ret=ret+1
		end
	end
	return ret
end
function crystal_step()
	material:read_texture(mat_tex1)
	local crystal_chances={
		[0]=0.0000001, --0
		0.001,--1
		1,
		0.01,
		0.0001,--4
		0.1,
		0,
		0.000001,
		0.000001,
	}
	local chance_mod=0.05
	for x=0,map_w-1 do
		for y=0,map_h-1 do
			local v=material:get(x,y)
			if v>config.material_needed and v<config.material_max then
				local c=count_nn(x,y)
				--[[local pp=config.cryst_pow
				pp=pp*pp
				local r =1-math.exp(pp/(-c*c))--crystal_chances[c]
				]]
				local r =crystal_chances[c]*chance_mod
				if r>math.random() and v>config.material_needed then
					--material:set(x,y,0)
					material:set(x,y,material:get(x,y)-config.material_needed*1.1)
					local c=config.color
					img_buf:set(x,y,{c[1]*255,c[2]*255,c[3]*255,255})
				end
			end
			if v>=config.material_melt then
				if img_buf:get(x,y).a~=0 then
					material:set(x,y,material:get(x,y)+config.material_needed)
					img_buf:set(x,y,{0,0,0,0})
				end
			end

		end
	end
	write_img()
	write_mat()
end

function save_img()
	if save_buf==nil or save_buf.w~=win_w or save_buf.h~=win_h then
		save_buf=make_image_buffer(win_w,win_h)
	end

	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	save_buf:read_frame()
	save_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
local draw_shader=shaders.Make(
[==[
#version 330
#line 118
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform sampler2D tex_cryst;
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    vec4 pixel=texture(tex_main,normed);
    vec4 pixel_c=texture(tex_cryst,normed);
    //color=vec4(max(pixel.x,pixel_c.x),pixel_c.y,pixel_c.z,1);

    color=vec4(clamp(pixel*(1-pixel_c.a)+pixel_c,0,1).xyz,1);
}
]==])
function draw(  )
	draw_shader:use()
    mat_tex1:use(0)
    img_tex1:use(1)
	draw_shader:set_i("tex_main",0)
	draw_shader:set_i("tex_cryst",1)
	draw_shader:draw_quad()
end
function add_mat( x,y,v )
	material:set(x,y,v+material:get(x,y))
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
				img_buf:set(i,j,{0,0,0,0})
			end
		end
		for i=1,5 do
			img_buf:set(math.random(0,map_w-1),math.random(0,map_h-1),{255,255,255,255})
		end
		write_mat()
		write_img()
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
	if config.simulate then
		if config.add_mat >0 then
			mat_tex1:use(0)
			material:read_texture(mat_tex1)

			local rw=math.floor(map_w/15)
			local rh=math.floor(map_h/15)
			local cx=math.floor(map_w/2)
			local cy=math.floor(map_h/2)
			for x=cx-rw,cx+rw do
			for y=cy-rh,cy+rh do
				add_mat(x,y,config.add_mat)
			end
			end
			material:write_texture(mat_tex1)
		end

		diffuse_and_decay(mat_tex1,mat_tex2,map_w,map_h,0.5,config.decay,config.diffuse_steps,img_tex1)
		if(config.diffuse_steps%2==1) then
			local c=mat_tex1
			mat_tex1=mat_tex2
			mat_tex2=c
	    end
	    crystal_step()
	end
	draw()
	if need_save then
		save_img()
		need_save=false
	end
end