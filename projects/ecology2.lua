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
        sun_buffer=make_float_buffer(nw,1)
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
    {"zoom",1,type="float",min=1,max=10},
    {"t_x",0,type="float",min=0,max=1},
    {"t_y",0,type="float",min=0,max=1},
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


float is_lit(vec2 p)
{
    float hsun=texture(tex_sun,vec2(p.x,0)).x;
    return 1-step(p.y,hsun);
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    normed=normed/zoom+translate;
    float lit=is_lit(normed);
    vec4 pixel=texture(tex_main,normed);
    if(pixel.a==0)
        color=vec4(sun_color.xyz*lit,1);
    else
        color=vec4(pixel.xyz+sun_color.xyz*lit,1);
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
function rand_dir4()
    return directions4[math.random(1,4)]
end
function rand_dir8()
    return directions8[math.random(1,8)]
end
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
    empty        ={0,0,0,0},
    sand         ={124,100,80 ,next_pixel_type_id(ph_sand  ,1)},
    wetsand      ={88 ,64 ,45 ,next_pixel_type_id(ph_wall  ,1)},
    water        ={70 ,70 ,150,next_pixel_type_id(ph_liquid,0)},
    wall         ={20 ,80 ,100,next_pixel_type_id(ph_wall  ,1)},
    ------------------------------------------------------------
    cactus_seed  ={212, 44,125,next_pixel_type_id(ph_wall  ,0)},
    cactus_body  ={120,190, 73,next_pixel_type_id(ph_wall  ,1)},
    cactus_center={ 65,100,112,next_pixel_type_id(ph_wall  ,1)},
}
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
    --settings
    local random_pixels={
        [pixel_types.water]=0.05,
        [pixel_types.sand] =0.1,
    }
    local count_platforms=25
    -------------------------
    local w=img_buf.w
    local h=img_buf.h
    local cx = math.floor(w/2)
    local cy = math.floor(h/2)


    for k,v in pairs(random_pixels) do
        for i=1,w*h*v do
            local x=math.random(0,w-1)
            local y=math.random(0,h-1)
            set_pixel(x,y,k)
        end
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
    for i=1,count_platforms do
        local platform_size=math.random(100,200)
        local x=math.random(0,(w-1)/2)
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

    for x=0,w-1 do
        sun_buffer:set(x,0,0)
    end

   for x=0,w-1 do
        for y=h-1,0,-1 do
            local c=get_pixel(x,y)
            if is_block_light(c.a) then
                sun_buffer:set(x,0,y/h)
                break
            end
        end
    end
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
                    local not_rolled=true
                    if c.a==pixel_types.water[4] then
                        if d.a==pixel_types.sand[4] then
                            set_pixel(x,y,pixel_types.empty)
                            set_pixel(x,y-1,pixel_types.wetsand)
                            not_rolled=false
                            no_move=false
                        end
                    end
                    local tx=x+1
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
function rand_pixel_step( count )
    for i=1,count do
        local x = math.random(0,map_w-1)
        local y = math.random(0,map_h-1)
        local d=get_pixel(x,y)
        if d.a==pixel_types.wetsand[4] then
            local tx=x+math.random(-1,1)
            local ty=y-1
            local moved=false
            if is_valid_coord(tx,ty) then
                if get_pixel(tx,ty).a==pixel_types.sand[4] then
                    swap_pixels(x,y,tx,ty)
                    wake_pixel(tx,ty)
                    wake_pixel(x,y)
                    moved=true
                end
            elseif ty==-1 then
                set_pixel(x,y,pixel_types.sand)
                wake_pixel(x,y)
            end

            if not moved  then
                if is_valid_coord(x,y+1) and is_sunlit(x,y+1) then
                    if get_pixel(x,y+1).a==pixel_types.empty[4] then
                        set_pixel(x,y,pixel_types.sand)
                        wake_pixel(x,y)
                    end
                end
            end
        elseif d.a==pixel_types.water[4] then
            local tx=x
            local ty=y+1
            if is_valid_coord(tx,ty) and is_sunlit(x,y) then
                if get_pixel(tx,ty).a==pixel_types.empty[4] then
                    set_pixel(x,y,pixel_types.empty)
                    wake_pixel(x,y)
                    wake_pixel(tx,ty)
                end
            end
        end
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
function rain( count )
    for i=1,count do
        local x=math.random(0,map_w-1)
        local y=map_h-1
        set_pixel(x,y,pixel_types.water)
        wake_pixel(x,y)
    end
