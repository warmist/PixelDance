--[==[
	A sparse CA float version:

--]==]

require "common"

local win_w=1024
local win_h=1024

local oversample=1/4

local map_w=math.floor(win_w*oversample+1)
local map_h=math.floor(win_h*oversample+1)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size
local max_range=40
local range_zones=2
local zone_starts={4,6,8}
local max_state=10

config=make_config({
    {"pause",true,type="bool"},
    {"radius",5,type="int",min=1,max=100},
    {"noise",0,type="float",min=0,max=1},
    },config)


local need_reinit=(cell_fields==nil)
cell_fields=cell_fields or{
	opencl.make_buffer(map_w*map_h*4),
	opencl.make_buffer(map_w*map_h*4),
}

function swap_cells(  )
	local p=cell_fields[1]
	cell_fields[1]=cell_fields[2]
	cell_fields[2]=p
end
texture=textures:Make()
texture:use(1)
texture:set(map_w,map_h,FLTA_PIX)
local display_buffer=opencl.make_buffer_gl(texture)

local kernel_str=[==[
#line __LINE__

#define RADIUS $max_range
#define W $width
#define H $height

#define MAX_ZONE_ID 1
const int zone_starts[]={20};
#define STATE_COUNT $state_count
#define SAMPLE_TYPE 1
#define BORDER_ZERO 1
#define BORDER_MIRROR 0
int pos_to_index(int2 p)
{
	//int2 p2=clamp_pos(p);
	return p.x+p.y*W;
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
int find_zone_start(int rsqr)
{
	for(int i=0;i<MAX_ZONE_ID;i++)
	{
		if(zone_starts[i]*zone_starts[i]>=rsqr)
			return i;
	}
	return MAX_ZONE_ID;
}
void count_around(__global float* cells,int2 pos,int* state_out)
{
	int rr=RADIUS*RADIUS;
	int zone_ids[MAX_ZONE_ID+1]={};
	int counts[MAX_ZONE_ID+1]={};
	for(int dx=-RADIUS;dx<=RADIUS;dx++)
	for(int dy=-RADIUS;dy<=RADIUS;dy++)
	{
		int rsq=dx*dx+dy*dy;
		if(rsq<rr)
		{
			float sample=sample_at_pos_float(cells,pos+(int2)(dx,dy));
			int zone=find_zone_start(rsq);
#if SAMPLE_TYPE==1
			zone_ids[zone]+=floor(sample);
			//zone_ids[zone]+=sample;
			counts[zone]+=1;
#elif SAMPLE_TYPE==2
			zone_ids[zone]=(sample>zone_ids[zone])?sample:zone_ids[zone];
#endif
		}
	}
	for(int i=0;i<MAX_ZONE_ID+1;i++)
	{
#if SAMPLE_TYPE==1
		state_out[i]=zone_ids[i]/counts[i];
#else
		state_out[i]=zone_ids[i];
#endif
	}
}

$generated_rule_definition


const float cell_step=0.1;
__kernel void cell_update(
	__global float* cell_input,
	__global float* cell_output
	)
{
	int i=get_global_id(0);
	int max_i=W*H;

	if(i>=0 && i<max_i)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		//float2 pos_i=convert_float2(pos)-(float2)(W/2,H/2);
		//float cell_step=(1+0.25*length(pos_i)/(W/2))*0.01; //probably quite silly...
		float my_cell_f=cell_input[i];
		int my_cell=(floor(my_cell_f));

		float new_cell=0;
		int cell_state[MAX_ZONE_ID+1];
		count_around(cell_input,pos,cell_state);
		//int state_id=floor(cell_state[0])+floor(cell_state[1])*STATE_COUNT+floor(cell_state[2])*STATE_COUNT*STATE_COUNT; //TODO: gen this too
		//int state_id=floor(cell_state[0])+floor(cell_state[1])*STATE_COUNT+floor(cell_state[2])*STATE_COUNT*STATE_COUNT+floor(cell_state[3])*STATE_COUNT*STATE_COUNT*STATE_COUNT; //TODO: gen this too
		//int state_id=cell_state[0]+cell_state[1]*STATE_COUNT+cell_state[2]*STATE_COUNT*STATE_COUNT;intentionally wrong
		int state_id=cell_state[0]+cell_state[1]*STATE_COUNT+cell_state[2]*STATE_COUNT*STATE_COUNT+cell_state[3]*STATE_COUNT*STATE_COUNT*STATE_COUNT;
		if(false);
		$generated_rule_logic
		//something like if(my_cell==1) new_cell=rulebook_1[state_id];
#if 0
		if(cell_state[0]>=1)
			new_cell=1;
		else if(cell_state[1]>=1)
			new_cell=2;
		else if(cell_state[2]>=1)
			new_cell=3;
		else
			new_cell=0;
#endif
#if 1
		float cell_final_out=0;
		int new_cell_i=(floor(new_cell));
		if(my_cell!=new_cell_i)
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
#else
		float cell_final_out=new_cell;
#endif
		cell_output[i]=cell_final_out;
	}
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
__kernel void init_cells(
	__global float* cells1,
	__global float* cells2,
	int radius,
	float noise_level)
{
	int i=get_global_id(0);
	int max=W*H;;
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
		uint4 hash=(uint4)(i,0,0,0);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		#if 1
		if( true
			&& float_from_hash(hash).x<noise_level
			//&& length(pos_normed)<0.9
			//&& length(pos_normed)>0.87
			//&& fmod(length(pos_normed),0.4f)<0.3
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))<0.1
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))>0.05
			|| fmax(fabs(pos_i.x),fabs(pos_i.y))<radius
			//|| length(pos_i)<radius
			//&& length(pos_i)>radius/2
			//&& pos_normed.y<0.01
			//&& pos_normed.y*pos_normed.x<0.00008
			//&& fabs(pos_normed.y)>0.084
			//&& (pos.y%64==(32) || pos.y%64==(32))
		)
			v=1;
			//v=pos.x%COUNT_TYPES;
			//v=hash.x%COUNT_TYPES;
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
		float my_cell=cell_input[i];

		float4 col=(float4)(my_cell/(float)(STATE_COUNT),0.f,0.f,0.f);

		write_imagef(output_tex,pos,col);
	}
}
]==]

