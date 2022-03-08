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

--__set_window_size(win_w,win_h)
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
    {"transient_cutoff",0,type="float",min=0,max=2},
    {"decay",0,type="floatsci",power=0.01},
    {"block_size",10,type="int",min=0,max=50,watch=true},
    {"block_count",3,type="int",min=0,max=8,watch=true},
    {"block_offset",4,type="int",min=0,max=100,watch=true},
    {"angle",0,type="int",min=0,max=180,watch=true},
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

uniform vec3 c1;
uniform vec3 c2;
uniform vec3 c3;
uniform vec3 c4;

uniform float transient_cutoff;
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
    //vec3 c=palette(pa,vec3(0.8,0.5,0.4),vec3(0.2,0.4,0.2),vec3(2,1,1),vec3(0.0,0.25,0.25));
    //vec3 c=palette(pa,vec3(0.2,0.7,0.4),vec3(0.6,0.9,0.2),vec3(0.6,0.8,0.7),vec3(0.5,0.1,0.0));
    //vec3 c=palette(pa,vec3(0.5),vec3(0.5),vec3(0.6,0.6,0.2),vec3(0.1,0.7,0.3));
    //vec3 c=palette(pa,vec3(0.5),vec3(0.5),vec3(0.33,0.4,0.7),vec3(0.5,0.12,0.8));
    //vec3 c=palette(pa,vec3(0.5),vec3(0.5),vec3(0.5),vec3(0.5));
    //vec3 c=palette(pa,vec3(0.999032,0.259156,0.217277),vec3(0.864574,0.440455,0.0905941),vec3(0.333333,0.4,0.333333),vec3(0.111111,0.2,0.1)); //Dark red/orange stuff
    //vec3 c=palette(pa,vec3(0.884088,0.4138,0.538347),vec3(0.844537,0.95481,0.818469),vec3(0.875,0.875,1),vec3(3,1.5,1.5)); //white and dark and blue very nice
    //vec3 c=palette(pa,vec3(0.971519,0.273919,0.310136),vec3(0.90608,0.488869,0.144119),vec3(5,10,2),vec3(1,1.8,1.28571)); //violet and blue
    //vec3 c=palette(pa,vec3(0.960562,0.947071,0.886345),vec3(0.850642,0.990723,0.499583),vec3(0.1,0.2,0.111111),vec3(0.6,0.75,1)); //violet and yellow
    vec3 c=palette(pa,c1,c2,c2,c3);
    if(transient_cutoff>0)
    {
        if(particle_age<transient_cutoff)
            //c=vec3(0);
            c*=0.0;
            //c=vec3(1);
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
function get_nn_smooth( pos,dist )
    if dist<2 then
        return get_nn(pos,dist)
    end
    local cx=pos.r
    local cy=pos.g
    local ret=0
    local d=math.floor((dist-1)/2)
    local value=0
    --dir=1 {1,0}
    for y=-d,d do
        local tp=fix_pos({r=cx+dist,g=cy+y})
        local v=static_layer:get(tp.r,tp.g)
        if v.a>0 then
           value=value+math.pow(2,0)
           break
        end
    end
     --dir=3 {0,1}
    for x=-d,d do
        local tp=fix_pos({r=cx+x,g=cy+dist})
        local v=static_layer:get(tp.r,tp.g)
        if v.a>0 then
           value=value+math.pow(2,2)
           break
        end
    end
     --dir=5 {-1,0}
    for y=-d,d do
        local tp=fix_pos({r=cx-dist,g=cy+y})
        local v=static_layer:get(tp.r,tp.g)
        if v.a>0 then
           value=value+math.pow(2,4)
           break
        end
    end
     --dir=7 {0,-1}
    for x=-d,d do
        local tp=fix_pos({r=cx+x,g=cy-dist})
        local v=static_layer:get(tp.r,tp.g)
        if v.a>0 then
           value=value+math.pow(2,6)
           break
        end
    end

    --dir=2 {1,1}
    local d2_done=false
    for y=d+1,dist do
        local tp=fix_pos({r=cx+dist,g=cy+y})
        local v=static_layer:get(tp.r,tp.g)
        if v.a>0 then
           value=value+math.pow(2,1)
           d2_done=true
           break
        end
    end
    if not d2_done then
        for x=d+1,dist do
            local tp=fix_pos({r=cx+x,g=cy+dist})
            local v=static_layer:get(tp.r,tp.g)
            if v.a>0 then
               value=value+math.pow(2,1)
               d2_done=true
               break
            end
        end
    end
    --dir=4 {-1,1},
    local d4_done=false
    for y=d+1,dist do
        local tp=fix_pos({r=cx-dist,g=cy+y})
        local v=static_layer:get(tp.r,tp.g)
        if v.a>0 then
           value=value+math.pow(2,3)
           d4_done=true
           break
        end
    end
    if not d4_done then
        for x=-dist,d-1 do
            local tp=fix_pos({r=cx+x,g=cy+dist})
            local v=static_layer:get(tp.r,tp.g)
            if v.a>0 then
               value=value+math.pow(2,3)
               d4_done=true
               break
            end
        end
    end
    --dir=6 {-1,-1},
    local d6_done=false
    for y=-dist,d-1 do
        local tp=fix_pos({r=cx-dist,g=cy+y})
        local v=static_layer:get(tp.r,tp.g)
        if v.a>0 then
           value=value+math.pow(2,5)
           d6_done=true
           break
        end
    end
    if not d6_done then
        for x=-dist,d-1 do
            local tp=fix_pos({r=cx+x,g=cy-dist})
            local v=static_layer:get(tp.r,tp.g)
            if v.a>0 then
               value=value+math.pow(2,5)
               d6_done=true
               break
            end
        end
    end
    --[8]={1,-1},
    local d8_done=false
    for y=-dist,d-1 do
        local tp=fix_pos({r=cx+dist,g=cy+y})
        local v=static_layer:get(tp.r,tp.g)
        if v.a>0 then
           value=value+math.pow(2,7)
           d8_done=true
           break
        end
    end
    if not d8_done then
        for x=d+1,dist do
            local tp=fix_pos({r=cx+x,g=cy-dist})
            local v=static_layer:get(tp.r,tp.g)
            if v.a>0 then
               value=value+math.pow(2,7)
               d8_done=true
               break
            end
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
local rule_0_stops=true
function calculate_long_range_rule( pos )

    for r=2,config.long_dist_range do --original
    --for r=config.long_dist_range,2,-1 do --inverted
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
            if rule_0_stops then
                return 0 --more than one direction to move, so don't
            end
        elseif count_in_range==1 then
            --if r>4 then
            --    return rotate_dir(last_dir,config.long_dist_offset)
            --else
            if last_dir~=0 or rule_0_stops then
                return rotate_dir(last_dir,config.long_dist_offset)
            end
            --end
        end
    end
    return 0 --couldn't find any thing
end



function calculate_rule( pos )
    if #rules==0 then
        return math.random(0,8)
    else

        --[==[ inverted order (first check farthest then closer)
        local v=0
        if v==0 and config.long_dist_range>=2 then
            if config.long_dist_mode==0 then
            -- three choices here: simple long dist
                return calculate_long_range_rule(pos)
            elseif config.long_dist_mode==1 then
                --one rule for all dists
                for i=config.long_dist_range,2,-1 do
                    local v=get_nn(pos,i)
                    if v~=0 and long_rules[2] then
                        if long_rules[2][v]~=0 or rule_0_stops then
                            return long_rules[2][v]
                        end
                    end
                end
            else
                for i=config.long_dist_range,2,-1 do
                -- each dist has it's own rules
                    if long_rules[i] then
                        local v=get_nn(pos,i)
                        if v~=0 then
                            if long_rules[i][v]~=0 or rule_0_stops then
                                return long_rules[i][v]
                            end
                        end
                    end
                end
            end
        end
        v=get_nn(pos)
        return rules[v] or 0
        --]==]
        --[==[ normal 
        local v=get_nn(pos)
        local r=rules[v]
        if (v==0 or (r==0 and not rule_0_stops)) and config.long_dist_range>=2 then
            if config.long_dist_mode==0 then
            -- three choices here: simple long dist
                return calculate_long_range_rule(pos)
            elseif config.long_dist_mode==1 then
                --one rule for all dists
                for i=2,config.long_dist_range do
                    local v=get_nn(pos,i)
                    if v~=0 and long_rules[2] then
                        if long_rules[2][v]~=0 or rule_0_stops then
                            return long_rules[2][v]
                        end
                    end
                end
            else
                for i=2,config.long_dist_range do
                -- each dist has it's own rules
                    if long_rules[i] then
                        local v=get_nn(pos,i)
                        if v~=0 then
                            if long_rules[i][v]~=0 or rule_0_stops then
                                return long_rules[i][v]
                            end
                        end
                    end
                end
            end
        end

        return r or 0
        --]==]
        -- [==[ Smooth angle thingy
        local v=get_nn(pos)
        local r=rules[v]
        if (v==0 or (r==0 and not rule_0_stops)) and config.long_dist_range>=2 then
            if config.long_dist_mode==0 then
            -- three choices here: simple long dist
                --TODO
                return calculate_long_range_rule(pos)
            elseif config.long_dist_mode==1 then
                --one rule for all dists
                for i=2,config.long_dist_range do
                    local v=get_nn_smooth(pos,i)
                    if v~=0 and long_rules[2] then
                        if long_rules[2][v]~=0 or rule_0_stops then
                            return long_rules[2][v]
                        end
                    end
                end
            else
                for i=2,config.long_dist_range do
                -- each dist has it's own rules
                    if long_rules[i] then
                        local v=get_nn_smooth(pos,i)
                        if v~=0 then
                            if long_rules[i][v]~=0 or rule_0_stops then
                                return long_rules[i][v]
                            end
                        end
                    end
                end
            end
        end

        return r or 0
        --]==]
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
                if a>config.transient_cutoff then
                    if a>max_age then max_age=a end
                    if a<min_age then min_age=a end
                end
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
function gen_one_color( name,tbl,version)
    local v1,v2,v3
    version=version or 0
    if version==0 then
        v1=math.random()
        v2=math.random()
        v3=math.random()
    elseif version==1 then
        v1=math.random()*2
        v2=math.random()*2
        v3=math.random()*2
    elseif version==2 then
        local vtop=math.random(0,10)
        v1=vtop/math.random(1,10)
        v2=vtop/math.random(1,10)
        v3=vtop/math.random(1,10)
    end
    place_pixels_shader:set(name,v1,v2,v3)
    table.insert(tbl,v1)
    table.insert(tbl,v2)
    table.insert(tbl,v3)
end
local color_not_set=true
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
    place_pixels_shader:set("transient_cutoff",config.transient_cutoff)
    if need_rand_color or color_table==nil then
        local sformat="palette(pa,vec3(%g,%g,%g),vec3(%g,%g,%g),vec3(%g,%g,%g),vec3(%g,%g,%g));"
        local res={}
        gen_one_color("c1",res)
        gen_one_color("c2",res)
        gen_one_color("c3",res,2)
        gen_one_color("c4",res,2)
        --palette(pa,vec3(0.2,0.7,0.4),vec3(0.6,0.9,0.2),vec3(0.6,0.8,0.7),vec3(0.5,0.1,0.0));
        --print(string.format(sformat,unpack(res)))
        color_table=res
        need_rand_color=false
        color_not_set=false
    end
    if color_not_set and color_table then
        for i=0,3 do
            --print(i)
            place_pixels_shader:set("c"..(i+1),color_table[i*3+1],color_table[i*3+2],color_table[i*3+3])
        end
        color_not_set=false
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
    sav_tick_max=180,
    animating=false,
}
function animation_metatick(  )
    local a=animation_data
    a.sav_tick_current=a.sav_tick_current+1
    if a.sav_tick_current>=a.sav_tick_max then
        a.animating=false
    end

    --config.block_offset=config.block_offset-1
    config.angle=config.angle+5
    if config.angle>=180 then
        a.animating=false
        config.angle=0
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

