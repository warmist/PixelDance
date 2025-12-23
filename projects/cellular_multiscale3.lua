--[[
	CA multistate totatalistic
	TODO: large scale?
--]]
require "common"
local ffi=require "ffi"
local w=256
local h=256

config=make_config({
	{"paused",false,type="bool"},
	{"steps_per_frame",1,type="int",min=1,max=100},
	{"field_mult",1,type="float",min=1,max=10},
	{"persist_mult",1,type="float",min=0,max=2},
	{"persist_pow",1,type="float",min=0.01,max=2},
},config)

function find_delta(x,y,z)
	local delta_id=y
	local delta=0
	if delta_id>1 or z>0 then
		delta=(delta_id-1)*delta_id/2+z*36
	end
	return delta
end
function get_unique_id(x,y,z)
	local delta=find_delta(x,y,z)
	return x+y*9+z*9*9--delta
end

function delta_display(tbl)
	local ret={}
	for i,v in ipairs(tbl) do
		if i>1 then
			print(i,v,v-tbl[i-1])
			table.insert(ret,v-tbl[i-1])
		else
			print(i,v)
			table.insert(ret,0)
		end
	end
	return ret
end
function map_comb()
	local str=""
	local tbl={}
	local actual_id=0
	for l=0,8 do
		str=str.." "..l.."\n"
		for k=0,8 do
			for j=0,8 do
				local tbl2={}
				local count=0
				for i=0,8 do
					local w=8-i-j-k-l
					if i+j+k+l<=8 then
						local v=get_unique_id(i,j,k)
						local actual_delta=v-actual_id
						print(string.format("(%d,%d,%d,%d)->%d-%d=%d %d",i,j,k,w,v,actual_id,actual_delta,actual_delta-find_delta(i,j,k)))
						if #tbl==0 or tbl[#tbl]~=actual_delta then
							table.insert(tbl,actual_delta)
						end
						actual_id=actual_id+1
					end
					if i+j+k+l<=8 then
						table.insert(tbl2,".")
					else
						table.insert(tbl2,"X")
						count=count+1
					end
				end

				str=str..table.concat(tbl2,"").." "..count.."\n"
			end
		end
	end
	print(str)
	--[[
	print(table.concat( tbl, ", " ))
	local t1=delta_display(tbl)
	local t2=delta_display(t1)
	local t3=delta_display(t2)
	--]]
end
--map_comb()
function copy_tbl(tbl)
	local ret={}
	for i,v in ipairs(tbl) do
		ret[i]=v
	end
	return ret
end
function gen_coords(dim,tbl)
	if dim==0 then
		return tbl
	end
	if tbl==nil then
		local ret={}
		for i=0,8 do
			table.insert(ret,{i})
		end
		return gen_coords(dim-1,ret)
	else
		local ret={}
		for i,v in ipairs(tbl) do
			for j=0,8 do
				local vv=copy_tbl(v)
				table.insert(vv,j)
				table.insert(ret,vv)
			end
		end
		return gen_coords(dim-1,ret)
	end
end
function sum_items(tbl)
	local sum=0
	for i,v in ipairs(tbl) do
		sum=sum+v
	end
	return sum
