require 'common'
require 'kdgrid'
config=make_config({
    {"Advance",true}
    },config)

--[[
    TODO:
]]
local NUM_FUNCTION_DIMENSIONS=3
local point=GenPointN(NUM_FUNCTION_DIMENSIONS)


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

function pos_f( in_pos )
    local t=in_pos[1]
    local u=in_pos[2]
    local v=in_pos[3]
    local radius=60-u*8
    local p=5
    local r2=2
    local phi=t
    local r=math.cos(t*9)*(5-v)+radius+math.sin(t*3)*(1+v*2)
    --return math.cos(t)*radius+math.cos(t*p)*radius/r2+math.cos(t*p*3)*radius/3,math.sin(t)*radius+math.sin(t*p)*radius/r2+math.sin(t*p*3)*radius/3
    --return math.cos(t)*radius+math.cos(t*p)*radius/r2,math.sin(t)*radius+math.sin(t*p)*radius/r2
    local x=math.cos(t+p)*radius+math.cos(t*p)*radius/r2+math.cos(t*p*p)*(radius-v)/(r2*r2)
    local y=math.sin(t+p)*radius+math.sin(t*p)*radius/r2+math.sin(t*p*p)*(radius-v)/(r2*r2)
    --local x=math.cos(phi)*r
    --local y=math.sin(phi)*r
    return Point(x,y)
end
function reinit()
    grid:clear()
    states={}
    state_count=0
    cells={}
    cur_x=point(0)
    cur_col=0.5
    start_x=point(0)
    xcells_grid=kdgrid(NUM_FUNCTION_DIMENSIONS,0.05)
    start_y=pos_f(start_x)
    cur_y=pos_f(start_x)
    cell_grid={}
end
--if cur_x==nil then
    reinit()
--end

function connect_cell( a,b )
    a.links[b]=true
    b.links[a]=true
end
function find_cell( p )
    local x=math.floor(p[1]+0.5)+math.floor(grid.w/2)
    local y=math.floor(p[2]+0.5)+math.floor(grid.h/2)
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
    local x=math.floor(p[1]+0.5)+math.floor(grid.w/2)
    local y=math.floor(p[2]+0.5)+math.floor(grid.h/2)
    grid:set(x,y,v)
end
function advance(coord,dir,dist)
    return coord+dir*dist
end
function dist_sq( a,b )
    local p=a-b
    return p:len_sq()
end
function find_next_step_bisect( f, start_y, start_x, dir )
    function update_segment( s )
        s.x=advance(start_x,dir,s.t)
        s.y=f(s.x)
    end
    local t_eps=0.000001
    local max_step=10000
    local start_step=0.01
    local segment_min={t=0,y=start_y,x=start_x}
    local segment_max={t=start_step}
    function print_state( i )
        print(i)
        print("\t",segment_min.t,segment_min.x,segment_min.y)
        print("\t",segment_max.t,segment_max.x,segment_max.y)
    end
    update_segment(segment_max)
    function get_mdelta( s )
        local delta=start_y-s.y
        local mdelta=math.max(math.abs(delta[1]),math.abs(delta[2]))
        return mdelta
    end
    --print_state(-2)
    function increment_max(  )
        local old_t=segment_max.t
        --segment_max.t=segment_max.t*2-segment_min.t --move segment by t
        segment_max.t=segment_max.t*3-segment_min.t*2 --double the size of segment
        update_segment(segment_max)
        local m=get_mdelta(segment_max)
        if m<1 then
            --not overshot, all good
            segment_min.t=old_t
            update_segment(segment_min)
            return true
        end
        --overshot
        return false
    end

    --increment higher bound until we step over
    repeat
        local lower_m=increment_max()
        --print_state(-1)
    until not lower_m
    --now it should be that min is lower than 1 and max over 1

    function increment_min(  )
        local old_t=segment_min.t
        segment_min.t=(segment_min.t+segment_max.t)*0.5 --half the segment
        update_segment(segment_min)
        local m=get_mdelta(segment_min)
        if m<1 then
            return true
        else
            --revert
            --@perf could skip recalc here
            segment_min.t=old_t
            update_segment(segment_min)
            return false
        end

    end
    function decrement_max(  )
        local old_t=segment_max.t
        segment_max.t=(segment_max.t+segment_min.t)*0.5 --half the segment
        update_segment(segment_max)
        local m=get_mdelta(segment_max)
        if m>1 then
            return true
        else
            --revert
            --@perf could skip recalc here
            segment_max.t=old_t
            update_segment(segment_max)
            return false
        end

    end
    local doing_min=true
    for i=1,max_step do
        if doing_min then
            --print("min")
            doing_min=increment_min()
        else
            --print("max")
            doing_min=not decrement_max()
        end
        --print_state(i)
        if segment_max.t-segment_min.t<t_eps then
            --todo return midpoint?
            return true,segment_max.x,segment_max.y
        end
    end
    print("out of steps",segment_max.t-segment_min.t,segment_min.x,segment_max.x)
    return false,segment_min.x,segment_min.y
end

