require "common"
--[==[
	Refs
	* https://en.wikipedia.org/wiki/Lloyd%27s_algorithm
	* https://en.wikipedia.org/wiki/Linde%E2%80%93Buzo%E2%80%93Gray_algorithm
	* https://en.wikipedia.org/wiki/Vector_quantization

	from wiki:
	It then repeatedly executes the following relaxation step:

	* The Voronoi diagram of the k sites is computed.
	* Each cell of the Voronoi diagram is integrated, and the centroid is computed.
	* Each site is then moved to the centroid of its Voronoi cell.

	when computing centroid have some weight function w(x,y) then result is non-equal distribution
]==]

local map_w=256
local map_h=256
local size=STATE.size

centers=centers or {}
local tree
function randomize_centers(  )
	local max_count=100
	centers={}
	for i=1,max_count do
		centers[i]={math.random()*map_w,math.random()*map_h}
	end
end
function recompute_tree(  )
	tree=kd_tree.Make(2)
	for i,v in ipairs(centers) do
		tree:add(v)
	end
end
function weight( x,y )
	--return x*x+y*y
	x=x*10
	y=y*10
	return x*x*x*x-y*y*y*y
end

function add_value(tbl, id,x,y,w )
	if tbl[id]==nil then
		tbl[id]={x*w,y*w,w}
	else
		local vold=tbl[id]
		tbl[id]={x*w+vold[1],y*w+vold[2],vold[3]+w}
	end
end
function compute_centroids()
	if tree==nil then recompute_tree() end
	local values={}

	for x=0,map_w-1 do
		for y=0,map_h-1 do
			local hits=tree:knn(1,{x,y})
			if #hits>0 then
				local id=hits[1][1]+1
				local w=weight((x-map_w/2)/map_w,(y-map_h/2)/map_h)
				add_value(values,id,x,y,w)
			end
		end
	end

	for i,v in ipairs(centers) do
		if values[i] then
			centers[i][1]=values[i][1]/values[i][3]
			centers[i][2]=values[i][2]/values[i][3]
		end
	end
	update_grid()
end

grid=grid or make_float_buffer(map_w,map_h)

function init_grid(  )
    for x=0,map_w-1 do
        for y=0,map_h-1 do
            grid:set(x,y,0)
        end
    end
end
init_grid()


function update_grid(  )
	recompute_tree()
	for x=0,map_w-1 do
		for y=0,map_h-1 do
			local hits=tree:knn(1,{x,y})
			if #hits>0 then
				grid:set(x,y,hits[1][1]/#centers)
			end
		end
	end
end

draw_field=init_draw_field(
[==[
#line __LINE__
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);
    //data.x*=data.x;
    color=vec4(palette(data.x,vec3(0.4),vec3(0.6),vec3(0.7,0.4,0.6),vec3(0.2,0.15,0.15)),1);
}
]==],
{
    uniforms={
    },
}
)

function draw(  )
    draw_field.update(grid)
    draw_field.draw()
end
function save_img(  )
    img_buf=img_buf or make_image_buffer(size[1],size[2])
    local config_serial=__get_source()
    img_buf:read_frame()
    img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
need_save=false
function update(  )

    draw()
    if need_save then
    	save_img()
    	need_save=false
    end

	imgui.Begin("LLoyds algorithm")
	if imgui.Button("Reset") then
		randomize_centers()
		update_grid()
	end
	--if imgui.Button("Step") then
		compute_centroids()
		update_grid()
	--end
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
    __no_redraw()
end