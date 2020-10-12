require 'common'
local tri_count=2
point_count=tri_count*3 --each tri is 3 points
tri_data=make_flt_buffer(point_count,1)
byte_count=point_count*4*4 --*4 floats *4bytes each
tri_buffer=tri_buffer or buffer_data.Make()

world_view_matrix=make_ident_matrix(4,4)
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

uniform mat4 world_view_matrix;
uniform mat4 projection_matrix;
uniform mat4 worldview_inverse_transpose_matrix;

layout(location = 0) in vec4 position;
out vec4 pos;

void main()
{
	gl_Position=position*world_view_matrix;
	pos=position*world_view_matrix;
}
]]
,
[[
#version 330
uniform mat4 world_view_matrix;
in vec4 pos;
out vec4 color;
float value_inside(float x,float a,float b)
{
	return step(a,x)-step(b,x);
}
void main()
{
	float v=0;
	for(int i=0;i<4;i++)
	for(int j=0;j<4;j++)
	{
		float xx=i/4.0-0.5;
		float yy=j/4.0-0.5;
		float g=world_view_matrix[i][j];
		v+=g*value_inside(pos.x,xx,xx+0.25)*value_inside(pos.y,yy,yy+0.25);
	}

	color=vec4(v,abs(pos.y+0.5),0*abs(pos.x+0.5),1);
}
]])
--print(world_view_matrix:tostring_full())
local t=0
function update(  )
	__clear()
    __no_redraw()

    --[[
    for i=0,3 do
    	for j=0,3 do
    		--[=[
    		if i==j then
    			world_view_matrix:set(i,j,1)
    		else
    			world_view_matrix:set(i,j,0)
    		end
    		]=]
    		world_view_matrix:set(i,j,math.random())
    	end
    end
    --]]
    t=t+1
    local c=math.cos(t*0.01)
    local s=math.sin(t*0.01)
    --[[ around Z
    world_view_matrix:set(0,0,c)
    world_view_matrix:set(1,0,-s)
    world_view_matrix:set(0,1,s)
    world_view_matrix:set(1,1,c)
    --]]
    world_view_matrix:set(1,1,c)
    world_view_matrix:set(2,1,-s)
    world_view_matrix:set(1,2,s)
    world_view_matrix:set(2,2,c)

	draw_shader:use()
	tri_buffer:use(0)
	draw_shader:set_m("world_view_matrix",world_view_matrix.d)
	if need_clear then
		__clear()
		need_clear=false
	end
	draw_shader:draw_triangles(0,point_count,4,0)
	__render_to_window()
	__unbind_buffer()
end