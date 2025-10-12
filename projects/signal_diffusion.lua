--[[
	Experiments with diffusion:
		* inhibitory/signaling hormones
			- pos/neg
			- more complex (i.e. pos if low, neg if high, pos if very high)
		* veins (hormone highways)
			- some sort of "flow"? (i.e. instant transport?)
		* short range signaling
		* cells
			- stem
			- terminal
			- differentiation
			- advancing front
			- advancing head
			- "solo"
			- niches bathed in signals
		* "waves" of signals
	Implementation:
		- float layers x N
		- float diffusion amount per layer
			- low diffusion blockers
			- high diffusion veins
		- cell layer (type)
			- cell transformations
			- cell emmitance/absorbtion
			- cell diffusion coefs
		- two step:
			- diffusion step
			- cell update step:emit/absorb/transform/etc...

TODO/IDEAS:
	- shelled creature that slowly grows until max size
		-exoskelton
		-endoskeleton
	- a creature that invades shelled creature and eats it
	- blob that differentiates
		- front vs back
		- left/right
		- apendages
		- other features
	- veins+organs
		- veins:
			- need to grow out from "source"
			- organic looking
			- not too blobby
		- organs:
			- bloby
			- size limited
			- far enough from source?
	- try to systematize behaviors
		- tree growth
		- blob growth
		- various CA-like things
		- do the reaction-diffusion-like parameter map system
	- redo the system:
		- try lower rez signal layer
			- quad tree?
		- group signals (signal+inhibitor)
		- make all cells have same info/system

--]]
require "common"
local ffi=require "ffi"
local w=512
local h=512
config=make_config({
	{"paused",false,type="bool"},
	{"mult",1,type="float",min=0,max=10},
	{"field",0,type="choice",choices={"cells","growth","starve","growth inhibit","destruct","growth sum"}},
	{"field_sample",0,type="choice",choices={"growth","starve","growth inhibit","destruct","growth sum"}},
},config)


