--basically waves.lua but there is chance for waves to collapse into a particle
--also limitation maybe only if it can "stick"
--also maybe DLA but instead of diffusion waves push particles around
--[[
	TODO:
		* refill particles everyonce a while
		* https://en.wikipedia.org/wiki/Maximal_entropy_random_walk
		* quantum wave
		* prefer sticking to already existing atoms
]]
require "common"
-- see waves.lua

local size_mult
local oversample=1
local oversample_waves=1
local win_w, win_h
local map_w, map_h
local wave_map_w, wave_map_h
local aspect_ratio

config=make_config({
	{"pause",false,type="boolean"},
	{"dt",1,type="float",min=0.001,max=2},
	{"freq",0.5,type="float",min=0,max=1},
	{"freq2",0.5,type="float",min=0,max=1},
	{"decay",0,type="floatsci",min=0,max=0.01,power=10},
	{"n",1,type="int",min=0,max=15},
	{"m",1,type="int",min=0,max=15},
	{"a",1,type="float",min=-1,max=1},
	{"b",1,type="float",min=-1,max=1},
	{"color",{124/255,50/255,30/255},type="color"},
	{"draw",true,type="boolean"},
	{"draw_moving",true,type="boolean"},
	{"animate",false,type="boolean"},
	{"animate_simple",false,type="boolean"},
	{"size_mult",true,type="boolean"},
	{"particle_step",0.1,type="float",min=0.01,max=1},
},config)

function update_size(  )
	win_w=1024
	win_h=1024--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
	map_w=math.floor(win_w*oversample)
	map_h=math.floor(win_h*oversample)
	wave_map_w=math.floor(win_w*oversample_waves)
	wave_map_h=math.floor(win_h*oversample_waves)
end
update_size()
--------------------- buffer setup / size update

local size=STATE.size
function make_textures()
	--three buffers for wave simulation stuff
	texture_buffers=texture_buffers or {}
	if #texture_buffers==0 or
		texture_buffers[1].w~=wave_map_w or
		texture_buffers[1].h~=wave_map_h then

		texture_buffers.old=1
		texture_buffers.cur=2
		texture_buffers.next=3
		--print("making tex")
		for i=1,3 do
			local t={t=textures:Make(),w=wave_map_w,h=wave_map_h}
			t.t:use(0,1)
			t.t:set(wave_map_w,wave_map_h,2)
			texture_buffers[i]=t
		end
		texture_buffers.advance=function( t )
			local l=t.old
			t.old=t.cur
			t.cur=t.next
			t.next=t.old
		end
		texture_buffers.get_old=function (t)
			return t[t.old]
		end
		texture_buffers.get_cur=function ( t )
			return t[t.cur]
		end
		texture_buffers.get_next=function ( t )
			return t[t.next]
		end
	end
	--particles that are stuck in there... wihtout a way to move :<
	texture_particles=texture_particles or {}
	if #texture_particles==0 or
		texture_particles[1].w~=map_w or
		texture_particles[1].h~=map_h then

		texture_particles.cur=1
		texture_particles.next=2
		--print("making tex")
		for i=1,2 do
			local t={t=textures:Make(),w=map_w,h=map_h}
			t.t:use(0,1)
			t.t:set(map_w,map_h,2)
			texture_particles[i]=t
		end
		texture_particles.advance=function( t )
			local l=t.cur
			t.cur=t.next
			t.next=l
		end
		texture_particles.get_cur=function (t)
			return t[t.cur]
		end
		texture_particles.get_next=function ( t )
			return t[t.next]
		end
	end
end
make_textures()
function make_io_buffer(  )
	if io_buffer==nil or io_buffer.w~=wave_map_w or io_buffer.h~=wave_map_h then
		io_buffer=make_float_buffer(wave_map_w,wave_map_h)
	end
end

make_io_buffer()
-----------------------------------------------------

current_time=current_time or 0

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

img_buf=make_image_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	print("new size:",w,h)
end

function fill_buffer(  )
	local t=texture_particles:get_cur().t
	t:use(0)
	io_buffer:read_texture(t)
	for i=0,win_w-1 do
    	for j=0,win_h-1 do
    		io_buffer:set(math.floor(i),math.floor(j),0)
    	end
    end
    io_buffer:write_texture(t)
end
function start_set_pixel(  )
	local t=texture_particles:get_cur().t
	t:use(0)
	io_buffer:read_texture(t)
end
function set_pixel( x,y )
	io_buffer:set(x,y,1)
