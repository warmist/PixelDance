require "common"
require "self_doc"
--[===[=
	** Cellular automaton "Huge" edition **

	An exploration of cellular automaton (CA) with huge state space. This includes having
	big number of states each cell can have, various neighborhoods, totalistic and not, etc...

	Due to very large number of possible states ruletable can't be practically written down,
	so rules are generated on the fly from seed(s).

	Refs:
	* https://en.wikipedia.org/wiki/Cellular_automaton
--]===]
--[==[
	TODO:
	FIXME:
--]==]

local win_w=1024
local win_h=1024

local oversample=1/4

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local size=STATE.size
local max_state=20
local use_actual_rulebook=false

local symmetries={
	--"pos.yx","-pos.xy","-pos.yx", --mirrors
	--"rotated(pos-center,M_PI_F/2)+center","rotated(pos-center,2*M_PI_F/2)+center","rotated(pos-center,3*M_PI_F/2)+center",
	--"rotated(pos-center,2*M_PI_F/3)+center","rotated(pos-center,4*M_PI_F/3)+center", --3fold
	--"rotated(pos-center,2*M_PI_F/5)+center","rotated(pos-center,4*M_PI_F/5)+center","rotated(pos-center,6*M_PI_F/5)+center","rotated(pos-center,8*M_PI_F/5)+center", --5fold
	--"rotated((int2)(3,0),2*M_PI_F/3)+pos","rotated((int2)(3,0),4*M_PI_F/3)+pos","(int2)(3,0)", --3fold local
}

