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


config=make_config({
	{"gamma",1,type="float",min=-5,max=5},
	{"diffusion",0,type="floatsci",min=0,max=1,power=2},
	{"diffusion_color",0,type="floatsci",min=0,max=1,power=2},
	{"avg_influence",0.5,type="float",min=0,max=1},
	{"value_grow",0.001,type="floatsci",min=0,max=1,power=10},
	{"value_shrink",0.002,type="floatsci",min=0,max=1,power=10},
},config)


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
	//vec3 value=log(col.xyz+vec3(1))/4;
	vec3 value=(col.xyz)/1;
	value=clamp(value,0,1);
	/*
	if(gamma_value<0)
		value=1-pow(1-value,-gamma_value);
	else
		value=pow(value,gamma_value);
	*/
	//float gamma_value=2;
	///*
	value.x=gain(value.x,gamma_value);
	value.y=gain(value.y,gamma_value);
	value.z=gain(value.z,gamma_value);
	//*/
	//value+=col.x*0.05;
	//col=palette(value,vec3(0.5),vec3(0.5),vec3(0.4,0.35,0.30),vec3(0.5,0.45,0.3));
	col=vec3(value);
	//col.r=1;
	color = vec4(col,1);
}
]==]

local update_shader=shaders.Make[==[
#version 330

#line 108
uniform sampler2D tex_main;
out vec4 color;
in vec3 pos;

uniform vec4 value_grow;
uniform vec4 value_shrink;

uniform float diffusion;
uniform float diffusion_color;
uniform float avg_influence;

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
vec4 laplace(vec2 pos) //with laplacian kernel (cnt -1,near .2,diag 0.05)
{
	vec4 ret=vec4(0);
	ret+=textureOffset(tex_main,pos,ivec2(-1,-1))*0.05;
	ret+=textureOffset(tex_main,pos,ivec2(-1,1))*0.05;
	ret+=textureOffset(tex_main,pos,ivec2(1,-1))*0.05;
	ret+=textureOffset(tex_main,pos,ivec2(1,1))*0.05;

	ret+=textureOffset(tex_main,pos,ivec2(0,-1))*.2;
	ret+=textureOffset(tex_main,pos,ivec2(-1,0))*.2;
	ret+=textureOffset(tex_main,pos,ivec2(1,0))*.2;
	ret+=textureOffset(tex_main,pos,ivec2(0,1))*.2;

	ret+=textureOffset(tex_main,pos,ivec2(0,0))*(-1);
	return ret;
}
vec4 rule(vec4 p,vec4 c,vec4 avg)
{
	//if p==1 and c=2,3 then 1
	//if p==0 and c==3 then 1
	//else 0
	//vec4 ret;
	/*
	ret+=mix(
		step(vec4(2.5),c)-step(vec4(3.5),c),
		step(vec4(1.5),c)-step(vec4(4.5),c)
		,clamp(p,0,1));
	*/
	vec4 ret=vec4(0);
	vec4 clp=clamp(p,0,1);
	vec4 clc=clamp(c,0,1);
#if 0
	vec4 rule_res=mix(
	step(vec4(2.5),c)-step(vec4(3.5),c),
	step(vec4(1.5),c)-step(vec4(4.5),c),
	clamp(p,0,1));
#elif 1
	float width=0.005;
	vec4 rule_res=mix(
		smoothstep(vec4(2.5-width),vec4(2.5+width),clc)-smoothstep(vec4(3.5-width),vec4(3.5+width),clc), //if dead
		smoothstep(vec4(1.5-width),vec4(1.5+width),clc)-smoothstep(vec4(4.5-width),vec4(4.5+width),clc), //if alive
		clp);
#else
	vec4 rule_res=cos(clp*784+124)*0.25+sin(clc*7777+777)*0.25+0.5;
#endif
	ret+=mix(-value_shrink,value_grow,rule_res)*(avg_influence*avg+(1-avg_influence));
	return ret;
}
vec4 avg_distant(vec2 pos)
{
	int d=1;
	vec4 ret=vec4(0);

	ret+=textureOffset(tex_main,pos,ivec2(0,-d));
	ret+=textureOffset(tex_main,pos,ivec2(-1,-d));
	ret+=textureOffset(tex_main,pos,ivec2(1,-d));

	ret+=textureOffset(tex_main,pos,ivec2(-d,-1));
	ret+=textureOffset(tex_main,pos,ivec2(-d,0));
	ret+=textureOffset(tex_main,pos,ivec2(-d,1));


	ret+=textureOffset(tex_main,pos,ivec2(d,-1));
	ret+=textureOffset(tex_main,pos,ivec2(d,0));
	ret+=textureOffset(tex_main,pos,ivec2(d,1));

	ret+=textureOffset(tex_main,pos,ivec2(-1,d));
	ret+=textureOffset(tex_main,pos,ivec2(0,d));
	ret+=textureOffset(tex_main,pos,ivec2(1,d));

	return ret/12.0;
}
vec4 mapping(vec4 around,vec4 distant)
{
	return around;//abs(around-distant)/(abs(around)+abs(distant));
}
void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 cnt=texture(tex_main,normed);
	vec4 count=count_around(normed);
	vec4 L=laplace(normed);
	vec4 AVG=avg_distant(normed);
	//vec4 ret=cnt+rule(log(cnt+1),mapping(log(count+1),log(cnt+1)),cnt/8.0)+L*diffusion;
	vec4 ret=cnt+rule(cnt,mapping(count,cnt),cnt/8.0)+L*diffusion;
	float avg=(ret.x+ret.y+ret.z+ret.w)/4.0;
	ret=ret*(1-diffusion_color)+vec4(avg)*diffusion_color;
	float d=length(pos.xy);
	if(length(pos.xy)<1)
		color=clamp(ret,0,1);
	else
	{
		//color=vec4(0);
		vec2 p2;
		float a=atan(pos.y,pos.x)+3.1459/4;
		p2=vec2(cos(a),sin(a))*(2-d);
		normed=(p2+vec2(1))/2;
		color=texture(tex_main,normed);
	}

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
		--local d=math.abs(dx)+math.abs(dy)
		local d=math.sqrt(dx*dx+dy*dy)
		local radius=w/5.5
		if d<radius then
		--if math.abs(dx)<radius and math.abs(dy)<radius then
			local p=io_buffer:get(x,y)
			local v=100000--math.random()
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

--reset_buffer()
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
	local g=config.value_grow
	local s=config.value_shrink
	update_shader:set("value_grow",g,g,g,g)
	update_shader:set("value_shrink",s,s*0.9,s*0.95,s)
	update_shader:set("diffusion",config.diffusion)
	update_shader:set("diffusion_color",config.diffusion_color)
	update_shader:draw_quad()
	__render_to_window()
	cell_buffer:advance()
end
function save_img()
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	img_buf=make_image_buffer(size[1],size[2])
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function draw(  )
	draw_shader:use()
	cell_buffer:get():use(0)
	draw_shader:set("tex_main",0)
	draw_shader:set("gamma_value",config.gamma)
	draw_shader:draw_quad()
	if need_save then
		need_save=nil
		save_img()
	end
end
function update(  )
	__no_redraw()
	__clear()
	rule_step()
	draw()
	imgui.Begin("CA")
	draw_config(config)
	if imgui.Button("Reset") then
		reset_buffer()
	end
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End("CA")
end