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
local oversample=0.125

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size

is_remade=false
local max_particle_count=win_w*win_h
current_particle_count= 500
function update_buffers()
	if particles_pos==nil or particles_pos.w~=max_particle_count then
		particles_pos=make_flt_half_buffer(max_particle_count,1)
        particles_speeds=make_flt_half_buffer(max_particle_count,1)
		particle_types=make_char_buffer(max_particle_count,1)
        is_remade=true
	end
    if static_layer==nil or static_layer.w~=map_w or static_layer.h~=map_h then
        static_layer=make_image_buffer(map_w,map_h)
        scratch_layer=make_image_buffer(map_w,map_h)
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
    normed=(normed-vec2(0.5,0.5)-translate)/zoom+vec2(0.5,0.5);

    vec4 pixel=texture(tex_main,normed);
    color=vec4(pixel.xyz,1);
}
]==])
local place_pixels_shader=shaders.Make(
[==[
#version 330
layout(location = 0) in vec3 position;
layout(location = 1) in uint particle_type;

out vec3 pos;
out vec4 col;
uniform int pix_size;
uniform vec2 res;
uniform vec2 zoom;
uniform vec2 translate;
void main(){
    gl_PointSize=pix_size*zoom.y;
    vec2 pix_int_pos=floor(position.xy+vec2(0.5,0.5))+vec2(0.5,0.5);
    vec2 pix_pos=(pix_int_pos/res-vec2(0.5,0.5))*vec2(2,-2);
    gl_Position.xy=pix_pos;
    gl_Position.xy=(gl_Position.xy*zoom+translate*vec2(2,-2));
    gl_Position.zw=vec2(0,1.0);//position.z;
    pos=gl_Position.xyz;
    if (particle_type==1)
        col=vec4(0,0,1,0.8);
    else if(particle_type==0)
        col=vec4(0,0,0,0);
    else
    {
        float v=particle_type;
        col=vec4(1,v/255.0,v/255.0,0.5);
    }
}
]==],[==[
#version 330

out vec4 color;
in vec4 col;
in vec3 pos;
void main(){
    color=col;//vec4(1,(particle_type*110)/255,0,0.5);
}
]==])
function rnd( v )
    return math.random()*v*2-v
end
int_count=0
intersect_list={}
function resolve_intersects(  )
    for k,v in pairs(intersect_list) do
        for i,v in ipairs(v) do
            local t=particle_types:get(v[1],0)

            if t==1 then
                local water_move_speed=0.01
                local p=particles_pos:get(v[1],0)
                local s=particles_speeds:get(v[1],0)
                --target pos
                local tx=math.floor(v[2]+0.5)
                local ty=math.floor(v[3]+0.5)
                --reset pos because we hit something anyways
                p.r=v[2]
                p.g=v[3]

                local ly=ty
                local x1=tx-1
                if x1<0 then x1=map_w-1 end
                local x2=tx+1
                if x2>=map_w then x2=0 end

                if ly<map_h-1 then
                    local sl=scratch_layer:get(tx,ly).a
                    if sl>0 then
                        local s1=scratch_layer:get(x1,ly).a
                        local s2=scratch_layer:get(x2,ly).a
                        if s1==0 then
                            s.r=s.r-water_move_speed
                        elseif s2==0 then
                            s.r=s.r+water_move_speed
                        else
                            local ss1=static_layer:get(tx,ly).a
                            local ss2=static_layer:get(x1,ly).a
                            local ss3=static_layer:get(x2,ly).a
                            print(tx,ly,ss1,ss2,ss3)
                            --static_layer:set(tx,ty,{255,255,255,255})
                            --particle_types:set(v[1],0,0)
                            
                        end
                    end
                end
            else
                --reset position because we intersect :<
                local p=particles_pos:get(v[1],0)
                p.r=v[2]
                p.g=v[3]
                --flip speed
                local s=particles_speeds:get(v[1],0)
                s.r=-s.r*0.8
                s.g=-s.g*0.8
                local l=math.sqrt(s.r*s.r+s.g*s.g)
                if l<0.001 then
                    local tx=math.floor(v[2]+0.5)
                    local ty=math.floor(v[3]+0.5)
                    static_layer:set(tx,ty,{255,255,255,255})
                    particle_types:set(v[1],0,0)
                end
            end
            
        end
    end
    
    intersect_list={}
    
end
function add_intersect( tx,ty,p_id,ox,oy )
    local intersect_id=tx+ty*map_w
    local tbl=intersect_list[intersect_id] or {}
    intersect_list[intersect_id]=tbl
    table.insert(tbl,{p_id,ox,oy})
    int_count=int_count+1
