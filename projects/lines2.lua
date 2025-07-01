require 'common'
--[[
Other ideas:
	- add "minimal distance" teleport, not straight
]]
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
	{"scale",1,type="float",min=0,max=0.01},
	{"teleport_scale",1,type="float",min=0,max=1},
	{"b",1,type="float",min=-0.5,max=0.5},
},config)

grid=grid or make_float_buffer(STATE.size[1],STATE.size[2])

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
objects={}
function rnd( v )
	return math.random()*(v*2)-v
end
function particle_init( object_count,pt_count )
	local pt_id=0
	for k=1,object_count do

		local kv=(k/object_count)*math.pi*2
		local center={math.cos(kv)*radius/2,math.sin(kv)*radius/2}
		local count=pt_count
		objects[k]={points=make_flt_half_buffer(pt_count*2,1),color={math.random(),math.random(),math.random(),1}}
		local points = objects[k].points
		for i=0,count-1 do
			local v=(i/count)*math.pi*2
			local nv=((i+1)/count)*math.pi*2
			local r=radius/4
			points.d[i*2]={math.cos(v)*r+center[1],math.sin(v)*r+center[2]}
			points.d[i*2+1]={math.cos(nv)*r+center[1],math.sin(nv)*r+center[2]}
			local mr=math.random()*math.sqrt(radius)
			local phi=math.random()*math.pi*2
			--points.d[i*2]={math.cos(phi)*mr,math.sin(phi)*mr}
			--points.d[i*2+1]={math.cos(nv)*r+center[1],math.sin(nv)*r+center[2]}
		end
	end
end
particle_init(1,1)
function draw_object( o )
	line_shader:use()
	line_shader:set("line_color",unpack(o.color))
	line_shader:draw_lines(o.points.d,o.points.w,false)
end
function dot(a,b )
	return a[1]*b[1]+a[2]*b[2]
end
function teleported_value( pt1,pt2 )
	local sum=0
	local step=0.1
	for i=-math.pi,math.pi,step do
		local v={math.cos(i),math.sin(i)}
		local dp=dot(v,pt1)
		local u=-dp+math.sqrt(dp*dp-dot(pt1,pt1)+1)
		local delta1={-u*v[1],-u*v[2]}
		local delta2={-pt1[1]-u*v[1]-pt2[1],-pt1[2]-u*v[2]-pt2[2]}
		local len1=math.sqrt(dot(delta1,delta1))
		local len2=math.sqrt(dot(delta2,delta2))
		sum=sum+len1+len2
	end
	return sum*step
end
function update_potential_field(  )
	local rsq=radius*radius
	local max_v=0
	for x=0,grid.w-1 do
		for y=0,grid.h-1 do
			local lx=(x/(grid.w/2))-1
			local ly=(y/(grid.w/2))-1
			if lx*lx+ly*ly<rsq then
				local sum=0
				for i,v in ipairs(objects) do
					for k=0,v.points.w-1 do
						local pt=v.points.d[k]
						local dx=pt.r-lx
						local dy=pt.g-ly
						local l=math.sqrt(dx*dx+dy*dy)
						if l>0.01 then
							sum=sum+1/l
						end
						sum=sum+1/teleported_value({pt.r,pt.g},{lx,ly})
					end
				end
				
				if max_v<sum then max_v=sum end
				grid:set(x,y,sum)
			end
		end
	end
	for x=0,grid.w-1 do
		for y=0,grid.h-1 do
			grid:set(x,y,grid:get(x,y)/max_v)
		end
	end
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

draw_potential=init_draw_field(
[==[
#line __LINE__

#define M_PI 3.1415926538
float teleported_value2(vec2 p1,vec2 p2)
{
	float sum=0;
	int step_count=100;
	float step=2*M_PI/float(step_count);
	for(int i=0;i<step_count;i++)
	{
		float vs=-M_PI+step*i;

		vec2 v=vec2(cos(vs),sin(vs));
		float dp=dot(v,p1);
		float u=-dp+sqrt(dp*dp-dot(p1,p1)+1);
		vec2 delta1=-u*v;
		vec2 delta2=-p1-u*v-p2;

		float len1=sqrt(dot(delta1,delta1));
		float len2=sqrt(dot(delta2,delta2));
		sum=sum+len1+len2;
	}
	return sum*step;
}
float teleported_value(vec2 p1,vec2 p2)
{
	vec2 delta_pt=p2-p1;
	float len=length(delta_pt);
	if(len<0.01)
		return 0;
	vec2 v=delta_pt/len;
	float dp=dot(v,p1);
	float u=-dp+sqrt(dp*dp-dot(p1,p1)+1);
	vec2 delta1=-u*v;
	vec2 delta2=-p1-u*v-p2;

	float len1=sqrt(dot(delta1,delta1));
	float len2=sqrt(dot(delta2,delta2));
	
	return -(len1+len2);
}
void main(){

    vec2 normed=(pos.xy);
    float l=dot(normed,normed);
    float c=0;
    if(l<0.8*0.8)
    {
    	vec2 delta=normed-trg_pos;
    	float l2=length(delta);
    	if(l2>0.01)
    		c=scale/l2;
    	c+=teleport_scale/teleported_value(normed,trg_pos);
    }
    color=vec4(c,c,c,1);
}
]==],
{
    uniforms={
    	{name="trg_pos",type="vec2"},
    	{name="teleport_scale",type="float"},
    	{name="scale",type="float"},
    },
}
)
function draw_potential_field( pos,first)
	if first then
		draw_potential.clear()
	end
	if not draw_field.textures.tex_main.texture:render_to(STATE.size[1],STATE.size[2]) then
		error("failed to set framebuffer up")
	end
	local shader=draw_potential.shader
	shader:blend_add()
	draw_potential.update_uniforms({trg_pos=pos,teleport_scale=config.teleport_scale,scale=config.scale})
	draw_potential.draw()
	shader:blend_default()
	__render_to_window()
end
local first=true
function update()
	__no_redraw()
	__clear()
	imgui.Begin("lines")
		draw_config(config)
	if imgui.Button("update") then
		update_potential_field(  )
	end
	if first then
		draw_field.update(grid)
		first=false
	end
	draw_field.draw()
	--line_shader:use()
	--line_shader:set("line_color",1,0.5,0,0.2)
	--line_shader:draw_lines(circle.d,circle.w*circle.h,true)
	-- [[
	local first_pt=true
	for i,v in ipairs(objects) do
		for k=0,v.points.w-1,2 do
			draw_potential_field({v.points.d[k].r,v.points.d[k].g},first_pt)
			first_pt=false
		end
	--draw_potential_field({0.4,0.2}))
	end
	--]]
	if imgui.Button("Save") then
		save_img()
	end
	imgui.End()
end