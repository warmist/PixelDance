--[===[
	Basic idea:
		* have some state+output as in normal CA
		* instead of output being 0 or 1 it's float 0 to 1
		* then you can have slider between 0 and 1 for which level set to look into
			* each state could be given number from 0 to max_state
			* then it's same as float 0 to 1 but each int is different "set" of 1
		* or you could simulate each cell as "count of cells that would be on/off after one step" and show that
--]===]
require "common"

local ffi=require "ffi"
local w=512
local h=512

config=make_config({
	{"paused",false,type="bool"},
	{"steps_per_frame",1,type="int",min=1,max=100},
	{"field_mult",1,type="float",min=1,max=10},
	{"persist_mult",1,type="float",min=0.00001,max=1},
	{"persist_pow",1,type="float",min=0.01,max=2},
	{"density",0.5,type="float",min=0,max=1},
	{"c_x",0.5,type="float",min=0,max=1},
	{"c_y",0.5,type="float",min=0,max=1},
	{"s_x",1.0,type="float",min=0,max=1},
	{"s_y",1.0,type="float",min=0,max=1},
	{"mapping",true,type="bool"},
},config)

local RULE_SIZE=10
local kernel_str=[==[
#line __LINE__

#define W $W_SIZE
#define H $H_SIZE
//#define M_PI 3.1415926538 use M_PI_F

#define MAX_RULE 100
#define COUNT_TYPES 2

#define BORDER_CLAMP 0
#define BORDER_MIRROR 0
#define BORDER_ZERO 1

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
float float_from_hash(uint val)
{
	return convert_float(val)/(float)(4294967295.0);
}

float4 float4_from_hash4(uint4 val)
{
	return convert_float4(val)/(float4)(4294967295.0);
}

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
#if BORDER_CLAMP
	p.x=clamp(p.x,0,W-1);
	p.y=clamp(p.y,0,H-1);
#elif BORDER_MIRROR
	if(p.x<0) p.x=-p.x;
	if(p.y<0) p.y=-p.y;
	if(p.y>=H) p.y=2*H-p.y-1;
	if(p.x>=W) p.x=2*W-p.x-1;
#elif BORDER_ZERO
	if(p.x<0) return 0;
	if(p.y<0) return 0;
	if(p.y>=H) return 0;
	if(p.x>=W) return 0;
#else
	if(p.x<0) p.x=W+p.x;
	if(p.x>=W) p.x=p.x-W;
	if(p.y<0) p.y=H+p.y;
	if(p.y>=H) p.y=p.y-H;
#endif
	return arr[pos_to_index(p)];
}
float sample_at_pos_float(__global float* arr,int2 p)
{
#if BORDER_CLAMP
	p.x=clamp(p.x,0,W-1);
	p.y=clamp(p.y,0,H-1);
#elif BORDER_MIRROR
	if(p.x<0) p.x=-p.x;
	if(p.y<0) p.y=-p.y;
	if(p.y>=H) p.y=2*H-p.y-1;
	if(p.x>=W) p.x=2*W-p.x-1;
#elif BORDER_ZERO
	if(p.x<0) return 0;
	if(p.y<0) return 0;
	if(p.y>=H) return 0;
	if(p.x>=W) return 0;
#else
	if(p.x<0) p.x=W+p.x;
	if(p.x>=W) p.x=p.x-W;
	if(p.y<0) p.y=H+p.y;
	if(p.y>=H) p.y=p.y-H;
#endif
	return arr[pos_to_index(p)];
}
#if 1 //rand rules
$RULE_DEF
#elif 1
const float rulebook_0[]={0.6,0.6,0.6,0.0,0.6,0.6,0.6,0.6,0.6,0.6,0.6,0.6,0.0,0.6,0.6,0.6,0.6,0.6};
const float rulebook_1[]={0.6,0.6,0.0,0.0,0.6,0.6,0.6,0.6,0.6,0.6,0.6,0.0,0.0,0.6,0.6,0.6,0.6,0.6};
#endif

#define NEIGH8 1
#define RULES_RECT $RULE_SIZE
/*	versions for count_around:
	* totalistic x by x
	* rings of dist r (circular-ish)
	* rings (rect) with different weights (e.g. first ring 1, second ring 1/4, third 1/32)
	* orbitals (some sort of patterns that fill space around)
*/
int count_around(__global float* arr,int2 pos,float thresh)
{
	int ret=0;
#if NEIGH8
	for(int dx=-RULES_RECT;dx<=RULES_RECT;dx++)
	for(int dy=-RULES_RECT;dy<=RULES_RECT;dy++)
	{
#else
	int ddx[]={-1,1,0,0};
	int ddy[]={0,0,-1,1};
	for(int j=0;j<4;j++)
	{
		int dx=ddx[j];
		int dy=ddy[j];
#endif
		if(dx!=0 || dy!=0)

		{
			float cell=sample_at_pos_float(arr,pos+(int2)( dx, dy));
			if(fmod(cell,MAX_RULE)>thresh)
				ret+=1;
		}
	}
	return ret;
}
int full_rules(__global float* arr,int2 pos,float thresh)
{
	int ret=0;
	int id=0;
#if NEIGH8
	for(int dx=-RULES_RECT;dx<=RULES_RECT;dx++)
	for(int dy=-RULES_RECT;dy<=RULES_RECT;dy++)
	{
#else
	int ddx[]={-1,1,0,0};
	int ddy[]={0,0,-1,1};
	for(int j=0;j<4;j++)
	{
		int dx=ddx[j];
		int dy=ddy[j];
#endif
		if(dx!=0 || dy!=0)

		{
			float cell=sample_at_pos_float(arr,pos+(int2)( dx, dy));
			if(fmod(cell,MAX_RULE)>thresh)
				ret+=1<<id;
			id++;
		}
	}
	return ret;
}
int count_around_complex(__global float* arr,int2 pos,float thresh)
{
	int ret=0;
#if NEIGH8
	for(int dx=-RULES_RECT;dx<=RULES_RECT;dx++)
	for(int dy=-RULES_RECT;dy<=RULES_RECT;dy++)
	{
#else
	int ddx[]={-1,1,0,0};
	int ddy[]={0,0,-1,1};
	for(int j=0;j<4;j++)
	{
		int dx=ddx[j];
		int dy=ddy[j];
#endif
		if(dx!=0 || dy!=0)
		{
			float cell=sample_at_pos_float(arr,pos+(int2)( dx, dy));
			if(fmod(cell,MAX_RULE)>thresh)
			{
				int ring=max(abs(dx),abs(dy));
				int ring_cell=abs(dx)+abs(dy)-ring;
				int ring_start_cell=((ring)*(3+ring))/2;
				int ring_offset=ring_start_cell*2+ring_cell;
				ret+=1<<ring_offset;
			}
		}
	}
	return ret;
}
int count_around_ring_simple(__global float* arr,int2 pos,float thresh)
{
#define SAMPLE() cell=sample_at_pos_float(arr,pos+(int2)( dx, dy)); if(fmod(cell,MAX_RULE)>thresh) alive++;
	int ret=0;
	for(int ring=1;ring<=RULES_RECT;ring++)
	{

		int count=0;
		int alive=0;
		float cell;
		for(int dx=-ring;dx<=ring;dx++)
		{
			int dy=-ring;
			count++;
			SAMPLE()
			dy=ring;
			count++;
			SAMPLE()
		}
		for(int dy=-ring;dy<=ring;dy++)
		{
			int dx=-ring;
			count++;
			SAMPLE()
			dx=ring;
			count++;
			SAMPLE()
		}
		if(alive>count/2)
			ret+=1;
	}
	return ret;
}
const float ring_weights[]={
	3,2,1,1,2,4,8,16
};

int count_around_rings(__global float* arr,int2 pos,float thresh)
{
	float ret=0;
#if NEIGH8
	for(int dx=-RULES_RECT;dx<=RULES_RECT;dx++)
	for(int dy=-RULES_RECT;dy<=RULES_RECT;dy++)
	{
#else
	int ddx[]={-1,1,0,0};
	int ddy[]={0,0,-1,1};
	for(int j=0;j<4;j++)
	{
		int dx=ddx[j];
		int dy=ddy[j];
#endif
		if(dx!=0 || dy!=0)

		{
			int ring=max(abs(dx),abs(dy));
			float cell=sample_at_pos_float(arr,pos+(int2)( dx, dy));
			if(fmod(cell,MAX_RULE)>thresh)
				ret+=ring_weights[ring]/(8.0f*(ring));
		}
	}
	return ret;
}
#if 0
float lookup_rule(int cur_cell,int configuration,uint seed,float bias)
{
	float rule_level=0;
	//Generated code goes here:
	//	basic idea
	//  else if(cur_cell==4) rule_level=rulebook_4[configuration];
	if(false);
	$RULE_IMPL
	return rule_level;
}
#else
float lookup_rule(int cur_cell,int configuration,uint seed,float bias)
{
	uint new_seed=seed+convert_uint(cur_cell)*12938;
	uint rnd1=lowbias32(new_seed);
	rnd1=lowbias32(rnd1);
	rnd1=lowbias32(rnd1^lowbias32(convert_uint(configuration)));
	float v=float_from_hash(rnd1);
	if(bias>0)
		return v*(1-bias)+bias;
	else
		return v*(1+bias);
}
#endif
#define TEST_RULETABLE 0
__kernel void cell_update(
	__global float* cell_input,
	__global float* cell_output,
	uint seed,
	float2 min_pos,
	float2 max_pos,
	uint mapping
	)
{
	int i=get_global_id(0);
	int max_i=W*H;

	if(i>=0 && i<max_i)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;

		float2 pos_normed;
		float2 pos_i=convert_float2(pos)-(float2)(W/2,H/2);
		pos_normed.x=pos.x/(float)(W);
		pos_normed.y=pos.y/(float)(H);

		float thresh_self=0.5;
		float thresh_other=0.5;
		float thresh_rule1=0.5;
		float thresh_rule2=0.5;
		float output_spread=0.0;
		float count_offset=0.0;
		float rule_bias1=1;
		float rule_bias2=1;
		//TODO: bias from around the target cell (i.e. w avg of around)
		const int count_diff=0;
#define MAPPINGX(var,value) if(mapping & value) var=min_pos.x+pos_normed.x*(max_pos.x-min_pos.x);
#define MAPPINGY(var,value) if(mapping & value) var=min_pos.y+pos_normed.y*(max_pos.y-min_pos.y);
		MAPPINGX(thresh_rule1,1)
		MAPPINGY(thresh_rule1,2)
		MAPPINGX(thresh_rule2,4)
		MAPPINGY(thresh_rule2,8)
		MAPPINGX(output_spread,16)
		MAPPINGY(output_spread,32)
		MAPPINGX(thresh_other,64)
		MAPPINGY(thresh_other,128)
		MAPPINGX(count_offset,256)
		MAPPINGY(count_offset,512)
		MAPPINGX(thresh_self,1024)
		MAPPINGY(thresh_self,2048)
		MAPPINGX(rule_bias1,4096)
		MAPPINGY(rule_bias1,8192)
		MAPPINGX(rule_bias2,16384)
		MAPPINGY(rule_bias2,32768)
		output_spread*=0.5;
		count_offset*=0.5;
		float my_value=fmod(cell_input[i],MAX_RULE);
		float persist_value=(cell_input[i]-my_value)/MAX_RULE;
		int cur_cell=0;
		if(my_value>thresh_self)
			cur_cell=1;
		float rule_bias=rule_bias1;
		if(cur_cell==1)
			rule_bias=rule_bias2;
		rule_bias=rule_bias*2-1;
		int configuration=count_around(cell_input,pos,thresh_other);
		//int configuration=count_around_rings(cell_input,pos,thresh_other);
		//int configuration=count_around_complex(cell_input,pos,thresh_other);
		//int configuration=count_around_ring_simple(cell_input,pos,thresh_other);
		//int configuration=full_rules(cell_input,pos,thresh_other);
		//configuration+=64;
		//configuration=clamp(configuration,0,(RULES_RECT*2+1)*(RULES_RECT*2+1));
		float rule_level=0;
		#if 0
		float wsum=0;
		for(int diff=-count_diff;diff<=count_diff;diff++)
		{
			if(diff!=0)
			{
				int id=configuration+diff;
				id=clamp(id,0,(RULES_RECT*2+1)*(RULES_RECT*2+1));
				rule_level+=lookup_rule(cur_cell,id,seed,rule_bias);
				wsum+=1;
			}
		}
		if(count_diff!=0)
		{
			rule_level/=wsum;
			rule_level*=count_offset;
		}
		#endif


		rule_level+=lookup_rule(cur_cell,configuration,seed,rule_bias);
		float new_cell=0;
		new_cell=rule_level;
		new_cell=clamp(new_cell,0.f,1.f);
//TODO: add off by 1 weighted by w

		int new_cell_type=0;

		float thresh_used=0;
		if(cur_cell==1)
		{
			thresh_used=thresh_rule1;
		}
		else
		{
			thresh_used=thresh_rule2;
		}
		if(new_cell-thresh_used>0)
			new_cell_type=1;
#if 1
		if(new_cell_type==cur_cell)
			persist_value+=1.0f;
		else
			persist_value=1;
#else
		if(new_cell_type!=cur_cell)
			persist_value=1;
#endif
#if 0
	//basic idea: remap output so that if we are very over thresh-> output close to 1
		//linear spread:
		if(new_cell>thresh_used)
		{
			float a=0.5/(output_spread*(1-thresh_used));
			new_cell=a*new_cell+0.5-a*thresh_used;
		}
		else
		{
			float a=0.5/(output_spread*thresh_used);
			float b=0.5-a*thresh_used;
			new_cell=new_cell*a;
		}
		new_cell=clamp(new_cell,0.0f,1.0f);
#elif 1 //smoothstep
		new_cell=smoothstep(thresh_used-output_spread/2,thresh_used+output_spread/2,new_cell);
#else
		new_cell=new_cell_type;
#endif
		//if(new_cell_type==1)
		//	new_cell=(new_cell-thresh_rule)/(1-thresh_rule);
#if TEST_RULETABLE
		int config_test=pos_normed.x*100;
		cell_output[i]=lookup_rule(0,config_test,seed,pos_normed.x*2-1);
#else
		cell_output[i]=new_cell+persist_value*MAX_RULE;
#endif
	}
}
__kernel void update_texture(
	__global float* cell_input,
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
#if TEST_RULETABLE
		float my_cell=cell_input[i];
		float4 col=(float4)(my_cell,1.0f,0.f,0.f);
#else
		float my_cell=fmod(cell_input[i],MAX_RULE);
		float persist=(cell_input[i]-my_cell)/MAX_RULE;
		//float persist=1;
		float4 col=(float4)(my_cell,persist,0.f,0.f);
#endif
		write_imagef(output_tex,pos,col);
	}
}



float repetition_rotational( float2 p, int n )
{
    float sp = 6.283185/(float)(n);
    float an = atan2(p.y,p.x);
    float id = floor(an/sp);

    float a1 = sp*(id+0.0);
    float a2 = sp*(id+1.0);
    float2 r1 = mat2(cos(a1),-sin(a1),sin(a1),cos(a1))*p;
    float2 r2 = mat2(cos(a2),-sin(a2),sin(a2),cos(a2))*p;

    return min( sdf(r1,id+0.0), sdf(r2,id+1.0) );
}
#define C_SIZE 5
#define C_OFFSET 25
#define C_SIZE2 4
#define C_OFFSET2 4
float2 rotated(float2 v, float angle)
{
	float2 ret;
	ret.x=v.x*cos(angle)-v.y*sin(angle);
	ret.y=v.x*sin(angle)+v.y*cos(angle);
	return ret;
}
bool asym_blob(float2 pos,float rotation)
{
	float2 bcenter=pos+rotated((float2)(C_OFFSET,C_OFFSET),rotation);
	return length(bcenter)<C_SIZE || length(bcenter-rotated((float2)(C_OFFSET2,0),rotation))<C_SIZE2;
}
__kernel void init_cells(__global float* cells1,__global float* cells2,float density)
{
	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float2 pos_normed;
		float2 pos_i=convert_float2(pos)-(float2)(W/2,H/2);
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;
		float v=0;
		uint hash=(uint)(i);
		hash=lowbias32(hash);
		hash=lowbias32(hash);
		hash=lowbias32(hash);

		#if 1
		if( true
			&& float_from_hash(hash)>density

			//&& length(pos_normed)<density
			//&& length(pos_normed)>0.5
			//&& fmod(length(pos_normed),0.4f)<0.3
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))<0.1
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))>0.05
			//&& fmax(fabs(pos_i.x),fabs(pos_i.y))<radius
			//&& pos_normed.y<0.01
			//&& pos_normed.y*pos_normed.x<0.00008
			//&& fabs(pos_normed.y)>0.084
			//&& (pos.y%64==(32) || pos.y%64==(32))
		)
			v=1;
			//v=pos.x%COUNT_TYPES;
			//v=hash.x%COUNT_TYPES;
		#endif
		cells1[i]=v;
		cells2[i]=v;
	}
}
]==]
function advance_format(str,tbl)
	local fill=function(key)
		if tbl[key]==nil then
			error("No value for key:\""..key.."\"")
		end
		return tbl[key]
	end
	return str:gsub("%$([%w_]+)",fill)
