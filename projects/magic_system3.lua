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

local max_agent_count=1e6
local agent_count=0
local default_angle=math.pi/4

config=make_config({
    {"draw_trails",false,type="bool"},
    {"sim_agents",false,type="bool"},

    {"blob_count",5,type="int",min=1,max=max_tool_count},
    {"outside_strength",1.0,type="float",min=0,max=2},
    {"tool_scale",0.25,type="float",min=0,max=2},
    {"influence_size",0.3,type="float",min=0,max=2},

    {"seed",0,type="int",min=0,max=10000000},

    {"max_agent_iterations",2000,type="int",min=10,max=10000},
    {"field_mult",0.05,type="float",min=0,max=2},
    {"speed_mult",1,type="float",min=0,max=2},
    {"color_spread",10,type="float",min=0,max=25},

    {"draw_layer",0,type="int",min=0,max=2,watch=true},
    {"agent_whitepoint",1,type="floatsci",min=-8,max=1,watch=true},
    {"agent_gamma",1,type="float",min=0,max=2,watch=true},
},config)


AGENT_SIZE=4*8 --floats*(vec2 pos,vec2 speed,vec4 color)

cl_agent_buffers=cl_agent_buffers or {}
gl_agent_buffers=gl_agent_buffers or {}
function resize_agents(agent_count)
	local size=agent_count*AGENT_SIZE
	if cl_agent_buffers.agent_count==nil or cl_agent_buffers.size~=size then
		for i=1,2 do
			local buffer=buffer_data.Make()
	    	buffer:use()
            buffer:set(agent_count*AGENT_SIZE)
	    	gl_agent_buffers[i]=buffer
			cl_agent_buffers[i]=opencl.make_buffer_gl(buffer)
		end
        __unbind_buffer()
	end
end
resize_agents(max_agent_count)

if field_texture==nil then
    field_texture=textures:Make()
    field_texture:use(0)
    field_texture:set(map_w,map_h,FLTA_PIX)
    display_buffer=opencl.make_buffer_gl(field_texture)
end

