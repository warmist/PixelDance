require "common"

--[[
	An attempt of implementing [Computer generated watercolor] (https://grail.cs.washington.edu/projects/watercolor/paper_small.pdf)
--]]

config=make_config({
	{"pause",false,type="boolean"},
	{"scale",0.1,type="float"},
},config)

local oversample=1
function update_size()
	local trg_w=1280
	local trg_h=1280
	--this is a workaround because if everytime you save
	--  you do __set_window_size it starts sending mouse through windows. SPOOKY
	if win_w~=trg_w or win_h~=trg_h or (img_buf==nil or img_buf.w~=trg_w*oversample) then
		win_w=trg_w
		win_h=trg_h
		aspect_ratio=win_w/win_h
		__set_window_size(win_w,win_h)
	end
end
update_size()

local size=STATE.size
img_buf=img_buf or make_image_buffer(size[1],size[2]) --output display buffer
io_buffer=io_buffer or make_flt_buffer(size[1],size[2])

--format: speed:(u,v), pressure,bonus(?)
buf_water_speed=buf_water_speed or multi_texture(size[1],size[2],2,FLTA_PIX)


function reset_buffers( )
	local b=io_buffer
	local min_value=-500
	local max_value=500
	local p_min=0
	local p_max=0.1
	for x=0,b.w-1 do
		for y=0,b.h-1 do
			local dx=x-b.w/2
			local dy=y-b.h/2
			local dist=math.sqrt(dx*dx+dy*dy)/b.w
			-- [[

			-- [=[ circle
				if dist<b.w/4 then
					b:set(x,y,{
					math.random()*(max_value-min_value)+min_value,
					math.random()*(max_value-min_value)+min_value,
					math.max(math.min(0.1-dist,1),0),
					0})
				else
					b:set(x,y,{0,0,0,0})
				end
			--]=]
			--[=[
				b:set(x,y,{
				math.random()*(max_value-min_value)+min_value,math.random()*(max_value-min_value)+min_value,
					math.random()*(max_value-min_value)+min_value,math.random()*(max_value-min_value)+min_value})
			--]=]

			--]]
			--[[ chaos check
			local v=(x+y)/(b.w+b.h-2)
			b:set(x,y,{
					(x/(b.w-1)+0.1)*(max_value-min_value)+min_value,
					(y/(b.h-1)+0.1)*(max_value-min_value)+min_value,
					--dist/10,
					--dist/10,
					--dist/10,
					0,
					0})
			--]]
		end
	end

	local buf=buf_water_speed:get()
	buf:use(0)
	b:write_texture(buf)
	buf_water_speed:advance()

	buf=buf_water_speed:get()
	buf:use(0)
	b:write_texture(buf)

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

local draw_shader = shader_make[==[
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;

uniform float v_gamma;
uniform float v_gain;


uniform vec4 value_scale;
uniform vec4 value_offset;

float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}

float paper_texture(vec2 p)
{
	float ret=0;
	//TODO: actual textures
	ret=0.5-dot(p,p);
	return clamp(ret,0,1);
}
void main(){

	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 cnt=abs(texture(tex_main,normed));
	cnt+=value_offset;
	cnt*=value_scale;

	float lv=cnt.x;//paper_texture(pos.xy);

	//lv=gain(lv,v_gain);
	//lv=pow(lv,v_gamma);

	//color=vec4(cnt.xyz,1);
	//color.a=1;
	color=vec4(cnt.xyz,1);
	//color=vec4(palette(lv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.5,1.5,1.25),vec3(1.0,1.05,1.4)),1);
}
]==]

function draw_texture( id )
	draw_shader:use()
	draw_shader:blend_default()
	local buf=buf_water_speed:get()

	--[=[
	if do_normalize or global_mm==nil or config.do_norm then
		global_mm,global_mx=find_min_max(buf)
		if do_normalize=="single" then
			do_normalize=false
		-- [[

		print("=======================")
		for i,v in ipairs(global_mm) do
			print(i,v)
		end
		for i,v in ipairs(global_mx) do
			print(i,v)
		end
		--]]
		end
	end
	]=]
	buf:use(0,0,0)
	draw_shader:set_i('tex_main',0)
	draw_shader:set("v_gamma",1)--config.gamma)
	draw_shader:set("v_gain",1)--config.gain)

	--[[
	local mm=global_mm
	local mx=global_mx
	local mmin=math.min(mm[1],mm[2])
	mmin=math.min(mmin,mm[3])
	mmin=math.min(mmin,mm[4])
	local mmax=math.max(mx[1],mm[2])
	mmax=math.max(mmax,mm[3])
	mmax=math.max(mmax,mm[4])
	--]]
	--[[
	local mmin=mm[config.draw_comp+1]
	local mmax=mx[config.draw_comp+1]
	--]]
	--[[
	draw_shader:set("value_offset",-mm[1],-mm[2],-mm[3],0)
	draw_shader:set("value_scale",1/(mx[1]-mm[1]),1/(mx[2]-mm[2]),1/(mx[3]-mm[3]),1)
	--]]
	--draw_shader:set("value_offset",0.5,0.5,0,0)
	draw_shader:set("value_offset",0,0,0,0)
	local s=config.scale
	draw_shader:set("value_scale",s,s,s,0)
	--draw_shader:blend_disable()
	draw_shader:draw_quad()
	if need_save or id then
		save_img(id)
		if need_save=="r" then
			reset_buffers()
		end
		need_save=nil
	end
