require 'common'
local tri_count=1
tri_data=make_flt_buffer(tri_count*3,1)
tri_buffer=buffer_data.Make()
function gen_tris(  )
	tri_buffer:use()
	tri_data:set(0,0,{0,0,0,1})
	tri_data:set(1,0,{0,1,0,1})
	tri_data:set(2,0,{1,1,0,1})
	tri_buffer:set(tri_data.d,tri_count*3*4)
	__unbind_buffer()
end
gen_tris()
draw_shader=shaders.Make(
[[
#version 330

layout(location = 0) in vec4 position;
out vec4 pos_out;

void main()
{
	pos_out=position;
}
]]
,
[[
#version 330
in vec4 pos;
out vec4 color;
void main()
{
	color=vec4(1,0,0,1);
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
	draw_shader:draw_points(0,tri_count,4)
	__render_to_window()
	__unbind_buffer()
end