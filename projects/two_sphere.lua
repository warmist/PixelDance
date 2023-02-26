require "common"
local ffi=require "ffi"
--[[
	implements ideas from: https://arxiv.org/abs/0707.0022
	todo:
		* set potential energy from nearby cells (e.g. min in same place as they are or inverted etc...)
		* compress data (2 for pos, 2 for speed -> one float4 vs 2!)
]]
local w=1024
local h=1024

local no_floats_per_pixel=4*2*3 --4 for pos, 4 for speed, times 3 

config=make_config({
    {"pause",false,type="bool"},
    {"layer",0,type="int",min=0,max=2},
    {"friction",0.01215,type="floatsci",min=0.005,max=0.1,power=10,watch=true},
    },config)

function set_values(s,tbl)
	return s:gsub("%$([^%$]+)%$",function ( n )
		return tbl[n]
	end)
end

local cl_kernel,init_kernel
function remake_program()
cl_kernel,init_kernel=opencl.make_program(set_values([==[
#line __LINE__
#define W 1024
#define H 1024
#define PARTICLE_COUNT 3

#define TIME_STEP 0.005f
#define GAMMA (2.5f)
#define GAMMA2 (2.5f)
#define DIFFUSION 0.3f
//#define FRICTION $friction$f
typedef struct _settings
{
	float friction;
}settings;
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
#if 0 //gravity based thing
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
#elif 0 //modified (non-singular) gravity
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
			float dd=2-d*d;
			float val=1/sqrt(dd*dd*dd);
			ret+=qs[j]*val;
		}
	}
	return gamma*ret;
}
#elif 0 //modified (non-singular) gravity + static potential
float3 del_potential( float3* qs,int i)
{
	float3 ret=(float3)(0,0,0);
	float3 qi=qs[i];
	float gamma=GAMMA;
	float3 static_potential[3]={
		(float3)(1,0,0),
		(float3)(0,1,0),
		(float3)(0,0,1),
	};
	for(int j=0;j<PARTICLE_COUNT;j++)
	{
		if(j!=i)
		{
			float d=dot(qs[j],qi);
			float dd=2-d*d;
			float val=1/sqrt(dd*dd*dd);
			ret+=qs[j]*val;
		}
		ret+=static_potential[i];
	}
	return gamma*ret;
}
#elif 1 //very simple parabola potential with min at vmin
float3 del_potential( float3* qs,int i,float2 npos)
{
	float3 ret=(float3)(0,0,0);
	float3 qi=qs[i];
	float gamma=GAMMA*(npos.y-0.5)*2;
	float vmin=npos.x;
	for(int j=0;j<PARTICLE_COUNT;j++)
	{
		if(j!=i)
		{
			ret+=2*(dot(qi,qs[j])-vmin)*qs[j];
		}
	}
	return gamma*ret;
}
#elif 0
float3 del_potential( float3* qs,int i)
{
	float3 ret=(float3)(0,0,0);
	float3 qi=qs[i];
	float gamma=GAMMA;
	float values[3]={-2,15,2};
	for(int j=0;j<PARTICLE_COUNT;j++)
	{
		if(j!=i)
		{
			ret+=2*values[i]*dot(qi,qs[j])*qs[j];
		}
	}
	return gamma*ret;
}
#else
float3 del_potential( float3* qs,int i)
{
	float3 ret=(float3)(0,0,0);
	float3 qi=qs[i];
	float gamma=GAMMA;
	float values[3]={1,1,1};
	for(int j=0;j<PARTICLE_COUNT;j++)
	{
		if(j!=i)
		{
			float d=dot(qi,qs[j]);
			ret+=values[i]*cos(d-GAMMA2*d*d)*(1.0f-2.0f*GAMMA2*d)*qs[j];
		}
	}
	return gamma*ret;
}
#endif
void simulation_tick(float2 npos, float3* in_pos, float3* in_speed, float3* out_pos, float3* out_speed)
{
	float step_size=TIME_STEP;

	//float inv_masses=1;//todo: different masses for more fun...
	float inv_masses[3]={1,1,1};
	float3 vecs[PARTICLE_COUNT];
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		float3 vec=in_speed[i]-step_size*0.5f*inv_masses[i]*(cross(in_pos[i],del_potential(in_pos,i,npos)));
		vecs[i]=vec;
		out_pos[i]=cross((step_size*vec),in_pos[i])+sqrt(1-step_size*step_size*dot(vec,vec))*in_pos[i];
	}
	for(int i=0;i<PARTICLE_COUNT;i++)
	{
		float3 vec=vecs[i];
		out_speed[i]=vec-step_size*inv_masses[i]*0.5f*cross(out_pos[i],del_potential(out_pos,i,npos));
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
	float diffusion=DIFFUSION;
	float3 sl=(float3)(length(speed[0]),length(speed[1]),length(speed[2]));

	//float3 nl=laplace(input,pos)*TIME_STEP*diffusion+sl;
	float3 nl=((avg_around(input,pos)+sl*0.2f)/sl)*diffusion+(1-diffusion);

	speed[0]*=nl.x;
	speed[1]*=nl.y;
	speed[2]*=nl.z;
}
__kernel void update_grid(__global __read_only float4* input,__global __write_only float4* output,
	__write_only image2d_t output_tex,int layer_id,float min_x,float min_y,float max_x,float max_y,
	float friction)
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
		float2 npos;
		npos.x=(float)pos.x/(float)W;
		npos.y=(float)pos.y/(float)H;

		npos.x=npos.x*(max_x-min_x)+min_x;
		npos.y=npos.y*(max_y-min_y)+min_y;

		float4 col;

		int offset=i*6;//pos_to_index(pos);
		load_data(input+offset,old_pos,old_speed);
		#if 1
		//diffusion(input,old_speed,pos);
		for(int j=0;j<4;j++)
		{
			simulation_tick(npos,old_pos,old_speed,new_pos,new_speed);
			simulation_tick(npos,new_pos,new_speed,old_pos,old_speed);
			simulation_tick(npos,old_pos,old_speed,new_pos,new_speed);
		}
		//for(int k=0;k<3;k++)
		//	normalize(new_pos[i]);
		for(int k=0;k<3;k++)
			new_speed[k]*=pow(friction,TIME_STEP);
		bool is_ok=true;
		for(int i=0;i<3;i++)
		{
			if(!isnormal(new_pos[i]).x ||! isnormal(new_pos[i]).y || !isnormal(new_pos[i]).z)
				is_ok=false;
		}
		if(is_ok)
			save_data(output+offset,new_pos,new_speed);
		
		#endif
		int di=layer_id;
		#if 0
		col.x=(new_pos[di].x+1)*0.5;
		col.y=(new_pos[di].x+1)*0.5;
		col.z=(new_pos[di].x+1)*0.5;
		#endif
		#if 1
		col.x=(new_pos[di].x+1)*0.5;
		col.y=(new_pos[di].y+1)*0.5;
		col.z=(new_pos[di].z+1)*0.5;
		#endif
		#if 0
		float3 qdot=cross(new_speed[di],new_pos[di]);
		col.xyz=qdot;
		#endif
		#if 0
		col.x=(new_speed[di].x+1)*0.5;
		col.y=(new_speed[di].y+1)*0.5;
		col.z=(new_speed[di].z+1)*0.5;
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
		float val=(dot(new_pos[di],new_pos[(di+1)%3])+1)*0.5;
		col.xyz=(float3)(val);
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
void set_spherical(float phi, float theta,float speed,float4* out_pos,float4* out_speed)
{
	float x=sin(phi)*cos(theta);
	float y=sin(phi)*sin(theta);
	float z=cos(phi);
	(*out_pos).x=x;
	(*out_pos).y=y;
	(*out_pos).z=z;

	(*out_speed).x=copysign(z,x);
	(*out_speed).y=copysign(z,y);
	(*out_speed).z=-copysign(fabs(x)+fabs(y),z);
	(*out_speed)*=speed/length((*out_speed).xyz);
}
__kernel void init_grid(__global float4* output,float min_x,float min_y,float max_x,float max_y)
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
		float x_v=(min_x+pos_normed.x*(max_x-min_x))*M_PI_F*2;
		float y_v=(min_y+pos_normed.y*(max_y-min_y))*M_PI_F;

		set_spherical(0.1,0,2,old_pos,old_speed);
		set_spherical(-2.45,3,-2,old_pos+1,old_speed+1);
		set_spherical(-3,0,1.5f,old_pos+2,old_speed+2);

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
]==],config))

