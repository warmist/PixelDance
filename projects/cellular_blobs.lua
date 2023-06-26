--[[
    CA with rules always oriented to center of disjoint sets
    other ideas:
        * global (i.e. none) partition could point in one direction or e.g. center to the field
        * empty partions might be partitions or not
    Random ideas:
        * rotation of the rules is some sort of flowfield, that is slowly evolving?
        * or the flowfield reacts to the rules?
--]]

require "common"

map_w=256
map_h=256

neighborhood={
    --[[ von Neumann
    {1,0},
    {0,-1},
    {-1,0},
    {0,1},
    --]]
    -- [[ Moore
    {1,0},
    {1,-1},
    {0,-1},
    {-1,-1},
    {-1,0},
    {-1,1},
    {0,1},
    {1,1},
    --]]
}
ruleset_alive={
    [1]=1,
    --[2]=1,
    --[4]=1,
    --[8]=1,
}
ruleset_dead={
    [1]=1,
    --[2]=1,
    --[4]=1,
    --[8]=1,
}
function gen_ruleset()
    for i=0,255 do
        if math.random()>0.2 then
            ruleset_alive[i]=1
        else
            ruleset_alive[i]=0
        end
    end
        for i=0,255 do
        if math.random()>0.75 then
            ruleset_dead[i]=1
        else
            ruleset_dead[i]=0
        end
    end
    ruleset_dead[0]=0 --noblinking pls
    --ruleset[0]=0 --noblinking pls
    --[[
    local rr={
        1,2,4,8,16,32,64
    }
    ruleset[255]=1
    for i,v in ipairs(rr) do
        ruleset[255-v]=1
    end
    --]]
end
gen_ruleset()
--double buffered state of cells
buffers={make_char_buffer(map_w,map_h),make_char_buffer(map_w,map_h)}
function init_texture(  )
    cell_texture=textures:Make()
    cell_texture:use(0,1)
    cell_texture:set(map_w,map_h,U8_PIX)

    cell_id=textures:Make()
    cell_id:use(0,1)
    cell_id:set(map_w,map_h,U32_PIX)
end
init_texture()
function fill_buffers()
    --[[
    for y=0,map_h-1 do
        for x=map_w/4,map_w-1-map_w/4 do
            if math.random()>1*y/map_h then
                buffers[1]:set(x,y,1)
            else
                buffers[1]:set(x,y,0)
            end
        end
    end
    --]]
    local c=Point(map_w/2,map_h/2)
    local r=16
    for y=-r,r do
        for x=-r,r do
            buffers[1]:set(c[1]+x,c[2]+y,1)
        end
    end
end
fill_buffers()
--partition data
set_ids=make_u32_buffer(map_w,map_h)
partitions={}

--NB: not double buffered
function calculate_rotation(x,y )
    local id=set_ids:get(x,y).r
    local c
    if partitions[id]==nil then
        c=Point(map_w/2,map_h/2)
        --return 0
    else
        c=partitions[id].center
        --[[
        if math.random()>0.999  then
            print(x,y,c-Point(x,y))
        end
        ]]
    end
    local delta=c-Point(x,y)
    local angle=math.atan2(delta[2],delta[1])
    --[[
    ]]
--------------------------------------------
    --TODO
--------------------------------------------
    local rotation=math.floor(angle*4/math.pi+0.5)+4
    if rotation<0 then rotation=#neighborhood+rotation end
    return rotation
end
function get_looped( buffer,x,y )
    if x<0 then x=map_w+x end
    if y<0 then y=map_h+y end
    if x>=map_w then x=x-map_w end
    if y>=map_h then y=y-map_h end

    return buffer:get(x,y)
end
function set_looped( buffer,x,y,v )
    if x<0 then x=map_w+x end
    if y<0 then y=map_h+y end
    if x>=map_w then x=x-map_w end
    if y>=map_h then y=y-map_h end

    return buffer:set(x,y,v)
end
function lookup_nn(buffer, x,y )
    local ret={}
    for i,v in ipairs(neighborhood) do
        ret[i]=get_looped(buffer,x+v[1],y+v[2])
    end
    return ret
end
function apply_rule(buffer, x,y ,rotation)
    local ruleset=ruleset_dead
    if buffer:get(x,y)>0 then
        ruleset=ruleset_alive
    end
    local nn=lookup_nn(buffer,x,y)
    local compact_nn=0
    for i=1,#nn do
        if nn[i]>0 then
            local shift=(i-1+rotation)% #neighborhood
            compact_nn=bit.bor(compact_nn,bit.lshift(1,shift))
        end
    end
    
    --TODO offset rules by rotation
    return ruleset[compact_nn] or 0
end
--rules for von Neumann neighborhood of distance N or Moore of distance N
function do_rules(  )
    local current=buffers[1]
    local next=buffers[2]
    for y=0,map_h-1 do
        for x=0,map_w-1 do
            local rotation=calculate_rotation(x,y)
            --local rotation=0
            next:set(x,y,apply_rule(current,x,y,rotation))
        end
    end
