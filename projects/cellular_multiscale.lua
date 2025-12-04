--[[
	CA with additional links to other scales
	TODO:
		isotropic non-totalistic
			8+1 bits per state (last bit is "big scale majority")
			8+n bits (multiscale)
		some sort of alternative for majority?
			count above some X

--]]
require "common"
local ffi=require "ffi"
local w=256
local h=256

config=make_config({
	{"paused",false,type="bool"},
	{"steps_per_frame",1,type="int",min=1,max=100},
	{"field_mult",1,type="float",min=1,max=10},
	{"persist_mult",1,type="float",min=1,max=100},
},config)



local kernel_str=[==[
#line __LINE__


#define CELL_MASK(X) (1<<X)
#define HAS_CELL(X,Y) ((X & CELL_MASK(Y))!=0)

#define W 256
#define H 256
#define M_PI 3.1415926538
#define BIGGER_SCALE_RECT 3
#define USE_ROUND_REGION 0
#define LONG_RANGE_INFLUENCE 1
#define LONG_RANGE_COUNT_NON_EMPTY 1
#define RULES_RECT 1
#define MAX_PERSIST 1000
#define MAX_RULE 10

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
#if USE_ROUND_REGION
		if(dx*dx+dy*dy<BIGGER_SCALE_RECT*BIGGER_SCALE_RECT) //not perf nice
#endif
		{
			int cell=sample_at_pos_int(arr,pos+(int2)(dx,dy)) %% MAX_RULE;
#if LONG_RANGE_COUNT_NON_EMPTY
			if(cell>0) //TODO PERSIST HERE
#else
			if(cell)==type)
#endif
				count+=1;
			else
				count-=1;
		}
	return count;
}
int count_around(__global int* arr,int type,int2 pos)
{
	int ret=0;
	for(int dx=-RULES_RECT;dx<=RULES_RECT;dx++)
	for(int dy=-RULES_RECT;dy<=RULES_RECT;dy++)
		if(dx!=0 || dy!=0)
		{
			int cell=sample_at_pos_int(arr,pos+(int2)( dx, dy))%%MAX_RULE;
			//if(cell>0)//TODO PERSIST HERE
			if(cell==type)
				ret+=1;
		}
	int majority=count_majority(arr,type,pos);
	if (majority>0)
		ret+=LONG_RANGE_INFLUENCE;

	//if (majority<0)
	//	ret-=LONG_RANGE_INFLUENCE;
	//if (majority<-4)
	//	ret-=LONG_RANGE_INFLUENCE;
	ret=clamp(ret,0,9);
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
#if 0 //rand rules
%s
#elif 1 // very nice short term patterns
#define BIGGER_SCALE_RECT 3
#define USE_ROUND_REGION 0
#define LONG_RANGE_INFLUENCE 1
#define LONG_RANGE_COUNT_NON_EMPTY 1
#define RULES_RECT 1
#define MAX_PERSIST 1000
#define MAX_RULE 10
const rulebook0[]={
        0, 0, 1, 1, 0, 0, 1, 0, 0, 1
};
const rulebook1[]={
        0, 1, 1, 2, 1, 1, 1, 2, 1, 1
};
const rulebook2[]={
        2, 3, 2, 0, 3, 2, 2, 2, 2, 2
};
const rulebook3[]={
        3, 3, 3, 0, 3, 3, 3, 0, 3, 0
};

#elif 0 //short-term stable patterns
const rulebook0[]={
        0, 2, 1, 0, 0, 2, 3, 0, 0, 2
};
const rulebook1[]={
        0, 2, 0, 1, 1, 2, 3, 1, 1, 0
};
const rulebook2[]={
        0, 1, 1, 0, 2, 0, 0, 1, 1, 2
};
const rulebook3[]={
        2, 1, 2, 3, 3, 0, 0, 2, 2, 3
};
#elif 0 //rebuilding mazes?
#define BIGGER_SCALE_RECT 3
#define USE_ROUND_REGION 0
#define LONG_RANGE_INFLUENCE 1
#define LONG_RANGE_COUNT_NON_EMPTY 1
const rulebook0[]={
        0, 0, 1, 1, 1, 0, 0, 0, 1, 1
};
const rulebook1[]={
        0, 1, 0, 1, 1, 1, 1, 0, 1, 1
};
#elif 0 // coraling?
#define BIGGER_SCALE_RECT 3
#define USE_ROUND_REGION 0
#define LONG_RANGE_INFLUENCE 1
const rulebook0[]={
        2, 1, 3, 2, 3, 1, 1, 2, 3, 3
};
const rulebook1[]={
        0, 1, 0, 3, 0, 2, 1, 0, 3, 3
};
const rulebook2[]={
        2, 0, 3, 1, 0, 0, 3, 0, 2, 2
};
const rulebook3[]={
        3, 3, 3, 0, 3, 0, 1, 1, 1, 1
};
#elif 1 // sort-of-maze builders
const rulebook0[]={
        1, 0, 0, 0, 4, 5, 5, 0, 3, 5
};
const rulebook1[]={
        5, 1, 2, 4, 4, 2, 3, 2, 3, 0
};
const rulebook2[]={
        5, 1, 5, 3, 5, 3, 2, 5, 0, 5
};
const rulebook3[]={
        0, 3, 0, 2, 2, 2, 2, 3, 1, 5
};
const rulebook4[]={
        1, 4, 5, 5, 0, 0, 0, 2, 1, 3
};
const rulebook5[]={
        1, 2, 5, 4, 0, 0, 5, 1, 3, 4
};

#elif 0 //squiglies3 unstable
#define BIGGER_SCALE_RECT 3
#define USE_ROUND_REGION 0
#define LONG_RANGE_INFLUENCE 1
const rulebook0[]={
        0, 0, 1, 0, 0, 0, 0, 1, 0, 0
};
const rulebook1[]={
        0, 0, 1, 1, 1, 0, 0, 1, 0, 1
};

#elif 0 //squiglies2
#define BIGGER_SCALE_RECT 3
#define USE_ROUND_REGION 0
#define LONG_RANGE_INFLUENCE 1
const rulebook0[]={
        0, 1, 0, 0, 0, 0, 0, 0, 1, 0
};
const rulebook1[]={
        1, 0, 1, 1, 0, 1, 1, 1, 0, 1
};
#elif 0 //mazes like
#define BIGGER_SCALE_RECT 5
#define USE_ROUND_REGION 1
#define LONG_RANGE_INFLUENCE 1
const rulebook0[]={
        1, 0, 1, 0, 1, 0, 0, 0, 0, 1
};
const rulebook1[]={
        0, 1, 1, 1, 1, 1, 0, 0, 1, 0
};
#elif 1 //strange only stable if symetric start conditions?
/*
#define BIGGER_SCALE_RECT 5
#define USE_ROUND_REGION 1
#define LONG_RANGE_INFLUENCE -1
*/
const rulebook0[]={
        1, 1, 0, 1, 1, 1, 0, 0, 1, 0
};
const rulebook1[]={
        1, 1, 1, 1, 1, 1, 0, 1, 0, 0
};
#elif 1 //semi stable @10 range rounded
const rulebook0[]={
        1, 0, 0, 1, 0, 1, 0, 0, 0,0
};
const rulebook1[]={
        1, 1, 0, 0, 1, 1, 1, 0, 1,1
};
#elif 0 //forts?
const rulebook0[]={
        0, 1, 1, 1, 1, 1, 0, 0, 0
};
const rulebook1[]={
        0, 1, 0, 1, 1, 1, 1, 1, 0
};
#elif 0 //squiglies
const rulebook0[]={
        0, 1, 0, 0, 0, 0, 0, 1, 1
};
const rulebook1[]={
        0, 0, 1, 1, 0, 0, 1, 0, 0
};
#elif 0 //conway
const rulebook0[]={
	0,0,0,1,0,0,0,0,0,
	0
};
const rulebook1[]={
	0,0,1,1,0,0,0,0,0,
	0
};
#elif 0 //blinking coral
const rulebook0[]={
	1,0,0,0,0,0,0,0,0,
	0
};
const rulebook1[]={
	0,0,0,0,1,1,1,1,1,
	0
};
#elif 1
const rulebook0[]={
	0,0,0,1,1,1,0,0,0,
	0
};
const rulebook1[]={
	0,0,0,0,1,1,1,0,0,
	1
};
#elif 0 //coral
const rulebook0[]={
	0,0,0,1,0,0,0,0,0,
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
		pos.x=i%%W;
		pos.y=i/W;

		int my_cell=cell_input[i];
		int count_cells=count_around(cell_input,1,pos);
		int new_cell=my_cell %% MAX_RULE;
		if(new_cell==0)
		{
			new_cell=rulebook0[count_cells];
		}
		else if(new_cell==1)
		{
			new_cell=rulebook1[count_cells];
		}
		else if(new_cell==2)
		{
			new_cell=rulebook2[count_cells];
		}
		else if(new_cell==3)
		{
			new_cell=rulebook3[count_cells];
		}
		/*else if(new_cell==4)
		{
			new_cell=rulebook4[count_cells];
		}
		else if(new_cell==5)
		{
			new_cell=rulebook5[count_cells];
		}*/
#if MAX_PERSIST
		if (new_cell==(my_cell %% MAX_RULE) && new_cell!=0)
		{
			new_cell=my_cell+MAX_RULE;
			if(new_cell/MAX_RULE>MAX_PERSIST)
			{
				new_cell=MAX_RULE*MAX_PERSIST+new_cell%%MAX_RULE;
			}
		}
#endif
		cell_output[i]=new_cell;
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
		pos.x=i%%W;
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
		pos.x=i%%W;
		pos.y=i/W;
		float2 pos_normed;
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;
		int v=0;
		uint4 hash=(uint4)(i,0,0,0);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		#if 1
		if( true
			//&& float_from_hash(hash).x>0.1
			&& length(pos_normed)<0.05
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))<0.1
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))>0.05
			//&& fabs(pos_normed.y)<0.05
			&& pos_normed.y<0.01
			//&& fabs(pos_normed.y)>0.084
			//&& (pos.y%%64==(32) || pos.y%%64==(32))
		)
			v=1;
		#endif
		#if 0
		if( true
			&& length(pos_normed)<0.07
		)
			v=1;
		#endif
		#if 0
		if(	true
			//&& pos.x==W/2 && hash.x%%8==0)
			&& pos.x==W/2 && pos.y==H/2)
			v=1;
		#endif
		cells1[i]=v;
		cells2[i]=v;
	}
}
]==]
local rand_rules
local transition_matrix={
	[0]={0.4,0.6,0,0},
	[1]={0.125,0.75,0.125,0},
	[2]={0.125,0,0.75,0.125},
	[3]={0.25,0,0,0.75},
}
function get_transition(id_from)
	local chance=transition_matrix[id_from]
	local rnd=math.random()
	local chance_sum=0
	for i=1,#chance do
		chance_sum=chance_sum+chance[i]
		if rnd<chance_sum then
			return i-1
		end
	end
	return #chance-1
