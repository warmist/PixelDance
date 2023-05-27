--[[
	opencl cell/agent (one per cell) based sim

	TODO:
		* merge logic and atomic writes, then you could theoretically merge in the move too
--]]

require "common"
local ffi=require "ffi"
w=1024
h=1024
agent_count=100000
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
kern_logic,kern_target,kern_move,kern_init,kern_output=opencl.make_program(set_values(
[==[
#pragma FILE cl_kernel
#pragma LINE __LINE__
#define W $w$
#define H $h$
#define AGENT_MAX 100000
#define TIME_STEP 0.005f

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
	ret.x=v&0xFFFF;
	ret.y=(v>>16)&0xFFFF;
	return ret;
}
__kernel void update_agent_logic(__global __read_only int4* input,__read_only image2d_t static_layer,__global __write_only int4* output)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		int2 agent=input[i].xy;
		if(agent.x>0 && agent.x<W-1 && agent.y>0 && agent.y<H-1)
		{
			/*
			int2 d=unpack_coord(pcg((uint)i));
			d.x=d.x%3;
			d.y=d.y%3;
			d-=(int2)(1,1);
			*/
			int2 d=(int2)(0,-1);
			int2 target;
			target=agent+d;
			output[i].xy=agent;
			float4 col=read_imagef(static_layer,target);
			float4 col1=read_imagef(static_layer,target+(int2)(1,0));
			float4 col2=read_imagef(static_layer,target+(int2)(-1,0));
			if(col.r+col.g+col.b==0)
				output[i].zw=target;
			else
			{
				if(col1.r+col1.g+col1.b==0)
					output[i].zw=target+(int2)(1,0);
				else if(col2.r+col2.g+col2.b==0)
					output[i].zw=target+(int2)(-1,0);
				else
					output[i].zw=agent;
			}
		}
	}
}
__kernel void update_agent_targets(__global __read_only int4* input,__global volatile int* movement_counts)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		//int2 agent=input[i].xy;
		int2 tagent=input[i].zw;
		//if(agent.x>=0 && agent.x<W && agent.y>=0 && agent.y<H)
		//	atomic_inc(movement_counts+(agent.x+agent.y*W));
		if(tagent.x>=0 && tagent.x<W && tagent.y>=0 && tagent.y<H)
		{
			atomic_inc(movement_counts+(tagent.x+tagent.y*W));
		}
	}
}
__kernel void update_agent_move(__global __read_only int4* input,__global __read_only int* movement_counts,__global __write_only int4* output)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		int2 agent=input[i].zw;
		if(agent.x>=0 && agent.x<W && agent.y>=0 && agent.y<H)
		{
			if(movement_counts[agent.x+agent.y*W]==1)
			{
				output[i].xy=agent;
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

__kernel void init_agents(__global __write_only int4* output)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		#if 0
		int2 trg=unpack_coord((int)pcg((uint)i));
		output[i].x=trg.x % W;
		output[i].y=H-(trg.y % (H/3));
		#else
		int r=(int)pcg((uint)i);
		int j=i*10+r%10;
		output[i].x=j % (W-2)+1;
		output[i].y=H-(j / (W-2));
		#endif
	}
}
__kernel void output_to_texture(__global __read_only int4* input,__write_only image2d_t output_tex)
{
	int i=get_global_id(0);
	int max=AGENT_MAX;
	if(i>=0 && i<max)
	{
		float4 col;
		col.x=(float)i/(float)max;//cos((float)i*742.154+7745.0)*0.5+0.5;
		col.y=cos((float)i*1141.154+774.0)*0.5+0.5;
		col.z=cos((float)i*333.10+10.0)*0.5+0.5;
		int2 pos=input[i].xy;
		write_imagef(output_tex,pos,col);
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
	display_buffer:fill(w*h*16,4);
end
function update(  )
	__no_redraw()
	__clear()

	clear_counts()
	display_buffer:aquire()
	kern_logic:set(0,buffers[1])
	kern_logic:set(1,display_buffer)
	kern_logic:set(2,buffers[2])
	kern_logic:run(agent_count)
	display_buffer:release()

	kern_target:set(0,buffers[2])
	kern_target:set(1,move_count_buffer)
	kern_target:run(agent_count)

	kern_move:set(0,buffers[2])
	kern_move:set(1,move_count_buffer)
	kern_move:set(2,buffers[1])
	kern_move:run(agent_count)
	--output
	kern_output:set(0,buffers[2])
	kern_output:set(1,display_buffer)


	texture:use(1)
	if not texture:render_to(w,h) then
		error("failed to set framebuffer up")
	end
	__clear()
	__render_to_window()
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
end