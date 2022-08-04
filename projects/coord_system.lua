require 'common'

config=make_config({
    {"Advance",true}
    },config)


local size=STATE.size
local zoom=4

grid=grid or make_float_buffer(math.floor(size[1]/zoom),math.floor(size[2]/zoom))
local draw_shader=shaders.Make[==[
#version 330
#line 13
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float count_steps;

vec3 palette(float v)
{
    vec3 a=vec3(0.5,0.5,0.5);
    vec3 b=vec3(0.5,0.5,0.5);
    /* blue-black-red
    vec3 c=vec3(0.25,0.3,0.4);
    vec3 d=vec3(0.5,0.3,0.2);
    //*/
    /*
    vec3 c=vec3(0.8,2.7,1.0);
    vec3 d=vec3(0.2,0.5,0.8);
    //*/
    /* gold and blue
    vec3 c=vec3(1,1,0.5);
    vec3 d=vec3(0.8,0.9,0.3);
    //*/
    ///* gold and violet
    vec3 c=vec3(0.5,0.5,0.45);
    vec3 d=vec3(0.6,0.5,0.35);
    //*/
    /* ice and blood
    vec3 c=vec3(1.25,1.0,1.0);
    vec3 d=vec3(0.75,0.0,0.0);
    //*/
    return a+b*cos(3.1459*2*(c*v+d));
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    float col=texture(tex_main,normed).x;

    if(count_steps>0)
        col=floor(col*count_steps)/count_steps;
#if 1
    color = vec4(palette(col),1);
#else
    col=pow(col,2.2);
    color.xyz=vec3(col);
    color.w=1;
#endif
}
]==]
grid_tex =grid_tex or textures.Make()
function draw_grid(  )
    draw_shader:use()
    grid_tex:use(0)
    grid:write_texture(grid_tex)
    draw_shader:set_i("tex_main",0)
    draw_shader:draw_quad()
    if need_save then
        save_img()
        need_save=nil
    end
end
cur_x=cur_x or {x=0,y=0}
cur_pos=cur_pos or {x=0,y=0}
state_count=0
states=states or {}
cells={} or cells
cell_grid={} or cell_grid
cur_col=0.5
function pos_f( in_pos )
    local t=in_pos.x
    local u=in_pos.y

    local radius=60-u
    local p=5
    local r2=2
    --return math.cos(t)*radius+math.cos(t*p)*radius/r2+math.cos(t*p*3)*radius/3,math.sin(t)*radius+math.sin(t*p)*radius/r2+math.sin(t*p*3)*radius/3
    --return math.cos(t)*radius+math.cos(t*p)*radius/r2,math.sin(t)*radius+math.sin(t*p)*radius/r2
    local x=math.cos(t)*radius--+math.cos(t*p)*radius/r2+math.cos(t*p*p)*radius/(r2*r2)
    local y=math.sin(t)*radius--+math.sin(t*p)*radius/r2+math.sin(t*p*p)*radius/(r2*r2)

    return {x=x,y=y}
end
function reinit()
    grid:clear()
    states={}
    state_count=0
    cells={}
    cur_x={x=0,y=0}
    cur_col=0.5
    start_x={x=0,y=0}
    start_pos=pos_f(start_x)
    cur_pos=pos_f(start_x)
end
reinit()
function connect_cell( a,b )
    a.links[b]=true
    b.links[a]=true
end
function find_cell( p )
    local x=math.floor(p.x+0.5)+math.floor(grid.w/2)
    local y=math.floor(p.y+0.5)+math.floor(grid.h/2)
    local idx=x+y*grid.w
    if cell_grid[idx] then
        return cell_grid[idx]
    else
        local nc={links={}}
        cell_grid[idx]=nc
        return nc
    end
end

function draw_point( p,v )
    local x=math.floor(p.x+0.5)+math.floor(grid.w/2)
    local y=math.floor(p.y+0.5)+math.floor(grid.h/2)
    grid:set(x,y,v)
end
function advance(coord,dir,dist)
    local ret={}
    for k,v in pairs(dir) do
        ret[k]=v*dist+coord[k]
    end
    return ret
end
function dist_sq( a,b )
    local ret=0
    for k,v in pairs(a) do
        local d=v-b[k]
        ret=ret+d*d
    end
    return ret
