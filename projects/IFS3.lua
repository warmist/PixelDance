--[==[
	Iterative fractal system 3:
		- build on ifs/ifs2
		- use opencl
		- ndimensional accumulation phase
			- maybe spherical harmonics?
				it would be shells (r) with spherical harmonics on each
				or just assume there is stuff already integrated and just calculate final surface harmonic
		- raytrace output
		- ??
		- profit

	TODO:
		point colors
		absorbtion/emittion?
		local thread group iterate over x by y by z cell (why? though?)
--]==]

--[=[
	basic architecture:
		- iteration kernel -> a main function that takes points and advances on a function
			- might do N steps to be faster
		- splatting kernel -> iterates over output points and adds them to "their voxels"
			- gal sujungti splat+iterate, nes reik po kiekvieno iterate, splat daryt kad nereiktu invocation overhead moket
		- rendering kernel -> raytraces over the voxels
--]=]
require "common"
local grid_size={200,200,200}
local point_count=100
local view_w=1024
local view_h=1024
--__set_window_size(view_w,view_h)

config=make_config({
    {"pause",true,type="bool"},
    {"pause_points",true,type="bool"},
    {"x_rot",0,type="float",min=0,max=1},
    {"y_rot",0,type="float",min=0,max=1},
    {"brightness",0,type="float",min=0,max=2},
    },config)

local need_reinit=(grid_field==nil)
function swap_buffers(tbl)
	local p=tbl[1]
	tbl[1]=tbl[2]
	tbl[2]=p
end
grid_field=grid_field or {
	opencl.make_buffer(grid_size[1]*grid_size[2]*grid_size[3]*4*4),
	opencl.make_buffer(grid_size[1]*grid_size[2]*grid_size[3]*4*4),
	swap=function() swap_buffers(grid_field) end
}

point_data=point_data or {
	opencl.make_buffer(point_count*4*4),
	opencl.make_buffer(point_count*4*4),
	swap=function() swap_buffers(point_data) end
}
point_data_rnd=point_data_rnd or {
	opencl.make_buffer(point_count*4*4),
	opencl.make_buffer(point_count*4*4),
	swap=function() swap_buffers(point_data_rnd) end
}

texture=textures:Make()
texture:use(1)
texture:set(view_w,view_h,FLTA_PIX)
local display_buffer=opencl.make_buffer_gl(texture)


