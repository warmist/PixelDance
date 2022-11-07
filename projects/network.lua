require "common"

require "graph"
local size=STATE.size
local max_size=math.min(size[1],size[2])/2
img_buf=img_buf or make_image_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
end

config=make_config({

	},config)
function gen_pos( angle )
	return {math.cos(angle)*0.4,math.sin(angle)*0.4}
end
function new_network(  )
	network={nodes={}}
	local nn={}
	local count=7
	for i=1,count do
		local a=add_node(network,{name="node_"..i,pos=gen_pos(math.pi*2*i/count)})
		nn[i]=a
		if i>1 then
			link_nodes(network,nn[i],nn[i-1])
			if math.random()>0.1 then
				link_nodes(network,nn[i],nn[math.random(1,i)])
				--[[for h=1,i do
					link_nodes(network,nn[i],nn[h])
				end]]
			end
		end
	end
	link_nodes(network,nn[count],nn[1])
end

if network==nil then
	new_network()
end

function draw_nodes( )
	-- todo
end

local MAX_LINE_POINT_COUNT=5000
local line_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

void main(){
	color=vec4(1,0,0,1);
}
]==]
line_points=make_flt_half_buffer(MAX_LINE_POINT_COUNT,1)
function regen_line_buffer(  )
	network.clean=true
	local edges={}
	for k,v in pairs(network.nodes) do
		for k,v in pairs(k.edges) do
			edges[k]=true
		end
	end
	network.edge_mapping=edges

	local i=0
	for k,v in pairs(edges) do
		edges[k]=i
		i=i+1
	end
	line_count=i*2

end
function update_line_buffer(  )
	for k,v in pairs(network.edge_mapping) do

		local source=k[1]
		local target=k[2]
		local sp=source.pos
		local tp=target.pos

		line_points:sset(v*2,0,{sp[1],sp[2]})
		line_points:sset(v*2+1,0,{tp[1],tp[2]})
	end
end
function draw_edges(  )
	if not network.clean then
		regen_line_buffer()
	end
	update_line_buffer()
	line_shader:use()
	line_shader:draw_lines(line_points.d,line_count,false)
end
function set_or_add( tbl,key,pos )
	if tbl[key] then
		tbl[key][1]=tbl[key][1]+pos[1]
		tbl[key][2]=tbl[key][2]+pos[2]
	else
		tbl[key]=pos
	end
end
function calc_force( p1,p2,str )
	local opt_edge=0.1*str
	local springiness=0.0001


	local dx=p1[1]-p2[1]
	local dy=p1[2]-p2[2]
	local d=math.sqrt(dx*dx+dy*dy)
	local dir_x
	local dir_y
	if d >0.001 then
		dir_x=dx/d
		dir_y=dy/d
	else
		local a=math.random()*math.pi*2
		dir_x=math.cos(a)
		dir_y=math.sin(a)
	end
	local force=springiness*(d-opt_edge)
	--F=-kv
	return {force*dir_x,force*dir_y}
end
function calc_angular_force( center,around )
	--try to move points so that angles are about the same


end
function simulate( dt )
	local max_radius=0.9

	--[[
		algo:
			* resize so the points are always around 0,0 with some bbox size
			* add springs from nodes to the center (does same thing as above?)
			* add springs as edges

			Maybe also:
			* some angle maximization or sth
	--]]
	local node_forces={}
	local center={0,0}
	for k,v in pairs(network.edge_mapping) do
		local p1=k[1].pos
		local p2=k[2].pos
		--F=-kv
		local F=calc_force(p1,p2,1)
		set_or_add(node_forces,k[1],{-F[1],-F[2]})
		set_or_add(node_forces,k[2],{F[1],F[2]})
	end
	local count=0
	for k,v in pairs(network.nodes) do
		center[1]=k.pos[1]+center[1]
		center[2]=k.pos[2]+center[2]
		count=count+1
	end
	center[1]=center[1]/count
	center[2]=center[2]/count
	for k,v in pairs(network.nodes) do
		local F=calc_force(k.pos,center,6)
		set_or_add(node_forces,k,{-F[1],-F[2]})

	end
	for k,v in pairs(node_forces) do
		k.pos[1]=k.pos[1]+v[1]-center[1]
		k.pos[2]=k.pos[2]+v[2]-center[2]
	end
end
function generate_all_edges( nodes )
	local ret={}
	for i=1,#nodes do
		for j=i+1,#nodes do
			table.insert(ret,{nodes[i],nodes[j]})
		end
	end
	return ret
end
function tconcat( tbl,visitor,seperator )
	local ret=""
	for i=1,#tbl do
		if i==1 then
			ret=visitor(tbl,i)
		else
			ret=ret..seperator..visitor(tbl,i)
		end
	end
	return ret