end
function end_set_pixel(  )
	local t=texture_particles:get_cur().t
    io_buffer:write_texture(t)
end

--[===[ DOES NOT WORK
reduce_shader=shader_make[==[
out vec4 color;
in vec3 pos;
uniform sampler2D values;
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;

    float v = textureOffset(values,normed,ivec2(0,0)).r;
    v=abs(v);
    float test = textureOffset(values, normed,ivec2(0, 1)).r;
    test=abs(test);
    if(test < v)
            v = test;
    test = textureOffset(values, normed, ivec2(1, 0)).r;
    test=abs(test);
    if(test < v)
            v = test;
    test = textureOffset(values, normed, ivec2(1, 1)).r;
    test=abs(test);
    if(test < v)
            v = test;

    color = vec4(v,0,0,0);
}
]==]
--max: if(test>v) v=test;
--min: if(test<v) v=test;
--sum: v+=test;
--sumabs: v+=abs(test); (init: v=abs(v))
--avg: v+=test/4;
function reduce( txt_in ,w,h)
	local num=math.floor(math.log(w)/math.log(2))
	num=math.max(num,math.floor(math.log(h)/math.log(2)))

	--setup output texture
	red_buf=red_buf or multi_texture(math.floor(w/2),math.floor(h/2),2,2)
	red_buf:update_size(math.floor(w/2),math.floor(h/2))
	reduce_shader:use()
	reduce_shader:blend_default()
	for i=1,num do
		w=math.floor(w/2)
		h=math.floor(h/2)
	--init
		if i==1 then
			txt_in:use(0)
		else
			red_buf:get():use(0)
		end
		reduce_shader:set_i("values",0)
		--reduce_shader:set_i("rez",w,h)
		red_buf:get_next():use(1)
		if not red_buf:get_next():render_to(w,h) then
			error("failed to set framebuffer up")
		end
		reduce_shader:draw_quad()

	--flip output
		red_buf:advance()
	end
	--read_output
	__render_to_window()
	red_buf_out=red_buf_out or make_float_buffer(red_buf.w,red_buf.h)
	red_buf:get_prev():use(0)
	red_buf_out:read_texture(red_buf:get_prev())
	local value=red_buf_out:get(0,0)
	print(value)
	--restore state
	reduce_shader:blend_default()
	
	return value
end
]===]
simple_shader=shader_make[==[
out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float draw_moving;
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float lv=texture(values,normed).x;
	if(lv>0.5)
		color=vec4(lv,0,0,1);
	else if(lv>0 && draw_moving>=1)
		color=vec4(lv,lv,lv,1);
	else
		color=vec4(0);
}
]==]




