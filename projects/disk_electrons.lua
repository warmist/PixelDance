--[[
	electrons on a disk
--]]
require "common"
local ffi=require "ffi"
local w=1024
local h=1024
local particle_count=1024
config=make_config({
	{"gain",1,type="float",min=0,max=10},
	{"mult",1,type="float",min=0,max=10},
	{"perturb_str",0.005,type="float",min=0,max=0.01},
},config)


local cl_kernels=opencl.make_program[==[
#line __LINE__
#define W 1024
#define H 1024
#define PCOUNT 1024
#define M_PI 3.1415926538
#define SMALL_SCALE_SIZE 0.0005f
#define RADIUS 1.0f
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

float2 potential_grad_org(float2 delta) //original potential
{
	float dist=length(delta);
	if(dist<SMALL_SCALE_SIZE)
		return (float2)(0,0);
	float2 ret;
	ret.x=-delta.x/sqrt(dist*dist*dist);
	ret.y=-delta.y/sqrt(dist*dist*dist);
	return ret;
}
float2 potential_grad_4pow(float2 delta)
{
	float dist=length(delta);
	if(dist<SMALL_SCALE_SIZE)
		return (float2)(0,0);
	float d4=(dist*dist);
	d4*=d4;
	float2 ret;
	ret.x=-delta.x/d4;
	ret.y=-delta.y/d4;
	return ret;
}
float2 potential_grad_ln(float2 delta)
{
	float dist=length(delta);
	if(dist<SMALL_SCALE_SIZE)
		return (float2)(0,0);
	float l4=log(dist*dist+1);

	float2 ret;
	ret.x=-delta.x/(l4*(dist*dist+1));
	ret.y=-delta.y/(l4*(dist*dist+1));
	return ret;
}
float2 potential_grad_2pow(float2 delta)
{
	float dist=length(delta);
	if(dist<SMALL_SCALE_SIZE)
		return (float2)(0,0);
	float2 ret;
	ret=-delta/(dist*dist);
	return ret*0.0125f;
}
float2 potential_grad_exp(float2 delta)
{
	float dist=length(delta);
	if(dist<SMALL_SCALE_SIZE)
		return (float2)(0,0);
	//if(dist>0.2)
	//	return (float2)(0,0);

	float e=-exp(-dot(delta,delta)*64);
	return delta*e;
}
float2 actual_grad(float2 p)
{
	return potential_grad_2pow(p);
	return potential_grad_ln(p);
	return potential_grad_exp(p);
	return potential_grad_4pow(p);
	return potential_grad_org(p);
}
float2 teleported_value_grad_wave_simple(float2 p1,float2 p2)
{
	//simpler idea:
	//  if p2=>center -> influence=>0
	//  if p2=>edge -> influence=>1 (constant)
	// inbetween some sin(delta angle) and sin(delta radius) thingy
	float l2=length(p2);
	if(l2<SMALL_SCALE_SIZE)
		return 0;
	float l1=length(p1);
	if(l1<SMALL_SCALE_SIZE)
		return 0;
	float2 edge=normalize(p2)*RADIUS;
	float edge_val=1-l2/RADIUS;
	float dp=dot(p1,p2)/(l1*l2);
	dp=clamp(dp,-1.f,1.f);
	float da=acos(dp);//cos(angle);
	float dr=fabs(l1-l2);
	return 1*(actual_grad(-edge)+actual_grad(p2-p1)*((l2-0.1f)*cos(da*edge_val*12)+1)*(exp(-dr*dr)*sin(dr*edge_val*64)+1));
}
float2 teleported_value_grad_wave_simple2(float2 p1,float2 p2)
{
	//simpler idea:
	// if center=>0
	// near edge=>1
	//
	float l2=length(p2);
	if(l2<SMALL_SCALE_SIZE)
		return 0;
	float l1=length(p1);
	if(l1<SMALL_SCALE_SIZE)
		return 0;
	float2 edge=normalize(p2)*RADIUS;
	float dp=dot(p1,p2)/(l1*l2);

	float dist_to_edge=RADIUS-l2;
	float dist_to_edge2=RADIUS-l1;
	dp=clamp(dp,-1.f,1.f);
	float da=acos(dp);//cos(angle);
	float dr=fabs(l1-l2);
	return 3*(actual_grad(-edge)*exp(-dist_to_edge*dist_to_edge/(da+0.01f+dr)-dist_to_edge2*dist_to_edge2/(da+0.01f)));
}
float2 teleported_value_grad_wave(float2 p1,float2 p2) //Eh...
{
	float2 delta_pt=p2+p1;
	float len=length(delta_pt);
	if(len<SMALL_SCALE_SIZE)
		return 0;

	float2 v=delta_pt/len;
	float dp=dot(v,p1);
	float rval=dp*dp-dot(p1,p1)+RADIUS*RADIUS;
	if(rval<0)
		return 0;
	//if(rval<0)
	//	rval*=-1;

	float u1=-dp+sqrt(rval); //tv+A and circle intersection at t=u
	float u2=-dp-sqrt(rval);


	float2 intersect1=u1*v+p1;
	float2 mirror_intesect1=-intersect1;
	float2 mirror_p1_1=mirror_intesect1-u1*v;
	float2 delta3_1=p2-mirror_p1_1;

	float2 intersect2=u2*v+p1;
	float2 mirror_intesect2=-intersect2;
	float2 mirror_p1_2=mirror_intesect2-u2*v;
	float2 delta3_2=p2-mirror_p1_2;
	float delta_len=length(delta3_1+delta3_2);
	float2 ret=0;
	int N_MAX=12;
	for(int n=1;n<N_MAX;n++)
	{

		float alpha=n*M_PI/4*rval;
		ret+=sin(alpha*delta_len)*actual_grad(delta3_1+delta3_2)/N_MAX;
	}
	return ret;
	//else
	//	return actual_grad(-delta3_2);
	//return actual_grad(delta1)+actual_grad(delta2);
	//return actual_grad(delta1+delta2);
	//return actual_grad(delta3);
}
float2 teleported_value_grad(float2 p1,float2 p2)
{
	float2 delta_pt=p2+p1;
	//float2 delta_pt=p2-p1; //was this bug for nicer effects...
	float len=length(delta_pt);
	if(len<SMALL_SCALE_SIZE)
		return 0;
	float2 v=delta_pt/len;
	float dp=dot(v,p1);
	float rval=dp*dp-dot(p1,p1)+RADIUS*RADIUS;
	if(rval<0)
		return 0;
	//if(rval<0)
	//	rval*=-1;


	float u1=-dp+sqrt(rval); //tv+A and circle intersection at t=u
	float u2=-dp-sqrt(rval);


	float2 intersect1=u1*v+p1;
	float2 mirror_intesect1=-intersect1;
	float2 mirror_p1_1=mirror_intesect1-u1*v;
	float2 delta3_1=p2-mirror_p1_1;

	float2 intersect2=u2*v+p1;
	float2 mirror_intesect2=-intersect2;
	float2 mirror_p1_2=mirror_intesect2-u2*v;
	float2 delta3_2=p2-mirror_p1_2;

	return actual_grad(delta3_1)+actual_grad(delta3_2);
	//else
	//	return actual_grad(-delta3_2);
	//return actual_grad(delta1)+actual_grad(delta2);
	//return actual_grad(delta1+delta2);
	//return actual_grad(delta3);
}
float2 teleported_value_grad_angle(float2 p1,float2 p2,float angle)
{
	//float angle=M_PI/2; //only M_PI is stable, all other spin...
	float2 delta_pt=p2+p1;
	float len=length(delta_pt);
	if(len<SMALL_SCALE_SIZE)
		return 0;
	float2 v=delta_pt/len;
	float dp=dot(v,p1);
	float rval=dp*dp-dot(p1,p1)+RADIUS*RADIUS;
	//if(rval<0)
	//	return 0;
	if(rval<0)
		rval*=-1;
	float u=-dp+sqrt(rval);
	float2 proj_p1=u*v+p1;
	float2 rot_pp1=(float2)(
		cos(angle)*proj_p1.x-sin(angle)*proj_p1.y,
		sin(angle)*proj_p1.x+cos(angle)*proj_p1.y);
	float2 mirror_p1=rot_pp1-u*v;

	float2 delta3=p2-mirror_p1;

	return actual_grad(-delta3);
}

float2 teleported_value_grad_mirror(float2 p1,float2 p2)
{
	float angle=M_PI;

	float p1sq=dot(p1,p1);
	if(p1sq<SMALL_SCALE_SIZE)
		return (float2)(0,0);
	float2 mirror_p1=RADIUS*RADIUS*p1/dot(p1,p1);
	float2 rotated_p1=(float2)(
		mirror_p1.x*cos(angle)-mirror_p1.y*sin(angle),
		mirror_p1.x*sin(angle)+mirror_p1.y*cos(angle));

	float2 delta_pt=p2-rotated_p1;
	float len=length(delta_pt);
	if(len<SMALL_SCALE_SIZE)
		return 0;

	return actual_grad(delta_pt);
}

float2 static_potential(float2 pos)
{
	float2 ret=0.0f*actual_grad(pos);

	return ret;
}
float2 find_particle_offset(int j)
{
	float2 offset=(float2)(0,0);
	/*
	if(j%4==0)
		offset=(float2)(1,0);
	else if(j%4==1)
		offset=(float2)(cos(2*M_PI/4),sin(2*M_PI/4));
	else if(j%4==2)
		offset=(float2)(cos(4*M_PI/4),sin(4*M_PI/4));
	else
		offset=(float2)(cos(6*M_PI/4),sin(6*M_PI/4));
	//*/
	/*
	if(j%2==0)
		offset=(float2)(1,0);
	else
		offset=(float2)(-1,0);
	//*/
	/*
	if(j%3==0)
		offset=(float2)(1,0);
	else if(j%3==1)
		offset=(float2)(cos(2*M_PI/3),sin(2*M_PI/3));
	else
		offset=(float2)(cos(4*M_PI/3),sin(4*M_PI/3));
	//*/
	/*
	if(j%5==0)
		offset=(float2)(1,0);//0
	else if(j%5==1)
		offset=(float2)(cos(2*M_PI/5),sin(2*M_PI/5));//1/5
	else if(j%5==2)
		offset=(float2)(cos(4*M_PI/5),sin(4*M_PI/5));//2/5
	else if(j%5==3)
		offset=(float2)(cos(6*M_PI/5),sin(6*M_PI/5));//3/5
	else
		offset=(float2)(cos(8*M_PI/5),sin(8*M_PI/5));//4/5
	*/
	//offset=(float2)(0,0);
	float dist=0.5;
	return offset*dist;
}
__kernel void update_grid(__global float2* particles,__global float2* output,__write_only image2d_t output_tex,float time)
{
	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	float max_rad=RADIUS;
	float rad_sq=max_rad*max_rad;
	float electric_str=0.125;
	float teleport_str=1.0;
	float angle_step=0.8;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float2 pos_normed;
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;
		float2 potential_sum=0;
		float2 teleport_sum=0;
		float o_rad=dot(pos_normed,pos_normed);
		float inside_pt=0;
		if(o_rad<rad_sq)
		{
			for(int j=0;j<PCOUNT;j++)
			{
				float2 offset;
				offset=find_particle_offset(j);
				float2 delta=pos_normed-particles[j];
				float l=length(delta);
				if(l>SMALL_SCALE_SIZE)
					potential_sum+=electric_str*actual_grad(delta);
				else
					inside_pt=1;
				teleport_sum+=teleport_str*electric_str*teleported_value_grad_wave_simple2(particles[j]+offset,pos_normed+offset);
				/*
				if(j%2==0)
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,M_PI+angle_step);
				else
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,M_PI-angle_step);
				//*/
				/*
				if(j%3==0)
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,M_PI+angle_step);
				else if(j%3==1)
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,M_PI);
				else
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,M_PI-angle_step);
				*/
				/*
				if(j%4==0)
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,angle_step*2.0/3.0);
				else if(j%4==1)
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,angle_step/3.0);
				else if(j%4==2)
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,-angle_step*2.0/3.0);
				else
					teleport_sum+=teleport_str*electric_str*teleported_value_grad_angle(particles[j]+offset,pos_normed+offset,-angle_step/3.0);
				*/
			}
			potential_sum+=electric_str*static_potential(pos_normed);
		}
		output[i]=potential_sum+teleport_sum;
		float4 col;
		//float2 v=teleport_sum;
		//float2 v=potential_sum;
		float2 v=potential_sum+teleport_sum;
		col.x=dot(v,v);
		col.y=inside_pt;
		//col.x=sqrt(dot(potential_sum,potential_sum));
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
	float step_size=0.01;
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
__kernel void recenter_particles(__global float2* particles,__global float2* out_particles)
{
	int i=get_global_id(0);
	int max=PCOUNT;
	if(i>=0 && i<max)
	{
		float2 avg=0;
		for(int j=0;j<PCOUNT;j++)
			{
				avg+=particles[j];
			}
		out_particles[i]=particles[i]-avg/PCOUNT;
	}
}
__kernel void perturb_particles(__global float2* particles,__global float2* out_particles,float seed,float strength)
{
	int i=get_global_id(0);
	int max=PCOUNT;
	if(i>=0 && i<max)
	{
		float2 pos=particles[i];

		float a=0.5*(cos(1238*i/(float)max+seed)+1);
		float r=0.5*(sin(436897*i/(float)max+seed)+1);
		pos.x+=cos(a*M_PI*2)*sqrt(r)*strength;
		pos.y+=sin(a*M_PI*2)*sqrt(r)*strength;

		out_particles[i]=pos;
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
texture:set(w,h,FL_PIX)
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
    float anti_grad_step=0.001;
    //vec4 data=texture(tex_main,normed);
    //vec4 data=(texture(tex_main,normed)+texture(tex_main,normed+anti_grad_step*vec2(1,0))+texture(tex_main,normed+anti_grad_step*vec2(0,1)));
    vec4 data=texture(tex_main,normed);

    //data.x*=data.x;
   	//float v=dot(data.xy,data.xy);
   	float v=data.x;
   	//if(v<1)
	//	v=100;
   	//v=log(v+1);
   	v=v/(v+1);
   	v=v*field_mult;
   	//v=gain(v,field_gain);
   	//v=sqrt(sqrt(v));
    vec3 c=palette(v,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
    if(data.y>0)
    	c=vec3(1);
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

	--if imgui.Button("Perturb") then
		local perturb_particles=cl_kernels.perturb_particles
		perturb_particles:set(0,particle_buffers[2])
		perturb_particles:set(1,particle_buffers[1])
		perturb_particles:set(2,math.random())
		perturb_particles:set(3,config.perturb_str)

		perturb_particles:run(particle_count)
	--end
	--particle move
	local update_particles=cl_kernels.update_particles
	update_particles:set(0,particle_buffers[1])
	update_particles:set(1,particle_buffers[2])
	update_particles:set(2,potential_field)
	update_particles:run(particle_count)
	local do_recenter=true
	if do_recenter then
		local recenter_particles=cl_kernels.recenter_particles
		recenter_particles:set(0,particle_buffers[2])
		recenter_particles:set(1,particle_buffers[1])
		recenter_particles:run(particle_count)
	end
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
	-- [==[
	if not do_recenter then
		local b=particle_buffers[2]
		particle_buffers[2]=particle_buffers[1]
		particle_buffers[1]=b
	end
	--]==]
	time=time+0.00001
end