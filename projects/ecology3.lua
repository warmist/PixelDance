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
local max_particle_count=10000

function update_particle_buffer()
	if particles==nil or particles.w~=max_particle_count then
		particles=make_flt_half_buffer(max_particle_count,1)
		particle_types=make_char_buffer(max_particle_count,1)
	end
end
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


local draw_shader=shaders.Make[==[
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
]==]
local place_pixels_shader=shaders.Make[==[
out vec4 color;
in vec3 pos;
void main(){
    color=vec4(1,0,0,1);
}
]==]
function update()
    __clear()
    __no_redraw()

    imgui.Begin("ecology")
    draw_config(config)

    --imgui.SameLine()
    if imgui.Button("Reset world") then
        img_buf=nil
        update_img_buf()
        pixel_init()
        for k,v in pairs(sim_master_list) do
            v.items={}
        end
    end

    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    imgui.SameLine()
    if imgui.Button("Wake") then
        wake_blocks()
    end
    imgui.End()

    if config.draw then
    	
        draw_shader:use()
        tex_pixel:use(0,0,1)

        img_buf:write_texture(tex_pixel)

        draw_shader:set_i("tex_main",0)
        draw_shader:set_i("rez",map_w,map_h)
        draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
        draw_shader:set("translate",config.t_x,config.t_y)
        draw_shader:draw_quad()
    end

    if config.timelapse>0 and tick>=config.timelapse then
        need_save=true
        tick=0
    end
    if need_save then
        save_img()
        need_save=false
    end
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
end
