require 'common'
require 'bit'
local win_w=768
local win_h=768

__set_window_size(win_w,win_h)
local oversample=0.5

local map_w=(win_w*oversample)
local map_h=(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size

is_remade=false
local max_particle_count=win_w*win_h
current_particle_count= 1000
function update_particle_buffer()
	if particles==nil or particles.w~=max_particle_count then
		particles=make_flt_half_buffer(max_particle_count,1)
        particles_speeds=make_flt_half_buffer(max_particle_count,1)
		particle_types=make_char_buffer(max_particle_count,1)
        is_remade=true
	end
end
update_particle_buffer()
function update_img_buf(  )
    local nw=math.floor(map_w)
    local nh=math.floor(map_h)

    if img_buf==nil or img_buf.w~=nw or img_buf.h~=nh then
        img_buf=make_image_buffer(nw,nh)
        sun_buffer=make_float_buffer(nw,1)
        is_remade=true
    end
end

config=make_config({
    {"pause",false,type="bool"},
    {"draw",true,type="bool"},
    {"zoom",1,type="float",min=1,max=10},
    {"t_x",0,type="float",min=0,max=1},
    {"t_y",0,type="float",min=0,max=1},
    },config)

--[==[
#version 330
layout(location = 0) in vec3 position;
out vec3 pos;
void main()
{
    pos=position;
}
]==]
local draw_shader=shaders.Make(
[==[
#version 330
#line 47
out vec4 color;
in vec3 pos;

uniform ivec2 rez;
uniform sampler2D tex_main;
uniform vec2 zoom;
uniform vec2 translate;

void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    normed=normed/zoom+translate;

    vec4 pixel=texture(tex_main,normed);
    color=vec4(pixel.xyz,1);
}
]==])
local place_pixels_shader=shaders.Make[==[
#version 330
out vec4 color;
in vec3 pos;
void main(){
    color=vec4(1,0,0,0.1);
}
]==]
function rnd( v )
    return math.random()*v*2-v
end
function particle_step(  )
    for i=0,current_particle_count do
        local p=particles:get(i,0)
        local s=particles_speeds:get(i,0)
        for j=i+1,current_particle_count do
            local pt=particles:get(j,0)
            local dx=pt.r-p.r
            local dy=pt.g-p.g
            local len=math.sqrt(dx*dx+dy*dy)
            s.r=s.r+(dx/len)*0.0000001
            s.g=s.g+(dy/len)*0.0000001
        end
        s.r=s.r*0.99
        s.g=s.g*0.99
    end
    for i=0,current_particle_count do
        local p=particles:get(i,0)
        local s=particles_speeds:get(i,0)
        p.r=p.r+s.r+rnd(0.005)
        p.g=p.g+s.g+rnd(0.005)
    end
end
if tex_pixel==nil then
    update_img_buf()
    tex_pixel=textures:Make()
    tex_pixel:use(0,0,1)
    tex_pixel:set(img_buf.w,img_buf.h,0)
end
need_clear=false
function update()
    __clear()
    __no_redraw()

    imgui.Begin("ecology")
    draw_config(config)

    --imgui.SameLine()
    if imgui.Button("Reset world") then
        img_buf=nil
        update_img_buf()
        need_clear=true
    end
    if is_remade then
        is_remade=false
        for i=0,max_particle_count-1 do
            particles:set(i,0,{math.random()*2-1,math.random()*2-1})
            particles_speeds:set(i,0,{math.random()*0.005-0.0025,math.random()*0.005-0.0025})
        end
    end
    particle_step()
    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    imgui.End()
    __render_to_window()

    if config.draw then
        update_img_buf()

    	place_pixels_shader:use()

        if not tex_pixel:render_to(img_buf.w,img_buf.h) then
            error("failed to set framebuffer up")
        end
        if need_clear then
            __clear()
            need_clear=false
        end
        place_pixels_shader:draw_points(particles.d,current_particle_count)
        __render_to_window()
        
        draw_shader:use()
        tex_pixel:use(0,0,1)

        --img_buf:write_texture(tex_pixel)

        draw_shader:set_i("tex_main",0)
        draw_shader:set_i("rez",map_w,map_h)
        draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
        draw_shader:set("translate",config.t_x,config.t_y)
        draw_shader:draw_quad()
        
    end

    if need_save then
        save_img()
        need_save=false
    end
    --[[
    local tx,ty=config.t_x,config.t_y
    local c,x,y,dx,dy= is_mouse_down2()
    local update_bounds=false
    if c then
        dx,dy=dx/size[1],dy/size[2]
        config.t_x=config.t_x-dx/config.zoom
        config.t_y=config.t_y+dy/config.zoom
        update_bounds=true
    end
    if __mouse.wheel~=0 then
        local pfact=math.exp(__mouse.wheel/10)
        config.zoom=config.zoom*pfact
        --config.t_x=config.t_x*pfact
        --config.t_y=config.t_y*pfact
        update_bounds=true
    end
    if update_bounds then
        config.t_x=clamp(config.t_x,0,1-1/config.zoom)
        config.t_y=clamp(config.t_y,0,1-1/config.zoom)
    end
    ]]
end
