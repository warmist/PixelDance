--try some simulated annealing image-stuff
--[[
	idea: pixels/objects get "score" due to near objects, anneal to maximize
--]]

require "common"
--__set_window_size(1024,1024)
local size=STATE.size
local zoom=2

grid=grid or make_float_buffer(math.floor(size[1]/zoom),math.floor(size[2]/zoom))
function resize( w,h )
	grid=make_float_buffer(math.floor(w/zoom),math.floor(h/zoom))
end

config=make_config({
	{"temperature",1,type="float"},
	{"dt",0.002,type="floatsci",min=0.000001,max=0.005},
	{"percent_update",0.3,type="float"},
	{"max_dist_moved",10, type="int",min=0,max=grid.w},
	{"fixed_colors",false, type="boolean"},
	{"paused",true, type="boolean"},
	},config)
-- [[
local bwrite = require "blobwriter"
local bread = require "blobreader"
function buffer_save( name )
	local b=bwrite()
	b:u32(grid.w)
	b:u32(grid.h)
	b:u32(1) --channel count
	b:u32(0) --do log norm on load
	b:f32(0)
	b:f32(1)
	b:f32(0.5)
	for x=0,grid.w-1 do
	for y=0,grid.h-1 do
		local v=grid:get(x,y)
		b:f32(v)
	end
	end
	local f=io.open(name,"wb")
	f:write(b:tostring())
	f:close()
end
--]]
local draw_shader=shaders.Make[==[
#version 330
#line 27
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
org_ruleset2={
	[1]={  -1,1,   -1, 0.1,-5},
	[2]={ -1, -4,  2,   1, 0},
	[3]={8,-5,-1,  0,   0,-1},
	[4]={-5,5,-10,  10,   0,-1},
}
local org_ruleset
local unif_func=function ( a,org_v,v_fract,x,y)
	local ret=0

	local r =org_ruleset[org_v+1]
	-- [[
	local r2=org_ruleset2[org_v+1]
	for i,v in ipairs(a) do
		if i<=8 or v==org_v then
			ret=ret+r[v[1]+1]*delta_substep((v[2]+v_fract)/2)
		-- [=[
		--elseif i<=6 then
		--	ret=ret-r[v[1]+1]*delta_substep((v[2]+v_fract)/2)
		else
			ret=ret+r2[v[1]+1]*delta_substep((v[2]+v_fract)/2)
		end
		--]=]
	end
	--]]
	--[[
	local tx=grid.w-x-1
	local ty=grid.h-y-1
	tx,ty=coord_edge(tx,ty)
	local rv=grid:get(tx,ty)
	local v=math.floor(rv*4)
	local fv=rv*4-v
	ret=ret+(r[v+1]*delta_substep((fv+v_fract)/2))*4
	--]]
	--[[
	local dx=0.5-(x)/grid.w
	local dy=0.5-(y)/grid.h
	local d=math.sqrt(dx*dx+dy*dy)
	ret=ret-math.abs(d-org_v/3)*80
	--]]
	return ret
end
org_ruleset={
[1]={1.050534960329,2.8011640168863,1.0713388527572,-1.418155686454,},
[2]={2.7275103983318,-2.7684494602978,-2.2556926164395,2.5410745884247,},
[3]={1.0039516242389,-2.4073493439788,3.0456065895772,-0.95797595012118,},
[4]={0.58162930522197,-1.4412001876779,-3.0412968617895,3.2062549688465,},
	--[[
	[4]={1,1,-1,  1,   0,-1},
	[5]={0,0,-1,  -3,   1,-1},]]
}

ruleset=ruleset or org_ruleset

--[==[
{
	[1]=unif_func,
	[2]=unif_func,
	[3]=unif_func,
	--[4]=unif_func,
	--[[function ( a,v,v_fract)
		local has_2=false
		local ret=0
		local ret2=0
		local r ={1,1,1}
		local r2={-5,0,-0.9}
		for i,v in ipairs(a) do
			ret=ret+r[v[1]+1]*delta_substep((v[2]+v_fract)/2)
			ret2=ret2+r2[v[1]+1]*delta_substep((v[2]+v_fract)/2)

			if v[1]==2 then
				has_2=true
			end

			if has_2 then
				return ret+ret2
			else
				return ret
			end
		end
	end
	]]--
	--[[
	[2]=function ( a )
		--local dx={-1,-1,-1, 0, 0, 1, 1, 1}
		--local dy={-1, 0, 1,-1, 1,-1, 0, 1}
		local s={-1,-1,-1,1,1,-1,-1,-1}
		local ret=0
		for i,v in ipairs(a) do
			ret=ret+(v[1]-1)*s[i]+v[2]
		end
		return ret
	end
	--]]
	--[[
	--[3]={   1,-0.5,   1,-0.5, 1},
	[4]={ 0.1,   1,-0.5,   1,-1},
	[5]={2,0,4,-1,1},
	--]]
}
--]==]
local function signum(number)
   if number > 0 then
      return 1
   elseif number < 0 then
      return -1
   else
      return 0
   end
end
function factorial(n)
    if (n == 0) then
        return 1
    else
        return n * factorial(n - 1)
    end
end
function randomize_ruleset(count )
	local ret={}
	for i=1,count do
		local tbl={}
		for ii=1,count do
			--[[
			local t={}
			for i=1,4 do
				t[i]=math.random()*8-4
			end
			local v=math.random()*8-4
			for i=5,10 do
				t[i]=v
			end
			tbl[i]=t
			--]]
			tbl[ii]=math.random()*4-2
		end
		ret[i]=tbl
	end

	-- [[ enforce >1 self
	for i=1,count do
		ret[i][i]=math.abs(ret[i][i])
	end
	--]]
	-- [[ enforce symetry
	for i=1,count do
		for ii=i+1,count do
			-- [=[ full
				ret[i][ii]=ret[ii][i]
			--]=]
			--[=[ sign only
				local s=signum(ret[ii][i])
				ret[i][ii]=s*math.abs(ret[i][ii])
			--]=]
			--[=[ anti sign (mostly chaos)
				local s=signum(ret[ii][i])
				ret[i][ii]=-s*math.abs(ret[i][ii])
			--]=]
		end
	end
	--]]
	--[[ normalize (Frobenius)
	local norm=0
	for i=1,count do
		for ii=1,count do
			local v=ret[i][ii]
			norm=norm+v*v
		end
	end
	norm=math.sqrt(norm)
	for i=1,count do
		for ii=1,count do
			ret[i][ii]=ret[i][ii]/norm
		end
	end
	--]]
	-- [[ row-wise norm
	for i=1,count do
		local norm=0
		for ii=1,count do
			local v=ret[i][ii]
			norm=norm+v*v
		end
		norm=math.sqrt(norm)
		for ii=1,count do
			ret[i][ii]=ret[i][ii]/norm
		end
	end
	--]]
	ruleset=ret

	rules_pol={}
	for i=1,10 do
		rules_pol[i]=(math.random()*4-2)
	end
end
--randomize_ruleset(4)
local num_values=#ruleset
function pmod2( x,y ,sizex,sizey)
	local hsizex=sizex*0.5
	local hsizey=sizey*0.5
	local cx=math.floor((x+hsizex)/sizex)
	x=(x+hsizex)%sizex - hsizex
	local cy=math.floor((y+hsizey)/sizey)
	y=(y+hsizey)%sizey - hsizey
	return x,y,cx,cy;
end
function coord_edge( x,y )
	--[[ clamp
	if x<0 then x=0 end
	if y<0 then y=0 end
	if x>=grid.w then x=grid.w-1 end
	if y>=grid.h then y=grid.h-1 end
	--]]
	--[[ loop
	if x<0 then x=grid.w+x end
	if y<0 then y=grid.h+y end

	if x<0 then x=grid.w+x end
	if y<0 then y=grid.h+y end
	if x>=grid.w then x=x-grid.w end
	if y>=grid.h then y=y-grid.h end

	if x>=grid.w then x=x-grid.w end
	if y>=grid.h then y=y-grid.h end
	--]]
	-- [[ bounce
	if x<0 then x=-x end
	if y<0 then y=-y end
	if x>=grid.w then x=grid.w*2-x-1 end
	if y>=grid.h then y=grid.h*2-y-1 end
	if x<0 then x=-x end
	if y<0 then y=-y end
	if x>=grid.w then x=grid.w*2-x-1 end
	if y>=grid.h then y=grid.h*2-y-1 end
	--]]
	--[[ flip each flip?
	local rx,ry
	x,y,rx,ry=pmod2(x,y,grid.w,grid.h);
	local index=math.abs(rx)+math.abs(ry);
	if(index%2~=0) then --make more interesting tiling: each second tile is flipped
		x=-x
		y=-y
	end
	if x<0 then x=grid.w+x end
	if y<0 then y=grid.h+y end

	if x<0 then x=grid.w+x end
	if y<0 then y=grid.h+y end
	if x>=grid.w then x=x-grid.w end
	if y>=grid.h then y=y-grid.h end

	if x>=grid.w then x=x-grid.w end
	if y>=grid.h then y=y-grid.h end
	--]]
	--[[ mixed
	if x<0 then x=-x end
	if y<0 then y=grid.h+y end
	if x>=grid.w then x=grid.w*2-x-1 end
	if y>=grid.h then y=y-grid.h end
	--]]
	return x,y

end
function gen_cos_sin_table( size,times)
	local ct={}
	local st={}
	times=times or 1 --simple way to weight the interaction more
	for t=1,times do
	for i=1,size-1 do
		local c=math.cos(i*math.pi*2/size)
		local s=math.sin(i*math.pi*2/size)
		table.insert(ct,c)
		table.insert(st,s)
	end
	end
	return ct,st
end
ctab,stab=gen_cos_sin_table(5,2)
function get_around_fract( x,y )
	local ret={}
	local offset=0

	local cx=x-grid.w/2
	local cy=y-grid.h/2

	local cv=grid:get(x,y)
	--[[
	local dx={-1, 0, 0, 1}
	local dy={ 0,-1, 1, 0}
	--]]
	-- [[
	local dx={-1,-1,-1, 0, 0, 1, 1, 1}
	local dy={-1, 0, 1,-1, 1,-1, 0, 1}
	--]]
	--[[
	local dx={-1,-1,-1, 0, 0, 1, 1, 1,2,-2,2,-2}
	local dy={-1, 0, 1,-1, 1,-1, 0, 1,2,2,-2,-2}
	--]]
	--[[
	local dx={-2,-2,-2, 0, 0, 2, 2, 2}
	local dy={-2, 0, 2,-2, 2,-2, 0, 2}
	--]]
	--[[
	local dx={-1,-1,-1,0,0,1,1,1,2,0,0,-2,3,0,0,-3,4,0,0,-4}
	local dy={-1,0,1,-1,1,-1,0,1,0,2,-2,0,0,3,-3,0,0,4,-4,0}
	--]]
	--[[
	local dx={-1,-1,-1,0,0,1,1,1,2,2,2,-2,-2,-2}
	local dy={-1,0,1,-1,1,-1,0,1,0,-2,-1,0,2, 1}
	--]]
	--[[
	local dx={-1, 0,0,1,2,0, 0,-2,3,0,0,-3}
	local dy={ 0,-1,1,0,0,2,-2, 0,0,3,-3,0}
	--]]
	-- [[
	for i=1,#dx do
		local tx=x+dx[i]
		local ty=y+dy[i]
		tx,ty=coord_edge(tx,ty)

		--if tx<grid.w or ty<grid.h or tx>=0 or ty>=0 then
			local rv=grid:get(tx,ty)
			local v=math.floor(rv*num_values)
			ret[i]={v,rv*num_values-v}
		--else
		--ret[i]=0
		--end
	end
	offset=#dx
	--]]
	--[[

	local d_cos={1,3,5,7,9,11}
	local d_sin={2,4,6,8,10,12}
	for i=1,#d_cos do
		local tx=cx+(grid.w/2)*(math.cos(d_cos[i]*x)+math.sin(d_cos[i]*y))
		local ty=cy+(grid.h/2)*(math.sin(d_sin[i]*y)+math.cos(d_sin[i]*x))
		tx=math.floor(tx)
		ty=math.floor(ty)
		tx,ty=coord_edge(tx,ty)

		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+offset]={v,rv*num_values-v}

	end
	offset=#d_cos
	--]]
	--[[
	local dist=0.1
	local offsets_x={cv*(1+dist),cv*(1-dist),1,1}
	local offsets_y={1,1,cv*(1+dist),cv*(1-dist)}



	for i=1,#offsets_x do
		local tx=cx*offsets_x[i]+grid.w/2
		local ty=cy*offsets_y[i]+grid.h/2

		tx=math.floor(tx)
		ty=math.floor(ty)
		tx,ty=coord_edge(tx,ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+offset]={v,rv*num_values-v}

	end
	offset=offset+#offsets_x
	--]]
	--[[ 4(up to) fold symetry 

	local gdx={1,-1,1,-1}
	local gdy={1,1,-1,-1}
	local mdx={0,1,0,1}
	local mdy={0,0,1,1}

	for i=1,#gdx do
		local tx=(grid.w-1)*mdx[i]+x*gdx[i]
		local ty=(grid.h-1)*mdy[i]+y*gdy[i]
		tx,ty=coord_edge(tx,ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+offset]={v,rv*num_values-v}
	end
	offset=offset+#gdx
	--]]
	--[[ 4(up to) fold symmetry

	local gdxx={0,-1,0}
	local gdxy={1,0,-1}
	local gdyx={-1,0,1}
	local gdyy={0,-1,0}

	local cx=x-grid.w/2
	local cy=y-grid.h/2

	for i=1,#gdxx do
		local tx=grid.w/2+cx*gdxx[i]+cy*gdxy[i]
		local ty=grid.h/2+cx*gdyx[i]+cy*gdyy[i]

		tx=math.floor(tx)
		ty=math.floor(ty)
		tx,ty=coord_edge(tx,ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+offset]={v,rv*num_values-v}
	end
	offset=offset+#gdxx
	--]]
	--[[
	local delta_v={1,2,4,8,16}
	for i=1,#delta_v do
		local tx=delta_v[i]/(x+1)
		local ty=delta_v[i]/(y+1)

		tx=math.floor(tx)
		ty=math.floor(ty)
		tx,ty=coord_edge(tx,ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+offset]={v,rv*num_values-v}
	end
	offset=offset+#delta_v
	--]]
	-- [[ n fold rotational sym

	for i=1,#ctab do

		local tx=cx*ctab[i]-cy*stab[i]+grid.w/2
		local ty=cx*stab[i]+cy*ctab[i]+grid.h/2

		
		tx,ty=coord_edge(tx,ty)
		tx=math.floor(tx)
		ty=math.floor(ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+offset]={v,rv*num_values-v}
	end
	offset=offset+#ctab
	--]]
	--[[
	local gdx={0.5,0.25,1,1,0.25,0.5}
	local gdy={1,1,0.25,0.5,0.5,0.25}
	local cx=x-grid.w/2
	local cy=y-grid.h/2
	for i=1,#gdx do
		local tx=(grid.w/2)+cx*gdx[i]
		local ty=(grid.h/2)+cy*gdy[i]
		tx,ty=coord_edge(tx,ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+#dx]={v,rv*num_values-v}
	end
	--]]
	--[[
	local rot_sym=3
	local ddx=x-grid.w/2
	local ddy=y-grid.h/2
	local r=math.sqrt(ddx*ddx+ddy*ddy)
	local a=math.atan(ddy,ddx)
	
	for i=1,rot_sym-1 do
		local t=i/rot_sym
		local tx=(grid.w/2)+math.cos(a+t*math.pi/8)*(r)
		local ty=(grid.h/2)+math.sin(a+t*math.pi/8)*(r)
		tx=math.floor(tx)
		ty=math.floor(ty)
		tx,ty=coord_edge(tx,ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+#dx]={v,rv*num_values-v}
	end
	--]]
	--[[
	local radial_sym=8
	local ddx=x-grid.w/2
	local ddy=y-grid.h/2
	local r=math.sqrt(ddx*ddx+ddy*ddy)
	local a=math.atan(ddy,ddx)
	
	for i=1,radial_sym-1 do
		local t=i/radial_sym
		local tx=(grid.w/2)+math.cos(a)*(r*t)
		local ty=(grid.h/2)+math.sin(a)*(r*t)
		tx=math.floor(tx)
		ty=math.floor(ty)
		tx,ty=coord_edge(tx,ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+#dx]={v,rv*num_values-v}
	end
	--]]
	--[[
	local rot_sym=8
	local ddx=x-grid.w/2
	local ddy=y-grid.h/2
	local r=math.sqrt(ddx*ddx+ddy*ddy)
	local a=math.atan(ddy,ddx)
	
	for i=1,rot_sym-1 do
		local t=i/rot_sym
		local tx=(grid.w/2)+math.cos(a+t*math.pi*4)*(r)
		local ty=(grid.h/2)+math.sin(a+t*math.pi*4)*(r)
		tx=math.floor(tx)
		ty=math.floor(ty)
		tx,ty=coord_edge(tx,ty)
		local rv=grid:get(tx,ty)
		local v=math.floor(rv*num_values)
		ret[i+#dx]={v,rv*num_values-v}
	end
	--]]
	--[[
	local grid_div=4
	
	local id=1
	for ix=0,grid_div-1 do
	for iy=0,grid_div-1 do
		local ddx=math.floor(x/grid_div+ix)*grid_div
		local ddy=math.floor(y/grid_div+iy)*grid_div
		if ix~= 0 or iy~=0 then
			local tx=ddx
			local ty=ddy
			tx=math.floor(tx)
			ty=math.floor(ty)
			tx,ty=coord_edge(tx,ty)
			local rv=grid:get(tx,ty)
			local v=math.floor(rv*num_values)
			ret[id+#dx]={v,rv*num_values-v}
			id=id+1
		end
	end
	end
	--]]
	return ret
end
function delta_substep( v )
	--return 1+v
	--return math.abs(1-v)
	return 0.5+math.abs(0.5-v)*2
	--return -math.sin(v*math.pi*3)+1.5
	--return -(math.cos(v*math.pi*2)+1)*0.5*0.3-0.7
	--return 1-v*0.5

	--smoothstep
	--[[
	if v<=0 then return 0.5 end
	if v>=1 then return 1.5 end
	return 3*v*v-2*v*v*v+0.5
	--]]
end
function calculate_value_fract( x,y,v,v_fract)
	local a=get_around_fract(x,y)
	local r=ruleset[v+1]
	if r==nil then print(v+1,v_fract) end
	local ret=0
	local dst=delta_substep(v_fract)
	if type(r)=="function" then
		return r(a,v,v_fract,x,y)
	end

	for i,vv in ipairs(a) do
		if vv[1]==nil then print(vv[1],vv[2],x,y,v,v_fract) end
		local rule=r[vv[1]+1]
		--[[if type(rule)=="table" then
			rule=rule[i]
		end]]
		--ret=rule*(dst+delta_substep(vv[2]))+ret
		ret=rule*delta_substep((vv[2]+v_fract)/2)+ret
		--ret=rule*delta_substep(math.sqrt(vv[2]*v_fract))+ret
	end
	return ret --*delta_substep(v_fract)
end

function calculate_value_smooth( x,y,v,v_fract,real_value)
	local a=get_around_fract(x,y)
	-- [[
	local f=function ( v1,v2 )
		local d=v1-v2
		--return math.exp(-d*d)
		--return 1-math.abs(math.abs(d)*4-(x/grid.w)*(y/grid.h))
		return 1-math.abs(d)/(1+v2)
		--return math.abs(d)
		--return math.cos(math.abs(d)*math.pi*2)
	end
	--]]
	--[[
	local r=rules_pol
	local f=function ( v1,v2 )
		local d=math.abs(v1-v2)
		--return r[1]+r[2]*d+r[3]*d*d/factorial(2)+r[4]*d*d*d/factorial(3)+r[5]*d*d*d*d/factorial(4)
		--return r[1]+r[2]*d+r[3]*d*d+r[4]*d*d*d+r[5]*d*d*d*d
		return r[1]+r[2]*v1+r[3]*v2+r[4]*v1*v2+r[5]*v1*v2*v1+r[5]*v2*v1*v2
		--return r[1]+r[2]*v1+r[3]*v2+r[4]*v1*v2/factorial(2)+r[5]*v1*v2*v1/factorial(3)+r[5]*v2*v1*v2/factorial(3)
	end
	]]
	local ret=0
	for i,vv in ipairs(a) do
		if vv[1]==nil then print(vv[1],vv[2],x,y,v,v_fract) end
		ret=ret+f(real_value,(vv[1]+vv[2])/num_values)
	end
	return ret
end
function calculate_value_avg( x,y,v,v_fract,real_value)
	local a=get_around_fract(x,y)
	local ret=0
	for i,vv in ipairs(a) do
		if vv[1]==nil then print(vv[1],vv[2],x,y,v,v_fract) end
		local rv=(vv[1]+vv[2])/num_values
		if rv<real_value then
			ret=ret+1
		else
			ret=ret-1
		end
	end
	return ret
end
function round(n)
    return n % 1 >= 0.5 and math.ceil(n) or math.floor(n)
end
function random_in_circle( dist )
	local r=math.sqrt(math.random())*dist
	local a=math.random()*math.pi*2
	return round(math.cos(a)*r),round(math.sin(a)*r)
end

function do_grid_step(x,y)

	local rv=grid:get(x,y)
	local v=math.floor(rv*num_values)
	local v_fract=rv*num_values-v
	--[[
	local dx={-1,-1,-1,0,0,1,1,1}
	local dy={-1,0,1,-1,1,-1,0,1}

	local tx=x+dx[math.random(1,#dx)]
	local ty=y+dy[math.random(1,#dy)]
	--]]
	-- [[
	--local max_dist=config.max_dist_moved*config.temperature+1
	local max_dist=config.max_dist_moved
	local dx,dy=random_in_circle(max_dist)
	local tx=x+dx
	local ty=y+dy
	--]]
	tx,ty=coord_edge(tx,ty)
	--[[if tx>=grid.w or ty>=grid.h or tx<0 or ty<0 then
		return
	end]]
	local trv=grid:get(tx,ty)
	local tv=math.floor(trv*num_values)
	local t_fract=trv*num_values-tv
	--if tv==0 then
		--[[
		local old_value=calculate_value(x,y,v)*delta_substep(rv*num_values-v)
		local old_trg_value=calculate_value(tx,ty,tv)*delta_substep(trv*num_values-tv)
		local new_trg_value=calculate_value(tx,ty,v)*delta_substep(rv*num_values-v)
		local new_value=calculate_value(x,y,tv)*delta_substep(trv*num_values-tv)
		--]]
		local f=calculate_value_fract
		local old_value=f(x,y,v,v_fract,rv)
		local old_trg_value=f(tx,ty,tv,t_fract,trv)

		local new_trg_value=f(tx,ty,v,v_fract,rv)
		local new_value=f(x,y,tv,t_fract,trv)

		local delta_value=(old_value+old_trg_value)-(new_value+new_trg_value)

		--[[
		if math.random()>0.99999 and delta_value~=0 then
			print(math.sqrt(dx*dx+dy*dy),delta_value)
		end
		--]]
		if delta_value<0 or ( math.exp(-delta_value*(1-config.temperature))>math.random()) then
			--[[
			grid:set(x,y,tv/num_values)
			grid:set(tx,ty,v/num_values)
			--]]
			grid:set(x,y,trv)
			grid:set(tx,ty,rv)
			return tx,ty
		end
	--end

end
function update_grid(  )
	if config.temperature<=0 then
		return
	end

	for x=0,grid.w-1 do
		for y=0,grid.h-1 do
			if math.random()<config.percent_update then
				local nx=x
				local ny=y
				nx,ny=do_grid_step(nx,ny)
				--[[
				for i=1,config.max_dist_moved do
					if nx==nil then break end
					nx,ny=do_grid_step(nx,ny)

				end
				--]]
			end
		end
	end
end
function rule_string()
	local ret = "ruleset={"
	for i,v in ipairs(ruleset) do
		local s=""
		for ii,vv in ipairs(v) do
			s=s..tostring(vv)..","
		end
		ret=ret..s.."\n"
	end
	return ret.."}"
end
function save_img(  )
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    config_serial=config_serial..serialize_config(config).."\n"..rule_string()
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
grid_tex =grid_tex or textures.Make()
function draw_grid(  )
	draw_shader:use()
	grid_tex:use(0)
	grid:write_texture(grid_tex)
	draw_shader:set_i("tex_main",0)
	if config.fixed_colors then
		draw_shader:set("count_steps",num_values)
	else
		draw_shader:set("count_steps",-1)
	end
	draw_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Simulated annealing")
	draw_config(config)
	local variation_const=0.0
	if imgui.Button("Restart") then
		for x=0,grid.w-1 do
		for y=0,grid.h-1 do
			--grid:set(x,y,math.random())
			--grid:set(x,y,(x*(1-variation_const)/grid.w+math.random()*variation_const))
			--[[
			local t=(x/grid.w+y/grid.h)*0.5
			grid:set(x,y,(t*(1-variation_const)+math.random()*variation_const))
			--]]
			-- [[
			local dx=(x-grid.w/2)
			local dy=(y-grid.h/2)
			local len=math.sqrt(dx*dx+dy*dy)/(0.5*grid.w)
			local v=0
			if y>grid.h/2 then
				v=(len*(1-variation_const)+math.random()*variation_const)
			else
				v=0.9999-(len*(1-variation_const)+math.random()*variation_const)
			end
			if v>=1 then v=0.999 end
			if v<0 then v=0 end
			grid:set(x,y,v)
			--]]
		end
		end
		config.temperature=0.2
		--config.paused=false
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.SameLine()
	if imgui.Button("SaveBuf") then
		buffer_save("sim_aneal.dat")
	end
	imgui.SameLine()
	if imgui.Button("RandomizeRules") then
		randomize_ruleset(3)
		num_values=#ruleset
		print(rule_string())
	end
	imgui.End()
	if not config.paused then
		local stop_cond=0.001
		update_grid()
		--config.temperature=config.temperature-config.dt --linear cooling
		--config.temperature=config.temperature*(1-config.dt) --exponential cooling
		config.temperature=config.temperature*math.pow(stop_cond,config.dt/(1-stop_cond)) --exp cooling, but same step count as linear
		if config.temperature<=stop_cond then
			config.paused=true
			config.temperature=1
		end
	end
	draw_grid()
	local c,x,y= is_mouse_down()
	if c then
		local tx = math.floor(x/zoom)
		local ty = math.floor(y/zoom)

		local trv=grid:get(tx,ty)
		local tv=math.floor(trv*num_values)
		local t_fract=trv*num_values-tv
		print(string.format("M(%d,%d)=%g (%d;%g), value:%g",tx,ty,trv,tv,t_fract,calculate_value_fract(tx,ty,tv,t_fract)))
	end
end