end

function readAll(file)
    local f = assert(io.open(file, "rb"))
    local content = f:read("*all")
    f:close()
    return content
end

-----------------------------------------
local cl_kernels

function gen_rule_def( current_cell,rules )
	return string.format("const float rulebook_%d[]={%s};\n",current_cell,table.concat( rules, ", "))
end
function gen_rule_string(current_cell)
	return string.format("else if(cur_cell==%d) rule_level=rulebook_%d[configuration];",current_cell,current_cell)
end
function gen_rules_from_data(cur_rules)
	local rule_defs={}
	local rule_impls={}
	print("Rules:",#cur_rules.data)
	local max_rule=cur_rules.max_rule

	for rule_id=0,max_rule do
		print("Generating: r:",rule_id)
		table.insert(rule_defs,gen_rule_def(rule_id,cur_rules.data[rule_id]))
		table.insert(rule_impls,gen_rule_string(rule_id))
	end

	local rules_gen={}
	rules_gen.RULE_DEF=table.concat(rule_defs,"\n")
	rules_gen.RULE_IMPL=table.concat(rule_impls,"\n")

	return rules_gen
end
function thresh_table(tbl, v)
	local ret={}
	for i,value in pairs(tbl) do
		if value>v then
			ret[i]=1
		else
			ret[i]=0
		end
	end
	return ret
end
function print_rules(cur_rules)

	local max_rule=cur_rules.max_rule
	for rule_id=0,max_rule do
		print(string.format("Rule %d:[%s]\n",rule_id,table.concat(cur_rules.data[rule_id],", ")))
	end
end
function update_rules(tbl)
	generated_rules=gen_rules_from_data(tbl)
	generated_rules.W_SIZE=w
	generated_rules.H_SIZE=h
	generated_rules.RULE_SIZE=RULE_SIZE
	print(generated_rules.RULE_DEF)
	print(generated_rules.RULE_IMPL)
	print(generated_rules.RULE_SIZE)
	local final_kernel_str=advance_format(kernel_str,generated_rules)
	cl_kernels=opencl.make_program(final_kernel_str)
end
function load_rules(  )
local rule_def=[===[
#define GENERATED_RULE_COUNT 1

const float rulebook_0[]={0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0};

const float rulebook_1[]={1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0};

]===]
local rule_impl=[===[
else if(cur_cell==0) rule_level=rulebook_0[configuration];
else if(cur_cell==1) rule_level=rulebook_1[configuration];
]===]
	local rule_count=tonumber(rule_def:match("#define GENERATED_RULE_COUNT (%d+)"))

	local rule_data={}
	for str_rule_id,str in rule_def:gmatch("rulebook_(%d+)%[%]={([^}]+)}") do
		local rule_id=tonumber(str_rule_id)

		rule_data[rule_id]=rule_data[rule_id] or {}
		local cur_rule=rule_data[rule_id]
		for m in str:gmatch("(%d+),") do --TODO: Parse float here!
			table.insert(cur_rule,tonumber(m))
		end
	end
	for k,v in pairs(rule_data) do
		print(k,v)
	end
	print("loaded:",rule_count,rule_data[0],rule_data[1])
	current_rules={max_rule=rule_count,data=rule_data}
end
if current_rules==nil or current_rules.data==nil then
	if false then
		current_rules={max_rule=1}
	else
		load_rules()
		update_rules(current_rules)
	end
end
function sum_bits(v)
	return ((v)*(v+3))
end
--local MAX_STATE_VALUE=(RULE_SIZE*2+1)*(RULE_SIZE*2+1)-1 
local MAX_STATE_VALUE=math.pow(2,sum_bits(RULE_SIZE))
function make_rule_random(no_zero,max_rule,offset)
	local rules={}
	for i=0,MAX_STATE_VALUE do
		if i==1 and no_zero then
			rules[i]=0
		else
			rules[i]=math.random()*(1.0-offset)+offset
		end
	end
	return rules
end

function gen_rand_rules(tbl)
	local rules_base={}

	for rule_id=0,tbl.max_rule do
		local rules={}
		if rule_id==1 then
			rules=make_rule_random(false,rule_id,0.0)
		else
			rules=make_rule_random(false,rule_id,0.0)
		end
		rules_base[rule_id]=rules
	end
	return rules_base
end


function randomize_rules()
	current_rules.data=gen_rand_rules(current_rules)
	update_rules(current_rules)
end
if current_rules.data==nil then
	randomize_rules()
end
local final_kernel_str=advance_format(kernel_str,generated_rules)
cl_kernels=opencl.make_program(final_kernel_str)
print(generated_rules.RULE_DEF)
print(generated_rules.RULE_IMPL)
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

#define MAX_PERSIST 21474836
#define MAX_RULE 100.0
#define MAX_VALUE 3.0
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float field_mult;
uniform float persist_mult;
uniform float persist_pow;


vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec3 desaturate(vec3 c,float v)
{
	float gray=dot(c, vec3(0.2126, 0.7152, 0.0722 ));
	vec3 new_color=vec3(gray,gray,gray);
	return mix(new_color,c,v);
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);

    vec4 data=texture(tex_main,normed);

	float v= data.x;
	//float p= log(data.y);
	float p= data.y;
	//p*=field_mult;
	v*=field_mult;
   	vec3 c=palette(v,vec3(0.5),vec3(0.5),vec3(1.0),vec3(0.0,0.1,0.2));
#if 0
   	vec3 c=vec3(0);
   	if(v_cell>=1.0)
   		c=vec3(1,0.05,0.05);
   	else if(v_cell>=0.6665)
   		c=vec3(0.99,.9,.98);
   	else if(v_cell>=0.3332)
   		c=vec3(0.9,0.75,0.05);
#endif
   	//vec3 c=palette(mod(v_cell+0.50,1.0),vec3(0.5),vec3(0.5),vec3(1.0,0.7,0.4),vec3(0.0,0.15,0.2));
#if 0
	vec3 c=vec3(0);
   	if(mod(data.x,MAX_RULE)==0)
   		c=vec3(1,0.05,0.05);
   	if(mod(data.x,MAX_RULE)==1)
   		c=vec3(0.99,.9,.98);
   	if(mod(data.x,MAX_RULE)==2)
   		c=vec3(0.9,0.75,0.05);
#endif
   	//c=c*v*persist_mult;
   	//v=log(v+1);
   	//c=c*gain(clamp(v*persist_mult,0,1),persist_pow);
   	//c=c*pow(clamp(v*persist_mult,0,1),persist_pow);
   	//c=desaturate(c,gain(clamp(p*persist_mult,0,1),persist_pow));
   	c=desaturate(c,pow(clamp(p*persist_mult,0,1),persist_pow));
   	c*=pow(clamp(p*persist_mult,0,1),persist_pow);
    color=vec4(c,1);
}
]]


