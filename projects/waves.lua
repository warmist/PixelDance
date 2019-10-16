require "common"
--basically implementing: http://hplgit.github.io/num-methods-for-PDEs/doc/pub/wave/html/._wave006.html

local size_mult=1
local oversample=1
local win_w
local win_h
local aspect_ratio
function update_size(  )
	win_w=1280*size_mult
	win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
--update_size()

local size=STATE.size



img_buf=make_image_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	print("new size:",w,h)
end

textures=textures or {}
function make_textures()
	if #textures==0 or textures[1].w~=size[1]*oversample or textures[1].h~=size[2]*oversample then
		--print("making tex")
		for i=1,3 do
			local t={t=textures:Make(),w=size[1]*oversample,h=size[2]*oversample}
			t.t:use(0,1)
			t.t:set(size[1]*oversample,size[2]*oversample,2)
			textures[i]=t
		end
	end
end
make_textures()

function make_io_buffer(  )
	if io_buffer==nil or io_buffer.w~=size[1]*oversample or io_buffer.h~=size[2]*oversample then
		io_buffer=make_float_buffer(size[1]*oversample,size[2]*oversample)
	end
end

make_io_buffer()

config=make_config({
	{"dt",1,type="float",min=0.001,max=2},
	{"freq",1000,type="float",min=1,max=4000},
	{"decay",1,type="float",min=0.99,max=1},
	{"draw",true,type="boolean"},
	{"size_mult",true,type="boolean"},
},config)


draw_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float line_w;
uniform vec2 limits;
uniform vec4 in_col;
float f(float v)
{
	return clamp(pow(v,1),0,1);
}
void main(){

	vec2 normed=(pos.xy+vec2(1,1))/2;
	float lv=f(abs(texture(values,normed).x));
	color=vec4(lv,lv,lv,1);
	/*if (lv>0)
		color=vec4(f(lv),0,0,1);
	else
		color=vec4(0,0,f(-lv),1);*/
}
]==]

solver_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;
uniform sampler2D values_cur;
uniform sampler2D values_old;
uniform float init;
uniform float dt;
uniform float c_const;
uniform float time;
uniform float decay;
uniform float freq;
uniform vec2 tex_size;
//uniform vec2 dpos;

#define M_PI 3.14159265358979323846264338327950288

#define DX(dx,dy) textureOffset(values_cur,normed,ivec2(dx,dy)).x
float func(vec2 pos)
{
	//if(length(pos)<0.0025 && time<100)
	//	return cos(time/freq)+cos(time/(2*freq/3))+cos(time/(3*freq/2));
	return 0;
	//return 0.1;//0.0001*sin(time/1000)/(1+length(pos));
}
float func_init_speed(vec2 pos)
{
	float p=length(pos);
	float w=M_PI/0.5;
	float m1=3;
	float m2=7;

	//float d=exp(-dot(pos,pos)/0.005);
	//return exp(-dot(pos,pos)/0.00005);

	//return (sin(p*w*m1)+sin(p*w*m2))*0.05;
	//if(max(abs(pos.x),abs(pos.y))<0.002)
	//	return 1;
	return 0;
}
float func_init(vec2 pos)
{
	//float theta=atan(pos.y,pos.x);
	//float r=length(pos);

	float w=M_PI/0.5;
	float m1=5;
	float m2=7;
	float a=1;
	float b=-1;
	//float d=exp(-dot(pos,pos)/0.005);
	//return exp(-dot(pos,pos)/0.00005);
	//solution from https://thelig.ht/chladni/
	return (a*sin(pos.x*w*m1)*sin(pos.y*w*m2)+
			b*sin(pos.x*w*m2)*sin(pos.y*w*m1))*0.0005;
	//if(max(abs(pos.x),abs(pos.y))<0.002)
	//	return 1;
	return 0;
	return 0; //TODO
}
#define IDX(dx,dy) func_init(pos+vec2(dx,dy)*dtex)
float calc_new_value(vec2 pos)
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float dcsqr=dt*dt*c_const*c_const;
	float dcsqrx=dcsqr;
	float dcsqry=dcsqr;

	float ret=-texture(values_old,normed).x+
		2*DX(0,0)+
		dcsqrx*(DX(1,0)-2*DX(0,0)+DX(-1,0))+
		dcsqry*(DX(0,1)-2*DX(0,0)+DX(0,-1))+
		dt*dt*func(pos);

	return ret*decay;
}
float calc_init_value(vec2 pos)
{
	vec2 normed=(pos.xy+vec2(1,1))/2;

	vec2 dtex=1/tex_size;
	//float dcsqr=dt*dt*c_const*c_const;
	float dcsqrx=dt*dt*c_const*c_const/(dtex.x*dtex.x);
	float dcsqry=dt*dt*c_const*c_const/(dtex.y*dtex.y);

	float ret=
		2*IDX(0,0)+
		dt*func_init_speed(pos)+
		0.5*dcsqrx*(IDX(1,0)-2*IDX(0,0)+IDX(-1,0))+
		0.5*dcsqry*(IDX(0,1)-2*IDX(0,0)+IDX(0,-1))+
		dt*dt*func(pos);

	return ret;
}
float boundary_condition(vec2 pos)
{
	return 0;
}
//rectangle
//#define BOUNDARY_SHAPE max(abs(pos.x),abs(pos.y))
//circle
#define BOUNDARY_SHAPE length(pos.xy)
void main(){
	float v=0;
	float max_d=.5;
	float w=0.01;
	if(BOUNDARY_SHAPE<max_d)
	{
		if(init==1)
			v=calc_init_value(pos.xy);
		else
			v=calc_new_value(pos.xy);
	}
	else if(BOUNDARY_SHAPE>max_d+w)
	{
		v=boundary_condition(pos.xy);
	}
	color=vec4(clamp(v,-100,100),0,0,1);
}
]==]


