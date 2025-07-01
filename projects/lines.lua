require 'common'

local line_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;
uniform vec4 line_color;
void main(){
	color=line_color;
}
]==]
config=make_config({
	{"a",1,type="float",min=-3,max=3},
	{"b",1,type="float",min=-0.5,max=0.5},
	{"c",1,type="float",min=-0.5,max=0.5},
},config)
function init_circle( rad,pt_count )
	circle=make_flt_half_buffer(pt_count or 100,1)
	local count=circle.w
	for i=0,count-1 do
		local v=(i/(count-1))*math.pi*2
		local r=rad
		circle.d[i]={math.cos(v)*r,math.sin(v)*r}
	end
end
local radius=0.8
init_circle(radius)

points=make_flt_half_buffer(50000,1)
function rnd( v )
	return math.random()*(v*2)-v
end
function particle_init(  )
	local count=points.w
	for i=0,count-1 do
		local v=(i/count)*math.pi*2
		local r=rnd(0.01)+0.3
		points.d[i]={math.cos(v)*r,math.sin(v)*r}
	end
end
local time=0
function F(t)
	local a=config.a
	local b=config.b
	local c=config.c
	--return {t,a*t*t+b}
	--return {a*math.cos(b*t)-b*(a*t+c)*math.sin(b*t),
	--	a*math.sin(b*t)+b*(a*t+c)*math.cos(b*t)}
	--return {a*math.exp(b*t)*math.cos(t),
	--	a*math.exp(b*t)*math.sin(t)}
	local sgn=1
	if t<0 then
		t=-t
		sgn=-1
	end
	return {sgn*a*math.sqrt(c*t)*math.cos(b*t+math.cos(time)),
		sgn*a*math.sqrt(c*t)*math.sin(b*t+math.cos(time))+0.6}
end
function find_step_len( cur_t,dt,limit_len )
	local start_pt=F(cur_t)
	for i=1,10 do
		local end_pt=F(cur_t+dt)
		local delta={end_pt[1]-start_pt[1],end_pt[2]-start_pt[2]}
		local len=math.sqrt(delta[1]*delta[1]+delta[2]*delta[2])
		if len>math.abs(limit_len) then
			dt=dt/2
		end
	end
	return dt
end
particle_init()
function eval_funcs(dt,max_len)
	local count=points.w
	local offset_pt={0,0}
	local rad_sq=radius*radius
	local pt_id=0
	local jump_count=0
	local current_t=0
	local cur_dt=dt

	points.d[0]=F(current_t)
	points.d[1]=F(current_t)
	pt_id=pt_id+2

	local break_after=0
	for i=0,max_len do

		--draw array full, so draw and restart
		if pt_id+2>count then
			line_shader:draw_lines(points.d,pt_id,false)
			points.d[0]={points.d[pt_id-1].r,points.d[pt_id-1].g}
			points.d[1]={points.d[pt_id-1].r,points.d[pt_id-1].g}
			pt_id=2
			break_after=break_after+1
		end

		cur_dt=find_step_len(current_t,cur_dt,dt)
		current_t=current_t+cur_dt
		local ft=F(current_t)

		ft[1]=ft[1]+offset_pt[1]
		ft[2]=ft[2]+offset_pt[2]

		local len=ft[1]*ft[1]+ft[2]*ft[2]
		if len>rad_sq then
			--reproject to circle
			ft[1]=radius*ft[1]/math.sqrt(len)
			ft[2]=radius*ft[2]/math.sqrt(len)

			local old_offset={offset_pt[1],offset_pt[2]}
			--find new offset
			offset_pt={offset_pt[1]-2*ft[1],offset_pt[2]-2*ft[2]}

			jump_count=jump_count+1
			--if jump_count>4 then
			--	break
			--end
			ft[1]=ft[1]+offset_pt[1]-old_offset[1]
			ft[2]=ft[2]+offset_pt[2]-old_offset[2]
			points.d[pt_id]={ft[1],ft[2]}
			points.d[pt_id+1]={ft[1],ft[2]}
			pt_id=pt_id+2
		else
			--no jump so just copy over last pt and add our own

			points.d[pt_id]={points.d[pt_id-1].r,points.d[pt_id-1].g}
			points.d[pt_id+1]={ft[1],ft[2]}
			pt_id=pt_id+2
		end
		--if break_after>1 then
		--	break
		--end
	end

	line_shader:draw_lines(points.d,pt_id,false)
end
function save_img( id )
	--make_image_buffer()
	local size=STATE.size
	img_buf=make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	config_serial=config_serial.."\n"..string.format("thingy_string=%q",thingy_string)
	config_serial=config_serial.."\n"..string.format("feed_kill_string=%q",feed_kill_string)
	img_buf:read_frame()
	if id then
		img_buf:save(string.format("video/saved (%d).png",id),config_serial)
	else
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	end
end

draw_field=init_draw_field(
[==[
#line __LINE__
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);
    //data.x*=data.x;
    float normed_particle=data.x*255/5;
    vec3 c=palette(normed_particle,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
    color=vec4(c,1);
}
]==],
{
    uniforms={
    },
}
)

function update()
	__no_redraw()
	__clear()
	imgui.Begin("lines")
		draw_config(config)

	time=time+0.0005
	line_shader:use()
	line_shader:set("line_color",1,0,0,0.1)
	eval_funcs(-0.05,6000)
	eval_funcs(0.05,6000)
	line_shader:set("line_color",1,0.5,0,0.2)
	line_shader:draw_lines(circle.d,circle.w*circle.h,true)
	if imgui.Button("Save") then
		save_img()
	end
	imgui.End()
end