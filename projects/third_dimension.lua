require 'common'
local tri_count=2
point_count=tri_count*3 --each tri is 3 points
tri_data=make_flt_buffer(point_count,1)
byte_count=point_count*4*4 --*4 floats *4bytes each
tri_buffer=tri_buffer or buffer_data.Make()
function gen_tris(  )
	tri_data:set(0,0,{-0.5,-0.5,0,1})
	tri_data:set(1,0,{-0.5,0.5,0,1})
	tri_data:set(2,0,{0.5,0.5,0,1})

	tri_data:set(3,0,{0.5,0.5,0,1})
	tri_data:set(4,0,{0.5,-0.5,0,1})
	tri_data:set(5,0,{-0.5,-0.5,0,1})
	tri_buffer:use()
	tri_buffer:set(tri_data.d,byte_count)
	__unbind_buffer()
end
gen_tris()
draw_shader=shaders.Make(
[[
#version 330

layout(location = 0) in vec4 position;
out vec4 pos;

void main()
{
	gl_Position=position;
	pos=position;
}
]]
,
[[
#version 330
in vec4 pos;
out vec4 color;
void main()
{
	color=vec4(1,abs(pos.y+0.5),abs(pos.x+0.5),1);
}
]])

function update(  )
	__clear()
    __no_redraw()

	draw_shader:use()
	tri_buffer:use(0)
	if need_clear then
		__clear()
		need_clear=false
	end
	draw_shader:draw_triangles(0,point_count,4,0)
	__render_to_window()
	__unbind_buffer()
end