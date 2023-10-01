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

local max_agent_count=10000
local agent_count=0
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

field_texture=textures:Make()
field_texture:use(0)
field_texture:set(map_w,map_h,F_PIX)
local display_buffer=opencl.make_buffer_gl(field_texture)

kernels=opencl.make_program
[==[
#line __LINE__
__kernel void advance_particles(__global float8* input,__global float8* output,__read_only image2d_t read_tex,int count)
{
	int i=get_global_id(0);
	if(i>=0 && i<count)
	{
		//TODO: there is a better way to do this in opencl...
		float8 agent_data=input[i];
		/*
		float2 pos=(float2)(input[i*8],input[i*8+1]);
		float2 speed=(float2)(input[i*8+2],input[i*8+3]);
		float4 color=(float2)(input[i*8+2],input[i*8+3]);
		*/
		output[i]=agent_data;
		/*
		output[i*8+0]=pos.x;
		output[i*8+1]=pos.y;
		output[i*8+2]=speed.x;
		output[i*8+3]=speed.y;
		*/
	}
}
__kernel void init_agents(__global float8* output,__read_only image2d_t read_tex,int count,int seed)
{
	int i=get_global_id(0);
	if(i>=0 && i<count)
	{
		//TODO: there is a better way to do this in opencl...
		float8 agent_data;
		agent_data.s0=i/100;
		agent_data.s1=128;
		agent_data.s2=0;
		agent_data.s3=0;

		agent_data.s4=1;
		agent_data.s5=1;
		agent_data.s6=1;
		agent_data.s7=0;
		output[i]=agent_data;
	}
}
]==]
function init_agents(  )
	agent_count=max_agent_count
	local k=kernels.init_agents
	k:set(0,cl_agent_buffers[1])
	k:set(1,display_buffer)
	k:set(2,agent_count)

	display_buffer:aquire()
	cl_agent_buffers[1]:aquire()
	k:run(agent_count)
	cl_agent_buffers[1]:release()
	display_buffer:release()
end
function update_agents(  )
	local k=kernels.advance_particles
	k:set(0,cl_agent_buffers[1])
	k:set(1,cl_agent_buffers[2])
	k:set(2,display_buffer)
	k:set(3,agent_count)

	display_buffer:aquire()
	for i=1,2 do
		cl_agent_buffers[i]:aquire()
	end
	k:run(agent_count)
	for i=1,2 do
		cl_agent_buffers[i]:release()
	end
	display_buffer:release()
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
        for i,v in ipairs(texture_list) do
            uniform_string=uniform_string..generate_uniform_string({type="sampler2D",name=v.name})
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
    vec2 normed=(agent_position.xy/rez)*2-vec2(1,1);
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
        for i,v in ipairs(texture_list) do
            v.texture:use(i)
            draw_shader:set_i(v.name,i)
        end

        texture:use(0,0,0)
        draw_shader:set_i('tex_main',0)

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
    color=vec4(1,0,0,1);
    //color=vec4(pos_out.w,0,0,1);
    //color=vec4(palette(atan(pos_out.w,pos_out.z),vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);
    //color=vec4(palette(length(pos_out.wz),vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);
    //color=vec4(agent_color.xyz*pow(agent_color.w,1),1);
    //color=vec4(palette(agent_color.x,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);;
]==],
{
    attributes={
        {pos_idx=0,name="agent_position",offset=0,stride=8,no_buffer=true},
        {pos_idx=1,name="agent_color",offset=4,stride=8,no_buffer=true}
    },
    uniforms={
    	{name="rez",type="vec2"}
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
        out_col=vec4(palette(angle,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75))*len,1);
    else if(draw_layer==1)
    {
        len=1-len;
        out_col=vec4(len,len,len,1);
    }else
    {
        vec4 data2=texture(tex_agents,normed);

        data2/=agent_iterations;
        //data2.xyz=log(data2.xyz+vec3(1));
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
    	{texture=field_texture,name="tex_main"},
    	{texture=draw_agents.tex_offscreen,name="tex_agents"}
    }
}
)
local iterations=1
function update()
    __no_redraw()
    __clear()
    imgui.Begin("Magic system test")
    draw_config(config)
    if config.__change_events.any then
        draw_field.update_uniforms(config)
    end
    draw_field.update_uniforms{agent_iterations=iterations,rez={map_w,map_h}}
    if config.sim_agents then
        update_agents()
    end
    if config.draw_trails then
    	draw_agents.update_uniforms({rez={map_w,map_h}})
    	gl_agent_buffers[1]:use()
    	draw_agents.shader:push_attribute(0,0,4,nil,8)
    	draw_agents.shader:push_attribute(4,1,4,nil,8)
        draw_agents.draw(agent_count)
    	__unbind_buffer()
        iterations=iterations+1
    end
    draw_field.draw()
    if imgui.Button("Save") then
        save_img()
    end
    imgui.Text(string.format("Agent count:%d",agent_count))
    if imgui.Button("Reset agents") then
        init_agents()
        draw_agents.clear()
        iterations=1
    end
    if imgui.Button("Step agents") then
        update_agents()
    end
    if imgui.Button("Regen") then
        init_tools()
        update_field()
    end
    if imgui.Button("Clear") then
        draw_agents.clear()
        draw_field.clear()
        iterations=1
    end
   
    imgui.End()
end