--[===[
2D CA but!:
    * no create/destroy! only move
    * if can't move, dont!
    * gen random rules, check out the "dynamics" and "meta-atoms"
    * "permutation city"
TODO:
    * fix saving
    * to fix saving fix stupid rule format (or atleast make a compact form)
    * add more "states" (i.e. non 1/0 but actually have 1/2/...)
    * more "laws of conservation"
    * simulate for each seed id and avg over them/do histogram?/probablity cloud?
    * remove requirement for symmetry, but add system center of mass 
        and rotate rules so it always points to it
    * k-means for:
        - automatic rule classification (e.g. is "stable", is "merging", is "dividing")
        - track atom locations
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
local MAX_ATOM_TYPES=4
local ALLOW_TRANSFORMATION=true
is_remade=false
local dist_logic_type="simple"
local max_particle_count=10000
current_particle_count=current_particle_count or 0

local history_avg_size=Grapher(1000)
history_avg_size:set_filter(10)
local history_avg_disp=Grapher(1000) --actually deviation
history_avg_disp:set_filter(10)
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
    {"transient_cutoff",0,type="float",min=0,max=2},
    {"decay",0,type="floatsci",power=0.01},
    {"seed",0,type="int",min=0,max=200000,watch=true},
    {"block_size",10,type="int",min=0,max=500,watch=true},
    {"block_count",3,type="int",min=0,max=8,watch=true},
    {"block_offset",4,type="int",min=0,max=100,watch=true},
    {"angle",0,type="int",min=0,max=180,watch=true},
    {"long_dist_mode",0,type="choice",choices={"simple","single","multiple","quadratic"}},
    {"long_dist_range",2,type="int",min=0,max=50},
    {"long_dist_range_count",2,type="int",min=0,max=5},
    {"long_dist_offset",0,type="int",min=0,max=7},
    {"zoom",1,type="float",min=1,max=10},
    {"t_x",0,type="float",min=0,max=1},
    {"t_y",0,type="float",min=0,max=1},
    },config)


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
    //c=clamp(c,0,1);
    //color=vec4(c,1);
    //color=vec4(mix(pixel.xyz,pix_old.xyz,0.7),1);
    color=vec4(pixel.xyz,1);
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
    col=vec4(c,particle_age);
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
function dx_to_dir( dx,dy )
    local anti_dx={
        [-1]={[-1]=6,[0]=5,[1]=4},
        [0]={[-1]=7,[0]=0,[1]=3},
        [1]={[-1]=7,[0]=1,[1]=2},
    }
    return anti_dx[dx][dy]
end
--[[
    432
    501
    678
--]]
rules=rules or {

}
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
function add_dir_to_ret( ret,dir,value )
    local nval=round((value/255)*(MAX_ATOM_TYPES-1))
    --last
    --ret[dir]=round((value/255)*(MAX_ATOM_TYPES))
    --max
    ret[dir]=math.max(ret[dir],nval)
    --min
    --[[
    if nval>0 then
        ret[dir]=math.min(ret[dir],nval)
    end
    --]]
    --avg
    --todo
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
function ids_to_string( tbl )
    for i,v in ipairs(tbl) do
        if v==0 then
            tbl[i]="*"
        else
            tbl[i]=tostring(v-1)
        end
    end
    return table.concat( tbl, "" )
end
function get_nn_ex( pos,dist )
    --local ret={}
    local value=0
    local ret={0,0,0,0,0,0,0,0}
    for i=1,8 do
        local t=displace_by_dir_nn(pos,i,dist)
        local v=static_layer:get(t.r,t.g)
        add_dir_to_ret(ret,i,v.a)
    end
    return ids_to_string(ret)
end

