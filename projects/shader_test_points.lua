
require "common"
local size=STATE.size
img_buf=make_flt_buffer(80000,1)

local main_shader=shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;

void main(){
	color = vec4(0.1,0,0,1);
}
]]
tick=0
function update(  )
	__no_redraw()
	if math.fmod(tick,60)==0 then
		__clear()
	end
	for i=0,img_buf.w-1 do
		img_buf:set(i,0,{math.random()*2-1,math.random()*2-1,0,0})
	end
	

	--texture_fb:read() -- read framebuffer
	main_shader:use()
	main_shader:blend_add()
	main_shader:draw_points(img_buf.d,img_buf.w*img_buf.h)
	tick=tick+1
end