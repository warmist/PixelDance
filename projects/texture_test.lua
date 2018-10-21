
require "common"
local size=STATE.size
local console=console or make_image_buffer(50,50)
if cp437_tex==nil then
	local txt=STATE.cp437
	cp437_tex = textures.Make()
	cp437_tex:use(0)
	cp437_tex:set(txt.data,txt.w,txt.h)
end

local main_shader=shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;

uniform sampler2D font;
uniform sampler2D console;

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	normed.y*=-1;

	vec4 c=texture(console,normed);
	c.a*=256;

	vec2 char_coord=floor(vec2(mod(c.a,16.0),c.a/16.0));
	//char_coord=vec2(floor(normed.x*16),floor(normed.y*16));

	vec2 fr=mod(normed,1/50.0);
	vec4 t=texture(font,char_coord/16+fr*(50/16));

	if(t.r==1 && t.b==1 && t.g==0)
		t.a=0;

	color = vec4(c.r,c.g,c.b,t.a);
}
]]
local con_tex=textures.Make()

function update(  )
	__no_redraw()
	__clear()
	for i=1,5 do
		console:set(math.random(0,console.w-1),math.random(0,console.h-1),{math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255)})
	end
	main_shader:use()
	cp437_tex:use(0)
	con_tex:use(1)
	console:write_texture(con_tex)
	main_shader:set_i("font",0)
	main_shader:set_i("console",1)
	main_shader:draw_quad()
end