local cl_kernels
function update_kernels()
	local kern=advance_format(kernel_str,{
		max_range=max_range,
		width=map_w,
		height=map_h,
		generated_rule_definition=generated_rule_definition or "",
		generated_rule_logic=generated_rule_logic or "",
		state_count=max_state,
	})
	--print(kern)
	cl_kernels=opencl.make_program(kern)
end
update_kernels()
function gen_rule_def(id,rule)
	return string.format("const int rulebook_%d[]={%s};",id,table.concat(rule,", "))
end
function gen_rule_logic(id,rule)
	return string.format("else if(my_cell==%d) new_cell=rulebook_%d[state_id]-1;",id-1,id)
end
function update_rules()
	local rule_def={}
	for i,v in pairs(ruleset) do
		rule_def[i]=gen_rule_def(i,v)
	end
	generated_rule_definition=table.concat(rule_def,"\n")
	--print(generated_rule_definition)
	local rule_logic={}
	for i,v in pairs(ruleset) do
		rule_logic[i]=gen_rule_logic(i,v)
	end
	generated_rule_logic=table.concat(rule_logic,"\n")
	--print(generated_rule_logic)
	update_kernels()
end

color_info=color_info or {
	col_offset={0.5,0.5,0.5},
	col_amplitute={0.5,0.5,0.5},
	col_freq={1,1,1},
	col_angle={0,0.1,0.2},
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
    vec3 c=palette(normed_particle,col_offset,col_amplitute,col_freq,col_angle);
    //vec3 c=vec3(normed_particle);
    color=vec4(c,1);
    
}
]==],{}),
{
    uniforms={
    	{type="vec3",name="col_offset"},
    	{type="vec3",name="col_amplitute"},
    	{type="vec3",name="col_freq"},
    	{type="vec3",name="col_angle"},
    	{type="float",name="test"}
    },
    textures={
    	tex_main={texture=texture}
    },
}
)
function randomize_colors()
	for i=1,3 do
		-- [==[ rand offset+ampl
			color_info.col_offset[i]=math.random()
			color_info.col_amplitute[i]=1-color_info.col_offset[i]
		--]==]
		color_info.col_freq[i]=math.random()*4
		color_info.col_angle[i]=math.random()
	end

	draw_field.update_uniforms(color_info)
end
draw_field.update_uniforms(color_info)
function init_buffer(  )
	local init_cells=cl_kernels.init_cells
	init_cells:set(0,cell_fields[1])
	init_cells:set(1,cell_fields[2])
	init_cells:seti(2,config.radius)
	init_cells:set(3,config.noise)
	init_cells:run(map_w*map_h)
end

function sim_tick(  )
    local cell_update=cl_kernels.cell_update
	cell_update:set(0,cell_fields[1])
	cell_update:set(1,cell_fields[2])
	cell_update:run(map_w*map_h)
	swap_cells()
end
function draw(  )
	--draw_field:update_uniforms(color_info)
	local update_texture=cl_kernels.update_texture
	update_texture:set(0,cell_fields[1])
	update_texture:set(1,display_buffer)
	display_buffer:aquire()
	update_texture:run(map_w*map_h)
	display_buffer:release()
    draw_field.draw()
end
function save_img(  )
    img_buf_save=make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    img_buf_save:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function random_rule_state(cur_state)
	local ret={}
	local chance_stay=0.3
	local chance_random=0.5
	local chance_advance=0.0
	for i=0,math.pow(max_state,range_zones)-1 do
		--ret[i]=math.random(0,max_state)
		--  [==[
		local r=math.random()
		if r>1-chance_random then
			ret[i]=math.random(1,max_state)
		elseif r>1-(chance_advance+chance_random) then
			ret[i]=(cur_state+1)% max_state
		elseif r>1-(chance_stay+chance_random+chance_advance) then
			ret[i]=cur_state
		else --chance 0
			ret[i]=0
		end
		--]==]
	end
	return ret
end
function random_rules()
	ruleset={}
	for i=0,max_state do
		ruleset[i]=random_rule_state(i)
	end
	print("rules size:",#ruleset[1])
end
local need_step=false
function update(  )
	__clear()
    __no_redraw()

    imgui.Begin("Cellular sparse")
    draw_config(config)
    if imgui.Button("Reset") then
    	init_buffer()
    end
    if imgui.Button("Step") then
    	need_step=true
    end
    if imgui.Button("RandColor") then
    	randomize_colors()
    end
    if imgui.Button("RandRules") then
    	random_rules()
    	update_rules()
    	init_buffer()
    end
    if not config.pause or need_step then
    	sim_tick()
    	need_step=false
    end
    draw()
 	if imgui.Button("Save") then
    	save_img()
    end
    imgui.End()
end