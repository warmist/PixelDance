require "common"
local ffi=require "ffi"

local w=64
local h=64
local no_floats_per_pixel=(3+3)*3 --3 for pos, 3 for speed, times 3 
local cl_kernel,init_kernel=opencl.make_program[==[
#line __LINE__
#define W 64
#define H 64
#define PARTICLE_COUNT 3
#define TIME_STEP 0.001f
int2 clamp_pos(int2 p)
{
	return clamp(p,0,W-1);
}
int pos_to_index(int2 p)
{
	int2 p2=clamp_pos(p);
	return (p2.x+p2.y*W)*3*2*PARTICLE_COUNT;
}
float3 del_potential(__local float3* qs,int i)
{
	float3 ret=(float3)(0,0,0);
	float3 qi=qs[i];
	float gamma=1;
	for(int j=0;j<PARTICLE_COUNT;j++)
	{
		if(j!=i)
		{
			float d=dot(qs[j],qi);
			float dd=1-d*d;
			float val=1/sqrt(dd*dd*dd);
			ret+=qs[j]*val;
		}
	}
	return gamma*ret;
}
void simulation_tick(__local float3* in_pos,__local float3* in_speed,__local float3* out_pos,__local float3* out_speed)
{
	float step_size=TIME_STEP;

	float inv_masses=1;//todo: different masses for more fun...
	float3 vecs[PARTICLE_COUNT];
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		float3 vec=in_speed[i]-step_size*0.5f*inv_masses*(cross(in_pos[i],del_potential(in_pos,i)));
		vecs[i]=vec;
		out_pos[i]=cross((step_size*vec),in_pos[i])+sqrt(1-step_size*step_size*dot(vec,vec))*in_pos[i];
	}
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		float3 vec=vecs[i];
		out_speed[i]=vec-step_size*inv_masses*0.5f*cross(out_pos[i],del_potential(out_pos,i));
	}
}
void load_data(__global float* input,__local float3* pos,__local float3* speed)
{
	for(int i=0;i<PARTICLE_COUNT;i++)
		pos[i]=(float3)(input[i*6],input[i*6+1],input[i*6+2]);
	for(int i=0;i<PARTICLE_COUNT;i++)
		speed[i]=(float3)(input[i*6+3],input[i*6+4],input[i*6+5]);
}
void save_data(__global float* output,__local float3* pos,__local float3* speed)
{
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		output[i*6+0]=pos[i].x;
		output[i*6+1]=pos[i].y;
		output[i*6+2]=pos[i].z;
	}
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		output[i*6+3]=speed[i].x;
		output[i*6+4]=speed[i].y;
		output[i*6+5]=speed[i].z;
	}
}
float system_energy(__local float3* pos,__local float3* speed)
{
	float sum=0;
	float masses=1;
	float kin_sum=0;
	float gamma=1;
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		float3 qdot=cross(speed[i],pos[i]);
		kin_sum+=dot(qdot,qdot)*masses;
	}
	kin_sum*=0.5;
	float pot_sum=0;
	for(int i=0;i<PARTICLE_COUNT;i++)
		for(int j=0;j<PARTICLE_COUNT;j++)
			if (i!=j)
			{
				float3 qi=pos[i];
				float3 qj=pos[j];
				float d=dot(qi,qj);
				pot_sum+=d/sqrt(1-d*d);
			}
	pot_sum=pot_sum*gamma*0.5;

	sum=kin_sum+pot_sum;
	return sum;
}
float load_speed_v(__global float* input,int offset,int i)
{
	float3 s;
	s.x=input[offset+i*6+3];
	s.y=input[offset+i*6+4];
	s.z=input[offset+i*6+5];
	return length(s);
}
float3 load_speed_v3(__global float* input,int2 pos)
{
	int offset=pos_to_index(pos);
	float3 s;
	s.x=load_speed_v(input,offset,0);
	s.y=load_speed_v(input,offset,1);
	s.z=load_speed_v(input,offset,2);
	return s;
}
float3 laplace(__global float* input,int2 pos)
{
	float3 ret=(float3)(0,0,0);
	ret+=load_speed_v3(input,pos+(int2)(-1,-1))*0.05f;
	ret+=load_speed_v3(input,pos+(int2)(-1, 1))*0.05f;
	ret+=load_speed_v3(input,pos+(int2)( 1,-1))*0.05f;
	ret+=load_speed_v3(input,pos+(int2)( 1, 1))*0.05f;

	ret+=load_speed_v3(input,pos+(int2)( 0,-1))*0.2f;
	ret+=load_speed_v3(input,pos+(int2)(-1, 0))*0.2f;
	ret+=load_speed_v3(input,pos+(int2)( 1, 0))*0.2f;
	ret+=load_speed_v3(input,pos+(int2)( 0, 1))*0.2f;

	ret+=load_speed_v3(input,pos+(int2)( 0, 0))*(-1.0f);
	return ret;
}
void diffusion(__global float* input,__local float3* speed,int2 pos)
{
	float diffusion=0.1f;
	float3 sl=(float3)(length(speed[0]),length(speed[1]),length(speed[2]));

	float3 nl=laplace(input,pos)*TIME_STEP*diffusion+sl;
	nl/=sl;
	speed[0]*=nl.x;
	speed[1]*=nl.y;
	speed[2]*=nl.z;
}
__kernel void update_grid(__global float* input,__global float* output,__write_only image2d_t output_tex)
{
	__local float3 old_pos[PARTICLE_COUNT];
	__local float3 old_speed[PARTICLE_COUNT];
	__local float3 new_pos[PARTICLE_COUNT];
	__local float3 new_speed[PARTICLE_COUNT];

	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		int offset=pos_to_index(pos);
		load_data(input+offset,old_pos,old_speed);
		//diffusion(input,old_speed,pos);
		for(int j=0;j<100;j++)
		{
			simulation_tick(old_pos,old_speed,new_pos,new_speed);
			simulation_tick(new_pos,new_speed,old_pos,old_speed);
			simulation_tick(old_pos,old_speed,new_pos,new_speed);
		}
		//for(int k=0;k<3;k++)
		//	normalize(new_pos[i]);
		save_data(output+offset,new_pos,new_speed);

		float4 col;
		#if 1
		col.r=(new_pos[0].r+1)*0.5;
		col.g=(new_pos[1].r+1)*0.5;
		col.b=(new_pos[2].r+1)*0.5;
		#endif
		#if 0
		col.r=(new_pos[0].r+1)*0.5;
		col.g=(new_pos[0].g+1)*0.5;
		col.b=(new_pos[0].b+1)*0.5;
		#endif
		#if 0
		col.r=length(new_speed[0]);
		col.g=length(new_speed[1]);
		col.b=length(new_speed[2]);
		col.rgb*=0.2f;
		#endif
		#if 0
		col.r*=length(new_pos[0]);
		col.g*=length(new_pos[1]);
		col.b*=length(new_pos[2]);
		#endif
		#if 0
		float v=system_energy(new_pos,new_speed)/10;
		col.r=v;
		col.g=v;
		col.b=v;
		#endif
		#if 0
		float v=1-fabs(system_energy(old_pos,old_speed)-system_energy(new_pos,new_speed));
		col.r=v;
		col.g=v;
		col.b=v;
		#endif
		#if 0
		col.r=pos.x/(W*1.0f);
		col.g=pos.y/(H*1.0f);
		col.b=0;
		#endif
		col.a=1;
		write_imagef(output_tex,pos,col);
	}
}
__kernel void init_grid(__global float* output)
{
	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;

		float2 delta;
		delta=convert_float2(pos-(int2)(W,H)/2)/W;
		float distance=dot(delta,delta);

		int offset=pos_to_index(pos);
		float v=distance*0.5;
		output[offset+0]=1;
		output[offset+1]=0;
		output[offset+2]=0;

		output[offset+3]=0;
		output[offset+4]=0.05f;
		output[offset+5]=0;
		//-------------------
		output[offset+6]=0;
		output[offset+7]=-1;
		output[offset+8]=0;

		output[offset+9]=0.05f;
		output[offset+10]=0;
		output[offset+11]=0;
		//-------------------
		output[offset+12]=0;
		output[offset+13]=0;
		output[offset+14]=1;

		output[offset+15]=0;
		output[offset+16]=0.1+v*0.5;
		output[offset+17]=0;
		

	}
}
]==]
local buffers={
	opencl.make_buffer(w*h*4*no_floats_per_pixel),
	opencl.make_buffer(w*h*4*no_floats_per_pixel)
}

