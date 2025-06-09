--[=[ Main idea: magic system 1

Simulate field with dimensions D some internal symmetries (gauge theory if i learn it soon enough).

1. choose D
2. formulate "axioms"
	a. some sort of "conservation" laws
	b. symmetries or rules for each entry relation to other
3. think of "tools" or "interactions"
	a. e.g. tools and interaction can only access N out of D dimensions
	b. interaction is limited by some power P (i.e. can't change more than P per timestep)
4. see if anything interesting happens

Bonus points:
	* steal ideas from physics
	* try to make system "boring" (i.e. non simulated) if "interaction" is far away. (i.e. local theory)
	* have enough space for randomization of rules, but not too much so it's not too random
	* kinetic vs potential

Alternatives:
	* isolines are moving particles, and you can push them
	* all the tools are doing are "stretching the field"
--]=]

--CODECOPY: simulated_annealing.lua

require "common"
require "common_math"
--__set_window_size(1024,1024)
local size=STATE.size
local zoom=2

grid=grid or make_f4_buffer(math.floor(size[1]/zoom),math.floor(size[2]/zoom))
tools={} or tools
function resize( w,h )
	grid=make_f4_buffer(math.floor(w/zoom),math.floor(h/zoom))
end

config=make_config({
	{"paused",true, type="boolean"},
	{"do_global",true, type="boolean"},
	{"do_radius",false, type="boolean"},
	{"do_meander",false, type="boolean"},
	{"draw_comp",0,type="int",min=0,max=3},
	{"percent_update",0.3,type="float"},
	{"eps",0.002,type="floatsci",min=0.000001,max=0.1},
	{"max_angle",0,type="float",min=0,max=1},
	},config)

local draw_shader=shaders.Make[==[
#version 330
#line 46
out vec4 color;
in vec3 pos;
#define M_PI 3.14159265359
uniform sampler2D tex_main;
uniform int draw_comp;
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
#if 1
	vec4 T=texture(tex_main,normed);
	float col=T.x;
	if(draw_comp==1)
		col=T.y;
	else if(draw_comp==2)
		col=T.z;
	else if(draw_comp==3)
		col=T.a;
#else
	vec2 T=texture(tex_main,normed).xy;
	float col=(atan(T.y,T.x)/M_PI+1)*0.5;
#endif
#if 1
	color = vec4(palette(col),1);
#else
	col=pow(col,2.2);
	color.xyz=vec3(col);
	color.w=1;
#endif
}
]==]
local GDX={-1,-1,-1, 0, 0, 1, 1, 1}
local GDY={-1, 0, 1,-1, 1,-1, 0, 1}