local checked_cells=(8+#symmetries)
local max_rule=math.pow(checked_cells,max_state)-1
config=make_config({
    {"pause",true,type="bool"},
    {"draw_food",false,type="bool"},
    {"radius",8,type="float",min=1,max=100},
    {"noise",1,type="float",min=0,max=1},
    {"step_count",8,type="int",min=0,max=15},
    },config)


local need_reinit=(cell_fields==nil)
cell_fields=cell_fields or{
	opencl.make_buffer(map_w*map_h*4),
	opencl.make_buffer(map_w*map_h*4),
}
cell_food_fields=cell_food_fields or{
	opencl.make_buffer(map_w*map_h*4),
	opencl.make_buffer(map_w*map_h*4),
}
function swap_cells(  )
	local p=cell_fields[1]
	cell_fields[1]=cell_fields[2]
	cell_fields[2]=p

	local p=cell_food_fields[1]
	cell_food_fields[1]=cell_food_fields[2]
	cell_food_fields[2]=p
end
texture=textures:Make()
texture:use(1)
texture:set(map_w,map_h,FLTA_PIX)
local display_buffer=opencl.make_buffer_gl(texture)

local kernel_str=[==[
#line __LINE__

#define W $width
#define H $height

#define SYMMETRY_COUNT $symmetries
#define STATE_COUNT $state_count
#define CELL_COUNT (SYMMETRY_COUNT+8)


#define BORDER_ZERO 0
#define BORDER_MIRROR 0
#define BORDER_CLAMP 0
int pos_to_index(int2 p)
{
	//int2 p2=clamp_pos(p);
	return p.x+p.y*W;
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
int2 rotated(int2 pos,float rotation)
{
	return (int2)(pos.x*cos(rotation)-pos.y*sin(rotation),pos.x*sin(rotation)+pos.y*cos(rotation));
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

void count_around(__global float* cells,int2 pos,int* state_counts)
{
	for(int dx=-1;dx<=1;dx++)
	for(int dy=-1;dy<=1;dy++)
	{
		if(dx!=0 || dy!=0)
		{
			float sample=sample_at_pos_float(cells,pos+(int2)(dx,dy));
			int state_id=floor(sample);
			if(state_id>0)
				state_counts[state_id-1]++;
				//state_counts[0]++;
		}
	}
	int2 center=(int2)(W/2,H/2);
	//something along the lines of int2 samples_pos[]={a,b,c}
	$generated_count_logic
#if 0
	for(int i=0;i<SYMMETRY_COUNT;i++)
	{
		int2 dp=sample_pos[i];
		float sample=sample_at_pos_float(cells,dp);
		int state_id=floor(sample);
		if(state_id>0)
			state_counts[state_id-1]++;
	}
#endif
}
float avg_around(__global float* values,int2 pos)
{
	float w_around=0.0002;
	float w_center=1.0;
	float center=sample_at_pos_float(values,pos);
	float sum=0;
	for(int dx=-1;dx<=1;dx++)
	for(int dy=-1;dy<=1;dy++)
	{
		if(dx!=0 || dy!=0)
		{
			float sample=sample_at_pos_float(values,pos+(int2)(dx,dy));
			sum+=sample;
		}
	}
	return (w_around*sum+w_center*center)/(8*w_around+w_center);
}
$generated_rule_definition

int count_cell_state(int* cell_state)
{
	int trg_id=0;
	for(int k=0;k<STATE_COUNT;k++)
		trg_id+=cell_state[k]*(int)(pown((float)(CELL_COUNT),k));

	int max_id=pown((float)(CELL_COUNT),STATE_COUNT)-1;
	int actual_id=0;
	for(int i=0;i<max_id;i++)
	{
		if(i==trg_id)
			return actual_id;

		int sum=0;
		int split_i=i;
		for(int k=0;k<STATE_COUNT;k++)
		{
			sum+=(i%CELL_COUNT);
			i/=CELL_COUNT;
		}


		if(sum<CELL_COUNT)
			actual_id+=1;
	}
	return 0;
}
$weight_table
int hash_based_rule(int state,uint hash_offset,int my_state)
{
	uint h=lowbias32(hash_offset);
	h=lowbias32(h);
	h=lowbias32(h+state);
#if 0 //weights... unfinished!
//TODO: better weight system
#define WEIGHTS_PER_STATE 3
	//weighted table for rule selection
	int wtable[]={
		//state 0
		0,1,2,1,1,1,2,2,2,
		//state 1
		0,0,1,1,1,1,1,2,2,
		//state 2
		0,0,0,0,1,2,2,2,2,
	};
	return wtable[(h % STATE_COUNT*WEIGHTS_PER_STATE)+my_state*STATE_COUNT*WEIGHTS_PER_STATE];
#elif 1
	// something like: return weight_table_my_state[h%WEIGHT_COUNT];
	$weight_logic
#else
	return h % STATE_COUNT;
#endif
}
//linear color step
const float color_step=1/400.0f;
//exp color step
const float color_decay=0.01f;

#define HIGHER_STATES_COST_MORE 0
const float cost_change=0.6;
const float min_cost=0.001;
const float cost_recovery_efficiency=0.0;

const float exp_value=-10;
const float food_drain_near=0;//0.00005f;
const float food_drain_far=0;//-0.00005f;
float state_cost(int state)
{
	if (state==0)
		return 0;
	float normed_state=(float)(state)/(float)(STATE_COUNT);
	//square with center at min
	//float ret_cost=(4-min_cost)*(normed_state-0.5)*(normed_state-0.5)+min_cost;
	//cos thingy...
	//float ret_cost=(cos(normed_state*222)*0.5+0.5)*(1-min_cost)+min_cost;
	//linear thingy
	//float ret_cost=normed_state*(1-min_cost)+min_cost;
	//square with 0 at 0
	//float ret_cost=normed_state*normed_state+min_cost;
	//float ret_cost=(1-min_cost)*(exp(exp_value*normed_state)-1)/(exp(exp_value)-1)+min_cost;
#ifdef STATE_LOOKUP
	uint h=lowbias32(STATE_LOOKUP(state));
#else
	uint h=0;
#endif
#if HIGHER_STATES_COST_MORE
	float ret_cost=float_from_hash(h).x*(cost_change*normed_state-min_cost)+min_cost; //generate random cost [min_cost,cost_change*normed_state]
#else
	float ret_cost=float_from_hash(h).x*(cost_change-min_cost)+min_cost; //generate random cost [min_cost,cost_change]
#endif

	//ret_cost+=state_cost(state-1);
	return cost_change*ret_cost;
}
__kernel void cell_update(
	__global float* cell_input,
	__global float* cell_output,
	__global float* cell_food_input,
	__global float* cell_food_output
	)
{
	int i=get_global_id(0);
	int max_i=W*H;

	if(i>=0 && i<max_i)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;

		float2 pos_i=convert_float2(pos)-(float2)(W/2,H/2);
		//float cell_step=(1+0.25*length(pos_i)/(W/2))*0.01; //probably quite silly...

		float my_cell_f=cell_input[i];
		int my_cell_i=(floor(my_cell_f));

#if 0
		float food=cell_food_input[i];
#else //food diffusion
		float food=avg_around(cell_food_input,pos);
#endif
		if(length(pos_i)/(W/2)<0.25)
			food=max(food-food_drain_near,0.0f);
		else
			food=max(food-food_drain_far,0.0f);

		float new_cell=0;
		int cell_state[STATE_COUNT]={};
		count_around(cell_input,pos,cell_state);
		//int state_id=cell_state[0]+cell_state[1]*STATE_COUNT+cell_state[2]*STATE_COUNT*STATE_COUNT+cell_state[3]*STATE_COUNT*STATE_COUNT*STATE_COUNT;

		$generated_rule_logic
		//something like if(my_cell_i==1) new_cell=rulebook_1[state_id];
		//or new_cell=hash_based_rule(state_id,state_hash_offset[my_cell_i])

		//no flashing!
		if(state_id==0 && my_cell_i==0)
			new_cell=0;

		int new_cell_i=(floor(new_cell));
		float cell_final_out=my_cell_f;

#if 0 //cell food system

//cost selection
#if 1 //simple cost system
		float old_cell_cost=state_cost(my_cell_i);
		float new_cell_cost=state_cost(new_cell);
#elif 0 //advance states need more energy DEPRECATED, see state_cost!
		float old_cell_cost=state_cost(my_cell_i)*(my_cell_i+1);
		float new_cell_cost=state_cost(new_cell)*(new_cell_i+1);
#else   //cost depends on cells around
		float avg_cell=0;
		for(int i=0;i<STATE_COUNT;i++)
			avg_cell+=cell_state[i];
		avg_cell/=STATE_COUNT;
		float old_cell_cost=state_cost(fabs(my_cell_i-avg_cell));
		float new_cell_cost=state_cost(fabs(new_cell-avg_cell));
#endif

		float actual_change_cost=new_cell_cost-old_cell_cost*cost_recovery_efficiency;

		if(my_cell_i!=new_cell_i)
		{
			if(food>actual_change_cost)
			{
				food-=actual_change_cost;
				//nop, perform the change
			}
			else
			{
				new_cell=my_cell_f;
				new_cell_i=(floor(new_cell));
			}
		}
#else
		//float cell_final_out=new_cell;
#endif

#if 0 //fractional part needs to increase for cell type to change
		if(my_cell_i!=new_cell_i)
		{
			//trying to change cell type
			float offset=my_cell_f-floor(my_cell_f);
			if(offset+cell_step<1) //if we dont overflow, we increase the "fractional part timer"
			{
				cell_final_out=my_cell_f+cell_step;
			}
			else
			{
				//if we overflow just set to new cell
				cell_final_out=new_cell;
			}
		}
		else
		{
			//we want to keep same cell
			float offset=my_cell_f-floor(my_cell_f);
			if(offset>cell_step)
			{
				//if we have some fractional part, reduce it
				cell_final_out=my_cell_f-cell_step;
			}
			else
			{
				cell_final_out=floor(my_cell_f);
			}
		}
#elif 1 //fractional part is only for display
		if(my_cell_i!=new_cell_i)
		{
			cell_final_out=new_cell;
		}
		else
		{
#if 1 //linear
			//we want to keep same cell
			float fract_part=my_cell_f-floor(my_cell_f);
			if(fract_part<1-2*color_step)
			{
				//if we have some fractional part, reduce it
				cell_final_out=my_cell_f+color_step;
			}
			else
			{
				cell_final_out=floor(my_cell_f)+0.999f;
			}
#else //exp?
			float fract_part=my_cell_f-floor(my_cell_f);
			float next_fract=(1-fract_part)*color_decay;
			if(fract_part+next_fract<0.999f)
			{
				//if we have some fractional part, reduce it
				cell_final_out=my_cell_f+next_fract;
			}
			else
			{
				cell_final_out=my_cell_f;
			}
#endif
			
		}
#else
		//float cell_final_out=new_cell;
#endif

#if 0
		cell_final_out=cell_state[0];
#endif
		cell_output[i]=cell_final_out;
		cell_food_output[i]=food;
	}
}

float food_function(float2 pos_normed,float radius)
{
	float f=0;
	//f=cos(length(pos_normed)*4+2)*0.4+0.6;
	f=radius-length(pos_normed);
	f=fmax(f,0.0f);
	//f=fabs(pos_normed.y);
	//f=(pos.x/(float)(W)+pos.y/(float)(H));
	//f=1-fmax(fabs(pos_normed.x),fabs(pos_normed.y));
	f*=3;
	//ambient food
	//f=f*0.95+0.05;
	//f=pow(f,2);
	return f;
}

int is_neg(int a)
{
	if(a<0)
		return -1;
	else
		return 0;
}
int e_mod(int a,int b)
{
	return abs((a%b+b)%b);
}
__kernel void init_cells(
	__global float* cells1,
	__global float* cells2,
	__global float* food1,
	__global float* food2,
	float radius,
	float noise_level)
{
	int i=get_global_id(0);
	int max_i=W*H;
	if(i>=0 && i<max_i)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		int2 center_i;
		center_i.x=W/2;
		center_i.y=H/2;
		int2 posc=center_i-pos;
		float2 pos_normed;
		float2 pos_i=convert_float2(pos)-(float2)(W/2,H/2);
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;
		float v=0;
		uint4 hash=(uint4)(i,0,0,0);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		float2 center_offset=(float2)(0,0.0);
		int edge_w=8;
		float L=radius-edge_w*2;
		int slider_pos=noise_level;
	#if 1
		if( true
			&& float_from_hash(hash).x<noise_level
			//&& length(pos_normed-center_offset)<radius/(float)(W)
			//&& length(pos_normed)<0.2
			//&& fmod(length(pos_normed),0.4f)<0.3
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))<0.1
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))>0.05
			//&& fmax(fabs(pos_i.x),fabs(pos_i.y))<radius
			//&& length(pos_i)<radius
			//&& length(pos_i)>radius/2
			//&& pos_normed.y<0.01
			//&& pos_normed.y*pos_normed.x<0.00008
			//&& fabs(pos_normed.y)>0.084
			//&& (pos.y%64==(32) || pos.y%64==(32))
#if 0 //box
			&& (abs(posc.x)<radius)
			&& (abs(posc.y)<radius)
			&& (abs(posc.x)%4==0 || abs(posc.x)>(radius-edge_w*2))
			&& (abs(posc.y)%4==0 || abs(posc.y)>(radius-edge_w*2))
			&& (max(abs(posc.x),abs(posc.y))>L)
#elif 0 // T
			&& (abs(posc.x)<radius*2)
			&& (abs(posc.y)<edge_w || abs(posc.x)<edge_w)
			&& (posc.y>-edge_w)
			&& (posc.y<radius*2)
			&& (abs(posc.x)%4==0 || (abs(posc.x)>(radius*2-edge_w*2) || abs(posc.x)<edge_w))
			&& (abs(posc.y)%4==0 || (abs(posc.y)>(radius*2-edge_w*2) || abs(posc.y)<edge_w))
#elif 0 // X
			&& (abs(posc.x)<radius*2)
			&& (abs(posc.y)<edge_w || abs(posc.x)<edge_w)
			&& (posc.y>-radius*2)
			&& (posc.y<radius*2)
			&& (abs(posc.x)%4==0 || (abs(posc.x)>(radius*2-edge_w*2) || abs(posc.x)<edge_w))
			&& (abs(posc.y)%4==0 || (abs(posc.y)>(radius*2-edge_w*2) || abs(posc.y)<edge_w))
#elif 0 // slider
			&& (abs(posc.x)<radius*2)
			&& (abs(posc.y)<edge_w+1)
			&& (abs(posc.y)<edge_w || (posc.x-edge_w<slider_pos && posc.x+edge_w>slider_pos))
			&& (abs(posc.x)%4==0 || (abs(posc.x)>(radius*2-edge_w*2) || (posc.x-edge_w<slider_pos && posc.x+edge_w>slider_pos)))
#elif 1 //grid
			&& e_mod(pos.x,8)<4
			&& e_mod(pos.y,8)<4
#endif
		)
			v=5;
			//v=pos.x%COUNT_TYPES;
			//v=hash.x%COUNT_TYPES;
	#endif

		#if 0
		if( fabs(pos_i.y)>50)
			v=1;
		#endif
		#if 0
		if( pos.x==W/2 && pos.y==H/2)
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

		float f=0;
		#if 1
		f=food_function(pos_normed-center_offset,(radius/(float)(W)));
		#endif
		food1[i]=f;
		food2[i]=f;
	}
}
__kernel void inject_food(
	__global float* food1,
	__global float* food2,
	float radius,
	float scale)
{
	int i=get_global_id(0);
	int max=W*H;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float2 pos_normed;
		float2 pos_i=convert_float2(pos)-(float2)(W/2,H/2);
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;

		float f=food_function(pos_normed,(radius/(float)(W))); //TODO: offset
		f*=scale;
		food1[i]+=f;
		food2[i]+=f;
	}
}

