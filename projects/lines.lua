require 'common'

local line_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

void main(){
	color=vec4(1,0,0,1);
}
]==]
points=make_flt_half_buffer(2000,1)
function rnd( v )
	return math.random()*(v*2)-v
end
function particle_init(  )
	local count=points.w
	for i=0,count-1 do
		local v=(i/count)*math.pi*2
		local r=rnd(0.0001)+0.3
		points.d[i]={math.cos(v)*r,math.sin(v)*r}
	end
end

particle_init()
function calc_force( id )
	local count=points.w-1
	local fx=0
	local fy=0
	local w=0
	local ps=points.d[id]
	for i=0,count do
		if i~=id then
			local p=points.d[i]
			local dx=ps.r-p.r
			local dy=ps.g-p.g
			local lsq=dx*dx+dy*dy
			fx=fx+dx/lsq
			fy=fy+dy/lsq
			w=w+lsq
		end
	end
	--local l=math.sqrt(fx*fx+fy*fy)
	return fx/w,fy/w
end
function particle_update(  )
	local count=points.w-1
	for i=0,count do
		local p=points.d[i]

		local last_p
		if i>0 then
			last_p=points.d[i-1]
		else
			last_p=points.d[count]
		end
		local next_p
		if i<count then
			next_p=points.d[i+1]
		else
			next_p=points.d[0]
		end
		local ld={r=p.r-last_p.r,g=p.g-last_p.g}
		local nd={r=p.r-next_p.r,g=p.g-next_p.g}
		local dx,dy=calc_force(i)

		local max_size=0.05
		local min_size=0.00005
		local fov_mult=0.002
		local reverse_mult=0.0002
		local lld={dx*fov_mult+ld.r,dy*fov_mult+ld.g}
		local nnd={dx*fov_mult+nd.r,dy*fov_mult+nd.g}
		local d1=math.sqrt(lld[1]*lld[1]+lld[2]*lld[2])
		local d2=math.sqrt(nnd[1]*nnd[1]+nnd[2]*nnd[2])
		if d1< max_size and
			d2< max_size then

			p.r=p.r+dx*fov_mult
			p.g=p.g+dy*fov_mult
		elseif d1>min_size and
			d2>min_size	then
			p.r=p.r+dx*(-reverse_mult)
			p.g=p.g+dy*(-reverse_mult)
		end

	end
	points.d[count]=points.d[0]
end
function update()
	__no_redraw()
	__clear()
	particle_update()
	line_shader:use()

	line_shader:draw_lines(points.d,points.w*points.h,true)
end