require "common"

local size=STATE.size
local max_size=math.min(size[1],size[2])/2
img_buf=img_buf or make_image_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(size[1],size[2])
end

config=make_config({

	},config)

function new_network(  )
	network={nodes={},edges={}}
end

if network==nil then
	new_network()
end

function draw_nodes( )
	-- body
end
function draw_edges(  )
	-- body
end


function update(  )

	imgui.Begin("Graphs N Crafts")
	draw_config(config)
	if imgui.Button("Clear") then
		img_buf:clear()
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