end
function is_sunlit( x,y )
    if x<0 or x>img_buf.w-1 then
        return false
    end
    local sh=sun_buffer:get(x,0)
    return sh*img_buf.h<=y
end

function concat_tables(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

function clamp( v,min,max )
    if v<min then
        return min
    end
    if v>max then
        return max
    end
    return v
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
function is_pixel_type( x,y,ptype )
    if not is_valid_coord(x,y) then
        return false
    end
    if ptype==nil then
        ptype=0
    end
    local p= get_pixel(x,y)
    if p.a==ptype then
        return true,p
    else
        return false
    end
end
sim_master_list={}
--------------------------------------------------------------------------------

cactus=cactus or {items={}}
sim_master_list.cactus=cactus
cactus.repop=3
function cactus.create(tbl,x,y,args )
    local w=img_buf.w
    local h=img_buf.h
    args=args or {}
    x=x or math.random(0,w-1)
    y=y or h-1

    table.insert(tbl or cactus.items,{
        food=args.food or 500,dead=false,seed=Point(x,y),
        fract=Point(0,0),
        dir=Point(0,-1),
        })
    set_pixel(x,y,pixel_types.cactus_seed)
end
function cactus.sim_step(it,new_items)
    --settings
    local seed_drift_bias=2.5
    local seed_gravity_bias=0.15
    local seed_drop_speed=0.4

    local body_max_size=30

    local food_cost_grow=30
    local food_cost_grow_buffer=4
    local food_cost_dist={1,3}
    local food_cost_seed=150
    local food_cost_seed_buffer=3

    local food_consume=0.003
    local food_water_gain=15
    local food_cap=3000
    ----------------------------------
    local w=img_buf.w
    local h=img_buf.h

    local food_balance = -food_consume
    if it.seed then
        it.dir=it.dir+seed_drift_bias*Point(math.random()-0.5,math.random()-0.5)+seed_gravity_bias*Point(0,-1)
        it.dir:normalize()
        local step=fract_move(it,seed_drop_speed,it.dir)
        local want_move=true
        if step[1]==0 and step[2]==0 then
            want_move=false
        end
        local t=it.seed+step
        if want_move then
            want_move=is_pixel_type(t[1],t[2])
        end

        if want_move then
            set_pixel(it.seed[1],it.seed[2],pixel_types.empty)
            it.seed=t
            set_pixel(it.seed[1],it.seed[2],pixel_types.cactus_seed)
        end


        if is_pixel_type(it.seed[1],it.seed[2]+1) then
            local sprout=true
            if is_valid_coord(it.seed[1],it.seed[2]-1) then
                local bottom=get_pixel(it.seed[1],it.seed[2]-1)
                if bottom.a~=pixel_types.sand[4] and bottom.a~=pixel_types.wetsand[4] then
                    sprout=false
                end
            end
            local d=rand_dir8()
            local t=it.seed+Point(d[1],d[2])

            if sprout and is_valid_coord(t[1],t[2]) then
                local p=get_pixel(t[1],t[2])
                if p.a==pixel_types.water[4] then
                    set_pixel(t[1],t[2],pixel_types.empty)
                elseif p.a==pixel_types.wetsand[4] then
                    set_pixel(t[1],t[2],pixel_types.sand)
                else
                    sprout=false
                end
            end
            if sprout then
                local x=it.seed[1]
                local y=it.seed[2]
                set_pixel(x,y,pixel_types.cactus_body)
                it.seed=nil
                food_balance=food_balance+food_water_gain
                it.skin={Point(x,y)}
                it.body={Point(x,y)}
                it.center=Point(x,y)
            end
        end

    elseif #it.skin>0 then
        local idx=math.random(1,#it.skin)
        local cell=it.skin[idx]
        local remove=false
        local c=4-count_pixels_around4(cell[1],cell[2],0)
        c=c-count_pixels_around4(cell[1],cell[2],pixel_types.water[4])
        if c==4 then
            remove=true
        end
        if remove then
            set_pixel(cell[1],cell[2],pixel_types.cactus_center)
            it.skin[idx]=it.skin[#it.skin]
            it.skin[#it.skin]=nil
        else

            if it.food>food_cost_grow*food_cost_grow_buffer and
                #it.body<body_max_size then
                local d=rand_dir4()
                local t=cell+Point(d[1],d[2])
                if is_valid_coord(t[1],t[2]) and get_pixel(t[1],t[2]).a==0 then
                    local dist=(t-it.center):len()
                    local food_cost=food_cost_grow+dist*food_cost_dist[1]+
                        dist*dist*food_cost_dist[2]
                    if food_cost<it.food then
                        food_balance=food_balance-food_cost
                        set_pixel(t[1],t[2],pixel_types.cactus_body)
                        table.insert(it.skin,t)
                        table.insert(it.body,Point(t[1],t[2]))
                    end
                end
            elseif it.food>food_cost_seed*food_cost_seed_buffer then
                local d=rand_dir4()
                local t=cell+Point(d[1],d[2])
                if is_pixel_type(t[1],t[2],pixel_types.empty[4]) then
                    food_balance=food_balance-food_cost_seed
                    cactus.create(new_items,t[1],t[2],{food=food_cost_seed})

                end
            end
            local d=rand_dir8()
            local t=cell+Point(d[1],d[2])
            local got_water=false
            if is_valid_coord(t[1],t[2]) then
                local p=get_pixel(t[1],t[2])
                if p.a==pixel_types.water[4] then
                    set_pixel(t[1],t[2],pixel_types.empty)
                    got_water=true
                elseif p.a==pixel_types.wetsand[4] then
                    set_pixel(t[1],t[2],pixel_types.sand)
                    got_water=true
                end
            end
            if got_water then
                food_balance=food_balance+food_water_gain
            end
        end
    else
        it.dead=true
    end
    it.food=it.food+food_balance
    if it.food>food_cap then
        it.food=food_cap
    end
    if it.food<=0 then
        it.dead=true
    end
end
function cactus.cleaup( it )
    if it.seed then
        set_pixel(it.seed[1],it.seed[2],pixel_types.empty)
    else
        for i,v in ipairs(it.body) do
            set_pixel(v[1],v[2],pixel_types.water)
            wake_pixel(v[1],v[2])
        end
    end
end
--------------------------------------------------------------------------------
function organism_step()
    for k,v in pairs(sim_master_list) do
        local new_items={}
        if #v.items<v.repop then
            v.create()
        end
        for _,it in ipairs(v.items) do
            v.sim_step(it,new_items)
        end
        for _,it in ipairs(v.items) do
            if it.dead then
                v.cleaup(it)
            end
        end
        remove_dead_addnew(v.items,new_items)
    end
end
tex_pixel=tex_pixel or textures:Make()
tex_sun=tex_sun or textures:Make()
need_save=false
tick=0

rain_tick=rain_tick or 0
is_raining=is_raining or false

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
    local md,x,y=is_mouse_down(  )
    if md then
        local tx,ty=math.floor(x*oversample),math.floor(img_buf.h-y*oversample)
        if is_valid_coord(tx,ty) then
            set_pixel(tx,ty,pixel_types.water)
            --cactus.create(nil,tx,ty)

            wake_pixel(tx,ty)
            --print(get_pixel(tx,ty).a,is_sunlit(tx,ty))
        end
    end

    -- [[
    if not config.pause then
        if rain_tick>10000 then
            is_raining=true
        end
        if is_raining then
            rain(5)
            rain_tick=rain_tick-5
        else
            rain_tick=rain_tick+math.random(1,2)
        end
        if rain_tick<=0 then
            is_raining=false
        end
        pixel_step_blocky( )
        rand_pixel_step(1000)
        organism_step()
        tick=tick+1
    end
    if config.draw then
        draw_shader:use()
        tex_pixel:use(1,0,1)

        img_buf:write_texture(tex_pixel)
        tex_sun:use(2,0,1)
        sun_buffer:write_texture(tex_sun)

        draw_shader:set_i("tex_main",1)
        draw_shader:set_i("tex_sun",2)
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
        config.t_x=clamp(config.t_x,0,1-1/config.zoom)
        config.t_y=clamp(config.t_y,0,1-1/config.zoom)
    end
end
