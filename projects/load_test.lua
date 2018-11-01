
require "common"
local size=STATE.size
local knock_buf=load_png("knock.png")
local main_shader=shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 c=texture(tex_main,normed*vec2(1,-1));
	float v=length(c)/3;
	color = vec4(v,v,v,1);//vec4(0.2,0,0,1);
}
]]
local con_tex=textures.Make()
function update(  )
	__no_redraw()
	__clear()
	main_shader:use()
	con_tex:use(0)
	knock_buf:write_texture(con_tex)
	main_shader:set_i("tex_main",0)
	main_shader:draw_quad()
end