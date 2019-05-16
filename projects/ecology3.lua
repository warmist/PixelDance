require 'common'
require 'bit'

--[[
    Ecology the last version to rule all the other versions.

    Features wanted:
        * sand/water/etc behavior i.e. a simpl-ish particles that do one thing
        * material layers that are diffusing e.g. scent, nutrients, maybe water(wetness)?
            with masks (e.g. nutrients only in water, scent only in air)
        * multi-cell organisms (??)
            - allow mutations and stuff
            - more general "what is me" system
        * maybe some physics: springs and such
        * maybe try going big (e.g. with quadtrees and stuff)
--]]

local win_w=768
local win_h=768

__set_window_size(win_w,win_h)
local oversample=0.25

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size

is_remade=false
local max_particle_count=win_w*win_h
current_particle_count= 1000
function update_buffers()
	if particles_pos==nil or particles_pos.w~=max_particle_count then
		particles_pos=make_flt_half_buffer(max_particle_count,1)
        particles_speeds=make_flt_half_buffer(max_particle_count,1)
		particle_types=make_char_buffer(max_particle_count,1)
        is_remade=true
	end
    if static_layer==nil or static_layer.w~=map_w or static_layer.h~=map_h then
        static_layer=make_image_buffer(map_w,map_h)
        is_remade=true
    end
end
update_buffers()


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

uniform ivec2 res;
uniform sampler2D tex_main;
uniform vec2 zoom;
uniform vec2 translate;

void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=normed/zoom+translate;

    vec4 pixel=texture(tex_main,normed);
    color=vec4(pixel.xyz,1);
}
]==])
local place_pixels_shader=shaders.Make(
[==[
#version 330
layout(location = 0) in vec3 position;
out vec3 pos;
uniform int pix_size;
uniform vec2 res;
void main(){
    gl_PointSize=pix_size;
    gl_Position.xy=((floor(position.xy+vec2(0.5,0.5))+vec2(0.5,0.5))/res-vec2(0.5,0.5))*vec2(2,-2);
    gl_Position.zw=vec2(0,1.0);//position.z;
    pos=gl_Position.xyz;
}
]==],[==[
#version 330
out vec4 color;
in vec3 pos;
void main(){
    color=vec4(1,0,0,1);
}
]==])
function rnd( v )
    return math.random()*v*2-v
end
function particle_step(  )
    local gravity=0.001
    for i=0,current_particle_count-1 do
        local t=particle_types:get(i,0)
        if t~= 0 then
            local p=particles_pos:get(i,0)
            local s=particles_speeds:get(i,0)
            --add gravity to all particles that use it
            if t==1 then
                s.g=s.g+gravity
            end
            --limit speed for stability of sim
            local speed_len=math.sqrt(s.r*s.r+s.g*s.g)
            if speed_len>1 then
                s.r=s.r/speed_len
                s.g=s.g/speed_len
            end

            --move particles with intersection testing
            local old={p.r,p.g}
            p.r=p.r+s.r
            p.g=p.g+s.g
            
            if p.r>map_w-1 then p.r=0 end
            if p.g>map_h-1 then p.g=0 end
            if p.r<0 then p.r=map_w-1 end
            if p.g<0 then p.g=map_h-1 end

            local x=math.floor(p.r+0.5)
            local y=math.floor(p.g+0.5)

            local sl=static_layer:get(x,y)

            if sl.r~=0 then
                --reset position because we intersect :<
                p.r=old[1]
                p.g=old[2]
            end
        end
    end
end
function sand_step(  )
    for i=0,current_particle_count-1 do
        local t=particle_types:get(i,0)
        if t== 1 then
            local p=particles_pos:get(i,0)
            local s=particles_speeds:get(i,0)

            local x=math.floor(p.r+0.5)
            local y=math.floor(p.g+0.5)
            local ly=y+1
            if ly<map_h-1 then
                local sl=static_layer:get(x,ly)
                if sl.r~=0 then
                    static_layer:set(x,y,{255,255,255,255})
                    particle_types:set(i,0,0)
                end
            end
        end
    end
end
function sim_tick(  )
    particle_step()
    sand_step()
end
if tex_pixel==nil then
    update_buffers()
    tex_pixel=textures:Make()
    tex_pixel:use(0,0,1)
    tex_pixel:set(static_layer.w,static_layer.h,0)
end
need_clear=false
function update()
    __clear()
    __no_redraw()

    imgui.Begin("ecology")
    draw_config(config)

    --imgui.SameLine()
    if imgui.Button("Reset world") then
        static_layer=nil
        update_buffers()
        need_clear=true
    end
    if is_remade then
        is_remade=false
        for i=0,max_particle_count-1 do
            particles_pos:set(i,0,{math.random()*map_w,math.random()*map_h})
            particles_speeds:set(i,0,{math.random()*0.005-0.0025,math.random()*0.005-0.0025})
            particle_types:set(i,0,1);
            
        end
        for x=0,map_w-1 do
            static_layer:set(x,math.floor(map_h/2),{255,255,255,255})
        end
    end
    if not config.pause then
        sim_tick()
    end
    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    imgui.End()
    __render_to_window()

    if config.draw then
        update_buffers()

        draw_shader:use()
        tex_pixel:use(0,0,1)

        static_layer:write_texture(tex_pixel)

        draw_shader:set_i("tex_main",0)
        draw_shader:set_i("res",map_w,map_h)
        draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
        draw_shader:set("translate",config.t_x,config.t_y)
        draw_shader:draw_quad()

    	place_pixels_shader:use()
        place_pixels_shader:set_i("pix_size",math.floor(1/oversample))
        place_pixels_shader:set("res",map_w,map_h)
        --[[if not tex_pixel:render_to(img_buf.w,img_buf.h) then
            error("failed to set framebuffer up")
        end]]
        if need_clear then
            __clear()
            need_clear=false
        end
        place_pixels_shader:draw_points(particles_pos.d,current_particle_count)
        --[[__render_to_window()
        
        
        ]]
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
