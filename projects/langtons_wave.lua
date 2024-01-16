--[[
	langtons ant but a wavefront
		* each cell has direction and position
		* if nearby cells diverge, add new ones to have continous wavefront
		* instead of L/R actions that could be taken are Advance and Slowdown
--]]




require "common"
local map_w=256
local map_h=256
local cx=math.floor(map_w/2)
local cy=math.floor(map_h/2)
local dir_to_dx={ 1, 1, 0,-1,-1,-1, 0, 1}
local dir_to_dy={ 0,-1,-1,-1, 0, 1, 1, 1}
wavefront={
	
}
for i,v in ipairs(dir_to_dx) do
	local dx=v
	local dy=dir_to_dy[i]
	wavefront[i]={p=Point(cx+dx,cy+dy),d=Point(dx,dy),skip=0}
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
function interpolate_dir( start_d,end_d,value )
	--TODO
end
function create_new_cells( cell,last_cell,tbl )
	local delta=cell.p-last_cell.p
	local dx=delta[1]
	local dy=delta[2]

	local sdx=sign(dx)
	local sdy=sign(dy)

	if math.abs(dx)+math.abs(dy)==1 then --cells are connected - done
		return
	end
	--note connected so we fill in the gap
	if math.abs(dx)>math.abs(dy) then
		local step_dy=dy/math.abs(dx)
		for i=1,math.abs(dx) do
			local p=Point(cell.p[1]+i*sdx,math.floor(cell.p[2]+step_dy*i+0.5))
			local d=interpolate_dir(cell.d,last_cell.d,i/math.abs(dx))
			table.insert(tbl,{p=p,d=d,skip=0})
		end
	else
		local step_dx=dx/math.abs(dy)
		for i=1,math.abs(dy) do
			local p=Point(math.floor(cell.p[1]+step_dx*i+0.5),cell.p[2]+i*sdy)
			local d=interpolate_dir(cell.d,last_cell.d,i/math.abs(dy))
			table.insert(tbl,{p=p,d=d,skip=0})
		end
	end
end
function step_cell( c )
	local dir=c.d
	c.p=c.p+Point(dir_to_dx[dir],dir_to_dy[dir])
end
function wave_advance(  )
	local new_wavefront={}
	--first advance all non skipped
	for i,v in ipairs(wavefront) do
		set_value_at(v)
		if v.skip==0 then
			step_cell(v)
		else
			v.skip=v.skip-1
		end
	end
	local last_c
	for i,v in ipairs(wavefront) do
		if last_c==nil or last_c.p~=v.p then
			create_new_cells(v,last_c,new_wavefront)
			last_c=c
			table.insert(new_wavefront,last_p)
		end
	end
end

function draw(  )
    draw_field.update(grid)
    draw_field.draw()
end

function update(  )
    wave_advance()
    __no_redraw()
    draw()
end