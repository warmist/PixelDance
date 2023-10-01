--[[
	game mechanic exploration based on crystals and crystal-based lifeform.

	factorio like with some rts features. Maybe some procedural generated abilities and co.

	crystal like because this is rewareded:
		- repeating structure
		- symmetries
		- scale symmetry? (hard to imagine how that would work)

	Game phases:
		* expansion
			- grow from seed
			- build infrastructure
			- start the tech tree
		* encounter
			- enemy faction encounter
			- battle over resources and survival
		* domination
			- fully conquer the field
			- exploit resources and optimize the build
		* spore creation
			- final creation to change the next start
			- sort-of-idle game mechanic of reincarnation/meta progression
			- meta progression of targets?
				- asteroid (i.e. tutorial?)
				- moon
				- planet
				- gas giant
				- star
				- neutron star
				- black hole

	Mechanics:
		* crystal grid
			- stuff like some structures must be placed in a grid now there are multiple choices
		* resources
			- energy-like - has no direct map location. "alive" tiles can store for no cost
				- transport energy e.g. diagonally
			- matter-like - takes up space. storages have dedicated place for it. Movement is difficult?
			- research-like ?
				- could be connection limited (i.e. must have N connections to "grow")
			- supply-like (i.e like in rts supplies) - max unit support
				- supply pixels e.g. two up, one right (thus enforce some sort of structure)
		* interactions
			- growth/assimilation
			- mining
			- energy creation
			- "research"
		* types of "constructions":
			- seed/main crystal - big, has multiple abilities
			- storage crystals
			- support/supply
			- mining?
			- growth?
--]]


require "common"
local ffi=require "ffi"
local w=256
local h=256
local cl_kernels=opencl.make_program[==[
#line __LINE__
#define W 256
#define H 256
int2 clamp_pos(int2 p)
{
	return clamp(p,0,W-1);
}
int pos_to_index(int2 p)
{
	int2 p2=clamp_pos(p);
	return p2.x+p2.y*W;
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
__kernel void update_grid(__global float* input,__global float* output,__write_only image2d_t output_tex,float time)
{
	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	int D=64;
	float a=1;
	float b=-1;
	float c=0.75;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;

		float2 pos_normed;
		pos_normed.x=pos.x/(float)(W);//-0.5;
		pos_normed.y=pos.y/(float)(H);//-0.5;
		float size=0.125f;
		int2 int_part;
		int_part.x=(int)trunc(pos_normed.x/size);
		int_part.y=(int)trunc(pos_normed.y/size);
		pos_normed.x=fmod(pos_normed.x,size);
		pos_normed.y=fmod(pos_normed.y,size);
		if(int_part.x%2==0)
		{
			pos_normed.x*=-1;
			//pos_normed.x-=0.5;
		}
		if(int_part.y%2==0)
		{
			pos_normed.y*=-1;
			//pos_normed.y-=0.5;
		}
		output[i]=0;
		float dist_to_line=fabs(a*pos_normed.x+b*pos_normed.y+c)/sqrt(a*a+b*b);
		float4 col;

		col.x=fmod(dist_to_line*25,1);
		col.w=1;
		write_imagef(output_tex,pos,col);
		//output_tex[i]=output[i];
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

		float2 delta=convert_float2(pos-(int2)(W,H)/2)/W;
		float distance=clamp(dot(delta,delta),0.0f,1.0f);
		if(distance>0.01)
			output[i]=0.5;
		else
			output[i]=0;

	}
}
]==]
local buffers={
	opencl.make_buffer(w*h*4),
	opencl.make_buffer(w*h*4)
}
ffi.cdef[[
typedef struct { int32_t w,h; } size;
]]

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
	float v=texture(tex_main,normed).x;
	v=pow(v,2.2);
	//color=vec4(v,v,v,1);
	color.xyz=spectral_zucconi6(v);
	color.w=1;
}
]]
local time=0
local size=ffi.new("size")
function init_buffer(  )
	cl_kernels.init_grid:set(0,buffers[1])
	cl_kernels.init_grid:run(w*h)
end
init_buffer()
function update(  )
	__no_redraw()
	__clear()
	--cl tick
	--setup stuff
	size.w=w
	size.h=h
	local update_grid=cl_kernels.update_grid
	--update_grid:set(2,size)
	update_grid:set(0,buffers[1])
	update_grid:set(1,buffers[2])
	update_grid:set(2,display_buffer)
	update_grid:set(3,time)
	--  run kernel
	display_buffer:aquire()
	update_grid:run(w*h)
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
	local b=buffers[2]
	buffers[2]=buffers[1]
	buffers[1]=b
	time=time+0.00001
end