end

function gen_rand_rules( )
	local max_rule=3
	local rules_base={}
	for rule_id=0,max_rule do
		local rules={}
		for i=1,10 do --0 to 8 +1 =>10
			if i==1 and rule_id==0 then
				rules[i]=0
			else
				rules[i]=get_transition(rule_id)
				--rules[i]=math.random(0,max_rule)
			end
		end
		table.insert(rules_base,string.format("const rulebook%d[]={\n\t%s\n};\n",rule_id,table.concat( rules, ", ")))
	end

	return table.concat( rules_base, "")
end
local cl_kernels
function randomize_rules()
	rand_rules=gen_rand_rules()
	print(rand_rules)
	local final_kernel_str=string.format(kernel_str,rand_rules)
	cl_kernels=opencl.make_program(final_kernel_str)
end
randomize_rules()
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

#define MAX_PERSIST 1000.0
#define MAX_RULE 10.0
#define MAX_VALUE 3.0
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float field_mult;
uniform float persist_mult;


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
    float v_cell=mod(data.x,MAX_RULE)/MAX_VALUE;
	float v= (data.x/MAX_RULE)/MAX_PERSIST;
	v_cell=v_cell+v/MAX_VALUE;
   	//v_cell=v_cell*field_mult;
   	v_cell=v_cell+field_mult;

   	//vec3 c=palette(v_cell,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
   	//vec3 c=palette(mod(v_cell+0.5,1.0),vec3(0.5),vec3(0.5),vec3(1.0),vec3(0.0,0.1,0.2));
   	vec3 c=palette(mod(v_cell+0.50,1.0),vec3(0.5),vec3(0.5),vec3(1.0,0.7,0.4),vec3(0.0,0.15,0.2));
   	//c=c*v*persist_mult;
   	c=c*pow(v,persist_mult);
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
	if not config.paused or imgui.Button("Step") then
		for i=1,config.steps_per_frame do
			local cell_update=cl_kernels.cell_update
			cell_update:set(0,cell_fields[1])
			cell_update:set(1,cell_fields[2])
			cell_update:run(w*h)
			swap_cells()
		end
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
	shader:set("persist_mult",config.persist_mult)
	shader:draw_quad()
	if imgui.Button("Save") then
		save_img()
	end
	if imgui.Button("Reset") then
		init_buffer()
	end
	if imgui.Button("Rand") then
		randomize_rules()
		init_buffer()
	end
end