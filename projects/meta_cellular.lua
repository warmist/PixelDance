--[===[
    second layer of cellular_move

    TODO: better momentum transfer stuff...
--]===]
require 'common'
require 'bit'

dofile "hist_log.ldat"

local win_w=1024
local win_h=1024

--__set_window_size(win_w,win_h)
local oversample=1/8

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size

img_buf=img_buf or make_image_buffer(map_w,map_h)

function resize( w,h )
    img_buf=make_image_buffer(map_w,map_h)
end

local img_tex1=textures.Make()
function write_img(  )
    img_tex1:use(0)
    img_buf:write_texture(img_tex1)
end
write_img()

local draw_shader=shaders.Make(
[==[
#version 330
#line 30
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    vec4 pixel=texture(tex_main,normed);
    color=vec4(pixel.xyz,1);
    //color=vec4(1,0,0,1);
}
]==])
function draw(  )
    __clear()
    draw_shader:use()
    img_tex1:use(0)
    draw_shader:set_i("tex_main",0)
    draw_shader:draw_quad()
end


config=make_config({
    {"pause",false,type="bool"},
    },config)
dist_constraints={}

particles={}
particle_map={}
function choose_one( tbl )
    local sum=0
    local choice=math.random()

    for i,v in pairs(tbl) do
        if choice<sum+v then
            return v,i
        end
        sum=sum+v
    end
end
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
function rand_speed( s )
    local a=math.random()*math.pi*2
    s=s or 1
    return math.cos(a)*s,math.sin(a)*s
end
function split_particle( particle,count_of_loss )
    print("SPLIT:",count_of_loss,particle.count)
    local max_s=0.125
    local new_particles={}
    local col=count_of_loss
    while col>0 do
        local dir=math.random(1,8)
        local delta=dir_to_dx[dir]

        local no_p=math.random(1,col)
        col=col-no_p
        particle.count=particle.count-no_p
        --TODO: better speeds
        local vx,vy=rand_speed(  )
        local np={x=particle.x+delta[1],y=particle.y+delta[2],vx=0,vy=0,count=no_p}
        table.insert(new_particles,np)
        table.insert(particles,np)
    end

    local vel={ particle.vx*(particle.count+count_of_loss),
                particle.vy*(particle.count+count_of_loss) }
    print("Before:",vel[1],vel[2])
    for i,v in ipairs(new_particles) do
        local vx,vy=rand_speed(max_s)
        vel[1]=vel[1]-vx*v.count
        vel[2]=vel[2]-vy*v.count
        v.vx=vx
        v.vy=vy
    end
    print("After:",vel[1],vel[2])
    particle.vx=vel[1]/particle.count
    particle.vy=vel[2]/particle.count
    print("After:",particle.vx,particle.vy)
end
function particle_splits()
    local c=#particles
    for i=1,c do
        local v=particles[i]
        local chance=math.random()
        if v.count>1 and chance>0.0 then

            local tbl=particle_stats[v.count]
            if tbl then
            local chance_self=tbl[v.count] or 0
                if chance_self<1 then
                    local _,ncount=choose_one(tbl)
                    local loss=v.count-ncount
                    if loss>0 then
                        print(loss,ncount)
                        split_particle(v,loss)
                    end
                end
            end
        end
    end
end
local max_count=41
function particle_merge_and_map_update(  )
    max_count=0
    local alive_particles={}
    particle_map={}
    for i,v in ipairs(particles) do
        local x=math.floor(v.x)
        local y=math.floor(v.y)
        local id=x+y*map_w
        local c=v.count
        if particle_map[id] then
            local tp=particle_map[id]
            local nc=tp.count+v.count
            tp.vx=(tp.vx*tp.count+v.vx*v.count)/nc
            tp.vy=(tp.vy*tp.count+v.vy*v.count)/nc
            tp.count=nc
            c=nc
        else
            particle_map[id]=v
            table.insert(alive_particles,v)
        end
        if c>max_count then
            max_count=c
        end
    end
    particles=alive_particles
end
function particle_move( step )
    for i,v in ipairs(particles) do
        v.x=v.x+step*v.vx
        v.y=v.y+step*v.vy
        if v.x<0 then v.x=map_w+v.x end
        if v.y<0 then v.y=map_h+v.y end

        if v.x>=map_w then v.x=v.x-map_w end
        if v.y>=map_h then v.y=v.y-map_h end
    end
end
function particle_draw(  )
    img_buf:clear()
    for i,v in ipairs(particles) do
        local x=math.floor(v.x)
        local y=math.floor(v.y)
        local c=(v.count/max_count)*255
        img_buf:sset(x,y,{c,c,255,255})
    end
    write_img()
end
function populate(  )
    local vx,vy=rand_speed()
    particles={{x=map_w/2,y=map_h/8,vx=0,vy=1/41,count=41},{x=map_w/2,y=7*map_h/8,vx=0,vy=-1/5,count=5}}
    --particles={{x=map_w/2,y=map_h/2,vx=0,vy=0,count=50}}
end
populate()

function update(  )
    __no_redraw()
    __clear()

    particle_splits()
    particle_merge_and_map_update()
    particle_move(0.1)
    particle_draw()
    draw()

end