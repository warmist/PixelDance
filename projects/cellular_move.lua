--[===[
2D CA but!:
    * no create/destroy! only move
    * if can't move, dont!
    * gen random rules, check out the "dynamics" and "meta-atoms"
    * "permutation city"
--]===]
require 'common'
require 'bit'

local win_w=1024
local win_h=1024

__set_window_size(win_w,win_h)
local oversample=1/8

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size

is_remade=false
local dist_logic_type="simple"
local max_particle_count=10000
current_particle_count=current_particle_count or 0

function update_buffers()
    if particles_pos==nil or particles_pos.w~=max_particle_count then
        particles_pos=make_flt_half_buffer(max_particle_count,1)
        particles_age=make_float_buffer(max_particle_count,1)
        is_remade=true
        need_clear=true
    end
    if static_layer==nil or static_layer.w~=map_w or static_layer.h~=map_h then
        static_layer=make_image_buffer(map_w,map_h)
        movement_layer_target=make_char_buffer(map_w,map_h) --a 0,1,2 would be enough
        movement_layer_source=make_char_buffer(map_w,map_h) --direction of movement
        is_remade=true
        need_clear=true
    end
end
update_buffers()


config=make_config({
    {"pause",false,type="bool"},
    {"color_by_age",true,type="bool"},
    {"no_transients",true,type="bool"},
    {"decay",0.99,type="floatsci",power=0.01},
    {"block_size",10,type="int",min=0,max=50,watch=true},
    {"block_count",3,type="int",min=0,max=8,watch=true},
    {"block_offset",4,type="int",min=0,max=100,watch=true},
    {"long_dist_mode",0,type="choice",choices={"simple","single","multiple"}},
    {"long_dist_range",2,type="int",min=0,max=5},
    {"long_dist_offset",0,type="int",min=0,max=7},
    {"zoom",1,type="float",min=1,max=10},
    {"t_x",0,type="float",min=0,max=1},
    {"t_y",0,type="float",min=0,max=1},
    },config)
dist_constraints={}


local draw_shader=shaders.Make(
[==[
#version 330
#line 47
out vec4 color;
in vec3 pos;

uniform ivec2 res;
uniform sampler2D tex_main;
uniform sampler2D tex_old;
uniform vec2 zoom;
uniform vec2 translate;
uniform float decay;
#define DOWNSAMPLE 0
#define SMOOTHDOWNSAMPLE 0
#define MAXDOWNSAMPLE 0
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5)-translate)/zoom+vec2(0.5,0.5);
    //normed/=2;
#if DOWNSAMPLE
    normed*=vec2(res)/2;
    normed=floor(normed)/(vec2(res)/2);
#endif
#if SMOOTHDOWNSAMPLE
    vec4 pixel=textureOffset(tex_main,normed,ivec2(0,0))+
        textureOffset(tex_main,normed,ivec2(1,0))+
        textureOffset(tex_main,normed,ivec2(0,1))+
        textureOffset(tex_main,normed,ivec2(1,1));
    pixel/=4;
#elif MAXDOWNSAMPLE
    vec4 pixel=max(
    max(textureOffset(tex_main,normed,ivec2(0,0)),
        textureOffset(tex_main,normed,ivec2(1,0))),
    max(textureOffset(tex_main,normed,ivec2(0,1)),
        textureOffset(tex_main,normed,ivec2(1,1))));
#else
    vec4 pixel=texture(tex_main,normed);
#endif
    vec4 pix_old=texture(tex_old,(pos.xy+vec2(1,1))/2);
    //float decay=0.0;
    float a=pixel.a;
    //vec3 c=pixel.xyz*a+pix_old.xyz*(1-a)-vec3(0.003);
    vec3 c=pixel.xyz*a+pix_old.xyz*(1-a)*decay;
    c=clamp(c,0,1);
    color=vec4(c,1);
    //color=vec4(mix(pixel.xyz,pix_old.xyz,0.6),1);
    //color=vec4(pixel.xyz,1);
    //color=vec4(1,0,0,1);
}
]==])