end
function flip_entry(v)
	local ret={}
	for i=1,#v do
		ret[#v-i+1]=v[i]
	end
	--ret[1]=8-ret[1]
	return ret
end
function flip_entries(tbl)

	for i,v in ipairs(tbl) do
		v[2]=flip_entry(v[2])
	end
end
function enumerate_all_allowed(tbl)
	local ret={}
	local counter=0
	for i,v in ipairs(tbl) do
		local sum=sum_items(v)
		if sum<=8 then
			table.insert(v,8-sum)
			table.insert(ret,{i,v,counter})
			counter=counter+1
		end
	end
	return ret
end
--[==[
local coord_list=gen_coords(3)
for i,v in ipairs(coord_list) do
	print(string.format("%04d (%s)",i-1,table.concat(v,",")))
end
local allowed_coord=enumerate_all_allowed(coord_list)
flip_entries(allowed_coord)
local last_delta=0
for i,v in ipairs(allowed_coord) do
	local delta=v[1]-1-v[3]
	print(string.format("%d %d (%s) %d %d",v[1]-1,v[3],table.concat(v[2],","),delta,delta-last_delta))
	last_delta=delta
end
--]==]
local kernel_str=[==[
#line __LINE__


#define CELL_MASK(X) (1<<X)
#define HAS_CELL(X,Y) ((X & CELL_MASK(Y))!=0)

#define W $W_SIZE
#define H $H_SIZE
#define M_PI 3.1415926538
#define BIGGER_SCALE_RECT2 32
#define BIGGER_SCALE_RECT 5
#define USE_ROUND_REGION 1
#define NEIGH8 1
#define LONG_RANGE_COUNT_NON_EMPTY 0
#define LONG_RANGE_GRID 0
#define LONG_RANGE_DELTA 0

#define SHORT_RANGE_COUNT_NON_EMPTY 1
#define SHORT_RANGE_WEIGHTS 0
#define SHORT_RANGE_DELTA 0

#define PERSIST_COLORED_BY_TIME 0
#define USE_PERSIST_FOR_CHANGES 0
#define USE_MAJORITY 1
#define MAJORITY_COUNT 0
#define RULES_RECT 1
#define MAX_PERSIST (21474836)
#define MAX_RULE 100
#define COUNT_TYPES 3

#define BORDER_CLAMP 0
#define BORDER_MIRROR 0
#define BORDER_ZERO 0
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


int count_majority(__global int* arr,int type,int2 pos)
{
	int count=0;
	for(int dx=-BIGGER_SCALE_RECT;dx<=BIGGER_SCALE_RECT;dx++)
	for(int dy=-BIGGER_SCALE_RECT;dy<=BIGGER_SCALE_RECT;dy++)
#if USE_ROUND_REGION
		if(dx*dx+dy*dy<BIGGER_SCALE_RECT*BIGGER_SCALE_RECT) //not perf nice
#endif
		{
			int cell=sample_at_pos_int(arr,pos+(int2)(dx,dy)) % MAX_RULE;
#if LONG_RANGE_COUNT_NON_EMPTY
			if(cell>0) //TODO PERSIST HERE
#elif LONG_RANGE_DELTA
			if(abs(cell-type)<=LONG_RANGE_DELTA)
#else
			if(cell==type)
#endif
				count+=1;
			else
				count-=1;
		}
	return count;
}
int count_majority_ex(__global int* arr,int type,int2 pos,int R)
{
	int count=0;
	for(int dx=-R;dx<=R;dx++)
	for(int dy=-R;dy<=R;dy++)
#if USE_ROUND_REGION
		if(dx*dx+dy*dy<=R*R) //not perf nice
#endif
		{
			int cell=sample_at_pos_int(arr,pos+(int2)(dx,dy)) % MAX_RULE;
#if LONG_RANGE_COUNT_NON_EMPTY
			if(cell>0) //TODO PERSIST HERE
#elif LONG_RANGE_DELTA
			if(abs(cell-type)<=LONG_RANGE_DELTA)
#else
			if(cell==type)
#endif
				count+=1;
			else
				count-=1;
		}
	return count;
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


#if 1 //rand rules
$RULE_DEF
#elif 1
const int rulebook_0[]={2, 2, 0, 2, 2, 1, 2, 1, 2, 1, 0, 1, 0, 0, 2, 0, 1, 1, 0, 0, 2, 0, 1, 0, 2, 2, 2, 2, 1, 0, 1, 0, 0, 1, 0, 0, 1, 2, 2, 2, 2, 1, 1, 0, 0};

const int rulebook_1[]={1, 2, 1, 0, 1, 2, 0, 0, 2, 1, 1, 2, 2, 2, 1, 2, 0, 2, 0, 2, 2, 2, 2, 2, 2, 1, 2, 0, 0, 2, 0, 2, 1, 1, 2, 2, 1, 0, 0, 2, 1, 2, 0, 1, 1};

const int rulebook_2[]={2, 2, 2, 2, 2, 1, 1, 2, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 1, 1, 2, 2, 1, 2, 1, 2, 2, 2, 2, 1, 2};
#endif

const int powers_of9[]={1,9,81};

int compress_id(int* counts)
{
	int delta_id=counts[1];
	int delta=(delta_id-1)*delta_id/2;
	return counts[0]+counts[1]*9-delta;//+counts[2]*9*9
}
int count_around(__global int* arr,int2 pos)
{
	int ret[3]={};
	//int ret=0;
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
			int cell=sample_at_pos_int(arr,pos+(int2)( dx, dy))%MAX_RULE;
			ret[cell]+=1;
		}
	}
	return compress_id(ret);
}
__kernel void cell_update(
	__global int* cell_input,
	__global int* cell_output,
	int time
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
		int configuration=count_around(cell_input,pos);


		int cur_cell=(my_cell % MAX_RULE);
		int majority1=count_majority_ex(cell_input,cur_cell,pos,BIGGER_SCALE_RECT);

		int majority_id=0;
#if USE_MAJORITY
		if (majority1>0)
			majority_id=1;
#else
		if (majority1<0)
			majority_id=1;
#endif
		int new_cell=0;
		//Generated code goes here:
		//	basic idea
		//  else if(cur_cell==4 && majority_id==1) new_cell=rulebook_4_1[configuration];
		if(false);
		$RULE_IMPL
#if 1
#if MAX_PERSIST
		if (new_cell==(my_cell % MAX_RULE) && new_cell!=0)
		{
#if PERSIST_COLORED_BY_TIME
			new_cell=my_cell; //keep the current persist
#else
			if(my_cell+MAX_RULE<MAX_PERSIST)
				new_cell=my_cell+MAX_RULE; //advance persist
			else
				new_cell=my_cell;
#endif
			//new_cell=cur_cell+majority_id*MAX_RULE; //debug majority_id
			/*
			if(new_cell/MAX_RULE>MAX_PERSIST)
			{
				new_cell=MAX_RULE*MAX_PERSIST+new_cell%MAX_RULE; //cap persist to max
			}
			*/
		}
#if PERSIST_COLORED_BY_TIME
		else if(new_cell!=(my_cell % MAX_RULE))
		{
			new_cell=new_cell+time*MAX_RULE;
		}
#endif
#if USE_PERSIST_FOR_CHANGES
		else if(new_cell!=(my_cell % MAX_RULE))
		{
			if(my_cell>MAX_RULE)
			{
				new_cell=my_cell-MAX_RULE;
			}
			else
			{
				//actually just leave as new value
			}
		}
#endif
#endif
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
__kernel void init_cells(__global int* cells1,__global int* cells2)
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
		int v=0;
		uint4 hash=(uint4)(i,0,0,0);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		#if 0

		if(false
			//||asym_blob(pos_i,0)
			|| length(pos_i+(float2)(C_OFFSET,C_OFFSET))<C_SIZE
			|| length(pos_i+(float2)(C_OFFSET,C_OFFSET)-(float2)(C_OFFSET2,-C_OFFSET2))<C_SIZE2

			|| length(pos_i+(float2)(-C_OFFSET,C_OFFSET))<C_SIZE
			|| length(pos_i+(float2)(-C_OFFSET,C_OFFSET)-(float2)(C_OFFSET2,C_OFFSET2))<C_SIZE2

			|| length(pos_i+(float2)(C_OFFSET,-C_OFFSET))<C_SIZE
			|| length(pos_i+(float2)(C_OFFSET,-C_OFFSET)-(float2)(-C_OFFSET2,-C_OFFSET2))<C_SIZE2

			|| length(pos_i+(float2)(-C_OFFSET,-C_OFFSET))<C_SIZE
			|| length(pos_i+(float2)(-C_OFFSET,-C_OFFSET)-(float2)(-C_OFFSET2,C_OFFSET2))<C_SIZE2

			|| length(pos_i+(float2)(C_OFFSET,0))<C_SIZE
			|| length(pos_i+(float2)(C_OFFSET,0)-(float2)(0,-C_OFFSET2))<C_SIZE2

			|| length(pos_i+(float2)(-C_OFFSET,0))<C_SIZE
			|| length(pos_i+(float2)(-C_OFFSET,0)-(float2)(0,C_OFFSET2))<C_SIZE2

			|| length(pos_i+(float2)(0,C_OFFSET))<C_SIZE
			|| length(pos_i+(float2)(0,C_OFFSET)-(float2)(C_OFFSET2,0))<C_SIZE2

			|| length(pos_i+(float2)(0,-C_OFFSET))<C_SIZE
			|| length(pos_i+(float2)(0,-C_OFFSET)-(float2)(-C_OFFSET2,0))<C_SIZE2
		)
			v=1;
			//v=pos.x%COUNT_TYPES;
			//v=hash.x%COUNT_TYPES;
		#endif
		#if 1
		if( true
			//&& float_from_hash(hash).x>0.5

			&& length(pos_normed)<0.8
			&& length(pos_normed)>0.35
			//&& fmod(length(pos_normed),0.4f)<0.3
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))<0.1
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))>0.05
			//&& pos_normed.y<0.01
			&& pos_normed.y*pos_normed.x<0.00008
			//&& fabs(pos_normed.y)>0.084
			//&& (pos.y%64==(32) || pos.y%64==(32))
		)
			v=1;
			//v=pos.x%COUNT_TYPES;
			//v=hash.x%COUNT_TYPES;
		#endif
		#if 0
		if( pos.x==13 && pos.y==12)
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
			//&& pos.x==W/2 && hash.x%8==0)
			&& (pos.x==W/2 && pos.y==H/2)
			//&& (pos.x-LONG_RANGE_GRID/2<W/2 && pos.x+LONG_RANGE_GRID/2>W/2 && pos.y-LONG_RANGE_GRID/2<H/2 && pos.y+LONG_RANGE_GRID/2>H/2)
			//|| (pos.x==W/2-64 && pos.y==H/2-8) || (pos.x==W/2+64 && pos.y==H/2+8)
			)
			v=2;
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
local transition_matrix={
	[0]={0.4,0.6,0,0},
	[1]={0.125,0.75,0.125,0},
	[2]={0.125,0,0.75,0.125},
	[3]={0.2,.05,.05,0.7},
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
function readAll(file)
    local f = assert(io.open(file, "rb"))
    local content = f:read("*all")
    f:close()
    return content
end

-----------------------------------------
local cl_kernels

function gen_rule_def( current_cell,current_majority,rules )
	return string.format("const int rulebook_%d_%d[]={%s};\n",current_cell,current_majority,table.concat( rules, ", "))
end
function gen_rule_string(current_cell,current_majority)
	return string.format("else if(cur_cell==%d && majority_id==%d) new_cell=rulebook_%d_%d[configuration];",current_cell,current_majority,current_cell,current_majority)
end
function gen_rules_from_data(cur_rules)
	local rule_defs={}
	local rule_impls={}
	print("Rules:",#cur_rules.data)
	local max_rule=cur_rules.max_rule
	for majority_id=0,cur_rules.max_majority do
		for rule_id=0,max_rule do
			print("Generating: r:",rule_id," m:",majority_id)
			table.insert(rule_defs,gen_rule_def(rule_id,majority_id,cur_rules.data[majority_id][rule_id]))
			table.insert(rule_impls,gen_rule_string(rule_id,majority_id))
		end
	end
	local rules_gen={}
	rules_gen.RULE_DEF=table.concat(rule_defs,"\n")
	rules_gen.RULE_IMPL=table.concat(rule_impls,"\n")
	return rules_gen
end

function update_rules(tbl)
	generated_rules=gen_rules_from_data(tbl)
	generated_rules.W_SIZE=w
	generated_rules.H_SIZE=h
	print(generated_rules.RULE_DEF)
	print(generated_rules.RULE_IMPL)
	local final_kernel_str=advance_format(kernel_str,generated_rules)
	cl_kernels=opencl.make_program(final_kernel_str)
end
function load_rules(  )
local rule_def=[===[
#define GENERATED_RULE_COUNT 2
#define GENERATED_MAJORITY_COUNT 1

const int rulebook_0_0[]={0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0};

const int rulebook_1_0[]={1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0};

const int rulebook_2_0[]={2, 1, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 0, 2, 2, 2, 1, 2, 2, 1, 2, 1, 2, 2, 2, 2, 1, 2};

const int rulebook_0_1[]={0, 1, 0, 2, 0, 0, 0, 2, 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 2, 0, 0, 1, 0, 0, 2, 1, 0, 1, 0, 2, 1, 1, 0, 0, 0, 1, 2, 1, 0, 0, 1, 2};

const int rulebook_1_1[]={1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 2, 2, 0, 1, 0, 1, 1, 1, 1, 1, 0, 0, 1, 0, 1, 1, 0, 0, 2, 1, 1, 2, 0, 1, 0, 1, 1, 1, 0};

const int rulebook_2_1[]={1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 1, 2, 0, 2, 2, 1, 1, 2, 1, 1, 0, 1, 2, 0, 2, 2, 1, 2, 2, 1, 2, 1, 2, 1, 2, 2, 0, 1, 1, 2, 2, 2, 2, 1, 2};
]===]
local rule_impl=[===[
else if(cur_cell==0 && majority_id==0) new_cell=rulebook_0_0[configuration];
else if(cur_cell==1 && majority_id==0) new_cell=rulebook_1_0[configuration];
else if(cur_cell==2 && majority_id==0) new_cell=rulebook_2_0[configuration];
else if(cur_cell==0 && majority_id==1) new_cell=rulebook_0_1[configuration];
else if(cur_cell==1 && majority_id==1) new_cell=rulebook_1_1[configuration];
else if(cur_cell==2 && majority_id==1) new_cell=rulebook_2_1[configuration];
]===]
	local rule_count=tonumber(rule_def:match("#define GENERATED_RULE_COUNT (%d+)"))
	local majority_count=tonumber(rule_def:match("#define GENERATED_MAJORITY_COUNT (%d+)"))

	local rule_data={}
	for str_rule_id,str_majority_id,str in rule_def:gmatch("rulebook_(%d+)_(%d+)%[%]={([^}]+)}") do
		local rule_id=tonumber(str_rule_id)
		local majority_id=tonumber(str_majority_id)
		print("Parsing:",rule_id,majority_id)
		local majority_data=rule_data[majority_id] or {}
		rule_data[majority_id]=majority_data
		local cur_rule=majority_data[rule_id] or {}
		majority_data[rule_id]=cur_rule
		for m in str:gmatch("(%d+),") do
			table.insert(cur_rule,tonumber(m))
		end
	end
	for k,v in pairs(rule_data) do
		print(k,v)
	end
	print("loaded:",rule_count,majority_count,rule_data[0],rule_data[1])
	current_rules={max_rule=rule_count,max_majority=majority_count,data=rule_data}
end
if current_rules==nil or current_rules.data==nil then
	if false then
		current_rules={max_rule=2,max_majority=1}
	else
		load_rules()
		update_rules(current_rules)
	end
end
local MAX_STATE_VALUE=45 --TODO: depends on state count
function make_rule_random(no_zero,max_rule)
	local rules={}
	for i=0,MAX_STATE_VALUE do
		if i==1 and no_zero then
			rules[i]=0
		else
			rules[i]=math.random(0,max_rule)
		end
	end
	return rules
end
function make_rule_advancing(no_zero,max_rule)
	local rules={}
	for i=0,MAX_STATE_VALUE do
		if i==1 and no_zero then
			rules[i]=0
		else
			if math.random()>0.5 then
				rules[i]=rule_id
			elseif math.random()>0.5 then
				rules[i]=0
			else
				rules[i]=(rule_id+1)%max_rule
			end
		end
	end
	return rules
end
function normalize(tbl)
	local ret={}
	local sum=0
	for k,v in pairs(tbl) do
		sum=sum+v
	end
	local vsum=0
	for k,v in pairs(tbl) do
		vsum=vsum+v/sum
		ret[k]=vsum
	end
	return ret
end

function make_rule_changing(no_zero,rule_id,chances,max_rule)
	local chances_n=normalize(chances)
	local rules={}
	for i=0,MAX_STATE_VALUE do
		if i==0 and no_zero then
			rules[i]=0
		else
			local rnd=math.random()
			if rnd<=chances_n[0] then --chance to turn to 0
				rules[i]=0
			elseif rnd<=chances_n[1] then --chance to remain itself
				rules[i]=rule_id
			elseif rnd<=chances_n[2] then --chance to advance
				rules[i]=(rule_id+1)%max_rule
			elseif rnd<=chances_n[3] then --chance to reduce
				if rule_id==0 then
					rules[i]=max_rule-1
				else
					rules[i]=rule_id-1
				end
			end
		end
	end
	return rules
end
function make_rule_const(value)
	local rules={}
	for i=0,MAX_STATE_VALUE do
		rules[i]=value
	end
	return rules
end
function mutate_copy(tbl,amount)
	local ret={}
	for k,v in pairs(tbl) do
		ret[k]=v
	end
	for i=1,amount do
		local id=math.random(0,#ret)
		local change_to=math.random(0,current_rules.max_rule)
		ret[id]=change_to
	end
	return ret
end
function gen_rand_rules(tbl)
	local rules_base={}
	for majority_id=0,tbl.max_majority do
		local majority_base={}
		for rule_id=0,tbl.max_rule do
			local rules={}
			if majority_id==0 then
				rules=make_rule_changing(true,rule_id,{[0]=0.01,[1]=0.8,[2]=0.1,[3]=0.1},tbl.max_rule)
			--	rules=make_rule_changing(false,rule_id,{[0]=0.2,[1]=0.4,[2]=0.2,[3]=0.2},tbl.max_rule)
			--if rule_id==0 then
			--	rules=make_rule_changing(true,rule_id,{[0]=0.05,[1]=0.8,[2]=0.5,[3]=0.125},tbl.max_rule)
			--else
			--	if math.random()>0.5 then
					--rules=make_rule_random(false,tbl.max_rule)
			--	elseif math.random()>0.2 then
			--		rules=make_rule_const(rule_id)
			--	else
			--		rules=make_rule_const(0)
			--	end
			--end
			--[[
			elseif majority_id==1 or majority_id==2 then
				rules=make_rule_changing(rule_id==0,rule_id,{[0]=0.125,[1]=0.25,[2]=0.5,[3]=0.125},tbl.max_rule)
			else
				--if rule_id==3 then
					rules=make_rule_const(rule_id)
				--else
					--rules=make_rule_changing(rule_id==0,rule_id,{[0]=0.125,[1]=0.25,[2]=0.125,[3]=0.5},tbl.max_rule)
				--end
			end
			--]]
			else
				rules=mutate_copy(rules_base[0][rule_id],25)
			end
			majority_base[rule_id]=rules
		end
		rules_base[majority_id]=majority_base
	end
	return rules_base
	--return string.format("const int rulebook[]={\n%s};",table.concat( rules_base, ""))
end

function mutate_rules(amount)
	for i=1,amount do
		local id=math.random(0,#current_rules.data)
		local mid=math.random(0,#current_rules.data[id])
		local nid=math.random(0,#current_rules.data[id][mid])
		local from=current_rules.data[id][mid][nid]
		local change_to=math.random(0,current_rules.max_rule)
		print("changing",id,nid,"form:",from," to ",change_to)
		current_rules.data[id][mid][nid]=change_to
	end
end
function stabilize_rules(amount)
	for i=1,amount do
		local id=math.random(0,#current_rules.data)
		local mid=math.random(0,#current_rules.data[id])
		local nid=math.random(0,#current_rules.data[id][mid])
		local from=current_rules.data[id][mid][nid]
		print("changing",id,mid,nid,"form:",from," to ",mid)
		current_rules.data[id][mid][nid]=mid
	end
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
    float v_cell=mod(data.x,MAX_RULE)/MAX_VALUE;
	float v= ((data.x-mod(data.x,MAX_RULE))/MAX_RULE)/MAX_PERSIST;
	//v_cell=v_cell+v/MAX_VALUE;
   	//v_cell=v_cell*field_mult;
   	v_cell=v_cell+field_mult;
   	//v_cell=0;

   	//vec3 c=vec3(mod(v_cell+0.5,1.0));
   	//if(v_cell>2/MAX_VALUE)
   	//	c=vec3(mod(v_cell+0.5,1.0),0,0);
   	//vec3 c=palette(v_cell,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
   	//vec3 c=palette(mod(v_cell+0.5,1.0),vec3(0.5),vec3(0.5),vec3(1.0),vec3(0.0,0.1,0.2));
#if 0
   	vec3 c=vec3(0);
   	if(v_cell>=1.0)
   		c=vec3(1,0.05,0.05);
   	else if(v_cell>=0.6665)
   		c=vec3(0.99,.9,.98);
   	else if(v_cell>=0.3332)
   		c=vec3(0.9,0.75,0.05);
#endif
   	vec3 c=palette(mod(v_cell+0.50,1.0),vec3(0.5),vec3(0.5),vec3(1.0,0.7,0.4),vec3(0.0,0.15,0.2));
#if 0
   	if(mod(data.x,MAX_RULE)==0)
   		c=vec3(1,0,0);
   	if(mod(data.x,MAX_RULE)==1)
   		c=vec3(0,1,0);
   	if(mod(data.x,MAX_RULE)==2)
   		c=vec3(0,0,1);
#endif
   	//c=c*v*persist_mult;
   	c=c*gain(clamp(v*persist_mult,0,1),persist_pow);
   	//c=desaturate(c,gain(clamp(v*persist_mult,0,1),persist_pow));
    color=vec4(c,1);
}
]]


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

local need_step=false
local time=0
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
	if not config.paused or need_step then
		for i=1,config.steps_per_frame do
			local cell_update=cl_kernels.cell_update
			cell_update:set(0,cell_fields[1])
			cell_update:set(1,cell_fields[2])
			cell_update:seti(2,time)
			cell_update:run(w*h)
			swap_cells()
			time=time+1
		end
		need_step=false
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
	if imgui.Button("Save") then
		save_img()
	end
	if imgui.Button("Reset") then
		time=0
		init_buffer()
	end
	if imgui.Button("Rand") then
		time=0
		randomize_rules()
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
	if imgui.Button("Mutate") then
		time=0
		mutate_rules(10)
		update_rules(current_rules)
		init_buffer()
		need_step=true
	end
	if imgui.Button("Stabilize") then
		time=0
		stabilize_rules(10)
		update_rules(current_rules)
		init_buffer()
		need_step=true
	end
end