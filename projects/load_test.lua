
require "common"
local size=STATE.size

local ffi = require "ffi"
ffi.cdef[[
void free_image(char* data);
char* png_load(const char* path,int* w,int* h,int* comp,int need_comp);
]]

local main_shader=shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;


void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	color = vec4(0.2,0,0,1);
}
]]
local con_tex=textures.Make()

function update(  )
	__no_redraw()
	__clear()
	main_shader:use()
	main_shader:draw_quad()
end