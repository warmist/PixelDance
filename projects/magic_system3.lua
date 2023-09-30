--[[
	see magic_system2.lua
	but in opencl
--]]

require "common"

local win_w=1024
local win_h=1024
local oversample=1/4
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)


config=make_config({
    {"draw_trails",false,type="bool"},
    {"sim_agents",false,type="bool"},
    {"blob_count",5,type="int",min=1,max=max_tool_count},
    {"seed",0,type="int",min=0,max=10000000},
    {"outside_strength",1.0,type="float",min=0,max=2},
    {"tool_scale",0.25,type="float",min=0,max=2},

    {"draw_layer",0,type="int",min=0,max=2,watch=true},
    {"agent_whitepoint",1,type="floatsci",min=-8,max=1,watch=true},
    {"agent_gamma",1,type="float",min=0,max=2,watch=true},
},config)


AGENT_SIZE=4*8 --floats*(vec2 pos,vec2 speed,vec4 color)

cl_agent_buffers=cl_agent_buffers or {}
function resize_agents(agent_count)
	local size=agent_count*AGENT_SIZE
	if cl_agent_buffers.agent_count==nil or cl_agent_buffers.size~=size then
		cl_agent_buffers[1]=opencl.make_buffer(size)
		cl_agent_buffers[2]=opencl.make_buffer(size)
	end
end
resize_agents(max_agent_count)

texture=textures:Make()
texture:use(0)
texture:set(map_w,map_h,F_PIX)
local display_buffer=opencl.make_buffer_gl(texture)

kernels=opencl.make_program
[==[
#line __LINE__
__kernel void advance_particles(__global float* input,__global float* output,__read_only image2d_t read_tex,float time)
{
	
}
]==]