add_shader=shader_make[==[
out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float mult;

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float lv=abs(texture(values,normed).x*mult);
	color=vec4(lv,lv,lv,1);
}
]==]
draw_waves_shader=shader_make[==[
out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float mult;
uniform float add;
uniform float v_gamma;
uniform float v_gain;
uniform vec3 mid_color;
#define M_PI 3.14159265358979323846264338327950288
float f(float v)
{
#if LOG_MODE
	return log(v+1);
#else
	return v;
#endif
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
//#define RG
void main(){

	vec2 normed=(pos.xy+vec2(1,1))/2;
#ifdef RG
	float lv=(texture(values,normed).x+add)*mult;
	if (lv>0)
		{
			lv=f(lv);
			lv=pow(lv,gamma);
			color=vec4(lv,0,0,1);
		}
	else
		{
			lv=f(-lv);
			lv=pow(lv,gamma);
			color=vec4(0,0,lv,1);
		}
#else
	float lv=abs(f(texture(values,normed).x+add)*mult);
	//float lv=f(abs(log(texture(values,normed).x+1)+add))*mult;
	//lv=pow(1-lv,gamma);
	lv=clamp(lv,0,1);
	lv=gain(lv,v_gain);
	lv=pow(lv,v_gamma);

	/* quantize
	float q=7;
	lv=clamp(floor(lv*q)/q,0,1);
	//*/
	//color=vec4(palette(lv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(0.5,2.0,1.5),vec3(0.1,0.4,0.4)),1);
	color.a=1;
	vec3 col_back=vec3(0);
	vec3 col_top=vec3(1);
	/* color with a down to dark break
	
	if(lv>0.5)
		color.xyz=mix(col_back,col_top,(lv-0.5)*2);
	else
	{
		float nv=sin(lv*2*M_PI);
		color.xyz=mix(col_back,mid_color,nv);
	}
	//*/
	
	/* continuous color
	if(lv>0.5)
	{
		color.xyz=mix(mid_color,col_top,(lv-0.5)*2);
	}
	else
	{
		color.xyz=mix(col_back,mid_color,lv*2);
	}
	//*/
	color.xyz=vec3(lv);
#endif
}
]==]
solver_shader=shader_make[==[
out vec4 color;
in vec3 pos;
uniform sampler2D values_cur;
uniform sampler2D values_old;
uniform sampler2D static_layer;
uniform float init;
uniform float dt;
uniform float c_const;
uniform float time;
uniform float decay;
uniform float freq;
uniform float freq2;
uniform vec2 tex_size;
uniform vec2 nm_vec;
uniform vec2 ab_vec;
//uniform vec2 dpos;

#define M_PI 3.14159265358979323846264338327950288

#define DX(dx,dy) textureOffset(values_cur,normed,ivec2(dx,dy)).x
float hash(float n) { return fract(sin(n) * 1e4); }
float hash(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x)))); }
float func(vec2 pos)
{
	//if(length(pos)<0.0025 && time<100)
	//	return cos(time/freq)+cos(time/(2*freq/3))+cos(time/(3*freq/2));
	//vec2 pos_off=vec2(cos(time*0.001)*0.5,sin(time*0.001)*0.5);
	//if(sh_ring(pos,1.2,1.1,0.001)>0)
	float max_time=50;
	float min_freq=1;
	float max_freq=5;
	float ang=atan(pos.y,pos.x);
	float rad=length(pos);
	float fr=freq;
	float fr2=freq2;
	//fr*=mix(min_freq,max_freq,time/max_time);
	float max_a=5;
	float r=0.5;
	#if 0
		//if(time<max_time)
			//if(pos.x<-0.35)
				//return (hash(time*freq2)*hash(pos*freq))/2;
				return n4rand(pos);
	#endif
	#if 0
		//if(time<max_time)
		//if(pos.x<-0.9)
			return (
		ab_vec.x*sin(time*fr*M_PI/1000
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.x*M_PI*nm_vec.x)+
		ab_vec.y*sin(time*fr2*M_PI/1000
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.y*M_PI*nm_vec.y)
		);
	#endif
	#if 0
	for(float a=0;a<max_a;a++)
	{
		float ang=(a/max_a)*M_PI*2;

		vec2 dv=vec2(cos(ang)*r,sin(ang)*r);
		if(length(pos+dv)<0.005)
		//if(time<max_time)
			return (
			sin(time*fr*M_PI/1000)
			+sin(time*fr*M_PI/1000*1.618)
			/*+sin(time*freq*3*M_PI/1000)*/
										);
	}
	#endif
	#if 0
	//if(time<max_time)
		return (
		ab_vec.x*sin(time*fr*M_PI/1000
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.x*M_PI*nm_vec.x)+
		ab_vec.y*sin(time*fr2*M_PI/1000
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.y*M_PI*nm_vec.y)
		)*0.00005;
	#endif

	#if 0


	
	//if(time<max_time)
	if(abs(length(pos)-0.2)<0.005)
		return sin(time*fr*M_PI/1000+ang*nm_vec.x+rad*nm_vec.y);
	//if(length(pos+vec2(0,0.5)+p)<0.005)
	//	return sin(time*fr2*M_PI/1000);


	#endif
	#if 1
	vec2 p=vec2(0.0,0.4);
	//vec2 p=vec2(cos(time*fr2*M_PI/1000),sin(time*fr2*M_PI/1000))*0.65;
	if(time<max_time)
	if(length(pos+p)<0.005)
		return 1;//sin(time*fr*M_PI/1000);
	#endif
	//return 0.1;//0.0001*sin(time/1000)/(1+length(pos));
	return 0;
}
float func_init_speed(vec2 pos)
{
	return 0;
}
float func_init(vec2 pos)
{
	return 0;
}
#define IDX(dx,dy) func_init(pos+vec2(dx,dy)*dtex)
float calc_new_value(vec2 pos)
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	
	float dcsqr=dt*dt*c_const*c_const;
#if 0
	vec2 p2=pos+vec2(0,-0.3);
	dcsqr*=(dot(p2,p2)+0.05);
#endif
	float dcsqrx=dcsqr;
	float dcsqry=dcsqr;