function histogram( data,max_len)
    local max=0
    local max_namel=0
    local sum=0
    for k,v in pairs(data) do
        if max<v then
            max=v
        end
        sum=sum+v
        local n=tostring(k)
        if #n>max_namel then
            max_namel=#n
        end
    end

    for k,v in pairs(data) do
        local vn=v/max
        local vc=math.floor(vn*max_len)
        local vl=max_len-vc
        print(string.format("%"..max_namel.."s ",k)..string.rep('#',vc)..string.rep(' ',vl)..
            string.format("  %3d%%",(v/sum)*100))
    end
end
function add_count( tbl,e )
    if tbl[e]==nil then
        tbl[e]=1
    else
        tbl[e]=tbl[e]+1
    end
end
local sim_thread
function simulate_decay(  )
    local decay_data={}
    local no_repeats=1000
    local no_sim_ticks=40
    is_remade=true
    for i=1,no_repeats do
        for j=1,no_sim_ticks do
            coroutine.yield()
        end
        local radius=math.ceil((math.sqrt(2*config.block_size-1)+1)/2)
        local c,m=count_in_radius(map_w/2,map_h/2,radius+config.long_dist_range/2)
        print("Count:",c,c/m,"Iter:",i)
        add_count(decay_data,c)
        is_remade=true
        need_clear=true
        if (i%50)==49 then
            histogram(decay_data,20)
        end
        coroutine.yield()
    end
    histogram(decay_data,20)
    sim_thread=nil