end
function print_rule( r )
	print("Rule:",r)
	print("\tMatch:")
	local node_str=table.concat(r.match.nodes,",")
	print("\t\tNodes:"..node_str)
	local f_edge=function (e,i)
		if e==nil or e[i]==nil then
			return "ERR"
		elseif e[i][1]==nil or e[i][2]==nil then
			return "EERR"
		end
		return string.format("{%d - %d}",e[i][1],e[i][2])
	end
	local edge_str=tconcat(r.match.edges,f_edge,",")
	print("\t\tEdges:"..edge_str)
	local not_edge_str=tconcat(r.match.not_edges,f_edge,",")
	print("\t\tNot edges:"..not_edge_str)
	local f_add_node=function (e,i )
		return string.format("%d",e[i].id)
	end
	print("\tApply:")
	local add_node_str=tconcat(r.apply.add_node,f_add_node,",")
	print("\t\tAdd nodes:"..add_node_str)
	local add_edge_str=tconcat(r.apply.add_edge,f_edge,",")
	print("\t\tAdd edge:"..add_edge_str)

end
function random_rule(  )
	local ret={match={},apply={}}
	local m=ret.match
	m.nodes={}
	m.edges={}
	m.not_edges={}
	local a=ret.apply
	--TODO: remove nodes
	--TODO: remove edge
	a.add_node={}
	a.add_edge={}
	local edge_count=math.random(1,4)
	local max_count=math.random(3,9)
	local not_edge_count=math.random(0,2)

	local add_node_count=math.random(0,2)
	local add_new_node_edges=math.random(1,3)
	local add_new_not_edges=math.random(1,3)
	local add_new_other_edges=math.random(1,3)
	for i=1,max_count do
		table.insert(m.nodes,i)
	end
	local all_edges=generate_all_edges(m.nodes)
	if add_new_other_edges>#all_edges-edge_count-not_edge_count then
		add_new_node_edges=#all_edges-edge_count-not_edge_count-1
	end
	shuffle_table(all_edges)
	for i=1,edge_count do
		table.insert(m.edges,all_edges[i])
	end
	for i=1,not_edge_count do
		table.insert(m.not_edges,all_edges[i+edge_count])
	end

	for i=1,add_node_count do
		table.insert(a.add_node,
			{id=max_count+i,
				data={name="node_??",pos={math.random()*1-0.5,math.random()*1-0.5}}})
	end
	if add_node_count>0 then
		for i=1,add_new_node_edges do
			table.insert(a.add_edge,{a.add_node[math.random(1,#a.add_node)].id,m.nodes[math.random(1,#m.nodes)]})
		end
	end
	if not_edge_count>0 then
		for i=1,add_new_node_edges do
			table.insert(a.add_edge,m.not_edges[i])
		end
	end
	for i=1,add_new_other_edges do
		table.insert(a.add_edge,all_edges[i+edge_count+not_edge_count])
	end
	print_rule(ret)
	return ret
end
function check_rule( rr )
	local ok={}
	for i=1,#rr.match.nodes do
		ok[rr.match.nodes[i]]=false
	end
	for i,v in ipairs(rr.match.edges) do
		ok[v[1]]=true
		ok[v[2]]=true
	end
	--[==[
	for i,v in ipairs(rr.match.not_edges) do
		ok[v[1]]=true
		ok[v[2]]=true
	end
	--]==]
	local good=true
	for k,v in pairs(ok) do
		if not v then
			print("Unreferenced node:"..k)
			good=false
		end
	end
	return good
end
function update(  )

	imgui.Begin("Graphs N Crafts")
	draw_config(config)
	if imgui.Button("Clear") then
		img_buf:clear()
	end
	if imgui.Button("Apply Rule") then
		--[[local rule={
			--match={nodes={1,2,3,4},edges={{1,2},{2,3},{3,4}},not_edges={{1,4}}},
			match={nodes={1,2,3},edges={{1,2},{2,3}}},
	 	 	apply={add_node={{id=4,data={name="node_??",pos={math.random()*2-1,math.random()*2-1}}}},add_edge={{4,1},{4,2},{4,3}}}
		}]]
		local rr=random_rule()
		if check_rule(rr) then
			apply_random(network,rr)
			network.clean=false
		end
	end
	if imgui.Button("Remove Dense Stuff") then
		local rule={
			match={nodes={1,2,3,4},edges={{1,2},{1,3},{1,4},{1,5}}},
	 	 	apply={remove_node={1}}
		}
		apply_random(network,rule)
		network.clean=false
	end
	if imgui.Button("Untangle") then
		for k,v in pairs(network.nodes) do
			k.pos[1]=math.random()*2-1
			k.pos[2]=math.random()*2-1
		end
	end
	if imgui.Button("Clear Objects") then
		new_network()
	end

	__no_redraw()
	__clear()

	draw_edges()
	draw_nodes()
	simulate()

	imgui.End()
end