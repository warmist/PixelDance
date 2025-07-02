--[[
	electrons on a disk
--]]
require "common"
local ffi=require "ffi"
local w=1024
local h=1024
local particle_count=13
config=make_config({
	{"gain",1,type="float",min=0,max=10},
	{"mult",1,type="float",min=0,max=10},
},config)


local cl_kernels=opencl.make_program[==[
#line __LINE__
#define W 1024
#define H 1024
#define PCOUNT 13
#define M_PI 3.1415926538
#define SMALL_SCALE_SIZE 0.005f
#define RADIUS 0.8f
int2 clamp_pos(int2 p)
{
	return clamp(p,0,W-1);
}
int pos_to_index(int2 p)
{
	int2 p2=clamp_pos(p);
	return p2.x+p2.y*W;
}
float2 sample_at_pos2(__global float2* arr,int2 p)
{
	if(p.x<0 || p.x>=W ||p.y<0||p.y>=H)
	{
		return 0;
	}
	float2 ret=arr[pos_to_index(p)];
	//return (ceil(ret*255))/255;
	return ret;
}
float2 sample_at_posf(__global float2* arr,float2 pf)
{
	int2 p;
	p.x=(int)(pf.x*W);
	p.y=(int)(pf.y*H);
	if(p.x<0 || p.x>=W ||p.y<0||p.y>=H)
	{
		return 0;
	}
	float2 ret=arr[pos_to_index(p)];
	//return (ceil(ret*255))/255;
	return ret;
}
float sample_at_pos(__global float* arr,int2 p)
{
	if(p.x<0 || p.x>=W ||p.y<0||p.y>=H)
	{
		return 0;
	}
	float ret=arr[pos_to_index(p)];
	return (ceil(ret*255))/255;
	return ret;
}
float sum_around_L(__global float* arr,int2 pos)
{
	float ret=0;
	//ret+=arr[pos.x+pos.y*W];

	ret+=sample_at_pos(arr,pos+(int2)( 0, 1));
	ret+=sample_at_pos(arr,pos+(int2)( 0,-1));
	ret+=sample_at_pos(arr,pos+(int2)( 1, 0));
	ret+=sample_at_pos(arr,pos+(int2)(-1, 0));
	ret*=4.0f;

	ret+=sample_at_pos(arr,pos+(int2)( 1, 1));
	ret+=sample_at_pos(arr,pos+(int2)( 1,-1));
	ret+=sample_at_pos(arr,pos+(int2)(-1, 1));
	ret+=sample_at_pos(arr,pos+(int2)(-1,-1));
	
	return ret/20.0f;
}
float sum_around(__global float* arr,int2 pos)
{
	float ret=0;
	//ret+=arr[pos.x+pos.y*W];

	ret+=sample_at_pos(arr,pos+(int2)( 0, 0));

	ret+=sample_at_pos(arr,pos+(int2)( 0, 1));
	ret+=sample_at_pos(arr,pos+(int2)( 0,-1));
	ret+=sample_at_pos(arr,pos+(int2)( 1, 0));
	ret+=sample_at_pos(arr,pos+(int2)(-1, 0));
	
	ret+=sample_at_pos(arr,pos+(int2)( 1, 1));
	ret+=sample_at_pos(arr,pos+(int2)( 1,-1));
	ret+=sample_at_pos(arr,pos+(int2)(-1, 1));
	ret+=sample_at_pos(arr,pos+(int2)(-1,-1));
	
	return ret/9.0f;
}

float teleported_value(float2 p1,float2 p2)
{
	float2 delta_pt=p2-p1;
	float len=length(delta_pt);
	if(len<0.005)
		return 0;
	float2 v=delta_pt/len;
	float dp=dot(v,p1);
	float u=-dp+sqrt(dp*dp-dot(p1,p1)+1);
	float2 delta1=-u*v;
	float2 delta2=-p1-u*v-p2;

	float len1=sqrt(dot(delta1,delta1));
	float len2=sqrt(dot(delta2,delta2));

	return -(len1+len2);
}
float2 potential_grad(float2 delta)
{
	float dist=length(delta);
	float2 ret;
	ret.x=-delta.x/sqrt(dist*dist*dist);
	ret.y=-delta.y/sqrt(dist*dist*dist);
	return ret;
}
float2 teleported_value_grad(float2 p1,float2 p2)
{
	float2 delta_pt=p2-p1;
	float len=length(delta_pt);
	if(len<SMALL_SCALE_SIZE)
		return 0;
	float2 v=delta_pt/len;
	float dp=dot(v,p1);
	float u=-dp+sqrt(dp*dp-dot(p1,p1)+RADIUS*RADIUS);
	float2 delta1=-u*v;
	float2 delta2=-p1-u*v-p2;
	float2 delta3=p2+2*u*v+p2;
	float len1=sqrt(dot(delta1,delta1));
	float len2=sqrt(dot(delta2,delta2));

	//return potential_grad(delta1)+potential_grad(delta2);
	//return potential_grad(delta1+delta2);
	return potential_grad(-delta3);
}
float2 static_potential(float2 pos)
{
	float2 ret=0*5.f*potential_grad(pos);

	return ret;
}
__kernel void update_grid(__global float2* particles,__global float2* output,__write_only image2d_t output_tex,float time)
{
	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	float max_rad=RADIUS;
	float rad_sq=max_rad*max_rad;
	float electric_str=0.25;
	float teleport_str=2.5;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float2 pos_normed;
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;
		float2 potential_sum=0;
		float o_rad=dot(pos_normed,pos_normed);
		if(o_rad<rad_sq)
		{
			for(int j=0;j<PCOUNT;j++)
			{
				float2 delta=pos_normed-particles[j];
				float l=length(delta);
				if(l>SMALL_SCALE_SIZE)
					potential_sum+=electric_str*potential_grad(delta);
				potential_sum+=teleport_str*electric_str*teleported_value_grad(particles[j],pos_normed);
			}
			potential_sum+=electric_str*static_potential(pos_normed);
		}
		output[i]=potential_sum;
		float4 col;

		col.x=sqrt(dot(potential_sum,potential_sum));
		col.w=1;
		write_imagef(output_tex,pos,col);
		//output_tex[i]=output[i];
	}
}
__kernel void update_particles(__global float2* particles,__global float2* out_particles,__global float2* field)
{
	int i=get_global_id(0);
	int max=PCOUNT;
	float max_rad=RADIUS-0.001;
	float rad_sq=max_rad*max_rad;
	float step_size=0.1;
	if(i>=0 && i<max)
	{
		float2 parr=0.5f*(particles[i]+(float2)(1.0f,1.0f));
		float2 grad=sample_at_posf(field,parr);
		float2 pout=particles[i]-grad*step_size;
		float l=dot(pout,pout);
		//if(l>rad_sq)
		//	pout=-pout;
		out_particles[i]=pout;
	}
}
__kernel void init_particles(__global float2* output,float seed)
{
	int i=get_global_id(0);
	int max=PCOUNT;
	float dist=0.8;
	if(i>=0 && i<max)
	{
		float2 pos;
		//float a=i/(float)max;
		float a=0.5*(cos(1238*i/(float)max+seed)+1);
		float r=0.5*(sin(436897*i/(float)max+seed)+1);
		pos.x=cos(a*M_PI*2)*sqrt(r)*dist;
		pos.y=sin(a*M_PI*2)*sqrt(r)*dist;
		output[i]=pos;
	}
}
]==]

