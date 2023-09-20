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
        * add physics: https://www.toptal.com/game/video-game-physics-part-iii-constrained-rigid-body-simulation
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
current_particle_count= 1500
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
tile={
    empty=0,
    sand=1,
    water=2,
    plant=3,
}
particle_colors={
    {0,0,0,tile.empty},
    {124,100,80,tile.sand},
    {70 ,70 ,150,tile.water},
    {81,138,61,tile.plant},
}

function update_particle_colors(  )
    local pcb=particle_colors_buf
    if pcb==nil or pcb.w~=#particle_colors then
        particle_colors_buf=make_image_buffer(#particle_colors,1)
        for i,v in ipairs(particle_colors) do
            particle_colors_buf:set(i-1,0,v)
        end
        pcb=particle_colors_buf
        tex_pcb=textures:Make()
        tex_pcb:use(0,0,1)
        tex_pcb:set(pcb.w,1,0)
        pcb:write_texture(tex_pcb)
    end
end
update_particle_colors()
config=make_config({
    {"pause",false,type="bool"},
    {"draw",true,type="bool"},
    {"zoom",1,type="float",min=1,max=10},
    {"t_x",0,type="float",min=0,max=1},
    {"t_y",0,type="float",min=0,max=1},
    },config)
dist_constraints={}

function clear_dead_constraints()
    local old_c=dist_constraints
    dist_constraints={}
    for i,v in ipairs(dist_constraints) do
        local t1=particle_types:get(v[1],0)
        local t2=particle_types:get(v[2],0)
        if t1~=0 and t2~=0 then
            table.insert(dist_constraints,v)
        end
    end
end

function add_dist_constraint( p1,p2,dist )
    table.insert(dist_constraints,{p1,p2,dist})
end
function resolve_dist_constraints(iter_count)
    clear_dead_constraints()
    for i=1,iter_count do
        for i,v in ipairs(dist_constraints) do
            
        end
    end
end
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
uniform sampler2D pcb_colors;
uniform int pix_size;
uniform vec2 res;
uniform vec2 zoom;
uniform vec2 translate;
void main(){
    gl_PointSize=int(pix_size*abs(zoom.y));
    vec2 pix_int_pos=floor(position.xy+vec2(0.5,0.5))+vec2(0.5,0.5);
    vec2 pix_pos=(pix_int_pos/res-vec2(0.5,0.5))*vec2(2,-2);
    gl_Position.xy=pix_pos;
    gl_Position.xy=(gl_Position.xy*zoom+translate*vec2(2,-2));
    gl_Position.zw=vec2(0,1.0);//position.z;
    pos=gl_Position.xyz;
    

    col=texelFetch(pcb_colors,ivec2(particle_type,0),0);
    if(col.a!=0)
        col.a=1;
    /*
    if (particle_type==1u)
        col=vec4(0,0,1,0.8);
    else if(particle_type==0u)
        col=vec4(0,0,0,0);
    else
    {
        float v=particle_type;
        col=vec4(1,v/255.0,v/255.0,0.5);
    }
    //*/
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
function reset_intersects(  )
    intersect_list={}
end
function resolve_intersects_slips(  )
    for k,v in pairs(intersect_list) do
        --local num_close=#v todo: maybe some crowding prevention?
        for i,v in ipairs(v) do
            local t=particle_types:get(v[1],0)
            if t==tile.sand then --sand slipping
                local sand_move_speed=0.125
                local p=particles_pos:get(v[1],0)
                local s=particles_speeds:get(v[1],0)
                --target pos
                local tx=math.floor(v[2]+0.5)
                local ty=math.floor(v[3]+0.5)
                --reset pos because we hit something anyways
                p.r=v[2]
                p.g=v[3]

                local ly=ty+1
                local x1=tx-1
                if x1<0 then x1=map_w-1 end
                local x2=tx+1
                if x2>=map_w then x2=0 end

                if ly<=map_h-1 then
                    local sl=scratch_layer:get(tx,ly).a
                    if sl>0 then
                        local s1=scratch_layer:get(x1,ly).a
                        local s2=scratch_layer:get(x2,ly).a
                        if s1==0 and s2==0 then
                            s.r=s.r+(math.random()-0.5)*sand_move_speed
                        elseif s1==0 then
                            s.r=s.r-sand_move_speed
                        elseif s2==0 then
                            s.r=s.r+sand_move_speed
                            --s.r=s.r+math.random()*sand_move_speed
                        else
                            local ss1=scratch_layer:get(tx,ly).a
                            local ss2=scratch_layer:get(x1,ly).a
                            local ss3=scratch_layer:get(x2,ly).a
                            if ss1>0 and ss2>0 and ss3>0 then
                                static_layer:set(tx,ty,particle_colors[tile.sand+1] or {255,0,0,255})
                                particle_types:set(v[1],0,0)
                            end
                        end
                    end
                end
            elseif t==tile.water then --water slipping+ejection?
                local water_move_speed=0.3
                local water_lift=0.05
                local p=particles_pos:get(v[1],0)
                local s=particles_speeds:get(v[1],0)
                --target pos
                local tx=math.floor(v[2]+0.5)
                local ty=math.floor(v[3]+0.5)
                --reset pos because we hit something anyways
                p.r=v[2]
                p.g=v[3]

                local ly=ty+1
                local x1=tx-1
                if x1<0 then x1=map_w-1 end
                local x2=tx+1
                if x2>=map_w then x2=0 end

                if ly<=map_h-1 then
                    local sl=scratch_layer:get(tx,ly).a
                    if sl>0 then
                        local s1=scratch_layer:get(x1,ty).a
                        local s2=scratch_layer:get(x2,ty).a

                        local s3=scratch_layer:get(x1,ly).a
                        local s4=scratch_layer:get(x2,ly).a
                        
                        if (s1==0 and s2==0) or (s3==0 and s4==0) then
                            s.r=s.r+(math.random()-0.5)*water_move_speed
                            --s.g=s.g*0.1
                            s.g=s.g-water_lift
                        elseif s1==0 or s3==0 then
                            s.r=s.r-water_move_speed
                            --s.g=s.g*0.1
                            s.g=s.g-water_lift
                        elseif s2==0 or s4==0 then
                            s.r=s.r+water_move_speed
                            --s.g=s.g*0.1
                            --s.r=s.r+math.random()*sand_move_speed
                            s.g=s.g-water_lift
                        else
                            --TODO: not sure if this works for water...
                            local ss1=scratch_layer:get(tx,ly).a
                            local ss2=scratch_layer:get(x1,ty).a
                            local ss3=scratch_layer:get(x2,ty).a
                            if ss1>0 and ss2>0 and ss3>0 then
                                static_layer:set(tx,ty, particle_colors[tile.water+1] or {255,0,0,255})
                                particle_types:set(v[1],0,0)
                            end
                        end
                    end
                end
            else
                --we intesected so we reset positions
                local p=particles_pos:get(v[1],0)
                p.r=v[2]
                p.g=v[3]
                --rest of resolution, done at iterative solver
            end
        end
    end
end
function clear_dead_intersects(  )
    local old_i=intersect_list
    intersect_list={}
    for i,v in ipairs(old_i) do
        if #v > 0 then
            local tbl={}
            for _,iv in ipairs(v) do
                local t1=particle_types:get(iv[1],0)
                if t1~=0 then
                    table.insert(tbl,iv)
                end
            end
            if #tbl>0 then
                table.insert(intersect_list,tbl)
            end
        end
    end
end
function resolve_intersects(  )
    for i,v in ipairs(intersect_list) do
        for _,iv in ipairs(table_name) do
            local p=particles_pos:get(iv[1],0)
            local s=particles_speeds:get(v[1],0)
            --calculate forces
            --apply forces
            --update speeds
            s.r=-s.r*0.8
            s.g=-s.g*0.8
            local l=math.sqrt(s.r*s.r+s.g*s.g)
        end
    end
end
function add_intersect( tx,ty,p_id,ox,oy )
    local intersect_id=tx+ty*map_w
    local tbl=intersect_list[intersect_id] or {}
    intersect_list[intersect_id]=tbl
    table.insert(tbl,{p_id,ox,oy})
    int_count=int_count+1
end
function reserve_particle_id(  )
    for i=0,current_particle_count-1 do
        if particle_types:get(i,0)==0 then
            return i
        end
    end
    if current_particle_count<max_particle_count then
        current_particle_count=current_particle_count+1
        return current_particle_count-1
    end
    --TODO: resolve this?
    return 0
end
add_list={}
add_count=0
function add_particle( p )
    local id=reserve_particle_id()
    particles_pos:set(id,0,{p[1],p[2]})
    particles_speeds:set(id,0,{p[3],p[4]})
    particle_types:set(id,0,p[5])
end
function wake_pixels( x,y,s)
    local dx={ -1, 0, 1,-1, 1,-1, 0, 1}
    local dy={ -1,-1,-1, 0, 0, 1, 1, 1}
    local new_speed=s*0.2
    for i=1,8 do
        local tx=x+dx[i]
        if tx<0 then tx=tx+map_w end
        if tx>=map_w then tx=tx-map_w end
        local ty=y+dy[i]
        if ty<0 then ty=ty+map_h end
        if ty>=map_h then ty=ty-map_h end

        local a=static_layer:get(tx,ty).a
        if a~=0 and a~=255 then
            table.insert(add_list,{tx,ty,
            math.random()*new_speed-new_speed/2,math.random()*new_speed-new_speed/2,
            a})
            static_layer:set(tx,ty,{0,0,0,0})
        end
       
    end
end
function resolve_adds(  )
    for i,v in ipairs(add_list) do
        add_particle(v)
    end
    add_count=#add_list
    add_list={}
end
function particle_step(  )
    local gravity=0.1
    for x=0,map_w-1 do

    end
    for i=0,current_particle_count-1 do
        local t=particle_types:get(i,0)
        if t~= 0 then
            local p=particles_pos:get(i,0)
            local s=particles_speeds:get(i,0)
            --add gravity to all particles that use it
            if t==tile.sand or t==tile.water then
                s.g=s.g+gravity
            else
                --[[ particles go to center!
                local dx=p.r-map_w/2
                local dy=p.g-map_h/2
                local dist=math.sqrt(dx*dx+dy*dy)
                s.r=s.r-(dx/dist)*gravity
                s.g=s.g-(dy/dist)*gravity
                --]]
            end
            --limit speed for stability of sim
            local speed_len=math.sqrt(s.r*s.r+s.g*s.g)
            if speed_len>1 then
                s.r=s.r/speed_len
                s.g=s.g/speed_len
                speed_len=1
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
                --print(x,y,sl.a)
                if sl.a>0 then
                    add_intersect(x,y,i,old[1],old[2])
                else
                    wake_pixels(old_x,old_y,speed_len)
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

    -- [[
    --huh? these two must go before tex_scratch stuff...
    tex_pcb:use(2,0,1)
    place_pixels_shader:set_i("pcb_colors",2)

    tex_scratch:use(1,0,1)
    if not tex_scratch:render_to(scratch_layer.w,scratch_layer.h) then
        error("failed to set framebuffer up")
    end
    --]]

    place_pixels_shader:set_i("pix_size",1)
    place_pixels_shader:set("res",map_w,map_h)
    place_pixels_shader:set("zoom",1*map_aspect_ratio,-1)
    place_pixels_shader:set("translate",0,0)

    place_pixels_shader:push_iattribute(particle_types.d,"particle_type",1,GL_UNSIGNED_BYTE)
    place_pixels_shader:draw_points(particles_pos.d,current_particle_count)
    __render_to_window()
    scratch_layer:read_texture(tex_scratch)
end
function sim_tick(  )
    int_count=0
    scratch_update()
    particle_step()
    resolve_intersects_slips()
    clear_dead_intersects()
    
    resolve_adds()
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
        --print("==============================")
        is_remade=false

        -- [[
        for i=0,current_particle_count-1 do
            local r=math.sqrt(math.random())*map_w/4
            local a=math.random()*math.pi*2
            --particles_pos:set(i,0,{math.random()*map_w/2+map_w/4,math.random()*map_h/2+map_h/4})
            particles_pos:set(i,0,{map_w/2+math.cos(a)*r,map_h/2+math.sin(a)*r})
            particles_speeds:set(i,0,{math.random()*1-0.5,math.random()*1-0.5})
            if math.random()<0.5 then
                particle_types:set(i,0,tile.water);
            else
                particle_types:set(i,0,tile.sand);
            end
        end
        --]]

        for x=0,map_w-1 do
            static_layer:set(x,map_h-1,{255,255,255,255})
        end
        for x=math.floor(map_w/4),math.floor(map_w-map_w/4) do
            static_layer:set(x,map_h/2,{255,255,255,255})
        end
    end
    if not config.pause then
        sim_tick()
        --add_particle{map_w/2,0,math.random()*0.25-0.125,math.random()-0.5,3}
    end
    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    imgui.Text(string.format("Intesects:%d",int_count))
    imgui.Text(string.format("Added particles:%d",add_count))
    imgui.End()
    __render_to_window()

    
    update_buffers()

    draw_shader:use()
    if config.draw then
        tex_pixel:use(0,0,1)
        static_layer:write_texture(tex_pixel)
    else
        tex_scratch:use(0,0,1)
    end

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("res",map_w,map_h)
    draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
    draw_shader:set("translate",config.t_x,config.t_y)
    draw_shader:draw_quad()

    if config.draw then
    	place_pixels_shader:use()
        tex_pcb:use(2,0,1)
        place_pixels_shader:set_i("pcb_colors",2)
        place_pixels_shader:set_i("pix_size",math.floor(1/oversample))
        place_pixels_shader:set("res",map_w,map_h)
        place_pixels_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
        place_pixels_shader:set("translate",config.t_x,config.t_y)
        if need_clear then
            __clear()
            need_clear=false
        end
        place_pixels_shader:push_iattribute(particle_types.d,"particle_type",1,GL_UNSIGNED_BYTE)
        place_pixels_shader:draw_points(particles_pos.d,current_particle_count)
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