function get_nn_smooth( pos,dist )
    if dist<2 then
        return get_nn_ex(pos,dist)
    end
    local ret={0,0,0,0,0,0,0,0}
    local cx=pos.r
    local cy=pos.g
    local d=math.floor((dist-1)/2)
    local single_dir={1,3,5,7}
    for _,dir in ipairs(single_dir) do
        local delta=dir_to_dx[dir]
        for T=-d,d do
            local dx=dist
            local dy=T
            if delta[1]==0 then
                dx=T
                dy=dist*delta[2]
            else
                dx=dist*delta[1]
                dy=T
            end
            local tp=fix_pos({r=cx+dx,g=cy+dy})
            --print(dx,dy,dir,tp.r,tp.g)
            local v=static_layer:get(tp.r,tp.g)
            if v.a>0 then
               add_dir_to_ret(ret,dir,v.a)
               --break
            end
        end
    end
    local mixed_dir={2,4,6,8}
    for _,dir in ipairs(mixed_dir) do
        local done=false
        local delta=dir_to_dx[dir]

        local dx
        local sx,ex
        local dy
        local sy,ey

        if delta[1]<0 then
            sx=-dist
            ex=-d-1
        else
            sx=d+1
            ex=dist
        end
        dx=dist*delta[1]

        if delta[2]<0 then
            sy=-dist
            ey=-d-1
        else
            sy=d+1
            ey=dist
        end
        dy=dist*delta[2]

        for y=sy,ey do
            local tp=fix_pos({r=cx+dx,g=cy+y})
            local v=static_layer:get(tp.r,tp.g)
            --print(dir,tp.r-cx,tp.g-cy,round((v.a/255)*(MAX_ATOM_TYPES-1)))
            if v.a>0 then
               add_dir_to_ret(ret,dir,v.a)
               --done=true
               --break
            end
        end
        if not done then
            for x=sx,ex do
                local tp=fix_pos({r=cx+x,g=cy+dy})
                local v=static_layer:get(tp.r,tp.g)
                if v.a>0 then
                   add_dir_to_ret(ret,dir,v.a)
                   --done=true
                   --break
                end
            end
        end
    end

    return ids_to_string(ret)
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
function value_to_nn_string_ex( v )
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
        ret=ret..v:sub(vv,vv)
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
local rule_0_stops=false
function calculate_long_range_rule( pos )

    for r=2,config.long_dist_range do --original
    --for r=config.long_dist_range,2,-1 do --inverted
        local ret=get_nn_smooth(pos,r)
        local count_in_range=0
        local last_dir=0
        for i=1,8 do
            if ret[i]~="*" then
                count_in_range=count_in_range+1
                last_dir=i
            end
        end
        if count_in_range>1 then
            if rule_0_stops then
                return {0,0} --more than one direction to move, so don't
            end
        elseif count_in_range==1 then
            --if r>4 then
            --    return rotate_dir(last_dir,config.long_dist_offset)
            --else
            if last_dir~=0 or rule_0_stops then
                return {rotate_dir(last_dir,config.long_dist_offset),0}
            end
            --end
        end
    end
    return {0,0} --couldn't find any thing
end



function calculate_rule( pos )
    if #rules==0 then
        return {math.random(0,8),0}
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
        local v=get_nn_ex(pos,1)
        --print(v)
        local r=rule_lookup[1][v]
        if (v=="********" or (r[1]==0 and not rule_0_stops)) and config.long_dist_range>=2 then
            if config.long_dist_mode==0 then
            -- three choices here: simple long dist
                return calculate_long_range_rule(pos)
            else
                --one rule for all dists
                for i=2,config.long_dist_range do
                    local v=get_nn_smooth(pos,i)
                    --print("===================")
                    --print(v)
                    local r=rule_lookup[i]
                    if v~="********" and r then
                        if r[v][1]~=0 or rule_0_stops then
                            return r[v]
                        end
                    end
                end
            end

        end
        return r or {0,0}
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
        local tpos=displace_by_dir(pos,dir[1])
        local sl=static_layer:get(tpos.r,tpos.g)
        if sl.a>0 then
            dir={0,0}
            tpos=displace_by_dir(pos,dir[1])
        end
        trg_pos[i]={dir[1],tpos,dir[2]}
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
        local change=trg_pos[i][3]
        local tp=movement_layer_target:get(tpos.r,tpos.g)
        if tp<2 and dir~=0 then
            pos.r=tpos.r
            pos.g=tpos.g
            particles_pos:set(i,0,pos)
            local a=particles_age:get(i,0)
            --a=(a+change)%(MAX_ATOM_TYPES-1)+1
            local nval=a*MAX_ATOM_TYPES--round((a/255)*(MAX_ATOM_TYPES-1))
            if ALLOW_TRANSFORMATION then
                nval=(nval+change-1)%(MAX_ATOM_TYPES-1)+1
            end
            --print(a,nval,change,nval/MAX_ATOM_TYPES)
            particles_age:set(i,0,nval/MAX_ATOM_TYPES)
        else
            --movement_layer_target:set(tpos.r,tpos.g,tp-1)
        end
    end
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
    place_pixels_shader:blend_disable()
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
        gen_one_color("c2",res,1)
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
function rotate_pattern_left_ex(p)
    return p:sub(2)..p:sub(1,1)
    
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

