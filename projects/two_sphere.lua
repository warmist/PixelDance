require "common"
local ffi=require "ffi"

local w=1024
local h=1024

local no_floats_per_pixel=4*2*3 --4 for pos, 4 for speed, times 3 

config=make_config({
    {"pause",false,type="bool"},
    {"layer",0,type="int",min=0,max=2},
    },config)

local cl_kernel,init_kernel=opencl.make_program[==[
#line __LINE__
#define W 1024
#define H 1024
#define PARTICLE_COUNT 3
#define TIME_STEP 0.0005f
#define GAMMA (-1.0f)
int2 clamp_pos(int2 p)
{
	if(p.x<0)
		p.x=W-1;
	if(p.y<0)
		p.y=H-1;
	if(p.x>=W)
		p.x=0;
	if(p.y>=H)
		p.y=0;
	//return clamp(p,0,W-1);
	return p;
}
int pos_to_index(int2 p)
{
	int2 p2=clamp_pos(p);
	return (p2.x+p2.y*W)*2*PARTICLE_COUNT;
}
float3 del_potential( float3* qs,int i)
{
	float3 ret=(float3)(0,0,0);
	float3 qi=qs[i];
	float gamma=GAMMA;
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
void simulation_tick( float3* in_pos, float3* in_speed, float3* out_pos, float3* out_speed)
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
void load_data(__global __read_only float4* input, float3* pos, float3* speed)
{
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		pos[i]=input[i].xyz;
		speed[i]=input[i+3].xyz;
		//pos[i]=vload3(i*2,input);
		//speed[i]=vload3(i*2+1,input);
	}
}
void save_data(__global __write_only float4* output, float3* pos, float3* speed)
{
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		output[i].xyz=pos[i];
		output[i+3].xyz=speed[i];
		//vstore3(pos[i],i*2,output);
		//vstore3(speed[i],i*2+1,output);
	}
}
float system_energy( float4* pos, float4* speed)
{
	float sum=0;
	float masses=1;
	float kin_sum=0;
	float gamma=GAMMA;
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		float4 qdot=cross(speed[i],pos[i]);
		kin_sum+=dot(qdot,qdot)*masses;
	}
	kin_sum*=0.5;
	float pot_sum=0;
	for(int i=0;i<PARTICLE_COUNT;i++)
		for(int j=0;j<PARTICLE_COUNT;j++)
			if (i!=j)
			{
				float4 qi=pos[i];
				float4 qj=pos[j];
				float d=dot(qi,qj);
				pot_sum+=d/sqrt(1-d*d);
			}
	pot_sum=pot_sum*gamma*0.5;

	sum=kin_sum+pot_sum;
	return sum;
}
float load_speed_v(__global float4* input,int offset,int i)
{
	return length(input[offset+i+3]);
}
float3 load_speed_v3(__global float4* input,int2 pos)
{
	int offset=pos_to_index(pos);
	float3 s;
	s.x=load_speed_v(input,offset,0);
	s.y=load_speed_v(input,offset,1);
	s.z=load_speed_v(input,offset,2);
	return s;
}
float3 laplace(__global float4* input,int2 pos)
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
float3 avg_around(__global float4* input,int2 pos)
{
	float3 ret=(float3)(0,0,0);
	/*
	ret+=load_speed_v3(input,pos+(int2)(-1,-1))*0.05f;
	ret+=load_speed_v3(input,pos+(int2)(-1, 1))*0.05f;
	ret+=load_speed_v3(input,pos+(int2)( 1,-1))*0.05f;
	ret+=load_speed_v3(input,pos+(int2)( 1, 1))*0.05f;
	*/
	ret+=load_speed_v3(input,pos+(int2)( 0,-1))*0.2f;
	ret+=load_speed_v3(input,pos+(int2)(-1, 0))*0.2f;
	ret+=load_speed_v3(input,pos+(int2)( 1, 0))*0.2f;
	ret+=load_speed_v3(input,pos+(int2)( 0, 1))*0.2f;

	return ret;
}
void diffusion(__global float4* input, float3* speed,int2 pos)
{
	float diffusion=1.0f;
	float3 sl=(float3)(length(speed[0]),length(speed[1]),length(speed[2]));

	//float3 nl=laplace(input,pos)*TIME_STEP*diffusion+sl;
	float3 nl=((avg_around(input,pos)+sl*0.2f)/sl)*diffusion+(1-diffusion);

	speed[0]*=nl.x;
	speed[1]*=nl.y;
	speed[2]*=nl.z;
}
__kernel void update_grid(__global __read_only float4* input,__global __write_only float4* output,__write_only image2d_t output_tex)
{
	float3 old_pos[PARTICLE_COUNT];
	float3 old_speed[PARTICLE_COUNT];
	float3 new_pos[PARTICLE_COUNT];
	float3 new_speed[PARTICLE_COUNT];

	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float4 col;

		int offset=i*6;//pos_to_index(pos);
		load_data(input+offset,old_pos,old_speed);
		#if 1
		diffusion(input,old_speed,pos);
		for(int j=0;j<16;j++)
		{
			simulation_tick(old_pos,old_speed,new_pos,new_speed);
			simulation_tick(new_pos,new_speed,old_pos,old_speed);
			simulation_tick(old_pos,old_speed,new_pos,new_speed);
		}
		//for(int k=0;k<3;k++)
		//	normalize(new_pos[i]);
		for(int k=0;k<3;k++)
			new_speed[k]*=0.99995f;
		save_data(output+offset,new_pos,new_speed);
		
		#endif
		int di=0;
		#if 1
		col.x=(new_pos[di].x+1)*0.5;
		col.y=(new_pos[di].y+1)*0.5;
		col.z=(new_pos[di].z+1)*0.5;
		#endif
		#if 0
		col.x=(new_pos[0].x+1)*0.5;
		col.y=(new_pos[0].y+1)*0.5;
		col.z=(new_pos[0].z+1)*0.5;
		#endif
		#if 0
		col.x=(new_pos[0].x+1)*0.5;
		col.y=(new_pos[1].x+1)*0.5;
		col.z=(new_pos[2].x+1)*0.5;
		#endif
		#if 0
		col.x=(dot(new_pos[0],new_pos[1])+1)*0.5;
		col.y=(dot(new_pos[1],new_pos[2])+1)*0.5;
		col.z=(dot(new_pos[2],new_pos[0])+1)*0.5;
		#endif
		#if 0
		col.x=(new_pos[0].x+1)*0.5;
		col.y=(new_pos[0].y+1)*0.5;
		col.z=(new_pos[0].z+1)*0.5;
		#endif
		#if 0
		col.x=length(new_speed[0]);
		col.y=length(new_speed[1]);
		col.z=length(new_speed[2]);
		#endif
		#if 0
		col.x*=length(new_pos[0]);
		col.y*=length(new_pos[1]);
		col.z*=length(new_pos[2]);
		col.xyz*=0.2f;
		#endif
		#if 0
		float v=system_energy(new_pos,new_speed)/10;
		col.x=v;
		col.y=v;
		col.z=v;
		#endif
		#if 0
		float v=1-fabs(system_energy(old_pos,old_speed)-system_energy(new_pos,new_speed));
		col.x=v;
		col.y=v;
		col.z=v;
		#endif
		#if 0
		col.xyz=old_pos[di];
		//col.xyz=old_speed[di];
		#endif
		#if 0
		col.x=pos.x/(W*1.0f);
		col.y=pos.y/(H*1.0f);
		col.z=0;
		#endif
		col.w=1;
		write_imagef(output_tex,pos,col);
	}
}
__kernel void init_grid(__global float4* output)
{
	float4 old_pos[PARTICLE_COUNT];
	float4 old_speed[PARTICLE_COUNT];
	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float iW=1.0f/W;
		float2 pos_normed;
		pos_normed=(float2)(pos.x*iW,pos.y*iW);
		float2 delta;
		delta=convert_float2(pos-(int2)(W,H)/2)/W;
		float distance=dot(delta,delta);

		int offset=pos_to_index(pos);
		float v=distance*0.5;
		#if 0
		old_pos[0]=(float4)(pos_normed.x,pos_normed.y,0.1f,0);
		old_speed[0]=(float4)(1-pos_normed.x,pos_normed.y,0.8f,0);
		old_pos[1]=(float4)(pos_normed.x,pos_normed.y,0.3f,0);
		old_speed[1]=(float4)(pos_normed.x,pos_normed.y,0.4f,0);		
		old_pos[2]=(float4)(pos_normed.x,pos_normed.y,0.5f,0);
		old_speed[2]=(float4)(pos_normed.x,pos_normed.y,0.6f,0);
		#endif
		#if 1
		old_pos[0]=(float4)(1,0,0,0);
		old_speed[0]=(float4)(0,-1.5f+delta.x*0.00005f,0,0);

		old_pos[1]=(float4)(0,-1,0,0);
		old_speed[1]=(float4)(0.5f,0,0,0);

		old_pos[2]=(float4)(0,0,1,0);
		old_speed[2]=(float4)(0,1.5f+delta.y*0.00005f,0,0);
		#endif
		save_data(output+i*6,old_pos,old_speed);
		#if 0
		output[offset+0]=1;
		output[offset+1]=0;
		output[offset+2]=0;

		output[offset+3]=0;
		output[offset+4]=0.05f+delta.x*0.5f;
		output[offset+5]=0;
		//-------------------
		output[offset+6]=0;
		output[offset+7]=-1;
		output[offset+8]=0;

		output[offset+9]=0.5f;
		output[offset+10]=0;
		output[offset+11]=0;
		//-------------------
		output[offset+12]=0;
		output[offset+13]=0;
		output[offset+14]=1;

		output[offset+15]=0;
		output[offset+16]=0.0+v*2.0f;
		output[offset+17]=0;
		#endif

	}
}
]==]
buffers={
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
function save_img(  )
	local size=STATE.size
    local img_buf_save=make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config or {}) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    img_buf_save:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("TwoSphere doc")
	draw_config(config)
	--cl tick
	--setup stuff
	if not config.pause then
		cl_kernel:set(0,buffers[1])
		cl_kernel:set(1,buffers[2])
		cl_kernel:set(2,display_buffer)
		--cl_kernel:seti(3,config.layer)
		--cl_kernel:set(3,time)
		--  run kernel
		display_buffer:aquire()
		cl_kernel:run(w*h)
		display_buffer:release()
	end
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
	if not config.pause then
		local b=buffers[2]
		buffers[2]=buffers[1]
		buffers[1]=b
	end
	--]]
	if imgui.Button("Save") then
		save_img()
	end
	if imgui.Button("Reset") then
		init_buffers()
	end
	imgui.End()
end