__kernel void update_texture(
	__global float* cell_input,
	__global float* food_input,
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
		float my_cell=cell_input[i]*1;
		float my_food=food_input[i]*1;
		//float my_cell=cell_input[i]*25;

		float4 col=(float4)(my_cell/(float)(STATE_COUNT),my_food,0.f,0.f);

		write_imagef(output_tex,pos,col);
	}
}
]==]

local cl_kernels
function update_kernels()
	local kern=advance_format(kernel_str,{
		width=map_w,
		height=map_h,
		generated_rule_definition=generated_rule_definition or "",
		generated_rule_logic=generated_rule_logic or "int state_id=0;",
		generated_count_logic=generated_count_logic or "int2 sample_pos[]={};",
		weight_table=weight_table or "",
		weight_logic=weight_logic or "return h%STATE_COUNT;",
		state_count=max_state,
		symmetries=#symmetries,
	})
	--[=[
	local f=io.open("tmp.txt","w")
	f:write(kern)
	f:close()
	--]=]
	--print(kern)
	cl_kernels=opencl.make_program(kern)
end
update_kernels()
function gen_rule_def(id,rule)
	--print(string.format("rulebook_%d[]",id))
	return string.format("const int rulebook_%d[]={%s};",id,table.concat(rule,", "))
end
function gen_rule_logic(id,rule)
	return string.format("else if(my_cell_i==%d) new_cell=rulebook_%d[state_id];",id,id)