local particle_buffers={
	opencl.make_buffer(particle_count*4),
	opencl.make_buffer(particle_count*4)
}
local potential_field=opencl.make_buffer(w*h*4*2)

texture=textures:Make()
texture:use(0)
texture:set(w,h,F_PIX)
local display_buffer=opencl.make_buffer_gl(texture)

shader=shaders.Make[[
#version 330
#line __LINE__

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float field_mult;
uniform float field_gain;
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
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);
    //data.x*=data.x;
   	float v=data.x;
   	//v=v/(v+1);
   	v=v*field_mult;
   	v=log(v+1);
   	//v=gain(v,field_gain);
    vec3 c=palette(v,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
    color=vec4(c,1);
}
]]
local time=0

function init_buffer(  )
	cl_kernels.init_particles:set(0,particle_buffers[1])
	cl_kernels.init_particles:set(1,math.random())
	cl_kernels.init_particles:run(w*h)
end
init_buffer()
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

function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Electrons")
	draw_config(config)

	--cl tick
	--setup stuff

	local update_grid=cl_kernels.update_grid
	--update_grid:set(2,size)
	update_grid:set(0,particle_buffers[1])
	update_grid:set(1,potential_field)
	update_grid:set(2,display_buffer)
	update_grid:set(3,time)
	


	--  run kernel
	display_buffer:aquire()
	update_grid:run(w*h)
	display_buffer:release()
	--particle move
	local update_particles=cl_kernels.update_particles
	update_particles:set(0,particle_buffers[1])
	update_particles:set(1,particle_buffers[2])
	update_particles:set(2,potential_field)
	update_particles:run(particle_count)
	--opengl draw
	--  read from cl
	-- actually the kernel writes it itself...
	--  draw the texture
	shader:use()
	texture:use(1)
	shader:set_i("tex_main",1)
	shader:set("field_mult",config.mult)
	shader:set("field_gain",config.gain)

	shader:draw_quad()
	if imgui.Button("Save") then
		save_img()
	end
	imgui.End()
	--flip input/output
	local b=particle_buffers[2]
	particle_buffers[2]=particle_buffers[1]
	particle_buffers[1]=b
	time=time+0.00001
end