local cl_kernels=opencl.make_program[==[
#line __LINE__

//Cell types
#define CELL_TYPE_STEM 0
#define CELL_TYPE_STEM_ROOT 1
#define CELL_TYPE_VEIN 2
#define CELL_TYPE_ORGAN 3
#define CELL_TYPE_NODULE 4
#define CELL_TYPE_ROCK 5
#define CELL_TYPE_ROCK2 6
#define CELL_TYPE_DECAY_ROCK 7
#define CELL_TYPE_BLOB 8
#define CELL_TYPE_BLOB2 9

#define CELL_TYPE_LAST 9

#define CELL_MASK(X) (1<<X)
#define HAS_CELL(X,Y) ((X & CELL_MASK(Y))!=0)

#define FIELD_STEM_ROOT x
#define FIELD_STARVED y
#define FIELD_TRANSFORM_INHIBIT z
#define FIELD_DESTRUCT w

#define TRANS_THRESH 20
#define VEIN_SPAWN_THRESH 3.0
#define VEIN_PRUNE_STARVATION 1.0
#define TRANS_INHIBIT_THRESH 2000

#define DEFAULT_FLOW 0.02,0.05,0.01,0.01
#define DEFAULT_IO -0.001,-0.001,-0.025,0

#define STEM_EMIT 2.0,0,0,0
#define STEM_FLOW 0.5,0.01,0,0



#define ORGAN_EMIT 10.0
#define ORGAN_TRANS_THRESH 25
#define ORGAN_GROW_THRESH 100
#define ORGAN_STARVE_THRESH 5000
#define ORGAN_FLOW 0.01,0.4,0.02,0.01

#define NODULE_EMIT 0.1,ORGAN_EMIT,0,0
#define NODULE_FLOW 0.5,0.5,0,0


#define VEIN_FLOW 0.01,0.5,0.007,0.0
#define VEIN_EMIT 0,-0.05,0.5,0

#define ROCK_FLOW 0.0001,0.0001,0.0001,0.0001
#define ROCK_EMIT 0,0,0,0

#define DECAY_ROCK_EMIT -1,-1,-1,0.1
#define DECAY_ROCK_DESTRUCT 10

#define BLOB_MAX_GROW 0.35
#define BLOB_GROW 0.3
#define BLOB_DESTRUCT 5.5
#define BLOB_TRANSFORM_INHIBIT (0)
#define BLOB_TRANSFORM_DESTRUCT (-0)
#define BLOB_TRANSFORM_GROW (-1)

#define BLOB2_LIVE_STATE 2.7
#define BLOB2_SKIN_TRANSF -3
#define BLOB2_BONES_TRANSF 30

#define BLOB_EMIT 0.1,   0, 0.04,0.05
#define BLOB2_EMIT 0.5,   0.1, 0.5,0.05
#define BLOB_FLOW 0.3,0.05, 0.3, 0.4
#define LOG_FIELD_DECAY -0.0009

#define W 512
#define H 512
#define M_PI 3.1415926538
int2 clamp_pos(int2 p)
{
	return clamp(p,0,W-1);
}
int pos_to_index(int2 p)
{
	int2 p2=clamp_pos(p);
	return p2.x+p2.y*W;
}

float4 sample_at_pos(__global float4* arr,int2 p)
{
	if(p.x<0) p.x=W-1;
	if(p.x>=W) p.x=0;
	if(p.y<0) p.y=H-1;
	if(p.y>=H) p.y=0;
	float4 ret=arr[pos_to_index(p)];
	return ret;
}
float4 sum_around_L(__global float4* arr,__global float4* warr,int2 pos)
{
	float4 center=arr[pos_to_index(pos)];

	float4 wsum=0;
	float4 csum=0;
	float4 tmp1;
	float4 tmp2;

	tmp1=sample_at_pos(arr,pos+(int2)( 0, 1));
	tmp2=sample_at_pos(warr,pos+(int2)( 0, 1));
	wsum+=tmp2;
	csum+=tmp1*tmp2;

	tmp1=sample_at_pos(arr,pos+(int2)( 0, -1));
	tmp2=sample_at_pos(warr,pos+(int2)( 0, -1));
	wsum+=tmp2;
	csum+=tmp1*tmp2;

	tmp1=sample_at_pos(arr,pos+(int2)( 1, 0));
	tmp2=sample_at_pos(warr,pos+(int2)( 1, 0));
	wsum+=tmp2;
	csum+=tmp1*tmp2;

	tmp1=sample_at_pos(arr,pos+(int2)( -1, 0));
	tmp2=sample_at_pos(warr,pos+(int2)( -1, 0));
	wsum+=tmp2;
	csum+=tmp1*tmp2;

	wsum*=0.25f;
	csum*=0.25f;
	center=center*(1-wsum)+csum;

	return center;
}
//laplace but with higher order terms of |nabla u|^(2,3,4,...)
float4 sum_around_dunno(__global float4* arr,__global float4* warr,int2 pos)
{
	float4 center=arr[pos_to_index(pos)];

	float beta=-0.0000001;
	//TODO: gamma/delta params should be step size dependant!
	float gamma=0;
	float delta=0;

	float4 sum1=0;

	float4 tmp1;

	tmp1=sample_at_pos(arr,pos+(int2)( 0, 1));
	tmp1+=sample_at_pos(arr,pos+(int2)( 0, -1));
	tmp1*=0.25f;

	sum1+=tmp1*(1+tmp1*(beta+tmp1*(gamma+tmp1*delta)));



	tmp1=sample_at_pos(arr,pos+(int2)( 1, 0));
	tmp1+=sample_at_pos(arr,pos+(int2)( -1, 0));
	tmp1*=0.25f;

	sum1+=tmp1*(1+tmp1*(beta+tmp1*(gamma+tmp1*delta)));


	center=sum1;

	return center;
}
float4 sum_around_dunno2(__global float4* arr,__global float4* warr,int2 pos)
{
	float beta=-0.0;

	float4 sum1=0;

	float4 tmp1;
	float4 tmp2;


	tmp1=sample_at_pos(arr,pos+(int2)( 0, 1));
	tmp1+=sample_at_pos(arr,pos+(int2)( 0, -1));
	tmp1*=0.25f;
	sum1+=tmp1;

	tmp2=sample_at_pos(arr,pos+(int2)( 0, 1))-sample_at_pos(arr,pos+(int2)( 0, -1));
	tmp2*=tmp2*0.25f*0.25f*beta;
	sum1+=tmp2;

	tmp1=sample_at_pos(arr,pos+(int2)( 1, 0));
	tmp1+=sample_at_pos(arr,pos+(int2)( -1, 0));
	tmp1*=0.25f;
	sum1+=tmp1;


	tmp2=sample_at_pos(arr,pos+(int2)( 1, 0))-sample_at_pos(arr,pos+(int2)( -1, 0));
	tmp2*=tmp2*0.25f*0.25f*beta;
	sum1+=tmp2;

	return sum1;
}
float4 sum_around_mixed(__global float4* arr,__global float4* warr,int2 pos)
{
	float4 center=arr[pos_to_index(pos)];

	float beta=-0.0001;

	float4 sum1=0;

	float4 tmp1;

	tmp1=sample_at_pos(arr,pos+(int2)( 0, 1));
	tmp1+=sample_at_pos(arr,pos+(int2)( 0, -1));
	tmp1*=0.25f;

	sum1+=tmp1;



	tmp1=sample_at_pos(arr,pos+(int2)( 1, 0));
	tmp1+=sample_at_pos(arr,pos+(int2)( -1, 0));
	tmp1*=0.25f;

	sum1+=tmp1;


	tmp1=sample_at_pos(arr,pos+(int2)( 1, 1));
	tmp1+=sample_at_pos(arr,pos+(int2)( -1, -1));
	tmp1*=0.25f*0.25f;

	sum1+=tmp1*beta;

	tmp1=sample_at_pos(arr,pos+(int2)( -1, 1));
	tmp1+=sample_at_pos(arr,pos+(int2)( 1, -1));
	tmp1*=0.25f*0.25f;

	sum1+=tmp1*beta;

	center=sum1;

	return center;
}
#define WRITE_TEX_FIELD 0
__kernel void field_update(
	__global float4* input,
	__global float4* output,
	__global float4* winput,
	__global float4* field_params,
	float delta_t
	#if WRITE_TEX_FIELD
	,__write_only image2d_t output_tex
	#endif
	)
{
	int i=get_global_id(0);
	int max_i=W*H;
	float log_decay=LOG_FIELD_DECAY;
	float r_fixed=0.3;
	float r_width=0.2;
	if(i>=0 && i<max_i)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;

		float2 pos_normed;
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;

		float a=atan2(pos_normed.y,pos_normed.x);
		float r=length(pos_normed);
		float4 center=input[pos_to_index(pos)];
		float4 around=sum_around_L(input,winput,pos);

		float4 field_add=field_params[i];
#if 0 //mapping params
		float r_field=0.7;
		//float w_field=(length(pos_normed)-r_field)/(1-r_field);
		float w_field=(pos_normed.x+1)*0.5;
		float w_field2=(pos_normed.y+1)*0.5;
		w_field=min(w_field,1.0f);
		if(w_field>0)
		{
			field_add.FIELD_TRANSFORM_INHIBIT-=0.03*w_field;
			field_add.FIELD_STEM_ROOT+=0.03*w_field;
			//field_add.FIELD_DESTRUCT-=0.03*w_field;
		}
		if(w_field2>0)
		{
			//field_add.FIELD_TRANSFORM_INHIBIT-=0.04*w_field2;
			//field_add.FIELD_STEM_ROOT-=0.1*w_field2;
			field_add.FIELD_DESTRUCT-=0.07*w_field2+0.03;
		}
#endif
		around+=field_add*delta_t;
		around*=exp(delta_t*log_decay);
		//around=clamp(around.xy,0,1);
		around=max(around,0);
		//if(r>r_fixed && r<r_fixed+r_width)
		//	around=(float4)(0,(cos(a*7)+1)*(cos(r*3)+1)*10,0,0);
		//if(fabs(pos_normed.x)>0.2)
		//	around=center;

		output[i]=around;
	#if WRITE_TEX_FIELD
		float4 col=around;
		//float4 col=fabs(around-center);
		//col.x=max(col.x-col.z,0.0f);
		write_imagef(output_tex,pos,col);
	#endif
	}
}
int sample_at_pos_int(__global int* arr,int2 p)
{
	if(p.x<0) p.x=W-1;
	if(p.x>=W) p.x=0;
	if(p.y<0) p.y=H-1;
	if(p.y>=H) p.y=0;
	return arr[pos_to_index(p)];
}
int count_around(__global int* arr,int type,int2 pos)
{
	int ret=0;

	if(sample_at_pos_int(arr,pos+(int2)( 0, 1))==type) ret+=1;
	if(sample_at_pos_int(arr,pos+(int2)( 0, -1))==type) ret+=1;
	if(sample_at_pos_int(arr,pos+(int2)( 1, 0))==type) ret+=1;
	if(sample_at_pos_int(arr,pos+(int2)( -1, 0))==type) ret+=1;

	if(sample_at_pos_int(arr,pos+(int2)( 1, 1))==type) ret+=1;
	if(sample_at_pos_int(arr,pos+(int2)( 1, -1))==type) ret+=1;
	if(sample_at_pos_int(arr,pos+(int2)( -1, 1))==type) ret+=1;
	if(sample_at_pos_int(arr,pos+(int2)( -1, -1))==type) ret+=1;

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

__kernel void cell_update(
	__global int* cell_input,
	__global int* cell_output,
	__global float4* field_input,
	__global float4* field_output,
	__global float4* field_params,
	__global float4* field_weights
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
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;


		int my_cell=cell_input[i];
		float4 field_value=field_input[i];
		//cell changes
		if(my_cell==CELL_TYPE_STEM)
		{
			int mask=mask_around4(cell_input,pos);

			float value=((field_value.FIELD_STEM_ROOT-field_value.FIELD_TRANSFORM_INHIBIT)-TRANS_THRESH)/TRANS_THRESH;
			if( field_value.FIELD_TRANSFORM_INHIBIT<TRANS_INHIBIT_THRESH &&
				value>1 &&
				field_value.FIELD_STARVED>VEIN_SPAWN_THRESH
				)
			{
				//int veins_around=count_around(cell_input,CELL_TYPE_VEIN,pos);
				//if(veins_around<2 || (veins_around<3 && value>2))
				if(HAS_CELL(mask,CELL_TYPE_VEIN)||HAS_CELL(mask,CELL_TYPE_STEM_ROOT))
					my_cell=CELL_TYPE_VEIN;
			} else if (HAS_CELL(mask,CELL_TYPE_ORGAN)
			&& field_value.FIELD_STEM_ROOT>ORGAN_TRANS_THRESH
			&& field_value.FIELD_STARVED<ORGAN_GROW_THRESH
			)
			{
					my_cell=CELL_TYPE_ORGAN;
			}
			float delta_transform=field_value.FIELD_STEM_ROOT-field_value.FIELD_TRANSFORM_INHIBIT;
			if(delta_transform>BLOB_GROW && delta_transform<BLOB_MAX_GROW
				&& HAS_CELL(mask,CELL_TYPE_BLOB))
			{
				//field_value.FIELD_STEM_ROOT-=BLOB_GROW/2;
				field_value.FIELD_STEM_ROOT+=BLOB_TRANSFORM_GROW;
				field_value.FIELD_TRANSFORM_INHIBIT+=BLOB_TRANSFORM_INHIBIT;
				field_value.FIELD_DESTRUCT+=BLOB_TRANSFORM_DESTRUCT;
				my_cell=CELL_TYPE_BLOB;
			}
		} else if (my_cell==CELL_TYPE_ORGAN || my_cell==CELL_TYPE_NODULE)
		{
			if(field_value.FIELD_STARVED>ORGAN_STARVE_THRESH)
			{
				my_cell=CELL_TYPE_STEM;
			}
			/*else
			if(field_value.FIELD_STEM_ROOT>TRANS_THRESH)
			{
				int organ_around=count_around(cell_input,CELL_TYPE_ORGAN,pos);
				if(organ_around>7 && field_value.FIELD_STARVED<ORGAN_GROW_THRESH/2)
					my_cell=CELL_TYPE_NODULE;
			}*/
		} else if (my_cell==CELL_TYPE_VEIN)
		{
			int organ_around=count_around(cell_input,CELL_TYPE_ORGAN,pos);
			if(organ_around>4)
				my_cell=CELL_TYPE_ORGAN;
			if(field_value.FIELD_STARVED<VEIN_PRUNE_STARVATION)
			{
				my_cell=CELL_TYPE_STEM;

			}
		} else if (my_cell==CELL_TYPE_BLOB)
		{
			int mask=mask_around4(cell_input,pos);
			if(field_value.FIELD_DESTRUCT>BLOB_DESTRUCT)
			{
				//because this becomes rock, there is no point adding/removing stuff in the fields
				// they propagate very slow
				field_value.FIELD_STEM_ROOT+=BLOB_TRANSFORM_GROW;
				//field_value.FIELD_DESTRUCT+=BLOB_DESTRUCT/2;
				//field_value.FIELD_DESTRUCT-=BLOB_DESTRUCT;
				//field_value.FIELD_TRANSFORM_INHIBIT+=BLOB_DESTRUCT;
				//if(HAS_CELL(mask,CELL_TYPE_ROCK2))
				//	my_cell=CELL_TYPE_DECAY_ROCK;
				//else
					my_cell=CELL_TYPE_BLOB2;
			}
		} else if (my_cell==CELL_TYPE_BLOB2)
		{
			int mask=mask_around4(cell_input,pos);
			if(field_value.FIELD_STEM_ROOT<BLOB2_LIVE_STATE)
			{
				my_cell=CELL_TYPE_ROCK2;
			}
			else if (field_value.FIELD_STEM_ROOT-field_value.FIELD_TRANSFORM_INHIBIT<BLOB2_SKIN_TRANSF)
			{
				my_cell=CELL_TYPE_ROCK;
			}
			else if(field_value.FIELD_DESTRUCT>BLOB2_BONES_TRANSF)
			{
				my_cell=CELL_TYPE_BLOB;
				field_value.FIELD_DESTRUCT-=BLOB2_BONES_TRANSF;
			}
		}else if (my_cell==CELL_TYPE_DECAY_ROCK)
		{
			if(field_value.FIELD_DESTRUCT>DECAY_ROCK_DESTRUCT)
			{
				my_cell=CELL_TYPE_STEM;
				//field_value.FIELD_DESTRUCT-=DECAY_ROCK_DESTRUCT;
			}
		}

		cell_output[i]=my_cell;
		//update params and weights
		if(my_cell==CELL_TYPE_STEM)
		{
			//dead cell
			field_weights[i]=(float4)(DEFAULT_FLOW);
			field_params[i]=(float4)(DEFAULT_IO);
		}
		else if(my_cell==CELL_TYPE_STEM_ROOT)
		{
			field_weights[i]=(float4)(STEM_FLOW);
			field_params[i]=(float4)(STEM_EMIT);
		}
		else if(my_cell==CELL_TYPE_ORGAN)
		{
			float4 field_io=0;
			field_io.FIELD_STARVED=ORGAN_EMIT;
			field_weights[i]=(float4)(ORGAN_FLOW);
			field_params[i]=field_io;
		}
		else if(my_cell==CELL_TYPE_VEIN)
		{
			field_weights[i]=(float4)(VEIN_FLOW);
			field_params[i]=(float4)(VEIN_EMIT);
		}
		else if(my_cell==CELL_TYPE_NODULE)
		{
			field_weights[i]=(float4)(NODULE_FLOW);
			field_params[i]=(float4)(NODULE_EMIT);

		}
		else if(my_cell==CELL_TYPE_ROCK || my_cell==CELL_TYPE_ROCK2)
		{
			field_weights[i]=(float4)(ROCK_FLOW);
			field_params[i]=(float4)(ROCK_EMIT);
		}
		else if(my_cell==CELL_TYPE_DECAY_ROCK)
		{
			field_weights[i]=(float4)(ROCK_FLOW);
			field_params[i]=(float4)(DECAY_ROCK_EMIT);
		}
		else if(my_cell==CELL_TYPE_BLOB)
		{
			field_weights[i]=(float4)(BLOB_FLOW);
			field_params[i]=(float4)(BLOB_EMIT);
		}
		else if(my_cell==CELL_TYPE_BLOB2)
		{
			field_weights[i]=(float4)(BLOB_FLOW);
			field_params[i]=(float4)(BLOB2_EMIT);
		}
		field_output[i]=field_value;
	}
}
__kernel void update_texture(
	__global int* cell_input,
	__global float4* field_input,
	__write_only image2d_t output_tex,
	int field_id
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
		float4 field_value=field_input[i];
		float4 col;
		if(field_id==0)
		{
			col=(float4)(convert_float(my_cell)/CELL_TYPE_LAST);
		}
		else if(field_id==1)
		{
			col=(float4)(field_value.x);
		}
		else if(field_id==2)
		{
			col=(float4)(field_value.y);
		}
		else if(field_id==3)
		{
			col=(float4)(field_value.z);
		}
		else if(field_id==4)
		{
			col=(float4)(field_value.w);
		}
		else if(field_id==5)
		{
			col=(float4)(max(field_value.x-field_value.z,0.0f));
		}
		write_imagef(output_tex,pos,col);
	}
}