function coord_edge( x,y )
	--[[ clamp
	if x<0 then x=0 end
	if y<0 then y=0 end
	if x>=grid.w then x=grid.w-1 end
	if y>=grid.h then y=grid.h-1 end
	--]]
	-- [[ loop
	if x<0 then x=grid.w+x end
	if y<0 then y=grid.h+y end

	if x<0 then x=grid.w+x end
	if y<0 then y=grid.h+y end
	if x>=grid.w then x=x-grid.w end
	if y>=grid.h then y=y-grid.h end

	if x>=grid.w then x=x-grid.w end
	if y>=grid.h then y=y-grid.h end
	--]]
	--[[ bounce
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

function get_around( x,y )
	local ret={}
	local offset=0
	local cv=grid:get(x,y)
	local dx=GDX
	local dy=GDY
	--[[
	local dx={-1, 0, 0, 1}
	local dy={ 0,-1, 1, 0}
	--]]
	--[[
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
		local rv=grid:get(tx,ty)
		ret[i]=rv
	end
	offset=#dx
	--]]
	return ret
end
function normed_2vec(x,y,ex,ey)
	local dx=ex-x
	local dy=ey-y
	local l=math.sqrt(dx*dx+dy*dy)
	dx=dx/l
	dy=dy/l
	return {dx,dy}
end
function modEx( x,s )
	return ((x+s/2)%s)-s/2
end
function angle_delta( a1,a2 )
	--return math.pi/2-math.abs(math.abs(a1-a2)-math.pi/2)
	return modEx(math.abs(a1-a2),math.pi/4)
end

function get_around_angle_limited( x,y,fx,fy,dot_min,theta )
	local ret={}
	local offset=0
	--local cv=grid:get(x,y)
	local cvec=normed_2vec(fx,fy,x,y)

	local cs=math.cos(theta)
	local ss=math.sin(theta)
	

	--local a0=math.atan(cvec[2],cvec[1])
	--print("C",cvec[1],cvec[2])
	local dx=GDX
	local dy=GDY
	--[[
	local dx={-1, 0, 0, 1}
	local dy={ 0,-1, 1, 0}
	--]]
	--[[
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
		local mdx=dx[i]*cs-dy[i]*ss
		local mdy=dx[i]*ss+dy[i]*cs
		--local tvec=normed_2vec(fx,fy,x+mdx,x+mdy)
		--local a1=math.atan(dy[i],dx[i])
		--local a1=math.atan(tvec[2],tvec[1])
		--local dot=tvec[1]*cvec[1]+tvec[2]*cvec[2]
		local ds=math.sqrt(dx[i]*dx[i]+dy[i]*dy[i])
		local dot=mdx*cvec[1]+mdy*cvec[2]

		--if angle_delta(a0,a1)<dot_min then
		if (dot/ds-dot_min)>=-math.random()*0.25 then
		--if math.abs(dot/ds-1)<=dot_min then
		--if math.pi/2-math.acos(dot/ds)>=dot_min then
			tx,ty=coord_edge(tx,ty)
			local rv=grid:get(tx,ty)
			table.insert(ret,rv)
		end
	end

	--]]
	return ret
end
local S=#get_around(0,0)
print("Size:",S)

max_delta=0
update_count=0
function quat_dot( a,b )
	local ret=0
	for i=0,3 do
		ret=ret+a.d[i]*b.d[i]
	end
	return ret
end

function quat_mult( a,b,out )
	local ret={}

	ret[0]=a.d[0]*b.d[0]-a.d[1]*b.d[1]-a.d[2]*b.d[2]-a.d[3]*b.d[3]
	ret[1]=a.d[0]*b.d[1]+a.d[1]*b.d[0]+a.d[2]*b.d[3]-a.d[3]*b.d[2]
	ret[2]=a.d[0]*b.d[2]-a.d[1]*b.d[3]+a.d[2]*b.d[0]+a.d[3]*b.d[1]
	ret[3]=a.d[0]*b.d[3]+a.d[1]*b.d[2]-a.d[2]*b.d[1]+a.d[3]*b.d[0]
	if out then
		for i=0,3 do
			out.d[i]=ret[i]
		end
	else
		return ret
	end
end
function quat_add( a,b,out )
	for i=0,3 do
		out.d[i]=a.d[i]+b.d[i]
	end
end
function quat_commutator( a,b )
	local q1={d={}}
	local q2={d={}}
	quat_mult(a,b,q1)
	quat_mult(b,a,q2)
	for i=0,3 do
		q2.d[i]=q2.d[i]*(-1)
	end
	quat_add(q1,q2,q1)
	return q1
end
function quat_normalize( a )
	local l=math.sqrt(quat_dot(a,a))
	for i=0,3 do
		a.d[i]=a.d[i]/l
	end
end
function quat_lerp( a,b,out,t )
	local c0=1-t
	local c1=t
	for i=0,3 do
		out.d[i]=c0*a.d[i]+c1*b.d[i]
	end
end
function quat_slerp( a,b,out,t )
	if t<0.01 or t>0.99 then
		quat_lerp(a,b,out,t)
		quat_normalize(out)
	else
		local dprod=quat_dot(a,b)
		local ang=math.acos(dprod)
		if ang<0 then ang=-ang end
		local s=math.sin(ang)
		if math.abs(s)<0.00001 or ang~=ang then
			return
		end
		local c0=math.sin((1-t)*ang)/s
		local c1=math.sin(t*ang)/s
		for i=0,3 do
			out.d[i]=c0*a.d[i]+c1*b.d[i]
		end
	end
end
function quat_inverse( a,a_out )
	local d=quat_dot(a,a)
	a_out.d[0]=a.d[0]/d
	for i=1,3 do
		a_out.d[i]=-a.d[i]/d
	end
end
function quat_conjugate( a,a_out )
	a_out.d[0]=a.d[0]
	for i=1,3 do
		a_out.d[i]=-a.d[i]
	end
end
function enforce_symmetry(c)
	--U(1)
	--[[
	local l=math.sqrt(c.r*c.r+c.g*c.g)
	c.r=c.r/l
	c.g=c.g/l
	--]]
	--3 sphere
	--[[
	local l=math.sqrt(c.r*c.r+c.g*c.g+c.b*c.b)
	c.r=c.r/l
	c.g=c.g/l
	c.b=c.b/l
	--]]
	--The group SU(2) is isomorphic to the group of quaternions of norm 1
	local l=math.sqrt(quat_dot(c,c))
	--print("L:"..math.abs(l-1))
	if max_delta<math.abs(l-1) then
		max_delta=math.abs(l-1)
	end
	for i=0,3 do
		c.d[i]=c.d[i]/l
	end
end
function update_radius( cx,cy,r,f,t)
	local updates={}
	for x=-r,r do
		local ymin=math.floor(-math.sqrt(r*r-x*x)+0.5)
		local ymax=math.floor(math.sqrt(r*r-x*x)+0.5)
		for y=ymin,ymax do
			if math.random()<config.percent_update then
				local tx=x+cx
				local ty=y+cy
				tx,ty=coord_edge(tx,ty)
				table.insert(updates,{tx,ty,x,y})
			end
		end
	end
	shuffle_table(updates)
	for i,v in ipairs(updates) do
		f(v[1],v[2],v[3],v[4],t)
	end
end
function update_meander( cx,cy,r,f,t)
	local max_heads=10
	local updates=t.heads
	if #updates==0 then
		table.insert(updates,{cx,cy,0,0})
	end
	shuffle_table(updates)
	for i,v in ipairs(updates) do
		local tx=v[1]
		local ty=v[2]
		tx,ty=coord_edge(tx,ty)
		f(v,cx,cy,r,t)
	end
end

function update_global(f,t)
	local updates={}
	for x=0,grid.w-1 do
		for y=0,grid.h-1 do
			if math.random()<config.percent_update then
				table.insert(updates,{x,y})
			end
		end
	end
	shuffle_table(updates)
	for i,v in ipairs(updates) do
		f(v[1],v[2],0,0,t)
	end
end
function tool_smooth( x,y,lx,ly,tool )
	local cur_r=math.sqrt(lx*lx+ly*ly)
	local eps=config.eps*(1-cur_r/tool.r)
	local rv=grid:get(x,y)
	local around=get_around(x,y)
	-- diffusion on F_0
	local avg_a=rv.r
	for i,v in ipairs(around) do
		avg_a=avg_a+v.r
	end
	avg_a=avg_a/(#around+1)
	--local angle=math.atan(rv.g,rv.r)
	rv.r=rv.r+(avg_a-rv.r)*eps
	enforce_symmetry(rv)
end
function tool_towards_max( x,y,lx,ly,tool )
	local cur_r=math.sqrt(lx*lx+ly*ly)
	local eps=config.eps*(1-cur_r/tool.r)

	local rv=grid:get(x,y)
	local around=get_around(x,y)
	-- towards max/min
	local trg=rv.r
	for i,v in ipairs(around) do
		if v.r>trg then
			trg=v.r
		end
	end
	rv.r=rv.r+(trg-rv.r)*eps
	enforce_symmetry(rv)
end
function tool_towards_min( x,y,lx,ly,tool )
	local cur_r=math.sqrt(lx*lx+ly*ly)
	local eps=config.eps*(1-cur_r/tool.r)

	local rv=grid:get(x,y)
	local around=get_around(x,y)
	-- towards max/min
	local trg=rv.r
	for i,v in ipairs(around) do
		if v.r<trg then
			trg=v.r
		end
	end
	rv.r=rv.r+(trg-rv.r)*eps
	enforce_symmetry(rv)
end
function tool_ang(dir)
	return function(x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		-- push towards vector such that it points outwards
		local llx=lx/(cur_r+1)
		local lly=ly/(cur_r+1)
		rv.r=rv.r+dir*(rv.r+llx)*eps/2
		rv.g=rv.g+dir*(rv.g+lly)*eps/2
		enforce_symmetry(rv)
	end
end
function tool_curl(dir)
	return function(x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		-- push towards vector such that it points outwards
		local llx=-ly/(cur_r+1)
		local lly=lx/(cur_r+1)
		rv.r=rv.r+dir*(rv.r+llx)*eps/2
		rv.g=rv.g+dir*(rv.g+lly)*eps/2
		enforce_symmetry(rv)
	end
end
function tool_rnd_polynomial()
	local argsX={}
	local pow2_const=3/2
	--local names={"x","y","z","w"}
	for i=1,4 do
		table.insert(argsX,math.random()*2-1)
	end
	for i=1,4 do
		for j=1,4 do
			table.insert(argsX,math.random()*math.random()*2*pow2_const-pow2_const)
		end
	end
	local argsY={}

	for i=1,4 do
		table.insert(argsY,math.random()*2-1)
	end
	for i=1,4 do
		for j=1,4 do
			table.insert(argsY,math.random()*math.random()*2*pow2_const-pow2_const)
		end
	end
	for i,v in ipairs(argsX) do
		print(v,argsY[i])
	end
	return function(x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		-- push towards vector such that it points outwards
		local input={rv.r,rv.g,rv.b,rv.a}
		local dr=0
		local idX=1
		for i=1,4 do
			dr=dr+argsX[idX]*input[i]
			idX=idX+1
		end
		for i=1,4 do
			for j=1,4 do
				dr=dr+argsX[idX]*input[i]*input[j]
				idX=idX+1
			end
		end

		local dg=0
		local idY=1
		for i=1,4 do
			dg=dg+argsY[idY]*input[i]
			idY=idY+1
		end
		for i=1,4 do
			for j=1,4 do
				dg=dg+argsY[idY]*input[i]*input[j]
				idY=idY+1
			end
		end
		rv.r=rv.r+eps*dr
		rv.g=rv.g+eps*dg
		enforce_symmetry(rv)
	end
end
function tool_rnd_polynomial2()
	local argsX={}
	local pow2_const=3/2
	--local names={"x","y","z","w","r"}
	for i=1,5 do
		table.insert(argsX,math.random()*2-1)
	end
	for i=1,5 do
		for j=1,5 do
			table.insert(argsX,math.random()*math.random()*2*pow2_const-pow2_const)
		end
	end
	local argsY={}

	for i=1,5 do
		table.insert(argsY,math.random()*2-1)
	end
	for i=1,5 do
		for j=1,5 do
			table.insert(argsY,math.random()*math.random()*2*pow2_const-pow2_const)
		end
	end
	for i,v in ipairs(argsX) do
		print(v,argsY[i])
	end
	return function(x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		-- push towards vector such that it points outwards
		local input={rv.r,rv.g,rv.b,rv.a,cur_r/tool.r}
		local dr=0
		local idX=1
		for i=1,5 do
			dr=dr+argsX[idX]*input[i]
			idX=idX+1
		end
		for i=1,5 do
			for j=1,5 do
				dr=dr+argsX[idX]*input[i]*input[j]
				idX=idX+1
			end
		end

		local dg=0
		local idY=1
		for i=1,5 do
			dg=dg+argsY[idY]*input[i]
			idY=idY+1
		end
		for i=1,5 do
			for j=1,5 do
				dg=dg+argsY[idY]*input[i]*input[j]
				idY=idY+1
			end
		end
		rv.r=rv.r+eps*dr
		rv.g=rv.g+eps*dg
		enforce_symmetry(rv)
	end
end
function extremum_dot( cells,center_cell,direction )
	local ex_dot,ex_cell
	for i,v in ipairs(cells) do
		if i==1 then
			ex_dot=quat_dot(v,center_cell)
			ex_cell=v
		else
			local d=quat_dot(v,center_cell)
			if direction*ex_dot<direction*d then
				ex_dot=d
				ex_cell=v
			end
		end
	end
	return ex_dot,ex_cell
end
function extremum_commutator( cells,center_cell,direction )
	local ex_dot,ex_cell
	for i,v in ipairs(cells) do
		if i==1 then
			local q1=quat_commutator(v,center_cell)
			ex_dot=quat_dot(q1,q1)
			ex_cell=v
		else
			local q1=quat_commutator(v,center_cell)
			local d=quat_dot(q1,q1)
			if direction*ex_dot<direction*d then
				ex_dot=d
				ex_cell=v
			end
		end
	end
	return ex_dot,ex_cell
end
function extremum_value(cells,transform_inverse,index,direction )
	local ex_val=0
	local ex_cell
	for i,v in ipairs(cells) do
		local ain={d={[0]=0,0,0,0}}
		quat_mult(v,transform_inverse,ain)
		local delta=math.abs(v.d[index]-ain.d[index])
		if i==1 then
			ex_val=delta
			ex_cell=v
		else

			if direction*ex_val<direction*delta then
				ex_val=delta
				ex_cell=v
			end
		end
	end
	return ex_val,ex_cell
end
function rnd_trans_unt(  )
	local dir={0,1,2,3}
	shuffle_table(dir)
	local d1=dir[1]
	local d2=dir[2]
	print("D:"..d1..d2)
	return function ( x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		--local around=get_around(x,y)
		local cv=grid:get(tool.x,tool.y)

		local left=1-rv.d[dir[3]]*rv.d[dir[3]]-rv.d[dir[4]]*rv.d[dir[4]]
		--print("U:",left)
		local left_s=math.sqrt(left)

		local d_min=-left_s-rv.d[d1]
		local d_max=left_s-rv.d[d1]

		local dx=(math.random()*(d_max-d_min)+d_min)*eps
		local dot=quat_dot(rv,cv)
		--if rv[d1]+dx>cv[d1] then
		if dot>0.9 then
			local dy=math.sqrt(left-(rv.d[d1]+dx)*(rv.d[d1]+dx))-rv.d[d2]
			--print(string.format("%s %s %g %g %g %g",d1,d2,d_min,d_max,dx,dy))

			rv.d[d1]=rv.d[d1]+dx
			rv.d[d2]=rv.d[d2]+dy
			enforce_symmetry(rv)
		end
	end
end
function rnd_quat_unt(  )
	local args={d={}}
	local direction=-1
	--if math.random()>0.5 then
	--	direction=-1
	--end
	for i=0,3 do
		local c=math.random()*2-1
		args.d[i]=c
	end
	local l=math.sqrt(quat_dot(args,args))
	--print("Pre norm:")
	--print(string.format("\t%g %g %g %g l=%g",args.d[0],args.d[1],args.d[2],args.d[3],l))
	for i=0,3 do
		args.d[i]=args.d[i]/l
	end
	local args_inv={d={}}
	quat_inverse(args,args_inv)
	--print("Post norm:")
	--local l=math.sqrt(quat_dot(args,args))
	--print(string.format("\t%g %g %g %g l=%g",args.d[0],args.d[1],args.d[2],args.d[3],l))
	--print(quat_dot(args,args))
	return function ( x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		local around=get_around(x,y)
		
		local rrv={d={[0]=0,0,0,0}}
		quat_mult(rv,args,rrv)
		--local ex_dot,ex_cell=extremum_dot(around,rrv,direction)
		local ex_dot,ex_cell=extremum_value(around,args_inv,0,direction)
		--local cv=grid:get(tool.x,tool.y)
		--local dot=quat_dot(cv,rv)

		--if rv[d1]+dx>cv[d1] then
		--if ex_dot<1*(1-cur_r/tool.r) then
		if ex_dot<config.max_angle then
		--if ex_dot>config.max_angle then
			update_count=update_count+1
			--quat_mult(rv,args,rv)
			local ain={d={[0]=0,0,0,0}}
			quat_mult(ex_cell,args_inv,ain)

			quat_slerp(rv,rrv,rv,eps)
			quat_slerp(ex_cell,ain,ex_cell,eps)

			enforce_symmetry(rv)
			enforce_symmetry(ex_cell)
		end
	end
end
function rnd_quat_morph_into(  )
	local args={d={}}
	local direction=-1
	--if math.random()>0.5 then
	--	direction=-1
	--end
	for i=0,3 do
		local c=math.random()*2-1
		args.d[i]=c
	end
	local l=math.sqrt(quat_dot(args,args))
	--print("Pre norm:")
	--print(string.format("\t%g %g %g %g l=%g",args.d[0],args.d[1],args.d[2],args.d[3],l))
	for i=0,3 do
		args.d[i]=args.d[i]/l
	end
	local args_inv={d={}}
	quat_conjugate(args,args_inv)
	--print("Post norm:")
	--local l=math.sqrt(quat_dot(args,args))
	--print(string.format("\t%g %g %g %g l=%g",args.d[0],args.d[1],args.d[2],args.d[3],l))
	--print(quat_dot(args,args))
	return function ( x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps--*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		local around=get_around(x,y)
		
		local rrv={d={[0]=0,0,0,0}}
		quat_mult(rv,args,rrv)
		--local ex_dot,ex_cell=extremum_dot(around,rrv,direction)
		--local ex_dot,ex_cell=extremum_value(around,args_inv,0,direction)
		local ex_dot,ex_cell=extremum_commutator(around,rrv,direction)
		--local cv=grid:get(tool.x,tool.y)
		--local dot=quat_dot(cv,rv)

		--if rv[d1]+dx>cv[d1] then
		--if ex_dot<1*(1-cur_r/tool.r) then
		if ex_dot<config.max_angle then
		--if ex_dot>config.max_angle then
			update_count=update_count+1
			--quat_mult(rv,args,rv)
			--[[local transformer={d={}}
			local rv_inv={d={}}
			quat_conjugate(rv,rv_inv)
			quat_mult(rv_inv,ex_cell,transformer)

			quat_mult(rv,transformer,rrv)

			quat_conjugate(transformer,transformer)
			local trg_inv={d={[0]=0,0,0,0}}
			quat_mult(ex_cell,transformer,trg_inv)

			quat_slerp(rv,rrv,rv,eps)
			quat_slerp(ex_cell,trg_inv,ex_cell,eps)
			-]]
			local rv_o={d={}}
			for i=0,3 do
				rv_o.d[i]=rv.d[i]
			end
			quat_slerp(rv,ex_cell,rv,eps)
			quat_slerp(ex_cell,rv_o,ex_cell,eps)


			enforce_symmetry(rv)
			enforce_symmetry(ex_cell)
		end
	end
end
function rnd_quat_unt_ray_sample(  )
	local args={d={}}
	local direction=1
	if math.random()>0.5 then
		direction=-1
	end
	for i=0,3 do
		local c=math.random()*2-1
		args.d[i]=c
	end
	local l=math.sqrt(quat_dot(args,args))
	--print("Pre norm:")
	--print(string.format("\t%g %g %g %g l=%g",args.d[0],args.d[1],args.d[2],args.d[3],l))
	for i=0,3 do
		args.d[i]=args.d[i]/l
	end
	local args_inv={d={}}
	quat_inverse(args,args_inv)
	local max_angle=math.random()*0.25+0.25
	local do_dot=(math.random()>0.5)
	local do_index=math.random(0,3)
	local theta=math.random()*math.pi*2
	if math.random()>0.5 then
		theta=math.pi/2
	else
		theta=0
	end
	--print("Post norm:")
	--local l=math.sqrt(quat_dot(args,args))
	--print(string.format("\t%g %g %g %g l=%g",args.d[0],args.d[1],args.d[2],args.d[3],l))
	--print(quat_dot(args,args))
	return function ( x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps--*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		local cv=grid:get(tool.x,tool.y)

		local around
		if cur_r>2 then
			around=get_around_angle_limited(x,y,tool.x,tool.y,max_angle,theta)--*(1-cur_r*0.5/tool.r))
		else
			around=get_around(x,y)
		end
		--print(x,y,tool.x,tool.y)
		--[[
		if #around~=8 then
			print(#around)
		end
		--]]
		local rrv={d={[0]=0,0,0,0}}
		local ccv={d={[0]=0,0,0,0}}
		quat_mult(rv,args,rrv)
		quat_mult(cv,args,ccv)
		local ex_dot,ex_cell
		if do_dot then
			ex_dot,ex_cell=extremum_dot(around,ccv,direction)
		else
			ex_dot,ex_cell=extremum_value(around,ccv,do_index,direction)
		end
		--print(ex_dot,#around)
		--if ex_dot<1*(1-cur_r/tool.r) then
		if ex_cell~=nil and ex_dot>config.max_angle then
			update_count=update_count+1
			--quat_mult(rv,args,rv)
			local ain={d={[0]=0,0,0,0}}
			quat_mult(ex_cell,args_inv,ain)

			quat_slerp(rv,rrv,rv,eps)
			quat_slerp(ex_cell,ain,ex_cell,eps)

			enforce_symmetry(rv)
			enforce_symmetry(ex_cell)
		end
	end
end
function field_optimizer( index )
	local args={d={}}
	local direction=1
	--if math.random()>0.5 then
	--	direction=-1
	--end
	for i=0,3 do
		local c=math.random()*2-1
		args.d[i]=c
	end
	local l=math.sqrt(quat_dot(args,args))
	--print("Pre norm:")
	--print(string.format("\t%g %g %g %g l=%g",args.d[0],args.d[1],args.d[2],args.d[3],l))
	for i=0,3 do
		args.d[i]=args.d[i]/l
	end
	local args_inv={d={}}
	quat_inverse(args,args_inv)
	--print("Post norm:")
	--local l=math.sqrt(quat_dot(args,args))
	--print(string.format("\t%g %g %g %g l=%g",args.d[0],args.d[1],args.d[2],args.d[3],l))
	--print(quat_dot(args,args))
	return function ( x,y,lx,ly,tool )
		local cur_r=math.sqrt(lx*lx+ly*ly)
		local eps=config.eps*(1-cur_r/tool.r)
		local rv=grid:get(x,y)
		local around=get_around(x,y)
		local ex_val,ex_cell=extremum_value(around,args_inv,index)
		--local cv=grid:get(tool.x,tool.y)
		--local dot=quat_dot(cv,rv)

		--if rv[d1]+dx>cv[d1] then
		--if ex_dot<1*(1-cur_r/tool.r) then
		if ex_val>config.max_angle then
			update_count=update_count+1
			--quat_mult(rv,args,rv)
			local ain={d={[0]=0,0,0,0}}
			quat_mult(ex_cell,args_inv,ain)

			local rrv={d={[0]=0,0,0,0}}
			quat_mult(rv,args,rrv)

			quat_slerp(rv,rrv,rv,eps)
			quat_slerp(ex_cell,ain,ex_cell,eps)

			enforce_symmetry(rv)
			enforce_symmetry(ex_cell)
		end
	end
end
local tool_funcs={
		--smooth=tool_smooth,
		--[[source=tool_ang(1),
		sink=tool_ang(-1),
		curl=tool_curl(1),
		anticurl=tool_curl(-1),
		max=tool_towards_max,
		min=tool_towards_min,
		--]]
		--[[
		rrr1=tool_rnd_polynomial2(),
		rrr2=tool_rnd_polynomial2(),
		rrr3=tool_rnd_polynomial2(),
		rrr4=tool_rnd_polynomial2(),
		--]]
		rrr1=rnd_quat_morph_into(),
		rrr2=rnd_quat_morph_into(),
		rrr3=rnd_quat_morph_into(),
		rrr4=rnd_quat_morph_into(),
	}
function do_tools(  )
	for i,v in ipairs(tools) do
		if v.is_global and config.do_global then
			update_global(v.func,v)
		end

		if v.is_radius and config.do_radius then
			update_radius(v.x,v.y,v.r,v.func,v)
		end

		if v.is_meander and config.do_meander then
			update_meander(v.x,v.y,v.r,v.func,v)
		end
	end
end

function save_img(  )
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    config_serial=config_serial..serialize_config(config).."\n"
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
grid_tex =grid_tex or textures.Make()
function draw_grid(  )
	draw_shader:use()
	grid_tex:use(0)
	grid:write_texture(grid_tex)
	draw_shader:set_i("tex_main",0)
	draw_shader:set_i("draw_comp",config.draw_comp)
	draw_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function random_key_from_table( tbl )
	local keys={}
	for k,v in pairs(tbl) do
		table.insert(keys,k)
	end
	return function()
		return keys[math.random(1,#keys)]
	end
end
function init_tools(  )
	local rt=random_key_from_table(tool_funcs)
	tools={}
	--[[
	for i=1,1 do

		table.insert(tools,{
			--x=math.random(0,grid.w-1),
			--y=math.random(0,grid.h-1),
			x=math.floor(grid.w/2),
			y=math.floor(grid.h/2),
			func=tool_funcs[rt()],
			--r=math.random(grid.w/4,grid.w/2),
			r=math.random(100,200),
			--r=grid.w/2-5
			is_radius=true
		})
	end
	--]]
	--[[
	table.insert(tools,{
		is_global=true,
		func=field_optimizer(0),
		r=math.sqrt((grid.w*grid.w+grid.h*grid.h)*2)
	})
	--]]
	table.insert(tools,{
		is_global=true,
		func=tool_funcs[rt()],
		r=math.sqrt((grid.w*grid.w+grid.h*grid.h)*2)
	})
end
function clamp_urand( val,dev )
	local ret=val+urand(dev)
	if ret<-1 then ret=-1 end
	if ret>1 then ret=1 end
	return ret
end
--sets values in rect x_s <-> x_e by y_s <-> y_e
function generate_field_subdiv( x,y,w,h,deviation,step )
	step=step or 0
	sprint(w,h)
	if w<=1 and h<=1 then
		return
	end
	local x_s=x-w/2
	local x_e=x+w/2
	local y_s=y-h/2
	local y_e=y+h/2
	if step%2==0 then
		--diamond step

		local corners={
			grid:get(x_s,y_s).d[0],
			grid:get(x_e,y_s).d[0],
			grid:get(x_e,y_e).d[0],
			grid:get(x_s,y_e).d[0]
		}

		local cval=clamp_urand((corners[1]+corners[2]+corners[3]+corners[4])/4,deviation)
		grid:set(x,y,{d={cval,0,0,0}})

		generate_field_subdiv(x_s,y,w,h,deviation/2,step+1)
		generate_field_subdiv(x_e,y,w,h,deviation/2,step+1)
		generate_field_subdiv(x,y_s,w,h,deviation/2,step+1)
		generate_field_subdiv(x,y_e,w,h,deviation/2,step+1)
	else
		--square step
		local corners={
			grid:get(x_s,y).d[0],
			grid:get(x_e,y).d[0],
			grid:get(x,y_s).d[0],
			grid:get(x,y_e).d[0]
		}
	end


	if w==0 then
		local s=grid:get(x_s,y_s).d[0]
		for y=y_s,y_e do
			grid:set(x_s,y,{d={s,0,0,0}})
		end
	end
	if h==0 then
		local s=grid:get(x_s,y_s).d[0]
		for y=y_s,y_e do
			grid:set(x_s,y,{d={s,0,0,0}})
		end
	end

	if w%2==0 and h%2==0 then
		

		grid:set(x_s+w/2,y_s,{d={clamp_urand((corners[1]+corners[2])/2,0),0,0,0}})
		grid:set(x_e,y_s+h/2,{d={clamp_urand((corners[2]+corners[3])/2,0),0,0,0}})
		grid:set(x_s+w/2,y_e,{d={clamp_urand((corners[3]+corners[4])/2,0),0,0,0}})
		grid:set(x_s,y_s+h/2,{d={clamp_urand((corners[4]+corners[1])/2,0),0,0,0}})


		generate_field_subdiv(x_s,x_s+w/2,y_s,y_s+h/2,deviation/2)
		generate_field_subdiv(x_s+w/2,x_e,y_s,y_s+h/2,deviation/2)
		generate_field_subdiv(x_s+w/2,x_e,y_s+h/2,y_e,deviation/2)
		generate_field_subdiv(x_s,x_s+w/2,y_s+h/2,y_e,deviation/2)
	else
		error("oops!",w,h)
	end
end
function normed_gaussian( xsq,p )
	--local norm=1/(p*math.sqrt(2*math.pi))
	return math.exp(-xsq/(2*p*p))--*norm
end

function rand_blobs( no_blobs,scale,index )
	local blobs={}
	for i=1,no_blobs do
		local s=math.random(grid.w/16,grid.w/8)*scale
		local w=urand(100)--*(1/(s*s))
		local x=math.random(0,grid.w-1)
		local y=math.random(0,grid.h-1)
		table.insert(blobs,{x=x,y=y,s=s,w=w})
	end
	local min_val
	local max_val
	for x=0,grid.w-1 do
	for y=0,grid.h-1 do
		local val=0
		for i,v in ipairs(blobs) do
			--TODO: check if looped coord is closer...
			local dx=modEx(v.x-x,grid.w)--mod(p+vec2(size/2),size)-vec2(size/2);
			local dy=modEx(v.y-y,grid.h)
			val=val+v.w*normed_gaussian(dx*dx+dy*dy,v.s)
		end
		local v=grid:get(x,y)
		v.d[index]=val
		if x==0 and y==0 then
			min_val=val
			max_val=val
		else
			if min_val>val then min_val=val end
			if max_val<val then max_val=val end
		end
	end
	end
	for x=0,grid.w-1 do
	for y=0,grid.h-1 do
		local v=grid:get(x,y)
		local vs=((v.d[index]-min_val)/(max_val-min_val))*2-1
		v.d[index]=vs
	end
	end
end
function fill_rest(  )
	for x=0,grid.w-1 do
	for y=0,grid.h-1 do
		local v=grid:get(x,y)
		local left=math.sqrt(1-v.d[0]*v.d[0])
		local rest={v.d[1],urand(0.5),-1}
		local rest_len=math.sqrt(rest[1]*rest[1]+rest[2]*rest[2]+rest[3]*rest[3])
		for i=1,3 do
			v.d[i]=rest[i]*left/rest_len
		end
	end
	end
end
local pow_pot=3
local pow_kinectic=2
function angle_difference( a1,a2 )
	local diff=a2-a1
	if diff>math.pi then
		return diff-math.pi
	elseif diff<-math.pi then
		return diff+math.pi
	else
		return diff
	end
end
function calc_potential_energy( m,a )
	local sum=0
	for i=1,#m do
		for j=i+1,#m do
			local d=angle_difference(a[i],a[j])
			sum=sum+2*math.pow(math.abs(d),pow_pot)*m[i]*m[j]
		end
	end
	return sum
end
function calc_kinetic_energy( m,a,as )
	local sum=0
	for i=1,#m do
		sum=sum+m[i]*math.pow(as[i],pow_kinectic)
	end
	return sum
end
function sim_tick(a,as, dt )
	for i=1,#a do
		a[i]=(a[i]+as[i]*dt)%(math.pi*2)
	end
end
function newtons_method( f,fder,guess,iter )
	iter=iter or 10
	local om=0.5
	local x=guess
	for i=1,iter do
		print("\t\t\t",x,f(x),fder(x))
		local x_n=x-f(x)/fder(x)
		x=(1-om)*x+om*x_n
	end
	return x
end

function fix_kinectic_additive(m,as, delta_kin )
	--print("D:",delta_kin)
	local function fnew(x)
		local sum=0
		for i=1,#m do
			sum=sum+m[i]*(math.pow(as[i],pow_kinectic)-math.pow(as[i]+m[1]*x/m[i],pow_kinectic))
		end
		return sum-delta_kin
	end
	local function fder_new(x)
		local sum=0
		for i=1,#m do
			sum=sum+math.pow(as[i]+m[1]*x/m[i],pow_kinectic-1)
		end
		return -pow_kinectic*m[1]*sum
	end
	local dx=newtons_method(fnew,fder_new,0)
	print("found delta:",dx,fnew(dx))
	for i=1,#m do
		as[i]=as[i]+m[1]*dx/m[i]
	end
end
function fix_kinectic_multiply( m,as, vold,vnew )
	local top=vnew*2-vold
	local bottom=0
	for i=1,#as do
		bottom=bottom+math.pow(as[i],pow_kinectic)
	end
	bottom=bottom*m[1]
	local dx=top/bottom
	for i=1,#m do
		as[i]=as[i]*m[1]*dx/m[i]
	end
end
function print_state(a,as, cur_time,denergy)
	--print("==============")
	local str=string.format("%.5f ",cur_time)
	for i=1,#as do
		str=str..string.format("%.5f %.5f ",a[i],as[i])
	end
	str=str..string.format("%.5f ",denergy)
	print(str)
end
function calc_total_energy(m,a,as)
	return calc_potential_energy(m,a)+calc_kinetic_energy(m,a,as)
end
function sim_angular(  )
	local timestep=0.05
	local masses={1,2}
	local angles={math.pi/4,math.pi/2}--{math.random()*math.pi*2,math.random()*math.pi*2}
	local angular_speeds={0,1}--{math.random()*2-1,math.random()*2-1}
	print("Starting:")
	local old_pot=calc_potential_energy(masses,angles)
	local old_kin=calc_kinetic_energy(masses,angles,angular_speeds)
	local total_energy=old_pot+old_kin
	--print("\tpot:",calc_potential_energy(masses,angles)," kinetic:",old_kin, "total:",total_energy)
	print_state(angles,angular_speeds,0,0)
	local cur_time=0
	for i=1,100 do
		sim_tick(angles,angular_speeds,timestep)
		cur_time=i*timestep

		local cur_pot=calc_potential_energy(masses,angles)
		local cur_kin=total_energy-cur_pot
		--print("\tpot:",cur_pot," kinetic:",cur_kin)
		if cur_kin <0 then
			break
		end
		local kin_delta=old_kin-cur_kin
		fix_kinectic_additive(masses,angular_speeds,kin_delta)
		--fix_kinectic_multiply(masses,angular_speeds,old_kin,cur_kin)
		local new_kin=calc_potential_energy(masses,angles,angular_speeds)
		--print("\t\tnew total:",calc_total_energy(masses,angles,angular_speeds))
		print_state(angles,angular_speeds,cur_time,total_energy-calc_total_energy(masses,angles,angular_speeds))
	end
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Magic system 1")
	draw_config(config)
	local variation_const=0.05
	if imgui.Button("SIMSIMSIM") then
		sim_angular()
	end
	if imgui.Button("Restart") then
		init_tools()
		local cx=grid.w/2
		local cy=grid.h/2
		rand_blobs(30,1,0)
		rand_blobs(50,0.5,1)
		fill_rest()
		-- grid:set(0,0,{d={0,0,0,0}})
		-- grid:set(grid.w-1,0,{d={0,0,0,0}})
		-- grid:set(grid.w-1,grid.h-1,{d={0,0,0,0}})
		-- grid:set(0,grid.h-1,{d={0,0,0,0}})
		-- --generate_field_subdiv(0,grid.w-1,0,grid.h-1,1)
		-- generate_field_subdiv(0,256,0,256,1)
		--[===[
		for x=0,grid.w-1 do
		for y=0,grid.h-1 do
			local dx=x-cx
			local dy=y-cy
			local l=math.sqrt(dx*dx+dy*dy)
			--[[
			local v1=math.random()
			local v2=math.random()
			local v3=math.random()
			--]]

			local v3=l/(math.sqrt(2)*grid.w/2)--math.random()
			--local v3=x/grid.w
			--v3=v3*v3
			if v3>1 then
				v3=1
			end
			local v2=math.random()--*math.sqrt(1-v3*v3)
			local v1=math.random()--math.sqrt(1-v3*v3-v2*v2)
			--local v2=math.sqrt(1-v1*v1)
			--local r=math.sqrt(v1*v1+v2*v2);
			--v1=v1/r
			--v2=v2/r
			local t=grid:get(x,y)
			t.d[0]=v1
			t.d[1]=v2
			t.d[2]=v3
			t.d[3]=0.5
			enforce_symmetry(t)
			--grid:set(x,y,(x*(1-variation_const)/grid.w+math.random()*variation_const))
			--[[
			local t=(x/grid.w+y/grid.h)*0.5
			grid:set(x,y,(t*(1-variation_const)+math.random()*variation_const))
			--]]
			--[[
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
			--[[
			local nx=x/grid.w
			local ny=y/grid.h
			local dist=math.huge
			for i,v in ipairs(init_centers) do
				local dx=v[1]-nx
				local dy=v[2]-ny
				local d=dx*dx+dy*dy
				if d<dist then
					dist=d
					centers:set(x,y,{dx,dy})
					--grid:set(x,y,(v[2]+v[1])/2)
				end
			end
			--]]
		end
		end
		--]===]
		--config.paused=false
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.Text(string.format("Biggest delta:%f updates:%3f",max_delta,(update_count)/(config.percent_update*grid.w*grid.h)))
	imgui.End()
	if not config.paused then
		max_delta=0
		update_count=0
		do_tools()
	end
	draw_grid()
	local c,x,y= is_mouse_down()
	if c then
		local tx = math.floor(x/zoom)
		local ty = math.floor(y/zoom)

		local trv=grid:sget(tx,grid.h-ty)
		print(string.format("M(%d,%d)=(%g,%g,%g,%g)",tx,ty,trv.d[0],trv.d[1],trv.d[2],trv.d[3]))
		--[[
		trv.d[0]=1
		for i=1,3 do
			trv.d[i]=0
		end
		--]]
	end
end