end
local shader_remove_grad=shader_make[==[
out vec4 color;
in vec3 pos;

uniform sampler2D velocity;

vec2 paper_grad(vec2 pos)
{
	//TODO: we use it for u, and it needs to be offset at 0.5
	return vec2(0,0);
}

void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 g=paper_grad(pos.xy);
	color.xyz=texture(velocity,normed).xyz -vec3(g,0);
	color.a=1;
}
]==]
local shader_update_velocities=shader_make[==[
out vec4 color;
in vec3 pos;

uniform sampler2D velocity;

uniform float viscosity;
uniform float drag;
uniform float dt;

/*

u_i-0.5j
+------+ v_ij-0.5
|      |
| p_ij |
|      |
+------+
	   u_i+0.5j
	   v_ij+0.5

*/
void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 vel_out;//=texture(velocity,normed).xy;

	/* index in name is doubled and offset i.e:
		u00-> (u(-1,0)+u(0,0))/2
		u10-> u(0,0)
		u20-> (u(0,0)+u(1,0))/2
		u30-> u(1,0)

		second one is doubled but not halfstep!
		u11->(u(0,0)+u(0,1))/2
		u12->u(0,1);
		u14->u(0,2);
		u32->u(1,1);

		for v it's reverse
		v00-> (v(0,-1)+v(0,0))/2
		v01-> v(0,0)
	*/

	float u_10=textureOffset(velocity,normed,ivec2(-1,0)).x;
	float u_11=(textureOffset(velocity,normed,ivec2(-1,0)).x+textureOffset(velocity,normed,ivec2(-1,1)).x)/2;
	float u00=(textureOffset(velocity,normed,ivec2(-1,0)).x+textureOffset(velocity,normed,ivec2(0,0)).x)/2;
	float u1_2=textureOffset(velocity,normed,ivec2(0,-1)).x;
	float u1_1=(textureOffset(velocity,normed,ivec2(0,-1)).x+textureOffset(velocity,normed,ivec2(0,0)).x)/2;
	float u10=textureOffset(velocity,normed,ivec2(0,0)).x; //same as input
	float u11=(textureOffset(velocity,normed,ivec2(0,0)).x+textureOffset(velocity,normed,ivec2(0,1)).x)/2;
	float u12=textureOffset(velocity,normed,ivec2(0,1)).x;
	float u20=(textureOffset(velocity,normed,ivec2(0,0)).x+textureOffset(velocity,normed,ivec2(1,0)).x)/2;
	float u30=textureOffset(velocity,normed,ivec2(1,0)).x;


	float v0_1=textureOffset(velocity,normed,ivec2(0,-1)).y;
	float v1_1=(textureOffset(velocity,normed,ivec2(0,-1)).y+textureOffset(velocity,normed,ivec2(1,-1)).y)/2;
	float v00=(textureOffset(velocity,normed,ivec2(0,-1)).y+textureOffset(velocity,normed,ivec2(0,0)).y)/2;
	float v_21=textureOffset(velocity,normed,ivec2(-1,0)).y;
	float v_11=(textureOffset(velocity,normed,ivec2(-1,0)).y+textureOffset(velocity,normed,ivec2(0,0)).y)/2;
	float v01=textureOffset(velocity,normed,ivec2(0,0)).y; //same as input
	float v11=(textureOffset(velocity,normed,ivec2(0,0)).y+textureOffset(velocity,normed,ivec2(1,0)).y)/2;
	float v21=textureOffset(velocity,normed,ivec2(1,0)).y;
	float v02=(textureOffset(velocity,normed,ivec2(0,0)).y+textureOffset(velocity,normed,ivec2(0,1)).y)/2;
	float v03=textureOffset(velocity,normed,ivec2(0,1)).y;


	float p00=textureOffset(velocity,normed,ivec2(0,0)).z;
	float p10=textureOffset(velocity,normed,ivec2(1,0)).z;
	float p01=textureOffset(velocity,normed,ivec2(0,1)).z;

	{
		float A=u00*u00-u20*u20+u1_1*v1_1-u11*v11;
		float B=u30+u_10+u12+u1_2-4*u10;

		vel_out.x=u10+dt*(A-viscosity*B+p00-p10-drag*u10);
	}
	{
		float A=v00*v00-v02*v02+u_11*v_11-u11*v11;
		float B=v21+v_21+v03+v0_1-4*v01;

		vel_out.y=v01+dt*(A-viscosity*B+p00-p01-drag*v01);
	}
	color.xy=vel_out;

	color.z=p00;
	color.a=1;
}
]==]
local shader_relax_divergence=shader_make[==[
out vec4 color;
in vec3 pos;

uniform float step_size;
uniform sampler2D velocity;

void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 state=texture(velocity,normed);
	float del00=step_size*(
		textureOffset(velocity,normed,ivec2(0,0)).x-textureOffset(velocity,normed,ivec2(1,0)).x+
		textureOffset(velocity,normed,ivec2(0,0)).y-textureOffset(velocity,normed,ivec2(0,1)).y);

	float del10=step_size*(
		textureOffset(velocity,normed,ivec2(-1,0)).x-textureOffset(velocity,normed,ivec2(0,0)).x+
		textureOffset(velocity,normed,ivec2(-1,0)).y-textureOffset(velocity,normed,ivec2(-1,1)).y);

	float del01=step_size*(
		textureOffset(velocity,normed,ivec2(0,-1)).x-textureOffset(velocity,normed,ivec2(1,-1)).x+
		textureOffset(velocity,normed,ivec2(0,-1)).y-textureOffset(velocity,normed,ivec2(0,0)).y);

	state.xyz+=vec3(-del00+del10,-del00+del01,del00);
	color=state;
}
]==]
function calculate_divergence(  )
	local b=io_buffer
	local buf=buf_water_speed:get()
	buf:use(0)
	b:read_texture(buf)
	local max_div=0
	local avg_div=0
	local mxy={0,0}
	for i=0,b.w-1 do
	for j=0,b.h-1 do
		local p00=b:get(i,j)
		local ni=i+1
		if ni==buf.w then ni=0 end
		local nj=j+1
		if nj==buf.h then nj=0 end
		local p10=b:get(ni,j)
		local p01=b:get(i,nj)

		local d=math.abs((p00.r-p10.r)+(p00.g-p01.g))
		if d>max_div then max_div=d end
		avg_div=avg_div+d
		if mxy[1]<math.abs(p00.r) then mxy[1]=math.abs(p00.r) end
		if mxy[2]<math.abs(p00.g) then mxy[2]=math.abs(p00.g) end
	end
	end
	avg_div=avg_div/(b.w*b.h)
	local step=1/math.max(mxy[1],mxy[2])
	print("MAX D:",max_div,avg_div,step)
