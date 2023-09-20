--[[
	simple vector field. Stuff happens if "particles" linger.

	place things that modify the grad-field. find places where fields becomes low, draw stuff there

	maybe too easy so we could do N fields and only when few of them overlap magic happens. Then you
	could make tools manipulate few fields at once and thus not be clear what needs to be done.

	random ideas:
		* outside field (i.e. normally particles are not stopped, thus no magic)
		* interaction types:
			* orthogonal-like - i.e. four basic ones (push, pull, curl, anticurl)
			* mixed nonsense - e.g. could be because your gem is with a flaw
		* interaction distance:
			* also falloff - linear, square, exp, etc...
		* insane interactions, like f(vec)=sin(cos(|vec|))*exp(-|vec|^2)/....
]]


require "common"

local win_w=1280
local win_h=1280
local oversample=1/4
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local influence_size=0.6
local max_tool_count=30
current_tool_count=current_tool_count or 0
--x,y,type,???
tool_data={}--make_flt_buffer(max_tool_count,1)
--x,y,??,??
if field==nil or field.w~=map_w or field.h~=map_h then
	field=make_flt_buffer(map_w,map_h)
end

local agent_count=10000
if agents==nil or agents.w~=agent_count then
	agents=make_flt_buffer(agent_count,1)
end

local outside_angle=math.random()*math.pi*2


config=make_config({
	{"blob_count",5,type="int",min=1,max=max_tool_count},
	--[[{"placement",0,type="choice",choices={
		"single_center",		
		}},]]
	--[[ blob type choice]]
	{"blob_order",14,type="int",min=2,max=14},
	{"seed",0,type="int",min=0,max=10000000},
	{"outside_strength",1.0,type="float",min=0,max=10},
	{"tool_scale",0.25,type="float",min=0,max=10},

	{"draw_layer",0,type="int",min=0,max=1,watch=true},
},config)



function random_coefs( count )
	local order={
		1,1,
		2,2,2,
		3,3,3,3,
		4,4,4,4,4
	}
	local ret={}
	for i=1,14 do
		if i<count then
			ret[i]=math.random()*2-1
			--ret[i]=(math.random()*2-1)/order[i]
			--ret[i]=(math.random()*2-1)/math.pow(2,order[i])
		else
			ret[i]=0
		end
	end
	return ret
end
function init_tools(  )
	
	tool_data={}
	--[[
	current_tool_count=1
	tool_data[1]={0.5,0.5,1,random_coefs(14)}
	tool_data[2]={0.25,0.5,1,random_coefs(9)}
	tool_data[3]={0.75,0.5,1,random_coefs(9)}
	--]]
	--[[
	local dist=0.2
	local pos={
		{dist,dist},
		{dist,1-dist},
		{1-dist,dist},
		{1-dist,1-dist}
	}
	local general_scale=0.5
	current_tool_count=#pos
	for i=1,#pos do
		tool_data[i]={pos[i][1],pos[i][2],math.random()*general_scale*2-general_scale,random_coefs(14)}
	end
	--]]
	-- [[
	local dist=0.35
	
	local general_scale=config.tool_scale
	current_tool_count=config.blob_count
	for i=1,current_tool_count do
		local a=(i/current_tool_count)*math.pi*2
		tool_data[i]={math.cos(a)*dist+0.5,math.sin(a)*dist+0.5,math.random()*general_scale*2-general_scale,random_coefs(config.blob_order)}
	end
	--]]
	--[[
	local general_scale=0.5
	current_tool_count=2
	for i=1,current_tool_count do
		tool_data[i]={math.random(),math.random(),math.random()*general_scale*2-general_scale,random_coefs(14)}
	end
	--]]
	--[[
	current_tool_count=1
	tool_data:set(0,0,{0.5,0.5,25,2})
	tool_data:set(2,0,{0.37,0.55,-35,0})
	tool_data:set(3,0,{0.65,0.5,0,1})
	tool_data:set(4,0,{0.65,0.5,30,0})
	--]]
	--[[
	current_tool_count=max_tool_count
	for i=0,current_tool_count-1 do
		if math.random()<0 then
			tool_data:set(i,0,{math.random(),math.random(),math.random()*60-30,2})
		else
			tool_data:set(i,0,{math.random(),math.random(),math.random()*60-30,3})
		end
	end
	--]]
end

function linear_scaling( pos_len )
	return 1-pos_len/influence_size
end
function quadratic_scaling( pos_len )
	local s=1-pos_len/influence_size
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
	return exp_falloff(v/influence_size)