kernels=opencl.make_program
[==[
const sampler_t default_sampler =CLK_NORMALIZED_COORDS_TRUE|CLK_ADDRESS_REPEAT|CLK_FILTER_LINEAR;

#line __LINE__
float2 rotate2d(float2 p,float angle)
{
  float s = sin(angle);
  float c = cos(angle);

  float xnew = p.x * c - p.y * s;
  float ynew = p.x * s + p.y * c;
  return (float2)(xnew,ynew);
}
float2 lorenz_addition(float2 v,float2 u,float light_speed)
{
	float lss=light_speed*light_speed;
	float vsq=dot(v,v);
	float vu=dot(v,u);
	float2 nv=fast_normalize(v);
	float2 normed_vu=dot(nv,u)*nv;
	float alpha=sqrt(1-vsq/lss);
	float scale=1/(1+vu/lss);

	float2 ret=alpha*u+v+(1-alpha)*normed_vu;
	return ret*scale;
}
__kernel void advance_particles(__global float8* input,
	__global float8* output,__read_only image2d_t read_tex,int count,
	float color_spread,float speed_mult,float field_mult,float map_w,float map_h)
{
	int i=get_global_id(0);
	if(i>=0 && i<count)
	{
		float8 agent_data=input[i];
		/*
		float2 pos=(float2)(input[i*8],input[i*8+1]);
		float2 speed=(float2)(input[i*8+2],input[i*8+3]);
		float4 color=(float2)(input[i*8+2],input[i*8+3]);
		*/
		float4 field=read_imagef(read_tex,default_sampler,agent_data.s01/(float2)(map_w,map_h));
		agent_data.s01+=agent_data.s23*speed_mult;

		if(agent_data.s0<0 || agent_data.s0>map_w || agent_data.s1<0 ||agent_data.s1>map_h)
			agent_data.s7=-1;

		agent_data.s01=fmod(agent_data.s01,(float2)(map_w,map_h));
        //float col_variation=exp(-agent_data.s4*agent_data.s4/color_spread*color_spread);
        //float col_variation=exp(-(agent_data.s7*agent_data.s7)/(color_spread*color_spread));
        float delta_col=field.w-agent_data.s7;
        float col_variation=exp(-(delta_col*delta_col)/(color_spread*color_spread));
		float old_speed=length(agent_data.s23)*col_variation;
		old_speed=clamp(old_speed,0.0f,1.0f);
        old_speed=1-pow(1-old_speed,0.4f);
        float2 add_speed=field.s01*field_mult*col_variation;
        float max_speed=10.0f;
        //float max_speed=10.0f;
        if(length(add_speed)>max_speed)
        {
        	add_speed/=length(add_speed);
        	add_speed*=max_speed;
        }
        float2 old_vec=agent_data.s23;
        if(length(old_vec)>max_speed)
        {
        	old_vec/=length(old_vec);
        	old_vec*=max_speed;
        }
        //agent_data.s23=lorenz_addition(old_vec,rotate2d(add_speed,M_PI*2*(length(old_vec)/max_speed)),max_speed);
        agent_data.s23=lorenz_addition(old_vec,add_speed,max_speed);
        //agent_data.s23=old_vec+add_speed;

		//agent_data.s23+=rotate2d(field.s01*field_mult,M_PI*2*old_speed*col_variation);
		//agent_data.s23+=field.s01*field_mult*col_variation;
		//if(length(agent_data.s23)>1.0f)
		//	agent_data.s23/=length(agent_data.s23);
		output[i]=agent_data;
		/*
		output[i*8+0]=pos.x;
		output[i*8+1]=pos.y;
		output[i*8+2]=speed.x;
		output[i*8+3]=speed.y;
		*/
	}
}

float gaussian(float x, float alpha, float mu, float sigma1, float sigma2) {
  float squareRoot = (x - mu)/(x < mu ? sigma1 : sigma2);
  return alpha * exp( -(squareRoot * squareRoot)/2 );
}
float gaussian1(float x, float alpha, float mu, float sigma) {
  float squareRoot = (x - mu)/sigma;
  return alpha * exp( -(squareRoot * squareRoot)/2 );
}
float gaussian_conv(float x, float alpha, float mu, float sigma1, float sigma2,float mu2,float sigma3) {
	float mu_new=mu+mu2;
	float s1=sqrt(sigma1*sigma1+sigma3*sigma3);
	float s2=sqrt(sigma2*sigma2+sigma3*sigma3);
	float new_alpha=sqrt(M_PI)/(sqrt(1/(sigma1*sigma1)+1/(sigma3*sigma3)));
	new_alpha+=sqrt(M_PI)/(sqrt(1/(sigma2*sigma2)+1/(sigma3*sigma3)));
	new_alpha/=2;
	return gaussian(x,new_alpha,mu_new,s1,s2);
}
//from https://en.wikipedia.org/wiki/CIE_1931_color_space#Color_matching_functions
//Also better fit: http://jcgt.org/published/0002/02/01/paper.pdf

float3 xyzFromWavelength(float wavelength) {
	float3 ret;
  	ret.x = gaussian(wavelength,  1.056, 5998, 379, 310)
         + gaussian(wavelength,  0.362, 4420, 160, 267)
         + gaussian(wavelength, -0.065, 5011, 204, 262);

  	ret.y = gaussian(wavelength,  0.821, 5688, 469, 405)
         + gaussian(wavelength,  0.286, 5309, 163, 311);

  	ret.z = gaussian(wavelength,  1.217, 4370, 118, 360)
         + gaussian(wavelength,  0.681, 4590, 260, 138);
  	return ret;
}
float3 xyz_from_normed_waves(float v_in)
{
	float3 ret;
	ret.x = gaussian(v_in,  1.056, 0.6106, 0.10528, 0.0861)
		+ gaussian(v_in,  0.362, 0.1722, 0.04444, 0.0742)
		+ gaussian(v_in, -0.065, 0.3364, 0.05667, 0.0728);

	ret.y = gaussian(v_in,  0.821, 0.5244, 0.1303, 0.1125)
	    + gaussian(v_in,  0.286, 0.4192, 0.0452, 0.0864);

	ret.z = gaussian(v_in,  1.217, 0.1583, 0.0328, 0.1)
	    + gaussian(v_in,  0.681, 0.2194, 0.0722, 0.0383);
	return ret;
}
float black_body_spectrum(float l,float temperature)
{
    float const_1=5.955215e-17;//h*c*c
    float const_2=0.0143878;//(h*c)/k
    float top=(2*const_1);
    float bottom=(exp((const_2)/(temperature*l))-1)*l*l*l*l*l;
    return top/bottom;
}
float black_body(float iter,float temp)
{
    return black_body_spectrum(mix(380*1e-9f,740*1e-9f,iter),temp);
}
float D65_approx(float iter)
{
    //3rd order fit on D65
    float wl=mix(380,740,iter);
    return (-1783.1047729784+9.977734354*wl-(0.0171304983)*wl*wl+(0.0000095146)*wl*wl*wl);
}
float D65_blackbody(float iter,float temp)
{
    float b65=black_body(iter,6503.5);
    return D65_approx(iter)*(black_body(iter,temp)/b65);
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
float float_from_hash(uint val)
{
	return val/4294967295.0f;
}
__kernel void init_agents(__global float8* output,__read_only image2d_t read_tex,int max_count,int seed,
	int sx,int sy,
	int offset,int bundle_size
)
{
	int i=get_global_id(0);
	if(i>=0 && i+offset<max_count)
	{
		float2 center=(float2)(sx,sy);//(float2)(256.0f);
		float max_spread=25.0f;

		float p1=sqrt(float_from_hash(lowbias32(seed+i)))*max_spread;
		float p2=float_from_hash(lowbias32(seed*8+i*1377))*M_PI*2;

		float p3=float_from_hash(lowbias32(seed*77+i*111));
		float angle=((float)i/10000)*6.28318530718;
		float8 agent_data;
		//agent_data.s01=(float2)(256.f)+(float2)(cos(angle),sin(angle))*p;//*256.0f*0.5f;
		//agent_data.s01=(float2)(p1,p2);
		agent_data.s01=(float2)(cos(p2),sin(p2))*p1+(float2)(sx,sy);
		agent_data.s23=(float2)(0,0);//(-cos(angle),-sin(angle));
		float2 delta=center-agent_data.s01;
		//float t=length(delta)/256.0f;(float)i/(float)count;
		float t=length(delta)/max_spread;
		t*=t;
		agent_data.s456=xyz_from_normed_waves(t)*D65_blackbody(t,6503.5);
		agent_data.s7=t;
		output[i+offset]=agent_data;
	}
}
]==]
function init_agents(  )
	agent_count=max_agent_count
	local k=kernels.init_agents
	display_buffer:aquire()
	cl_agent_buffers[1]:aquire()
	k:set(0,cl_agent_buffers[1])
	k:set(1,display_buffer)
	k:seti(2,agent_count)
	local bundle_size=1024--4096
	local bundle_count=math.floor(max_agent_count/bundle_size)
	for i=0,bundle_count-1 do
		k:seti(3,math.random(0,9999999))
		k:seti(4,math.random(0,map_w))
		k:seti(5,math.random(0,map_h))
		k:seti(6,i*bundle_size)
		k:seti(7,bundle_size)
		k:run(bundle_size)
	end

	cl_agent_buffers[1]:release()
	display_buffer:release()
	--[[
	gl_agent_buffers[1]:use()
	local buf=make_flt_buffer(agent_count*2,1)
	gl_agent_buffers[1]:read(buf.d,agent_count*AGENT_SIZE,0);
	for i=0,100 do
		local b=buf:get(i,0)
		print(i,b.r,b.g,b.b,b.a)
	end
	__unbind_buffer()
	--]]
end
function update_agents(  )
    if agent_count==0 then
        return
    end
	local k=kernels.advance_particles
	k:set(0,cl_agent_buffers[1])
	k:set(1,cl_agent_buffers[2])
	k:set(2,display_buffer)
	k:seti(3,agent_count)
	k:set(4,config.color_spread)
	k:set(5,config.speed_mult)
	k:set(6,config.field_mult)
	k:set(7,map_w)
	k:set(8,map_h)
	display_buffer:aquire()
	for i=1,2 do
		cl_agent_buffers[i]:aquire()
	end
	k:run(agent_count)
	for i=1,2 do
		cl_agent_buffers[i]:release()
	end
	display_buffer:release()
	--swap buffers
	local buf=cl_agent_buffers[2]
	cl_agent_buffers[2]=cl_agent_buffers[1]
	cl_agent_buffers[1]=buf
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
            uniform_string=uniform_string..generate_uniform_string({type="sampler2D",name=k})
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
function init_draw_agents(draw_string,settings)
    settings=settings or {}
    local uniform_list=settings.uniforms or {}
    local attributes=settings.attributes or {}

    local uniform_string=generate_uniforms_string(uniform_list)
    local attribute_list,attribute_variables,attribute_assigns,attribute_variables_frag=generate_attribute_strings(attributes)
    settings.attrib_buffers={} or settings.attrib_buffers
    for i,v in ipairs(attributes) do
    	if not v.no_buffer then
	        settings.attrib_buffers[v.name]=settings.attrib_buffers[v.name] or buffer_data.Make()
	        v.attr_buffer=settings.attrib_buffers[v.name]
	    end
    end
    local vert_shader=string.format(
[==[
#version 330
#line __LINE__ 99

%s
#line __LINE__ 99
uniform int pix_size;
uniform vec2 rez;

out vec4 pos_out;
%s
#line __LINE__ 99
void main()
{
    vec2 normed=(agent_position_attrib.xy/rez)*2-vec2(1,1);
    //normed=vec2(agent_position.xy);
    normed.y=-normed.y;
    gl_Position.xy = normed;//mod(normed,vec2(1,1));
    gl_PointSize=1;
    gl_Position.z = 0;
    gl_Position.w = 1.0;
    pos_out=agent_position;
    %s
    #line __LINE__ 99
}
]==],
attribute_list,attribute_variables,attribute_assigns
)
    local frag_shader=string.format(
[==[
#version 330
#line __LINE__ 99

out vec4 color;
in vec4 pos_out;
%s
#line __LINE__ 99
%s
#line __LINE__ 99
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    %s
#line __LINE__ 99
}
]==],
attribute_variables_frag,
uniform_string,draw_string)
    print(vert_shader,frag_shader)
    local draw_shader=shaders.Make(vert_shader,frag_shader)
    local need_clear=false

    local tex_offscreen=textures:Make()
    tex_offscreen:use(0,1)
    tex_offscreen:set(map_w,map_h,1)
    local update_agents=function ( count ,attribs)
        attribs=attribs or {}
        -- [[
        for i,v in ipairs(attributes) do
            local buf=attribs[v.name] or v.buffer
            if buf then
            	v.attr_buffer:use()
            	v.attr_buffer:set(buf.d,count*4*4)
            end
        end
        --]]
        __unbind_buffer()
    end
    local draw=function( count )
        draw_shader:use()
        draw_shader:blend_add()
        -- [[ offscreen render
        if settings.offscreen then
            tex_offscreen:use(0)
            if not tex_offscreen:render_to(map_w,map_h) then
                error("failed to set framebuffer up")
            end
        end
        --]]
        -- clear
        if need_clear then
            __clear()
            need_clear=false
        end

        for i,v in ipairs(attributes) do
        	if v.attr_buffer then
	            v.attr_buffer:use()
	            if v.is_int then
	                draw_shader:push_iattribute(v.offset or 0,v.pos_idx,v.count or 4,v.type,v.stride)
	            else
	                draw_shader:push_attribute(v.offset or 0,v.pos_idx,v.count or 4,v.type,v.stride)
	            end
	        end
        end
        if agent_buffers then
        	agent_buffers:use()
        end
        draw_shader:draw_points(0,count,4)

        draw_shader:blend_default()
        if settings.offscreen then
            __render_to_window()
        end
        __unbind_buffer()
    end
    local update_uniforms=function ( tbl )
        draw_shader:use()
        for i,v in ipairs(uniform_list) do
            if tbl[v.name]~=nil then
                update_uniform(draw_shader,v.type,v.name,tbl)
            end
        end
    end
    local ret={
        shader=draw_shader,
        draw=draw,
        update=update_agents,
        texture=textures,
        update_uniforms=update_uniforms,
        clear=function (  )
            need_clear=true
        end,
        tex_offscreen=tex_offscreen
    }
    
    return ret
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

        --[[
        texture:use(0,0,0)
        draw_shader:set_i('tex_main',0)
        --]]

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
draw_agents=init_draw_agents([==[
#line __LINE__
    //color=vec4(1,1,1,1);
    //color=vec4(pos_out.w,0,0,1);
    //color=vec4(palette(atan(pos_out.w,pos_out.z),vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);
    //color=vec4(palette(length(pos_out.wz),vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);
    //color=vec4(agent_color.xyz,1);
    float life_min=0.8;
    float life_max=1;
    float smoothness=0.05;
    float life=smoothstep(life_min-smoothness,life_min+smoothness,lifetime)-smoothstep(life_max-smoothness,life_max+smoothness,lifetime);
    if(agent_color.w<0)
    	life=0;
    color=vec4(agent_color.xyz*life,1);
    //color=vec4(palette(agent_color.x,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);;
]==],
{
    attributes={
        {pos_idx=1,name="agent_position",offset=0,stride=8*4,no_buffer=true},
        {pos_idx=2,name="agent_color",offset=4*4,stride=8*4,no_buffer=true}
    },
    uniforms={
    	{name="rez",type="vec2"},
        {type="float",name="lifetime"},
    },
    offscreen=true,
})
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
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);

    float angle=(atan(data.y,data.x)/3.14159265359+1)/2;
    float len=min(length(data.xy),1);
    vec4 out_col;
    if (draw_layer==0)
        out_col=vec4(palette(angle,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);
    else if(draw_layer==1)
    {
        len=1-len;
        out_col=vec4(len,len,len,1);
    }else
    {
        vec4 data2=texture(tex_agents,normed);


        data2/=agent_iterations;
        data2.xyz=log(data2.xyz+vec3(1));
        //data2*=agent_gamma;
        data2.xyz=pow(data2.xyz,vec3(agent_gamma));

        out_col.xyz=tonemap(data2.xyz,agent_whitepoint,1);
        out_col.w=1;

        /*
        out_col=vec4(0,0,0,1);
        normed.y=-normed.y;
        vec3 agent_data=clamp(data2.xyz/agent_iterations,0,1);

        vec3 col_agent=pow(log(agent_data+vec3(1)),vec3(agent_gamma));
        //vec3 col_agent=pow(agent_data,vec3(agent_gamma));
        float l=length(col_agent);
        col_agent/=l;
        l = (l*(1 + l / agent_opacity)) / (l + 1);
        col_agent*=l;
        out_col.xyz+=col_agent;
        */
    }
    color=out_col;
}
]==],
{
	uniforms={
		{type="int",  name="draw_layer"},
        {type="float",name="agent_whitepoint"},
        {type="float",name="agent_gamma"},
        {type="float",name="agent_iterations"},
        {type="vec2",name="rez"},
    },
    textures={
    	tex_main={texture=field_texture},
    	tex_agents={texture=draw_agents.tex_offscreen}
    }
}
)

