--[==[ A yet another attempt at making a "fun to puzzle out" system

	Main idea:
		* grid of "oscillators"
			- has "total energy"
			- a "configuration" (which probably determines energy)
			- interaction(s) between cells
				- at least some diffusion like process
			- transitions
				- probably between configurations
				- with "outside world" i.e. outputs
		* outside field
			- changes
				- how configuration "looks like"
				- which interactions take place
				- which are allowed transitions
		* rules for outside interactions
			- how to add energy
			- how to release energy

	Nice to have:
		* have levels "different" e.g.:
			- one might be time independent
			- only the cell value dependent
			- somehow from around the cell
			- take into account other cell levels
	Iteration 1:

	32 bit int for state

		1 bit for 1st level
		2 bit for 2nd
		4 for 3rd etc...
	without outside influence all bits falldown if possible
		a: 1=1 bit
		b: two bits in nth level to n-1th level
		c: exactly half of higher level

	with influence:
		influence is: f(x,y)
			1. value at point
			2. dx and dy at point
			3. dx*dx+dy*dy at point
			4. center/avg around (div by 0?)
			5. angle (i.e. atan(dy,dx)) undefined at 0, no good value for "no outside field",
					no preferred direction
			6. curl=F_y/der_x-F_x/der_y or curl^2
			7. some sort of skew (dx/dy? )
			if f(x,y,t)?
			1. dt
			2. avg over t f(x,y,t)
		1st level defines if outside is low energy i.e. in high energy 1 is forbidden there
		2nd -"-							gradient sth sth?
		3rd ??
		4th ??
	Iter 1.a
		levels allowed are like this
			1st low/high
			2nd low/mid-low/mid-high/high
			3rd etc...
			PRO: easy
			CONS: only power, no location etc
	Iter 1.b
		2 bits: low (00), mid (01), high(11)
		2 bits: count of high around - 3 values (0 -> 00; 1,2,3->01; 4->11)
		4 bits: not blocked(?)
		8 bits: direction of atan(dy,dx) compared to 4 bits lower
		16 bits: never blocked
		CONS:
			8 bits are never filled until lower 4 are filled,
				but when they are filled they always point to same direction
	Iter 1.c
		2 bits: low (00), mid (01), high(11)
		2 bits: count of high around - 3 values (0 -> 00; 1,2,3->01; 4->11) (probably bad...)
		4 bits: |A-B| where A is directly around, B is diagonal around
		8 bits: direction of atan(dy,dx) compared to "direction"
		16 bits: never blocked

		here direction is another grid that shows "some original polarization" where it's hard to change
--]==]


require "common"

local win_w=1024
local win_h=1024
local oversample=1/2
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)



config=make_config(
	{
		{"pause",true,type="bool"},
		{"draw_layer",0,type="choice",min=0,max=3,watch=true,choices={
			"outside field",
			"polarization direction",
			"orbital fill",
			"orbital energy",
			"total energy",
			}
		},
		{"orbital",1,type="int",min=0,max=4,watch=true}
	},config)

grid=grid or make_u32_1c_buffer(map_w,map_h) --32 bits of energy levels
grid_alt=grid_alt or make_flt_buffer(map_w,map_h) --outside field and polarization direction

if field_texture==nil then
    field_texture=textures:Make()
    field_texture:use(0)
    field_texture:set(map_w,map_h,U32_1C_PIX)

    alt_tex=textures:Make()
    alt_tex:use(0)
    alt_tex:set(map_w,map_h,FLTA_PIX)
end

