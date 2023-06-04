--[[
	opencl cell/agent (one per cell) based sim

	TODO:
		* merge logic and atomic writes, then you could theoretically merge in the move too
--]]

require "common"
local ffi=require "ffi"
w=512
h=512
agent_count=15000
config=make_config({
    {"pause",false,type="bool"},
    },config)

function set_values(s,tbl)
	return s:gsub("%$([^%$]+)%$",function ( n )
		return tbl[n]
	end)
end

local kern_logic,kern_target,kern_move,kern_init,kern_output
function remake_program()
kern_logic,kern_target,kern_move,kern_init,kern_init_s,kern_output=opencl.make_program(set_values(
[==[
#pragma FILE cl_kernel
#pragma LINE __LINE__
#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable
#define W $w$
#define H $h$
#define AGENT_MAX 15000
#define TIME_STEP 0.005f
struct agent_state
{
	int pos;
	int target;
	int flags;
	int id; //or sth...
};
int2 clamp_pos(int2 p)
{
#if 0
	if(p.x<0)
		p.x=W-1;
	if(p.y<0)
		p.y=H-1;
	if(p.x>=W)
		p.x=0;
	if(p.y>=H)
		p.y=0;
	return p;
#else
	return clamp(p,0,W-1);
#endif
}
int pos_to_index(int2 p)
{
	int2 p2=clamp_pos(p);
	return (p2.x+p2.y*W);
}
uint pcg(uint v)
{
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}
int2 unpack_coord(int v)
{
	int2 ret;
	ret.x=abs(v&0xFFFF);
	ret.y=abs((v>>16)&0xFFFF);
	return ret;
}
int pack_coord(int2 v)
{
	int ret=(v.x&0xFFFF) | ((abs(v.y)&0xFFFF)<<16);
	return ret;
}
__kernel void update_agent_logic(__global __read_only struct agent_state* input,
	__global __read_only int* static_layer,
	__global __read_only int* dynamic_layer,
	__global __write_only struct agent_state* output,int seed)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		int2 pos=unpack_coord(input[i].pos);
		if(pos.x>0 && pos.x<W-1 && pos.y>0 && pos.y<H-1)
		{
			/*
			int2 d=unpack_coord(pcg((uint)i));
			d.x=d.x%3;
			d.y=d.y%3;
			d-=(int2)(1,1);
			*/
			int2 d=(int2)(0,-1);
			int2 target;
			target=pos+d;
			output[i].pos=input[i].pos;
		#if 0
			float4 col=read_imagef(static_layer,target);
			float4 col1=read_imagef(static_layer,target+(int2)(1,0));
			float4 col2=read_imagef(static_layer,target+(int2)(-1,0));
			if(dot(col,col)==0)
				output[i].target=target;
			else
			{
				if(dot(col1,col1)==0)
					output[i].target=target+(int2)(1,0);
				else if(dot(col2,col2)==0)
					output[i].target=target+(int2)(-1,0);
				else
					output[i].target=agent;
			}
		#else
			uint r=pcg((uint)(seed+i));

			int col=static_layer[target.x+target.y*W]+dynamic_layer[target.x+target.y*W];
			int col1=static_layer[target.x+1+target.y*W]+dynamic_layer[target.x+1+target.y*W];
			int col2=static_layer[target.x-1+target.y*W]+dynamic_layer[target.x-1+target.y*W];

			int col3=static_layer[pos.x+1+pos.y*W]+dynamic_layer[pos.x+1+pos.y*W];
			int col4=static_layer[pos.x-1+pos.y*W]+dynamic_layer[pos.x-1+pos.y*W];
			int id=input[i].id;
			output[i]=input[i];
			output[i].target=pack_coord(pos);
			if(col==0)
				output[i].target=pack_coord(target);
			else
			{
				bool moved=false;
				if(r%2)
				{
					if(col1==0)
					{
						output[i].target=pack_coord(target+(int2)(1,0));
						moved=true;
					}
				}
				else
				{
					if(col2==0)
					{
						output[i].target=pack_coord(target+(int2)(-1,0));
						moved=true;
					}
				}
				if(!moved && id==1)
				{
					if(r%2==0)
					{
						if(col3==0)
						{
							output[i].target=pack_coord(pos+(int2)(1,0));
							moved=true;
						}
					}
					else
					{
						if(col4==0)
						{
							output[i].target=pack_coord(pos+(int2)(-1,0));
							moved=true;
						}
					}
				}
			}
		#endif
		}
	}
}
void increment(int2 pos,__global volatile int* movement_counts)
{
	if(pos.x>=0 && pos.x<W && pos.y>=0 && pos.y<H)
	{
		atomic_inc(movement_counts+(pos.x+pos.y*W));
	}
}
__kernel void update_agent_targets(__global __read_only struct agent_state* input,__global volatile int* movement_counts)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		int2 pos=unpack_coord(input[i].pos);
		int2 target=unpack_coord(input[i].target);
		increment(pos,movement_counts);
		increment(target,movement_counts);
	}
}
__kernel void update_agent_move(__global __read_only struct agent_state* input,__global __read_only int* movement_counts,__global __write_only struct agent_state* output)
{
	/*
		TODO:
			* move +
			* grow (move without clear at source)
			* exchange (only static with dynamic)
			* die?
			* transforms might happen here too
	*/
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{

		int2 trg=unpack_coord(input[i].target);
		if(trg.x>=0 && trg.x<W && trg.y>=0 && trg.y<H)
		{
			if(movement_counts[trg.x+trg.y*W]==1)
			{
				//output[i]=input[i];
				output[i].pos=input[i].target;
				output[i].target=input[i].target;
				output[i].flags=input[i].flags;
				output[i].id=input[i].id;
			}
			else
				output[i]=input[i];
		}
		else
		{
			output[i]=input[i];
		}
	}
}