end
local scaling_function=exp_scaling
--push/pull
function tool_direct_linear( pos,power,pos_len )
	local l=pos_len/influence_size
	local scale=1-l
	if scale<0 then scale=0 end
	return pos*power*scale
end
--curl/anticurl
function tool_orthogonal_linear( pos,power,pos_len )
	local tmp=tool_direct_linear(pos,power,pos_len)
	return Point(tmp[2],-tmp[1])
end


--push/pull
function tool_direct_sqr( pos,power,pos_len )
	local l=pos_len/influence_size
	local scale=1-l
	if scale<0 then scale=0 end
	return pos*power*scale*scale
end
--curl/anticurl
function tool_orthogonal_sqr( pos,power,pos_len )
	local tmp=tool_direct_sqr(pos,power,pos_len)
	return Point(tmp[2],-tmp[1])
end


--push/pull
function tool_direct_exp( pos,power,pos_len )
	local l=pos_len/influence_size
	local scale=l
	if scale>1 then scale=1 end
	scale=exp_falloff(scale)
	return pos*power*scale
end
--curl/anticurl
function tool_orthogonal_exp( pos,power,pos_len )
	local tmp=tool_direct_exp(pos,power,pos_len)
	return Point(tmp[2],-tmp[1])
end
local tools={
	tool_direct_linear,
	tool_orthogonal_linear,
	tool_direct_sqr,
	tool_orthogonal_sqr,
	tool_direct_exp,
	tool_orthogonal_exp
}

function zernike_der_function( pos,arguments )
	--0th is 0 both in x and y
	local X=pos[1]
	local Y=pos[2]
	local ox=
		--11-1 is 0
		2*arguments[2]+

		math.sqrt(6)*2*Y*arguments[3]+
		math.sqrt(3)*4*X*arguments[4]+
		math.sqrt(6)*2*X*arguments[5]+

		math.sqrt(8)*6*X*Y*(arguments[6]+
									arguments[7])+
		math.sqrt(8)*(9*X*X+3*Y*Y-2)*arguments[8]+
		math.sqrt(8)*3*(X*X-Y*Y)*arguments[9]+

		math.sqrt(10)*(12*X*X*Y-4*Y*Y*Y)*arguments[10]+
		math.sqrt(10)*(24*X*X*Y+8*Y*Y*Y-6*Y)*arguments[11]+
		math.sqrt(5)*(24*X*X*X+24*X*Y*Y-12*X)*arguments[12]+
		math.sqrt(10)*(16*X*X*X-6*X)*arguments[13]+
		math.sqrt(10)*(4*X*X*X-12*X*Y*Y)*arguments[14]

	local oy=
		2*arguments[1]+
		--111 is 0
		math.sqrt(6)*2*X*arguments[3]+
		math.sqrt(3)*4*Y*arguments[4]+
		math.sqrt(6)*(-2)*Y*arguments[5]+

		math.sqrt(8)*3*(X*X-Y*Y)*arguments[6]+
		math.sqrt(8)*(3*X*X+9*Y*Y-2)*arguments[7]+
		math.sqrt(8)*6*X*Y*(arguments[8]-
									arguments[9])+

		math.sqrt(10)*(4*X*X*X-12*X*Y*Y)*arguments[10]+
		math.sqrt(10)*(24*X*Y*Y+8*X*X*X-6*X)*arguments[11]+
		math.sqrt(5)*(24*Y*Y*Y+24*X*X*Y-12*Y)*arguments[12]+
		math.sqrt(10)*(-16*Y*Y*Y+6*Y)*arguments[13]+
		math.sqrt(10)*(-12*X*X*Y+4*Y*Y*Y)*arguments[14]
	return Point(ox,oy)
end

function update_field(  )
	local default_field=Point(math.cos(outside_angle),math.sin(outside_angle))*config.outside_strength
	--zernike version
	for x=0,map_w-1 do
	for y=0,map_h-1 do
		local value=default_field--*(y/map_h)
		for i=0,current_tool_count-1 do
			local td=tool_data[i+1]--tool_data:get(i,0)
			local local_pos=Point(x/map_w,y/map_h)-Point(td[1],td[2])
			local local_pos_len=local_pos:len()
			local normed_pos=(1/influence_size)*local_pos
			if local_pos_len<influence_size then
				local angle=math.atan(local_pos[2],local_pos[1])
				--value=local_pos*local_pos_len
				value=value+zernike_der_function(normed_pos,td[4])*scaling_function(local_pos_len)*td[3]
			end
		end
		field:set(x,y,{value[1],value[2],0,0})
	end
	end
	--[[
	for x=0,map_w-1 do
	for y=0,map_h-1 do
		local value=default_field--*(y/map_h)
		for i=0,current_tool_count-1 do
			local td=tool_data[i+1]--tool_data:get(i,0)
			local tool_fun=tools[math.floor(td[4])+1]
			local local_pos=Point(x/map_w,y/map_h)-Point(td[1],td[2])
			local local_pos_len=local_pos:len()
			if local_pos_len<influence_size then
				--value=local_pos*local_pos_len
				value=value+tool_fun(local_pos,td[3],local_pos_len)
			end
		end
		field:set(x,y,{value[1],value[2],0,0})
	end
	end
	--]]
	draw_field.update(field)
