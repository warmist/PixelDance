--[===[
    * allow changes (i.e. no longer only move)
    * all cells have "movement direction" (which can be no movement)
    * optional - only have "reactions" when collision would happen
    * allow only changes that preserve some quantities
        * momentum (i.e. mass+direction+(speed?))
            - only 8( 9 if no movement) directions so some combinations not allowed
        * "scalar" - i.e. any tag on the particle, that has some relation
            - or alternatively try deduce these from reactions
            - e.g:
                - charge: (sum before = sum after, can be +1/-1 and/or partials?)
                - color: (r+g+b=w, w+(-g)+(-b)=r, etc...)
                - mass: a bit complicated? but probably like charge with only positive
        * "group" - i.e. any set that has a neutral element (e.g. 0) and an operation (+)
            
    * also some properties are part of particle type some are not
        - velocity is seperate
        - other are not
    TODO:
        * add non-stochastic momentum
        * for now simpler rules, todo more complex?
        * apply rules only when "colliding"
        * add a partial momentum requirement 
            (i.e. i want one of outputs have X probably 0/non0 to be rotation agnostic)
        * self destroy not supported
    ISSUES:
        * no "agreed upon" priority if two recipes match
    RANDOM:
        * add vacuum energy like thing
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
local MAX_ATOM_TYPES=2


function init_arrays(  )
    particles=particles or {}
    local p=particles
    p.count=0
    p.pos=make_flt_half_buffer(max_particle_count,1)
    p.type=make_char_buffer(max_particle_count,1)
    p.dir=make_char_buffer(max_particle_count,1)


    grid=grid or {}
    local g=grid
    g.type=make_char_buffer(map_w,map_h)
    g.dir=make_char_buffer(map_w,map_h)
    g.move_to=make_char_buffer(map_w,map_h)
end

rules=rules or {
--example rules
-- [==[ split-recombine
    [1]={{match={2},change_self=2,create={2}}} --when 2 is around split
    [2]={{match={2},change_self=1,destroy={2}}} --when another of 2 is around, combine
--]==]

}
--[==[
    movement (i.e. momentum) rules
    allowed transformations:
        generate dx,dy sum, check if inverse exists

--]==]

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
anti_dir={
    [0]=0,
    [1]=5,
    [2]=6,
    [3]=7,
    [4]=8,
    [5]=1,
    [6]=2,
    [7]=3,
    [8]=4,
}
function dx_to_dir( dx,dy )
    local anti_dx={
        [-1]={[-1]=6,[0]=5,[1]=4},
        [0]={[-1]=7,[0]=0,[1]=3},
        [1]={[-1]=8,[0]=1,[1]=2},
    }
    return anti_dx[dx][dy]
end
function dx_to_dir_safe( dx,dy )
    local anti_dx={
        [-1]={[-1]=6,[0]=5,[1]=4},
        [0]={[-1]=7,[0]=0,[1]=3},
        [1]={[-1]=8,[0]=1,[1]=2},
    }
    local d1=anti_dx[dx]
    if d1 then
        return d1[dy]
    else
        return nil
    end
end
function enumerate_allowed_momentums( )
    --A+B=C style
    --OR A=C-B (i.e. B is inverted in that case)
    --etc...
    for i=0,8 do
        local di=dir_to_dx[i]
        for j=0,8 do
            local dj=dir_to_dx[j]
            local sdx=di[1]+dj[1]
            local sdy=di[2]+dj[2]
            local odir=dx_to_dir_safe(sdx,sdy)
            if odir then
                print(i,j,sdx,sdy,odir)
            end
        end
    end
end
function enumerate_allowed_momentums_ex(depth,tbl )
    if depth==0 then
        return tbl
    end
    local new_tbl={}
    if tbl==nil then
        for i=0,8 do
            local d=dir_to_dx[i]
            local nk=tostring(i)
            new_tbl[nk]={dx=d[1],dy=d[2]}  
        end

    else
        for i=0,8 do
            for k,v in pairs(tbl) do
                local d=dir_to_dx[i]
                local nk=k..tostring(i)
                
                new_tbl[nk]={dx=v.dx+d[1],dy=v.dy+d[2]}
            end
        end
    end
    return enumerate_allowed_momentums_ex(depth-1,new_tbl)
end
function enum_rules( pos,type,vel,around_type,around_vel,count_around)
    local my_rules=rules[type]
    local ret_rules={}
    for i,v in ipairs(my_rules) do
        local add=true
        do
            local count_before=1+count_around
            --check if we have space to add
            if count_around+v.create-v.destroy>8 then
                add=false
                break
            end
            --check if we match all of the "match"
            local ok,matching=try_match(around_type,v.match)
            if not ok then
                add=false
                break
            end
            local count_involved=1+#matching
            local count_after=count_involved+v.create-v.destroy
            --check if momentum sums can exist

        while false
    end
end
function list_momentums( depth )
    local t=enumerate_allowed_momentums_ex(depth)
    local count=0
    local count_max=0
    for k,v in pairs(t) do
        local dir=dx_to_dir_safe(v.dx,v.dy)
        if dir then
          print(k,dir)
          count=count+1
        end
        count_max=count_max+1
    end
    print("Total:",count," out of ",count_max," percent",math.floor(count*100/count_max))
end
function apply_rule( rule,pos,type,vel,around_type,around_vel )
    
    local valid_momentum=enum_valid_momentum(m,v.result)
    if #valid_momentum>0 then
        --only transform if at least one valid momentum exist
        table.insert(results,{v,valid_momentum})
    end
    shuffle_table(momentums)
    for _,chosen_momentum in ipairs(momentums) do
        
    end
end
function fix_pos( x,y )
    x=math.floor(x)
    y=math.floor(y)

    if x<0 then x=map_w-1 end
    if y<0 then y=map_h-1 end
    if x>=map_w then x=0 end
    if y>=map_h then y=0 end

    return x,y
end
function get_around( pos )
    local ret_type={}
    local ret_dir={}
    local count=0
    for i=1,8 do
        local dx=dir_to_dx[i]
        local dy=dir_to_dy[i]

        local tx=pos[1]+dx
        local ty=pos[2]+dy
        tx,ty=fix_pos(tx,ty)

        ret_dir[i]=grid.dir:get(tx,ty)
        local t=grid.type:get(tx,ty)
        ret_type[i]=t

        if t>0 then
            count_around=count_around+1
        end
    end
    return ret_type,ret_dir,count_around
end
function find_and_apply_rule(pid)
    local pos=particles.pos[pid]
    local type=particles.type[pid]
    local vel=particles.dir[pid]
    --TODO: rule needs to be sure that if A+B=C that B+A=C
    --get stuff around the atom
    local around_type,around_vel,count_around=get_around(pos)
    --get applicable rules
    local applicable_rules=enum_rules(pos,type,vel,around_type,around_vel,count_around)
    if #applicable_rules==0 then
        return
    end
    shuffle_table(applicable_rules)
    for _,rule in ipairs(applicable_rules) do
        if apply_rule(rule,pos,type,vel,around_type,around_vel,count_around) then
            return
        end
    end
end