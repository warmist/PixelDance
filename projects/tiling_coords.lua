--[==[
Reference:
	http://chequesoto.info
	and basically:

	An integer representation for periodic tilings of the plane by regular
	polygons
	José Ezequiel Soto Sánchez a, Tim Weyrich b, Asla Medeiros e Sá c, Luiz Henrique de
	Figueiredo

	TODO/Ideas:
	* make face graph
	* color stuff differently
	* cellular automata on faces
--]==]

require "common"

function lua_mod( v,k )
	return ((v-1) %k)+1
end

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


--[==[ NPQU
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
--t2001
--[==[
local tiling_name="t2001"
local tiling={
	--first two are translation vector
{0,2,2,2},
{2,4,0,-2},
	--next are vertexes
{0,0,0,0},
{0,1,0,1},
{0,1,1,1},
{0,2,0,-1},
{0,2,0,0},
{0,2,1,0},
{0,2,1,2},
{0,3,1,0},
{0,3,1,1},
{0,3,2,1},
{1,3,1,1},
{1,3,1,0},
{1,4,1,1},
{1,4,1,-1},
{2,4,0,-1},
{1,5,1,-1},
{1,5,1,0},
{2,5,1,0},
}
--]==]
--[==[
local tiling_name="experiment"
local tiling={
	--first two are translation vector
{0,2,2,2},
{2,4,0,-2},
	--next are vertexes


   {1,2,1,-1},
   {0,1,1,0},
   {1,1,1,0},
   {0,0,1,0},
   {1,2,1,0},
   {1,1,1,-1},
   {0,0,1,1},
   {0,1,2,1},
   {0,1,1,-1},
   {0,2,2,0},
   {0,1,2,0},
   {0,0,2,1},
}
    
--]==]
-- [==[
local tiling_name="experiment2"
local tiling={
	--first two are translation vector
{0,2,-1,-1},
{8,0,-0,-8},
	--next are vertexes

	{0,0,0,0},
    {0,0,0,1},
    {1,0,0,0},
    {1,0,0,1},
    {0,0,1,1},
    {1,1,0,0},
    {1,0,-1,0},
    {0,-1,0,1},
    {0,1,1,1},
    {1,1,0,1},
    {2,0,-1,0},
    {2,1,-1,0},
    {0,-1,0,0},
    {1,-1,-1,0},
    {-1,-1,1,1},
    {-1,0,1,1}, 
}
    
--]==]
    
four_vec=class(function (tbl, ...)
    tbl:new(...)
  end
)
--return correct omega power
function four_vec.omega(k)
	--allow end_id >12 by modulo wrapping
	local kid=lua_mod(k,12)
	return omega_powers[kid]
end
function four_vec:new( v1,v2,v3,v4 )
	if type(v1)=="table" then
		for i=1,4 do
			self[i]=v1[i]
		end
	else
		self={v1,v2,v3,v4}
	end
end
function four_vec:add( other )
	local ret={}
	for i=1,4 do
		ret[i]=self[i]+other[i]
	end
	return four_vec(ret)
end
function four_vec:mul( scalar )
	local ret={}
	for i=1,4 do
		ret[i]=self[i]*scalar
	end
	return four_vec(ret)
end
function four_vec:to_cartesian()
	local s3=math.sqrt(3)
	return Point(
		self[1]+0.5*self[3]+0.5*self[2]*s3,
		self[2]*0.5+self[4]+0.5*self[3]*s3
		)
end
function four_vec:to_string(  )
	return string.format("(4vec %d %d %d %d %x)",self[1],self[2],self[3],self[4],self:hash())
end

local max_coord_4vec=20 --must fit all inner and dx,dy=+-1
--given a 4-vec coordinates, return a hash of it.
function four_vec.hash( four_vec )
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

for i,v in ipairs(omega_powers) do
	omega_powers[i]=four_vec(v)
end
tiling.seeds={}
for i=3,#tiling do
	tiling.seeds[i-2]=four_vec(tiling[i])
end
tiling.dx=four_vec(tiling[1])
tiling.dy=four_vec(tiling[2])

--[[
	vertex is:
		id - id into unit cell
		dx - dx of cells
		dy - dy of cells
	e.g:
		id=0, dx=0,dy=0 is root
		id=0,dx=-1,dy=0 is root of cell "left" to this cell
--]]

cloud_vert=class(function (tbl,id,dx,dy)
	tbl.id=id
	tbl.dx=dx
	tbl.dy=dy
end)

function cloud_vert:get_fvec(tiling)
	return tiling.seeds[self.id]
end

function cloud_vert:is_outer()
	return self.dx~=0 or self.dy~=0
end

function cloud_vert:to_string()
	return string.format("(vert %d %d %d)",self.id,self.dx,self.dy)
end

function cloud_vert:offet_vertex_hash(tiling, dx, dy )
	local fvec=self:get_fvec(tiling)
	local offset_v=fvec:add(tiling.dx:mul(dx)):add(tiling.dy:mul(dy))
	return offset_v:hash()
end
--given a tiling, construct a local vertex cloud in int coords
function construct_cloud(  )
	local vertexes={}
	local t_dx=tiling.dx
	local t_dy=tiling.dy
	for i=1,#tiling.seeds do
		local c=tiling.seeds[i]
		for dx=-1,1 do
		for dy=-1,1 do
			local fvec=c:add(t_dx:mul(dx)):add(t_dy:mul(dy)) --offset by dx,dy
			local h=fvec:hash()
			if vertexes[h] then
				error("hash collision:",i,dx,dy,h)
			end
			vertexes[h]=cloud_vert(i,dx,dy)
		end
		end
	end

	return vertexes
end


local topo_info={face_count={}}

local cloud=construct_cloud()

topo_info.verts=cloud
--list all vertexes that are connected to input one
function topo_star( vertex,start_id,end_id )
	local ret={}
	start_id=start_id or 1
	end_id=end_id or 12
	for k=start_id,end_id do
		local vert_four_vec=vertex:get_fvec(tiling)
		local offset_v=vert_four_vec:add(four_vec.omega(k))
		local tv=cloud[offset_v:hash()]
		if tv then
			--print("topo star check:",tv:to_string())
			table.insert(ret,{k,tv})
		end
	end
	return ret
end

--given a vertex, return all pairs of vertexes that are edges
function topo_edges( vertex )
	--TODO: probably check if input is dx,dy==0
	local ret={}
	for i,v in ipairs(omega_powers) do
		local offset_v=vertex:get_fvec(tiling):add(v)
		local tv=cloud[offset_v:hash()]
		if tv and (tv:is_outer() or vertex.id<tv.id) then
			table.insert(ret,tv)
		end
	end
	return ret
end
function face_corner_count( id1,id2 )
	return 12/(6-(id2-id1))
end
--get a list of vertexes for this face
function topo_face( vertex,id1,id2 ) --> list of fourvec vertexes
	local ret={}
	local m=face_corner_count(id1,id2)
	print("Topo face:",id1,id2,m)
	local v=vertex:get_fvec(tiling)
	table.insert(ret,v)
	for i=1,m-1 do
		--print("Id",id1,lua_mod(id1,12))
		v=v:add(four_vec.omega(id1))
		table.insert(ret,v)
		id1=lua_mod(id1+12/m,12)
	end
	return ret
end
--given a vertex enumerate all faces
function topo_faces( vertex )
	local ret={}
	if vertex:is_outer() then
		return ret
	end
	local s=topo_star(vertex,11,16)
	for i=1,#s-1 do
		--print("i:",i,s[i][1],s[i+1][1])
		table.insert(ret,topo_face(vertex,s[i][1],s[i+1][1]))
	end
	return ret
end
print("==================================")
local faces_list={}
local face_lookup={}
--[[
	face lookup indexed by vertex hash:
		members - table indexed by second vertex hash:
			members - tables of {face id, dx, dy}
--]]
--local edge_list=MultiKeyTable()
local function add_edge_to_lookup( v1,v2,face_id,dx,dy)
	dx=dx or 0
	dy=dy or 0
	face_lookup[v1:hash()]=face_lookup[v1:hash()] or {}
	--print("\t",v1:to_string(),v2:to_string())
	if face_lookup[v1:hash()][v2:hash()] then
		print("\t=====oops hash collided?")
	else
		face_lookup[v1:hash()][v2:hash()]={face_id,dx,dy}
	end
end
local function add_offset_edges( v1,v2,face_id )
	for dx=-1,1 do
		for dy=-1,1 do
			local v1_off=v1:add(tiling.dx:mul(dx)):add(tiling.dy:mul(dy))
			local v2_off=v2:add(tiling.dx:mul(dx)):add(tiling.dy:mul(dy))

			add_edge_to_lookup(v1_off,v2_off,face_id,dx,dy)
		end
	end
end
for i,v in pairs(cloud) do
	if v.dx==0 and v.dy==0 then
		print(v:to_string(),i)
		--[[local edges=topo_edges(v)
		for i,v in ipairs(edges) do
			print("\t",i,v.id)
		end--]]
		local f=topo_faces(v)
		--[==[
		print("=>")
		for i,v in ipairs(fe) do
			for id,vert in ipairs(v) do
				local nvert=v[lua_mod(id+1,#v)]
				local v1=vert:get_fvec(tiling)
				local v2=nvert:get_fvec(tiling)
				edge_list:set(v1:hash(),v2:hash(),#faces_list+i)
			end
			print(i,#v,v[1]:to_string(),v[2]:to_string())
		end
		--]==]
		print(">=====<faces from vertex:",i,#f)
		for ii,vv in ipairs(f) do
			table.insert(faces_list,vv)
			for vert_id,v1 in ipairs(vv) do
				local v2=vv[lua_mod(vert_id+1,#vv)]
				--add_edge_to_lookup(v1,v2,ii)
				add_offset_edges(v1,v2,#faces_list)
			end
		end
	end
	--break
end
topo_info.face_list=face_list
topo_info.face_cons={}
function match_edge( face,v1,v2 )
	for i,v in ipairs(face) do
		for id=1,#v do
			local nvert=v[lua_mod(id+1,#v)]
			local v1=v[id]:get_fvec(tiling)
			local v2=nvert:get_fvec(tiling)
			
		end
	end
end
function find_matching_face( v1,v2 )
	for i,v in ipairs(face_vert_list) do
		local e,dx,dy=match_edge(v,v1,v2)
		if e then
			return i,e,dx,dy
		end
	end
end
function get_face_connections(  )
	--print("Checking connections:")
	for face_id,face in ipairs(faces_list) do
		--print("\tFace",face_id)
		local ret={}
		for vert_id=1,#face do
			--print("\t\tVert",vert_id)
			local nvert=face[lua_mod(vert_id+1,#face)]
			local v1=face[vert_id]
			local v2=nvert
			local d=face_lookup[v1:hash()][v2:hash()]
			--print("\t\t\tresult:",d[1])
			local d_rev=face_lookup[v2:hash()][v1:hash()]
			--print("\t\t\tresult:",d_rev[1],d_rev[2],d_rev[3])
			ret[vert_id]=d_rev
		end
		topo_info.face_cons[face_id]=ret
	end
end
get_face_connections()
function recurse_print( t,depth )
	depth=depth or 1
	for k,v in pairs(t) do
		print(string.rep("\t",depth)..k)
		if type(v)=="table" then
			recurse_print(v,depth+1)
		else
			print(string.rep("\t",depth)..tostring(v))
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
		local tmp_pt=f[vert_id]:to_cartesian()
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
	color_data=make_flt_buffer(count_pt,1)
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

for i,v in ipairs(faces_list) do
	topo_info.face_count[i]=#v*3
end

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
function set_face_color( topo_info,colors )
	local count=0
	for i,v in ipairs(topo_info.face_count) do
		if colors[i] then
			for k=0,(v-1) do
				color_data:set(k+count,0,colors[i])
			end
		end
		count=count+v
	end
	local byte_count=count_draw*4*4
	face_colors_buffer:use()
	face_colors_buffer:set(color_data.d,byte_count)
end
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
grid_data=grid_data or {}
function lookup_grid( x,y )
	if grid_data[x]==nil then
		grid_data[x]={[y]={}}
	else
		if grid_data[x][y]==nil then
			grid_data[x][y]={}
		end
	end
	return grid_data[x][y]
end

function save_img(tile_count)
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	img_buf=make_image_buffer(STATE.size[1],STATE.size[2])
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
luv=require "colors_luv"
function colorize( normal_x,normal_y,normal_face )

	local r,g,b=unpack(luv.hsluv_to_rgb({360*(normal_face*0.5+normal_x*2+normal_y*4),20,50}))
	return {r,g,b,1}
end
function colorize_ray( steps_from_center )

	local r,g,b=unpack(luv.hsluv_to_rgb({360*math.random(),100*(1-steps_from_center),50}))
	return {r,g,b,1}
end
function colorize_cells(x,y, state )

	local r,g,b=unpack(luv.hsluv_to_rgb({360*(x+y),100*state,50}))
	return {r,g,b,1}
end
local function nsin( v )
	return math.sin(v)*0.5+0.5
end
rules=rules or {}
function generate_rules(  )
	local MAX_STATE=1
	--[[
		two versions possible:
			* each n faced poly has same rule OR
			* each face has same rule
		also possible to make rules:
			* count of states (e.g. 3 state 1, 3 state 0)
			* based on edge values (e.g. edges have these states [1,1,0,0,1,1])
	--]]
	function random_rule( no_edges,no_states )
		local ret={}
		--TODO: non 2 state thingy
		for i=0,no_edges do
			ret[i]=math.random(0,no_states)
		end
		return ret
	end
	--each n faced poly rules with count of states:
	for i,v in ipairs(topo_info.face_cons) do
		rules[#v]=random_rule(#v,MAX_STATE)
	end

	--print rules:
	for k,v in pairs(rules) do
		print("N-gon:",k)
		for i,v in ipairs(v) do
			print('\t',i,v)
		end
	end
end
--generate_rules()
local time=0
local pointer={x=0,y=0,face=1}
local steps_taken=0
function step_pointer( min_t,max_t )

	local dx=pointer.x
	local dy=pointer.y

	local face_con_info=topo_info.face_cons[pointer.face]
	local side=face_con_info[math.random(1,#face_con_info)]

	pointer.face=side[1]
	pointer.x=pointer.x+side[2]
	pointer.y=pointer.y+side[3]

	if pointer.x>max_t or pointer.x<min_t or
		pointer.y>max_t or pointer.y<min_t then
		pointer={x=0,y=0,face=1}
		steps_taken=0
	end

	local ginfo=lookup_grid(pointer.x,pointer.y)
	local colors=ginfo.colors or {}
	local steps_normalized=steps_taken/400
	if steps_normalized>1 then steps_normalized=1 end
	colors[pointer.face]=colorize_ray(steps_normalized)
	steps_taken=steps_taken+1
end
local grid_state={{},{}}
function resize_grid( min_t,max_t,face_count )
	--todo: int buffer or sth
	grid_state.l=min_t
	grid_state.h=max_t
	grid_state.f=face_count
	grid_state.stride=(max_t-min_t)*face_count

	local size=max_t-min_t
	size=size*size*face_count
	grid_state.size=size
	if grid_state.size~=size then
		grid_state.size=size
		for i=0,size-1 do
			grid_state[1][i]=0
			grid_state[2][i]=0
		end
	end
end
function grid_state:get( x,y,face )
	local tx=x-self.l
	local ty=y-self.l
	return grid_state[1][face-1+tx*self.f+ty*self.stride]
end
function grid_state:set( x,y,face,value )
	local tx=x-self.l
	local ty=y-self.l
	grid_state[1][face-1+tx*self.f+ty*self.stride]=value
end
function grid_state:set2( x,y,face,value )
	local tx=x-self.l
	local ty=y-self.l
	grid_state[2][face-1+tx*self.f+ty*self.stride]=value
end
function grid_state:flip(  )
	--swap grid_state
	local tmp=self[1]
	self[1]=self[2]
	self[2]=tmp
end
function init_grid_random(min_t,max_t, chance_one )
	local face_count=#topo_info.face_cons
	resize_grid(min_t,max_t,face_count)
	for dx=min_t,max_t-1 do
		for dy=min_t,max_t-1 do
			for f=1,face_count do
				local v=0
				if math.random()<chance_one then
					v=1
				end
				grid_state:set(dx,dy,f,v)
			end
		end
	end
end
init_grid_random(-10,10,0.8)
function apply_rules(min_t,max_t)
	local face_count=#topo_info.face_cons
	resize_grid(min_t,max_t,face_count)
	local function calc_state_cell( x, y, face )
		local face_con_info=topo_info.face_cons[face]
		local count=0
		for i,v in ipairs(face_con_info) do
			local tx=x+v[2]
			local ty=y+v[3]
			local tface=v[1]
			if tx<min_t then tx=max_t-1 end
			if tx>=max_t then tx=min_t end
			if ty<min_t then ty=max_t-1 end
			if ty>=max_t then ty=min_t end
			local value=grid_state:get(tx,ty,tface)
			--if math.random()>0.999 then
			--	print(i,tx,ty,tface,value)
			--end
			if value==1 then
				count=count+1
			end
		end
		--print(count,rules[#face_con_info][count])
		local new_value=rules[#face_con_info][count] or 0
		if new_value==1 then
			grid_state:set2(x,y,face,new_value)
		else
			local w=0.98
			local old_value=grid_state:get(x,y,face)
			grid_state:set2(x,y,face,old_value*w)
		end
	end
	-- [==[
	for dx=min_t,max_t-1 do
		for dy=min_t,max_t-1 do
			for f=1,face_count do
				calc_state_cell(dx,dy,f)
			end
		end
	end
	--]==]
	--calc_state_cell(0,1,2)
	grid_state:flip()
end
function draw_state( min_t,max_t )
	local MAX_STATE=1 --todo pass from above
	local color_noise=0.3
	for dx=min_t,max_t-1 do
		for dy=min_t,max_t-1 do
			local ndx=(dx-min_t)/(max_t-min_t)
			local ndy=(dy-min_t)/(max_t-min_t)

			local ginfo=lookup_grid(dx,dy)
			local colors=ginfo.colors or {}
			for i=1,#topo_info.face_cons do
				local grid_cell=grid_state:get(dx,dy,i)
				local v=0
				if grid_cell then
					v=grid_cell/MAX_STATE
				end
				--v=v+math.random()*color_noise-color_noise/2
				if v<0 then v=0 end
				if v>1 then v=1 end
				colors[i]=colorize_cells(ndx,ndy,v)
			end
		end
	end
end

function save_gdres( name )
	local f=io.open(name..".txt","w")
	local dx=tiling.dx:to_cartesian()
	local dy=tiling.dy:to_cartesian()
	f:write(string.format("tiling_dx = Vector2(%g,%g)\n",dx[1],dx[2]))
	f:write(string.format("tiling_dy = Vector2(%g,%g)\n",dy[1],dy[2]))
	local table_counts={}
	for i,v in ipairs(faces_list) do
		table.insert(table_counts,#v)
	end
	f:write(string.format("vertex_counts = PackedInt32Array(%s)\n",table.concat( table_counts,", ")))
	local topo_out={}
	for i,face_verts in ipairs(faces_list) do
		local v=topo_info.face_cons[i]
		local count_added=0
		for vert_id,vert_con in pairs(v) do
			count_added=count_added+1
			table.insert(topo_out,vert_con[1]-1)
			--table.insert(topo_out,vert_con[2])
			--table.insert(topo_out,vert_con[3])
		end
		local diff=#face_verts-count_added
		for i=1,diff do
			
			table.insert(topo_out,-1)
			--table.insert(topo_out,0)
			--table.insert(topo_out,0)
		end
	end

	print("Topology size:",#topo_out)
	f:write(string.format("face_topology = PackedInt32Array(%s)\n",table.concat( topo_out,", ")))
	f:write(string.format("tiling_name = \"%s\"\n",name))
	local vert_out={}
	local min_point
	for face_id,face in ipairs(faces_list) do
		for vert_id,vert in ipairs(face) do
			local vc=vert:to_cartesian()
			if min_point==nil then
				min_point=Point(vc[1],vc[2])
			else
				if vc[1]<min_point[1] then min_point[1]=vc[1] end
				if vc[2]<min_point[2] then min_point[2]=vc[2] end
			end
		end
	end
	for face_id,face in ipairs(faces_list) do
		for vert_id,vert in ipairs(face) do
			local vc=vert:to_cartesian()-min_point
			table.insert(vert_out,vc[1])
			table.insert(vert_out,vc[2])
		end
	end
	print("Vertex size:",#vert_out)
	f:write(string.format("vertex_coords = PackedVector2Array(%s)\n",table.concat( vert_out,", ")))
	f:close()
end
local frame=0
function update(  )
	__no_redraw()
	__clear()
	local scale=math.pow(2,-3)


	local tiling_dx=tiling.dx:to_cartesian()
	local tiling_dy=tiling.dy:to_cartesian()
	--print("dx:",tiling_dx)
	--print("dy:",tiling_dy)
	local center=tiling_dx+tiling_dy
	center=center*0.5
	local min_t=-0
	local max_t=-min_t
	imgui.Begin("Tiling")
	local need_rnd=false
	if imgui.Button("Randomize") then
		need_rnd=true
	end
	if imgui.Button("Export Tiling") then
		save_gdres(tiling_name)
	end
	--[[if imgui.Button("rnd_rules") then
		generate_rules()
	end]]
	if imgui.Button("rnd") then
		init_grid_random(min_t,max_t,.2)
	end
	--if imgui.Button("step") then
	if frame>3 then
		apply_rules(min_t,max_t)
		frame=0
	end
	frame=frame+1
	--end
	--draw_state( min_t,max_t )
	--step_pointer(min_t,max_t)
	for dx=min_t,max_t do
		for dy=min_t,max_t do
			local ndx=(dx-min_t)/(max_t-min_t)
			local ndy=(dy-min_t)/(max_t-min_t)
			local pt_dx=tiling_dx*dx
			local pt_dy=tiling_dy*dy
			local delta=pt_dx+pt_dy-center
			local ginfo=lookup_grid(dx,dy)
			local colors=ginfo.colors or {}
			local ndx1=(delta[1]*scale+1)/2
			local ndy1=(delta[2]*scale+1)/2
			ndx1=math.min(math.max(ndx1,0),1)
			ndy1=math.min(math.max(ndy1,0),1)
			--if #colors<#topo_info.face_count or math.random()>0.999 or need_rnd then
			--[[
			if #colors<#topo_info.face_count or need_rnd then
				for i=1,#topo_info.face_count do
					local ndf=(i-1)/#topo_info.face_count
					if need_rnd then
						--colors[i]={math.random(),math.random(),math.random(),1}
						colors[i]=colorize(math.random(),math.random(),math.random())
					else
						--colors[i]={ndx,(i-1)/#topo_info.face_count,ndy,1}
						--colors[i]={0.1+ndx1*0.8+nsin(ndy1*487)*nsin(ndx1+time*5)*0.1,nsin(ndf*12+ndy1*4+time)*0.5+0.125,0.2+ndy1*0.2,1}
						--colors[i]=colorize(ndx1+nsin(time),ndy1,ndf)
						--colors[i]=palette(ndf,ndx1,ndy1) --todo
						colors[i]=colorize(0,0,ndf)
					end
				end
			end
			--]]
			ginfo.colors=colors
			if inside_window(tiling_dx*scale,tiling_dy*scale,delta[1]*scale,delta[2]*scale) then
				set_face_color(topo_info,colors)
				draw_faces( delta[1],delta[2],scale)
			end
		end
	end
	time=time+0.05
	if need_save then
		save_img()
		need_save=false
	end
	
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
end