function init_draw_field(draw_string,settings)
    settings=settings or {}
    local texture_list=settings.textures or {}
    local uniform_list=settings.uniforms or {}
    local uniform_string=generate_uniforms_string(uniform_list,texture_list)
    local shader_string=string.format([==[
#version 330
#line __LINE__ 99

out vec4 color;
in vec3 pos;

#line __LINE__ 99
%s
#line __LINE__ 99
%s
]==],uniform_string,draw_string)

    local draw_shader=shaders.Make(shader_string)
    local texture=texture_list.tex_main or textures:Make()

    local update_texture=function ( buffer )
        buffer:write_texture(texture)
    end
    local draw=function(  )
        -- clear
        if need_clear then
            __clear()
            need_clear=false
        end
        draw_shader:use()
        local i=0
        for k,v in pairs(texture_list) do
            v.texture:use(i)
            draw_shader:set_i(k,i)
            i=i+1
        end

        draw_shader:draw_quad()
    end
    local update_uniforms=function ( tbl )
        draw_shader:use()
        for i,v in ipairs(uniform_list) do
            --todo more formats!
            if tbl[v.name]~=nil then
                update_uniform(draw_shader,v.type,v.name,tbl)
            end
        end
    end
    local ret={
        shader=draw_shader,
        draw=draw,
        update=update_texture,
        texture=texture_list,
        update_uniforms=update_uniforms,
        clear=function (  )
            need_clear=true
        end
    }
    return ret
end
function generate_uniform_string( v )
    return string.format("uniform %s %s;\n",v.type,v.name)
end
function generate_uniforms_string( uniform_list,texture_list )
    local uniform_string=""
    if uniform_list~=nil then
        for i,v in ipairs(uniform_list) do
            uniform_string=uniform_string..generate_uniform_string(v)
        end
    end
    if texture_list~=nil then
        for k,v in pairs(texture_list) do
    		uniform_string=uniform_string..generate_uniform_string({type=v.type or "sampler2D",name=k})
        end
    end
    return uniform_string
end
function update_uniform( shader,utype,name,value_table )
    local types={
        int=shader.set_i,
        float=shader.set,
        vec2=shader.set,
        vec3=shader.set,
        vec4=shader.set
    }
    if type(value_table[name])=="table" then
        types[utype](shader,name,unpack(value_table[name]))
    else
        types[utype](shader,name,value_table[name])
    end
end
function generate_attribute_strings( tbl )
    local attribute_list,attribute_variables,attribute_assigns,attribute_variables_frag
    attribute_list=""
    attribute_variables=""
    attribute_assigns=""
    attribute_variables_frag=""
    for i,v in ipairs(tbl) do
        local attrib_name=v.name_attrib or (v.name .. "_attrib")
        local var_name=v.name
        attribute_list=attribute_list..string.format("layout(location = %d) in vec4 %s;\n",v.pos_idx,attrib_name)
        attribute_variables=attribute_variables..string.format("out vec4 %s;\n",var_name)
        attribute_assigns=attribute_assigns..string.format("%s=%s;\n",var_name,attrib_name)
        attribute_variables_frag=attribute_variables_frag..string.format("in vec4 %s;\n",var_name)
    end
    return attribute_list,attribute_variables,attribute_assigns,attribute_variables_frag
