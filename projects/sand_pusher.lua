-- basically sisyphus table simulator
--[[
    TODO/ideas:
        * load sisyphus format files
--]]
require "common"
local map_w=256
local map_h=256

grid=grid or make_float_buffer(map_w,map_h)
local default_height=0.5
function init_grid(  )
    for x=0,map_w-1 do
        for y=0,map_h-1 do
            grid:set(x,y,default_height)
        end
    end
end
init_grid()


draw_field=init_draw_field(
[==[
#line __LINE__
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);
    //data.x*=data.x;
    color=vec4(data.xxx*0.5,1);
}
]==],
{
    uniforms={
    },
}
)


local shape_radius=5
--calculate shape if it's at shape_pos and you are checking at p
--returns "allowed height" at pos p
function shape( shape_pos,p )
    -- [[ sphere, d=0 => 0, d=r => h d>r => inf
    local height=1
    local const_r=shape_radius

    local rr=const_r*const_r

    local delta=p-shape_pos
    local l=delta:len_sq()
    if l>rr then
        return math.huge
    end
    return height*(l/rr)
    --]]
end
function tumble_sand( e,p )
    --if difference of sand at p vs 8 around is > allowed, spread sand around
    --spread as follows
    --figure out overmax and spread it to 8 around, taking into account shape limitations
    local max_allowed_delta=0.4
    local d=e-p
    --[[
    local dx={1,1,0,-1,-1,-1,0,1}
    local dy={0,-1,-1,-1,0,1,1,1}
    --]]
    local dx={1,0,-1,0}
    local dy={0,-1,0,1}
    local my_v=grid:get(p[1],p[2])
    local max_delta=0
    local sum_below=0
    local count_below=0
--    for i=1,8 do
    for i=1,4 do
        local x,y=p[1]+dx[i],p[2]+dy[i]
        if x>=0 and x<map_w and y>=0 and y<map_h then
            local v=grid:get(x,y)
            local d=my_v-v
            if d>max_delta then
                max_delta=d
            end
            if v<my_v then
                sum_below=sum_below+d
                count_below=count_below+1
            end
        end
    end
    if max_delta>max_allowed_delta then
        local moved=max_delta-max_allowed_delta
        grid:set(p[1],p[2],my_v-moved)
        --for i=1,8 do
        for i=1,4 do
            local x,y=p[1]+dx[i],p[2]+dy[i]
            if x>=0 and x<map_w and y>=0 and y<map_h then
                local v=grid:get(x,y)
                if v<my_v then
                    grid:set(x,y,v+moved/count_below)
                end
            end
        end
    end
    --if p:len_sq()<rr then

    --else

    --end
end
function sand_sim( e )
    local const_r=shape_radius
    local rr=const_r*const_r

    for i=1,5000 do
        local p=Point(math.random(0,map_w-1),math.random(0,map_h-1))
        tumble_sand(e,p)
    end
end
function push_sand( p,dir,amount )
    if dir>0 then
        local deltas={
            {dx={-1,-1,0},dy={0,1,1}},--top left corner
            {dx={-1,0,1},dy={1,1,1}},--top row
            {dx={0,1,1},dy={1,1,0}},--top right corner
            {dx={1,1,1},dy={1,0,-1}},--right row
            {dx={1,1,0},dy={0,-1,-1}},--bottom right corner
            {dx={1,0,-1},dy={-1,-1,-1}},--bottom row
            {dx={0,-1,-1},dy={-1,-1,0}},--bottom left corner
            {dx={-1,-1,-1},dy={-1,0,1}},--left row
        }
        local d=deltas[dir]

        --local w={math.random()*0.33,math.random()*0.33}
        --w[3]=1-w[1]-w[2]
        for i=1,3 do
            local x,y=p[1]+d.dx[i],p[2]+d.dy[i]
            --grid:set(x,y,grid:get(x,y)+amount*w[i])
            grid:set(x,y,grid:get(x,y)+amount/3)
        end
    elseif dir==0 then
        local dx={1,1,0,-1,-1,-1,0,1}
        local dy={0,-1,-1,-1,0,1,1,1}
        for i=1,8 do
            local x,y=p[1]+dx[i],p[2]+dy[i]
            grid:set(x,y,grid:get(x,y)+amount/8)
        end
    end
