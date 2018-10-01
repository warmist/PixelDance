

local main_shader=shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;
uniform vec2 resolution;

void main(){
	float v=(sin(pos.x*resolution.x/4)+1)/2;
	float v2=(sin(pos.y*resolution.y/4)+1)/2;
	color = vec4(v,v2,0,1);
}
]]

function update(  )
	main_shader:use()
	main_shader:set("resolution",STATE.size[1],STATE.size[2])
end