end
draw_field=init_draw_field(
[==[
#line __LINE__
vec3 YxyToXyz(vec3 v)
{
    vec3 ret;
    ret.y=v.x;
    float small_x = v.y;
    float small_y = v.z;
    ret.x = ret.y*(small_x / small_y);
    float small_z=1-small_x-small_y;

    //all of these are the same
    ret.z = ret.x/small_x-ret.x-ret.y;
    return ret;
}
vec3 xyz2rgb( vec3 c ) {
    vec3 v =  c / 100.0 * mat3(
        3.2406255, -1.5372080, -0.4986286,
        -0.9689307, 1.8757561, 0.0415175,
        0.0557101, -0.2040211, 1.0569959
    );
    vec3 r;
    r=v;
    /* srgb conversion
    r.x = ( v.r > 0.0031308 ) ? (( 1.055 * pow( v.r, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.r;
    r.y = ( v.g > 0.0031308 ) ? (( 1.055 * pow( v.g, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.g;
    r.z = ( v.b > 0.0031308 ) ? (( 1.055 * pow( v.b, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.b;
    //*/
    return r;
}
vec3 tonemap(vec3 light,float cur_exp,float white_point)
{
    float lum_white =white_point*white_point;

    float Y=light.y;

    Y=Y*exp(cur_exp);

    if(white_point<0)
        Y = Y / (1 + Y); //simple compression
    else
        Y = (Y*(1 + Y / lum_white)) / (Y + 1); //allow to burn out bright areas

    float m=Y/light.y;
    light.y=Y;
    light.xz*=m;


    vec3 ret=xyz2rgb((light)*100);
    ///*
    if(ret.x>1)ret.x=1;
    if(ret.y>1)ret.y=1;
    if(ret.z>1)ret.z=1;
    //*/
    float s=smoothstep(1,8,length(ret));
    return mix(ret,vec3(1),s);
    //return ret;
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
float count_high(vec2 pos)
{
	float ret=0;

	ret+=step(1.0f,textureOffset(tex_alt,pos,ivec2(0,-1)).x);
	ret+=step(1.0f,textureOffset(tex_alt,pos,ivec2(-1,0)).x);
	ret+=step(1.0f,textureOffset(tex_alt,pos,ivec2(1,0 )).x);
	ret+=step(1.0f,textureOffset(tex_alt,pos,ivec2(0,1 )).x);

	return ret;
}
float a_minus_b(vec2 pos)
{
	float ret=0;

	ret+=textureOffset(tex_alt,pos,ivec2(0,-1)).x;
	ret+=textureOffset(tex_alt,pos,ivec2(-1,0)).x;
	ret+=textureOffset(tex_alt,pos,ivec2(1,0 )).x;
	ret+=textureOffset(tex_alt,pos,ivec2(0,1 )).x;

	ret-=textureOffset(tex_alt,pos,ivec2(-1,-1)).x;
	ret-=textureOffset(tex_alt,pos,ivec2(-1,1)).x;
	ret-=textureOffset(tex_alt,pos,ivec2(1,1)).x;
	ret-=textureOffset(tex_alt,pos,ivec2(1,-1 )).x;
	return abs(ret);
}
vec2 tex_grad(vec2 pos)
{
	vec2 ret;
	float c=textureOffset(tex_alt,pos,ivec2(0,0)).x;
	ret.x=c-textureOffset(tex_alt,pos,ivec2(1,0)).x;
	ret.y=c-textureOffset(tex_alt,pos,ivec2(0,1)).x;
	return ret;
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_alt,normed);

    float angle=(atan(data.y,data.x)/3.14159265359+1)/2;
    float len=min(length(data.xy),1);
    vec4 out_col;
    if (draw_layer==0)
        out_col=vec4(palette(data.x,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);
    else if(draw_layer==1)
    {
    	float angle=atan(data.w,data.z);
    	float l=length(data.zw);
    	l=smoothstep(0.1,0.15,l);
        out_col=vec4(palette(angle,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,1.5,1))*l,1);
    }
    else if(draw_layer==2)
    {

    	if(orbital==0)
    	{
    		//just low/mid/high
    		out_col.xyz=vec3(2-step(0.5,data.x)-step(1,data.x))*0.5;
    	} else if(orbital==1)
    	{
    		//count pixels with high around
    		float c=count_high(normed);
    		out_col.xyz=vec3(2-step(0.1f,c)-step(3.9f,c))*0.5;
    	} else if(orbital==2)
    	{
    		float c=a_minus_b(normed)*20000;
    		out_col.xyz=vec3(step(0,c)+step(1,c)+step(2,c)+step(3,c))*0.25;
    		/*out_col.xyz=vec3(c);
    		out_col.x=step(0,c);
    		out_col.y=step(1,c);
    		out_col.z=step(2,c);*/
    	}
    	else if(orbital==3)
    	{
    		vec2 p=tex_grad(normed);
    		float angle_cos=dot(p,data.zw)/(length(p)*length(data.zw));
    		//float angle=atan(p.y,p.x);//acos(dot(p,data.zw));
    		//out_col=vec4(palette(angle_cos,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);
    		//remap -1,1 to 0,8
    		angle_cos=(angle_cos+1.0f)*4.0f;
    		out_col.xyz=vec3(8-floor(angle_cos))/8;
		}
		//orbital==4 is never filled
    	out_col.a=1;
    }
    else if(draw_layer==3)
    {
    	uvec4 data=texture(tex_main,normed);
    	uint value=data.r;//((data.r>>24) & 0xFFu) | ((data.g>>24)& 0xFFu)<<8 |((data.b>>24)& 0xFFu)<<16 |((data.a>>24)& 0xFFu)<<24;
    	if(orbital==0)
    	{
    		//bits 0-1
    		uint val=value & 3u;
    		out_col.xyz=vec3(float(val))/3.0f;
    	} else if(orbital==1)
    	{
    		//bits 2-3
    		uint val=(value>>2) & 3u;
    		out_col.xyz=vec3(float(val))/3.0f;
    	} else if(orbital==2)
    	{
    		//bits 4-7
    		uint val=(value>>4) & 15u;
    		out_col.xyz=vec3(float(val))/15.0f;
    	}
    	else if(orbital==3)
    	{
    		//bits 8-15
    		uint val=(value>>8) & 0xFFu;
    		out_col.xyz=vec3(float(val))/255.0f;
		}
		else if(orbital==4)
    	{
    		//bits 16-32
    		uint val=(value>>16) & 0xFFFFu;
    		out_col.xyz=vec3(float(val))/float(0xFFFF);
		}
		else if(orbital==5)
    	{
    		out_col.xyz=data.rgb;
		}
		else if(orbital==6)
    	{
    		out_col.x=float(data.r&0xFFu);
		}
    	out_col.a=1;
    }
    else if(draw_layer==4)
    {
    	uint value=texture(tex_main,normed).r;
#define E_0 5
#define E_1 4
#define E_2 3
#define E_3 2
#define E_4 1
    	float energy_value=0;
    	{
    		uint val=value & 3u;
    		energy_value+=E_0*float(val)/3.0f;
    	}
    	{
    		uint val=(value>>2) & 3u;
    		energy_value+=E_1*float(val)/3.0f;
    	}
    	{
    		uint val=(value>>4) & 15u;
    		energy_value+=E_2*float(val)/15.0f;
    	}
    	{
    		uint val=(value>>8) & 0xFFu;
    		energy_value+=E_3*float(val)/255.0f;
		}
    	{
    		uint val=(value>>16) & 0xFFFFu;
    		energy_value+=E_4*float(val)/float(0xFFFF);
		}
		out_col.xyz=vec3(energy_value)/(15.0f);
    	out_col.a=1;
    }
    color=out_col;
}
]==],
{
	uniforms={
		{type="int", name="draw_layer"},
		{type="int", name="orbital"},
        {type="vec2", name="rez"},
    },
    textures={
    	tex_main={texture=field_texture,type="usampler2D"},
    	tex_alt={texture=alt_tex},
    }
}
)
function init_grad_noise( )
	local ret={}
	local count=6
	-- [[
	for i=1,count do
		local x=math.random()*2-1
		local y=math.random()*2-1
		local p=Point(x,y)
		table.insert(ret,p)
	end
	--]]
	--[[
	ret={
		Point(-0.5,0),
		Point(0.5,0),
	}
	--]]
	return ret