function init_buffer(  )
	local init_cells=cl_kernels.init_cells
	init_cells:set(0,cell_fields[1])
	init_cells:set(1,cell_fields[2])
	init_cells:set(2,config.density)
	init_cells:run(w*h)
end
if need_reinit then
	init_buffer()
end
local need_save=false
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
	config_serial=config_serial..string.format("\nrand_rules=[==[%s]==]\n",rand_rules)
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
function is_mouse_down2()
    local ret=__mouse.clicked2 and not __mouse.owned2
    if ret then
        current_down2=true
        last_mouse2={__mouse.x,__mouse.y}
    end
    local delta_x=0
    local delta_y=0
    if current_down2 then
        delta_x=__mouse.x-last_mouse2[1]
        delta_y=__mouse.y-last_mouse2[2]
        last_mouse2={__mouse.x,__mouse.y}
    end
    if __mouse.released2 then
        current_down2=false
    end
    return current_down2, __mouse.x,__mouse.y, delta_x,delta_y
end
sim_thread=nil
function save_tiles()
	local need_steps=2000000
	local steps_per_iteration=10000

	local start_radius=1
	local end_radius=31
	config.paused=false
	for radius=start_radius,end_radius do
		config.radius=radius
	    init_buffer( )
	    config.steps_per_frame=steps_per_iteration

	    for k=1,need_steps/steps_per_iteration do
	    	coroutine.yield()
	    end
		need_save=true
		coroutine.yield()
	end
	config.paused=true
    sim_thread=nil
