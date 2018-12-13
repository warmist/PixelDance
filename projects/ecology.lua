require 'common'
require 'bit'
local win_w=768
local win_h=768
--640x640x1 ->40fps (90fps??)
--640x640 b=80 ->40/45fps
--1280x1280 b=80 ->10/40fps
--1280x1280 b=0 ->10/8fps
--1280x1280 b=8 ->9/70fps
--1280*4x1280 b=8 ->4/14fps ->28fps no draw

__set_window_size(win_w,win_h)
local oversample=0.5

local map_w=(win_w*oversample)
local map_h=(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size


is_remade=false
local block_size=8--640,320,160,80
print("Block count:",(map_w/block_size)*(map_h/block_size))
function update_img_buf(  )
    local nw=math.floor(map_w)
    local nh=math.floor(map_h)

    if img_buf==nil or img_buf.w~=nw or img_buf.h~=nh then
        img_buf=make_image_buffer(nw,nh)
        sun_buffer=make_flt_buffer(nw,nh)
        block_alive=make_char_buffer(nw/block_size,nh/block_size)
        is_remade=true
    end
end
function set_pixel( x,y,pixel )
    if x<0 or y<0 or x>=img_buf.w or y>=img_buf.h then
        error("invalid pixel to set")
    end
    img_buf:set(x,y,pixel)
end
function get_pixel( x,y )
    return img_buf:get(x,y)
end
update_img_buf()
config=make_config({
    {"pause",false,type="bool"},
    {"draw",true,type="bool"},
    {"color",{0.63,0.59,0.511,0.2},type="color"},
    {"color_misc",{0.63,0.59,0.511,0.2},type="color"},
    {"zoom",1,type="float",min=1,max=10},
    {"t_x",0,type="float",min=0,max=1},
    {"t_y",0,type="float",min=0,max=1},
    {"opacity",1,type="float",min=0,max=1},
    {"air_opacity",0,type="float",min=0,max=1},
    {"timelapse",0,type="int",min=0,max=1000},
    },config)
local draw_shader=shaders.Make[==[
#version 330
#line 59
out vec4 color;
in vec3 pos;

uniform ivec2 rez;
uniform vec4 sun_color;
uniform sampler2D tex_main;
uniform sampler2D tex_sun;
uniform vec2 zoom;
uniform vec2 translate;

#define M_PI 3.141592

float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}
// ----------------------------------------------------------------------------
vec2 Hammersley(uint i, uint N)
{
    return vec2(float(i)/float(N), RadicalInverse_VdC(i));
}

float random (vec2 st) {
    return fract(sin(dot(st.xy,
                         vec2(12.9898,78.233)))*
        43758.5453123);
}
float is_lit(vec2 p)
{
    vec4 hsun=texture(tex_sun,vec2(p.x,p.y));
    return (hsun.r+hsun.b+hsun.g)/3;
}
vec4 raycast(vec2 o,vec2 d)
{
    int ray_len=300;
    float ray_step=0.002;
    vec2 p=o+d*ray_step;
    vec4 occ=vec4(1);
    for(int i=0;i<ray_len;i++)
    {
        p+=d*ray_step;
        vec4 v=texture(tex_main,p);

        occ*=vec4(v.rgb,1-v.a);
        /*if(v.a>0)
            occ+=pow(v.rgb,vec3(0.2));
        else
            occ*=vec3(0.9999);*/
    }
    return occ;
}
vec3 calc_light(vec2 pos)
{
    int max_iter=64;
    vec3 l=vec3(0);

    for(int i=0;i<max_iter;i++)
    {
        float a=Hammersley(i,max_iter).x*M_PI*2;
        l+=raycast(pos,vec2(cos(a),sin(a))).xyz;
    }
    return l/max_iter;
}
vec4 calc_light2(vec2 pos)
{
    vec4 l=vec4(0);
    for(int i=0;i<rez.x;i++)
    {
        vec2 dir=vec2(float(i)/float(rez.x),0)-pos;
        dir/=length(dir);
        l+=raycast(pos,dir);
    }
    return l;
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    normed=normed/zoom+translate;
    vec4 sun=texture(tex_sun,vec2(normed.x,normed.y));
    vec4 pixel=texture(tex_main,normed);
    if(pixel.a==0)
        color=vec4(sun.xyz,1);
    else
        color=vec4(pixel.xyz,1);
}
]==]
function is_valid_coord( x,y )
    return x>=0 and y>=0 and x<img_buf.w and y<img_buf.h
end
function fract_move(cell, dist,dir )
    cell.fract=cell.fract+dist*dir
    local step=Point(0,0)
    if cell.fract[1]>1 then
        step[1]=1
        cell.fract[1]=cell.fract[1]-1
    elseif cell.fract[1]<-1 then
        step[1]=-1
        cell.fract[1]=cell.fract[1]+1
    end

    if cell.fract[2]>1 then
        step[2]=1
        cell.fract[2]=cell.fract[2]-1
    elseif cell.fract[2]<-1 then
        step[2]=-1
        cell.fract[2]=cell.fract[2]+1
    end
    return step
end
function fract_move4(cell, dist,dir )
    cell.fract=cell.fract+dist*dir
    local step=Point(0,0)
    local function move_x(  )
        if cell.fract[1]>1 then
            step[1]=1
            cell.fract[1]=cell.fract[1]-1
            return true
        elseif cell.fract[1]<-1 then
            step[1]=-1
            cell.fract[1]=cell.fract[1]+1
            return true
        end
    end

    local function move_y(  )
        if cell.fract[2]>1 then
            step[2]=1
            cell.fract[2]=cell.fract[2]-1
            return true
        elseif cell.fract[2]<-1 then
            step[2]=-1
            cell.fract[2]=cell.fract[2]+1
            return true
        end
    end
    if math.random()>0.5 then
        if not move_x() then
            move_y()
        end
    else
        if not move_y() then
            move_x()
        end
    end
    return step
