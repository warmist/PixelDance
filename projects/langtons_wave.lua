--[[
	langtons ant but a wavefront
		* each cell has direction and position
		* if nearby cells diverge, add new ones to have continous wavefront
		* instead of L/R actions that could be taken are:
			* Advance and Slowdown
				- Pro: simple, nice interaction with wave adding new cells
				- Cons: nothing happens on empty field
			* phase change - some sort of state change??
				-??
			* cw/ccw in the chain of particles - does nothing if ants are stateless
			* flip: fw->back
				- Pro: interesting, simple to create
				- Cons: collapses on empty field :| (maybe don't allow to step into same occupied tiles?)
--]]


require "common"
local map_w=256
local map_h=256
local cx=math.floor(map_w/2)
local cy=math.floor(map_h/2)
local dir_to_dx={ 1, 1, 0,-1,-1,-1, 0, 1}
local dir_to_dy={ 0,-1,-1,-1, 0, 1, 1, 1}
ruleset={
	{skip=0},
	{skip=1},
}
local rulecount=#ruleset

wavefront={
	
}
for i,v in ipairs(dir_to_dx) do
	local dx=v
	local dy=dir_to_dy[i]
	wavefront[i]={p=Point(cx+dx,cy+dy),d=i,skip=0}
end
grid=grid or make_float_buffer(map_w,map_h)
local default_height=1
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
--TODO: this should be fixed values i.e. gap has only few possible values
function mix(s,e,v)
  return (s+math.floor((e-s)*v+0.5))%8
end
function interpolate_dir( start_d,end_d,value )
	local delta=math.abs(end_d-start_d)
	if delta>4 then
	  return mix(end_d,start_d+8,1-value)
	else
		return mix(start_d,end_d,value)
	end
end
function create_new_cells( cell,last_cell,tbl )
	local delta=cell.p-last_cell.p
	local dx=delta[1]
	local dy=delta[2]

	local sdx=sign(dx)
	local sdy=sign(dy)

	if math.abs(dx)+math.abs(dy)==1 then --cells are connected - done
		return false
	end
	--note connected so we fill in the gap
	if math.abs(dx)>math.abs(dy) then
		local step_dy=dy/math.abs(dx)
		for i=1,math.abs(dx) do
			local p=Point(cell.p[1]+i*sdx,math.floor(cell.p[2]+step_dy*i+0.5))
			local d=interpolate_dir(cell.d,last_cell.d,i/math.abs(dx))+1
			table.insert(tbl,{p=p,d=d,skip=0})
		end
	else
		local step_dx=dx/math.abs(dy)
		for i=1,math.abs(dy) do
			local p=Point(math.floor(cell.p[1]+step_dx*i+0.5),cell.p[2]+i*sdy)
			local d=interpolate_dir(cell.d,last_cell.d,i/math.abs(dy))+1
			table.insert(tbl,{p=p,d=d,skip=0})
		end
	end
	return true
end
function step_cell( c )
	local dir=c.d
	c.p=c.p+Point(dir_to_dx[dir],dir_to_dy[dir])
end
function process_state_cell( c )
	if c.p[1]<0 then c.p[1]=map_w-1 end
	if c.p[1]>=map_w-1 then c.p[1]=0 end

	if c.p[2]<0 then c.p[2]=map_h-1 end
	if c.p[2]>=map_h-1 then c.p[2]=0 end

	if c.p[1]>=0 and c.p[1]<map_w-1 and c.p[2]>=0 and c.p[2]<map_h-1 then
		local v=math.floor(grid:get(c.p[1],c.p[2])*(rulecount-1))+1
		--set skip
		c.skip=ruleset[v].skip
		--change state
		local nv=v+1
		if nv>rulecount then
			nv=1
		end

		local new_value=(nv-1)/rulecount
		grid:set(c.p[1],c.p[2],new_value)
	end
end
function wave_advance(  )
	local new_wavefront={}
	--first advance all non skipped
	print("WF:",#wavefront)
	for i,v in ipairs(wavefront) do
		print(v,v.p,v.d,v.skip)
		--TODO: fix this so skipping only skips once and then continues
		--i.e. rules are: state(i.e. value) + skip/noskip, skip only delays the move one tick

		if v.skip==0 then
			step_cell(v)
			process_state_cell(v)
		else
			v.skip=v.skip-1
		end
	end
	--go over wavefront, removing cells where they overlap and filling in the gaps
	for i,v in ipairs(wavefront) do
		local c1=v
		local c2
		if i<#wavefront then c2=wavefront[i+1] else c2=wavefront[1] end
		if c1.p~=c2.p then --two cells overlapping
			if not create_new_cells(c1,c2,new_wavefront) then
				table.insert(new_wavefront,c1)
			end
		end		
	end
	wavefront=new_wavefront
end

function draw(  )
    draw_field.update(grid)
    draw_field.draw()
end

function update(  )
	if imgui.Button("Step") then
    	wave_advance()
    end
    __no_redraw()
    draw()
end