local cl_kernels
local kernel_base=[==[
#line __LINE__

#define GRID_W $GRID_W
#define GRID_H $GRID_H
#define GRID_D $GRID_D

#define VIEW_W $VIEW_W
#define VIEW_H $VIEW_H

#define POINT_COUNT $POINT_COUNT
#define MAX_STEPS 1000
#define POINT_SPREAD 0.5f
#define SPLAT_SCALE 0.2f
#define CUBE_CENTER (float3)(0,0,0.0f)
#define GENERATION_OFFSET (float4)(0.0f,0.0f,0.0f,0.0f)

//from: https://www.shadertoy.com/view/WttXWX
//bias: 0.17353355999581582 ( very probably the best of its kind )
uint lowbias32(uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

// bias: 0.020888578919738908 = minimal theoretic limit
uint triple32(uint x)
{
    x ^= x >> 17;
    x *= 0xed5ad4bbU;
    x ^= x >> 11;
    x *= 0xac4c1b51U;
    x ^= x >> 15;
    x *= 0x31848babU;
    x ^= x >> 14;
    return x;
}
#define HASH lowbias32
uint4 hash_seed(uint4 v)
{
	return (uint4)(HASH(v.x),HASH(v.y),HASH(v.z),HASH(v.w));
}
float4 gaussian4 (float4 seed,float4 mean,float4 var)
{
    return  (float4)(
    sqrt(-2 * var.x * log(seed.x)) * cos(2 * M_PI * seed.y),
    sqrt(-2 * var.y * log(seed.x)) * sin(2 * M_PI * seed.y),
    sqrt(-2 * var.z * log(seed.z)) * cos(2 * M_PI * seed.w),
    sqrt(-2 * var.w * log(seed.z)) * sin(2 * M_PI * seed.w))+mean;
}
float4 calculate_origin_point(uint4 seed)
{
	float4 rnd_pt=convert_float4(seed)/(4294967295.0f);
	float4 ret=gaussian4(rnd_pt,GENERATION_OFFSET,(float4)(POINT_SPREAD));
	ret.w=0;
	return ret;
}
__kernel void seed_random(__global uint4* output_random,__global float4* output_points,uint4 global_seed)
{
	int i=get_global_id(0);
	if(i>=0 && i<POINT_COUNT)
	{
		uint4 cur_seed;
		cur_seed=(uint4)(i)+global_seed;
		cur_seed=hash_seed(cur_seed);

		output_random[i]=cur_seed;
		output_points[i]=calculate_origin_point(cur_seed);
		//output_points[i]=(float4)(2*i/convert_float(POINT_COUNT)-1);
	}
}
__kernel void advance_random(__global uint4* input_random,__global uint4* output_random)
{
	int i=get_global_id(0);
	if(i>=0 && i<POINT_COUNT)
	{
		output_random[i]=hash_seed(input_random[i]);
	}
}
float3 rotate_around(float3 vec, float3 axis,float angle)
{
	float ca=cos(angle);
	float sa=sin(angle);
	return vec*ca+cross(axis,vec)*sa+axis*(dot(axis,vec))*(1-ca);
}
float4 pt_func(float4 pt,float4 pt_start)
{
	float4 pt_out;
	//cubic mandelbulb?
#if 0
	pt_out.x=pt.x*pt.x*pt.x-3*pt.x*(pt.y*pt.y+pt.z*pt.z);
	pt_out.y=-pt.y*pt.y*pt.y+3*pt.y*pt.x*pt.x-pt.y*pt.z*pt.z;
	pt_out.z=pt.z*pt.z*pt.z-3*pt.z*pt.x*pt.x+pt.z*pt.y*pt.y;
	pt_out+=pt_start;
#elif 0
	float b=0.1f;
	float a=1.0f;
	float c=-0.01f;
	pt_out=a*sin(pt.yzxw)-b*pt+c*pt_start;
#elif 0 //simple affine?
	pt_out.xyz=rotate_around(pt.xyz-pt_start.xyz,(float3)(0,0,1),0.1)*0.9f+pt_start.xyz;
	pt_out.w=pt.w;
#elif 1
	float a=0.2f;
	float b=0.8f;
	pt_out=a*pt*pt.yzxw-b*pt.zzyy*pt.xxyy;
	pt_out+=pt_start;
#endif
	pt_out.w=pt.w;
	return pt_out;
}
__kernel void point_iterate(
	__global float4* point_list_input,
	__global uint4*  input_random,
	__global float4* point_list_output,
	__global uint4*  output_random
	//__global float4* params
	)
{
	int i=get_global_id(0);
	
	if(i>=0 && i<POINT_COUNT)
	{
		uint4 my_rnd=input_random[i];
		float4 point_start=calculate_origin_point(my_rnd);
		float4 pt=point_list_input[i];
		float4 pt_out;
		float dist_traveled=0;
		//pt_out=pt*1.001f;
		//pt_out=a*sin(c*pt.yzxw)-b*pt;
		for(int k=0;k<200;k++)
		{
			pt_out=pt_func(pt,point_start);
			pt_out.w=pt.w;
			dist_traveled+=distance(pt_out.xyz,pt.xyz);
			pt=pt_out;
		}
		float abs_dist=distance(point_start.xyz,pt_out.xyz);
		//--------------
		//if(pt_out.w<0.1 )//&& dist_traveled>0.001
		//	pt_out.w+=0.001;
		//if(dist_traveled<0)
		//	pt_out.w=5;
		pt_out.w=0.01;
		if( //dist_traveled<1 || dist_traveled>100 ||
			//abs_dist<0.2 ||
			dist_traveled/abs_dist <1 ||
		    pt_out.x*SPLAT_SCALE<-GRID_W || pt_out.x*SPLAT_SCALE>GRID_W*2 ||
			pt_out.y*SPLAT_SCALE<-GRID_H || pt_out.y*SPLAT_SCALE>GRID_H*2 ||
			pt_out.z*SPLAT_SCALE<-GRID_D || pt_out.z*SPLAT_SCALE>GRID_D*2)
			{
				my_rnd=hash_seed(my_rnd);
				pt_out=calculate_origin_point(my_rnd);
				pt_out.w=0;
			}
		point_list_output[i]=pt_out;
		output_random[i]=my_rnd;
	}
}
__kernel void splat(__global float4* point_list,__global float4* input_voxels,__global float4* output_voxels,int need_reset)
{
	int i=get_global_id(0);
	int max=GRID_W*GRID_H*GRID_D;
	float3 grid_center=CUBE_CENTER;
	float3 grid_size=(float3)(2);
	float3 grid_cell_size=(float3)(grid_size.x/GRID_W,grid_size.y/GRID_H,grid_size.z/GRID_D);
	if(i>=0 && i<max)
	{
		int3 pos;
		pos.x=i%GRID_W;
		pos.y=i%(GRID_W*GRID_H)/GRID_W;
		pos.z=i/(GRID_W*GRID_H);
		int3 center;
		center.x=GRID_W/2;
		center.y=GRID_H/2;
		center.z=GRID_D/2;
#if 0 //debug basic splat


		int3 delta=pos*SPLAT_SCALE-center;
		delta*=delta;
		int wsq=(GRID_W/2)*(GRID_W/2);
		int wsq2=(GRID_W/4)*(GRID_W/4);
		if(delta.x+delta.y+delta.z<wsq)
		{
			if(delta.x+delta.y+delta.z<wsq2)
				output_voxels[i]=(float4)(1.0f,0.0f,1.0f,0.1f);
			else
				output_voxels[i]=(float4)(1.0f,0.0f,0.0f,0.01f);
		}
		else
		{
			output_voxels[i]=(float4)(0.0f,0.0f,0.0f,0.0f);
		}

#elif 0 //debug wall splat
		int3 delta=pos-center;
		if(abs(delta.x)<2)
			output_voxels[i]=(float4)(0.125f,0.0f,0.0f,1.0f);
#else
		float4 accumulated_color=(float4)(0);
		if(need_reset==0)
			accumulated_color=input_voxels[i];
		float3 cell_start=convert_float3(pos-center)*grid_cell_size-grid_center;
		for(int j=0;j<POINT_COUNT;j++)
		{
			float3 delta=point_list[j].xyz*SPLAT_SCALE-cell_start;
			if( point_list[j].w>0 &&
			    delta.x>0 && delta.x<grid_cell_size.x &&
				delta.y>0 && delta.y<grid_cell_size.y &&
				delta.z>0 && delta.z<grid_cell_size.z)
				{
					accumulated_color+=(float4)(1.0f,1.0f,1.0f,1.0f)*point_list[j].w;
				}
		}
		accumulated_color.w=1;
		output_voxels[i]=accumulated_color;
#endif
	}
}

float4 raycast_voxels3(__global float4* voxels,float3 ray_start,float3 ray_direction)
{
	float4 ret=(float4)(0);
	for(int step=0;step<MAX_STEPS;step++)
	{
		float3 world_pixel=ray_start+ray_direction*(1+convert_float(step)/MAX_STEPS);

		int3 voxel_pos;
		voxel_pos.x=world_pixel.x*GRID_W;
		voxel_pos.y=world_pixel.y*GRID_H;
		voxel_pos.z=world_pixel.z*GRID_D;
		float4 data;
		if(voxel_pos.x<0 || voxel_pos.x>=GRID_W || voxel_pos.y>0 || voxel_pos.y>=GRID_H || voxel_pos.z<0 || voxel_pos.z>=GRID_D)
			data=(float4)(0.0f,0.0f,0.0f,0.0f);
		else
		{
			int voxel_id=voxel_pos.x+voxel_pos.y*GRID_W+voxel_pos.z*GRID_W*GRID_H;
			data=voxels[voxel_id];
		}
		ret+=data*data.w;
	}
	return ret;
}
float4 sample_voxels(__global float4* voxels,float3 coord)
{
	int3 voxel_pos=convert_int3(coord);
	float4 data;
	if(voxel_pos.x<0 || voxel_pos.x>=GRID_W || voxel_pos.y<0 || voxel_pos.y>=GRID_H || voxel_pos.z<0 || voxel_pos.z>=GRID_D)
	{
		float4 ret=(float4)(0.0f,0.0f,0.0f,1.0f);
		/*
		if(voxel_pos.x<0)// || voxel_pos.x>=GRID_W)
			ret.x=1;
		if(voxel_pos.y<0)// || voxel_pos.y>=GRID_H)
			ret.y=1;
		if(voxel_pos.z<0)// || voxel_pos.z>=GRID_D)
			ret.z=1;
		*/
		data=ret;
	}
	else
	{
		int voxel_id=voxel_pos.x+voxel_pos.y*GRID_W+voxel_pos.z*GRID_W*GRID_H;
		data=voxels[voxel_id];
	}
	return data;
}
float4 sample_voxels_normed(__global float4* voxels,float3 normed_coord)
{
	int3 voxel_pos=convert_int3(normed_coord*(float3)(GRID_W,GRID_H,GRID_D));
	float4 data;
	if(voxel_pos.x<0 || voxel_pos.x>=GRID_W || voxel_pos.y<0 || voxel_pos.y>=GRID_H || voxel_pos.z<0 || voxel_pos.z>=GRID_D)
		data=(float4)(0.0f,0.0f,0.0f,0.0f);
	else
	{
		int voxel_id=voxel_pos.x+voxel_pos.y*GRID_W+voxel_pos.z*GRID_W*GRID_H;
		data=voxels[voxel_id];
	}
	return data;
}
bool ray_intersects_aabb(float3 ray_origin, float3 ray_inv_direction,
                         float3 box_min, float3 box_max,
                         float* t_near, float* t_far)
{

    float3 t1 = (box_min - ray_origin) * ray_inv_direction;
    float3 t2 = (box_max - ray_origin) * ray_inv_direction;

    float3 t_min = fmin(t1, t2);
    float3 t_max = fmax(t1, t2);


    float t_enter = fmax(fmax(t_min.x, t_min.y), t_min.z);
    float t_exit = fmin(fmin(t_max.x, t_max.y), t_max.z);

    *t_near = t_enter;
    *t_far = t_exit;

    return t_exit >= t_enter && t_exit > 0.0f;
}
float tonemap(float Y)
{
	float white_point=0.0000001;
	float lum_white=pow(10,white_point);
	if(white_point<0)
    	Y = Y / (1 + Y); //simple compression
	else
    	Y = (Y*(1 + Y / lum_white)) / (Y + 1); //allow to burn out bright areas
    return Y;
}
float4 raycast_voxels(__global float4* voxels,float3 ray_start,float3 ray_direction,float brightness)
{
	float t_near;
	float t_far;
	float3 world_scale=(float3)(GRID_W,GRID_H,GRID_D);
	if(ray_intersects_aabb(ray_start*world_scale,1/ray_direction,(float3)(0,0,0),world_scale,&t_near,&t_far))
		{
			float4 ret=(float4)(0);
			t_near=max(t_near,0.0f);

			float3 cur_pos=(t_near+0.5f)*ray_direction+ray_start*world_scale;
			float3 tdelta=fabs(1/ray_direction);
			//distance to separating planes
			float3 s=((sign(ray_direction)*(floor(cur_pos)-cur_pos+0.5f))+0.5f)*tdelta;
			float t=0; //actual t in ray_start+(t+t_near)*ray_direction

			for(int i=0;i<MAX_STEPS;i++)
			{
				float3 mask=convert_float3((-1)*islessequal(s,min(s.yzx,s.zxy)));
				float u=min(min(s.x,s.y),s.z);
				float step=u-t;
				t=u;
				//why step is ~0
				//why so many invalid accesses???! -> probably entry nudge was needed?
				float4 data=sample_voxels(voxels,floor(cur_pos))*step;
				//float4 data=(float4)(1,0,0,1)*step;
				s+=tdelta*mask;
				cur_pos+=sign(ray_direction)*mask;
				//if(data.x>0.001)
				//	data.x=1/data.x;
				ret+=data;
				if (t>t_far){
					//ret=(float4)(0,0,1,1); //Debug if we see all of it
					break;
				}
			}
			ret=log(ret+(float4)(M_E_F))-(float4)(1);
			//ret.x*=1/(1+ret.x);
			//ret=pow(fabs(ret),1/4.0f);
			ret*=brightness;
			ret.x=tonemap(ret.x);

			ret.w=1;
			return ret;
		}
	else
		return (float4)(0.25f,0.25,0.25,1.0f);
}
float4 raycast_voxels2(__global float4* voxels,float3 ray_start,float3 ray_direction)
{
	float t_near;
	float t_far;

	if(ray_intersects_aabb(ray_start,1/ray_direction,(float3)(0,0,0),(float3)(1,1,1),&t_near,&t_far))
		{
			float d=t_far-t_near;
			float3 start_pos=t_near*ray_direction+ray_start;
			float3 adir=fabs(ray_direction);
			float3 step_amount=fmax(fmax(adir.x,adir.y),adir.z);
			float3 normed_step=(ray_direction/step_amount)/GRID_W;
			float4 ret=(float4)(0);

			float3 s=(dot(sign(ray_direction),(floor(start_pos)-start_pos+(float3)(0.5f)))+0.5f)*normed_step;
			//ret.x=0.2;
			for(int i=0;i<MAX_STEPS;i++)
			{
				int3 mask=islessequal(s,min(s.yzx,s.zxy));

				float3 sample_pos=start_pos+normed_step*i;
				float4 data=sample_voxels(voxels,sample_pos);
				ret+=data*data.w;
				//ret+=data;
				//ret+=(float4)(data.w);
				//if(data.w>0)
					//ret+=(float4)(0,0,0.01f,1.0f);
					//ret.z+=0.03f;
			}
			ret.w=1;
			return ret;
		}
	else
		return (float4)(0.0f,0.0,0.25,1.0f);
}

__kernel void render(__global float4* input_voxels,	__write_only image2d_t output_tex,float x_rot,float y_rot,float brightness)
{
	int i=get_global_id(0);
	int max=VIEW_W*VIEW_H;
	float view_dist=2;
	float view_angle=x_rot*M_PI*2;
	float view_angle2=y_rot*M_PI*2;
	float3 up_dir=(float3)(0.0f,0.0f,1.0f);
	up_dir=normalize(up_dir);
	//float3 view_pos=(float3)(cos(view_angle)*view_dist,sin(view_angle)*view_dist,0.5f);
	float3 offset=(float3)(0.5f,0.5f,.5f);

	float3 view_ray=rotate_around((float3)(1.0f,0.0f,0.0f),up_dir,view_angle);
	view_ray=normalize(view_ray);

	float3 right_dir=cross(view_ray,up_dir);
	view_ray=rotate_around(view_ray,right_dir,view_angle2);
	view_ray=normalize(view_ray);

	float3 up_dir_modified=cross(right_dir,view_ray);

	float3 view_pos=-view_ray*view_dist+offset;
	float2 screen_size=(float2)(1.0,1.0)*0.4f; //probably should match texture aspect ration at least...
	if(i>=0 && i<max)
	{
		int2 pos;

		pos.x=i%VIEW_W;
		pos.y=i/VIEW_W;

		float2 normed_pos;
		normed_pos.x=convert_float(pos.x)/(VIEW_W);
		normed_pos.y=convert_float(pos.y)/(VIEW_H);

		//pixel to cast ray to in world coords
		float3 cur_view_ray=view_ray+right_dir*(normed_pos.x-.5f)*2*screen_size.x+up_dir_modified*(normed_pos.y-.5f)*2*screen_size.y;
		cur_view_ray=normalize(cur_view_ray);

		float4 data=raycast_voxels(input_voxels,view_pos,cur_view_ray,brightness);
		/*
		float4 col=(float4)(1.0f,0.f,0.f,0.f);
		if (pos.x>VIEW_W/4 && pos.x<3*VIEW_W/4 && pos.y>VIEW_H/4 && pos.y<3*VIEW_H/4)
		{
			col=(float4)(0.0f,0.f,0.f,0.f);
		}
		*/

		data.w=1.0;
		write_imagef(output_tex,pos,data);
	}
}
]==]
function update_kernels()
cl_kernels=opencl.make_program(advance_format(kernel_base,{
	GRID_W=grid_size[1],
	GRID_H=grid_size[2],
	GRID_D=grid_size[3],
	VIEW_W=view_w,
	VIEW_H=view_h,
	POINT_COUNT=point_count,
}))
end
update_kernels()

draw_field=init_draw_field(advance_format(
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
    vec3 c=palette(0,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
    color=vec4(data.xyz,1);
}
]==],{}),
{
    uniforms={
    },
    textures={
    	tex_main={texture=texture}
    },
}
)