function iter_choices( items,item_count )
    if item_count==1 then
        return items
    end

    local ret={}
    local nitems=iter_choices(items,item_count-1)

    for i,v1 in ipairs(items) do
        for _,v2 in ipairs(nitems) do
            table.insert(ret,v1..v2)
        end
    end
    return ret
end
function classify_patterns_adv(no_states)
    --print("=========================")
    local store_id=1
    local ret_patern_store={}
    local pattern_store={}
    local state_tbl={"*"}

    for i=0,no_states-1 do
        table.insert(state_tbl,tostring(i))
    end

    local all_choices=iter_choices(state_tbl,8)

    for i,v in ipairs(all_choices) do
        local old_pattern
        local rotation=0
        local rp=v
        for j=1,8 do
            rp=rotate_pattern_left_ex(rp)
            local sp=pattern_store[rp]
            if sp then
                old_pattern={id=sp.id,sym=sp.sym,rot=j,has_free_dir=sp.has_free_dir}
                ret_patern_store[v]=old_pattern
                break
            end
            if rp==v then
                rotation=j
                break
            end
        end
        if not old_pattern then
            local has_free_dir=v:find("*")~=nil
            pattern_store[v]={id=store_id,sym=rotation,rot=0,has_free_dir=has_free_dir}
            store_id=store_id+1
            ret_patern_store[v]=pattern_store[v]
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
    sim_tick_max=10000,
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
    config.angle=config.angle+1
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

function histogram( data,max_len,h,lh)
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
    local sorted={}
    for k,v in pairs(data) do
        local vn=v/max
        local vc=math.floor(vn*max_len)
        local vl=max_len-vc
        table.insert(sorted,{k,string.format("%"..max_namel.."s ",k)..string.rep('#',vc)..string.rep(' ',vl)..
            string.format("  %3d%%",(v/sum)*100),v/sum})
    end
    table.sort(sorted,function ( a,b )
        return a[1]>b[1]
    end)
    if lh then
        lh:write("{\n\t")
    end
    for i,v in ipairs(sorted) do
        print(v[2])
        if h then
            h:write(v[2])
            h:write("\n")
            h:flush()
        end
        if lh then
            lh:write(string.format("[%d]=%g, ",v[1],v[3]))
        end
    end
    if lh then
        lh:write("\n\t},\n")
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
function add_particles( buf )
    for i=0,current_particle_count-1 do
        local p=particles_pos:get(i,0)
        buf:set(p.r,p.g,buf:get(p.r,p.g)+1)
    end
end
function add_particles_complex( buf,theta,r )
    local c=math.cos(theta)*(r or 1)
    local s=math.sin(theta)*(r or 1)
    for i=0,current_particle_count-1 do
        local p=particles_pos:get(i,0)
        local v=buf:get(p.r,p.g)
        buf:set(p.r,p.g,{v.r+c,v.g+s})
    end
end
function remap_and_save( buf )
    local w=static_layer.w
    local h=static_layer.h
    local img_buf=make_image_buffer(w,h)
    local max=0
    for x=0,w-1 do
        for y=0,h-1 do
            local v=buf:get(x,y)
            if v>max then max=v end
        end
    end
    for x=0,w-1 do
        for y=0,h-1 do
            local v=buf:get(x,y)
            v=math.floor((v/max)*255)
            img_buf:set(x,y,{v,v,v,255})
        end
    end
    img_buf:save("out.png")
