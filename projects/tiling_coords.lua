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
-- [==[ NPQU
local tiling={
	--first two are translation vector
	{0,2,1,1},
	{1,2,-1,-3},
	--next are vertexes
	{0,0,0,0},
	{0,1,0,0},
	{0,1,1,0},
	{0,2,0,-2},
	{0,2,0,-1},
	{1,2,-1,-2},
	{0,2,1,-1},
	{0,2,1,0},
	{1,2,0,-2},
	{1,2,0,-1},
	{0,3,1,-1},
	{1,3,0,-1},
}

--]==]
--[==[
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
--]==]
--t1007
--[==[
local tiling={
	--first two are translation vector
	{2,0,-2,0},
	{2,0,0,0},
	--next are vertexes
	{0,0,0,0},
	{1,0,-1,0},
	{1,0,0,0},
}
--]==]
local tiling_seeds={}
for i=3,#tiling do
	tiling_seeds[i-2]=tiling[i]
end

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
		four_vec[2]*0.5+four_vec[4]+0.5*four_vec[3]*s3
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
	for i=1,#tiling_seeds do
		local c=tiling_seeds[i]
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
			vertexes[h]={id=i,dx=dx,dy=dy}
		end
		end
	end
	ret.v=vertexes
	return ret
end
function lua_mod( v,k )
	return ((v-1) %k)+1
end
local cloud=construct_cloud()
--list all vertexes that are connected to input one
function topo_star( vertex,start_id,end_id )
	local ret={}
	start_id=start_id or 1
	end_id=end_id or 12
	for k=start_id,end_id do

		--allow end_id >12 by modulo wrapping
		local kid=lua_mod(k,12)
		local v=omega_powers[kid]
		local offset_v=four_vec_add(tiling_seeds[vertex.id],v)
		local tv=cloud.v[hash(offset_v)]
		print("topo star check:",vertex.id,k,tv and tv.id)
		if tv then
			table.insert(ret,{k,tv})
		end
	end
	return ret
end
function vertex_is_outer( vertex )
	return vertex.dx~=0 or vertex.dy~=0
end

--given a vertex, return all pairs of vertexes that are edges
function topo_edges( vertex )
	--TODO: probably check if input is dx,dy==0
	local ret={}
	for i,v in ipairs(omega_powers) do
		local offset_v=four_vec_add(tiling_seeds[vertex.id],v)
		local tv=cloud.v[hash(offset_v)]
		if tv and (vertex_is_outer(tv) or vertex.id<tv.id) then
			table.insert(ret,tv)
		end
	end
	return ret
end
--get a list of vertexes for this face
function topo_face( vertex,id1,id2 )
	local ret={}
	local m=12/(6-(id2-id1))
	print("Topo face:",id1,id2,m)
	local v=tiling_seeds[vertex.id]
	table.insert(ret,v)
	for i=1,m-1 do
		--print("Id",id1,lua_mod(id1,12))
		v=four_vec_add(v,omega_powers[lua_mod(id1,12)])
		table.insert(ret,v)
		id1=lua_mod(id1+12/m,12)
	end
	return ret
end
--given a vertex enumerate all faces
function topo_faces( vertex )
	local ret={}
	if vertex.dx~=0 or vertex.dy~=0 then
		return ret
	end
	local s=topo_star(vertex,10,15)
	for i=1,#s-1 do
		--print("i:",i,s[i][1],s[i+1][1])
		table.insert(ret,topo_face(vertex,s[i][1],s[i+1][1]))
	end
	return ret
end
print("==================================")
local faces_list={}
for i,v in pairs(cloud.v) do
	if v.dx==0 and v.dy==0 then
		print(v.id,v.dx,v.dy,i)
		local edges=topo_edges(v)
		for i,v in ipairs(edges) do
			--print("\t",i,v.id)
		end
		local f=topo_faces(v)
		for ii,vv in ipairs(f) do
			table.insert(faces_list,vv)
		end
	end
	--break
end
function recurse_print( t,depth )
	depth=depth or 1
	for k,v in pairs(t) do
		print(string.rep("\t",depth)..k)
		if type(v)=="table" then
			recurse_print(v,depth+1)
		else
			print(string.rep("\t",depth)..to_string(v))
		end
	end