__kernel void init_agents(__global __write_only struct agent_state* output)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		#if 0
		int2 trg=unpack_coord((int)pcg((uint)i*7846));
		output[i].x=abs(trg.x) % W;
		output[i].y=H-(abs(trg.y) % (H/3));
		#else
		int r=(int)pcg((uint)i);
		int density=3;
		int j=i*density+abs(r)%density;
		output[i].pos=pack_coord( (int2)(j % (W-2)+1,H-(j / (W-2))) );
		output[i].id=abs(r)%2;
		#endif
	}
}
__kernel void init_static(__global __write_only int* output)
{
	int i=get_global_id(0);
	int max=W*H;
	if(i>=0 && i<max)
	{
		int x=i%W;
		int y=i/W;
		int dx=x-W/2;
		int dy=y;
		int d=dx*dx+dy*dy;
		//float c=cos((float)i*5487697347779999578.15+4897778787.36)*0.5+0.5;
		uint r=pcg(i^0x4a67fd);
		/*if(r%5==0 && y<600)
			output[i]=1;
		else if(r%4==0 && y<300 && d>100000)
			output[i]=1;
		else if(r%3==0 && y<300)
			output[i]=1;
		else*/
		if(d<100000)
			output[i]=1;
		else
			output[i]=0;
	}
}
//from: https://www.alanzucconi.com/2017/07/15/improving-the-rainbow-2/
float3 bump3y (float3 x, float3 yoffset)
{
    float3 y = 1 - x * x;
    y = clamp(y-yoffset,0.0f,1.0f);
    return y;
}
float3 spectral_zucconi6 (float w)
{
    // w: [400, 700]
    // x: [0,   1]
    //fixed x = clamp((w - 400.0)/ 300.0,0,1);
    float x=w;
    float3 c1 = (float3)(3.54585104, 2.93225262, 2.41593945);
    float3 x1 = (float3)(0.69549072, 0.49228336, 0.27699880);
    float3 y1 = (float3)(0.02312639, 0.15225084, 0.52607955);
    float3 c2 = (float3)(3.90307140, 3.21182957, 3.96587128);
    float3 x2 = (float3)(0.11748627, 0.86755042, 0.66077860);
    float3 y2 = (float3)(0.84897130, 0.88445281, 0.73949448);
    return
        bump3y(c1 * (x - x1), y1) +
        bump3y(c2 * (x - x2), y2) ;
}
__kernel void output_to_texture(__global __read_only struct agent_state* input,__global __write_only int* static_dynamic_layer,__write_only image2d_t output_tex)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		float4 colors[2]={
			(float4)(0.7,0.75,.8,1),
			(float4)(0.8,0.2,0.3,1),
		};
		float4 col;
		float v=(float)i/(float)max;
		//col.xyz=spectral_zucconi6(v);
		int id=clamp(input[i].id,0,1);
		col=colors[id];
		int2 pos=unpack_coord(input[i].pos);
		col.w=1;
		write_imagef(output_tex,pos,col);
		static_dynamic_layer[pos.x+pos.y*W]=i;
	}
}

]==],_G))
end


