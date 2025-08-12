require "common"
require "half_edge_planar"
-- DEAD LINK!: http://cesperanca.org/archimedean
--[[ random idea:
	- figure out what symmetry exists
		- add path to-from symmteric element
		- action allows movement along the path
--]]
local m=model()

function lua_mod( v,k )
	return ((v-1) %k)+1
end
function MultiKeyTable:get_vec( v )
	return self:get(v[1],v[2],v[3],v[4])
end
function MultiKeyTable:set_vec( v,value )
	self:set(v[1],v[2],v[3],v[4],value)
end
local mtbl=MultiKeyTable
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
four_vec=class(function (tbl, ...)
    tbl:new(...)
  end
)
--return correct omega power
function four_vec.omega(k)
	--allow end_id >12 by modulo wrapping
	local kid=lua_mod(k,12)
	return four_vec(omega_powers[kid])
end
function four_vec:new( v1,v2,v3,v4 )
	if type(v1)=="table" then
		for i=1,4 do
			self[i]=v1[i]
		end
	else
		self[1]=v1
		self[2]=v2
		self[3]=v3
		self[4]=v4
	end
	self.directions={}
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
	return string.format("(4vec %d %d %d %d)",self[1],self[2],self[3],self[4])
end
function four_vec:set_direction_filled( start_dir,end_dir,face )
	start_dir=lua_mod(start_dir,12)
	end_dir=lua_mod(end_dir,12)
	--print("Setting dir:",start_dir,end_dir,face.id)
	local cur_dir
	for i=0,11 do
		cur_dir=lua_mod(start_dir+i,12)
		self.directions[cur_dir]=self.directions[cur_dir] or {}
		local sides=self.directions[cur_dir]
		if cur_dir~=end_dir then
			if sides.l~=nil then
				error("Left side already set to:"..sides.l.id)
			end
			sides.l=face
		end
		if i~=0 then
			if sides.r~=nil then
				error("Right side already set to:"..sides.r.id)
			end
			sides.r=face
		end
		if cur_dir==end_dir then
			break
		end
	end
end
function four_vec:directions_string()
	local tbl={}
	for i=1,12 do
		local sides=self.directions[i]
		if sides then
			if sides.l==sides.r then
				table.insert(tbl,sides.l.id)
			else
				local lid=-1
				if sides.l then lid=sides.l.id end
				local rid=-1
				if sides.r then rid=sides.r.id end
				local substr=string.format("%d/%d",lid,rid)
				table.insert(tbl,substr)
			end
		else
			table.insert(tbl,"-")
		end
	end
	return table.concat( tbl, " " )
end
function four_vec:is_dir_empty(dir)
	local sides=self.directions[lua_mod(dir,12)]
	if sides==nil or (sides.l==nil and sides.r==nil) then
		return true
	end
	return false
end
function four_vec:is_dir_lempty( dir )
	local sides=self.directions[lua_mod(dir,12)]
	if sides==nil or sides.l==nil then
		return true
	end
	return false
end
function four_vec:is_dir_rempty( dir )
	local sides=self.directions[lua_mod(dir,12)]
	if sides==nil or sides.r==nil then
		return true
	end
	return false
end
function four_vec:first_non_empty_back(  )
	for i=13,2,-1 do
		if not self:is_dir_empty(i) then
			return i-1
		end
	end
	return 0
end
--first empty direction in ccw
function four_vec:first_empty( min_size )
	local offset=self:first_non_empty_back()
	print("O:",offset)
	min_size=min_size or 1
	for i=1,12 do
		local is_empty=true
		for mi=0,min_size-1 do
			if mi==0 then
				if not self:is_dir_lempty(i+mi+offset) then
					is_empty=false
					break
				end
			elseif mi==min_size-1 then
				if not self:is_dir_rempty(i+mi+offset) then
					is_empty=false
					break
				end
			else
				if not self:is_dir_empty(i+mi+offset) then
					is_empty=false
					break
				end
			end
		end
		if is_empty then
			return lua_mod(i+offset,12)
		end
	end
end
function four_vec:first_empty_ngon( count )
	local inner_angle=(count-2)*6/count
	return self:first_empty(inner_angle)
end
function four_vec:is_filled( )
	for i=1,12 do
		local sides=self.directions[i]
		if sides==nil then
			return false
		end
		if sides.l==nil or sides.r==nil then
			return false
		end
	end
	return true
end
--vertexes can be one of G-W types
-- G-> 12gon * 2 + 3gon to
-- W-> 6*3gon

