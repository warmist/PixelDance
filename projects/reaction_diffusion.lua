require "common"
--[[
	TODO:
		* add oversample
]]
config=make_config({
	{"pause",false,type="boolean"},
	{"clamp_edges",false,type="boolean"},
	{"diff_a",1.0,type="float",min=0,max=1},
	{"diff_b",0.5,type="float",min=0,max=1},
	{"diff_c",0.25,type="float",min=0,max=1},
	{"diff_d",0.125,type="float",min=0,max=1},
	{"kill",0.062,type="float",min=0,max=1},
	{"feed",0.055,type="float",min=0,max=1},
	{"gamma",1,type="float",min=0.01,max=5},
	{"gain",1,type="float",min=-5,max=5},
	{"draw_comp",0,type="int",min=0,max=3},
},config)

local size=STATE.size
img_buf=img_buf or make_image_buffer(size[1],size[2])
react_buffer=react_buffer or multi_texture(size[1],size[2],2,1)
io_buffer=io_buffer or make_flt_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	react_buffer:update_size(w,h)
	io_buffer=make_flt_buffer(w,h);
end

function count_lines( s )
	local n=0
	for i in s:gmatch("\n") do n=n+1 end
	return n
end

function shader_make( s_in )
	local sl=count_lines(s_in)
	s="#version 330\n#line "..(debug.getinfo(2, 'l').currentline-sl).."\n"
	s=s..s_in
	return shaders.Make(s)
end


local react_diffuse=shader_make[==[
out vec4 color;
in vec3 pos;

uniform vec4 diffusion;
uniform vec2 kill_feed;

uniform sampler2D tex_main;
uniform float dt;
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
//#define MAPPING
vec2 gray_scott(vec4 cnt,vec2 normed)
{
	/*
		X+2Y=3Y
	*/
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	kill_rate=mix(0.045,0.07,normed.x);
	feed_rate=mix(0.01,.1,normed.y);
#endif
	float abb=cnt.x*cnt.y*cnt.y;
	return vec2(-abb,abb)+vec2(feed_rate*(1-cnt.x),-(kill_rate+feed_rate)*cnt.y);
}
vec3 ruijgrok(vec4 cnt,vec2 normed)
{
	/*
		X+Y=>2X
		Y+Z=>2Y
		Z+X=>2Z

		X+2Y=>3Y
		Y+2Z=>3Z
		Z+2X=>3X
	*/
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	kill_rate=mix(0.06,0.08,normed.x);
	feed_rate=mix(0.01,.0175,normed.y);
#endif
	float pos_x1=cnt.y*cnt.x;
	float pos_x2=cnt.z*cnt.x*cnt.x;

	float pos_y1=cnt.z*cnt.y;
	float pos_y2=cnt.x*cnt.y*cnt.y;

	float pos_z1=cnt.z*cnt.x;
	float pos_z2=cnt.z*cnt.y*cnt.y;

	float neg_x1=pos_y2;
	float neg_x2=pos_z1;

	float neg_y1=pos_x1;
	float neg_y2=pos_z2;

	float neg_z1=pos_x2;
	float neg_z2=pos_y1;
	return vec3(
		pos_x1+pos_x2-neg_x1-neg_x2+feed_rate*(1-cnt.x),
		pos_y1+pos_y2-neg_y1-neg_y2-(kill_rate+feed_rate)*cnt.y,
		pos_z1+pos_z2-neg_z1-neg_z2);
}
vec3 two_reacts(vec4 cnt,vec2 normed)
{
	/*
		X+2Y=3Y
		Z+X=2Z

	*/
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	vec2 c=vec2(0.5,0.5);
	vec2 cs=vec2(0.5,0.5);
	kill_rate=mix(c.x-cs.x,c.x+cs.x,normed.x);
	feed_rate=mix(c.y-cs.y,c.y+cs.y,normed.y);
#endif
	float pos_y1=cnt.x*cnt.y*cnt.y;
	float pos_z1=cnt.z*cnt.x;

	float neg_x1=pos_y1;
	float neg_x2=pos_z1;

	return vec3(
		-neg_x2-neg_x1+feed_rate*(1-cnt.x),
		pos_y1,
		pos_z1-(kill_rate+feed_rate)*cnt.z);
}
vec4 thingy_formulas(vec4 c,vec2 normed)
{
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	vec2 kc=vec2(0.05,0.1);
	vec2 kcs=vec2(0.05,0.1);
	kill_rate=mix(kc.x-kcs.x,kc.x+kcs.x,normed.x);
	feed_rate=mix(kc.y-kcs.y,kc.y+kcs.y,normed.y);
#endif
	vec4 values=vec4(c.x*c.w*c.w,c.y*c.z,c.z*c.w*c.w,c.w*c.x);

	return vec4(
		-values.x-values.z,
		values.y+values.w,
		-values.z-values.w,
		+values.x+values.y)+
		vec4(feed_rate*(1-c.x),-(kill_rate+feed_rate)*c.y,feed_rate*(1-c.z),-(kill_rate+feed_rate)*c.w);
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;

	vec4 L=laplace(normed);
	vec4 cnt=texture(tex_main,normed);
	vec4 ret=cnt+(diffusion*L
		//+vec4(gray_scott(cnt,normed),0,0)
		//+vec4(ruijgrok(cnt,normed),0)
		//+vec4(two_reacts(cnt,normed),0)
		+thingy_formulas(cnt,normed)
		)*dt;

	ret=clamp(ret,0,1);

	color=ret;
}
]==]
local draw_shader = shader_make[==[
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;

uniform float v_gamma;
uniform float v_gain;
uniform int draw_comp;
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}

void main(){

	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 cnt=texture(tex_main,normed);

	float lv=cnt.x;
	if(draw_comp==1)
		lv=cnt.y;
	else if(draw_comp==2)
		lv=cnt.z;
	else if(draw_comp==3)
		lv=cnt.w;

	lv=gain(lv,v_gain);
	lv=pow(lv,v_gamma);

	color=vec4(lv,lv,lv,1);
	//color=vec4(palette(lv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1,1.0,2),vec3(0.75,0.5,0.5)),1);
}
]==]
function sim_tick(  )
	local dt=0.5
	react_diffuse:use()
	react_diffuse:blend_default()
	react_diffuse:set("diffusion",config.diff_a,config.diff_b,config.diff_c,config.diff_d)
	react_diffuse:set("kill_feed",config.kill,config.feed)
	react_diffuse:set("dt",dt)

	local cur_buff=react_buffer:get()
	local do_clamp
	if config.clamp_edges then
		do_clamp=1
	else
		do_clamp=0
	end
	cur_buff:use(0,1,do_clamp)
	react_diffuse:set_i("tex_main",0)

	local next_buff=react_buffer:get_next()
	next_buff:use(1,1,do_clamp)
	if not next_buff:render_to(react_buffer.w,react_buffer.h) then
		error("failed to set framebuffer up")
	end

	react_diffuse:draw_quad()

	__render_to_window()
	react_buffer:advance()