end
function grad_noise(tbl, x,y )
	local p=Point(x,y)
	local sum=Point(0,0)
	for i,v in ipairs(tbl) do
		local d=v-p
		local len=d:len()
		local lp=1/(len*(1+len)*(1+len))
		--local g=Point(d[1]*3*len,d[2]*3*len)
		local g=Point(-d[1]*lp,-d[2]*lp)

		sum=sum+g --derivative of f(X)=|X-C|^2
	end
	return sum
end
function pot_noise( tbl,x,y )
	local p=Point(x,y)
	local sum=0
	for i,v in ipairs(tbl) do
		local d=v-p
		local len=d:len()
		--local g=len*len*len
		local g=1/(len+1)
		sum=sum+g --derivative of f(X)=|X-C|^2
	end
	return sum
end
function draw_outside(  )
	local function f(x,y)
		return math.sqrt(x*x+y*y)
	end
	local cx=map_w/2
	local cy=map_h/2
	local noise=init_grad_noise()
	for x=0,map_w-1 do
	for y=0,map_h-1 do
		--local coords [-1;1]
		local lx=(x-cx)/cx
		local ly=(y-cy)/cy
		local v=grad_noise(noise,lx,ly)
		local vf=pot_noise(noise,lx,ly)
		grid_alt:set(x,y,{f(lx,ly),vf,v[1],v[2]})
	end
	end
    alt_tex:use(0)
	alt_tex:set_sub(grid_alt.d,grid_alt.w,grid_alt.h,FLTA_PIX)
