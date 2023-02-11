require "common"
local ffi=require "ffi"
local w=1024
local h=1024
local cl_kernel=opencl.make_program[==[
#line __LINE__
#define W 1023
#define H 1023
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
float sum_around(__global float* arr,int2 pos)
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
__kernel void update_grid(__global float* input,__global float* output,__write_only image2d_t output_tex,float time)
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
		float distance=clamp(1-dot(delta,delta),0.0f,1.0f);
		float v=sum_around(input,pos);
		v=(ceil(v*255)+0.125)/255;
		//v=fmod(v,1);
		if(v>1)
			v=0;
		output[i]=v;
		
		float4 col;
		col.r=v;
		col.a=1;
		write_imagef(output_tex,pos,col);
		//output_tex[i]=output[i];
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
	color.a=1;
}
]]
local time=0
local size=ffi.new("size")
function update(  )
	__no_redraw()
	__clear()
	--cl tick
	--setup stuff
	size.w=w
	size.h=h
	--cl_kernel:set(2,size)
	cl_kernel:set(0,buffers[1])
	cl_kernel:set(1,buffers[2])
	cl_kernel:set(2,display_buffer)
	cl_kernel:set(3,time)
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
	local b=buffers[2]
	buffers[2]=buffers[1]
	buffers[1]=b
	time=time+0.00001
end