end
function logic_preamble()
	local state_comp=""
	local tbl_count={}
	local tbl_cells={}
	for i=1,max_state do
		local mult=""
		if i>1 then
			mult="*"
		end
		table.insert(tbl_cells,string.format("cell_state[%d]",i-1)..mult..table.concat(tbl_count,"*"))
		table.insert(tbl_count,"CELL_COUNT")
	end
	--return "int state_id=count_cell_state(cell_state);"
	return string.format("int state_id=%s;",table.concat(tbl_cells,"+"))
end
function gen_symmetries_def()
	return string.format("int2 sample_pos[]={%s};",table.concat(symmetries,", "))
end
function gen_rule_def_hashed(id)
	local ret={}

end
function update_rules()

	generated_rule_definition=string.format("uint state_hash_offset[]={%s};\n",table.concat(hash_offsets,",\n"))
	generated_rule_definition=generated_rule_definition..string.format("uint state_hash_offset_food[]={%s};\n#define STATE_LOOKUP(s) state_hash_offset_food[s]",table.concat(hash_offsets_food,",\n"))
	local rule_logic={logic_preamble(),"new_cell=hash_based_rule(state_id,state_hash_offset[my_cell_i],my_cell_i);\n"}
	generated_rule_logic=table.concat(rule_logic,"\n")

	print(generated_rule_definition)
	print(generated_rule_logic)
	generated_count_logic=gen_symmetries_def()
	print(generated_count_logic)
	print(weight_table)
	print(weight_logic)
	update_kernels()