end
function remap_and_save_complex( buf )
    local w=static_layer.w
    local h=static_layer.h
    local img_buf=make_image_buffer(w,h)
    local max=0
    for x=0,w-1 do
        for y=0,h-1 do
            local v=buf:get(x,y)
            local ls=v.r*v.r+v.g*v.g
            if ls>max then max=ls end
        end
    end
    max=math.sqrt(max)
    for x=0,w-1 do
        for y=0,h-1 do
            local v=buf:get(x,y)
            v=math.sqrt(v.r*v.r+v.g*v.g)/max
            v=math.floor(v*255)
            img_buf:set(x,y,{v,v,v,255})
        end
    end
    img_buf:save("out.png")
end
function count_by_type()
    local ret={}
    local w=static_layer.w
    local h=static_layer.h
    for x=0,w-1 do
        for y=0,h-1 do
            local a=static_layer:get(x,y).a
            if ret[a] then
                ret[a]=ret[a]+1
            else
                ret[a]=1
            end
        end
    end
    return ret
end
function simulate_cloud3(  )
    local max_seed=1000
    local buffer=make_flt_half_buffer(static_layer.w,static_layer.h)

    for k=0,max_seed do
        config.seed=k
        is_remade=true
        local no_sim_ticks=100
        for j=1,no_sim_ticks do
            coroutine.yield()
        end
        local ret=count_by_type()
        local c_last=ret[255] or 0
        add_particles_complex(buffer,math.pi*(c_last)/(4))
    end

    remap_and_save_complex(buffer)
    sim_thread=nil
end
function simulate_cloud2(  )
    local bc_start=364
    local bc_end=440
    local max_seed=100
    local buffer=make_flt_half_buffer(static_layer.w,static_layer.h)
    for i=bc_start,bc_end do
        config.block_size=i
        for k=0,max_seed do
            config.seed=k
            is_remade=true
            local no_sim_ticks=100
            for j=1,no_sim_ticks do
                coroutine.yield()
            end
            add_particles_complex(buffer,math.pi*(i-bc_start)/(bc_end-bc_start))
        end
    end
    remap_and_save_complex(buffer)
    sim_thread=nil
end
function simulate_cloud(  )
    local num_seeds=500
    local buffer=make_float_buffer(static_layer.w,static_layer.h)
    for i=1,num_seeds do
        config.seed=i
        is_remade=true
        local no_sim_ticks=100
        for j=1,no_sim_ticks do
            coroutine.yield()
        end
        add_particles(buffer)
    end
    remap_and_save(buffer)
    sim_thread=nil
end
function simulate_decay(  )
    local start_s=2
    local end_s=50
    local h=io.open("hist_log.txt","a")
    local lh=io.open("hist_log.ldat","w")
    lh:write("particle_stats={\n")
    for bs=start_s,end_s do
        print("Block size:",bs)
        h:write("================Size:",bs,"\n")
        config.block_size=bs
        local decay_data={}
        local no_repeats=100
        local no_sim_ticks=40
        is_remade=true
        for i=1,no_repeats do
            for j=1,no_sim_ticks do
                coroutine.yield()
            end
            local radius=math.ceil((math.sqrt(2*config.block_size-1)+1)/2)
            local c,m=count_in_radius(map_w/2,map_h/2,radius+config.long_dist_range/2)
            --print("Count:",c,c/m,"Iter:",i)
            add_count(decay_data,c)
            is_remade=true
            need_clear=true
            --if (i%50)==49 then
            --    histogram(decay_data,20)
            --end
            coroutine.yield()
        end
        lh:write(string.format("[%d]=",bs))
        histogram(decay_data,20,h,lh)
    end
    lh:write("}")
    lh:close()
    h:close()
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
function mask_has_dir_ex(m,d)
    return string.sub(m,d,d)=="*"