end
function particle_step(  )
    local gravity=0.01
    for x=0,map_w-1 do

    end
    for i=0,current_particle_count-1 do
        local t=particle_types:get(i,0)
        if t~= 0 then
            local p=particles_pos:get(i,0)
            local s=particles_speeds:get(i,0)
            --add gravity to all particles that use it
            if t==1 then
                s.g=s.g+gravity
            else
                --[[ particles go to center!
                local dx=p.r-map_w/2
                local dy=p.g-map_h/2
                local dist=math.sqrt(dx*dx+dy*dy)
                s.r=s.r-(dx/dist)*gravity
                s.g=s.g-(dy/dist)*gravity
                ]]
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
            if p.g>map_h-1 then p.g=map_h-1 end
            if p.r<0 then p.r=map_w-1 end
            if p.g<0 then p.g=0 end

            local x=math.floor(p.r+0.5)
            local y=math.floor(p.g+0.5)
            local old_x=math.floor(old[1]+0.5)
            local old_y=math.floor(old[2]+0.5)
            if old_x~=x or old_y~=y then
                local sl=scratch_layer:get(x,y)
                if sl.a>0 then
                    add_intersect(x,y,i,old[1],old[2])
                end
            end
        end
    end
end
function scratch_update(  )
    draw_shader:use()
    tex_pixel:use(0,0,1)
    tex_scratch:use(1,0,1)
    if not tex_scratch:render_to(scratch_layer.w,scratch_layer.h) then
        error("failed to set framebuffer up")
    end
    __clear()
    static_layer:write_texture(tex_pixel)

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("res",map_w,map_h)
    draw_shader:set("zoom",1*map_aspect_ratio,1)
    draw_shader:set("translate",0,0)
    --draw_shader:draw_quad()

    place_pixels_shader:use()
    --[[tex_scratch:use(1,0,1)
    if not tex_scratch:render_to(scratch_layer.w,scratch_layer.h) then
        error("failed to set framebuffer up")
    end]]
    place_pixels_shader:set_i("pix_size",1)
    place_pixels_shader:set("res",map_w,map_h)
    place_pixels_shader:set("zoom",1*map_aspect_ratio,-1)
    place_pixels_shader:set("translate",0,0)
    if need_clear then
        __clear()
        need_clear=false
    end
    place_pixels_shader:push_iattribute(particle_types.d,"particle_type",1,GL_UNSIGNED_BYTE)
    place_pixels_shader:draw_points(particles_pos.d,current_particle_count)
    __render_to_window()
    scratch_layer:read_texture(tex_scratch)
end
function sim_tick(  )
    int_count=0
    scratch_update()
    particle_step()
    resolve_intersects()
end

if tex_pixel==nil then
    update_buffers()
    tex_pixel=textures:Make()
    tex_pixel:use(0,0,1)
    tex_pixel:set(static_layer.w,static_layer.h,0)
end
if tex_scratch==nil then
    update_buffers()
    tex_scratch=textures:Make()
    tex_scratch:use(0,0,1)
    tex_scratch:set(scratch_layer.w,scratch_layer.h,0)
end
need_clear=false
function save_img(  )
    img_buf_save=make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    img_buf_save:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
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
    if imgui.Button("step") then
        sim_tick()
    end
    if is_remade then
        is_remade=false

        for i=0,current_particle_count-1 do
            local r=math.sqrt(math.random())*map_w/4
            local a=math.random()*math.pi*2
            --particles_pos:set(i,0,{math.random()*map_w/2+map_w/4,math.random()*map_h/2+map_h/4})
            particles_pos:set(i,0,{map_w/2+math.cos(a)*r,map_h/2+math.abs(math.sin(a)*r)})
            particles_speeds:set(i,0,{math.random()*1-0.5,math.random()*1-0.5})
            if math.random()<0.0 then
                particle_types:set(i,0,math.random(0,255));
            else
                particle_types:set(i,0,1);
            end
        end
        particles_pos:set(0,0,{0,0})
        particles_pos:set(1,0,{map_w-1,map_h-1})
        particles_pos:set(2,0,{0,map_h-1})
        particles_pos:set(3,0,{map_w-1,0})
        for x=0,map_w-1 do
            static_layer:set(x,map_h-1,{255,255,255,255})
        end
        for x=math.floor(map_w/4),math.floor(map_w-map_w/4) do
            static_layer:set(x,map_h/2,{255,255,255,255})
        end
    end
    if not config.pause then
        sim_tick()
    end
    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    imgui.Text(string.format("Intesects:%d",int_count))
    imgui.End()
    __render_to_window()

    if config.draw then
        update_buffers()

        draw_shader:use()
        tex_pixel:use(0,0,1)
        tex_scratch:use(0,0,1)

        
        --static_layer:write_texture(tex_pixel)

        draw_shader:set_i("tex_main",0)
        draw_shader:set_i("res",map_w,map_h)
        draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
        draw_shader:set("translate",config.t_x,config.t_y)
        draw_shader:draw_quad()

        --[==[
    	place_pixels_shader:use()
        place_pixels_shader:set_i("pix_size",math.floor(1/oversample))
        place_pixels_shader:set("res",map_w,map_h)
        place_pixels_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
        place_pixels_shader:set("translate",config.t_x,config.t_y)
        --[[if not tex_pixel:render_to(img_buf.w,img_buf.h) then
            error("failed to set framebuffer up")
        end]]
        if need_clear then
            __clear()
            need_clear=false
        end
        place_pixels_shader:push_iattribute(particle_types.d,"particle_type",1,GL_UNSIGNED_BYTE)
        place_pixels_shader:draw_points(particles_pos.d,current_particle_count)
        --[[__render_to_window()
        ]]
        --]==]
        
        
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