end

color_info=color_info or {
	col_offset={0.5,0.5,0.5},
	col_amplitute={0.5,0.5,0.5},
	col_freq={1,1,1},
	col_angle={0,0.1,0.2},
	state_count=max_state,
	draw_food=1,
}

draw_field=init_draw_field(advance_format(
[==[
#line __LINE__
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}

vec4 texture2D_bilinear(in sampler2D t, in vec2 uv, in vec2 textureSize, in vec2 texelSize)
{
    vec2 f = fract( uv * textureSize );
    uv += ( .5 - f ) * texelSize;    // move uv to texel centre
    vec4 tl = texture2D(t, uv);
    vec4 tr = texture2D(t, uv + vec2(texelSize.x, 0.0));
    vec4 bl = texture2D(t, uv + vec2(0.0, texelSize.y));
    vec4 br = texture2D(t, uv + vec2(texelSize.x, texelSize.y));
    vec4 tA = mix( tl, tr, f.x );
    vec4 tB = mix( bl, br, f.x );
    return mix( tA, tB, f.y );
}
const int M = 5;
const int N = 2 * M + 1;


const float coeffs[N] = float[N](0.0012,	0.0085,	0.0380,	0.1109,	0.2108,	0.2612,	0.2108,	0.1109,	0.0380,	0.0085,	0.0012); // generated kernel coefficients

vec4 gaussian_sample(in vec2 texcoord)
{
	vec4 sum = vec4(0.0);

    for (int i = 0; i < N; ++i)
    {
        for (int j = 0; j < N; ++j)
        {
            vec2 tc = texcoord + 1/vec2(256)
                * vec2(float(i - M), float(j - M));

            sum += coeffs[i] * coeffs[j]
                * texture(tex_main, tc);
        }
    }
    return sum;
}
//https://gist.github.com/983/e170a24ae8eba2cd174f
vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);
    //vec4 data=texture2D_bilinear(tex_main,normed,vec2(1024),vec2(1));
    //vec4 data=gaussian_sample(normed);
    //data.x*=data.x;
    float normed_particle=data.x;
    //vec3 c=palette(normed_particle,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
    //vec3 c=palette(normed_particle,vec3(0.5),vec3(0.5),vec3(1.0),vec3(0.0,0.1,0.2));
// saturation or value slowly increasing if state stays the same
    float state_whole_part=floor(normed_particle*state_count)/float(state_count);
    vec3 c=palette(state_whole_part,col_offset,col_amplitute,col_freq,col_angle);
    //vec3 c=vec3(state_whole_part);
#if 0
    float state_fract_part=(normed_particle-state_whole_part)*float(state_count);
    
    if (state_whole_part==0)
    	state_fract_part=1;
    c=rgb2hsv(c);
    c.y*=state_fract_part;
    //c.z*=state_fract_part;
    c=hsv2rgb(c);
#endif
    //vec3 c=vec3(normed_particle);
    if(draw_food>0)
    	c.xyz=vec3(data.y);
    color=vec4(c,1);
    
}
]==],{}),
{
    uniforms={
    	{type="vec3",name="col_offset"},
    	{type="vec3",name="col_amplitute"},
    	{type="vec3",name="col_freq"},
    	{type="vec3",name="col_angle"},
    	{type="int",name="state_count"},
    	{type="int",name="draw_food"}
    },
    textures={
    	tex_main={texture=texture}
    },
}
)
function randomize_colors()
	local max_amplitude=0.8
	local max_freq=1
	local max_phase=2
	for i=1,3 do
		-- [==[ rand offset+ampl
			color_info.col_offset[i]=math.random()*max_amplitude
			color_info.col_amplitute[i]=(1-color_info.col_offset[i])*max_amplitude
		--]==]
		color_info.col_freq[i]=math.random()*max_freq
		color_info.col_angle[i]=math.random()*max_phase
	end
	draw_field.update_uniforms(color_info)