end

function reset_energy(  )
	local cx=map_w/2
	local cy=map_h/2
	for x=0,map_w-1 do
	for y=0,map_h-1 do
		--local coords [-1;1]
		local lx=(x-cx)/cx
		local ly=(y-cy)/cy
		local d=math.sqrt(lx*lx+ly*ly)
		if d<1.2 then
			grid:set(x,y,bit.tobit(math.random(0,0xFFFFFFFF)))
		else
			grid:set(x,y,0)
		end
	end
	end
	field_texture:use(0)
	field_texture:set_sub(grid.d,grid.w,grid.h,U32_1C_PIX)
end
last_energy_balance=last_energy_balance or 0
function pop_cnt( v )
	local ret=0
	for i=0,31 do
		ret=ret+bit.band(bit.rshift(v,i),1)
	end
	return ret
end
	--[[


	4 bits: |A-B| where A is directly around, B is diagonal around
	8 bits: direction of atan(dy,dx) compared to "direction"
	16 bits: never blocked
	--]]
local bit_count_per_orbital={
	2,2,4,8,16
}
local orbital_masks_unshifted
local orbital_masks
function formatx(x)
  return("0x"..bit.tohex(x))
end
function init_masks(  )
	orbital_masks_unshifted={}
	orbital_masks={}
	local offset=0
	for i,v in ipairs(bit_count_per_orbital) do
		orbital_masks_unshifted[i]=bit.lshift(1,v)-1
		orbital_masks[i]=bit.lshift(orbital_masks_unshifted[i],offset)
		offset=offset+v
		print(i,v,formatx(orbital_masks_unshifted[i]),formatx(orbital_masks[i]))
	end

end
init_masks()
function split_energy( g )
	local ret={}
	local cur_offset=0
	for i,v in ipairs(bit_count_per_orbital) do

		ret[i]=bit.rshift(bit.band(g,orbital_masks[i]),cur_offset)
		cur_offset=cur_offset+v
	end
	return ret
end
function join_energy( t )
	local ret=0
	local cur_offset=0
	for i,v in ipairs(t) do
		ret=bit.bor(ret,bit.band(bit.lshift(v,cur_offset),orbital_masks[i]))
		cur_offset=cur_offset+bit_count_per_orbital[i]
	end
	return ret
end
function update_level_values( levels,cur_level,mask )
	local new_value=math.min(mask,levels[cur_level])
	local overflow=levels[cur_level]-new_value
	local space_below=mask-new_value
	levels[cur_level]=new_value
	return space_below,overflow
end
function count_around(x,y)
	local dx={-1,0,1,0}
	local dy={0,-1,0,1}
	local ret=0
	for i=1,4 do
		local tx=x+dx[i]
		local ty=y+dy[i]
		if tx>0 and ty>0 and tx<map_w-1 and ty<map_h-1 then
			if grid_alt:get(tx,ty).r>1 then
				ret=ret+1
			end
		else
			ret=ret+1
		end
	end
	return ret
end
function a_minus_b(x,y)
	local dx={-1,0,1,0,1,1,-1,-1}
	local dy={0,-1,0,1,1,-1,1,-1}
	local mult={1,1,1,1,-1,-1,-1,-1}
	local ret=0
	for i=1,8 do
		local tx=x+dx[i]
		local ty=y+dy[i]
		if tx>0 and ty>0 and tx<map_w-1 and ty<map_h-1 then
			local v=grid_alt:get(tx,ty).r*mult[i]
			ret=ret+v
		end
	end

	return math.abs(ret)
