require "common"
local oversample=0.25

win_w=win_w or 0
win_h=win_h or 0

aspect_ratio=aspect_ratio or 1
function update_size()
	local trg_w=1024
	local trg_h=1024
	--this is a workaround because if everytime you save
	--  you do __set_window_size it starts sending mouse through windows. SPOOKY
	if win_w~=trg_w or win_h~=trg_h then
		win_w=trg_w
		win_h=trg_h
		aspect_ratio=win_w/win_h
		__set_window_size(win_w,win_h)
	end
end
update_size()
local size=STATE.size

function init_buffers(  )
	local ww=size[1]*oversample
	local hh=size[2]*oversample

	img_buf=img_buf or make_image_buffer(size[1],size[2]) --for saving png
	cell_buffer=cell_buffer or multi_texture(ww,hh,2,FLTA_PIX)
	diffusion_buffer=diffusion_buffer or multi_texture(ww,hh,2,FLTA_PIX)
	io_buffer=io_buffer or make_flt_buffer(ww,hh)
end
init_buffers()

function resize( w,h )
	local ww=w*oversample
	local hh=h*oversample
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	cell_buffer:update_size(ww,hh)
	diffusion_buffer:update_size(ww,hh)
	io_buffer=make_flt_buffer(ww,hh);
end

local draw_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;


uniform sampler2D tex_main;
uniform float gamma_value;

vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	normed.y=1-normed.y;

	vec3 col=texture(tex_main,normed).xyz;
	//col*=(1-col.b*5);
	//col*=clamp(col.g*10,0.3,1);
	//float value=abs(current_age/255-col.z);//col.y;
	//vec3 value=log(col.xyz+vec3(1))/14;
	//value=clamp(value,0,1);
	/*
	if(gamma_value<0)
		value=1-pow(1-value,-gamma_value);
	else
		value=pow(value,gamma_value);
	*/
	/*
	value.x=gain(value.x,gamma_value);
	value.y=gain(value.y,gamma_value);
	value.z=gain(value.z,gamma_value);
	*/
	//value+=col.x*0.05;
	//col=palette(value,vec3(0.5),vec3(0.5),vec3(0.4,0.35,0.30),vec3(0.5,0.45,0.3));
	//col=vec3(value);
	//col.r=1;
	color = vec4(col,1);
}
]==]

local update_shader=shaders.Make[==[
#version 330

uniform sampler2D tex_main;
out vec4 color;
in vec3 pos;

uniform vec4 value_grow;
uniform vec4 value_shrink;

vec4 count_around(vec2 pos)
{
	vec4 ret=vec4(0);
	ret+=textureOffset(tex_main,pos,ivec2(-1,-1));
	ret+=textureOffset(tex_main,pos,ivec2(-1,1));
	ret+=textureOffset(tex_main,pos,ivec2(1,-1));
	ret+=textureOffset(tex_main,pos,ivec2(1,1));

	ret+=textureOffset(tex_main,pos,ivec2(0,-1));
	ret+=textureOffset(tex_main,pos,ivec2(-1,0));
	ret+=textureOffset(tex_main,pos,ivec2(1,0));
	ret+=textureOffset(tex_main,pos,ivec2(0,1));

	//ret+=textureOffset(tex_main,pos,ivec2(0,0))*(-1);
	return ret;
}

vec4 rule(vec4 p,vec4 c)
{
	//if p==1 and c=2,3 then 1
	//if p==0 and c==3 then 1
	//else 0
	//vec4 ret;
	//ret+=mix(step(vec4(2.5),c)-step(vec4(3.5),c),step(vec4(1.5),c)-step(vec4(3.5),c),p);
	vec4 ret=p;
	float width=0.01;
	vec4 rule_res=mix(
		smoothstep(vec4(2.5-width),vec4(2.5+width),c)-smoothstep(vec4(3.5-width),vec4(3.5+width),c), //if dead
		smoothstep(vec4(1.5-width),vec4(1.5+width),c)-smoothstep(vec4(5.5-width),vec4(5.5+width),c), //if alive
		clamp(p,0,1));
	ret+=mix(-value_shrink,value_grow,rule_res);
	return ret;
}

void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 cnt=texture(tex_main,normed);
	vec4 count=count_around(normed);
	float diffusion=0;
	float color_diffusion=0.001;
	vec4 ret=rule(cnt,count)+((count+cnt)/9)*diffusion;
	float avg=(ret.x+ret.y+ret.z+ret.w)/4.0;
	ret=ret*(1-color_diffusion)+vec4(avg)*color_diffusion;
	color=ret;
}
]==]

function reset_buffer(  )
	local w=io_buffer.w
	local h=io_buffer.h
	for x=0,w-1 do
	for y=0,h-1 do
		-- [[
		local dx=x-w/2
		local dy=y-h/2
		local d=math.sqrt(dx*dx+dy*dy)
		local radius=w/5.5
		if d<radius and math.random()>0.6 then
		--if math.abs(dx)<radius and math.abs(dy)<radius then
			local p=io_buffer:get(x,y)
			local v=math.random()
			p.r=v--MAX_VALUE
			p.g=v--MAX_VALUE
			p.b=v--MAX_VALUE
		else
			io_buffer:set(x,y,{0,0,0,0})
		end
		--]]
	end
	end
	local t=cell_buffer:get()
	t:use(0)
	io_buffer:write_texture(t)
end

reset_buffer()
function rule_step()

	update_shader:use()
	update_shader:blend_disable();
	cell_buffer:get():use(0)
	update_shader:set("tex_main",0)

	local next_buff=cell_buffer:get_next()
	local do_clamp=0
	next_buff:use(1,1,do_clamp)
	if not next_buff:render_to(cell_buffer.w,cell_buffer.h) then
		error("failed to set framebuffer up")
	end
	local g=0.5
	local s=0.01
	update_shader:set("value_grow",g,g+0.01,g+0.02,g+0.03)
	update_shader:set("value_shrink",s,s,s,s-0.001)
	update_shader:draw_quad()
	__render_to_window()
	cell_buffer:advance()
end
function draw(  )
	draw_shader:use()
	cell_buffer:get():use(0)
	draw_shader:set("tex_main",0)
	draw_shader:draw_quad()
end
function update(  )
	__no_redraw()
	__clear()
	rule_step()
	draw()
end