remake_program()

buffers={
	opencl.make_buffer(agent_count*16),
	opencl.make_buffer(agent_count*16)
}
move_count_buffer=opencl.make_buffer(w*h*4)
static_layer_buffer=opencl.make_buffer(w*h*4)
sd_layer_buffer=opencl.make_buffer(w*h*4)

texture=textures:Make()
texture:use(0)
texture:set(w,h,FLTA_PIX)

local display_buffer=opencl.make_buffer_gl(texture)
shader=shaders.Make[[
#version 330
#line __LINE__

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;

void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec3 v=texture(tex_main,normed).xyz;
	//v=pow(v,vec3(2.2));

	color.xyz=v;
	color.w=1;
}
]]
function init_buffers(  )
	kern_init:set(0,buffers[1])
	kern_init:run(agent_count)

	static_layer_buffer:fill_i(w*h*4,1)
	-- [[
	kern_init_s:set(0,static_layer_buffer)
	kern_init_s:run(w*h)
	--]]
end
init_buffers()

function save_img( path )
	local size=STATE.size
    local img_buf_save=make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config or {}) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    img_buf_save:save(path or string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function clear_counts(  )
	move_count_buffer:fill_i(w*h*4,1)
end
function clear_display(  )
	sd_layer_buffer:fill_i(w*h*4,1);
end
paused=false
function update(  )
	__no_redraw()
	__clear()
	local do_step=imgui.Button("Step")
	if imgui.RadioButton("Paused",paused) then
		paused=not paused
	end
	if do_step or not paused then
		clear_counts()
		kern_logic:set(0,buffers[1])
		kern_logic:set(1,static_layer_buffer)
		kern_logic:set(2,sd_layer_buffer)
		kern_logic:set(3,buffers[2])
		kern_logic:set(4,math.random(0,999999999))
		kern_logic:run(agent_count)

		kern_target:set(0,buffers[2])
		kern_target:set(1,move_count_buffer)
		kern_target:run(agent_count)

		kern_move:set(0,buffers[2])
		kern_move:set(1,move_count_buffer)
		kern_move:set(2,buffers[1])
		kern_move:run(agent_count)
		--output
	end
		clear_display()
		kern_output:set(0,buffers[2])
		kern_output:set(1,sd_layer_buffer)
		kern_output:set(2,display_buffer)


		display_buffer:aquire()
		kern_output:run(agent_count)
		display_buffer:release()
	
	--gl draw
	shader:use()
	texture:use(1)
	shader:set_i("tex_main",1)
	shader:draw_quad()
	if imgui.Button("save") then
		save_img()
	end
	-- [[
	--if do_step then
		texture:use(1)
		if not texture:render_to(w,h) then
			error("failed to set framebuffer up")
		end
		__clear()
		__render_to_window()
	--end
	--]]
end