function find_next_step( f, ypos, xpos, dir )
    local max_step=1000
    local dt=0.005
    local targets={
        Point{1,0},Point{0,1},Point{-1,0},Point{0,-1},
        Point{1,1},Point{-1,1},Point{-1,-1},Point{1,-1}
    }
    local floor_y=Point(math.floor(ypos[1]),math.floor(ypos[2]))
    for k,v in ipairs(targets) do
        targets[k]=v+floor_y
    end

    local best_t=0
    local best_trg=ypos
    local best_dist=math.huge--dist_sq(ypos,{x=math.floor(ypos.x),y=math.floor(ypos.y)})
    local best_cid=0
    for i=1,max_step do
        local new_x=advance(xpos,dir,dt*i)
        local new_y=f(new_x)
        --print(string.format("Step: %d",i))
        local min_dist=math.huge
        for cid,v in ipairs(targets) do
            local dsq=dist_sq(new_y,v)
            --print(string.format("\tcid:%d dsq:%g",cid,dsq))
            if dsq<best_dist then
                best_trg=v
                best_dist=dsq
                best_t=dt*i
                best_cid=cid
            end
            if dsq<min_dist then
                min_dist=dsq
            end
        end
        --[[if min_dist>100 then
            break
        end]]
    end
    --print(best_dist,best_t,best_t/dt,best_cid,ypos.x,ypos.y,xpos.x,xpos.y)
    --[[if best_dist>0.05 then
        return false,advance(xpos,dir,dt*max_step)
    end]]
    return true,advance(xpos,dir,dt*best_t),best_trg
end
function link_cells( c,trg,dir )
    local reverse_dir={
        2,1,
        4,3,
        6,5
    }
    c.links[dir]=trg
    trg.links[reverse_dir[dir]]=c
end
function add_cells_around(f, cell )
    local dirs={
        {1,0,0},{-1,0,0},
        {0,1,0},{0,-1,0},
        {0,0,1},{0,0,-1},
    }
    local center=xcells_grid:get(cell.xpos)
    if center==nil then
        local c={x=point(cell.xpos),y=Point(cell.ypos),links={}}
        xcells_grid:set(cell.xpos,c)
        center=c
    end
    for i,d in ipairs(dirs) do
        local ok,nx,ny=find_next_step_bisect(f,cell.ypos,cell.xpos,point(d))
        if ok then
            local c=find_cell(ny)
            c.xpos=nx
            c.ypos=ny
            local xcell
            xcell=xcells_grid:get(nx)
            if xcell==nil then
                xcell={x=point(nx),y=Point(ny),links={}}
                xcells_grid:set(nx,xcell)
            end
            link_cells(center,xcell,i)
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
    if cur_y==nil then
        cur_y=Point()
    else
        local oc=find_cell(cur_y)
        if oc and oc.xpos then
            draw_and_links(oc,0.4,0.2)
        end
    end
    --local ok,new_x,new_y,i=find_next_step(pos_f,cur_y,cur_x,dir)
    local ok,new_x,new_y,i=find_next_step_bisect(pos_f,cur_y,cur_x,dir)
    if not ok then
        cur_x=new_x
    else
        -- [[
        --print(cur_y.x,cur_y.y,cur_x.x,cur_x.y,i)
        local c=find_cell(cur_y)
        if c.xpos ==nil then
            c.xpos=new_x
            c.ypos=cur_y
        end
        cur_x=new_x
        cur_y=new_y
        add_cells_around(pos_f,c)
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
    --[[local max_links=0
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
    end]]
    for k,v in pairs(cell_grid) do
        v.count=0
    end
    local max_pts=0
    for k,v in pairs(xcells_grid.data) do
        local c=find_cell(v.y)
        c.count=c.count+1
        if max_pts<c.count then max_pts=c.count end
    end
    for k,v in pairs(cell_grid) do
         draw_point(v.ypos,v.count/max_pts)
    end

    print(max_pts)
end
start_y=Point{0,0}
start_x=point{0,0}
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
    -- [[
    if (imgui.Button "Advance" or cur_x[1] >math.pi*2 )and config.Advance then
        cur_x[1]=0
        --[[local ok,new_x,new_y,i=find_next_step_bisect(pos_f,start_y,start_x,point{1,0})
        if ok then
            start_pos=new_y
            start_x=new_x

            cur_y=start_pos
            cur_x=start_x
            --for i=1,3 do--]]
            local a=point(cur_x)
            print(cur_x)
                advance_func(point{0,1,1})
            print(cur_x,a-cur_x)
            --cur_x[2]=cur_x[2]+0.1
            --cur_x[3]=cur_x[3]+0.1
        --[[    --end
            start_pos=cur_y
            start_x=cur_x
            cur_col=math.random()
        end
        
        --]]
        steps=0
    end
    --]]
    if imgui.Button "Color" then
        color_cells_by_links()
    end
    steps=steps+1
    imgui.Text(string.format("Unique states:%d",state_count))
    if config.Advance or imgui.Button "Step" then
        local a=point(cur_x)
        --if math.random()<0.991 then
            advance_func(point{1,0,0})
        --[[else
            if math.random()>0.5 then
                advance_func(point{0,1,1})
            else
                advance_func(point{0,-1,-1})
            end
        end]]
        --print(cur_x-a)
    end
    imgui.End()
    draw_grid(  )
    if need_save then
        save_img()
        need_save=false
    end
end