--[[ a "reactor" (i.e. tilling of archimedian ngons) might be designed as such
		- select seed (one of 3,4,6,8,12 sided ngons)
		- put all vertexes into unfinished list
		- repeat while have unfinished vertexes:
			- select vertex
			- apply one of archimedean vertex types (G to W/ empty )
			- mark this vertex as complete
			- mark other vertexes (if surounded) as complete
			- add new vertexes into unfinished list
		Then the full output might be seed+string of letters (use "_") for empty
		Or start from vertex seed!
--]]
--[[

]]
local topology={
	faces={},
	grid=MultiKeyTable(),
	unfinished_vertexes={},
}
function topology:get_point( v )
	return self.grid:get_vec(v)
end
function topology:getc_point( v )
	local pt=self.grid:get_vec(v)
	if pt==nil then
		self.grid:set_vec(v,v)
	end
	return self.grid:get_vec(v)
end

function topology:check_reverse_edge(v1,v2)
	-- if v1 and v2 share same two faces => it's a double edge v1<->v2
	local shared_faces={}
	local ret_faces={}
	for i,v in ipairs(v1.faces) do
		shared_faces[v]=1
	end
	local count_shared=0
	for i,v in ipairs(v2.faces) do
		if shared_faces[v] then
			count_shared=count_shared+1
			ret_faces[count_shared]=v
		end
	end
	if count_shared==2 then
		return true,ret_faces
	end