end
function generate_uniform_string( v )
	return string.format("uniform %s %s;\n",v[1],v[2])
end
function update_uniform( shader,name,value_table )
	shader:set_i(name,value_table[name])
end
function init_draw_field(draw_string,uniform_list)
	local uniform_string=""
	if uniform_list~=nil then
		for i,v in ipairs(uniform_list) do
			uniform_string=uniform_string..generate_uniform_string(v)
		end
	end
	local draw_shader=shaders.Make(
string.format([==[
#version 330
#line __LINE__ 99

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
#line __LINE__ 99
%s
#line __LINE__ 99
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);
    %s
}
]==],uniform_string,draw_string))
	local texture=textures:Make()
	local update_texture=function ( buffer )
		buffer:write_texture(texture)
	end
	local draw=function(  )
		draw_shader:use()
		texture:use(0,0,0)
		draw_shader:set_i('tex_main',0)
		draw_shader:draw_quad()
	end
	local update_uniforms=function ( tbl )
		draw_shader:use()
		for i,v in ipairs(uniform_list) do
			--todo more formats!
			if tbl[v[2]]~=nil then
				update_uniform(draw_shader,v[2],tbl)
			end
		end
	end
	local ret={
		shader=draw_shader,
		draw=draw,
		update=update_texture,
		texture=textures,
		update_uniforms=update_uniforms
	}
	
	return ret
end
if draw_field==nil or regen_shader then
draw_field=init_draw_field([==[
#line __LINE__
	float angle=(atan(data.y,data.x)/3.14159265359+1)/2;
	float len=min(length(data.xy),1);
	if (draw_layer==0)
		color=vec4(palette(angle,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75))*len,1);
	else
	{
		len=1-len;
		color=vec4(len,len,len,1);
	}
]==],{{"int","draw_layer"}})
end

function init_draw_agents(draw_string,uniform_list)
	local uniform_string=""
	if uniform_list~=nil then
		for i,v in ipairs(uniform_list) do
			uniform_string=uniform_string..generate_uniform_string(v)
		end
	end
	local draw_shader=shaders.Make(
[==[
#version 330
#line __LINE__ 99
layout(location = 0) in vec4 position;

uniform int pix_size;
uniform vec4 params;
uniform vec2 rez;

out vec4 pos_out;
void main()
{
	vec2 normed=(position.xy/rez)*2-vec2(1,1);
	gl_Position.xy = normed;//mod(normed,vec2(1,1));
	gl_PointSize=pix_size;
	gl_Position.z = 0;
    gl_Position.w = 1.0;
    pos_out=position;
}
]==],
string.format([==[
#version 330
#line __LINE__ 99

out vec4 color;
in vec4 pos;

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
]==],uniform_string,draw_string))
	local texture=textures:Make()
	local update_agents=function ( buffer )
		error("TODO")
	end
	local draw=function(  )		
		draw_shader:use()
		draw_shader:set_i('tex_main',0)
		draw_shader:draw_quad()
	end
	local update_uniforms=function ( tbl )
		draw_shader:use()
		for i,v in ipairs(uniform_list) do
			--todo more formats!
			if tbl[v[2]]~=nil then
				update_uniform(draw_shader,v[2],tbl)
			end
		end
	end
	local ret={
		shader=draw_shader,
		draw=draw,
		update=update_agents,
		texture=textures,
		update_uniforms=update_uniforms
	}
	
	return ret
end
if draw_agents==nil or regen_shader then
draw_agents=init_draw_field([==[
#line __LINE__

	color=vec4(palette(angle,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75))*pos.z,1);

]==],{{"int","draw_layer"}})
end

function save_img()
	img_buf=make_image_buffer(win_w,win_h)
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))))
end

function update()
	__no_redraw()
	__clear()
	imgui.Begin("Magic system test")
	draw_config(config)
	if config.__change_events.any then
		draw_field.update_uniforms(config)
	end
	draw_field.draw()
	if imgui.Button("Regen") then
		init_tools()
		update_field()
	end
	if imgui.Button("Save") then
		save_img()
	end
	imgui.End()
end