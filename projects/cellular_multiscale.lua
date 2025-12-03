--[[
	CA with additional links to other scales
--]]
require "common"
local ffi=require "ffi"
local w=256
local h=256

config=make_config({
	{"paused",false,type="bool"},
	{"field_mult",1,type="float",min=1,max=10},
},config)


local cl_kernels=opencl.make_program[==[
#line __LINE__


#define CELL_MASK(X) (1<<X)
#define HAS_CELL(X,Y) ((X & CELL_MASK(Y))!=0)

#define W 256
#define H 256
#define M_PI 3.1415926538
#define BIGGER_SCALE_RECT 2
#define RULES_RECT 1

int2 clamp_pos(int2 p)
{
	return clamp(p,0,W-1);
}
int pos_to_index(int2 p)
{
	int2 p2=clamp_pos(p);
	return p2.x+p2.y*W;
}

int sample_at_pos_int(__global int* arr,int2 p)
{
	if(p.x<0) p.x=W+p.x;
	if(p.x>=W) p.x=p.x-W;
	if(p.y<0) p.y=H+p.y;
	if(p.y>=H) p.y=p.y-H;
	return arr[pos_to_index(p)];
}

int count_majority(__global int* arr,int type,int2 pos)
{
	int count=0;
	for(int dx=-BIGGER_SCALE_RECT;dx<=BIGGER_SCALE_RECT;dx++)
	for(int dy=-BIGGER_SCALE_RECT;dy<=BIGGER_SCALE_RECT;dy++)
		if(sample_at_pos_int(arr,pos+(int2)(dx,dy))==type)
			count+=1;
		else
			count-=1;
	return count;
}
int count_around(__global int* arr,int type,int2 pos)
{
	int ret=0;
	for(int dx=-RULES_RECT;dx<=RULES_RECT;dx++)
	for(int dy=-RULES_RECT;dy<=RULES_RECT;dy++)
		if(dx!=0 || dy!=0)
			if(sample_at_pos_int(arr,pos+(int2)( dx, dy))==type)
				ret+=1;

	if (count_majority(arr,type,pos)>0)
		ret+=1;
	//ret+=count_majority(arr,type,pos)/6;
	return ret;
}



int mask_around(__global int* arr,int2 pos)
{
	int ret=0;

	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( 0, 1)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( 0, -1)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( 1, 0)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( -1, 0)));

	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( 1, 1)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( 1, -1)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( -1, 1)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( -1, -1)));
	return ret;
}
int mask_around4(__global int* arr,int2 pos)
{
	int ret=0;

	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( 0, 1)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( 0, -1)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( 1, 0)));
	ret|=CELL_MASK(sample_at_pos_int(arr,pos+(int2)( -1, 0)));
	return ret;
}
#if 0 //conway
const rulebook0[]={
	0,0,0,1,0,0,0,0,0,
	0
};
const rulebook1[]={
	0,0,1,1,0,0,0,0,0,
	0
};
#elif 1 //coral
const rulebook0[]={
	1,0,0,0,0,0,0,0,0,
	0
};
const rulebook1[]={
	0,0,0,0,1,1,1,1,1,
	0
};
#elif 1 //anneal
const rulebook0[]={
	0,0,0,0,1,0,1,1,1,
	0
};
const rulebook1[]={
	0,0,0,1,0,1,1,1,1,
	0
};
#endif
__kernel void cell_update(
	__global int* cell_input,
	__global int* cell_output
	)
{
	int i=get_global_id(0);
	int max_i=W*H;

	if(i>=0 && i<max_i)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;

		int my_cell=cell_input[i];
		int count_cells=count_around(cell_input,1,pos);
		if(my_cell==0)
		{
			my_cell=rulebook0[count_cells];
		}
		else if(my_cell==1)
		{
			my_cell=rulebook1[count_cells];
		}
		cell_output[i]=my_cell;
	}
}
__kernel void update_texture(
	__global int* cell_input,
	__write_only image2d_t output_tex
	)
{
	int i=get_global_id(0);
	int max_i=W*H;

	if(i>=0 && i<max_i)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		int my_cell=cell_input[i];

		float4 col=(float4)(my_cell,0.f,0.f,0.f);

		write_imagef(output_tex,pos,col);
	}
}


float rand(float2 co){
	return sin(dot(co.xy ,(float2)(12342.9898,78515.233)) * 43758.5453)*0.5+0.5; }
float4 rnd_point4(float v,float seed)
{
	float4 ret;
	ret.x=0.5*(cos(99217*v+seed*1299-123.12938)+1);
	ret.y=0.5*(sin(10238*v+seed*2371+391.29389)+1);
	ret.z=0.5*(cos(-112983*v+seed*12993+111.1111)+1);
	ret.w=0;//0.5*(sin(10238*v+seed*2371+391.29389)+1);
	return ret;
}
uint lowbias32(uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}
float4 float_from_hash(uint4 val)
{
	return convert_float4(val)/(float4)(4294967295.0);
}
__kernel void init_cells(__global int* cells1,__global int* cells2)
{
	int i=get_global_id(0);
	int cw=10;
	int max=W*H;//s.w*s.h;
	float2 pos_root=(float2)(0,0.2);
	float2 pos_organ=(float2)(0,-0.2);
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float2 pos_normed;
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;
		int v=0;
		uint4 hash=(uint4)(i,0,0,0);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		#if 0
		if(  float_from_hash(hash).x>0.8)
			v=1;
		#endif
		#if 1
		if(  pos.x==W/2 && pos.y==H/2)
			v=1;
		#endif
		cells1[i]=v;
		cells2[i]=v;
	}
}
]==]

local need_reinit=(cell_fields==nil)
cell_fields=cell_fields or{
	opencl.make_buffer(w*h*4),
	opencl.make_buffer(w*h*4),
}

function swap_cells(  )
	local p=cell_fields[1]
	cell_fields[1]=cell_fields[2]
	cell_fields[2]=p
end
texture=textures:Make()
texture:use(1)
texture:set(w,h,FLTA_PIX)
local display_buffer=opencl.make_buffer_gl(texture)

shader=shaders.Make[[
#version 330
#line __LINE__

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float field_mult;


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

	float v= data.x;
   	v=v*field_mult;

   	vec3 c=palette(v,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));

    color=vec4(c,1);
}
]]
local time=0

function init_buffer(  )
	local init_cells=cl_kernels.init_cells
	init_cells:set(0,cell_fields[1])
	init_cells:set(1,cell_fields[2])
	init_cells:run(w*h)
end
if need_reinit then
	init_buffer()
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
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function is_mouse_down_0( ... )
	return __mouse.clicked0 and not __mouse.owned0, __mouse.x,__mouse.y
end


function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Electrons")
	draw_config(config)

	--cl tick
	--setup stuff
	-- [==[
	if not config.paused then
		local cell_update=cl_kernels.cell_update
		cell_update:set(0,cell_fields[1])
		cell_update:set(1,cell_fields[2])
		cell_update:run(w*h)
		swap_cells()
	end
	local update_texture=cl_kernels.update_texture
	update_texture:set(0,cell_fields[1])
	update_texture:set(1,display_buffer)
	display_buffer:aquire()
	update_texture:run(w*h)
	display_buffer:release()

	--opengl draw
	--  read from cl
	-- actually the kernel writes it itself...
	--  draw the texture
	shader:use()
	texture:use(1)
	shader:set_i("tex_main",1)
	shader:set("field_mult",config.field_mult)
	shader:draw_quad()
	if imgui.Button("Save") then
		save_img()
	end
	if imgui.Button("Reset") then
		init_buffer()
	end
end