end
function find_next_step( f, ypos, xpos, dir )
    local max_step=10
    local dt=0.001
    local candidates={
        {x=1,y=0},{x=0,y=1},{x=-1,y=0},{x=0,y=-1},
        {x=1,y=1},{x=-1,y=1},{x=-1,y=-1},{x=1,y=-1}
    }
    for k,v in ipairs(candidates) do
        v.x=v.x+math.floor(ypos.x)
        v.y=v.y+math.floor(ypos.y)
    end
    local best_t=0
    local best_trg=ypos
    local best_dist=5--dist_sq(ypos,{x=math.floor(ypos.x),y=math.floor(ypos.y)})
    local best_cid=0
    for i=1,max_step do
        local new_x=advance(xpos,dir,dt*i)
        local new_y=f(new_x)
        --print(string.format("Step: %d",i))
        for cid,v in ipairs(candidates) do
            local dsq=dist_sq(new_y,v)
            --print(string.format("\tcid:%d dsq:%g",cid,dsq))
            if dsq<best_dist then
                best_trg=v
                best_dist=dsq
                best_t=dt*i
                best_cid=cid
            end
        end
    end
    print(best_dist,best_t,best_t/dt,best_cid)
    if best_dist>0.05 then
        return false,advance(xpos,dir,dt*max_step)
    end
    return advance(xpos,dir,dt*best_t),best_trg
end
function add_cells_around(f, cell )
    local dirs={
        {x=1,y=0},{x=-1,y=0},
        {x=0,y=1},{x=0,y=-1},
        --{x=1,y=1},{x=-1,y=-1},{x=-1,y=1},{x=1,y=-1}
    }
    for _,d in ipairs(dirs) do
        local nx,ny=find_next_step(f,cell.ypos,cell.xpos,d)
        if nx then
            local c=find_cell(ny)
            c.xpos=nx
            c.ypos=ny
            connect_cell(cell,c)
        end
    end
end
function draw_and_links( c,m,l )
    draw_point(c.ypos,m)
    for k,v in pairs(c.links) do
        draw_point(k.ypos,l)
    end
end
function advance_func( dir )
    if cur_pos==nil then
        cur_pos={x=0,y=0}
    else
        local oc=find_cell(cur_pos)
        if oc and oc.xpos then
            draw_and_links(oc,0.4,0.2)
        end
    end
    local new_x,new_y,i=find_next_step(pos_f,cur_pos,cur_x,dir)
    if not new_x then
        cur_x=new_y
    else
        -- [[
        --print(cur_pos.x,cur_pos.y,cur_x.x,cur_x.y,i)
        local c=find_cell(cur_pos)
        if c.xpos ==nil then
            c.xpos=new_x
            c.ypos=cur_pos
        end
        cur_x=new_x
        cur_pos=new_y
        --add_cells_around(pos_f,c)
        draw_and_links(c,1,cur_col)
        --]]
    end
end
function save_img(  )
    img_buf=img_buf or make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    config_serial=config_serial..serialize_config(config).."\n"
    img_buf:read_frame()
    img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function color_cells_by_links(  )
    local max_links=0
    for k,v in pairs(cell_grid) do
        local clinks=0
        for c,_ in pairs(v.links) do
            clinks=clinks+1
        end
        v.nlinks=clinks
        if max_links<clinks then
            max_links=clinks
            print(max_links)
        end
    end
    for k,v in pairs(cell_grid) do
        draw_point(v.ypos,v.nlinks/max_links)
    end
end
start_pos={x=0,y=0}
start_x={x=0,y=0}
steps=0
function update()
    __clear()
    __no_redraw()

    imgui.Begin("coord systems")
    draw_config(config)
    if imgui.Button "Save" then
        need_save=true
    end
    if imgui.Button "Clear" then
        reinit()
    end
    if imgui.Button "Clear Grid" then
        grid:clear()
    end
    if (imgui.Button "Advance" or steps >4000 )and config.Advance then
        local new_x,new_y,i=find_next_step(pos_f,start_pos,start_x,{x=1,y=0})
        if new_x then
            start_pos=new_y
            start_x=new_x

            cur_pos=start_pos
            cur_x=start_x
            --for i=1,3 do
                advance_func({x=0,y=1})
            --end
            start_pos=cur_pos
            start_x=cur_x
            cur_col=math.random()
        end
        steps=0
    end
    if imgui.Button "Color" then
        color_cells_by_links()
    end
    steps=steps+1
    imgui.Text(string.format("Unique states:%d",state_count))
    if config.Advance or imgui.Button "Step" then
        advance_func({x=1,y=0})
    end
    imgui.End()
    draw_grid(  )
    if need_save then
        save_img()
        need_save=false
    end
end