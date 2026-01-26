--[==[
	A sparse CA:
	v1
		* e.g. ruleset:
			0=>[1=>2] -> 0 turns into 1 if alive closest alive cell is at 2
			1=>[0=>1] -> 1 turns into 0 if alive closest cell is at 0 (i.e. range>max_range)
--]==]

require "common"

local win_w=1024
local win_h=1024

local oversample=1/8

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size
local max_range=20
local range_zones=3
local zone_starts={5,10}
local max_state=4


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

local kernel_str=[==[
#line __LINE__

#define RADIUS $max_range
#define W $width
#define H $height

#define MAX_ZONE_ID 2
const int zone_starts_sqr[]={25,100};

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
int find_zone_start(int rsqr)
{
	for(int i=0;i<MAX_ZONE_ID;i++)
	{
		if(zone_starts_sqr[i]>=rsqr)
			return i;
	}
	return MAX_ZONE_ID;
}
void count_around(__global int* cells,int2 pos,int* state_out)
{
	int rr=R*R;
	int zone_ids[MAX_ZONE_ID+1]={};
	int counts[MAX_ZONE_ID+1]={};
	for(int dx=-R;dx<=R;dx++)
	for(int dy=-R;dy<=R;dy++)
	{
		int rsq=dx*dx+dy*dy;
		if(rsq<rr)
		{
			int sample=sample_at_pos_int(cells,pos+(int2)(dx,dy));
			int zone=find_zone_start(rsq);
			zone_ids[zone]+=sample;
			counts[zone]+=1;
		}
	}
	for(int i=0;i<MAX_ZONE_ID+1;i++)
	{
		state_out[i]=zone_ids[i]/counts[i];
	}
}

$generated_rule_definition

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
		int new_cell=my_cell;
		int cell_state[MAX_ZONE_ID+1];
		count_around(cell_input,pos,cell_state);

		$generated_rule_logic

		cell_output[i]=new_cell;
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
__kernel void init_cells(__global int* cells1,__global int* cells2,int radius)
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
		int v=0;
		uint4 hash=(uint4)(i,0,0,0);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		hash.x=lowbias32(hash.x);
		#if 1
		if( true
			//&& float_from_hash(hash).x>0.5

			//&& length(pos_normed)<0.9
			//&& length(pos_normed)>0.87
			//&& fmod(length(pos_normed),0.4f)<0.3
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))<0.1
			//&& fmax(fabs(pos_normed.x),fabs(pos_normed.y))>0.05
			&& fmax(fabs(pos_i.x),fabs(pos_i.y))<radius
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
]==]



config=make_config({
    {"pause",true,type="bool"},
    },config)


draw_field=init_draw_field(advance_format(
[==[
#line __LINE__
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);
    //data.x*=data.x;
    float normed_particle=data.x*255/$max_state;
    //vec3 c=palette(normed_particle,vec3(0.2),vec3(0.8),vec3(1.5,0.5,1.0),vec3(0.5,0.5,0.25));
    vec3 c=palette(normed_particle,vec3(0.5),vec3(0.5),vec3(1.0),vec3(0.0,0.1,0.2));
    //vec3 c=vec3(normed_particle);
    color=vec4(c,1);
    
}
]==],{max_state=max_state}),
{
    uniforms={
    },
}
)
ruleset=ruleset or {
	[0]={ [1]=1,[3]=1,[32]=1 },
	[1]={ [6]=1},
	[2]={ [6]=1},
}
function circle(x,y,cx,cy,R)
	local dx=x-cx
	local dy=y-cy
	local r=round(math.sqrt(dx*dx+dy*dy))
	--local r=math.sqrt(dx*dx+dy*dy)
	if r<R then
		return true
	end
	return false
end
function rhombus(x,y,cx,cy,R)
	local dx=x-cx
	local dy=y-cy
	local r=math.abs(dx)+math.abs(dy)
	if r<R then
		return true
	end
	return false
end
function init_grid( g )
    for x=0,map_w-1 do
    for y=0,map_h-1 do
    	--[==[
    	if math.random()>0.997 then
    		g.type[1]:set(x,y,1)
    	else
    		g.type[1]:set(x,y,0)
    	end
    	--]==]
        g.type[1]:set(x,y,0)
        --[==[
        if x==map_w/2 and y==map_h/2 then
        	g.type[1]:set(x,y,1)
        end
        --]==]
        --[==[
        if circle(x,y,map_w/2,map_h/2,15) then
        --if rhombus(x,y,map_w/2,map_h/2,15) then
        	g.type[1]:set(x,y,1)
        end
        --]==]
        --[==[
        if circle(x,y,map_w/2,map_h/2-11,5) then
        	g.type[1]:set(x,y,1)
        end
        if circle(x,y,map_w/2,map_h/2+11,5) then
        	g.type[1]:set(x,y,1)
        end
        --]==]
        -- [==[
        local count_circles=8
        local radius=24
        local angle_offset=math.pi/2
        for i=0,count_circles do
        	local cx=map_w/2+round(math.cos((i/count_circles)*math.pi*2+angle_offset)*radius)
        	local cy=map_h/2+round(math.sin((i/count_circles)*math.pi*2+angle_offset)*radius)
        	--local cx=map_w/2+math.cos((i/count_circles)*math.pi*2+angle_offset)*radius
        	--local cy=map_h/2+math.sin((i/count_circles)*math.pi*2+angle_offset)*radius
	        if circle(x,y,cx,cy,5) then
	        	g.type[1]:set(x,y,1)
	        end
	    end
        --]==]
    end
    end