end
function remove_dead_addnew(tbl,new_tbl)
    local tbl_end=#tbl
    local i=1
    while i<=tbl_end do
        if tbl[i].dead then
            tbl[i]=tbl[tbl_end]
            tbl[tbl_end]=nil
            tbl_end=tbl_end-1
        else
            i=i+1
        end
    end
    if new_tbl then
        for i,v in ipairs(new_tbl) do
            tbl_end=tbl_end+1
            tbl[tbl_end]=v
        end
    end
end
local directions8={
    {-1,-1},
    {0,-1},
    {1,-1},
    {1,0},
    {1,1},
    {0,1},
    {-1,1},
    {-1,0},
}
local directions4={
    {0,-1},
    {1,0},
    {0,1},
    {-1,0},
}
--[[
    pixel flags:
        sand/liquid/wall (2 bits?)
        block light (1 bit)
    left:
        5 bits-> 32 types
--]]
ph_wall=0
ph_sand=1
ph_liquid=2
--ph_gas=3
local flag_sets={
    [0]=0,--wall_block
    0, --wall_pass
    --
    0, --sand_block
    0, --sand_pass
    --
    0, --liquid_block
    0, --liquid_pass
}
function is_block_light( id )
    return bit.band(bit.rshift(id,5),1)~=0
end
function get_physics( id )
    return bit.band(bit.rshift(id,6),3)
end
function next_pixel_type_id( pixel_physics,block_light )
    local flag_id=bit.bor(block_light,bit.lshift(pixel_physics,1))
    flag_sets[flag_id]=flag_sets[flag_id]+1
    return bit.bor(bit.lshift(flag_id,5),flag_sets[flag_id])
end
local pixel_types={ --alpha used to id types
    sand         ={124,100,80 ,next_pixel_type_id(ph_sand  ,1)},
    dead_plant   ={50 ,20 ,30 ,next_pixel_type_id(ph_sand  ,1)},
    water        ={70 ,70 ,150,next_pixel_type_id(ph_liquid,0)},
    wall         ={20 ,80 ,100,next_pixel_type_id(ph_wall  ,1)},
    plant_seed   ={10 ,150,50 ,next_pixel_type_id(ph_wall  ,0)},
    worm_body    ={255,100,80 ,next_pixel_type_id(ph_wall  ,1)},
    tree_trunk   ={40 ,10 ,255,next_pixel_type_id(ph_wall  ,1)},
    plant_body   ={50 ,180,20 ,next_pixel_type_id(ph_wall  ,1)},
    plant_fruit  ={230,90 ,20 ,next_pixel_type_id(ph_wall  ,1)},
    mycelium     ={150,150,150,next_pixel_type_id(ph_wall  ,1)},
    mushroom     ={250,175,255,next_pixel_type_id(ph_wall  ,1)},
    spore        ={160,40 ,40 ,next_pixel_type_id(ph_wall  ,0)},
}
for k,v in pairs(pixel_types) do
    print(k,v[4],get_physics(v[4]),is_block_light(v[4]))
end
--TODO: test for id collisions

function wake_blocks(  )
    local bw=img_buf.w/block_size
    local bh=img_buf.h/block_size
    for bx=0,bw-1 do
    for by=0,bh-1 do
        local ba=block_alive:set(bx,by,1)
    end
    end