end
function relax_divergence(  )

	local step_count=50
	local min_div=0.01
	local step_size=0.1

	for i=1,step_count do
		shader_relax_divergence:use()
		shader_relax_divergence:set("step_size",step_size)
		buf_water_speed:get():use(0);
		shader_relax_divergence:set_i("velocity",0);
		local next_buff=buf_water_speed:get_next()
		next_buff:use(2,0,0)
		if not next_buff:render_to(buf_water_speed.w,buf_water_speed.h) then
			error("failed to set framebuffer up")
		end

		shader_relax_divergence:draw_quad()

		buf_water_speed:advance()
		__render_to_window()
	end
	calculate_divergence()
end
function remove_grad(  )
	shader_remove_grad:use()
	buf_water_speed:get():use(0);
	shader_update_velocities:set_i("velocity",0);
	local next_buff=buf_water_speed:get_next()
	next_buff:use(2,0,0)
	if not next_buff:render_to(buf_water_speed.w,buf_water_speed.h) then
		error("failed to set framebuffer up")
	end

	shader_update_velocities:draw_quad()

	buf_water_speed:advance()
	__render_to_window()
end

function velocity_update(  )
	local step_size=0.0001;
	local step_count=50;
	for i=1,step_count do
		shader_update_velocities:use()
		shader_update_velocities:set("viscosity",0.1);
		shader_update_velocities:set("drag",0.01);
		shader_update_velocities:set("dt",step_size);

		buf_water_speed:get():use(0);
		shader_update_velocities:set_i("velocity",0);

		local next_buff=buf_water_speed:get_next()
		next_buff:use(1,0,0)
		if not next_buff:render_to(buf_water_speed.w,buf_water_speed.h) then
			error("failed to set framebuffer up")
		end

		shader_update_velocities:draw_quad()

		buf_water_speed:advance()
	end
	__render_to_window()
end
function sim_tick(  )
	remove_grad()
	--velocity_update()
	relax_divergence()
	--flow_outward
end
function gui(  )
	imgui.Begin("Watercolor")
	draw_config(config)
	if imgui.Button("Reset") then
		reset_buffers()
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.SameLine()
	if imgui.Button("norm") then
		do_normalize="single"
	end
	imgui.End()
end

function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function is_mouse_down_0( ... )
	return __mouse.clicked0 and not __mouse.owned0, __mouse.x,__mouse.y
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
		draw_texture(save_id)
	end
	local c0
	local c,x,y= is_mouse_down()
	c0,x,y= is_mouse_down_0()
	if c or c0 then
		if c then
		end
	end
end