end
draw_field.update_uniforms(color_info)
function init_buffer(  )
	local init_cells=cl_kernels.init_cells
	init_cells:set(0,cell_fields[1])
	init_cells:set(1,cell_fields[2])
	init_cells:set(2,cell_food_fields[1])
	init_cells:set(3,cell_food_fields[2])
	init_cells:set(4,config.radius)
	init_cells:set(5,config.noise)
	init_cells:run(map_w*map_h)
end
function inject_food( scale )
	scale=scale or 1
	local inject_food=cl_kernels.inject_food
	inject_food:set(0,cell_food_fields[1])
	inject_food:set(1,cell_food_fields[2])
	inject_food:set(2,config.radius)
	inject_food:set(3,scale)
	inject_food:run(map_w*map_h)
end
function sim_tick(  )
    local cell_update=cl_kernels.cell_update
	cell_update:set(0,cell_fields[1])
	cell_update:set(1,cell_fields[2])
	cell_update:set(2,cell_food_fields[1])
	cell_update:set(3,cell_food_fields[2])
	cell_update:run(map_w*map_h)
	swap_cells()
end
function draw(  )

	--draw_field:update_uniforms(color_info)
	local update_texture=cl_kernels.update_texture

	update_texture:set(0,cell_fields[1])
	update_texture:set(1,cell_food_fields[1])

	update_texture:set(2,display_buffer)
	display_buffer:aquire()
	update_texture:run(map_w*map_h)
	display_buffer:release()
    draw_field.draw()