end
function pixel_init(  )
    local w=img_buf.w
    local h=img_buf.h
    local cx = math.floor(w/2)
    local cy = math.floor(h/2)

    for i=1,w*h*0.1 do
        local x=math.random(0,w-1)
        local y=math.random(0,h-1)
        set_pixel(x,y,pixel_types.sand)
    end
    for i=1,w*h*0.1 do
        local x=math.random(0,w-1)
        local y=math.random(0,h-1)
        set_pixel(x,y,pixel_types.dead_plant)
    end
    --[[
    for i=1,5 do
        local platform_size=math.random(100,200)
        local x=math.random(0,w-1)
        local y=math.random(0,h-1)
        for i=1,platform_size do
            local d=directions4[math.random(1,#directions4)]
            local tx=x+d[1]
            local ty=y+d[2]
            if is_valid_coord(tx,ty) then
                x=tx
                y=ty
                set_pixel(tx,ty,pixel_types.water)
            end
        end
    end
    --]]
    -- [[
    for i=1,5 do
        local platform_size=math.random(100,200)
        local x=math.random(0,w-1)
        local y=math.random(0,h-1)
        for i=1,platform_size do
            local d=directions4[math.random(1,#directions4)]
            local tx=x+d[1]
            local ty=y+d[2]
            if is_valid_coord(tx,ty) then
                x=tx
                y=ty
                set_pixel(tx,ty,pixel_types.wall)
            end
        end
    end
    --]]

    wake_blocks()
    --[[ h wall
    local wall_size = 8
    for i=1,5 do
        local x=math.random(0,w-1)
        local y=math.random(0,h-1-wall_size)
        for i=0,wall_size do
            set_pixel(x,y+i,pixel_types.wall)
        end
    end
    ]]
end
if is_remade then
pixel_init()
end

function swap_pixels( x,y,tx,ty )
    local d=get_pixel(tx,ty)
    local dd={d.r,d.g,d.b,d.a}
    set_pixel(tx,ty,get_pixel(x,y))
    set_pixel(x,y,dd)
end
function update_sun(  )
    local w=img_buf.w
    local h=img_buf.h
    local s=config.color
    local p=config.opacity
    local decay=math.pow(10,-config.air_opacity/100)
    for x=0,w-1 do
        local ray_pixel={s[1],s[2],s[3],1}
        sun_buffer:set(x,h-1,ray_pixel)
    end
    -- [[
    for y=h-2,0,-1 do

        for x=0,w-1 do
            local ray_pixel={0,0,0,1}
            for dx=-1,1 do
                local p
                if x+dx>0 and x+dx<w-1 then
                    p=sun_buffer:get(x+dx,y+1)
                    ray_pixel[1]=ray_pixel[1]+p.r/3
                    ray_pixel[2]=ray_pixel[2]+p.g/3
                    ray_pixel[3]=ray_pixel[3]+p.b/3
                else
                    ray_pixel[1]=ray_pixel[1]+s[1]/3
                    ray_pixel[2]=ray_pixel[2]+s[2]/3
                    ray_pixel[3]=ray_pixel[3]+s[3]/3
                end
            end
            local c=get_pixel(x,y)
            if is_block_light(c.a) then
                ray_pixel[1]=ray_pixel[1]*math.pow((c.r/255),p)
                ray_pixel[2]=ray_pixel[2]*math.pow((c.g/255),p)
                ray_pixel[3]=ray_pixel[3]*math.pow((c.b/255),p)
            end
            for i=1,3 do
                ray_pixel[i]=ray_pixel[i]*decay
            end
            sun_buffer:set(x,y,ray_pixel)
        end
    end
    --]]
end
function count_pixels_around4( x,y,ptype )
    local count=0
    for i,v in ipairs(directions4) do
        local tx = x+v[1]
        local ty = y+v[2]
        if is_valid_coord(tx,ty) then
            if get_pixel(tx,ty).a==ptype then
                count=count+1
            end
        end
    end
    return count
end
function count_pixels_around8( x,y,ptype )
    local count=0
    for i,v in ipairs(directions8) do
        local tx = x+v[1]
        local ty = y+v[2]
        if is_valid_coord(tx,ty) then
            if get_pixel(tx,ty).a==ptype then
                count=count+1
            end
        end
    end
    return count
end

function wake_block( bx,by,tx,ty )

    local tbx=math.floor(tx/block_size)
    local tby=math.floor(ty/block_size)
    
    if tbx~=bx or tby~=by then
        block_alive:set(tbx,tby,1)
    end
    --[[
    local lx=tx-tbx*block_size
    local ly=ty-tby*block_size
    if lx==0 and tx>0 then
        block_alive:set(tbx-1,tby,1)
    elseif lx==block_size-1 and tbx<block_alive.w then
        block_alive:set(tbx+1,tby,1)
    end
    if ly==0 and ty>0 then
        block_alive:set(tbx,tby-1,1)
    elseif ly==block_size-1 and tby<block_alive.h then
        block_alive:set(tbx,tby+1,1)
    end
    --]]
end
function wake_near_blocks( bx,by )
    for i,v in ipairs(directions8) do
        local tbx=bx+v[1]
        local tby=by+v[2]
        if tbx>=0 and tby>=0 and tbx<block_alive.w and tby<block_alive.h then
            block_alive:set(tbx,tby,1)
        end
    end
end
function wake_pixel(tx,ty )
    local tbx=math.floor(tx/block_size)
    local tby=math.floor(ty/block_size)
    block_alive:set(tbx,tby,1)
end
function calculate_block(bx,by)
    local w=img_buf.w
    local h=img_buf.h

    local bxl=bx*block_size
    local bxh=(bx+1)*block_size
    local byl=by*block_size
    local byh=(by+1)*block_size

    local no_move=true
    for x=bxl,bxh-1 do
        for y=byl,byh-1 do
            local c=get_pixel(x,y)
            local ph=get_physics(c.a)

            if ph==ph_sand and y>0 then
                local ty=y-1
                local tx=x
                local d=get_pixel(tx,ty)
                if d.a==0 then
                    set_pixel(tx,ty,c)
                    set_pixel(x,y,{0,0,0,0})
                    wake_block(bx,by,tx,ty)
                    no_move=false
                elseif get_physics(d.a)==ph_liquid then
                    swap_pixels(x,y,tx,ty)
                    wake_block(bx,by,tx,ty)
                    no_move=false
                else
                    local tx=x+1
                    local not_rolled=true
                    if tx>=0 and tx<=w-1 then
                        local d=get_pixel(tx,ty)
                        if d.a==0 then
                            set_pixel(tx,ty,c)
                            set_pixel(x,y,{0,0,0,0})
                            wake_block(bx,by,tx,ty)
                            not_rolled=false
                            no_move=false
                        end
                    end
                    if not_rolled then
                        tx=x-1
                        if tx>=0 and tx<=w-1 then
                            local d=get_pixel(tx,ty)
                            if d.a==0 then
                                set_pixel(tx,ty,c)
                                set_pixel(x,y,{0,0,0,0})
                                wake_block(bx,by,tx,ty)
                                not_rolled=false
                                no_move=false
                            end
                        end
                    end
                end
            elseif ph==ph_liquid and y>0 then
                local d=get_pixel(x,y-1)
                if d.a==0 then
                    set_pixel(x,y-1,c)
                    set_pixel(x,y,{0,0,0,0})
                    wake_block(bx,by,x,y-1)
                    no_move=false
                else
                    local tx=x+1
                    local not_rolled=true
                    if tx>=0 and tx<=w-1 then
                        local d=get_pixel(tx,y)
                        if d.a==0 then
                            set_pixel(tx,y,c)
                            set_pixel(x,y,{0,0,0,0})
                            wake_block(bx,by,tx,y)
                            not_rolled=false
                            no_move=false
                        end
                    end
                    if not_rolled then
                        tx=x-1
                        if tx>=0 and tx<=w-1 then
                            local d=get_pixel(tx,y)
                            if d.a==0 then
                                set_pixel(tx,y,c)
                                set_pixel(x,y,{0,0,0,0})
                                wake_block(bx,by,tx,y)
                                not_rolled=false
                                no_move=false
                            end
                        end
                    end
                end
            end
        end
    end
    if no_move then
        block_alive:set(bx,by,0)
    else
        wake_near_blocks(bx,by)
    end
end

function pixel_step_blocky(  )
    local w=img_buf.w
    local h=img_buf.h

    local bw=img_buf.w/block_size
    local bh=img_buf.h/block_size
    for bx=0,bw-1 do
    for by=0,bh-1 do
        local ba=block_alive:get(bx,by)
        if ba~=0 then
            calculate_block(bx,by)
        end
    end
    end
    update_sun()
end
function pixel_step(  )
    local w=img_buf.w
    local h=img_buf.h

    for x=0,w-1 do
        for y=1,h-1 do
            local c=get_pixel(x,y)
            local ph=get_physics(c.a)

            if ph==ph_sand then
                local d=get_pixel(x,y-1)
                if d.a==0 then
                    set_pixel(x,y-1,c)
                    set_pixel(x,y,{0,0,0,0})
                elseif get_physics(d.a)==ph_liquid then
                    swap_pixels(x,y,x,y-1)
                else
                    local tx=x+1
                    local not_moved=true
                    if tx>=0 and tx<=w-1 then
                        local d=get_pixel(tx,y-1)
                        if d.a==0 then
                            set_pixel(tx,y-1,c)
                            set_pixel(x,y,{0,0,0,0})
                            not_moved=false
                        end
                    end
                    if not_moved then
                        tx=x-1
                        if tx>=0 and tx<=w-1 then
                            local d=get_pixel(tx,y-1)
                            if d.a==0 then
                                set_pixel(tx,y-1,c)
                                set_pixel(x,y,{0,0,0,0})
                                not_moved=false
                            end
                        end
                    end
                end
            elseif ph==ph_liquid then
                local d=get_pixel(x,y-1)
                if d.a==0 then
                    set_pixel(x,y-1,c)
                    set_pixel(x,y,{0,0,0,0})
                else
                    local tx=x+1
                    local not_rolled=true
                    if tx>=0 and tx<=w-1 then
                        local d=get_pixel(tx,y)
                        if d.a==0 then
                            set_pixel(tx,y,c)
                            set_pixel(x,y,{0,0,0,0})
                            not_rolled=false
                        end
                    end
                    if not_rolled then
                        tx=x-1
                        if tx>=0 and tx<=w-1 then
                            local d=get_pixel(tx,y)
                            if d.a==0 then
                                set_pixel(tx,y,c)
                                set_pixel(x,y,{0,0,0,0})
                                not_rolled=false
                            end
                        end
                    end
                end
            end
        end
    end
    update_sun()

    --[[
    local i=img_buf_back
    img_buf_back=img_buf
    img_buf=i
    --]]
end
plants=plants or {}
if is_remade then plants={} end
function add_plant( x,y, tbl )
    local w=img_buf.w
    local h=img_buf.h
    x=x or math.random(0,w-1)
    y=y or (h-1)--math.random(0,h-1)
    table.insert(tbl or plants,{food=1000,dead=false,growing=false,seed={x,y}})
    set_pixel(x,y,pixel_types.plant_seed)
end

function is_sunlit( x,y )
    if x<0 or x>img_buf.w-1 then
        return false
    end
    local sh=sun_buffer:get(x,y)
    return (sh.r+sh.g+sh.b)/3>0.1
end

function plant_step()
    --super config
    local seed_bias_gravity    =0.04
    local seed_bias_random     =0.8
    local seed_move_speed      =0.1
    --growth stuff
    local chance_up=0.3
    local chance_sunlit=0.9
    local chance_drift=0.3
    --costs and food
    local sun_gain=5
    local grow_cost_const=1
    local grow_cost_buffer=1.5
    local grow_cost_size=0.00075
    local fruit_cost_const=1
    local fruit_cost_buffer=1.2
    local max_fruit_size=100
    local max_fruit_timer=1000 --prevent fruit getting stuck in ungrowable niches
    local fruit_chance_seed=0.05
    local fruit_shape_chances={
            [0]=1,
            [1]=1,
            [2]=0,
            [3]=1,
            [4]=1,
            [5]=0,
            [6]=1,
            [7]=1,
            [8]=0,
        }
    local max_food=20000
    local food_drain=5
    local food_drain_hibernate=0.75
    --
    local newplants={}
    local w=img_buf.w
    local h=img_buf.h
    
    for i,v in ipairs(plants) do
        local drop_fruit = false

        local food_balance=0
        --drop down
        if v.seed then
            local seed=v.seed
            local x=seed[1]
            local y=seed[2]

            if y>0 then
                local tx=x
                local ty=y-1
                if math.random()<chance_drift then
                    if math.random()>0.5 then
                        tx=x-1
                    else
                        tx=x+1
                    end
                end
                if tx>=0 and tx<img_buf.w then
                    local d=get_pixel(tx,ty)
                    local ph=get_physics(d.a)
                    if ph==ph_liquid or d.a==0 then
                        seed[1]=tx
                        seed[2]=ty
                        swap_pixels(x,y,tx,ty)
                    elseif d.a==pixel_types.sand[4] then
                        if is_sunlit(x,y) then
                            v.shoot={pos=Point(x,y)}
                            v.trunk={}
                            v.seed=nil
                        end
                    end
                end
            end
            if get_pixel(seed[1],seed[2]).a~=pixel_types.plant_seed[4] then
                v.dead=true
                print("seed misplace!",i,"@",seed[1],seed[2])
                v.seed=nil
            end
        elseif v.shoot then
            --growing logic
            for i,v in ipairs(v.trunk) do
                if is_sunlit(v[1],v[2]) then
                    food_balance=food_balance+sun_gain
                end
            end

            local tx = v.shoot.pos[1]
            local ty = v.shoot.pos[2]

            local grow_cost=grow_cost_const+(#v.trunk*#v.trunk)*grow_cost_size--+math.max(ty*2-25,0)
            if ty<h-1 and (food_balance>grow_cost*grow_cost_buffer or #v.trunk<3) then

                if math.random()>chance_up then
                    -- prefer sunlit directions
                    local right=is_sunlit(tx+1,ty)
                    local left=is_sunlit(tx-1,ty)
                    if math.random()<chance_sunlit and not(left== right) then
                        if left then
                            tx=tx-1
                        else
                            tx=tx+1
                        end
                    else
                        if math.random()>0.5 then
                            tx=tx+1
                        else
                            tx=tx-1
                        end
                    end
                else
                    ty=ty+1
                end
                if is_valid_coord(tx,ty) then
                    local d=get_pixel(tx,ty)
                    local ph=get_physics(d.a)
                    if d.a==0 or ph==ph_liquid then
                        local ox=v.shoot.pos[1]
                        local oy=v.shoot.pos[2]
                        table.insert(v.trunk,{ox,oy})
                        set_pixel(tx,ty,pixel_types.plant_body)
                        v.shoot.pos[1]=tx
                        v.shoot.pos[2]=ty
                        food_balance=food_balance-grow_cost
                    end
                end
            elseif (#v.trunk>8 and food_balance>fruit_cost_const*fruit_cost_buffer) then
                local p
                local tx
                local ty
                
                if v.fruit then
                    p=v.fruit[math.random(1,#v.fruit)]
                    local dd=directions4[math.random(1,#directions4)]
                    tx=p[1]+dd[1]
                    ty=p[2]+dd[2]
                    v.fruit.timer=v.fruit.timer+1
                    if v.fruit.timer>max_fruit_timer then
                        drop_fruit=true
                    end
                else
                    p=v.trunk[math.random(1,#v.trunk)]
                    tx=p[1]
                    ty=p[2]-1
                end
                
                if is_valid_coord(tx,ty) and get_pixel(tx,ty).a==0 then
                    local c=count_pixels_around8(tx,ty,pixel_types.plant_fruit[4])
                    if math.random()<fruit_shape_chances[c] then
                        if v.fruit then
                            table.insert(v.fruit,{tx,ty})
                            if #v.fruit>=max_fruit_size then
                                drop_fruit=true
                            end
                        else
                            v.fruit={{tx,ty}}
                            v.fruit.timer=0
                        end
                        food_balance=food_balance-fruit_cost_const
                        set_pixel(tx,ty,pixel_types.plant_fruit)
                    end
                end

            end
        else
            v.dead=true
        end
        --ageing logic
        if not v.growing then
            food_balance=food_balance-food_drain_hibernate
        else
            food_balance=food_balance-food_drain
        end

        v.food=v.food+food_balance
        if v.food>max_food then
            v.food=max_food
        end
        if v.food<=0 then
            v.dead=true
        end
        

        if v.dead then
            if v.seed then
                set_pixel(v.seed[1],v.seed[2],pixel_types.dead_plant)
                wake_pixel(v.seed[1],v.seed[2])
            elseif v.shoot then
                set_pixel(v.shoot.pos[1],v.shoot.pos[2],pixel_types.dead_plant)
                wake_pixel(v.shoot.pos[1],v.shoot.pos[2])
            end
            if v.trunk then
                for i,v in ipairs(v.trunk) do
                    set_pixel(v[1],v[2],pixel_types.dead_plant)
                    wake_pixel(v[1],v[2])
                end
            end
        end
        if drop_fruit or v.dead then
            if v.fruit then
                for i,v in ipairs(v.fruit) do
                    if math.random()<fruit_chance_seed then
                        add_plant(v[1],v[2],newplants)
                        wake_pixel(v[1],v[2])
                    else
                        set_pixel(v[1],v[2],pixel_types.dead_plant)
                        wake_pixel(v[1],v[2])
                    end
                end
                v.fruit=nil
            end
        end
    end
    remove_dead_addnew(plants,newplants)
end

worms=worms or {}
if is_remade then worms={} end

function add_worm( x,y,trg_tbl )
    local w=img_buf.w
    local h=img_buf.h
    x=x or math.random(0,w-1)
    y=y or 0
    local dir=Point(math.random()-0.5,math.random()-0.5)
    dir:normalize()
    table.insert(trg_tbl or worms,{
        pixel_types.worm_body,food=500,dead=false,tail={{x,y}},
        fract=Point(0,0),
        dir=dir,
        })
    set_pixel(x,y,pixel_types.worm_body)
end


function worm_step( )
    local surface_bias=0.000
    local random_bias=1.5
    local grow_cost_const=500
    local grow_cost_buffer=2
    local max_food=20000
    local food_drain=0.1
    local food_drain_sun=20 --burn in sun
    local food_gain={
        [pixel_types.dead_plant[4]]=20,
        [pixel_types.mycelium[4]]  =15,
        [pixel_types.spore[4]]     =10,
        [pixel_types.mushroom[4]]  =10,
    }


    local chance_new_worm=0.2
    local dead_tile=pixel_types.sand
    local move_speed=0.5
    --
    local newworms={}
    local w=img_buf.w
    local h=img_buf.h
    for i,v in ipairs(worms) do
        local x=v.tail[1][1]
        local y=v.tail[1][2]

        local want_move=true
        local want_growth=false
        --growth logic
        if v.food>grow_cost_const*grow_cost_buffer then
            want_growth=true
        end
        --movement logic
        v.dir=v.dir+surface_bias*Point(0,1)
        v.dir=v.dir+random_bias*Point(math.random()-0.5,math.random()-0.5)
        v.dir:normalize()
        local d=fract_move4(v,move_speed,v.dir)

        if d[1]==0 and d[2]==0 then
            want_move=false
        end

        local tx=d[1]+x
        local ty=d[2]+y
        if #v.tail>1 then
            local tdx=v.tail[2][1]-tx
            local tdy=v.tail[2][2]-ty
            if tdx==0 and tdy==0 then
                want_move=false
            end
        end

        local food_balance=0

        if want_move and is_valid_coord(tx,ty) then
            local d=get_pixel(tx,ty)
            local eat_type=d.a
            if food_gain[eat_type]~=nil then
                food_balance=food_balance+food_gain[eat_type]
            elseif eat_type==pixel_types.worm_body[4] then
                for i,t in ipairs(v.tail) do
                    if tx==t[1] and ty==t[2] then
                        for i,v in ipairs(v.tail) do
                            set_pixel(v[1],v[2],dead_tile)
                            wake_pixel(v[1],v[2])
                        end
                        local new_worm_count=math.random(0,#v.tail*chance_new_worm)
                        for i=1,new_worm_count do
                            local g=v.tail[math.random(1,#v.tail)]
                            local tx=g[1]
                            local ty=g[2]
                            add_worm(tx,ty,newworms)
                            wake_pixel(tx,ty)
                        end
                        v.tail={{x,y}}
                        set_pixel(x,y,pixel_types.worm_body)
                        wake_pixel(x,y)
                        want_move=false
                        break
                    end
                end
                want_move=false
            elseif eat_type~=pixel_types.sand[4] then
                want_move=false
            end

            if want_move then
                local px=tx
                local py=ty
                for i=1,#v.tail do
                    local ttx=v.tail[i][1]
                    local tty=v.tail[i][2]

                    v.tail[i][1]=px
                    v.tail[i][2]=py
                    set_pixel(px,py,pixel_types.worm_body)
                    wake_pixel(px,py)
                    px=ttx
                    py=tty
                end
                if eat_type==pixel_types.sand[4] then
                    set_pixel(px,py,pixel_types.sand)
                    wake_pixel(px,py)
                else
                    if want_growth then
                        table.insert(v.tail,{px,py})
                        set_pixel(px,py,pixel_types.worm_body)
                        food_balance=food_balance-grow_cost_const
                        wake_pixel(px,py)
                    else
                        set_pixel(px,py,{0,0,0,0})
                        wake_pixel(px,py)
                    end
                end
            end
        end
        for i,t in ipairs(v.tail) do
            if get_pixel(t[1],t[2]).a~=pixel_types.worm_body[4] then
                v.dead=true
            end
            if is_sunlit(t[1],t[2]) then
                food_balance=food_balance-food_drain_sun
            end
            
        end
        --ageing logic
        food_balance=food_balance-food_drain
        --growing logic
        v.food=v.food+food_balance
        if v.food>max_food then
            v.food=max_food
        end

        if v.food<=0 then
            v.dead=true
        end
        --readd new pos
        if v.dead then
            for i,v in ipairs(v.tail or {}) do
                set_pixel(v[1],v[2],dead_tile)
                wake_pixel(v[1],v[2])
            end
        end
    end
    remove_dead_addnew(worms,newworms)
end
mushrooms=mushrooms or {}
if is_remade then worms={} end

function add_mushroom( x,y,trg_tbl,kick,sterile )
    local w=img_buf.w
    local h=img_buf.h
    x=x or math.random(0,w-1)
    y=y or h-1
    local dir=Point(0,-1)
    dir:normalize()
    local food=500
    if sterile then
        food=math.random(1,20)
    end
    table.insert(trg_tbl or mushrooms,{
        food=food,dead=false,spore={x,y},
        fract=Point(0,0),
        dir=dir,
        kick=kick or 0,
        sterile=sterile
        })
    set_pixel(x,y,pixel_types.spore)
end

function mushroom_tick(  )
    local spore_bias_gravity    =0.04
    local spore_bias_random     =0.8
    local spore_move_speed      =0.1
    local spore_bias_kick       =0.15
    local spore_kick_speedup    =0.1

    local mycelium_chance_spread=0.1
    local mycelium_max_growers  =3
    local mycelium_move_speed   =0.005
    local mycelium_bias_random  =3
    local mycelium_max_life     =50

    local shroom_max_size       =100
    local shroom_spore_chance   =0.005
    local shroom_spore_kick     =300 --note +0.5*random
    local shroom_max_timer      =9000
    local shroom_shape_chances={
            [0]=1,
            [1]=1,
            [2]=0,
            [3]=1,
            [4]=0,
            [5]=0,
            [6]=0,
            [7]=0,
            [8]=0,
        }
    local food_drain_spore      =0.01
    local food_drain_shroom     =0.05
    local food_max              =1000
    local food_gain_plant_matter=2
    local food_cost_shroom      =25
    --
    local newshrooms={}
    local w=img_buf.w
    local h=img_buf.h

    for i,v in ipairs(mushrooms) do
        local myself=v
        local food_balance=0
        if v.spore then
            food_balance=food_balance-food_drain_spore
            local x=v.spore[1]
            local y=v.spore[2]
            local want_move=true
            if get_pixel(x,y).a~=pixel_types.spore[4] then
                want_move=false
                v.dead=true
                v.removed=true
            end
            local want_sprout
            local kick=0
            local move_speed=spore_move_speed
            if v.kick>0 then
                kick=spore_bias_kick
                v.kick=v.kick-1
                move_speed=move_speed+spore_kick_speedup
            end
            v.dir=v.dir+spore_bias_gravity*Point(0,-1)+
                spore_bias_random*Point(math.random()-0.5,math.random()-0.5)+
                kick*Point(0,1)
            v.dir:normalize()

            local d=fract_move(v,move_speed,v.dir)
            if d[1]==0 and d[2]==0 then
                want_move=false
            end


            local tx=d[1]+x
            local ty=d[2]+y

            if want_move and is_valid_coord(tx,ty) then
                local d=get_pixel(tx,ty)
                if d.a~=0 then
                    want_move=false
                end
            else
                want_move=false
            end

            if want_move then
                set_pixel(x,y,{0,0,0,0})
                set_pixel(tx,ty,pixel_types.spore)
                v.spore[1]=tx
                v.spore[2]=ty
                wake_pixel(tx,ty)
            elseif not is_sunlit(x,y) then
                local tx=x
                local ty=y-1
                if is_valid_coord(tx,ty) then
                    local d=get_pixel(tx,ty)
                    if d.a==pixel_types.dead_plant[4] then
                        want_sprout={tx,ty}
                    end
                end
            end

            if want_sprout and not v.sterile then
                set_pixel(x,y,{0,0,0,0})
                wake_pixel(x,y)
                v.spore=nil --i'm a spore no more!
                v.mycelium={want_sprout}
                v.mycelium_growers={}
                set_pixel(want_sprout[1],want_sprout[2],pixel_types.mycelium)
                --some cleanup
                v.fract=nil
                v.dir=nil
            end
        elseif v.mycelium then
            food_balance=food_balance-food_drain_shroom
            if #v.mycelium_growers==0 and #v.mycelium==0 then
                v.dead=true
            end
            for i,v in ipairs(v.mycelium_growers) do
                v.dir=v.dir+mycelium_bias_random*Point(math.random()-0.5,math.random()-0.5)
                local d=fract_move4(v,mycelium_move_speed,v.dir)
                local grow=not v.dead
                local sprout=false
                if d[1]==0 and d[2]==0 then
                    grow=false
                else
                    v.life=v.life+1
                end
                local trg=v.pos+d
                if grow and not is_valid_coord(trg[1],trg[2]) then
                    grow=false
                end
                if grow and is_sunlit(trg[1],trg[2]) then
                    v.dead=true
                    grow=false
                end
                if grow then
                    local tt=get_pixel(trg[1],trg[2]).a
                    if tt == pixel_types.sand[4] then
                        --just grow
                    elseif tt==pixel_types.dead_plant[4] then
                        food_balance=food_balance+food_gain_plant_matter
                    elseif tt==0 then
                        sprout=true
                        grow=false
                    else
                        grow=false
                    end
                end
                
                if sprout and myself.shroom==nil then
                    if myself.food>food_cost_shroom then
                        food_balance=food_balance - food_cost_shroom
                        myself.shroom={{trg[1],trg[2]},timer=0}
                        set_pixel(trg[1],trg[2],pixel_types.mushroom)
                    end
                elseif grow then --finally actually grow!
                    set_pixel(trg[1],trg[2],pixel_types.mycelium)
                    table.insert(myself.mycelium,{trg[1],trg[2]})
                    v.pos=trg
                end
                if v.life>mycelium_max_life then
                    v.dead=true
                end
            end
            remove_dead_addnew(v.mycelium_growers)
            if not v.dead and math.random()<mycelium_chance_spread and
                #v.mycelium_growers<mycelium_max_growers and
                #v.mycelium>0 then
                local source=v.mycelium[math.random(1,#v.mycelium)]
                if get_pixel(source[1],source[2]).a~=pixel_types.mycelium[4] then
                    source.dead=true
                else
                    local dir=Point(math.random()-0.5,math.random()-0.5)
                    dir:normalize()
                    local new_grower={
                        pos=Point(source[1],source[2]),
                        fract=Point(0,0),
                        dir=dir,
                        life=0,
                        dead=false,
                    }
                    table.insert(v.mycelium_growers,new_grower)
                end
            end
            remove_dead_addnew(v.mycelium)
        end
        if v.shroom then
            local sh=v.shroom
            local kill_shroom=false
            local make_spores=true
            for i,v in ipairs(sh) do
                if get_pixel(v[1],v[2]).a~=pixel_types.mushroom[4] then
                    v.dead=true
                end
            end
            if #sh>=shroom_max_size then
                --blast off!
                kill_shroom=true
            else
                local p=sh[math.random(1,#sh)]
                if not p.dead then
                    local dd=directions4[math.random(1,#directions4)]
                    local tx=p[1]+dd[1]
                    local ty=p[2]+dd[2]
                    sh.timer=sh.timer+1
                    if sh.timer>shroom_max_timer then
                        kill_shroom=true
                    elseif is_valid_coord(tx,ty) and get_pixel(tx,ty).a==0 then
                        local c=count_pixels_around8(tx,ty,pixel_types.mushroom[4])
                        if math.random()<shroom_shape_chances[c] then
                            table.insert(sh,{tx,ty})
                            set_pixel(tx,ty,pixel_types.mushroom)
                        end
                    end
                end
            end
            if kill_shroom then
                for i,v in ipairs(sh) do
                    if not v.dead then
                        if math.random()<shroom_spore_chance then
                            add_mushroom(v[1],v[2],newshrooms,math.floor(shroom_spore_kick+math.random()*shroom_spore_kick*0.5))
                        else
                            add_mushroom(v[1],v[2],newshrooms,math.floor(shroom_spore_kick+math.random()*shroom_spore_kick*0.5),true)
                        end
                        v.dead=true
                    end
                end
            end
            remove_dead_addnew(v.shroom)
            if #v.shroom==0 then
                v.shroom=nil
            end
        end

        v.food=v.food+food_balance
        if v.food>food_max then
            v.food=food_max
        end

        if v.food<=0 then
            v.dead=true
        end

        if v.dead and not v.removed then
            if v.spore then
                local x=v.spore[1]
                local y=v.spore[2]
                if y then
                    set_pixel(x,y,{0,0,0,0})
                    wake_pixel(x,y)
                end
            elseif v.mycelium then
                for i,v in ipairs(v.mycelium) do
                    set_pixel(v[1],v[2],pixel_types.dead_plant)
                    wake_pixel(v[1],v[2])
                end
                for i,v in ipairs(v.mycelium_growers) do
                    set_pixel(v.pos[1],v.pos[2],pixel_types.dead_plant)
                    wake_pixel(v.pos[1],v.pos[2])
                end
            end
            if v.shroom then
                for i,v in ipairs(v.shroom) do
                    set_pixel(v[1],v[2],pixel_types.dead_plant)
                    wake_pixel(v[1],v[2])
                end
            end
        end
    end
    remove_dead_addnew(mushrooms,newshrooms)
end
function concat_tables(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

function try_grow( pcenter,dir, valid_a)
    local trg=pcenter+dir
    if not is_valid_coord(trg[1],trg[2]) then
        return false
    end
    local d=get_pixel(trg[1],trg[2])
    if valid_a then
        return valid_a[d.a]
    else
        return d.a==0
    end
end

function max_w_stress_based( mydelta ,max_w,max_h,current_h)
    local grow_amount=current_h/max_h --how much current growth is
    local v=mydelta[2]/max_h
    return math.max(grow_amount*max_w*(1-v),1)
end

function next_pixel( dir )
    local m=math.max(math.abs(dir[1]),math.abs(dir[2]))
    return Point(dir[1]/m,dir[2]/m)
end
function is_mouse_down(  )
    local ret=__mouse.clicked1 and not __mouse.owned1
    if ret then
        current_down=true
    end
    if __mouse.released1 then
        current_down=false
    end
    return current_down, __mouse.x,__mouse.y
end
function is_mouse_down2()
    local ret=__mouse.clicked2 and not __mouse.owned2
    if ret then
        current_down2=true
        last_mouse2={__mouse.x,__mouse.y}
    end
    local delta_x=0
    local delta_y=0
    if current_down2 then
        delta_x=__mouse.x-last_mouse2[1]
        delta_y=__mouse.y-last_mouse2[2]
        last_mouse2={__mouse.x,__mouse.y}
    end
    if __mouse.released2 then
        current_down2=false
    end
    return current_down2, __mouse.x,__mouse.y, delta_x,delta_y
end
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
tex_pixel=tex_pixel or textures:Make()
tex_sun=tex_sun or textures:Make()
need_save=false
tick=0
function update()
    __clear()
    __no_redraw()

    imgui.Begin("ecology")
    draw_config(config)
    if imgui.Button("Kill plants") then
        for i,v in ipairs(plants) do
            v.dead=true
        end
    end
    imgui.SameLine()
    if imgui.Button("Reset world") then
        img_buf=nil
        update_img_buf()
        pixel_init()
        plants={}
        worms={}
        trees={}
        mushrooms={}
    end

    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    if imgui.Button("Wake") then
        wake_blocks()
    end
    --if imgui.Button("Add trees") then
    --  add_tree()
    --end
    imgui.End()
    local md,x,y=is_mouse_down(  )
    if md then
        local tx,ty=math.floor(x*oversample),math.floor(img_buf.h-y*oversample)
        if is_valid_coord(tx,ty) then
            --add_mushroom(tx,ty,nil,100+math.random(1,80))
            set_pixel(tx,ty,pixel_types.wall)
            wake_pixel(tx,ty)
        end
    end
    --[[
    if md then
        if tx<0 then tx=0 end
        if ty<0 then ty=0 end
        add_worm(tx,ty)
    end
    ]]
    -- [[
    if not config.pause then
        if math.random()>0.8 and #plants<5 then
            add_plant()
        end
        if math.random()>0.99 and #worms<5 then
            add_worm()
        end
        if math.random()>0.999 and #mushrooms<5 then
            add_mushroom()
        end
        --print("Worms:",#worms)
        --print("Plants:",#plants)
        --]]
        if block_size==0 then
            pixel_step( )
        else
            pixel_step_blocky( )
        end
        plant_step()
        worm_step()
        mushroom_tick()
        tick=tick+1
    end
    if config.draw then

    draw_shader:use()
    tex_pixel:use(0,0,1)

    --tex_pixel.t:set(size[1]*oversample,size[2]*oversample,3)
    img_buf:write_texture(tex_pixel)
    tex_sun:use(1,0,1)
    sun_buffer:write_texture(tex_sun)

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("tex_sun",1)
    draw_shader:set_i("rez",map_w,map_h)
    draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
    draw_shader:set("translate",config.t_x,config.t_y)
    draw_shader:set("sun_color",config.color[1],config.color[2],config.color[3],config.color[4])
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
        if config.t_x<0 then config.t_x=0 end
        if config.t_x>1-1/config.zoom then config.t_x=1-1/config.zoom end
        if config.t_y<0 then config.t_y=0 end
        if config.t_y>1-1/config.zoom then config.t_y=1-1/config.zoom end
    end
end