end
function generate_free_dir_ex( mask )
    for i=1,1000 do
        local d=math.random(1,8)
        if mask_has_dir_ex(mask,d) then
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
function count_in_sectors(cx,cy,r)

    local ret={[0]=0,0,0,0,0,0,0,0,0}

    local lx=cx-r
    local hx=cx+r
    local ly=cy-r
    local hy=cy+r

    local count=0
    local visited=0

    for x=0,map_w-1 do
        local mx=0
        if x<lx then
            mx=-1
        elseif x>hx then
            mx=1
        end
        for y=0,map_h-1 do
            local my=0
            if y<ly then
                my=-1
            elseif y>hy then
                my=1
            end
            if static_layer:get(x,y).a~=0 then
                local v=dx_to_dir(mx,my)
                ret[v]=ret[v]+1
            end
        end
    end
    return ret
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
                    --print("Group id:",v.id)
                    --print(concat_byline(value_to_nn_string(pt_rules[v.id][2]),dir_to_arrow_string(actual_dir)))
                    table.insert(short_rules,{v.id,actual_dir})
                end
                already_printed[v.id]=true
            end
        end
    end
    --[[
    local r="rules:"
    for i,v in ipairs(short_rules) do
        if i~=1 then
            r=r..","
        end
        r=r..v[1]..":"..v[2]
    end
    --print(r)
    --]]
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
function generate_rules_ex( rule_tbl,patterns,overwrite )
    local pt_rules={}
    for i,v in pairs(patterns) do
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
            if v.sym==8 and v.has_free_dir then
                if math.random()>chance_0 then
                    pt_rules[v.id]={generate_free_dir_ex(i),i,math.random(0,MAX_ATOM_TYPES-1)}
                else
                    pt_rules[v.id]={0,i,0}
                end
            else
                pt_rules[v.id]={0,i,0}
            end
        end
    end
    if overwrite then
        for i,v in ipairs(overwrite) do
            pt_rules[v[1]]={v[2],i,0}
        end
    end

    local already_printed={}
    local only_print_non0=true
    local short_rules={}
    print("========================================")
    for i,v in pairs(patterns) do
        if not already_printed[v.id] then
            if v.sym==8 then
                local actual_dir=rotate_dir(pt_rules[v.id][1],v.rot)
                local is_free
                if actual_dir~=0 then
                    is_free=mask_has_dir_ex(pt_rules[v.id][2],actual_dir)
                else
                    is_free=false
                end
                if not only_print_non0 or is_free then
                    print("Group id:",v.id)
                    print(concat_byline(value_to_nn_string_ex(pt_rules[v.id][2]),dir_to_arrow_string(actual_dir)))
                    table.insert(short_rules,{v.id,actual_dir})
                end
                already_printed[v.id]=true
            end
        end
    end
    
    --[[
    local r="rules:"
    for i,v in ipairs(short_rules) do
        if i~=1 then
            r=r..","
        end
        r=r..v[1]..":"..v[2]
    end
    print(r)
    --]]
    for i,v in pairs(patterns) do
        -- [[
        if v.sym==8  then
            rule_tbl[i]={rotate_dir(pt_rules[v.id][1],v.rot),pt_rules[v.id][3]}
        else
            rule_tbl[i]={0,0}
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
function prime(n)
    for i = 2, n^(1/2) do
        if (n % i) == 0 then
            return false
        end
    end
    return true
end
function is_triangular( k )
    local v=8*k+1
    local vs=math.floor(math.sqrt(v))

    return v==vs*vs
end
function is_triangular2( k )
    --sequence in form 1on,1off, 2on,2off, 3on,3off...
    local v=(math.sqrt(1+4*k)-1)/2
    local off=v-math.floor(v)
    return off<0.5

end
function update_rule_lookup(  )
    rule_lookup={}
    for i,v in ipairs(rules) do
        for i=v.rlow,v.rhigh do
            rule_lookup[i]=v.rules
        end
    end
end
function rand_rules(  )
    math.randomseed(os.time())
    math.random()
    math.random()
    math.random()
    rules={}
    local patterns=classify_patterns_adv(MAX_ATOM_TYPES)

    local close_rules={}
    close_rules[0]=0
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
    generate_rules_ex(close_rules,patterns)--,{{1,0},{2,0}})
    table.insert(rules,{rlow=1,rhigh=1,rules=close_rules})

    if config.long_dist_mode==2 then
        local range_size=math.floor(config.long_dist_range/(config.long_dist_range_count))
        for i=1,config.long_dist_range_count do
            local new_rules={}
            new_rules[0]=0
            generate_rules_ex(new_rules,patterns)
            if i==1 then
                rules[#rules].rhigh=rules[#rules].rlow
            else
                rules[#rules].rhigh=rules[#rules].rlow+range_size
            end
            table.insert(rules,{rlow=rules[#rules].rhigh+1,rules=new_rules})
        end
    elseif config.long_dist_mode==1 then
        local new_rules={}
        new_rules[0]=0
        generate_rules_ex(new_rules,patterns)
        rules[#rules].rhigh=rules[#rules].rlow
        table.insert(rules,{rlow=rules[#rules].rhigh+1,rules=new_rules})
    elseif config.long_dist_mode==3 then
        local lmax=math.floor(math.sqrt(config.long_dist_range))
        for i=1,config.long_dist_range_count do
            local new_rules={}
            new_rules[0]=0
            generate_rules_ex(new_rules,patterns)
            if i==1 then
                rules[#rules].rhigh=rules[#rules].rlow
            else
                rules[#rules].rhigh=math.floor(math.pow(i*lmax/(config.long_dist_range_count+1),2))+1
            end
            table.insert(rules,{rlow=rules[#rules].rhigh+1,rules=new_rules})
        end
    end
    rules[#rules].rhigh=config.long_dist_range
    update_rule_lookup()
    --]==]
    is_remade=true
    need_clear=true
end
function update_stats()
    local center=Point(0,0)
    for i=0,current_particle_count-1 do
        local p=particles_pos:get(i,0)
        center=center+Point(p.r,p.g)
    end
    center=center/current_particle_count
    local avg_dist=0
    for i=0,current_particle_count-1 do
        local p=particles_pos:get(i,0)
        local d=center-Point(p.r,p.g)
        avg_dist=avg_dist+d:len()
    end
    avg_dist=avg_dist/current_particle_count
    local avg_disp=0
    for i=0,current_particle_count-1 do
        local p=particles_pos:get(i,0)
        local d=center-Point(p.r,p.g)
        local dd=avg_dist-d:len()
        avg_disp=avg_disp+dd*dd
    end
    avg_disp=avg_disp/current_particle_count
    history_avg_size:add_value(avg_dist)
    history_avg_disp:add_value(math.sqrt(avg_disp))
end
function place_atom_wlayers( target_x,target_y,size,seed )
    local bs=size
    local cx_o=target_x
    local cy_o=target_y
    local layer=0
    local randomize_last=true
    local do_skip_layer= function (l)
        --[[ even
            return l%2==1
        --]]
        --[[ odd
            return l%2==0
        --]]
        --return l%3~=0
        --return (l*l+2*l)%3~=0
        --return prime(l*l+1)
        --return not prime(l*l+1)
        return is_triangular2(l)
    end
    --print("Radius:",math.log(3*bs+1)/math.log(4))
    --print("Radius:",(math.sqrt(2*config.block_size-1)+1)/2)
    math.randomseed (seed or config.seed)
    last_layer_fill=0
    while bs>0 do
        --atom_type=(math.pow(atom_type,5))*MAX_ATOM_TYPES
        local l=generate_atom_layer(layer)
        while do_skip_layer(layer) do
            layer=layer+1
            l=generate_atom_layer(layer)
        end
        local atom_type=math.random(1,MAX_ATOM_TYPES)
        if randomize_last and #l>=bs then
            shuffle_table(l)
        end
        for i=1,math.min(#l,bs) do
            local d=l[i]
            local tx=cx_o+d[1]
            local ty=cy_o+d[2]
            particles_pos:set(current_particle_count,0,{tx,ty})
            local variation=0--0.025*math.random()/(MAX_ATOM_TYPES+1);
            particles_age:set(current_particle_count,0,atom_type/MAX_ATOM_TYPES+variation)
            current_particle_count=current_particle_count+1
            if current_particle_count== max_particle_count-1 then
                break
            end
        end
        if bs>#l then
            last_layer_fill=1
        else
            last_layer_fill=bs/#l
        end
        bs=bs-#l
        layer=layer+1
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
    imgui.SameLine()
    if imgui.Button("Count") then
        local radius=(math.sqrt(2*config.block_size-1)+1)/2
        --print("Rad:",radius,"Count",count_in_radius(map_w/2,map_h/2,radius*2))
        print("Rad:",radius)
        local c=count_in_sectors(math.floor(map_w/2),math.floor(map_h/2),radius*1.5)
        for i=0,8 do
            print(" "..i.." "..c[i])
        end
    end
    local sim_done=false
    if imgui.Button("step") then
        sim_tick()
        sim_done=true
    end
    if imgui.Button("rand rules") then
        rand_rules()
    end
    imgui.SameLine()
    --[[
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
    --]]
    if imgui.Button("save rules") then
        local f=io.open("rules.lrul","w")
        f:write(string.format(
[[
config.long_dist_range=%d
config.long_dist_mode=%d
config.long_dist_range_count=%d
config.long_dist_offset=%d
]]
,config.long_dist_range,config.long_dist_mode,config.long_dist_range_count,config.long_dist_offset))
        f:write("rules={\n")
        for i,v in ipairs(rules) do
            f:write(string.format("\t{ rlow=%d, rhigh=%d, rules={\n\t\t",v.rlow,v.rhigh))
             for k,j in pairs(v.rules) do
                if j~=0 then
                    f:write(string.format("%q={%d, %d},\n",k,j[1],j[2]))
                end
            end
            f:write("}\n\t},\n")
        end
        f:write("}")
        f:close()
    end
    imgui.SameLine()
    --[[if imgui.Button("load rules") then
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
    end--]]
    if imgui.Button("load rules") then
        dofile"rules.lrul"
        for k,v in pairs(rules) do
            for i=1,255 do
                if v.rules[i]==nil then
                    v.rules[i]=0
                end
            end
        end
        update_rule_lookup()
    end
    imgui.SameLine()
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
        history_avg_disp:clear()
        history_avg_size:clear()
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
                current_particle_count=current_particle_count+1
            else
                not_place_count=not_place_count+1
            end
            if not_place_count>1000 then
                break
            end
        end
        --]==]
        --[[
        place_atom_wlayers(cx,cy,config.block_size,config.seed)
        --]]
        -- [[
        local delta=config.block_offset
        local angle_offset=(config.angle/180)*math.pi
        local c=math.cos(angle_offset)*delta
        local s=math.sin(angle_offset)*delta
        place_atom_wlayers(math.floor(cx-c),math.floor(cy-s),config.block_size,config.seed)
        place_atom_wlayers(math.floor(cx+c),math.floor(cy+s),config.block_size,config.seed)
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
        --print("particle count:",current_particle_count,current_particle_count/no_places)
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
           -- sim_thread=coroutine.create(simulate_decay)
           --sim_thread=coroutine.create(simulate_cloud2)
           sim_thread=coroutine.create(simulate_cloud3)
           --sim_thread=coroutine.create(simulate_cloud)
        end
    else
        if imgui.Button("Stop Simulate") then
            sim_thread=nil
        end
    end
    if imgui.Button("Randomize Color") then
        need_rand_color=true
    end
    if sim_done then
        update_stats()
    end
    history_avg_size:draw("size history")
    history_avg_disp:draw("deviation history")
    imgui.End()
    if animation_data.animating and sim_done then
        animation_tick()
    end
    if sim_thread and sim_done then
        --print("!",coroutine.status(sim_thread))
        local ok,err=coroutine.resume(sim_thread)
        if not ok then
            print("Error:",err)
            sim_thread=nil
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

    local want_decaying=(config.decay>0)

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