__kernel void init_grid(
	__global float4* output_grid1,
	__global float4* output_grid2,
	__global float4* output_weights,
	__global float4* output_params)
{
	int i=get_global_id(0);
	int max=W*H;//s.w*s.h;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float2 pos_normed;
		pos_normed.x=2*pos.x/(float)(W)-1.0;
		pos_normed.y=2*pos.y/(float)(H)-1.0;

		float r=0;
		float rdiff=0;
		float ri=0;
		output_grid1[i]=(float4)(r,r,0,0);
		output_grid2[i]=(float4)(r,r,0,0);
		output_weights[i]=(float4)(rdiff,0.5,0.5,0.5);

		output_params[i]=(float4)(ri,0,0,0);
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
		int v=CELL_TYPE_STEM;
		uint4 hash=(uint4)(i,0,0,0);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		#if 1
		if(  length(float_from_hash(hash).x)>0.999
		//	&&((pos_normed.y<-0.3 && pos_normed.y>-0.35) ||
		//	(pos_normed.y>0.3 && pos_normed.y<0.35))
			//&&length(pos_normed)>0.24
			//&&length(pos_normed-pos_organ)<0.3
			//&&pos.x==256
			)
			v=CELL_TYPE_BLOB;
		#endif
		#if 1
		hash.x=lowbias32(hash.x);
		if(  length(float_from_hash(hash).x)>0.999
		//	&&((pos_normed.y<-0.3 && pos_normed.y>-0.35) ||
		//	(pos_normed.y>0.3 && pos_normed.y<0.35))
			//&&length(pos_normed)>0.24
			//&&length(pos_normed-pos_organ)<0.3
			//&&pos.x==256
			)
			v=CELL_TYPE_ORGAN;
		#endif
		#if 1
		hash.x=lowbias32(hash.x);
		if(  length(float_from_hash(hash+2).x)>0.3
			&&length(pos_normed)>0.6
			&&length(pos_normed)<0.61
			)
			v=CELL_TYPE_ROCK;
		#endif
		#if 0
		//if(length(pos_normed-pos_root)<0.0125)
		//if(pos.x>=254 && pos.x<=257 && pos.y==256)
		if(pos.x==256)// && pos.y==256)
			v=CELL_TYPE_STEM_ROOT;
		#endif
		cells1[i]=v;
		cells2[i]=v;
	}
}
]==]

