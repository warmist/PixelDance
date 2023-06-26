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
    -- [[ von Neumann
    {1,0},
    {0,-1},
    {-1,0},
    {0,1},
    --]]
}
ruleset={
    [13]=1
}
--double buffered state of cells
buffers=buffers or {make_char_buffer(map_w,map_h),make_char_buffer(map_w,map_h)}
function fill_buffers()
    for y=0,map_h-1 do
        for x=0,map_w-1 do
            if math.random()>0.7 then
                buffers[1]:set(x,y,1)
            else
                buffers[1]:set(x,y,0)
            end
        end
    end
end
--partition data
set_ids=make_u32_buffer(map_w,map_h)
partitions={}

--NB: not double buffered
function calculate_rotation(x,y )
    local id=set_ids:get(x,y)
    if partitions[id]==nil then
        return 0
    end
    local c=partitions[id].center
    local delta=c-Point(x,y)

--------------------------------------------
    --TODO
--------------------------------------------

    return -1 
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
    local nn=lookup_nn(buffer,x,y)
    local compact_nn=0
    for i=1,#nn do
        if nn[i]>0 then
            compact_nn=bit.bor(compact_nn,bit.lshift(1,(i-1)))
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
                            local v=set_ids:get(x+tx,y-1)
                            if v>0 then
                                table.insert(processed_tiles,v)
                                if min_id>v then min_id=v end
                            end
                        end
                    end
                end
                if x-1>=0 then
                    local v=set_ids:get(x-1,y)
                    if v>0 then
                        table.insert(processed_tiles,v)
                        if min_id>v then min_id=v end
                    end
                end
                if #processed_tiles>0 then
                    --assign smallest label and connect all labels into one set
                    set_ids:set(x,y,min_id)
                    for i,v in ipairs(processed_tiles) do
                        id_set:union(min_id,v)
                    end
                else
                    --create new label
                    set_ids:set(x,y,next_id)
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
                id_set:set(x,y,id_set:find(id_set:get(x,y)))
            end
        end
    end            
end
function update_partition_data()
    partitions={}
    for y=0,map_h-1 do
        for x=0,map_w-1 do
            local id=set_ids:get(x,y)
            local p=partitions[id]
            if p==nil then
                p={center=Point(0,0),count=0}
                partitions[id]=p
            end
            p.center=p.center+Point(x,y)
            p.count=p.count+1
        end
    end
end
function draw()
    --------------------------------------------
    --TODO
    --------------------------------------------
end
function update(  )
    partition(buffers[1])
    update_partition_data()
    do_rules()
    draw()
end 