end
function texture_grad(ga, x,y )
	local c=ga.r
	local dx=0
	if x+1<map_w-1 then
		dx=c-grid_alt:get(x+1,y).r
	end
	local dy=0
	if y+1<map_h-1 then
		dy=c-grid_alt:get(x,y+1).r
	end
	return Point(dx,dy)
end
function tick(  )
	local energy_balance=0
	local energy_levels={
		16,8,4,2,1
	}
	local function level_transfer(levels,space_below,want_overflow,from,to )
		local overflow=math.floor(want_overflow/energy_levels[to])
		energy_balance=energy_balance+overflow*(energy_levels[from]-energy_levels[to])

		local energy_transfer_step=energy_levels[from]/energy_levels[to]

		local energy_below=math.floor(space_below*energy_transfer_step)
		local energy_above=levels[to]*energy_levels[to]

		local max_drop=math.floor((levels[to]*energy_levels[to])/energy_levels[from])
		local drop_amount=math.min(space_below,max_drop)
		levels[to]=levels[to]-drop_amount+overflow
		levels[from]=levels[from]+drop_amount
		energy_balance=energy_balance+drop_amount*(energy_levels[to]-energy_levels[from])
		return overflow
	end
	local modify_mask={
		function ( m,ga,g )
			--orbital 0 -> 2 bits: low (00), mid (01), high(11)
			if ga.r>=1 then
				m=bit.rshift(m,2)
			elseif ga.r>=0.5 then
				m=bit.rshift(m,1)
			end
			return m
		end,
		function ( m,ga,g,x,y )
			--orbital 1 -> count of high around - 3 values (0 -> 00; 1,2,3->01; 4->11) (probably bad...)
			local c=count_around(x,y)
			if c>=1 and c<4 then
				m=bit.rshift(m,1)
			elseif c>=4 then
				m=bit.rshift(m,2)
			end
			return m
		end,
		function ( m,ga,g,x,y )
			local v=math.floor(a_minus_b(x,y)*20000)
			local v_out=v
			v=math.min(v,4)
			local mnew= bit.rshift(m,v)
			--print(x,y,v,v_out,formatx(m),formatx(mnew))
			--error(1)
			return mnew
		end,
		function ( m,ga,g,x,y )
			local v=texture_grad(ga,x,y)
			local vs=Point(ga.b,ga.a)
			local dp=vs..v
			local l1=vs:len()
			local l2=v:len()
			if l1>0.000001 then
				dp=dp/l1
			end
			if l2>0.000001 then
				dp=dp/l2
			end
			local acos=(dp+1)*4
			local v=math.floor(acos)
			v=math.min(v,8)
			local mnew= bit.rshift(m,v)
			return mnew
		end,
		function ( m )
			return m
		end
	}
	for x=0,map_w-1 do
	for y=0,map_h-1 do
		local ga=grid_alt:get(x,y)
		local g=bit.tobit(grid:get(x,y))
		local el=split_energy(g)
		local total_overflow=0 --overflow in "energy"
		for i=1,5 do
			local m=orbital_masks_unshifted[i]
			m=modify_mask[i](m,ga,g,x,y)

			local space_below,overflow=update_level_values(el,i,m)
			total_overflow=total_overflow+overflow*energy_levels[i]
			if i~=5 then
				total_overflow=total_overflow-level_transfer(el,space_below,total_overflow,i,i+1)
			end
		end

		grid:set(x,y,join_energy(el))
	end
	end
	field_texture:use(0)
	field_texture:set_sub(grid.d,grid.w,grid.h,U32_1C_PIX)
	last_energy_balance=energy_balance
end
function update()
    __no_redraw()
    __clear()
    imgui.Begin("Magic system test")
    draw_config(config)
    if imgui.Button("Remake Outside") then
    	draw_outside()
    end
    if imgui.Button("Reset Energy") then
    	reset_energy()
    end
    if config.__change_events.any then
        draw_field.update_uniforms(config)
        draw_field.update_uniforms({rez={map_w,map_h}})
    end
    draw_field:draw()
    if imgui.Button("Tick") then
    	tick()
    end
    imgui.Text(string.format("delta E=%g",last_energy_balance))
    imgui.End()
end