local need_reinit=(fields==nil)
fields=fields or{
	opencl.make_buffer(w*h*4*4),
	opencl.make_buffer(w*h*4*4),
}

field_params=field_params or opencl.make_buffer(w*h*4*4)
field_weights=field_weights or opencl.make_buffer(w*h*4*4)

cell_fields=cell_fields or{
	opencl.make_buffer(w*h*4),
	opencl.make_buffer(w*h*4),
}
function swap_fields(  )
	local p=fields[1]
	fields[1]=fields[2]
	fields[2]=p
end
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
//uniform int field_id;

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
#if 0
   	float v;
   	if(field_id==0)
   		v=data.x;
   	if(field_id==1)
   		v=data.y;
   	if(field_id==2)
   		v=data.z;
   	if(field_id==3)
   		v=data.w;
#else
	float v=data.x;
#endif
   	float tru=v-trunc(v);
   	//if(v<1)
	//	v=100;
	//if(field_id!=3)
   	//v=log(v+1);
   	//v=v/(v+1);

   	//float p=log(10/field_mult)/(10*field_mult);
   	//v=pow(v,p);
   	//v=pow(v,4.0f);
   	v=v*field_mult;
   	//v=gain(v,field_gain);
   	//v=sqrt(sqrt(v));
#if 1
   	vec3 c=palette(v,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
#else
   	vec3 c;
   	if(v<0.1)
   		c=vec3(0.08);//background
   	else if (v<0.7)
   		c=vec3(0.5,0.11,0.13);
   	else if(v<0.9)
   		c=vec3(0.5);
   	else
   		c=vec3(0.08);
#endif
   	//if(tru>0.8)
   	//	c=vec3(1);
    color=vec4(c,1);
}
]]
local time=0