end
function clamp(v,min,max)
	if v>max then
		return max
	elseif v<min then
		return min
	else
		return v
	end
end
local need_step=false
local time=0
rule_seed=42
function randomize_rule_seed()
	rule_seed=math.random(0,4294967295)
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Electrons")
	draw_config(config)

	--cl tick
	--setup stuff
	-- [==[
	if imgui.Button("Step") then
		need_step=true
	end
	imgui.SameLine()
	if imgui.Button("Reset view") then
		config.c_x=0.5
		config.c_y=0.5
		config.s_x=1
		config.s_y=1
	end
	if not config.paused or need_step then
		for i=1,config.steps_per_frame do
			local cell_update=cl_kernels.cell_update
			cell_update:set(0,cell_fields[1])
			cell_update:set(1,cell_fields[2])
			cell_update:seti(2,rule_seed)
			if config.mapping then
				local low_x=config.c_x-config.s_x/2
				local low_y=config.c_y-config.s_y/2
				local high_x=config.c_x+config.s_x/2
				local high_y=config.c_y+config.s_y/2
				cell_update:set(3,low_x,low_y)
				cell_update:set(4,high_x,high_y)
			else
				cell_update:set(3,config.c_x,config.c_y)
				cell_update:set(4,config.c_x,config.c_y)
			end
			cell_update:seti(5,4096+32768+16)
			cell_update:run(w*h)
			swap_cells()
			time=time+1
		end
		need_step=false
	end
	if sim_thread then
    --print("!",coroutine.status(sim_thread))
        local ok,err=coroutine.resume(sim_thread)
        if not ok then
            print("Error:",err)
            sim_thread=nil
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
	shader:set("persist_pow",config.persist_pow)
	shader:draw_quad()
	if need_save then
		need_save=false
		save_img()
	end

	if imgui.Button("Save")then
		need_save=true
	end
	if imgui.Button("Reset") then
		time=0
		init_buffer()
	end
	if imgui.Button("Prule") then
		print_rules(current_rules)
	end
	if imgui.Button("Rand") then
		time=0
		--randomize_rules()
		randomize_rule_seed()
		init_buffer()
		if config.paused then
			need_step=true
		end
	end
	if imgui.Button("Load Rules") then
		time=0
		load_rules("../projects/ca_rules/rules6.txt")
		update_rules(current_rules)
		init_buffer()
	end
	if imgui.Button("RunSim") then
		sim_thread=coroutine.create(save_tiles)
	end
	local tx,ty=config.t_x,config.t_y
    local c,x,y,dx,dy= is_mouse_down2()
    local update_bounds=false
    if c then
        dx,dy=dx/w,dy/h
        local rect_size={config.s_x,config.s_y}
        dx=dx*config.s_x;
        dy=dy*config.s_y;
        -- move center to the new location
        config.c_x=config.c_x+dx
        config.c_y=config.c_y+dy
        update_bounds=true
    end

    if __mouse.wheel~=0 then
        local pfact=math.exp(__mouse.wheel/10)

        config.s_x=config.s_x*pfact
        config.s_y=config.s_y*pfact
        update_bounds=true
    end
    -- [==[
    if update_bounds then
        config.s_x=clamp(config.s_x,0.001,1)
        config.s_y=clamp(config.s_y,0.001,1)
        config.c_x=clamp(config.c_x,0,1)
        config.c_y=clamp(config.c_y,0,1)
        init_buffer()
    end
    --]==]
end