#if 0
	float dec=dot(pos,pos)*decay;//abs(hash(pos*100))*decay;
#elif 0
	float dec=0.2;
	float sh_v=texture(static_layer,normed).x;
	if(sh_v<0.9)
		dec=0;
#else
	float dec=decay;
#endif

	float ret=(0.5*dec*dt-1)*texture(values_old,normed).x+
		2*DX(0,0)+
		dcsqrx*(DX(1,0)-2*DX(0,0)+DX(-1,0))+
		dcsqry*(DX(0,1)-2*DX(0,0)+DX(0,-1))+
		dt*dt*func(pos);

	return ret/(1+0.5*dec*dt);
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

float boundary_condition(vec2 pos,vec2 dir)
{
	//TODO: open boundary condition??
	//simples condition (i.e. bounce)
	return 0;
}
float boundary_condition_init(vec2 pos,vec2 dir)
{
	//TODO: open boundary condition??
	//simples condition (i.e. bounce)
	return 0;
}
float sdCircle( vec2 p, float r )
{
  return length(p) - r;
}
void main(){
	float v=0;
	vec2 normed=(pos.xy+vec2(1,1))/2;

#if 1
	float sh_v=texture(static_layer,normed).x+(1-step(sdCircle(pos.xy,0.9),0));
#else
	float sh_v=0;
#endif

	if(sh_v<0.9)
	{
		if(init==1)
			v=calc_init_value(pos.xy);
		else
			v=calc_new_value(pos.xy);
	}
	else
		v=0;
	color=vec4(v,0,0,1);
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
function clear_sand(  )
	make_sand_buffer()
end
function clear_buffers(  )
	texture_buffers={}
	make_textures()
	--TODO: @PERF
end

function reset_state(  )
	current_time=0
	solver_iteration=0
	clear_buffers()
end

local need_save
local single_shot_value
current_tick=current_tick or 0
function gui()
	imgui.Begin("Waviness")
	draw_config(config)
	if config.size_mult then
		size_mult=1
	else
		size_mult=2
	end
	update_size()
	local s=STATE.size
	if imgui.Button("Reset") then
		reset_state()
		current_tick=0
		current_frame=0
	end
	imgui.SameLine()
	if imgui.Button("Reset Accumlate") then
		clear_sand()
	end
	if imgui.Button("SingleShotNorm") then
		single_shot_value=true
	end
	imgui.SameLine()
	if imgui.Button("ClearNorm") then
		single_shot_value=nil
	end
--[[
	if imgui.Button("Clear image") then
		clear_buffers()
	end
]]
	if imgui.Button("Save image") then
		need_save=true
	end
	if imgui.Button("RandomStatics") then
    	fill_buffer()
    end
    imgui.SameLine()
    if imgui.Button("WaveCollapse") or current_tick>4000 then
    	local trg_tex=texture_buffers:get_cur().t
    	trg_tex:use(0,1)
    	local pixels=wave_collapse(trg_tex)

    	reset_state()
		current_tick=0
		current_frame=0
		start_set_pixel()
		for i,v in ipairs(pixels) do
			set_big_pixel(v[1],v[2],4)
		end
		end_set_pixel()
    end
	imgui.End()
end

function update( )
	gui()
	update_real()
end

function waves_solve(  )
	make_textures()

	solver_shader:use()
	texture_buffers:get_old().t:use(0)
	texture_buffers:get_cur().t:use(1)
	solver_shader:set_i("values_old",0)
	solver_shader:set_i("values_cur",1)

	texture_particles:get_cur().t:use(2)
	solver_shader:set_i("static_layer",2)
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
	solver_shader:set("freq2",config.freq2)
	solver_shader:set("nm_vec",config.n,config.m)
	solver_shader:set("ab_vec",config.a,config.b)
	local trg_tex=texture_buffers:get_next()
	solver_shader:set("tex_size",trg_tex.w,trg_tex.h)
	if not trg_tex.t:render_to(trg_tex.w,trg_tex.h) then
		error("failed to set framebuffer up")
	end
	solver_shader:draw_quad()
	__render_to_window()
	texture_buffers:advance()
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
function set_big_pixel( x,y,s )
	for dx=-s,s do
		local s2=math.floor(math.sqrt(s*s-dx*dx))
		for dy=-s2,s2 do
			set_pixel(x+dx,y+dy)
		end
	end
end
function wave_collapse( tex )
	local ret={}
	make_io_buffer()
	io_buffer:read_texture(tex)
	local m1=0;
	local max_v=0
	for x=0,io_buffer.w-1 do
		for y=0,io_buffer.h-1 do
			local v=io_buffer:get(x,y)
			if max_v<math.abs(v) then
				max_v=math.abs(v)
			end
			m1=m1+math.abs(v)
		end
	end
	--[[
	for i=1,1 do
		local r=math.random()
		local m2=0
		local done=false
		for x=0,io_buffer.w-1 do
			for y=0,io_buffer.h-1 do
				local v=io_buffer:get(x,y)
				m2=m2+math.abs(v)
				if m2/m1>r then
					table.insert(ret,{x,y})
					done=true
				end
				if done then break end
			end
			if done then break end
		end
	end
	--]]
	local choices={}
	local count_choices=100
	for x=0,io_buffer.w-1 do
		for y=0,io_buffer.h-1 do
			local v=math.abs(io_buffer:get(x,y))
			if v>=max_v*0.99 then
				table.insert(choices,{x,y})
				--if #choices>=count_choices then
				--	table.insert(ret,choices[math.random(1,#choices)])
				--	return ret
				--end
			end
		end
	end
	if #choices>=1 then
		table.insert(ret,choices[math.random(1,#choices)])
	end
	return ret
end
function calc_abs_sum( tex )
	make_io_buffer()
	io_buffer:read_texture(tex)
	local m1=0;

	for x=0,io_buffer.w-1 do
		for y=0,io_buffer.h-1 do
			local v=io_buffer:get(x,y)
			m1=m1+math.abs(v)
		end
	end
	return m1
end
function calc_range_value( tex )
	make_io_buffer()
	io_buffer:read_texture(tex)
	local m1=math.huge;
	local m2=-math.huge;
	for x=0,io_buffer.w-1 do
		for y=0,io_buffer.h-1 do
			local v=io_buffer:get(x,y)
			if v>m2 then m2=v end
			if v<m1 then m1=v end
		end
	end
	return m1,m2
end
function draw_texture( id )
	__render_to_window()
	
	if config.draw then
		local minv,maxv

		draw_waves_shader:use()
		draw_waves_shader:blend_default()
		local trg_tex=texture_buffers:get_cur().t
		trg_tex:use(0,1)

		if single_shot_value==true then
			minv,maxv=calc_range_value(trg_tex)
			single_shot_value={minv,maxv}
		elseif type(single_shot_value)=="table" then
			minv,maxv=single_shot_value[1],single_shot_value[2]
		else
			minv,maxv=calc_range_value(trg_tex)
		end

		draw_waves_shader:set_i("values",0)
		draw_waves_shader:set("v_gamma",1)--config.gamma)
		draw_waves_shader:set("v_gain",1)--config.gain)
		draw_waves_shader:set("mid_color",config.color[1],config.color[2],config.color[3])
		-- [[
		draw_waves_shader:set("add",0)
		draw_waves_shader:set("mult",1/(math.max(math.abs(maxv),math.abs(minv))))
		--]]
		--[[
		draw_waves_shader:set("add",-minv)
		draw_waves_shader:set("mult",1/(maxv-minv))
		--]]
		--[[
		draw_waves_shader:set("add",-math.log(minv+1))
		draw_waves_shader:set("mult",1/(math.log(maxv+1)-math.log(minv+1)))
		--]]
		--[[
		draw_waves_shader:set("add",0)
		draw_waves_shader:set("mult",1/math.log(maxv+1))
		--]]
		draw_waves_shader:draw_quad()
	end
	-- [[
	simple_shader:use()
	simple_shader:blend_add()
	texture_particles:get_cur().t:use(0)
	--texture_buffers:get_cur().t:use(0)
	simple_shader:set_i("values",0)
	if config.draw_moving then
		simple_shader:set("draw_moving",1)
	else
		simple_shader:set("draw_moving",0)
	end
	simple_shader:draw_quad()
	--]]
	if need_save or id then
		save_img(id)
		need_save=nil
	end
end
local tick_refill=1000
current_particle_tick=current_particle_tick or 0
function update_real(  )
	__no_redraw()
	__clear()
	__render_to_window()
	if config.pause then
		draw_texture()
	else
		waves_solve()
		draw_texture()
		current_time=current_time+config.dt
		current_tick=current_tick+1
		--[[
		
		current_particle_tick=current_particle_tick+1
		if tick_refill<current_particle_tick then
			current_particle_tick=0
		end
		]]
	end
end