end
function teleport2( p )
    --move sphere from to e pushing stuff around
    local e=Point(math.floor(p[1]),math.floor(p[2]))
    --special logic for center tile
    local clear_value=0
    do
        local current_height=grid:get(e[1],e[2])
        local allowed_height=shape(e,Point(e[1],e[2]))
        if current_height>allowed_height then
            --remove overflow into the sand buffer
            --note: because we will do it in octants, set clear to 1/8 of overflow
            local overflow=current_height-allowed_height
            grid:set(e[1],e[2],current_height-overflow)
            clear_value=overflow/8
        end
    end
    local max_size=shape_radius
    --project sand into this buffer
    local sand_buffer={}
    local function clear(  )
        for i=0,max_size-1 do
            --[[
            if sand_buffer[i] then
                print(i,sand_buffer[i])
            end
            --]]
            sand_buffer[i]=clear_value/max_size
        end
    end

    local function calc_part_of_square( dx,dy,i )
        local ds = i/ max_size
        --float a = sqrt(ds*ds + 1);

        --float a =sqrt(dy / float(i) + 1);
        local dd = ds*dx / dy;
        local a = math.sqrt(dd*dd + 1);
        --if (i == 0)
        --  a = 1;
        return a
    end
    local function calculate_weights( dx,dy )
        --local slope = (math.atan((dx - 0.5) /dy) * 2) / math.pi
        local slope = (dx-0.5)/dy

        if slope < 0 then slope = 0 end
        local vslope = slope*max_size
        local min_v = math.floor(vslope)
    
        --local slope_end = 2 * math.atan((dx + 0.5) / dy) / math.pi
        local slope_end = (dx+0.5)/dy

        if slope_end > 1 then slope_end = 1 end
        local vslope_end = slope_end*max_size
        
        local max_v = math.floor(vslope_end);

        
        local t_val_s = vslope - min_v
        local t_val_e = vslope_end - max_v
        if max_v >= max_size then max_v = max_size - 1 end

        local ret={} --amount collected
        for i=0,max_size-1 do
            ret[i]=0
        end
        local w_total=0 --total weight
        --now two pass over the tiles, first collect all the weights, then collect weighted value
--[[ SMOOTH_ENDS
        for i=min_v+1,max_v-1 do
--]]
-- [[ !SMOOTH_ENDS
        for i=min_v,max_v do
--]]
            local a = calc_part_of_square(dx,dy,i);
            ret[i]=a
            w_total=w_total+a
        end