function linear_scaling( pos_len )
    return 1-pos_len/config.influence_size
end
function quadratic_scaling( pos_len )
    local s=1-pos_len/config.influence_size
    return s*s
end
local exp_p=0.35
local exp_psq=exp_p*exp_p
--value to reach at dist 1
function exp_sq( v )
    return math.exp(-v*v/exp_psq)
end
function exp_falloff( v )
    return (exp_sq(v)-exp_sq(1))/(exp_sq(0)-exp_sq(1))
end
function exp_scaling( v )
    return exp_falloff(v/config.influence_size)
end
local scaling_function=exp_scaling

--push/pull
function tool_direct( pos,pos_len )
    local l=pos_len/config.influence_size
    local scale=1-l
    if scale<0 then scale=0 end
    return pos*scale
end
--curl/anticurl
function tool_orthogonal( pos,pos_len )
    local tmp=tool_direct(pos,pos_len)
    return Point(tmp[2],-tmp[1])
end
local tool_functions={
	tool_direct,
	tool_orthogonal
}
local tool_falloff={
	linear_scaling,
	quadratic_scaling,
	exp_scaling
}
function default_field_value( x,y )
	--return Point(math.cos(default_angle),math.sin(default_angle))*config.outside_strength
	local P=Point(x,y)
	local C=Point(map_w/2,map_h/2)
    --local C=Point(map_w/2,-map_h/2)
	--local C=Point(-map_w/2,-map_h/2)
	local D=C-P
	D:normalize()

	--return Point(D[2],-D[1])*config.outside_strength,0.5
	return Point(-D[1],-D[2])*config.outside_strength,0.5
