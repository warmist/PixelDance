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


    REDO 1:
        * simplify rules:
            - only apply when colliding
            - all are matching equally
            - place by:
                - momentum or random
                - semi random (i.e. so that it would not hit collision center)

    RANDOM:
        * add vacuum energy like thing
            - i.e. particles appear and dissapear with some constrains
        * light-like particles: raycast a line if hitting anything react
            A) destroy (convert) when failing reaction
            B) stop at "valid location" (randomize momentum somehow?)


--]===]
require 'common'
require 'bit'
local gen_assign=require 'set_select'
local win_w=1024
local win_h=1024

--__set_window_size(win_w,win_h)
local oversample=1/16

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size
local MAX_ATOM_TYPES=3
local max_particle_count=10000

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
init_arrays()
function get_particle_next_pos( pid ,pos)
    local dir=particles.dir:get(pid,0)

    if dir==0 then
        --TODO: no floor here :|
        return pos.r,pos.g
    end

    local x=math.floor(pos.r)
    local y=math.floor(pos.g)

    local tx,ty=fix_pos(dir_to_dx[dir][1]+x,dir_to_dx[dir][2]+y)

    return tx,ty
end
function particle_move( pid )
    local dir=particles.dir:get(pid,0)
    if dir==0 then --not moving so nothing todo
        return
    end
    local pos=particles.pos:get(pid,0)
    local x=math.floor(pos.r)
    local y=math.floor(pos.g)
    --remove at pos
    --local ptype=grid.type:get(x,y)
    local ptype=particles.type:get(pid,0)
    grid.type:set(x,y,0)
    --grid.dir:set(x,y,0) --optional

    --increment pos by velocity
    x=x+dir_to_dx[dir][1]
    y=y+dir_to_dx[dir][2]
    x,y=fix_pos(x,y)
    --add at new pos
    --if dir==0 then
        grid.type:set(x,y,ptype)
    --end
    grid.dir:set(x,y,dir)

    particles.pos:set(pid,0,{r=x,g=y})
end
function particle_add( x,y,type,dir )
    local old_count=particles.count
    particles.dir:set(old_count,0,dir)
    particles.type:set(old_count,0,type)
    particles.pos:set(old_count,0,{r=x,g=y})

    grid.type:set(x,y,type)
    grid.dir:set(x,y,dir)
    particles.count=particles.count+1
    return particles.count-1
end
math.randomseed(os.time())
for i=1,3000 do
    particle_add(math.random(0,map_w-1),math.random(0,map_h-1),math.random(1,MAX_ATOM_TYPES),math.random(0,8))
end
function particle_remove( pid )
    local old_count=particles.count-1

    particles.dir:set(pid,0,particles.dir:get(old_count,0))
    particles.type:set(pid,0,particles.type:get(old_count,0))
    particles.pos:set(pid,0,particles.pos:get(old_count,0))
    particles.count=particles.count-1
    return particles.count