function init_buffer(  )
	local init_grid=cl_kernels.init_grid
	init_grid:set(0,fields[1])
	init_grid:set(1,fields[2])
	init_grid:set(2,field_weights)
	init_grid:set(3,field_params)
	init_grid:run(w*h)

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
local pixel4=ffi.new("float4")
local group_size=30
local pixel4_group=ffi.new("float4[30]")
local plot_data={
	make_float_buffer(group_size,1),
	make_float_buffer(group_size,1),
	make_float_buffer(group_size,1),
	make_float_buffer(group_size,1)
}
--TODO: read cell info too
--TOOD: read combo as display selected thing
--TODO: show history slice (i.e. value over time)
function read_pixel(x,y,arr)
	local s=STATE.size
	local lx=math.floor((x/s[1])*w)
	local ly=math.floor((y/s[2])*h)

	--size,pointer,offset
	local pixel_size=4*4
	arr:get(pixel_size,pixel4,(lx+ly*w)*pixel_size)
	print(string.format("(%g,%g,%g,%g)",pixel4.d[0],pixel4.d[1],pixel4.d[2],pixel4.d[3]))
end
function get_sample(data)
	local samples={
		data.d[0],
		data.d[1],
		data.d[2],
		data.d[3],
		data.d[0]-data.d[2],
	}
	return samples[config.field_sample+1]