--[[SMOOTH_ENDS
        if min_v > 0 then
            local a = calc_part_of_square(dx, dy, min_v)
            ret[min_v]=ret[min_v]+(1-t_val_s)*a
            ret[min_v-1]=ret[min_v-1]+t_val_s*a
        else
            ret[0]=ret[0]+calc_part_of_square(dx, dy, 0)
        end
        
        if max_v < max_size - 1 then
            local a = calc_part_of_square(dx, dy, max_v)
            ret[max_v]=ret[max_v]+(1-t_val_e)*a
            ret[max_v+1]=ret[max_v+1]+t_val_e*a
            
        else
            ret[max_size-1]=ret[max_size-1]+calc_part_of_square(dx, dy, max_size - 1)
        end
--]]
        -- [[
        if w_total==0 then
            w_total=1
        end
        --]]
        for i=0,max_size-1 do
            ret[i]=ret[i]/w_total
        end
        return ret,w_total
    end
    local function remove_from_buffer_atan( dx,dy,amount_want)
        local w=calculate_weights(dx,dy)
        local ret=0
        for i,v in pairs(w) do
            if v>0 then
                local wanted=amount_want*v
                local got=math.min(sand_buffer[i],wanted)
                
                sand_buffer[i]=sand_buffer[i]-got
                ret=ret+got
            end
        end
        return ret
    end
    local function add_to_buffer_atan( dx,dy,amount_add )
        local w=calculate_weights(dx,dy)
        for i,v in pairs(w) do
            sand_buffer[i]=sand_buffer[i]+amount_add*v
        end
    end
    local function do_octant( sx,sy )
        clear()
        for dy=1,max_size do
            local ty=e[2]+dy*sy
            if ty<0 or ty>=map_h then
                return;
            end
            
            local start_x = dy;-- sqrt(max_size*max_size - dy*dy);
            --[[if max_size/math.sqrt(2)<dy then --circulization
                start_x = math.floor(math.sqrt(max_size*max_size - dy*dy)+0.5)
            end]]
            for dx = start_x,0,-1 do
                local tx = e[1] + dx*sx;
                -- [[
                local w=calculate_weights( dx,dy )
                --[==[
                print("DY:",dy,dx)
                local allowed_height=shape(e,Point(tx,ty))
                print("\t",math.sqrt(dx*dy+dy*dy),allowed_height)

                for i,v in pairs(w) do
                    --print("\t",i,v)

                end
                --]]
                --]==]
                if tx >= 0 and tx<map_w then
                    --do sand sample
                    local current_height=grid:get(tx,ty)
                    local allowed_height=shape(e,Point(tx,ty))
                    if dy==max_size then
                        allowed_height=math.huge
                    end
                    if current_height<allowed_height then
                        --try filling in from sand buffer
                        local amount_got=remove_from_buffer_atan(dx,dy,allowed_height-current_height)
                        grid:set(tx,ty,current_height+amount_got)
                    end
                end
            end
            for dx = start_x,0,-1 do
                local tx = e[1] + dx*sx;
                if tx >= 0 and tx<map_w then
                    local current_height=grid:get(tx,ty)
                    local allowed_height=shape(e,Point(tx,ty))
                    if dy==max_size then
                        allowed_height=math.huge
                    end
                    if current_height>allowed_height then
                        --remove overflow into the sand buffer
                        local overflow=current_height-allowed_height
                        grid:set(tx,ty,current_height-overflow)
                        add_to_buffer_atan(dx,dy,overflow)
                    end
                end
            end
        end
    end
    local function do_octant_swp( sx,sy )
        clear()
        for dx=1,max_size do
            local tx=e[1]+dx*sx
            if tx<0 or tx>=map_w then
                return
            end
            
            local start_y = dx;-- sqrt(max_size*max_size - dy*dy);
            --[[if max_size/math.sqrt(2)<dx then --circulization
                start_y = math.floor(math.sqrt(max_size*max_size - dx*dx))
            end]]
            for dy = start_y,0,-1 do
                local ty = e[2] + dy*sy;
                if ty >= 0 and ty<map_h then
                    --do sand sample
                    local current_height=grid:get(tx,ty)
                    local allowed_height=shape(e,Point(tx,ty))
                    if dx==max_size then
                        allowed_height=math.huge
                    end
                    if current_height<allowed_height then
                        --try filling in from sand buffer
                        local amount_got=remove_from_buffer_atan(dy,dx,allowed_height-current_height)

                        grid:set(tx,ty,current_height+amount_got)
                    end
                end
            end
            for dy = start_y,0,-1 do
                local ty = e[2] + dy*sy;
                if ty >= 0 and ty<map_h then
                    local current_height=grid:get(tx,ty)
                    local allowed_height=shape(e,Point(tx,ty))
                    if dx==max_size then
                        allowed_height=math.huge
                    end
                    if current_height>allowed_height then
                        --remove overflow into the sand buffer
                        local overflow=current_height-allowed_height
                        grid:set(tx,ty,current_height-overflow)
                        add_to_buffer_atan(dy,dx,overflow)
                    end
                end
            end
        end
    end
    do_octant(-1, -1)
    --TODO: this should all be 0
    --[[for i,v in pairs(sand_buffer) do
        print(i,v)
    end
    --]]
    -- [[
    do_octant(1, -1)
    do_octant(1, 1)
    do_octant(-1, 1)
    --]]
    -- [[
    do_octant_swp(-1, -1)
    do_octant_swp(1, -1)
    do_octant_swp(1, 1)
    do_octant_swp(-1, 1)
    --]]