end
function clear_grid( g )
    for x=0,map_w-1 do
    for y=0,map_h-1 do
        g.type[1]:set(x,y,0)
    end
    end
end
function bound_coordinates(x,y)
	if x<0 then x=map_w+x end
	if y<0 then y=map_h+y end
	if x>=map_w then x=x-map_w end
	if y>=map_h then y=y-map_h end
	return x,y
end
function round(x)
	return math.floor(x+0.5)
end
function find_zone(actual_r,count_per_zone)
	--return math.floor((actual_r-1)/count_per_zone)+1
	-- [===[
	for i,v in ipairs(zone_starts) do
		if actual_r<v then
			return i
		end
	end
	return #zone_starts+1
	--]===]
end
function find_cell_state(array,x,y)
	local rsqr=max_range*max_range
	local min_range=max_range+1
	local h_range=-1
	local state={}
	local counts={}
	local count_per_zone=max_range/range_zones
	for i=1,range_zones do
		state[i]=0
		counts[i]=0
	end
	for dx=-max_range,max_range do
		for dy=-max_range,max_range do
			local r=(dx*dx+dy*dy)
			--local actual_r=math.abs(dx)+math.abs(dy)
			local actual_r=round(math.sqrt(r))
			local range_zone=find_zone(actual_r,count_per_zone)
			if r<=rsqr and (dx~=0 or dy~=0) then
			--for dy=-max_range,max_range do
				local tx,ty=bound_coordinates(x+dx,y+dy)
				local test_cell=array:get(tx,ty)
				if test_cell>0 then
					if state[range_zone] ==nil then
						print(range_zone,actual_r)
					end
					--variations: max state
					--state[range_zone]=math.max(test_cell,state[range_zone] or 0)
					--variations: avg_state
					state[range_zone]=state[range_zone]+test_cell
					counts[range_zone]=counts[range_zone]+1
					if h_range<actual_r then
						h_range=actual_r
					end
					if min_range>actual_r then
						min_range=actual_r
					end
				end
			end
		end
	end
	for i=1,range_zones do
		state[i]=round(state[i]/counts[i])
	end
	return state
end
function state_to_string(state)
	return table.concat(state)
end
function state_to_number(state)
	local ret=0
	for i=1,#state do
		ret=ret+math.pow(max_state,i)*state[i]
		--[[
		if state[i]>0 then
			ret=ret+math.pow(2,i)
		end
		--]]
	end
	return ret
end
function apply_rule(current_type,state)
	--return ruleset[current_type][state] or 0
	return ruleset[current_type][state_to_number(state)] or 0
	--return ruleset[current_type][state_to_string(state)] or 0
end

function sim_tick(  )
    local g=grid
    for x=0,map_w-1 do
    for y=0,map_h-1 do
    	local c_type=g.type[1]:get(x,y)
    	local cell_state=find_cell_state(g.type[1],x,y)
    	

    	--[[
    	if c_type>0 or new_type>0 then
    		print(x,y,c_type,new_type,cell_state)
    	end
    	--]]
    	-- [[
    	local new_type=apply_rule(c_type,cell_state)
    	g.type[2]:set(x,y,new_type)
    	--]]
    	--if cell_state==max_range+1 then cell_state=0 end
    	--g.type[2]:set(x,y,cell_state)
    	--g.type[2]:set(x,y,c_type)
    end
    end
    swap_buffers()
end
function draw(  )
    draw_field.update(grid.type[1])
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
	local chance_stay=0.6
	local chance_random=0.1
	local chance_advance=0.3
	for i=0,math.pow(max_state,range_zones+1)-1 do
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
	for i=0,max_state do
		ruleset[i]=random_rule_state(i)
	end
end
local need_step=false
function update(  )
	__clear()
    __no_redraw()

    imgui.Begin("Cellular sparse")
    draw_config(config)
    if imgui.Button("Reset") then
    	init_grid(grid)
    end
    if imgui.Button("Step") then
    	need_step=true
    end
    if imgui.Button("RandRules") then
    	random_rules()
    	init_grid(grid)
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