end
--disjoint set algo for partioning with blob id in the cell and blob data in the list
function partition( buffer )
    local next_id=1
    local id_set=DisjointSet()
    --clear (optional??)
    for y=0,map_h-1 do
        for x=0,map_w-1 do
            set_ids:set(x,y,{0})
        end
    end

    for y=0,map_h-1 do
        for x=0,map_w-1 do
            if buffer:get(x,y)>0 then
                local processed_tiles={}
                local min_id=math.huge
                if y>0 then
                    for tx=-1,1 do
                        if x+tx>=0 and x+tx<map_w then
                            local v=set_ids:get(x+tx,y-1).r
                            if v>0 then
                                table.insert(processed_tiles,v)
                                if min_id>v then min_id=v end
                            end
                        end
                    end
                end
                if x-1>=0 then
                    local v=set_ids:get(x-1,y).r
                    if v>0 then
                        table.insert(processed_tiles,v)
                        if min_id>v then min_id=v end
                    end
                end
                if #processed_tiles>0 then
                    --assign smallest label and connect all labels into one set
                    set_ids:set(x,y,{min_id})
                    for i,v in ipairs(processed_tiles) do
                        id_set:union(min_id,v)
                    end
                else
                    --create new label
                    set_ids:set(x,y,{next_id})
                    id_set:make_set(next_id)
                    next_id=next_id+1

                end
            end
        end
    end
    --second pass
    for y=0,map_h-1 do
        for x=0,map_w-1 do
            if buffer:get(x,y)>0 then
                local v=id_set:find(set_ids:get(x,y).r)
                set_ids:set(x,y,{v})
            end
        end
    end
end
function update_partition_data()
    partitions={}
    for y=0,map_h-1 do
        for x=0,map_w-1 do
            local id=set_ids:get(x,y).r
            local p=partitions[id]
            if p==nil then
                p={center=Point(0,0),count=0}
                partitions[id]=p
            end
            p.center=p.center+Point(x,y)
            p.count=p.count+1
        end
    end

    for k,v in pairs(partitions) do
        v.center=v.center/v.count
    end
    --[=[
    local new_partitions={}
    for i,v in pairs(partitions) do
        table.insert(new_partitions,{old_id=i,center=v.center/v.count,count=v.count})
    end
    table.sort(new_partitions,function ( a,b )
        --[[
        if a.center[1]==b.center[1] then
            return a.center[2]>b.center[2]
        else
            return a.center[1]>b.center[1]
        end
        --]]
        return a.center:len_sq()>b.center:len_sq()
    end)
    partitions=new_partitions
    local reverse_lookup={}
    for i,v in ipairs(new_partitions) do
        reverse_lookup[v.old_id]=i
    end
    for y=0,map_h-1 do
        for x=0,map_w-1 do
            local id=set_ids:get(x,y).r
            if id>0 then
                set_ids:set(x,y,{reverse_lookup[id]})
            end
        end
    end
    --]=]
end

local draw_shader=shaders.Make[==[
#version 330
#line __LINE__
out vec4 color;
in vec3 pos;


uniform sampler2D tex_main;
uniform usampler2D tex_id;

uniform float gamma_value;

vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec3 id_to_color(uint id)
{
    float t=float(id)*0.0001;
    return palette(t,vec3(0.5),vec3(0.5),vec3(0.4,0.35,0.30),vec3(0.5,0.45,0.3));
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    normed.y=1-normed.y;

    float v=texture(tex_main,normed).x>0?1:0;
    #if 1
        uint val=texture(tex_id,normed).x;
        vec3 col=id_to_color(val).xyz;
        if(val==0u)
            col=vec3(0);
    #else
        vec3 col=vec3(v*0.8);
    #endif
    //col.r=1;
    color = vec4(col,1);
}
]==]
function draw()
    buffers[2]:write_texture(cell_texture)
    set_ids:write_texture(cell_id)

    draw_shader:use()
    cell_texture:use(0)
    cell_id:use(1)

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("tex_id",1)
    draw_shader:draw_quad()

end

function save_img( path )
    local size=STATE.size
    local img_buf_save=make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config or {}) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    img_buf_save:save(path or string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function nicefy_partitions(  )
    --try to stabilize the id somehow...
    for y=0,map_h-1 do
        for x=0,map_w-1 do
            local id=set_ids:get(x,y).r
            if id>0 then
                local c=partitions[id].center
                local hash=math.floor(c[1]+c[2]*map_w)
                set_ids:set(x,y,{hash})
            end
        end
    end
end
once=true
function update(  )
    __no_redraw()
    __clear()
    --if once then
    local need_swap=false
    if imgui.Button("Step") or true then
        partition(buffers[1])
        update_partition_data()
        do_rules()
        nicefy_partitions()
        --once=false
        --end
        need_swap=true
    end
    draw()

    if imgui.Button("Save") then
        save_img()
    end
    -- [[
    if need_swap then
        local lb=buffers[1]
        buffers[1]=buffers[2]
        buffers[2]=lb
    end
    --]]
end