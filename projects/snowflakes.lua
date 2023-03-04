--[[
	source: 
		* http://mkweb.bcgsc.ca/snowflakes/sciam.mhtml
		* https://blogs.scientificamerican.com/sa-visual/in-silico-flurries/
--]]

require "common"
local ffi=require "ffi"
w=1024
h=1024

local no_floats_per_pixel=4 --vapor, liquid, solid, (4 aligned for easier modification)

settings_type=[[
typedef struct _settings
{

	float vapor_density;
	float freezing;
	float m_melting;
	float g_melting;
	float alpha_attachment;
	float beta_attachment;
	float theta_attachment;

}settings;
]]

ffi.cdef(settings_type)

config=make_config({
    {"pause",false,type="bool"},
    {"growth_steps",100,type="int",min=100,max=30000,watch=true},

    --[[ rho ]]   	{"vapor_density",0.35,type="float",min=0.35,max=0.65,watch=true},
    --[[ kappa ]] 	{"freezing",0.000001,type="float",min=0.000001,max=0.025,watch=true},
    --[[ miu ]] 	{"m_melting",0.072,type="float",min=0.072,max=0.102,watch=true},
    --[[ gamma ]] 	{"g_melting",5.2e-5,type="float",min=5.2e-5,max=10e-5,watch=true},

    {"alpha_attachment",0.00001,type="float",min=0.00001,max=0.35,watch=true},
    {"beta_attachment",1.05,type="float",min=1.05,max=1.097,watch=true},
    {"theta_attachment",0.002,type="float",min=0.002,max=0.081,watch=true},
    },config)

function set_values(s,tbl)
	return s:gsub("%$([^%$]+)%$",function ( n )
		return tbl[n]
	end)
end

local cl_kernel,init_kernel
function remake_program()
cl_kernel,init_kernel=opencl.make_program(set_values(
[==[
#line __LINE__
#define W $w$
#define H $h$
#define FLOATS_PER_PIXEL $no_floats_per_pixel$

#define TIME_STEP 0.005f

$settings_type$

__kernel void update_grid(__global __read_only float4* input,__global __write_only float4* output,
	__write_only image2d_t output_tex,settings cfg)
{

}
__kernel void init_grid(__global __write_only float4* output,settings cfg)
{
	int i=get_global_id(0);
	int max=W*H;
	if(i>=0 && i<max)
	{
		output[i].x=cfg.vapor_density;
	}
}
]==],_G))
end
remake_program()

buffers={
	opencl.make_buffer(w*h*4*no_floats_per_pixel),
	opencl.make_buffer(w*h*4*no_floats_per_pixel)
}
texture=textures:Make()
texture:use(0)
texture:set(w,h,FLTA_PIX)

local display_buffer=opencl.make_buffer_gl(texture)
function update_settings()
	cfg_struct=cfg_struct or ffi.new("settings",{})
	local names={
	"vapor_density",
	"freezing",
	"m_melting",
	"g_melting",
	"alpha_attachment",
	"beta_attachment",
	"theta_attachment",
	}
	for i,v in ipairs(names) do
		cfg_struct[v]=config[v]
	end
end
update_settings()
function init_buffers(  )
	init_kernel:set(0,buffers[1])
	init_kernel:set(1,cfg_struct,ffi.sizeof("settings"))
	init_kernel:run(w*h)
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