texture=textures:Make()
texture:use(0)
texture:set(w,h,FLTA_PIX)

local display_buffer=opencl.make_buffer_gl(texture)

shader=shaders.Make[[
#version 330
#line __LINE__

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;

void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	//float v=texture(tex_main,normed).x;
	//v=pow(v,2.2);
	//color=vec4(v,v,v,1);
	color.xyz=texture(tex_main,normed).xyz;
	color.a=1;
}
]]
function init_buffers(  )
	init_kernel:set(0,buffers[1])
	init_kernel:run(w*h)
end
init_buffers()
function update(  )
	__no_redraw()
	__clear()
	--cl tick
	--setup stuff

	cl_kernel:set(0,buffers[1])
	cl_kernel:set(1,buffers[2])
	cl_kernel:set(2,display_buffer)
	--cl_kernel:set(3,time)
	--  run kernel
	display_buffer:aquire()
	cl_kernel:run(w*h)
	display_buffer:release()
	--opengl draw
	--  read from cl
	-- actually the kernel writes it itself...
	--  draw the texture
	shader:use()
	texture:use(1)
	shader:set_i("tex_main",1)
	shader:draw_quad()
	--flip input/output
	-- [[
	local b=buffers[2]
	buffers[2]=buffers[1]
	buffers[1]=b
	--]]
end