end
remake_program()

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
//from: https://www.alanzucconi.com/2017/07/15/improving-the-rainbow-2/
vec3 bump3y (vec3 x, vec3 yoffset)
{
    vec3 y = 1 - x * x;
    y = clamp(y-yoffset,0,1);
    return y;
}
vec3 spectral_zucconi6 (float w)
{
    // w: [400, 700]
    // x: [0,   1]
    //fixed x = clamp((w - 400.0)/ 300.0,0,1);
    float x=w;
    vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
    vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
    vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);
    vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
    vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
    vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);
    return
        bump3y(c1 * (x - x1), y1) +
        bump3y(c2 * (x - x2), y2) ;
}
void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	//float v=texture(tex_main,normed).x;
	//v=pow(v,2.2);
	//color=vec4(v,v,v,1);
	#if 1
	color.xyz=texture(tex_main,normed).xyz;
	#else
	color.xyz=spectral_zucconi6(texture(tex_main,normed).x);
	#endif
	color.a=1;
}
]]
rsize=rsize or 1
start_pos=start_pos or {0,0}
local start_rect
function recal_rect()
	start_rect={start_pos[1],start_pos[2],start_pos[1]+rsize,start_pos[2]+rsize}
end
recal_rect()
function init_buffers(  )
	init_kernel:set(0,buffers[1])
	for i=1,#start_rect do
		init_kernel:set(i,start_rect[i])
	end
	init_kernel:run(w*h)
