-- basically sisyphus table simulator
--[[
	TODO/ideas:
		* load sisyphus format files
--]]
require "common"
local map_w=256
local map_h=256

grid=make_float_buffer(map_w,map_h)
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
	local max_allowed_delta=0.8
	local d=e-p
	local dx={1,1,0,-1,-1,-1,0,1}
	local dy={0,-1,-1,-1,0,1,1,1}
	local my_v=grid:get(p[1],p[2])
	local max_delta=0
	local sum_below=0
	local count_below=0
	for i=1,8 do
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
		for i=1,8 do
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
end

function draw(  )
	draw_field.update(grid)
	draw_field.draw()
end
local my_p=Point(map_w/2,map_h/2)
local last_pos=my_p
local time=0
function update(  )
	local spiral_t=(time/100-math.floor(time/100))*100
	local sphere_pos=my_p+Point(math.cos(time),math.sin(time))*spiral_t
	--local sphere_pos=my_p+Point(math.cos(time),math.sin(time))*(60*(math.cos(time/4)*0.5+0.5)+10)
	--local sphere_pos=my_p
	local d=sphere_pos-last_pos
	local dl=d:len()
	if dl>1 and dl<20 then
		for i=0,1,1/dl do
			teleport(last_pos+i*d)
		end
	else
		teleport(sphere_pos)
	end
	last_pos=sphere_pos
	sand_sim(sphere_pos)
	__no_redraw()
	draw()
	time=time+0.05
end