end
function reset_buffers(rnd  )
	local b=io_buffer
	for x=0,b.w-1 do
		for y=0,b.h-1 do
			if rnd then
				b:set(x,y,{math.random(),math.random(),math.random(),math.random()})
			else
				b:set(x,y,{1,0,0,0})
			end
		end
	end
	-- [[
	if not rnd then
		local cx=math.floor(b.w/2)
		local cy=math.floor(b.h/2)
		local s=5

		for x=cx-s,cx+s do
			for y=cy-s,cy+s do
				b:set(x,y,{0.5,.25,0.5,0.5})
			end
		end
	end
	--]]
	local buf=react_buffer:get()
	buf:use(0)
	b:write_texture(buf)
	react_buffer:advance()

	buf=react_buffer:get()
	buf:use(0)
	b:write_texture(buf)
end
function gui(  )
	imgui.Begin("GrayScott")
	draw_config(config)
	if imgui.Button("Reset") then
		reset_buffers()
	end
	imgui.SameLine()
	if imgui.Button("ResetRand") then
		reset_buffers(true)
	end
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.End()
end
function save_img( id )
	--make_image_buffer()
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	img_buf:read_frame()
	if id then
		img_buf:save(string.format("video/saved (%d).png",id),config_serial)
	else
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	end
end
function draw_texture(  )
	draw_shader:use()
	local buf=react_buffer:get()
	buf:use(0,0,0)
	draw_shader:set_i('tex_main',0)
	draw_shader:set("v_gamma",config.gamma)
	draw_shader:set("v_gain",config.gain)
	draw_shader:set_i("draw_comp",config.draw_comp)
	draw_shader:draw_quad()
	if need_save or id then
		save_img(id)
		need_save=nil
	end
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function update( )
	__no_redraw()
	__clear()
	__render_to_window()
	gui()
	if config.pause then
		draw_texture()
	else
		sim_tick()
		draw_texture()
	end
	local c,x,y= is_mouse_down()
	if c then
		local scale_x=0.05*2
		local scale_y=0.1*2
		local xx=(x/size[1])*scale_x
		local yy=(1-y/size[2])*scale_y
		print(xx,yy)
		config.kill_rate=xx
		config.feed_rate=yy
	end
end