end
function read_pixel_group( x,y,arr )
	local s=STATE.size
	local lx=math.floor((x/s[1])*w)
	local ly=math.floor((y/s[2])*h)
	if lx>group_size/2 then
		lx=lx-math.floor(group_size/2)
	end
	--size,pointer,offset
	local pixel_size=4*4
	arr:get(pixel_size*group_size,pixel4_group,(lx+ly*w)*pixel_size)
	--print(string.format("(%g,%g,%g,%g)",pixel4_group[0].d[0],pixel4_group[0].d[1],pixel4_group[0].d[2],pixel4_group[0].d[3]))
	for i=0,group_size-1 do
		--for k=1,4 do
			--plot_data[k]:set(i,0,pixel4_group[i].d[k-1])
		--end
		plot_data[1]:set(i,0,get_sample(pixel4_group[i]))
	end
end
local mouse_update_needed=false
local diffuse_update_needed=300
local max_diffuse_update_per_update=30
local diffuse_updates_left=0
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Electrons")
	draw_config(config)

	--cl tick
	--setup stuff
	-- [==[
	if not config.paused then
		if diffuse_updates_left<=0 then
			local cell_update=cl_kernels.cell_update
			cell_update:set(0,cell_fields[1])
			cell_update:set(1,cell_fields[2])
			cell_update:set(2,fields[1])
			cell_update:set(3,fields[2])
			cell_update:set(4,field_params)
			cell_update:set(5,field_weights)
			cell_update:run(w*h)
			swap_cells()
			swap_fields()
		end
		--]==]
		-- [[
		if diffuse_updates_left<=0 then
			diffuse_updates_left=diffuse_update_needed
		end
		for i=1,math.min(max_diffuse_update_per_update,diffuse_updates_left) do

			local field_update=cl_kernels.field_update
			field_update:set(0,fields[1])
			field_update:set(1,fields[2])
			field_update:set(2,field_weights)
			field_update:set(3,field_params)
			field_update:set(4,1/diffuse_update_needed)
			--field_update:set(5,display_buffer)

			--  run kernel
			--display_buffer:aquire()
			field_update:run(w*h)
			--display_buffer:release()
			--]]
			swap_fields()
		end

		diffuse_updates_left=diffuse_updates_left-max_diffuse_update_per_update
	end
	local update_texture=cl_kernels.update_texture
	update_texture:set(0,cell_fields[1])
	update_texture:set(1,fields[1])
	update_texture:set(2,display_buffer)
	update_texture:seti(3,config.field)
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
	shader:set("field_mult",config.mult)
	--shader:set_i("field_id",config.field)

	shader:draw_quad()
	if imgui.Button("Save") then
		save_img()
	end
	if imgui.Button("Reset") then
		init_buffer()
	end
	imgui.PlotLines("Field1",plot_data[1].d,group_size)
	--imgui.PlotLines("Field2",plot_data[2].d,group_size)
	--imgui.PlotLines("Field3",plot_data[3].d,group_size)
	--imgui.PlotLines("Field4",plot_data[4].d,group_size)
	imgui.End()

	--flip input/output
	--[==[
	if not do_recenter then
		local b=particle_buffers[2]
		particle_buffers[2]=particle_buffers[1]
		particle_buffers[1]=b
	end
	--]==]
	local m1,mx,my=is_mouse_down(  )
	if m1 then
		mouse_update_needed={mx,my}
	end
	if m1 or mouse_update_needed then
		read_pixel_group(mouse_update_needed[1],mouse_update_needed[2],fields[1])
	end
end