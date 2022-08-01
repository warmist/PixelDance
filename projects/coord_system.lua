require 'common'

config=make_config({

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
function reinit()
    grid:clear()
    states={}
    state_count=0
    cells={}
    cur_x={x=0,y=0}
    cur_pos=nil
    cur_col=0.5
end
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
function pos_f( in_pos )
    local t=in_pos.x
    local u=in_pos.y

    local radius=35
    local p=5
    local r2=2+u
    --return math.cos(t)*radius+math.cos(t*p)*radius/r2+math.cos(t*p*3)*radius/3,math.sin(t)*radius+math.sin(t*p)*radius/r2+math.sin(t*p*3)*radius/3
    --return math.cos(t)*radius+math.cos(t*p)*radius/r2,math.sin(t)*radius+math.sin(t*p)*radius/r2
    local x=math.cos(t)*radius+math.cos(t*p)*radius/r2+math.cos(t*p*p)*radius/(r2*r2)
    local y=math.sin(t)*radius+math.sin(t*p)*radius/r2+math.sin(t*p*p)*radius/(r2*r2)

    return {x=x,y=y}
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
function find_next_step( f, ypos, xpos, dir )
    local max_step=100000
    local dt=0.001
    for i=1,max_step do
        local new_x=advance(xpos,dir,dt*i)
        local new_y=f(new_x)
        if math.floor(new_y.x+0.5)~=math.floor(ypos.x+0.5) or
           math.floor(new_y.y+0.5)~=math.floor(ypos.y+0.5) then
            return new_x, new_y,i
        end
    end
    return false,advance(xpos,dir,dt*max_step)
end
function add_cells_around(f, cell )
    local dirs={
        {x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1}
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
        --print(cur_pos.x,cur_pos.y,cur_x.x,cur_x.y,i)
        local c=find_cell(cur_pos)
        if c.xpos ==nil then
            c.xpos=new_x
            c.ypos=cur_pos
        end
        cur_x=new_x
        cur_pos=new_y
        add_cells_around(pos_f,c)
        draw_and_links(c,1,cur_col)
    end
end
function save_img(  )
    img_buf=img_buf or make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    config_serial=config_serial..serialize_config(config).."\n"
    img_buf:read_frame()
    img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
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
    if imgui.Button "Advance" then
        advance_func({x=0,y=1})
        cur_col=math.random()
    end
    imgui.Text(string.format("Unique states:%d",state_count))
    imgui.End()
    advance_func({x=1,y=0})
    draw_grid(  )
    if need_save then
        save_img()
        need_save=false
    end
end