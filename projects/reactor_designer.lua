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
local topology={
	faces={},
	grid=MultiKeyTable(),
	unfinished_vertexes={},
}
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
	ret.id=#self.faces+1
	table.insert(self.faces,ret)
	return ret
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

function create_ngon( start_vec,count_edges,start_orientation )
	if type(start_vec)=="number" then
		start_orientation=count_edges
		count_edges=start_vec
		start_vec=four_vec(0,0,0,0)
	end
	start_orientation=start_orientation or 1
	local ret={}
	local step=12/count_edges
	local cur_pos=start_vec
	for i =1,12,step do
		table.insert(ret,cur_pos)
		cur_pos=cur_pos:add(four_vec.omega(i+start_orientation-1))
	end
	return topology:add_face(ret)
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
function create_seed(letter,start_pos)
	start_pos=start_pos or four_vec(0,0,0,0)
	local choice=letter_table[letter]
	local cur_omega=1
	for k,v in ipairs(choice) do
		if k>1 then
			cur_omega=cur_omega+6+12/v
		end
		print("Omega:",lua_mod(cur_omega,12))
		create_ngon(start_pos,v,cur_omega)
		--[[
		if k==4 then
			break
		end
		--]]
	end

	for _,face in ipairs(topology.faces) do
		for _,v in ipairs(face.vertexes) do
			if v[1]~=0 or v[2]~=0 or v[3]~=0 or v[4]~=0 then
				table.insert(topology.unfinished_vertexes,v)
				v.finished=false
			else
				v.finished=letter
			end
		end
	end

end