end
function ring_function( dr,da,count,color,angle_offset,rotation)
    local s=exp_scaling(dr*config.influence_size)*config.tool_scale
    local bias=0 --TODO
    local force=Point(s*(math.cos(da*count+angle_offset)+bias),s*(math.sin(da*count+angle_offset)+bias))
    force=force:rotate(rotation or 0)
    return Point(force[1],force[2],color),s
end
function global_field_value( x,y )
    local rings={
        {count=7,radius=0.3,color=0.5,aoffset=0,rotation=math.pi/3},
        {count=4,radius=0.4,color=0.9,aoffset=0,rotation=-math.pi/2,power=0.4},
        {count=7,radius=0.6,color=0.1,aoffset=math.pi/4,rotation=-math.pi/3,power=0.2},
        --{count=7,radius=0.8,color=0.75,aoffset=0,rotation=-math.pi/3},
    }
    local r=math.sqrt(x*x+y*y)
    local a=math.atan2(y,x)
    local wsum=0
    local ret=Point(0,0,0)
    for i,v in ipairs(rings) do

        local dr=math.abs(r-v.radius)
        if dr<config.influence_size then
            local da=a
            local vr,w=ring_function(dr/config.influence_size,da,v.count,v.color,v.aoffset,v.rotation)
            ret=ret+vr*(v.power or 1)
            wsum=wsum+w
        end
    end
    ret[3]=ret[3]/#rings
    return ret,wsum