end
init_buffers()
function save_img( path )
	local size=STATE.size
    local img_buf_save=make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config or {}) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    img_buf_save:save(path or string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
local last_click
function check_click(  )
	local c,x,y=is_mouse_down(  )
	if c then
		--mouse to screen
		
		x=(x/STATE.size[1])
		y=(1-y/STATE.size[2])
		if x>0 and x<1 and
		   y>0 and y<1 then
			--screen to world
			local nx=start_rect[1]+(start_rect[3]-start_rect[1])*x
			local ny=start_rect[2]+(start_rect[4]-start_rect[2])*y
			print(nx,ny)
			if last_click then
				print("  ",last_click[1]-nx,last_click[2]-ny)
				local lx=math.min(nx,last_click[1])
				local ly=math.min(ny,last_click[2])
				local hx=math.max(nx,last_click[1])
				local hy=math.max(ny,last_click[2])
				start_pos={lx,ly}
				rsize=math.max(hx-lx,hy-ly)
				recal_rect()
				init_buffers()
				last_click=nil
			else
				last_click={nx,ny}
			end
		end
		--]]
	end
end
function simulate_friction(  )
    local friction_start=0.005
    local friction_end=0.015
    local friction_step=(friction_end-friction_start)/(60*10)
    local image_no=1
	for f=friction_start,friction_end,friction_step do
        config.friction=f
        init_buffers()
        local no_sim_ticks=500
        for j=1,no_sim_ticks do
            coroutine.yield()
        end
        save_img(string.format("video/saved (%d).png",image_no))
        image_no=image_no+1
    end
    sim_thread=nil
end
function update(  )
	local sim_done=false
	__no_redraw()
	__clear()
	imgui.Begin("TwoSphere doc")
	draw_config(config)

	if config.__change_events.any then
		--remake_program()
		init_buffers()
	end
	--cl tick
	--setup stuff
	if not config.pause then
		cl_kernel:set(0,buffers[1])
		cl_kernel:set(1,buffers[2])
		cl_kernel:set(2,display_buffer)
		cl_kernel:seti(3,config.layer)
		for i=1,#start_rect do
			cl_kernel:set(i+3,start_rect[i])
		end
		cl_kernel:set(8,config.friction)
		--cl_kernel:set(3,time)
		--  run kernel
		display_buffer:aquire()
		cl_kernel:run(w*h)
		display_buffer:release()
		sim_done=true
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
	if imgui.Button("Reset View") then
		rsize=1
		start_pos={0,0}
		recal_rect()
		init_buffers()
	end
	if not sim_thread then
        if imgui.Button("Simulate") then
           sim_thread=coroutine.create(simulate_friction)
        end
    else
        if imgui.Button("Stop Simulate") then
            sim_thread=nil
        end
    end
 	if sim_thread and sim_done then
        --print("!",coroutine.status(sim_thread))
        local ok,err=coroutine.resume(sim_thread)
        if not ok then
            print("Error:",err)
            sim_thread=nil
        end
    end
	check_click()
	imgui.End()
end