end
function save_img( id )
    img_buf_save=img_buf_save or make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    if id and type(id)=="number" then
    	img_buf_save:save(string.format("video/saved (%d).png",id),config_serial)
    else
    	img_buf_save:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
    end
end
function decomp_rule_id(id)
	local ret={}
	for i=1,max_state do
		ret[i]=id % (checked_cells)
		id=math.floor(id/checked_cells)
	end
	return ret
end
function random_hashes()
	hash_offsets={}
	for i=1,max_state do
		hash_offsets[i]=string.format("0x%x%x%x%x", math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255))
	end
end
function random_hashes_food()
	hash_offsets_food={}
	for i=1,max_state do
		hash_offsets_food[i]=string.format("0x%x%x%x%x", math.random(0,255),math.random(0,255),math.random(0,255),math.random(0,255))
	end
end
function random_weights()
	local fill_stable=24
	local fill_zero=2
	local fill_random=2

	local zero_fill_zero=8
	local zero_fill_state=20
	local weight_count=fill_stable+fill_zero+fill_random

	weight_table={string.format("#define WEIGHT_COUNT %d",weight_count)}
	weight_logic={"if(false);"}
	for cur_state=0,max_state-1 do
		table.insert(weight_logic,string.format("if(my_state==%d) return weight_table_%d[h %% WEIGHT_COUNT];",cur_state,cur_state))
		local wtbl={}
		if cur_state==0 then
			for j=1,zero_fill_zero do
				table.insert(wtbl,0)
			end
			for j=0,zero_fill_state-1 do
				table.insert(wtbl,j)
			end
			for j=1,weight_count-zero_fill_zero-zero_fill_state do
				table.insert(wtbl,math.random(0,max_state-1))
			end
		else
			for i=1,fill_stable do
				table.insert(wtbl,cur_state)
			end
			for i=1,fill_zero do
				table.insert(wtbl,0)
			end
			for j=1,weight_count-#wtbl do
				table.insert(wtbl,math.random(0,max_state-1))
			end
		end
		table.insert(weight_table,string.format("const int weight_table_%d[]={%s};",cur_state,table.concat(wtbl,", ")))
	end
	weight_table=table.concat(weight_table,"\n")
	weight_logic=table.concat(weight_logic,"\n")