end
function mask_has_dir(m,d)
    return bit.band(m,math.pow(2,d-1))==0
end
function generate_free_dir( mask )
    for i=1,1000 do
        local d=math.random(1,8)
        if mask_has_dir(mask,d) then
            return d
        end
    end
    print("failed to find free dir for ",mask)
    return 0
end
function count_in_radius(cx,cy,rad )
    local lx=cx-math.floor(rad/2)
    local hx=cy+math.ceil(rad/2)
    local count=0
    local visited=0
    for x=lx,hx do
        local dx=x-cx
        local ly=math.floor(cx-math.sqrt(rad*rad-dx*dx))
        local hy=math.ceil(cx+math.sqrt(rad*rad-dx*dx))
        for y=ly,hy do
            if static_layer:get(x,y).a~=0 then
                count=count+1
            end
            visited=visited+1
        end
    end
    return count,visited
end
function generate_rules( rule_tbl,overwrite )
    local pt=classify_patterns()
    local pt_rules={}
    for i,v in pairs(pt) do
        --[[
        if pt_rules[v.id]==nil then
            if v.sym==8  then
                pt_rules[v.id]={math.random(0,8),i}
            else
                pt_rules[v.id]={0,i}
            end
        end
        --]]
        local chance_0=0.5
        if pt_rules[v.id]==nil then
            if v.sym==8  then
                if math.random()>chance_0 then
                    pt_rules[v.id]={generate_free_dir(i),i}
                else
                    pt_rules[v.id]={0,i}
                end
            else
                pt_rules[v.id]={0,i}
            end
        end
    end

    if overwrite then
        for i,v in ipairs(overwrite) do
            pt_rules[v[1]]={v[2],i}
        end
    end

    local already_printed={}
    local only_print_non0=true
    local short_rules={}
    for i,v in ipairs(pt) do
        if not already_printed[v.id] then
            if v.sym==8 then
                local actual_dir=rotate_dir(pt_rules[v.id][1],v.rot)
                local is_free
                if actual_dir~=0 then
                    is_free=mask_has_dir(pt_rules[v.id][2],actual_dir)
                else
                    is_free=false
                end
                if not only_print_non0 or is_free then
                    print("Group id:",v.id)
                    print(concat_byline(value_to_nn_string(pt_rules[v.id][2]),dir_to_arrow_string(actual_dir)))
                    table.insert(short_rules,{v.id,actual_dir})
                end
                already_printed[v.id]=true
            end
        end
    end
    local r="rules:"
    for i,v in ipairs(short_rules) do
        if i~=1 then
            r=r..","
        end
        r=r..v[1]..":"..v[2]
    end
    print(r)
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
function generate_atom_layer( n )
    if n==0 then return {{0,0}} end
    local ret={}
    local y=0
    for x=n,1,-1 do
        table.insert(ret,{x,y})
        y=y-1
    end
    --y=y+1
    for x=0,-n+1,-1 do
        table.insert(ret,{x,y})
        y=y+1
    end
    --y=y+1
    for x=-n,-1,1 do
        table.insert(ret,{x,y})
        y=y+1
    end
    --y=y-1

    for x=0,n-1,1 do
        table.insert(ret,{x,y})
        y=y-1
    end

    return ret