end
function init_tools(  )
    --[==[
	--[[local tool_list={
		{center=Point(0.5,0.5),power=-config.tool_scale,tool_fun=tool_orthogonal,scale_fun=quadratic_scaling},
		{center=Point(0.75,0.5),power=config.tool_scale,tool_fun=tool_direct,scale_fun=quadratic_scaling},
	}--]]
	local tool_list={}
	--[[ total random
	local offset=0.35;
	for i=1,config.blob_count do
		local power1=math.random(0,1)*2-1
		table.insert(tool_list,{
			--center=Point(math.random(),math.random())*(1-offset*0.5)+Point(1,1)*offset*0.5,
			center=Point(math.random()*2-1,math.random()*2-1)*offset+Point(0.5,0.5),
			--power=math.random()*config.tool_scale*2-config.tool_scale,
			power=power1*config.tool_scale,
			tool_fun=tool_functions[math.random(1,#tool_functions)],
			scale_fun=tool_falloff[math.random(1,#tool_falloff)],
			color_value=math.random()
		})
	end
	--]]
	--[[ 3 rings
	local rfun1=tool_functions[math.random(1,#tool_functions)]
	local rfun2=tool_functions[math.random(1,#tool_functions)]
	local sfun1=tool_falloff[math.random(1,#tool_falloff)]
	local sfun2=tool_falloff[math.random(1,#tool_falloff)]
	local rad1=0.1
	local rad2=rad1+config.influence_size*0.5
	local rad3=rad2+config.influence_size*0.4
	local power1=math.random(0,1)*2-1
	local power2=math.random(0,1)*2-1
	for i=0,2 do
		local angle=math.pi*2*(i/3)
		table.insert(tool_list,{
			center=Point(math.cos(angle)*rad1+0.5,math.sin(angle)*rad1+0.5),
			power=config.tool_scale*power1,
			tool_fun=rfun1,
			scale_fun=sfun1,
			color_value=0.8,
		})
	end

	for i=0,5 do
		local angle=math.pi*2*(i/6)+math.pi/12
		table.insert(tool_list,{
			center=Point(math.cos(angle)*rad2+0.5,math.sin(angle)*rad2+0.5),
			power=config.tool_scale*power2,
			tool_fun=rfun2,
			scale_fun=sfun2,
			color_value=0.5,
		})
	end
	for i=0,11 do
		local angle=math.pi*2*(i/12)-math.pi/6
		table.insert(tool_list,{
			center=Point(math.cos(angle)*rad3+0.5,math.sin(angle)*rad3+0.5),
			power=config.tool_scale*power1,
			tool_fun=rfun1,
			scale_fun=sfun2,
			color_value=0.2,
		})
	end
	--]]

	local buf=make_flt_buffer(map_w,map_h)
	for x=0,map_w-1 do
    for y=0,map_h-1 do
        local value,color_value=default_field_value(x,y)--*(y/map_h)
        local weight_sum=1
        for i,v in ipairs(tool_list) do
    	 	local local_pos=Point(x/map_w,y/map_h)-v.center
            local local_pos_len=local_pos:len()
            if local_pos_len<config.influence_size then
            	local weight=math.abs(v.power)*v.scale_fun(local_pos_len)
            	value=value+v.tool_fun(local_pos,local_pos_len)*v.power*v.scale_fun(local_pos_len)
            	color_value=color_value+v.color_value*weight
            	weight_sum=weight_sum+weight
            end
        end
        buf:set(x,y,{value[1],value[2],0,color_value/weight_sum})
    end
    end
    --]==]
    local default_influence=.001
    local buf=make_flt_buffer(map_w,map_h)
    local cx=map_w/2
    local cy=map_h/2
    for x=0,map_w-1 do
    for y=0,map_h-1 do
        local value_g,color_g=default_field_value(x,y)
        local value,wsum=global_field_value((x-cx)/(map_w/2),(y-cy)/(map_h/2))--*(y/map_h)
        local color=value[3]
        value=(value+value_g*default_influence)/(wsum+default_influence)
        buf:set(x,y,{value[1],value[2],0,color})
    end
    end
    __unbind_buffer()

    field_texture:use(0)
	field_texture:set_sub(buf.d,buf.w,buf.h,FLTA_PIX)

end
function save_img()
    img_buf=make_image_buffer(win_w,win_h)
    img_buf:read_frame()
    img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))))
end
local iterations=1
local agent_iteration=1
function reset_agents(  )
	init_agents()
    draw_agents.clear()
    iterations=1
    agent_iteration=1
end
function update()
    __no_redraw()
    __clear()
    imgui.Begin("Magic system test")
    draw_config(config)
    for i=1,1 do
        if config.sim_agents then
            update_agents()
            agent_iteration=agent_iteration+1
        end
        if config.draw_trails then
        	draw_agents.shader:use()
        	draw_agents.update_uniforms({rez={map_w,map_h},lifetime=agent_iteration/config.max_agent_iterations})
        	gl_agent_buffers[1]:use()
        	--push_attribute (offset/data,id/name,num_of_id,type,stride)
        	draw_agents.shader:push_attribute(0,1,4,GL_FLOAT,8*4)
        	draw_agents.shader:push_attribute(4*4,2,4,GL_FLOAT,8*4)
        	--draw_agents.shader:draw_points(0,agent_count,4)
            draw_agents.draw(agent_count)
        	__unbind_buffer()
        	
            iterations=iterations+1
        end

    end
    if config.__change_events.any then
        draw_field.update_uniforms(config)
    end
    draw_field.update_uniforms{agent_iterations=iterations,rez={map_w,map_h}}
    draw_field.draw()
    if imgui.Button("Save") then
        save_img()
    end
    imgui.Text(string.format("Agent count:%d",agent_count))
    imgui.Text(string.format("Iteration:%d",iterations))
    if agent_iteration>config.max_agent_iterations then
    	init_agents()
    	agent_iteration=1
    end
    if imgui.Button("Reset agents") then
        reset_agents()
    end
    if imgui.Button("Step agents") then
        update_agents()
    end
    if imgui.Button("Regen") then
        init_tools()
        reset_agents()
    end
    if imgui.Button("Clear") then
        draw_agents.clear()
        draw_field.clear()
        iterations=1
    end
   
    imgui.End()
end