end
function teleport( e )
    --move sphere from to e pushing stuff around
    --[[
        local min_x=math.floor(e[1]-shape_radius)
        local min_y=math.floor(e[2]-shape_radius)
        local max_x=math.floor(e[1]+shape_radius+0.5)
        local max_y=math.floor(e[2]+shape_radius+0.5)
    ]]
    local function proccess_pixel(pos,dir)
        --[[local dir=e-pos
        if dir:len_sq()>0.000000001 then
            dir:normalize() --todo perf
        else
            dir=nil
        end
        --]]
        local h=shape(e,pos)
        local value=grid:get(pos[1],pos[2])
        local new_value=math.min(h,value)
        grid:set(pos[1],pos[2],new_value)
        push_sand(pos,dir,value-new_value)
    end
    --process center first
    local center=Point(math.floor(e[1]),math.floor(e[2]))
    proccess_pixel(center,0)
    --now do the octants 
    --[[
        only edges are processed twice, maybe not an issue?
        \1|2/   
        8\|/3
        -x0x-
        7/|\4
        /6|5\
    --]]
    --or maybe not octants but just rectanges
    for i=1,shape_radius do
        --top left corner
        proccess_pixel(center+Point(-i,i),1)
        --line on top
        for dx=-i+1,i-1 do
            proccess_pixel(center+Point(dx,i),2)
        end
        --top right corner
        proccess_pixel(center+Point(i,i),3)
        --line on right
        for dy=i-1,-i+1,-1 do
            proccess_pixel(center+Point(i,dy),4)
        end
        --bottom right corner
        proccess_pixel(center+Point(i,-i),5)
        --line on bottom
        for dx=i-1,-i+1,-1 do
            proccess_pixel(center+Point(dx,-i),6)
        end
        --bottom left corner
        proccess_pixel(center+Point(-i,-i),7)
        --line on left
        for dy=-i+1,i-1 do
            proccess_pixel(center+Point(-i,dy),8)
        end
    end
    --new idea: collect overlap, deposit over next ring, repeat
    --how to fix the 4 lobes problem?
    --[[
        new idea:
            like projective lights in roguelike

            have a buffer or "collected sand" in distance
            each cell we pass either projects sand into the distance or deposits from the buffer
            just need mapping from "row"+"id" to "buffer id" + weight?

               3
              23
             123
            0123
             123
              23
               3
            0 maps fully into the buffer i.e. 0-n. Maybe weight 0.5 for 0th and nth id
            1-0 
    --]]        
end

function draw(  )
    draw_field.update(grid)
    draw_field.draw()
end
local my_p=Point(map_w/2,map_h/2)
teleport2(my_p)
--teleport2(my_p+Point(shape_radius/4,0))
local last_pos=my_p
local time=0
function update(  )
    local spiral_t=(time/12-math.floor(time/12))*100
    -- [==[
    local sphere_pos=my_p+Point(math.cos(time),math.sin(time))*spiral_t
   -- local sphere_pos=my_p+Point(math.cos(time+math.sin(time*0.05)*time),math.sin(time+math.sin(time*0.05)*time))*(60*(math.cos(time/4)*0.5+0.5)+10)
    --local sphere_pos=my_p
    local d=sphere_pos-last_pos
    local dl=d:len()
    local max_step=1
    if dl>max_step --[[and dl<20--]] then
        for i=0,1,max_step/dl do
            teleport2(last_pos+i*d)
        end
    else
        teleport2(sphere_pos)
    end
    last_pos=sphere_pos
    sand_sim(sphere_pos)
    --]==]
    __no_redraw()
    draw()
    time=time+0.05
end