end
for i=1,10 do
    print(#generate_atom_layer(i))
end
function diamond_spiral( t )
    --TODO
    --[[
        1
       042
      93015
       826
        7
    --]]
    local max_r=15
    local x=0
    local y=0
    if t==0 then return x,y end
    if t==1 then return x,y end

    local id_start=0
    local cur_level=0
    for i=1,max_r do
        local level_start=((2*i-1)*(2*i-1)+1)/2
        if t<=level_start then
            break
        end
        cur_level=i
        id_start=level_start
    end
    local remainder=t-id_start
    local side=math.floor(remainder/cur_level)
    local side_rem=remainder-side*cur_level
    print("Start:",t,id_start,cur_level,remainder)
    print("Side:",side,remainder-side*cur_level)
    --[[
        level    count start count per side
        0th level 1    0      -
        1st level 4    1      1
        2nd level 8    5      2
        3rd level 12  13      3
        4th level 16  25      4
    --]]
    local side_const={1,-1,1,-1}
    local side_off={-1,-1,1,1}
    local side_start={1,0,-1,0}

    x=side_start[side]*cur_level
    print(x)
end
function shuffle_table(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
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
    imgui.SameLine()
    if imgui.Button("Count") then
        local radius=(math.sqrt(2*config.block_size-1)+1)/2
        print("Rad:",radius,"Count",count_in_radius(map_w/2,map_h/2,radius*2))
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
        for k,v in pairs(long_rules) do
            local f=io.open("rules"..k..".txt","w")
            for i=1,255 do
                f:write(i," ",v[i],"\n")
            end
            f:close()
        end
    end
    imgui.SameLine()
    if imgui.Button("load rules") then
        local f=io.open("rules.txt","r")
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
            -- [[
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
            --]]
            --[[
            for i=0,current_particle_count-1 do
                local p=particles_pos:get(i,0)
                
                local x=p.r-math.floor(map_w/2)
                local y=p.g-math.floor(map_h/2)
                if x>0 then
                    particles_age:set(i,0,1)
                else
                    particles_age:set(i,0,0)
                end
            end
            --]]
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
            img_buf_save,5000,1)
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
        local no_places=0
        local cx=math.floor(map_w/2)
        local cy=math.floor(map_h/2)
        --[==[
        local count_add={0,10,4,6}
        local offset_add={0,8,17,22}
        local bcount_mod={1,3,1,1}
        --local angle_offset={0,math.pi/8,math.pi/4,3*math.pi/8}
        local angle_offset=(config.angle/180)*math.pi
        for kk=1,1 do
            local b_count=math.floor(config.block_count*bcount_mod[kk])
            local offset=math.floor(config.block_offset+offset_add[kk])


            for i=1,b_count do
                local v=(i-1)/b_count
                local bs=config.block_size+count_add[i]
                local hbs=math.floor(bs/2+0.5)
                local tx=math.floor(math.cos(v*math.pi*2+angle_offset)*offset+0.5)+cx-hbs
                local ty=math.floor(math.sin(v*math.pi*2+angle_offset)*offset+0.5)+cy-hbs

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
        local hbs=math.floor(config.block_size/2+0.5)
        no_places=math.floor(hbs*hbs*math.pi)

        while current_particle_count<config.block_count do
            local cx=math.floor(map_w/2)
            local cy=math.floor(map_h/2)

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
        -- [[
        local bs=config.block_size
        local cx_o=cx
        local cy_o=cy
        local o=config.block_offset
        local layer=0
        local randomize_last=true
        --print("Radius:",math.log(3*bs+1)/math.log(4))
        while bs>0 do
            local l=generate_atom_layer(layer)
            if randomize_last and #l>=bs then
                shuffle_table(l)
            end
            for i=1,math.min(#l,bs) do
                local d=l[i]
                local tx=cx+d[1]
                local ty=cy+d[2]
                particles_pos:set(current_particle_count,0,{tx,ty})
                if config.color_by_age then
                    particles_age:set(current_particle_count,0,0)
                end
                current_particle_count=current_particle_count+1
                if current_particle_count== max_particle_count-1 then
                    break
                end
            end
            bs=bs-#l
            layer=layer+1
        end
        --]]
        --[==[
        

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
                    if current_particle_count== max_particle_count-1 then
                        break
                    end
                end
            end
            if current_particle_count== max_particle_count-1 then
                break
            end
        end
        --]==]
        print("particle count:",current_particle_count,current_particle_count/no_places)
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
        --sim_done=true
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
    imgui.SameLine()
    if not sim_thread then
        if imgui.Button("Simulate") then
            sim_thread=coroutine.create(simulate_decay)
        end
    else
        if imgui.Button("Stop Simulate") then
            sim_thread=nil
        end
    end
    if imgui.Button("Randomize Color") then
        need_rand_color=true
    end
    imgui.End()
    if animation_data.animating and sim_done then
        animation_tick()
    end
    if sim_thread and sim_done then
        --print("!",coroutine.status(sim_thread))
        local ok,err=coroutine.resume(sim_thread)
        if not ok then
            print(err)
        end
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

    local want_decaying=false

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