end
rules=rules or {
--example rules
--[==[ split-recombine
    [1]={{match={2},change_self=2,create={2}}} --when 2 is around split
    [2]={{match={2},change_self=1,destroy={2}}} --when another of 2 is around, combine
--]==]
    {match={1,2},out={2,2,2}},
    {match={2,2},out={1}},
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

function enum_rules_new( pos,around_type,around_vel,count_around)

    --first do all partial matches for rules
    --TODO: might include all in the result, but for now match biggest part
    local ret_rules={}
    for i,v in ipairs(rules) do
        local add=true
        local to_add={rule=v}
        do

            local count_possible,iterator=gen_assign(around,rule)
            --print('\t',i,v[1],v[2],rule[v[1]],around[v[2]])
            if count_possible==0 then
                add=false
                break
            end
            --TODO: list all pick rand?
            to_add.assignment=iterator()

            --check if we have space to add
            local diff=#rule.out-#rule.match
            local count_before=count_around
            if count_around+diff>9 then
                add=false
                break
            end
            --check if momentum sums can exist
            local momentum_sum=get_sum(around_vel,to_add.assignment)
            local momentum_out=get_valid_momentum(momentum_sum,v.out)
            if momentum_out==nil then
                add=false
                break
            end
            to_add.momentum_out=momentum_out
        end
        if add then
            table.insert(ret_rules,to_add)
        end
    end
    return ret_rules
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
        end
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
function apply_rule( rule)

    local valid_momentum=enum_valid_momentum(rule,v.result)
    local momentums
    if #valid_momentum==0 then
        --only transform if at least one valid momentum exist
        return 0
    end
    shuffle_table(valid_momentum)
    for _,chosen_momentum in ipairs(valid_momentum) do

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
    for i=0,8 do
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
function find_and_apply_rule(colliding)
    --get applicable rules
    local applicable_rules=enum_rules(around_type,around_vel,count_around)
    if #applicable_rules==0 then
        return 0
    end
    --TODO: option to shuffle all rules
    --shuffle_table(applicable_rules)
    --TODO more than one rule per "tick"
    if apply_rule(applicable_rules[0]) then --TODO: this might fail due to momentum. Maybe try another one?
        return 1
    end
    return 0
end
function redistribute_momentum( members )
    local tbl={}
    for i,v in ipairs(members) do
        local d=particles.dir:get(v,0)
        tbl[i]=d
    end
    shuffle_table(tbl)
    for i,v in ipairs(members) do
        particles.dir:set(v,0,tbl[i])
    end
end
function resolve_collision( colliding)
    --try applying rules
    --if failed and/or rest of stuff exchanges momentum somehow...
    --TODO: alternative here would pull in rest of stuff around
    --pull_in_stuff(colliding)
    --get info about ids
    local particle_types
    local particle_momentums
    --NB: this should not remove "removed particles" as colliding is invalidated then
    find_and_apply_rule(colliding)

    --i.e. like it had rule match=out="exact match after rules"
    --local around=get_around(pos)
    redistribute_momentum(colliding)
end
function remove_dead(  )
    --go over all, and remove type -1
    local i=0
    while i<particles.count do
        if particles.type:get(i,0)==-1 then
            particle_remove(i)
        else
            i=i+1
        end
    end
end
function sim_tick(  )
    local g=grid
    --clear grid
    local function clear_grid(  )
        for x=0,map_w-1 do
        for y=0,map_h-1 do
            g.move_to:set(x,y,0)
        end
        end
    end
    local function update_moves(  )
        --for each particle
        for i=0,particles.count-1 do
            --add to <move to buffer>
            local pos=particles.pos:get(i,0)
            local x=math.floor(pos.r)
            local y=math.floor(pos.g)
            --add to current location
            g.move_to:set(x,y,g.move_to:get(x,y)+1)
            --add to next location
            local tx,ty=get_particle_next_pos(i,pos)
            g.move_to:set(tx,ty,g.move_to:get(tx,ty)+1)
        end
    end
    clear_grid()
    update_moves()
    -- [[
    --calculate collisions
    --collision format: x,y and list of ids
    local collisions={}
    
    for i=0,particles.count-1 do
        --check if it's only particle moving into the tile
        local pos=particles.pos:get(i,0)
        local tx,ty=get_particle_next_pos(i,pos)
        local trg_move=g.move_to:get(tx,ty)
        if trg_move==1 then
            --moving will be done after collision resolution
        else
            -- if not add to a list of collisions to resolve
            --table.insert(collisions,{x,y})
            local idx=tx+ty*map_w
            collisions[idx]=collisions[idx] or {x=tx,y=ty}
            table.insert(collisions[idx],i)
        end
    end

    for i,v in pairs(collisions) do
        --TODO: we could use <only involved in collision> or "quantum effects" pull in stuff around
        --TODO: could recover x/y from id
        resolve_collision(v)
    end
    remove_dead()
    clear_grid()
    update_moves()
    for i=0,particles.count-1 do
        --check if it's only particle moving into the tile
        local pos=particles.pos:get(i,0)
        local tx,ty=get_particle_next_pos(i,pos)
        local trg_move=g.move_to:get(tx,ty)
        if trg_move==1 then
            -- if yes, move
            particle_move(i)
        else
            --do nothing, we will do collisions next step
        end
    end
    
    --]]
end
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
    float normed_particle=data.x*255/5;
    vec3 c=palette(normed_particle,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
    color=vec4(c,1);
    
}
]==],
{
    uniforms={
    },
}
)
function draw(  )
    draw_field.update(grid.type)
    draw_field.draw()   
end

function update(  )
    __no_redraw()
    sim_tick()
    draw()
end