end
function topology:is_inside_edge(v1,v2,face)

	for i,v in ipairs(face.vertexes) do
		if v==v1 then
			if face.vertexes[lua_mod(i+1,#face.vertexes)]==v2 then
				return true,i
			else
				return false,i
			end
		end
	end
	return false,-1
end
function topology:add_face( vertexes,omegas )
	local ret={vertexes={},count=#vertexes}
	ret.id=#self.faces+1
	for vert_id,v in ipairs(vertexes) do
		local vv=self.grid:get(v[1],v[2],v[3],v[4])
		--print("Get:",v[1],v[2],v[3],v[4],vv)
		if vv==nil then
			vv=v
			vv.faces={}
			self.grid:set(v[1],v[2],v[3],v[4],vv)
		end
		table.insert(vv.faces,ret)
		table.insert(ret.vertexes,vv)
	end
	self:link_half_edges()

	table.insert(self.faces,ret)
	return ret
end
function topology:add_ngon(vertex_start,start_omega,count)
	local ret={vertexes={},count=count}
	ret.id=#self.faces+1
	local step=12/count
	local inner_angle=(count-2)*6/count
	local cur_pos=self:getc_point(vertex_start)
	for i =1,12,step do
		cur_pos:set_direction_filled(i+start_omega-1,i+start_omega-1+inner_angle,ret)
		table.insert(ret.vertexes,cur_pos)
		cur_pos=self:getc_point(cur_pos:add(four_vec.omega(i+start_omega-1)))
	end
	table.insert(self.faces,ret)
	return ret
end
function topology:fit_ngon(vertex,count )
	local omega=vertex:first_empty_ngon(count)
	print("Found omega:",omega,vertex:directions_string())
	return self:add_ngon(vertex,omega,count)
end
function topology:check_vertex_filled( v )

	local filled=true
	for i=1,12 do
		local next_pt=v:add(four_vec.omega(i))
		local grid_next_pt=self.grid:get_vec(next_pt)
		if grid_next_pt then
			if not self:check_reverse_edge(v,grid_next_pt) then
				v.finished=false
				return false
			end
		end
	end
	v.finished=true
	return true
end
function topology:parse_string(s)
	--3,4,6,D,*
	local unfinished_vertexes={}
	local cur_vertex=topology:getc_point(four_vec(0,0,0,0))
	function advance_vertex(  )
		cur_vertex=unfinished_vertexes[1]
		table.remove(unfinished_vertexes,1)
		while cur_vertex:is_filled() do
			cur_vertex=unfinished_vertexes[1]
			table.remove(unfinished_vertexes,1)
		end
	end
	local ngon_count={
		['3']=3,['4']=4,['6']=6,['D']=12
	}
	for i =1,#s do
		local letter=s:sub(i,i)
		print(i,letter)
		if ngon_count[letter] then
			local nngon=topology:fit_ngon(cur_vertex,ngon_count[letter])
			for _,v in ipairs(nngon.vertexes) do
				table.insert(unfinished_vertexes,v)
			end
		elseif letter=="*" then
			advance_vertex()
		else
			error("Invalid command:"..letter)
		end
		if cur_vertex:is_filled() then
			advance_vertex()
		end
	end
end

count_draw=0
--add triangles of the face to buffers
function process_face(f,tri_data,color_data,point_offset)
	--print("Processing face:",f,"with ",#f,"vertices")
	local color={math.random(),math.random(),math.random(),1}
	local verts=f.vertexes
	local center_pt=Point(0,0,0,0)
	local face_verts={}
	for vert_id=1,#verts do
		local tmp_pt=verts[vert_id]:to_cartesian()
		face_verts[vert_id]=tmp_pt
		center_pt=center_pt+tmp_pt
	end
	center_pt=center_pt/#verts
	local current_offset=point_offset
	local function add_pt( pt )
		tri_data:set(current_offset,0,{pt[1],pt[2],0,1})
		color_data:set(current_offset,0,color)
		current_offset=current_offset+1
	end
	local shrinkage=0.05
	for vert_id=1,#verts do
		--print("adding:",vert_id)
		local centerwise1=center_pt-face_verts[vert_id]
		centerwise1:normalize()
		add_pt(face_verts[vert_id]+centerwise1*shrinkage)
		local centerwise2=center_pt-face_verts[lua_mod(vert_id+1,#verts)]
		centerwise2:normalize()
		add_pt(face_verts[lua_mod(vert_id+1,#verts)]+centerwise2*shrinkage)
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
		count_tri=count_tri+#f.vertexes
		count_pt=count_pt+#f.vertexes*3
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



local letter_table={
	G={12,12,3},
	H={6,12,4},
	K={6,6,6},
	L={3,12,4,3},
	M={3,12,3,4},
	N={4,4,6,3},
	P={4,3,4,6},
	Q={3,6,6,3},
	R={6,3,6,3},
	S={4,4,4,4},
	T={4,3,3,3,4},
	U={3,4,3,4,3},
	V={6,3,3,3,3},
	W={3,3,3,3,3,3},
}

local function reverse_table(tab)
	local ret={}

    for i = 1, #tab do
        ret[i]=tab[#tab-i+1]
    end
    return ret
end

--[[
local start=topology:add_ngon(four_vec(0,0,0,0),1,6)
local zero_point=start.vertexes[1]
print(zero_point:directions_string(),zero_point:first_empty())
for i=1,10 do
	print("\t",i,zero_point:first_empty(i))
end
local s2=topology:fit_ngon(zero_point,6)
local s3=topology:fit_ngon(zero_point,6)
local pt2=start.vertexes[2]
print(pt2:directions_string())
topology:fit_ngon(pt2,3)
topology:fit_ngon(pt2,3)
topology:fit_ngon(s2.vertexes[2],3)
topology:fit_ngon(s2.vertexes[2],3)
topology:fit_ngon(s3.vertexes[2],3)
topology:fit_ngon(s3.vertexes[2],3)
--]]
topology:parse_string("6663344344334434433443443**********3***********3")--4434*334434433443443")
fill_faces(topology.faces)
function save_gdres( name , topology )
	local f=io.open(name..".txt","w")

	f:write(string.format("tiling_dx = Vector2(%g,%g)\n",0,0))
	f:write(string.format("tiling_dy = Vector2(%g,%g)\n",0,0))
	local table_counts={}
	for i,v in ipairs(topo_info.face_cons) do
		table.insert(table_counts,#v)
	end
	f:write(string.format("vertex_counts = PackedInt32Array(%s)\n",table.concat( table_counts,", ")))
	local topo_out={}
	for i,v in ipairs(topo_info.face_cons) do
		for vert_id,vert_con in ipairs(v) do
			table.insert(topo_out,vert_con[1])
			table.insert(topo_out,vert_con[2])
			table.insert(topo_out,vert_con[3])
		end
	end
	f:write(string.format("face_topology = PackedInt32Array(%s)\n",table.concat( topo_out,", ")))
	f:write(string.format("tiling_name = \"%s\"\n",name))
	local vert_out={}
	for face_id,face in ipairs(faces_list) do
		for vert_id,vert in ipairs(face) do
			local vc=vert:to_cartesian()
			table.insert(vert_out,vc[1])
			table.insert(vert_out,vc[2])
		end
	end
	f:write(string.format("vertex_coords = PackedVector2Array(%s)\n",table.concat( vert_out,", ")))
	f:close()
end
function save_reactor()

end
function update(  )
	__clear()
	imgui.Begin("R")
	if imgui.Button("Save") then
		save_reactor()
	end
	imgui.End()
	draw_faces(0,0,0.1)
end