end
count_draw=0
--add triangles of the face to buffers
function process_face(f,tri_data,color_data,point_offset)
	--print("Processing face:",f,"with ",#f,"vertices")
	local color={math.random(),math.random(),math.random(),1}

	local center_pt=Point(0,0,0,0)
	local face_verts={}
	for vert_id=1,#f do
		local tmp_pt=four_vec_to_cartesian(f[vert_id])
		face_verts[vert_id]=tmp_pt
		center_pt=center_pt+tmp_pt
	end
	center_pt=center_pt/#f
	local current_offset=point_offset
	local function add_pt( pt )
		tri_data:set(current_offset,0,{pt[1],pt[2],0,1})
		color_data:set(current_offset,0,color)
		current_offset=current_offset+1
	end
	for vert_id=1,#f do
		--print("adding:",vert_id)
		add_pt(face_verts[vert_id])
		add_pt(face_verts[lua_mod(vert_id+1,#f)])
		add_pt(center_pt)
	end
	return current_offset
end
function fill_faces( faces )
	--two ways: tri fan, tris or tri_strip

	--tri fan
	--first pass:count vertexes and tris
	local count_pt=0
	local count_tri=0

	for i,f in ipairs(faces) do
		count_tri=count_tri+#f
		count_pt=count_pt+#f*3
	end
	print("Point count:",count_pt)
	--alloc buffers
	local tri_data=make_flt_buffer(count_pt,1)
	local color_data=make_flt_buffer(count_pt,1)
	--write buffers
	local pt_id=0
	for i,f in ipairs(faces) do
	--local f=faces[3]
		pt_id=process_face(f,tri_data,color_data,pt_id)
	end
	print("done with pts:",pt_id)
	--upload buffers
	count_draw=count_pt
	local byte_count=count_pt*4*4
	face_colors_buffer=buffer_data.Make()
	face_colors_buffer:use()
	face_colors_buffer:set(color_data.d,byte_count)


	tri_buffer=buffer_data.Make()
	tri_buffer:use()
	tri_buffer:set(tri_data.d,byte_count)
	__unbind_buffer()
end
print("Face list:",#faces_list)
fill_faces(faces_list)
function draw_points( )
	point_shader:use()
	vertex_buf:use()
	point_shader:draw_points(0,draw_sample_count,4,1)
	__unbind_buffer()
end

draw_shader=shaders.Make(
[[
#version 330
#line __LINE__

layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;

uniform vec4 offset;
uniform float scale;

out vec4 pos;
out vec4 col;

void main()
{
	vec4 p=position+offset;
	p.xy*=scale;
	gl_Position=p;

	pos=p;
	col=color;
}
]]
,
[[
#version 330
#line __LINE__

in vec4 pos;
in vec4 col;
out vec4 color;

void main()
{
	color=col;
	color.a=1;
}
]])

function draw_faces( dx,dy,scale )
	draw_shader:use()
	face_colors_buffer:use()
	draw_shader:push_attribute(0,"color",4)
	tri_buffer:use()
	draw_shader:set("offset",dx,dy,0,0)
	draw_shader:set("scale",scale)
	draw_shader:draw_triangles(0,count_draw,4,0)
	__render_to_window()
	__unbind_buffer()
end
function pt_inside( pt )
	local wmin=-1
	local wmax=1

	return (pt[1]>=wmin and pt[1]<wmax and pt[2]>=wmin and pt[2]<wmax)
end
function inside_window( dx,dy,offset_x,offset_y )

	return pt_inside(Point(offset_x,offset_y)) or
		pt_inside(Point(offset_x,offset_y)+dx) or
		pt_inside(Point(offset_x,offset_y)+dy) or
		pt_inside(Point(offset_x,offset_y)+dx+dy)

end

function update(  )
	__no_redraw()
	__clear()
	local scale=math.pow(2,-3)


	local tiling_dx=four_vec_to_cartesian(tiling[1])
	local tiling_dy=four_vec_to_cartesian(tiling[2])
	--print("dx:",tiling_dx)
	--print("dy:",tiling_dy)
	local center=tiling_dx+tiling_dy
	center=center*0.5

	for dx=-20,20 do
		for dy=-20,20 do
			local pt_dx=tiling_dx*dx
			local pt_dy=tiling_dy*dy
			local delta=pt_dx+pt_dy-center
			if inside_window(tiling_dx*scale,tiling_dy*scale,delta[1]*scale,delta[2]*scale) then
				draw_faces( delta[1],delta[2],scale)
			end
		end
	end
end