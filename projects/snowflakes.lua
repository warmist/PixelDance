--[[
	source: 
		* http://mkweb.bcgsc.ca/snowflakes/sciam.mhtml
		* https://blogs.scientificamerican.com/sa-visual/in-silico-flurries/
--]]

require "common"
local ffi=require "ffi"
w=1024
h=1024

local no_floats_per_pixel=4 --is_boundary,solid, liquid,vapor

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

local kern_first,kern_second,init_kernel
function remake_program()
kern_first,kern_second,init_kernel=opencl.make_program(set_values(
[==[
#line __LINE__
#define W $w$
#define H $h$
#define FLOATS_PER_PIXEL $no_floats_per_pixel$

#define TIME_STEP 0.005f

$settings_type$

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
	return (p2.x+p2.y*W)*(FLOATS_PER_PIXEL/4);
}
//needs to calculate:
// * diffusion for diffusion
// * nearby_diffusion_mass for attachment
// * boundary, for bunch of stuff
float calc_around(__global __read_only float4* input,float4 self,int2 pos,float* neighbours,float* nearby_diffusion_mass)
{
	float4 weights=(float4)(1,0,0,1.0/7.0);
	float4 result=(float4)(0,0,0,0);
#define SAMPLE(dx,dy) pos_to_index(pos+(int2)(dx,dy))
	result+=self*(float4)(-7,0,0,1.0/7.0);;
	result+=input[SAMPLE(1,0)]*weights;
	result+=input[SAMPLE(0,1)]*weights;
	result+=input[SAMPLE(-1,0)]*weights;
	result+=input[SAMPLE(0,-1)]*weights;
	result+=input[SAMPLE(-1,1)]*weights;
	result+=input[SAMPLE(1,-1)]*weights;
	*neighbours=clamp(result.x,0,7);
	*nearby_diffusion_mass=result.w;
#undef SAMPLE
	return result.w*(1-self.x)+neighbours*self.w/7.0;
}
float calc_boundary_and_stuff(__global __read_only float4* input,int2 pos)
{
	float ret=0;
#define SAMPLE(dx,dy) pos_to_index(pos+(int2)(dx,dy))
	ret+=input[SAMPLE(0,0)].x*(-7);
	ret+=input[SAMPLE(1,0)].x;
	ret+=input[SAMPLE(0,1)].x;
	ret+=input[SAMPLE(-1,0)].x;
	ret+=input[SAMPLE(0,-1)].x;
	ret+=input[SAMPLE(-1,1)].x;
	ret+=input[SAMPLE(1,-1)].x;
#undef SAMPLE
	return ret;
}
void freezing(float* self,float boundary,float kappa)
{
	*self+=(*self)*(float4)(0,1-kappa,kappa,-1)*boundary;
}
__kernel void update_grid1(__global __read_only float4* input,__global __write_only float4* output,
	settings cfg)
{
	int i=get_global_id(0);
	int max=W*H;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float4 self=input[pos_to_index(pos)];

		float neighbours=0;
		float nearby_diffusion_mass=0;
		float boundary=0;
		float diff=calc_around(input,self,pos,&neighbours,&nearby_diffusion_mass);
		boundary=clamp(neighbours,0,1);
		//diffusion
		self.d=diff;
		//freezing
		freezing(&self,boundary,cfg.freezing);
		//attachment
		attachment(self,neighbours,boundary,cfg.beta_attachment,cfg.alpha_attachment,cfg.theta_attachment);
		//now other kernel...
		output[pos_to_index(pos)]=self;
	}
}
__kernel void update_grid2(__global __read_only float4* input,__global __write_only float4* output,
	__write_only image2d_t output_tex,settings cfg)
{
	int i=get_global_id(0);
	int max=W*H;
	if(i>=0 && i<max)
	{
		int2 pos;
		pos.x=i%W;
		pos.y=i/W;
		float4 self=input[pos_to_index(pos)];

		//... from other kernel
		//update neighbours and boundary
		float neighbours=calc_boundary_and_stuff(input,pos);
		neighbours=clamp(neighbours,0,7);
		boundary=clamp(neighbours,0,1);
		//melting
		
		//display
	}
}
__kernel void init_grid(__global __write_only float4* output,settings cfg)
{
	int i=get_global_id(0);
	int max=W*H;
	int i_center=(W/2)+(H/2)*W;
	if(i>=0 && i<max)
	{
		output[i]=(float4)(0,0,0,cfg.vapor_density);
		if(i==i_center)
		{
			output[i]=(float4)(1,1,0,0);
		}
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
	local size=ffi.sizeof("settings")
	kern_first:set(2,cfg_struct,size)
	kern_second:set(3,cfg_struct,size)
	init_kernel:set(1,cfg_struct,size)
end
update_settings()
function init_buffers(  )
	init_kernel:set(0,buffers[1])
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