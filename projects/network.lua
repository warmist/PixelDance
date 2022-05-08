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
function calc_force( p1,p2 )
	local opt_edge=0.3
	local springiness=0.001


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
		local F=calc_force(p1,p2)
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
		local F=calc_force(k.pos,center)
		set_or_add(node_forces,k,{-F[1],-F[2]})
	end
	for k,v in pairs(node_forces) do
		k.pos[1]=k.pos[1]+v[1]-center[1]
		k.pos[2]=k.pos[2]+v[2]-center[2]
	end
end

function update(  )

	imgui.Begin("Graphs N Crafts")
	draw_config(config)
	if imgui.Button("Clear") then
		img_buf:clear()
	end
	if imgui.Button("Apply Rule") then
		local rule={
			match={nodes={1,2,3,4},edges={{1,2},{2,3},{3,4}},not_edges={{1,4}}},
	 	 	apply={remove_edge={{2,3}}}
		}
		apply_random(network,rule)
		network.clean=false
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