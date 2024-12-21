--[==[
Reference:
	http://chequesoto.info
	and basically:

	An integer representation for periodic tilings of the plane by regular
	polygons
	José Ezequiel Soto Sánchez a, Tim Weyrich b, Asla Medeiros e Sá c, Luiz Henrique de
	Figueiredo
--]==]

require "common"


local omega_powers={
	{1,0,0,0},
	{0,1,0,0},
	{0,0,1,0},
	{0,0,0,1},

	{-1,0,1,0},
	{0,-1,0,1},
	{-1,0,0,0},
	{0,-1,0,0},

	{0,0,-1,0},
	{0,0,0,-1},
	{1,0,-1,0},
	{0,1,0,-1},
}


--[[
"t1010":{
"T1":[3,0,-2,0],
"T2":[-1,0,3,0],
"Seed":[
[0,0,0,0],
[0,0,1,0],
[1,0,0,0],
[0,0,2,0],
[2,0,-1,0],
[1,0,1,0],
],
--]]

local tiling={
	--first two are translation vector
	{3,0,-2,0},
	{-1,0,3,0},
	--next are vertexes
	{0,0,0,0},
	{0,0,1,0},
	{1,0,0,0},
	{0,0,2,0},
	{2,0,-1,0},
	{1,0,1,0},
}
function four_vec_add( v1,v2 )
	local ret={
	}
	for i=1,4 do
		ret[i]=v1[i]+v2[i]
	end
	return ret
end
function four_vec_to_cartesian( four_vec )
	local s3=math.sqrt(3)
	return Point(
		four_vec[1]+0.5*four_vec[3]+0.5*four_vec[2]*s3,
		four_vec[2]*0.5+four_vec[4]+0.5*four_vec[3]*s3,
		)
end

--[[
	vertex is:
		id - id into unit cell
		dx - dx of cells
		dy - dy of cells
	e.g:
		id=0, dx=0,dy=0 is root
		id=0,dx=-1,dy=0 is root of cell "left" to this cell
--]]

local max_coord_4vec=20 --must fit all inner and dx,dy=+-1
--given a 4-vec coordinates, return a hash of it.
function hash( four_vec )
	--lets assume max coord
	local m1=max_coord_4vec
	local m2=m1*m1
	local m3=m2*m1
	local m4=m2*m2
	return (four_vec[1]+max_coord_4vec/2)*m1+
		   (four_vec[2]+max_coord_4vec/2)*m2+
		   (four_vec[3]+max_coord_4vec/2)*m3+
		   (four_vec[4]+max_coord_4vec/2)*m4
end

--given a tiling, construct a local cloud that you can run topo ops on
function construct_cloud(  )
	local ret={}
	local vertexes={}
	local t_dx=tiling[1]
	local t_dy=tiling[2]
	for i=3,#tiling do
		local c=tiling[i]
		for dx=-1,1 do
		for dy=-1,1 do
			local four_vec={
				c[1]+t_dx[1]*dx+t_dy[1]*dy,
				c[2]+t_dx[2]*dx+t_dy[2]*dy,
				c[3]+t_dx[3]*dx+t_dy[3]*dy,
				c[4]+t_dx[4]*dx+t_dy[4]*dy
				} --offset by dx,dy
			local h=hash(four_vec)
			if vertexes[h] then
				error("hash collision:",i,dx,dy,h)
			end
			vertexes[h]={id=i-2,dx=dx,dy=dy}
		end
		end
	end
	ret.v=vertexes
	return ret
end

local cloud=construct_cloud()

function vertex_is_outer( vertex )
	return vertex.dx~=0 or vertex.dy~=0
end

--given a vertex, return all pairs of vertexes that are edges
function topo_edges( vertex )
	--TODO: probably check if input is dx,dy==0
	local ret={}
	for i,v in ipairs(omega_powers) do
		local offset_v=four_vec_add(tiling[vertex.id],v)
		local tv=cloud.v[hash(offset_v)]
		if tv and (vertex_is_outer(tv) or vertex.id<tv.id) then
			table.insert(ret,tv)
		end
	end
	return ret
end

function fill_points(  )
	
end

function draw_points(  )
	point_shader:use()
	vertex_buf:use()
	point_shader:draw_points(0,draw_sample_count,4,1)
	__unbind_buffer()
end