function init_buffer(  )
	local maxint=4294967295
	local seed_random=cl_kernels.seed_random
	seed_random:set(0,point_data_rnd[1])
	seed_random:set(1,point_data[1])
	seed_random:seti(2,math.random(0,maxint),math.random(0,maxint),math.random(0,maxint),math.random(0,maxint))
	seed_random:run(point_count)
end
function advance_random()
	local adv_random=cl_kernels.advance_random
	adv_random:set(0,point_data_rnd[1])
	adv_random:set(1,point_data_rnd[2])
	adv_random:run(point_count)
	point_data_rnd:swap()
end
function point_step()
	local point_iterate=cl_kernels.point_iterate
	point_iterate:set(0,point_data[1])
	point_iterate:set(1,point_data_rnd[1])
	point_iterate:set(2,point_data[2])
	point_iterate:set(3,point_data_rnd[2])
	point_iterate:run(point_count)
	point_data:swap()
	point_data_rnd:swap()
end
function put_points( need_reset )
	local splat=cl_kernels.splat
	splat:set(0,point_data[1])
	splat:set(1,grid_field[1])
	splat:set(2,grid_field[2])
	if need_reset then
		splat:seti(3,1)
	else
		splat:seti(3,0)
	end
	splat:run(grid_size[1]*grid_size[2]*grid_size[3])
	grid_field:swap()
