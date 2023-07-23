--[[
	opencl cell/agent (one per cell) based sim

	TODO:
		* merge logic and atomic writes, then you could theoretically merge in the move too
--]]

require "common"
local ffi=require "ffi"
w=256
h=256
agent_count=15000
config=make_config({
    {"pause",true,type="bool"},
    },config)

function set_values(s,tbl)
	return s:gsub("%$([^%$]+)%$",function ( n )
		return tbl[n]
	end)
end

local kern_logic,kern_target,kern_move,kern_init
function remake_program()
kern_logic,kern_target,kern_move,kern_init,kern_init_s,kern_add=opencl.make_program(set_values(
[==[
//#file cl_kernel
#line __LINE__

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
#define FLAG_DEAD 1
#define FLAG_SLEEPING 2
#define FLAG_MOVE_EXCHANGE 4
#define FLAG_MOVE_GROW 8
#line __LINE__
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
	v=clamp_pos(v);
	int ret=(v.x&0xFFFF) | ((abs(v.y)&0xFFFF)<<16);
	return ret;
}
enum material{
	MAT_NONE,
	MAT_SAND,
	MAT_WATER_L,
	MAT_WATER_R,
	MAT_WALL,
	MAT_LAST
};
enum directions{
	DIR_E ,
	DIR_SE,
	DIR_S ,
	DIR_SW,
	DIR_W ,
	DIR_NW,
	DIR_N ,
	DIR_NE
};
#define OFFSET_DIR_E(pos)  (pos+(int2)( 1, 0))
#define OFFSET_DIR_SE(pos) (pos+(int2)( 1,-1))
#define OFFSET_DIR_S(pos)  (pos+(int2)( 0,-1))
#define OFFSET_DIR_SW(pos) (pos+(int2)(-1,-1))
#define OFFSET_DIR_W(pos)  (pos+(int2)(-1, 0))
#define OFFSET_DIR_NW(pos) (pos+(int2)(-1, 1))
#define OFFSET_DIR_N(pos)  (pos+(int2)( 0, 1))
#define OFFSET_DIR_NE(pos) (pos+(int2)( 1, 1))


void load_around(__global __read_only int* static_layer,
				 __global __read_only int* dynamic_layer,
				 int2 target,int* around)
{
	#define LOOKUP(dx,dy) static_layer[pos_to_index(target+(int2)(dx,dy))]*1000+abs(dynamic_layer[pos_to_index(target+(int2)(dx,dy))])
	around[DIR_E] =LOOKUP( 1, 0);
	around[DIR_SE]=LOOKUP( 1,-1);
	around[DIR_S] =LOOKUP( 0,-1);
	around[DIR_SW]=LOOKUP(-1,-1);
	around[DIR_W] =LOOKUP(-1, 0);
	around[DIR_NW]=LOOKUP(-1, 1);
	around[DIR_N] =LOOKUP( 0, 1);
	around[DIR_NE]=LOOKUP( 1, 1);
	#undef LOOKUP
}
bool can_move_into(int id_self,int id_target)
{
	int material_density[]={
		0,
		5,
		1,
		1,
		99
	};
	if(id_target>=MAT_LAST)
		return false;
	return material_density[id_self]>material_density[id_target];
}
__kernel void update_agent_logic(__global __read_only struct agent_state* input,
	__global __read_only int* static_layer,
	__global __read_only int* dynamic_layer,
	__global __write_only struct agent_state* output,
	int seed,
	int step,
	__global volatile int* agent_count)
{
	int i=get_global_id(0);
	int count=agent_count[step];
	if(i>=0 && i<count)
	{
		struct agent_state agent=input[i];
		struct agent_state agent_out=agent;
		int2 pos=unpack_coord(agent.pos);
		pos=clamp_pos(pos);
		if(!(agent.flags & (FLAG_SLEEPING|FLAG_DEAD)))
		{
			int2 pp=unpack_coord(pcg((uint)i));
			/*
			int2 d=unpack_coord(pcg((uint)i));
			d.x=d.x%3;
			d.y=d.y%3;
			d-=(int2)(1,1);
			*/

			uint r=pcg((uint)(seed+i));
			int self_pos=abs(dynamic_layer[pos_to_index(pos)]);
			if(self_pos!=agent.id)
			{
				agent_out.flags|=FLAG_DEAD;
				output[i]=agent_out;
				return;
			}
			int around[8];
			load_around(static_layer,dynamic_layer,pos,around);
			int id=agent.id;

			agent_out.target=pack_coord(pos);
			/*
				NB: the movement choice logic is that even if there is a valid position to move into, it must not happen
					100% of time as it might deadlock with another particle that has only that spot
			*/
			if(can_move_into(id,around[DIR_S]))
			{
				agent_out.target=pack_coord(OFFSET_DIR_S(pos));
				//if(id==MAT_SAND && (around[DIR_S]==MAT_WATER_R || around[DIR_S]==MAT_WATER_L))
				{
					agent_out.flags|=FLAG_MOVE_EXCHANGE;
				}
			}
			else
			{
				bool moved=false;
				if(r%3==0)
				{
					if(can_move_into(id,around[DIR_SE]))
					{
						agent_out.target=pack_coord(OFFSET_DIR_SE(pos));
						agent_out.flags|=FLAG_MOVE_EXCHANGE;
						moved=true;
					}
					else if(can_move_into(id,around[DIR_SW]))
					{
						agent_out.target=pack_coord(OFFSET_DIR_SW(pos));
						agent_out.flags|=FLAG_MOVE_EXCHANGE;
						moved=true;
					}
				}
				else if(r%3==1)
				{
					if(can_move_into(id,around[DIR_SW]))
					{
						agent_out.target=pack_coord(OFFSET_DIR_SW(pos));
						agent_out.flags|=FLAG_MOVE_EXCHANGE;
						moved=true;
					}
					else if(can_move_into(id,around[DIR_SE]))
					{
						agent_out.target=pack_coord(OFFSET_DIR_SE(pos));
						agent_out.flags|=FLAG_MOVE_EXCHANGE;
						moved=true;
					}
				}
				if(!moved && id==MAT_WATER_L && r%2==1)
				{
					if(around[DIR_W]==MAT_NONE)
					{
						agent_out.target=pack_coord(OFFSET_DIR_W(pos));
						moved=true;
					}
					else
					{
						agent_out.id=MAT_WATER_R;
					}
				}
				if(!moved && id==MAT_WATER_R && r%2==1)
				{
					if(around[DIR_E]==MAT_NONE)
					{
						agent_out.target=pack_coord(OFFSET_DIR_E(pos));
						moved=true;
					}
					else
					{
						agent_out.id=MAT_WATER_L;
					}
				}
				if(!moved && ((r^0x54f87)%222==221))
					agent_out.flags |= FLAG_SLEEPING;
			}
		}
		output[i]=agent_out;
	}
}

void increment(int2 pos,__global volatile int* movement_counts)
{
	atomic_inc(movement_counts+pos_to_index(pos));
}
__kernel void update_agent_targets(
	__global __read_only struct agent_state* input,
	__global volatile int* movement_counts,
	int step,
	__global volatile int* agent_count)
{
	int i=get_global_id(0);
	int count=agent_count[step];
	if(i>=0 && i<count)
	{
		int2 pos=unpack_coord(input[i].pos);
		int2 target=unpack_coord(input[i].target);
		increment(pos,movement_counts);
		//if(target.x!=pos.x || target.y!=pos.y)
		increment(target,movement_counts);
	}
}
void wake_around(int2 pos, __global volatile int* wake_buffer)
{
	atomic_inc(wake_buffer+pos_to_index(pos+(int2)(1,0)));
	atomic_inc(wake_buffer+pos_to_index(pos+(int2)(-1,0)));
	atomic_inc(wake_buffer+pos_to_index(pos+(int2)(0,1)));
	atomic_inc(wake_buffer+pos_to_index(pos+(int2)(0,-1)));
	///*
	atomic_inc(wake_buffer+pos_to_index(pos+(int2)(1,1)));
	atomic_inc(wake_buffer+pos_to_index(pos+(int2)(-1,1)));
	atomic_inc(wake_buffer+pos_to_index(pos+(int2)(-1,-1)));
	atomic_inc(wake_buffer+pos_to_index(pos+(int2)(1,-1)));
	//*/
}
__kernel void update_agent_move(
	__global __read_only struct agent_state* input,
	__global __read_only int* movement_counts,
	__global __write_only struct agent_state* output,
	__global int* static_dynamic_layer,
	int step,
	__global volatile int* agent_count,
	__global volatile int* wake_buffer)
{
	/*
		TODO:
			* move +
			* grow (move without clear at source)
			* exchange (only static with dynamic)
			* die?
			* transforms might happen here too
	*/
	/*
		general logic v1:
			if agent survives:
				increment counter, copy over to output
			if agent wakes up static:
				//increment counter, create new agent
				//NOTE: it can trigger multiple times!!!?
				mark it in static layer?
			if agent dies:
				noop
			if agent sleeps:
				write to static layer your info
		general logic v2:
			if agent survives:
				mark as alive in flags
			if agent wakes up static:
				lookup static id for agent, mark as alive in flags (slow? needs atomic flag access?)
			if agent dies:
				mark as dead
			if agent sleeps:
				mark as sleeping in flags

			TODO: add compact step (drop all dead)
			TODO: how to create new particles?
		general logic v3:
			if tile @ pos is not me, die
			select where to go
			increment pos and target pos
			move if counter at pos is 1 (i.e. only i want to go there)
			draw particles to texture


	*/
	int i=get_global_id(0);
	int count=min(agent_count[step],AGENT_MAX);
	//int count=AGENT_MAX;
	if(i>=0 && i<count)
	{
		struct agent_state agent=input[i];
		int2 trg=unpack_coord(agent.target);
		if(!(agent.flags & FLAG_DEAD))
		{
			if(agent.flags & FLAG_SLEEPING)
			{
				int2 pos=unpack_coord(agent.pos);
				static_dynamic_layer[pos.x+pos.y*W]=-agent.id;
			}
			else
			{
				struct agent_state new_agent=agent;
				int new_id=atomic_inc(agent_count+(step+1)%2);
				//int new_id=i;
				if(new_id<AGENT_MAX)
				{
					int2 pos=unpack_coord(agent.pos);
					if(movement_counts[trg.x+trg.y*W]==1)
					{
						//new_agent.pos=pack_coord((int2)(new_id%W,new_id/W));
						static_dynamic_layer[pos.x+pos.y*W]=0; //clear old position
						new_agent.pos=agent.target;
						if(agent.flags & FLAG_MOVE_GROW)
						{
							int2 pos=unpack_coord(agent.pos);
							static_dynamic_layer[pos.x+pos.y*W]=-agent.id;
						}
						else if(true/*agent.flags & FLAG_MOVE_EXCHANGE*/)
						{
							int id2=static_dynamic_layer[trg.x+trg.y*W];
							static_dynamic_layer[pos.x+pos.y*W]=id2;
						}
						static_dynamic_layer[trg.x+trg.y*W]=agent.id;
						wake_around(pos,wake_buffer);
						wake_around(trg,wake_buffer);
					}
					else
					{
						static_dynamic_layer[pos.x+pos.y*W]=agent.id;
						/*uint r=pcg((uint)(step*784654+i));
						if((r^0x54874 % 77)==0)
						{
							new_agent.flags|=FLAG_SLEEPING;
						}*/
					}

					output[new_id]=new_agent;
				}
			}
		}
	}
}

__kernel void init_agents(
__global __write_only struct agent_state* output,
__global __write_only int* agent_count)
{
	int i=get_global_id(0);
	int count=AGENT_MAX;
	if(i>=0 && i<count)
	{
		#if 0
		int2 trg=unpack_coord((int)pcg((uint)i*7846));

		#else
		int density=6;
		int r=(int)pcg((uint)i^0x484234);
		int j=i*density+abs(r)%density;
		int2 trg=(int2)(j % (W-2)+1,H-(j / (W-2)));
		#endif
		output[i].pos=pack_coord( trg );
		output[i].target=pack_coord( trg );
		output[i].id=abs(r^0x8434af)%4;
		//output[i].id=MAT_WATER_L;
		output[i].flags=0;
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
		int rad=W/3;

		//float c=cos((float)i*5487697347779999578.15+4897778787.36)*0.5+0.5;
		uint r=pcg(i^0x4a67fd);
		/*if(r%5==0 && y<600)
			output[i]=1;
		else if(r%4==0 && y<300 && d>100000)
			output[i]=1;
		else if(r%3==0 && y<300)
			output[i]=1;
		else*/
		if(d<rad*rad)
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

__kernel void add_static_layer(
	__global __read_only int* static_layer,
	__global __read_only int* static_dynamic_layer,
	__write_only image2d_t output_tex,

	int step,
	__global volatile int* agent_count,
	__global __write_only struct agent_state* output,
	__global __read_only int* wake_buffer)
{
	int i=get_global_id(0);
	if(i>=0 && i<W*H)
	{
		//float mv=(float)movement_counts[i];
		//mv/=3.0;
		float4 col_out=(float4)(0,0,0,0);
		int2 pos=(int2)(i%W,i/W);

		float4 colors[5]={
			(float4)(0,0,0,1),
			(float4)(0.7,0.75,.8,1),
			(float4)(0.8,0.2,0.3,1),
			(float4)(0.9,0.5,0.8,1),
			(float4)(0.3,0.4,0.4,1),
		};
		bool write=false;
		//draw dynamic layer
		int oid=static_dynamic_layer[i];
		if(oid!=MAT_NONE)
		{
			int id=clamp((int)abs(oid),0,MAT_LAST);
			col_out=colors[id]; //TODO: add some variation
			write=true;
		}
		//wakeup logic
		int wake=wake_buffer[i];
		if(wake>0 && oid<MAT_NONE)
		{
			struct agent_state new_state;
			int new_id=atomic_inc(agent_count+step);
			if(new_id<AGENT_MAX)
			{
				new_state.pos=pack_coord(pos);
				new_state.target=pack_coord(pos);
				new_state.id=clamp((int)abs(oid),0,MAT_LAST);
				new_state.flags=0;
				output[new_id]=new_state;
				//might need a clear here?
			}
		}
		//trully static layer stuff
		oid=static_layer[i];
		if(oid!=MAT_NONE)
		{
			int id=clamp(oid,0,MAT_LAST);
			col_out=colors[MAT_WALL]; //TODO: add some variation
			write=true;
		}
		if(write)
			write_imagef(output_tex,pos,col_out);

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
wake_buffer=opencl.make_buffer(w*h*4)
static_layer_buffer=opencl.make_buffer(w*h*4)
sd_layer_buffer=opencl.make_buffer(w*h*4)

active_count=opencl.make_buffer(2*4)
active_count_rb=ffi.new("int[2]")
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
uniform vec2 rez; 
void main()
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float aspect=rez.x/rez.y;
	normed.y/=aspect;
	//normed=clamp(normed,0,1);
	vec3 v=texture(tex_main,normed).xyz;
	//v=pow(v,vec3(2.2));

	color.xyz=v*(step(normed.y,1)-step(normed.y,0));
	color.w=1;
}
]]
local cleared_buffers=false
function init_buffers(  )
	kern_init:set(0,buffers[1])
	kern_init:set(1,active_count)
	kern_init:run(agent_count)

	static_layer_buffer:fill_i(w*h*4,1)
	-- [[
	kern_init_s:set(0,static_layer_buffer)
	kern_init_s:run(w*h)
	--]]
	active_count:fill_i(2*4,1,agent_count/2)
	cleared_buffers=true
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
	--active_count:fill_i(2*4,1)

end
function clear_display( step )
	--sd_layer_buffer:fill_i(w*h*4,1);
	local next_id=(step+1)%2
	active_count:fill_i(4,1,0,4*next_id)
end
paused=paused or false
local step=0
function run_add( )
	display_buffer:aquire()
	--kern_output:run(agent_count)

	kern_add:set(0,static_layer_buffer)
	kern_add:set(1,sd_layer_buffer)
	kern_add:set(2,display_buffer)
	kern_add:seti(3,step)
	kern_add:set(4,active_count)
	kern_add:set(5,buffers[1])
	kern_add:set(6,wake_buffer)
	kern_add:run(w*h)
	display_buffer:release()
end
function update(  )
	__no_redraw()
	__clear()
	local do_step=imgui.Button("Step")
	if imgui.RadioButton("Paused",paused) then
		paused=not paused
	end
	local need_wake=0
	if imgui.Button("wake") then
		need_wake=1
	end
	if imgui.Button("reset") then
		init_buffers(  )
		sd_layer_buffer:fill_i(w*h*4,1);
		step=0
	end
	clear_display(step)
	if do_step or not paused then
		clear_counts()
		
		if cleared_buffers then
			run_add()
			cleared_buffers=false
		end
		-- [[
		kern_logic:set(0,buffers[1])
		kern_logic:set(1,static_layer_buffer)
		kern_logic:set(2,sd_layer_buffer)
		kern_logic:set(3,buffers[2])
		kern_logic:seti(4,math.random(0,999999999))
		kern_logic:seti(5,step)
		kern_logic:set(6,active_count)
		kern_logic:run(agent_count)

		kern_target:set(0,buffers[2])
		kern_target:set(1,move_count_buffer)
		kern_target:seti(2,step)
		kern_target:set(3,active_count)
		kern_target:run(agent_count)

		wake_buffer:fill_i(w*h*4,1,0)

		kern_move:set(0,buffers[2])
		kern_move:set(1,move_count_buffer)
		kern_move:set(2,buffers[1])
		kern_move:set(3,sd_layer_buffer)
		kern_move:seti(4,step)
		kern_move:set(5,active_count)
		kern_move:set(6,wake_buffer)
		kern_move:run(agent_count)
		--]]
		step=step+1
		if step==2 then
			step=0
		end
		active_count:get(8,active_count_rb)
		local next_step=(step+1)%2
		imgui.Text(string.format("Active:%d %d",active_count_rb[step],active_count_rb[next_step]))
		--swap buffers
		--[[
		local tmp=buffers[2]
		buffers[2]=buffers[1]
		buffers[1]=tmp
		--]]
	end
	--output
	clear_display(step)
	if need_wake==1 then
		wake_buffer:fill_i(w*h*4,1,1)
		need_wake=0
	end


	run_add()

		kern_add:set(0,static_layer_buffer)
		kern_add:set(1,sd_layer_buffer)
		kern_add:set(2,display_buffer)
		kern_add:seti(3,step)
		kern_add:set(4,active_count)
		kern_add:set(5,buffers[1])
		kern_add:set(6,wake_buffer)
		kern_add:run(w*h)
		display_buffer:release()

	end
	--gl draw
	shader:use()
	texture:use(1)
	shader:set_i("tex_main",1)
	shader:set("rez",STATE.size[1],STATE.size[2])
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
