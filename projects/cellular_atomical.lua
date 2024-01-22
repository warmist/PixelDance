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
    * also some properties are part of particle type some are not
        - velocity is seperate
        - other are not

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

rules=rules or {}
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
list_momentums(3)
function apply_rule()
    
end