end
local need_save=false
local sim_thread
function animate_radius()
	-- no of ticks to wait to grow
    local grow_timer=300
    -- no of ticks to capture frames
    local grow_timer_end=250
    local grow_capture_every=10
    -- radius to grow from up to, also number of frames
    local radius_min=25
    local radius_max=60
    local radius_step=0.25

    local frame_counter=0
    for r=radius_min,radius_max,radius_step do
        config.radius=r
        init_buffer()
        for j=1,grow_timer-grow_timer_end do
            coroutine.yield()
        end
        local grow_capture_timer=0
        for j=grow_timer_end,grow_timer do
            coroutine.yield()
            grow_capture_timer=grow_capture_timer+1
            if grow_capture_timer>grow_capture_every then
            	need_save=frame_counter
       			frame_counter=frame_counter+1
       			grow_capture_timer=0
       		end
        end
       	need_save=frame_counter
       	frame_counter=frame_counter+1
       	coroutine.yield()

    end
    sim_thread=nil
end
function animate_radius_persist()
	--[==[
		animate increasing radius, but overlay with last frame(s)
		if cell is unchanged increase it saturation, else saturation = 0
	--]==]
end
local need_step=0
function simulate_ui(tick)
	if not sim_thread then
        if imgui.Button("Simulate") then
           sim_thread=coroutine.create(animate_radius)
        end
    else
        if imgui.Button("Stop Simulate") then
            sim_thread=nil
        end
    end
    if tick then
	    if sim_thread then
	        --print("!",coroutine.status(sim_thread))
	        local ok,err=coroutine.resume(sim_thread)
	        if not ok then
	            print("Error:",err)
	            sim_thread=nil
	        end
	    end
	end
end
function update(  )
	local step_done=false
	__clear()
    __no_redraw()

    imgui.Begin("Cellular sparse")
    draw_config(config)
    local df=0
    if config.draw_food then
    	df=1
    else
    	df=0
    end
    if color_info.draw_food~=df then
   		color_info.draw_food=df
    	draw_field.update_uniforms({draw_food=df})
    end
    if imgui.Button("Reset") then
    	init_buffer()
    end
    if imgui.Button("Inject food") then
    	inject_food()
    end
    if imgui.Button("Step") then
    	need_step=1
    end
    imgui.SameLine()
    if imgui.Button("Multi Step") then
    	need_step=config.step_count
    end
    imgui.SameLine()
    if imgui.Button("Step Save") then
    	need_step=1
    	need_save=true
    end
    imgui.SameLine()
    if imgui.Button("Noise Step Save") then
    	init_buffer()
    	need_step=config.step_count
    	need_save=true
    end
    if imgui.Button("RandColor") then
    	randomize_colors()
    end
    if imgui.Button("RandRules") then
		random_hashes()
		random_hashes_food()
    	update_rules()
    	init_buffer()
    	need_step=config.step_count
    end
    if imgui.Button("RandWeights") then
    	random_weights()
    	update_rules()
    	init_buffer()
    	need_step=config.step_count
    end
    if not config.pause or need_step>0 then
    	sim_tick()
    	need_step=need_step-1
    	step_done=true
    end
    draw()
	simulate_ui(step_done)
 	if imgui.Button("Save") or (need_save and need_step==0) then
    	save_img(need_save)
    	need_save=false
    	--config.noise=config.noise-1
    end
    imgui.End()
end