local place_pixels_shader=shaders.Make(
[==[
#version 330
layout(location = 0) in vec3 position;
layout(location = 1) in float particle_age;

out vec3 pos;
out vec4 col;

uniform int pix_size;
uniform vec2 res;
uniform vec2 zoom;
uniform vec2 translate;

uniform vec2 value_range;

uniform int no_transients;
#define LOG_AGE 0
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    gl_PointSize=int(pix_size*abs(zoom.y));
    vec2 pix_int_pos=floor(position.xy+vec2(0.5,0.5))+vec2(0.5,0.5);
    vec2 pix_pos=(pix_int_pos/res-vec2(0.5,0.5))*vec2(2,-2);
    gl_Position.xy=pix_pos;
    gl_Position.xy=(gl_Position.xy*zoom+translate*vec2(2,-2));
    gl_Position.zw=vec2(0,1.0);//position.z;
    pos=gl_Position.xyz;
    

    //col=texelFetch(pcb_colors,ivec2(particle_type,0),0);
#if LOG_AGE
    float pa=log(particle_age+1);
    pa=(pa-log(value_range.x+1))/(log(value_range.y+1)-log(value_range.x+1));
#else
    float pa=particle_age;
    pa=(pa-value_range.x)/max((value_range.y-value_range.x),0.01);
#endif
    if (particle_age==0)
        pa=0;

    //pa=clamp(pa,0,1);
    //vec3 c=palette(pa,vec3(0.5),vec3(0.5),vec3(1),vec3(0.0,0.33,0.67));
    vec3 c=palette(pa,vec3(0.8,0.5,0.4),vec3(0.2,0.4,0.2),vec3(2,1,1),vec3(0.0,0.25,0.25));
    //vec3 c=palette(pa,vec3(0.2,0.7,0.4),vec3(0.6,0.9,0.2),vec3(0.6,0.8,0.7),vec3(0.5,0.1,0.0));
    //vec3 c=palette(pa,vec3(0.5),vec3(0.5),vec3(0.5),vec3(0.5));
    if(no_transients==1)
    {
        if(particle_age<0.02)
            //c=vec3(0);
            //c*=0.0;
            c=vec3(1);
            //discard;
    }
    col=vec4(c,1);
    //if(col.a!=0)
    //    col.a=1;
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
dir_to_dx={
    [0]={0,0},
    [1]={1,0},
    [2]={1,1},
    [3]={0,1},
    [4]={-1,1},
    [5]={-1,0},
    [6]={-1,-1},
    [7]={0,-1},
    [8]={1,-1},
}
--[[
    432
    501
    678
--]]
rules=rules or {

}
long_rules=long_rules or {}
function rnd( v )
    return math.random()*v*2-v
end
function fix_pos( p )
    local ret={r=p.r,g=p.g}
    if ret.r<0 then ret.r=map_w+ret.r end
    if ret.g<0 then ret.g=map_h+ret.g end
    if ret.r>=map_w then ret.r=ret.r-map_w end
    if ret.g>=map_h then ret.g=ret.g-map_h end
    return ret
end
function displace_by_dir_nn( pos,dir,dist )
    dist=dist or 1
    local ret={r=pos.r,g=pos.g}
    local dx=dir_to_dx[dir]
    ret.r=round(ret.r+dx[1]*dist)
    ret.g=round(ret.g+dx[2]*dist)
    return fix_pos(ret)
end
function get_nn( pos,dist )
    --local ret={}
    local value=0
    for i=1,8 do
        local t=displace_by_dir_nn(pos,i,dist)
        local v=static_layer:get(t.r,t.g)
        if v.a>0 then
            --ret[i]=true
            value=value+math.pow(2,i-1)
        end
    end
    return value
end
function value_to_nn_string( v )
    local ret=""
    local permutation={4,3,2,5--[[0]],1,6,7,8}

    local id=0
    for i=1,8 do
        if (id)%3==0 then
            ret=ret.."\n"
        end
        if i==5 then
            ret=ret.."X"
            id=id+1
        end
        id=id+1
        local vv=permutation[i]
        if bit.band(v,math.pow(2,vv-1))>0 then
            ret=ret..'*'
        else
            ret=ret..'o'
        end
    end
    return ret
end
function dir_to_arrow_string( d )
    local tbl={
        [0]=
[[
   
 * 
   
]],
        [1]=
[[
   
 ->
   
]],
        [2]=
[[
  ^
 / 
   
]],
        [3]=
[[
 ^ 
 | 
   
]],
        [4]=
[[
^  
 \ 
   
]],
        [5]=
[[
   
<- 
   
]],
        [6]=
[[
   
 / 
v  
]],
        [7]=
[[
   
 | 
 v 
]],
        [8]=
[[
   
 \ 
  v
]],
    }
    return tbl[d]
end
function concat_byline( s1,s2 )
    local ret=""
    local f,ns,s_other_start=s2:gmatch("[^\r\n]+")
    for s in s1:gmatch("[^\r\n]+") do
        
        local s_other=f(ns,s_other_start)
        ret=ret..s..s_other.."\n"
    end
    return ret
end
function displace_by_dir( pos,dir )
    local ret={r=pos.r,g=pos.g}
    local dx=dir_to_dx[dir]
    ret.r=round(ret.r+dx[1])
    ret.g=round(ret.g+dx[2])
    return fix_pos(ret)
end
function calculate_long_range_rule( pos )

    for r=2,config.long_dist_range do
        local count_in_range=0
        local last_dir=0
        for j=1,8 do
            local tpos=displace_by_dir_nn(pos,j,r)
            local sl=static_layer:get(tpos.r,tpos.g)
            if sl.a>0 then
                count_in_range=count_in_range+1
                last_dir=j
            end
        end
        if count_in_range>1 then
            return 0 --more than one direction to move, so don't
        elseif count_in_range==1 then
            --if r>4 then
            --    return rotate_dir(last_dir,config.long_dist_offset)
            --else
                return rotate_dir(last_dir,config.long_dist_offset)
            --end
        end
    end
    return 0 --couldn't find any thing
end



function calculate_rule( pos )
    if #rules==0 then
        return math.random(0,8)
    else
        local v=get_nn(pos)
        if v==0 and config.long_dist_range>=2 then
            if config.long_dist_mode==0 then
            -- three choices here: simple long dist
                return calculate_long_range_rule(pos)
            elseif config.long_dist_mode==1 then
                --one rule for all dists
                for i=2,config.long_dist_range do
                    local v=get_nn(pos,i)
                    if v~=0 then
                        return long_rules[2][v]
                    end
                end
            else
                for i=2,config.long_dist_range do
                -- each dist has it's own rules
                    if long_rules[i] then
                        local v=get_nn(pos,i)
                        if v~=0 then
                            return long_rules[i][v]
                        end
                    end
                end
            end
        end
        return rules[v] or 0
    end
end

function round( x )
    return math.floor(x+0.5)
end

function particle_step(  )
    local min_age=math.huge
    local max_age=-math.huge

    local no_0_age=true

    for x=0,map_w-1 do
        for y=0,map_h-1 do
            movement_layer_target:set(x,y,0)
        end
    end

    local trg_pos={}

    for i=0,current_particle_count-1 do
        local pos=fix_pos(particles_pos:get(i,0))
        local dir=calculate_rule(pos)
        local tpos=displace_by_dir(pos,dir)
        local sl=static_layer:get(tpos.r,tpos.g)
        if sl.a>0 then
            dir=0
            tpos=displace_by_dir(pos,dir)
        end
        trg_pos[i]={dir,tpos}
        local tp=movement_layer_target:get(tpos.r,tpos.g)
        if tp<254 then
            tp=tp+1
        end
        movement_layer_target:set(tpos.r,tpos.g,tp)
        --movement_layer_source:set(round(pos.r),round(pos.g),dir)
    end

    for i=0,current_particle_count-1 do
        local pos=fix_pos(particles_pos:get(i,0))
        --local dir=movement_layer_source:get(round(pos.r),round(pos.g))
        --local tpos=displace_by_dir(pos,dir)
        local tpos=trg_pos[i][2]
        local dir=trg_pos[i][1]
        local tp=movement_layer_target:get(tpos.r,tpos.g)

        if tp<2 and dir~=0 then
            pos.r=tpos.r
            pos.g=tpos.g
            particles_pos:set(i,0,pos)
            if config.color_by_age then
                --particles_age:set(i,0,0)
                local a=particles_age:get(i,0)
                a=a*0.99
                particles_age:set(i,0,a)
                --if not no_0_age then
                --    min_age=0
                --end
                if a>max_age then max_age=a end
                if not no_0_age then
                    if a<min_age then min_age=a end
                end
               --local a=particles_age:get(i,0)
               --particles_age:set(i,0,a+0.002)
            end
        else
            --movement_layer_target:set(tpos.r,tpos.g,tp-1)
            local a=particles_age:get(i,0)
            if config.color_by_age then
               --particles_age:set(i,0,0)
                a=a+0.001
                particles_age:set(i,0,a)
                if a>max_age then max_age=a end
                if a<min_age then min_age=a end
            end
        end
    end
    if config.color_by_age then
        g_min_age=min_age
        g_max_age=max_age
    end
    return min_age,max_age
end
if tex_pixel==nil then
    update_buffers()
    tex_pixel=multi_texture(static_layer.w,static_layer.h,2,FLTA_PIX)
    scratch_tex=multi_texture(static_layer.w,static_layer.h,2,FLTA_PIX)
end

function scratch_update(  )
    --clear the texture
    local t=scratch_tex:get()
    t:use(0,0,1)
    if not t:render_to(static_layer.w,static_layer.h) then
        error("failed to set framebuffer up")
    end
    __setclear(0,0,0,0)
    __clear()



    --draw_shader:draw_quad()

    place_pixels_shader:use()
    t:use(0,0,1)
    if not t:render_to(static_layer.w,static_layer.h) then
        error("failed to set framebuffer up")
    end

    place_pixels_shader:set_i("pix_size",1)
    place_pixels_shader:set("res",map_w,map_h)
    place_pixels_shader:set("zoom",1*map_aspect_ratio,-1)
    place_pixels_shader:set("translate",0,0)
    place_pixels_shader:set('value_range',g_min_age or 0,g_max_age or 0)
    if config.no_transients then
        place_pixels_shader:set_i("no_transients",1)
    else
        place_pixels_shader:set_i("no_transients",0)
    end
    place_pixels_shader:push_attribute(particles_age.d,"particle_age",1,GL_FLOAT)
    place_pixels_shader:draw_points(particles_pos.d,current_particle_count)
    __render_to_window()
    static_layer:read_texture(t)
end
function sim_tick(  )
    int_count=0
    scratch_update()
    particle_step()
    --scratch_update()
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
function save_gif_frame(  )
    if img_buf_save==nil or img_buf_save.w~=size[1] then
        img_buf_save=make_image_buffer(size[1],size[2])
    end
    if giffer==nil then
        return
    end
    img_buf_save:read_frame()
    giffer:frame(img_buf_save)
end
function rotate_pattern(p)
    local ret=p*2
    if ret>=256 then
        ret=ret-256+1
    end
    return ret
end
function rotate_pattern_left(p)
    local v=p%2
    local ret=math.floor(p/2)
    if v==1 then
        ret=ret+128
    end
    return ret
end
function rotate_dir( d,r )
    if d==0 then
        return 0
    end
    return (d+r-1)%8+1
end
function classify_patterns()
    --print("=========================")
    local store_id=1
    local ret_patern_store={}
    local pattern_store={}

    for i=1,255 do
        local old_pattern
        local r=0
        local rp=i
        for j=1,8 do
            rp=rotate_pattern_left(rp)
            local sp=pattern_store[rp]
            if sp then
                old_pattern={id=sp.id,sym=sp.sym,rot=j}
                ret_patern_store[i]=old_pattern
                break
            end
            if rp==i then
                r=j
                break
            end
        end
        if old_pattern then
            --print(i,old_pattern.id,old_pattern.sym,old_pattern.rot)
        else
            pattern_store[i]={id=store_id,sym=r,rot=0}
            --print(i,store_id,r,0)
            store_id=store_id+1
            ret_patern_store[i]=pattern_store[i]
        end
    end
    return ret_patern_store
end
function dist_func( x,y )
    --local v=(math.abs(x)+math.abs(y))
    local v=math.sqrt(x*x+y*y)
    return v
end
local animation_data={
    sim_tick_current=0,
    sim_tick_max=1000,
    sav_tick_current=0,
    sav_tick_max=25,
    animating=false,
}
function animation_metatick(  )
    local a=animation_data
    a.sav_tick_current=a.sav_tick_current+1
    if a.sav_tick_current>=a.sav_tick_max then
        a.animating=false
    end

    config.block_offset=config.block_offset-1
    if config.block_offset<10 then
        a.animating=false
        config.block_offset=10
    end
    is_remade=true
    need_save=true
end
function animation_tick(  )
    local a=animation_data
    a.sim_tick_current=a.sim_tick_current+1
    if a.sim_tick_current>=a.sim_tick_max then
        a.sim_tick_current=0
        animation_metatick()
    end
end
function animation_start(  )
    local a=animation_data
    a.sim_tick_current=0
    a.sav_tick_current=0
    a.animating=true
end
function generate_rules( rule_tbl,overwrite )
    local pt=classify_patterns()
    local pt_rules={}
    for i,v in pairs(pt) do
        -- [[
        if pt_rules[v.id]==nil then
            if v.sym==8  then
                pt_rules[v.id]={math.random(0,8),i}
            else
                pt_rules[v.id]={0,i}
            end
        end
        --]]
    end

    if overwrite then
        for i,v in ipairs(overwrite) do
            pt_rules[v[1]]={v[2],i}
        end
    end

    local already_printed={}
    for i,v in ipairs(pt) do
        if not already_printed[v.id] then
            if v.sym==8 then
                print("Group id:",v.id)
                local actual_dir=rotate_dir(pt_rules[v.id][1],v.rot)
                print(concat_byline(value_to_nn_string(pt_rules[v.id][2]),dir_to_arrow_string(actual_dir)))
                already_printed[v.id]=true
            end
        end
    end
    for i,v in pairs(pt) do
        -- [[
        if v.sym==8  then
            rule_tbl[i]=rotate_dir(pt_rules[v.id][1],v.rot)
        else
            rule_tbl[i]=0
        end
        --]]
    end
end
function update()
    __clear()
    __no_redraw()

    imgui.Begin("Cellular move")
    draw_config(config)

    --imgui.SameLine()
    need_clear=false
    if imgui.Button("Reset world") then
        static_layer=nil
        update_buffers()
        need_clear=true
    end
    local sim_done=false
    if imgui.Button("step") then
        sim_tick()
        sim_done=true
    end
    if imgui.Button("rand rules") then
        rules={}
        rules[0]=0
        --[[
        for i=1,255 do
            rules[i]=math.random(0,8)
        end
        --]]
        --[[
        for i=1,8 do
            rules[math.pow(2,i)]=math.random(0,8)
        end

        for i=1,8 do
            for j=1,8 do
                if i~=j then
                    rules[math.pow(2,i)+math.pow(2,j)]=math.random(0,8)
                end
            end
        end
        --]]
        -- [==[
        generate_rules(rules)--,{{1,0},{2,0}})
        long_rules={}
        if config.long_dist_mode==2 then
            for i=2,config.long_dist_range do
                long_rules[i]={}
                long_rules[i][0]=0
                generate_rules(long_rules[i])
            end
        elseif config.long_dist_mode==1 then
            local i=2
            long_rules[i]={}
            long_rules[i][0]=0
            generate_rules(long_rules[i])
        end
        --]==]
        is_remade=true
        need_clear=true
    end
    if imgui.Button("save rules") then
        local f=io.open("rules.txt","w")
        for i=1,255 do
            f:write(i," ",rules[i],"\n")
        end
        f:close()
    end
    imgui.SameLine()
    if imgui.Button("load rules") then
        local f=io.open("rules_huh.txt","r")
        for i=1,255 do
            local ii,v=f:read("*n","*n")
            if ii~=i then
                print("FAIL at line:",i)
                --break
            end

            rules[ii]=v
        end
        f:close()
    end
    if not config.color_by_age then

        if imgui.Button("recolor points") then
            g_max_age=-math.huge
            g_min_age=math.huge
            local max_val=0
            for i=0,current_particle_count-1 do
                local p=particles_pos:get(i,0)
                
                local x=p.r-math.floor(map_w/2)
                local y=p.g-math.floor(map_h/2)
                local v=dist_func(x,y)
                if max_val<v then max_val=v end
            end
            for i=0,current_particle_count-1 do
                local p=particles_pos:get(i,0)
                
                local x=p.r-math.floor(map_w/2)
                local y=p.g-math.floor(map_h/2)
                local v=dist_func(x,y)
                particles_age:set(i,0,v/(max_val))
            end
            g_max_age=1
            g_min_age=0
        end
    end
    if imgui.Button("clear rules") then
        rules={}
    end
    if imgui.Button("Save Gif") then
        if giffer~=nil then
            giffer:stop()
        end
        save_gif_frame()
        giffer=gif_saver(string.format("saved_%d.gif",os.time(os.date("!*t"))),
            img_buf_save,5000,10)
    end
    imgui.SameLine()
    if imgui.Button("Stop Gif") then
        if giffer then
            giffer:stop()
            giffer=nil
        end
    end
    if is_remade or (config.__change_events and config.__change_events.any) then
        current_particle_count=0
        --print("==============================")
        is_remade=false

        -- [[
        for x=0,map_w-1 do
        for y=0,map_h-1 do
            static_layer:set(x,y,{0,0,0,0})
        end
        end
        --[==[
        local count_add={0,2,4,6}
        local offset_add={0,8,17,22}
        local bcount_mod={1,1,1,1}
        local angle_offset={0,math.pi/8,math.pi/4,3*math.pi/8}
        for kk=1,1 do
            local b_count=math.floor(config.block_count*bcount_mod[kk])
            local offset=math.floor(config.block_offset+offset_add[kk])


            for i=1,b_count do
                local v=(i-1)/b_count
                local cx=math.floor(map_w/2)
                local cy=math.floor(map_h/2)
                local bs=config.block_size+count_add[kk]
                local hbs=math.floor(bs/2+0.5)
                local tx=math.floor(math.cos(v*math.pi*2+angle_offset[kk])*offset+0.5)+cx-hbs
                local ty=math.floor(math.sin(v*math.pi*2+angle_offset[kk])*offset+0.5)+cy-hbs
                
                for x=0,bs-1 do
                for y=0,bs-1 do
                    local ttx=x+tx
                    local tty=y+ty
                    if static_layer:get(ttx,tty).a==0 then
                        static_layer:set(ttx,tty,{1,1,1,1})
                        particles_pos:set(current_particle_count,0,{ttx,tty})
                        if config.color_by_age then
                            particles_age:set(current_particle_count,0,0)
                        end
                        current_particle_count=current_particle_count+1
                    end
                end
                end
            end
        end
        --]==]
        --[==[
        local not_place_count=0
        while current_particle_count<config.block_count do
            local cx=math.floor(map_w/2)
            local cy=math.floor(map_h/2)

            local bs=config.block_size
            local hbs=math.floor(bs/2+0.5)
            local v=math.random()
            local r=math.sqrt(math.random())*hbs
            local tx=math.floor(math.cos(v*math.pi*2)*r+cx)
            local ty=math.floor(math.sin(v*math.pi*2)*r+cy)
            if static_layer:get(tx,ty).a==0 then
                static_layer:set(tx,ty,{1,1,1,1})
                particles_pos:set(current_particle_count,0,{tx,ty})
                if config.color_by_age then
                    particles_age:set(current_particle_count,0,0)
                end
                current_particle_count=current_particle_count+1
            else
                not_place_count=not_place_count+1
            end
            if not_place_count>1000 then
                break
            end
        end
        --]==]
        
        -- [==[
        local cx=math.floor(map_w/2)
        local cy=math.floor(map_h/2)

        local bs=config.block_size
        local cx_o=cx
        local cy_o=cy
        local bc=config.block_count
        local o=config.block_offset

        local bw=bs+o --block width/height is it's size and spacer
        local hbw=math.floor(bw*bc/2)
        local ebw=bw*bc-hbw
        for bx=-hbw,ebw do
            for by=-hbw,ebw do
                local mx=(bx+hbw-1)%bw
                local my=(by+hbw-1)%bw

                local tx=cx_o+bx+math.floor(o/2)
                local ty=cy_o+by+math.floor(o/2)
                if mx<bs and my<bs then
                    particles_pos:set(current_particle_count,0,{tx,ty})
                    if config.color_by_age then
                        particles_age:set(current_particle_count,0,0)
                    end
                    current_particle_count=current_particle_count+1
                end
            end
        end
        --]==]
        print("particle count:",current_particle_count)
        --for i=0,max_particle_count-1 do
           
            --[[
            local x=math.random(0,map_w-1)
            local y=math.random(0,map_h-1)
            if static_layer:get(x,y).a==0 then
                particles_pos:set(i,0,{x,y})
            else
                local x=math.random(0,map_w-1)
                local y=math.random(0,map_h-1)
                particles_pos:set(i,0,{x,y})
            end
            --]]
            --[[
            local r=math.sqrt(math.random())*map_w/2

            local a=math.random()*math.pi*2

            --]]
            --particles_pos:set(i,0,{math.random()*map_w/2+map_w/4,math.random()*map_h/2+map_h/4})
            --particles_pos:set(i,0,{map_w/2+math.cos(a)*r,map_h/2+math.sin(a)*r})
            --[[

            local w=figure_w
            local x=i%w-math.floor(w/2)
            local y=math.floor(i/w)-math.floor(w/2)
            particles_pos:set(current_particle_count,0,{map_w/2+x,map_h/2+y})
            if config.color_by_age then
                particles_age:set(i,0,0)
            end
            --particles_age:set(i,0,dist_func(x,y)/(w))
            --]]
            

            --]]
            --[[
            local r=math.sqrt(math.random())*map_w/2

            local a=math.random()*math.pi*2

            --]]
            --particles_pos:set(i,0,{math.random()*map_w/2+map_w/4,math.random()*map_h/2+map_h/4})
            --particles_pos:set(i,0,{map_w/2+math.cos(a)*r,map_h/2+math.sin(a)*r})
            --[[
            local low_x=(i<(max_particle_count-1)/2)
            local w=math.floor(figure_w/2)
            --local h=math.floor(figure_h/2)
            local ii=i
            local offset=config.start_offset
            local offset_1=math.floor(offset/2)
            local offset_2=offset-offset_1
            if not low_x then
                ii=i-math.floor(max_particle_count/2)
            end
            local x=ii%w-math.floor(w/2)
            local y=math.floor(ii/w)-math.floor(w/2)
            if low_x then
                particles_pos:set(i,0,{x+math.floor(map_w/2)-offset_1-math.floor(w/2+0.5),y+math.floor(map_h/2)})
            else
                particles_pos:set(i,0,{x+math.floor(map_w/2)+offset_2+math.floor(w/2),y+math.floor(map_h/2)})
            end

            -- map particles to x=[offset,map_w-offset]; y=[center-h;center+h] (where h is height of bar)
            --[[
            local x_coord=i%(map_w-offset*2)+offset
            local y_coord=math.floor(map_h/2)-math.floor(figure_h/2)+math.floor(i/(map_w-offset*2))
            particles_pos:set(i,0,{x_coord,y_coord})
            --]]

        --end
        --]]
        --[[
        
        for i=1,noise_count do
            local i=noise_idx[i] or 0--math.floor((max_particle_count-1)*(i-1)/(noise_count-1)+0.5)--math.random(0,max_particle_count-1)
            local x=math.random(0,map_w-1)
            local y=math.random(0,map_h-1)
            particles_pos:set(i,0,{x,y})
        end
        --]]
        scratch_update()
        need_clear=true
    end
    if not config.pause then
        sim_tick()
        sim_done=true
        --add_particle{map_w/2,0,math.random()*0.25-0.125,math.random()-0.5,3}
    end
    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    if not animation_data.animating then
        if imgui.Button("Animate") then
            animation_start()
        end
    else
        if imgui.Button("Stop Animate") then
            animation_data.animating=false
        end
    end
    imgui.End()
    if animation_data.animating and sim_done then
        animation_tick()
    end
    __render_to_window()

    update_buffers()
    --[[
    for x=0,map_w-1 do
        for y=0,map_h-1 do
            local v=static_layer:get(x,y)
            if math.random()>0.99 and v.a>0 then
                print(x,y,math.abs(v.a-255*0.05))
            end
        end
    end
    --]]
    --[[
        scratch has "real data"
        draw from "scratch+old->new"
        draw from "new+empty->screen"
        swap new,old
    --]]
    draw_shader:use()
    local t1=scratch_tex:get()
    local t2=tex_pixel:get()
    local t_out=tex_pixel:get_next()
    static_layer:write_texture(t1)
    t1:use(0,0,1)
    t2:use(1,0,1)
    t_out:use(2,0,1)

    local want_decaying=true

    draw_shader:set_i("tex_main",0) --scratch
    draw_shader:set_i("tex_old",1) --old
    draw_shader:set_i("res",map_w,map_h)
    draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
    draw_shader:set("translate",config.t_x,config.t_y)
    draw_shader:set("decay",config.decay)
    if want_decaying then
        if sim_done then
            if not t_out:render_to(static_layer.w,static_layer.h) then --new
                error("failed to set framebuffer up")
            end
            if need_clear then
                __clear()
            else
                draw_shader:draw_quad()
            end
            __render_to_window()
            draw_shader:use()
        end
        t_out:use(2,0,1)
        draw_shader:set_i("tex_main",2)
        draw_shader:set_i("tex_old",5)
        draw_shader:set("decay",0)
        draw_shader:draw_quad()
        if need_clear then
            __clear()
        end
    else
        draw_shader:draw_quad()
    end
    if giffer and sim_done then
        if giffer:want_frame() then
            save_gif_frame()
        end
        giffer:frame(img_buf_save)
    end
    if need_save then
        save_img()
        need_save=false
    end
    if sim_done and want_decaying then tex_pixel:advance() end

    --need_clear=false
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