end
function draw(  )
	--draw_field:update_uniforms(color_info)
	local update_texture=cl_kernels.render
	--update_texture:set(0,cell_food_fields[1])
	update_texture:set(0,grid_field[1])
	update_texture:set(1,display_buffer)
	update_texture:set(2,config.x_rot)
	update_texture:set(3,config.y_rot)
	update_texture:set(4,config.brightness)
	display_buffer:aquire()
	update_texture:run(view_w*view_h)
	display_buffer:release()
    draw_field.draw()
    if not config.pause then
	    config.x_rot=config.x_rot+0.001
	    if config.x_rot>1 then
	    	config.x_rot=0
	    end
	end
end
function save_img(  )
    img_buf_save=make_image_buffer(view_w,view_h)
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    img_buf_save:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end

local need_step=false
local need_save=0
local max_count_steps=100
local cur_count_steps=0
function update(  )
	__clear()
    __no_redraw()

    imgui.Begin("IFS3")
    draw_config(config)
    if imgui.Button("Reset") then
    	init_buffer()
    	put_points(true)
    end
    if imgui.Button("Step") then
    	init_buffer()
    	put_points(false)
    end
    -- [[
    cur_count_steps=cur_count_steps+1
    if cur_count_steps>=max_count_steps then
    	cur_count_steps=0
    	init_buffer()
    	--advance_random()
    end
    --]]
    if not config.pause_points then
	    --advance_random()
	    point_step()

	    put_points(false)
	end
    --if not config.pause or need_step then
    --	sim_tick()
    --	need_step=false
    --end
    draw()
    if imgui.Button("Save") then
    	need_save=1
    	--config.x_rot=config.x_rot+0.001
    end
 	if need_save>0 then
    	save_img()
    	if need_save>0 then need_save=need_save-1 end
    end
    imgui.End()
end