print("Unfinished:",#topology.unfinished_vertexes)
function does_sublist_match(tbl,match)
	for i=0,#tbl-1 do
		local actual_match=true
		for j=1,#match do
			if tbl[lua_mod(i+j,#tbl)]~=match[j] then
				actual_match=false
				break
			end
		end
		if actual_match then
			return true,i --TODO: multiple matches???
		end
	end
end
function does_sublist_match_rev(tbl,match)
	for i=0,#tbl-1 do
		local actual_match=true
		for j=1,#match do
			if tbl[#tbl-lua_mod(i+j,#tbl)+1]~=match[j] then
				actual_match=false
				break
			end
		end
		if actual_match then
			return true,i --TODO: multiple matches???
		end
	end
end
function match_sublist( tbl )
	local ret={}
	for k,v in pairs(letter_table) do
		local m,offset=does_sublist_match(v,tbl)
		if m then
			table.insert(ret,{k,offset})
		end
		local m,offset=does_sublist_match_rev(v,tbl)
		if m then
			table.insert(ret,{k.."'",offset})
		end
	end
	return ret
end
--- Get vertex faces in CW order
function query_vertex_faces_sorted2( vertex )
	local faces=vertex.faces
	local ret_count={}
	local ret_direction={}
	--local ret_id={} --TODO?
	if #faces==0 then
		return ret_count,ret_direction
	end
	local rev_faces={}
	for i,v in ipairs(faces) do
		rev_faces[v]=i
	end
	local face_used={}
	function has_same_face( vert )
		for i,v in ipairs(vert.faces) do
			if rev_faces[v] then
				return true,v
			end
		end
		return false
	end
	local empty_edges={}
	local first_dbl=false
	local is_first=true
	-- look in all directions
	for i = 1,12 do
		local trg_vert=vertex:add(four_vec.omega(i))
		-- check if it's used
		local grid_next_pt=topology.grid:get_vec(trg_vert)
		if grid_next_pt then
			local dbl_edge=topology:check_reverse_edge(vertex,grid_next_pt)
			if is_first then
				first_dbl=dbl_edge
			end

			print(i,"IS dbl:",dbl_edge)
			if not dbl_edge then
				table.insert(empty_edges,i)
			end

			local _,shared_face=has_same_face(grid_next_pt)
			if shared_face and not face_used[shared_face] then
				face_used[shared_face]=true

				table.insert(ret_count,shared_face.count)
				table.insert(ret_direction,i)
			end
		end
	end
	-- [[
	if first_dbl then
		empty_edges[1],empty_edges[2]=empty_edges[2],empty_edges[1]
	end
	--]]
	return ret_count,ret_direction,empty_edges
end
--- Get vertex faces in CW order
function query_vertex_faces_sorted( vertex )
	local faces=vertex.faces
	local ret_count={}
	local ret_face={}
	local ret_direction={}

	if #faces==0 then
		return ret_count,ret_direction
	end
	local offset=0
	--find empty direction offset
	for i = 12,1,-1 do
		local trg_vert=vertex:add(four_vec.omega(i))
		-- check if it's used
		local grid_next_pt=topology.grid:get_vec(trg_vert)
		if grid_next_pt then
			if not topology:check_reverse_edge(vertex,grid_next_pt) then
				offset=12-i
				break
			end
		end
	end
	print("working with offset",offset)
	-- look in all directions
	for i = 12,1,-1 do
		local trg_vert=vertex:add(four_vec.omega(i+offset))
		-- check if it's used
		local grid_next_pt=topology.grid:get_vec(trg_vert)
		if grid_next_pt then
			--print(vertex:to_string(),grid_next_pt:to_string())
			for _,f in ipairs(faces) do
				local is_inside=topology:is_inside_edge(vertex,grid_next_pt,f)
				if is_inside then
					table.insert(ret_count,f.count)
					table.insert(ret_direction,i+offset)
					table.insert(ret_face,f)
				end
			end
		end
	end

	return ret_count,ret_direction,ret_face
end
local function reverse_table(tab)
	local ret={}

    for i = 1, #tab do
        ret[i]=tab[#tab-i+1]
    end
    return ret
end
function get_letter_table_entry( letter )
	if letter:sub(-1)=="'" then
		return reverse_table(letter_table[letter:sub(1,1)])
	else
		return letter_table[letter]
	end
end
function create_missing_faces( start_vec,existing_faces,vert_directions,vert_type,offset )
	print("Creating new faces for:")
	for i,v in ipairs(vert_directions) do
		print("-",i,existing_faces[i],v)
	end
	print("\t"..start_vec:to_string(),existing_faces[#existing_faces],vert_directions[#vert_directions],vert_type,offset)
	local choice=get_letter_table_entry(vert_type)
	local cur_omega=vert_directions[#existing_faces]
	local new_faces={}
	for id=1,#choice-#existing_faces do
		local actual_id=lua_mod(id+offset+#existing_faces,#choice)
		local face_type=choice[actual_id]
		--if id>1 then
			cur_omega=cur_omega+6+12/face_type
		--end
		print("\tAdding face:",face_type,lua_mod(cur_omega,12))
		table.insert(new_faces,create_ngon(start_vec,face_type,cur_omega))

	end

	for _,face in ipairs(new_faces) do
		for _,v in ipairs(face.vertexes) do
			topology:check_vertex_filled(v)
			if not v.finished then
				table.insert(topology.unfinished_vertexes,v)
			end
		end
	end
	local was_unfinished=#topology.unfinished_vertexes
	local unfinished_vertexes={}
	for i,v in ipairs(topology.unfinished_vertexes) do
		if not v.finished then
			table.insert(unfinished_vertexes,v)
		end
	end
	topology.unfinished_vertexes=unfinished_vertexes
	print("Culled:",was_unfinished-#unfinished_vertexes)
end


function print_matching(letter,offset,faces_sorted)
	local fc={}
	for i=1,offset do
		table.insert(fc,"0")
	end
	for i,v in ipairs(faces_sorted) do
		table.insert(fc,v)
	end
	print(table.concat( fc," "))

	if letter:sub(-1)=="'" then
		local tbl= reverse_table(letter_table[letter:sub(1,1)])

		print(table.concat(tbl, " "))
	else
		print(table.concat( letter_table[letter], " "))
	end
end
local L_found=false
function fill_out_unfinished_vert(vert_id,letter)
	print("Remaining:",#topology.unfinished_vertexes)
	local vert=topology.unfinished_vertexes[vert_id]
	table.remove(topology.unfinished_vertexes,vert_id)
	
	print("Doing:",vert:to_string(),letter)
	print(#vert.faces)
	local faces_sorted,dirs=query_vertex_faces_sorted(vert)
	print("Found faces:",table.concat( faces_sorted, " " ))
	local can_match_stuff=match_sublist(faces_sorted)
	local choice
	for i,v in ipairs(can_match_stuff) do
		print("\t",v[1],v[2])
		print_matching(v[1],v[2],faces_sorted)
		if v[1]=="L" or v[1]=="L'" then
			L_found=true
		end
		if v[1]==letter then
			choice=i
		end
	end
	if letter==" " then
		vert.finished=true
		return
	end
	if choice==nil then
		print("Couldn't add letter:"..letter)
		return
	end
	create_missing_faces(vert,faces_sorted,dirs,can_match_stuff[choice][1],can_match_stuff[choice][2])
end
--[[
create_seed('L')
fill_out_unfinished_vert(1,"L'")
fill_out_unfinished_vert(1,"T")
fill_out_unfinished_vert(1,"H'")
fill_out_unfinished_vert(1,"H")
fill_out_unfinished_vert(1,"H'")
fill_out_unfinished_vert(1,"H")
fill_out_unfinished_vert(1,"L'")
fill_out_unfinished_vert(1,"L")
fill_out_unfinished_vert(1,"H'")
fill_out_unfinished_vert(1,"H")
fill_out_unfinished_vert(1,"H'")
fill_out_unfinished_vert(1,"P")
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1,"P")
L_found=false
for i=1,14 do
	fill_out_unfinished_vert(1," ")
	if L_found then
		print("=====================")
		print(i)
		break
	end
end
fill_out_unfinished_vert(1,"W")
--[[
--]]

create_seed('U')
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1," ")
fill_out_unfinished_vert(1," ")

fill_out_unfinished_vert(1,"U")

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