function auto_clear(  )
	local pos_start=0
	local pos_end=0
	local pos_anim=0;
	for i,v in ipairs(config) do
		if v[1]=="size_mult" then
			pos_start=i
		end
		if v[1]=="size_mult" then
			pos_end=i
		end
	end

	for i=pos_start,pos_end do
		if config[i].changing then
			need_clear=true
			break
		end
	end
end
local need_save
function gui()
	imgui.Begin("Waviness")
	draw_config(config)
	if config.size_mult then
		size_mult=1
	else
		size_mult=0.5
	end
	update_size()
	local s=STATE.size
	if imgui.Button("Reset") then
		current_time=0
		solver_iteration=0
	end
--[[
	if imgui.Button("Clear image") then
		clear_buffers()
	end
]]
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.End()
end

function update( )
	gui()
	update_real()
end
solver_iteration=solver_iteration or 0
current_time=current_time or 0
function waves_solve(  )

	solver_iteration=solver_iteration+1
	if solver_iteration>2 then solver_iteration=0 end

	make_textures()

	solver_shader:use()
	local id_old=solver_iteration % 3 +1
	local id_cur=(solver_iteration+1) % 3 +1
	local id_next=(solver_iteration+2) % 3 +1
	textures[id_old].t:use(0)
	textures[id_cur].t:use(1)
	solver_shader:set_i("values_old",0)
	solver_shader:set_i("values_cur",1)
	if current_time==0 then
		solver_shader:set("init",1);
	else
		solver_shader:set("init",0);
	end
	solver_shader:set("dt",config.dt);
	solver_shader:set("c_const",0.1);
	solver_shader:set("time",current_time);
	solver_shader:set("decay",config.decay);
	solver_shader:set("freq",config.freq)
	local trg_tex=textures[id_next];
	solver_shader:set("tex_size",trg_tex.w,trg_tex.h)
	if not trg_tex.t:render_to(trg_tex.w,trg_tex.h) then
		error("failed to set framebuffer up")
	end
	solver_shader:draw_quad()
	__render_to_window()



	current_time=current_time+config.dt
end

function save_img(  )
	--make_image_buffer()
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	config_serial=config_serial..string.format("str_x=%q\n",str_x)
	config_serial=config_serial..string.format("str_y=%q\n",str_y)
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function draw_texture(  )
	local id_next=(solver_iteration+2) % 3 +1
	local trg_tex=textures[id_next];
	draw_shader:use()
	trg_tex.t:use(0)
	draw_shader:set_i("values",0)
	--draw_shader:set("in_col",config.color[1],config.color[2],config.color[3],config.color[4])
	draw_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end

function update_real(  )
	__no_redraw()
	if animate then
		tick=tick or 0
		tick=tick+1

	else
		__clear()
		if config.draw then
			draw_texture()
		end
	end
	auto_clear()
	waves_solve()
	local scale=config.scale
	--[[
	local c,x,y= is_mouse_down()
	if c then
		--mouse to screen
		x=(x/size[1]-0.5)*2
		y=(-y/size[2]+0.5)*2
		--screen to world
		x=(x-cx)/scale
		y=(y-cy)/(scale*aspect_ratio)

		--now set that world pos so that screen center is on it
		config.cx=(-x)*scale
		config.cy=(-y)*(scale*aspect_ratio)
		need_clear=true
	end
	if __mouse.wheel~=0 then
		local pfact=math.exp(__mouse.wheel/10)
		config.scale=config.scale*pfact
		config.cx=config.cx*pfact
		config.cy=config.cy*pfact
		need_clear=true
	end
	]]
end
