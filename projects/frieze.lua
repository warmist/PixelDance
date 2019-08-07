--[[
	generate frieze patterns
--]]
require "common"
local win_w=1024
local win_h=1024

__set_window_size(win_w,win_h)
local oversample=0.25
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local size=STATE.size

img_buf=img_buf or make_image_buffer(map_w,map_h)

function resize( w,h )
	img_buf=make_image_buffer(map_w,map_h)
end

local size=STATE.size

tick=tick or 0
config=make_config({
	{"n",3,type="int",min=3},
	{"mutate",1,type="int"},
},config)
image_no=image_no or 0

local need_save
local img_tex1=textures.Make()
function write_img(  )
	img_tex1:use(0)
	img_buf:write_texture(img_tex1)
end
write_img()

function save_img()
	if save_buf==nil or save_buf.w~=win_w or save_buf.h~=win_h then
		save_buf=make_image_buffer(win_w,win_h)
	end

	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	save_buf:read_frame()
	save_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
local draw_shader=shaders.Make(
[==[
#version 330
#line 118
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    vec4 pixel=texture(tex_main,normed);
    color=vec4(pixel.xyz,1);
}
]==])
function draw(  )
	draw_shader:use()
    img_tex1:use(0)
	draw_shader:set_i("tex_main",0)
	draw_shader:set_i("tex_cryst",1)
	draw_shader:draw_quad()
end

function triangulate_ngon( num_vertex,num_mutations )
	--triangulate and count triangles from each vertex
	if num_vertex<=3 then
		return {1,1,1}
	end
	local vertexes={}
	for i=1,num_vertex do
		vertexes[i]={id=i}
	end
	local edges={}
	local function remove_edge(e)
		for i=1,#edges do
			if edges[i]==e then
				table.remove(edges,i)
				break
			end
		end
		local v1=e[1]
		for i=1,#v1 do
			if v1[i]==e then
				table.remove(v1,i)
				break
			end
		end
		local v2=e[2]
		for i=1,#v2 do
			if v2[i]==e then
				table.remove(v2,i)
				break
			end
		end
	end
	local function add_edge( v1,v2 )
		local e={vertexes[v1],vertexes[v2]}
		table.insert(vertexes[v1],e)
		table.insert(vertexes[v2],e)
	end
	--also "implied edges": 1->2, 2->3, ..., n->1
	--make a fan
	for i=3,num_vertex-1 do
		add_edge(1,i)
	end

	--mutate the ngon
	for i=1,num_mutations do
		local n=math.random(1,num_vertex)
		--get random vertex
		if #vertexes[n]==1 then
			--get random edge
			local e=vertexes[n][math.random(1,#vertexes[n])]
			for k,v in pairs(e) do
				print(k,v)
			end
			local v_bef=n-1
			if v_bef==0 then
				v_bef=num_vertex
			end
			local v_next=n+1
			if v_next==num_vertex+1 then
				v_next=1
			end

			print("Mutating- flip of",e[1].id,e[2].id)
			--remove
			remove_edge(e)
			--add flipped
			add_edge(v_bef,v_next)
			print("added :",v_bef,v_next)
		end
	end
	--output the num of triangles
	local ret={}
	for i,v in ipairs(vertexes) do
		--triangle count is num edges+1
		ret[i]=#v+1
	end
	return ret
end
function gen_frieze_pattern( ngon_triangles )
	local rows={}
	local n=#ngon_triangles
	local last=n-1
	for i=1,n do
		rows[i]={}
	end	
	for i=1,n do
		rows[1][i]=1
		rows[last][i]=1
	end
	--TODO: we could shift here? maybe same as rotating ngon
	rows[2]=ngon_triangles
	for j=3,last-1 do
		local r0=rows[j-2]
		local r1=rows[j-1]
		local r_out=rows[j]
		for i=1,n do
			local w=r1[i]
			local e=r1[i+1]
			if i==n then e=r1[1] end
			if j%2==1 then
				if i==1 then
					w=r1[n]
				else
					w=r1[i-1]
				end
				e=r1[i]
			end
			r_out[i]=(w*e-1)/r0[i]
		end
	end
	print("FRIEZE:::")
	for i,v in ipairs(rows) do

		local s="."..i..">>"
		if i%2==1 then
			s=s.." "
		end
		for i,v in ipairs(v) do
			s=s.." "..v
		end
		print(s)
	end
	return rows
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Frieze patterns")
	local s=STATE.size
	draw_config(config)

	if imgui.Button("Clear image") then
		--clear_screen(true)
		for j=0,map_h-1 do
			for i=0,map_w-1 do
				img_buf:set(i,j,{0,0,0,0})
			end
		end
		write_img()
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	if imgui.Button("Gen") then
		print("=============",config.n,config.mutate)
		local n=config.n
		local r= triangulate_ngon(n,config.mutate)
		--local r={1,3,2,2,1,4,2}
		for i,v in ipairs(r) do
			print(v)
		end
		local pt=gen_frieze_pattern(r)
		for x=1,map_w-1 do
			for y=1,map_h-1 do
				local rx=(x%(n-1))+1
				local v1=pt[rx]
				local ry=(y%(#pt-1))+1
				local v=v1[ry]
				img_buf:set(x,y,{v,v,v})
			end
		end
		write_img()
	end
	imgui.End()
	draw()
	if need_save then
		save_img()
		need_save=false
	end
end