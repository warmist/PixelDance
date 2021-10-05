--from: https://sagejenson.com/physarum
--[[
	ideas:
		add other types of agents
		more interactive "world"
			* eatible food
			* sand-like sim?
			* more senses (negative?)
		mass and non-instant turning

        LOG space sensing/drawing. All natural things love log/exp spaces!
--]]

require 'common'
local win_w=1280
local win_h=1280

__set_window_size(win_w,win_h)
local oversample=1
local agent_count=3e6
--[[ perf:
	oversample 2 768x768
		ac: 3000 -> 43fps
			no_steps ->113fps
			no_tracks ->43fps
		gpu: 200*200 (40k)->35 fps
	map: 1024x1024
		200*200 -> 180 fps
	feedback: 
		RTX 2060
			33554432 ~20fps
			1e7 ~60fps

]]
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)
is_remade=false
function update_buffers(  )
    local nw=map_w
    local nh=map_h

    if signal_buf==nil or signal_buf.w~=nw or signal_buf.h~=nh then
    	tex_pixel=textures:Make()
    	tex_pixel:use(0)
        signal_buf=make_float_buffer(nw,nh)
        signal_buf:write_texture(tex_pixel)
        is_remade=true
    end
end

if agent_data==nil or agent_data.w~=agent_count then
	agent_data=make_flt_buffer(agent_count,1)
	agent_buffers={buffer_data.Make(),buffer_data.Make(),current=1,other=2,flip=function( t )
		if t.current==1 then
			t.current=2
			t.other=1
		else
			t.current=1
			t.other=2
		end
	end,
	get_current=function (t)
		return t[t.current]
	end,
	get_other=function ( t )
		return t[t.other]
	end}

	for i=0,agent_count-1 do
			agent_data:set(i,0,{math.random()*map_w,math.random()*map_h,math.random()*math.pi*2,0})
	end
	for i=1,2 do
		agent_buffers[i]:use()
		agent_buffers[i]:set(agent_data.d,agent_count*4*4)
	end
end
-- [[
local bwrite = require "blobwriter"
local bread = require "blobreader"
function read_background_buf( fname )
	local file = io.open(fname, 'rb')
	local b = bread(file:read('*all'))
	file:close()

	local sx=b:u32()
	local sy=b:u32()
	background_buf=make_float_buffer(sx,sy)
	background_minmax={}
	background_minmax[1]=b:f32()
	background_minmax[2]=b:f32()
	for x=0,background_buf.w-1 do
	for y=0,background_buf.h-1 do
		local v=(math.log(b:f32()+1)-background_minmax[1])/(background_minmax[2]-background_minmax[1])
		background_buf:set(x,y,v)
	end
	end
end
function make_background_texture()
	if background_tex==nil then
		print("making tex")
		read_background_buf("out.buf")
		background_tex={t=textures:Make(),w=background_buf.w,h=background_buf.h}
		background_tex.t:use(0,1)
		background_buf:write_texture(background_tex.t)
		__unbind_buffer()
	end
end
--make_background_texture()
--]]
update_buffers()
config=make_config({
    {"pause",false,type="bool"},
    {"color_back",{0.208, 0.274, 0.386, 1.000},type="color"},
    {"color_fore",{0.047, 0.000, 0.000, 1.000},type="color"},
    {"color_turn_around",{1,1,1,1},type="color"},
    --system
    {"decay",0.99174201488495,type="floatsci",min=0.99,max=1},
    --{"diffuse",0.5,type="float"},
    --agent
    {"ag_sensor_distance",5.1840000152588,type="float",min=0.1,max=10},
    --{"ag_sensor_size",1,type="int",min=1,max=3},
    {"ag_sensor_angle",1.3159999847412,type="float",min=0,max=math.pi/2},
    {"ag_turn_angle",0.25,type="float",min=-1,max=1},
    {"ag_turn_avoid",-0.60900002717972,type="float",min=-1,max=1},
    {"ag_step_size",6.7600002288818,type="float",min=0.01,max=10},
    {"ag_trail_amount",0.5,type="float",min=0,max=0.5},
    {"trail_size",1,type="int",min=1,max=5},
    {"turn_around",200,type="float",min=0,max=200},
    {"ag_clumpiness",70.871002197266,type="float",min=0,max=1},
    },config)

local decay_diffuse_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform float diffuse;
uniform float decay;

uniform sampler2D tex_main;

float sample_around(vec2 pos)
{
	float ret=0;
	ret+=textureOffset(tex_main,pos,ivec2(-1,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,1)).x;

	ret+=textureOffset(tex_main,pos,ivec2(0,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(0,1)).x;
	return ret/8;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float r=sample_around(normed)*diffuse;
	r+=texture(tex_main,normed).x*(1-diffuse);
	r*=decay;
	//r=clamp(r,0,1);
	color=vec4(r,0,0,1);
}
]==]

add_visit_shader=shaders.Make(
[==[
#version 330
#line 105
layout(location = 0) in vec4 position;

uniform int pix_size;
uniform float seed;
uniform float move_dist;
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
[==[
#version 330
#line 125

out vec4 color;
//in vec3 pos;
in vec4 pos_out;
uniform int pix_size;
uniform float trail_amount;
float shape_point(vec2 pos)
{
	//float rr=clamp(1-txt.r,0,1);
	//float rr = abs(pos.y*pos.y);
	float rr=dot(pos.xy,pos.xy);
	//float rr = pos.y-0.5;
	//float rr = length(pos.xy)/5.0;
	rr=clamp(rr,0,1);
	float delta_size=(1-0.2)*rr+0.2;
	return delta_size;
}
void main(){
#if 0
	float delta_size=shape_point(pos.xy);
#else
	float delta_size=1;
#endif
 	float r = 2*length(gl_PointCoord - 0.5)/(delta_size);
	float a = 1 - smoothstep(0, 1, r);
	float intensity=1/float(pix_size);
	//rr=clamp((1-rr),0,1);
	//rr*=rr;
	//color=vec4(a,0,0,1);
    if(pos_out.w>0.5)
	   color=vec4(a*intensity*trail_amount,0,0,1);
    else
       color=vec4(-a*intensity*trail_amount,0,0,1);
	//color=vec4(1,0,0,1);
}
]==])
function add_trails_fbk(  )
	add_visit_shader:use()
	tex_pixel:use(0)
	add_visit_shader:blend_add()
	add_visit_shader:set_i("pix_size",config.trail_size)
	add_visit_shader:set("trail_amount",config.ag_trail_amount)
	add_visit_shader:set("rez",map_w,map_h)
	if not tex_pixel:render_to(map_w,map_h) then
		error("failed to set framebuffer up")
	end
	if need_clear then
		__clear()
		need_clear=false
		--print("Clearing")
	end
	agent_buffers:get_current():use()
	add_visit_shader:draw_points(0,agent_count,4)

	add_visit_shader:blend_default()
	__render_to_window()
	__unbind_buffer()
end
local draw_shader=shaders.Make[==[
#version 330
#line 209
out vec4 color;
in vec3 pos;

uniform ivec2 rez;
uniform sampler2D tex_main;

uniform float turn_around;
uniform vec4 color_back;
uniform vec4 color_fore;
uniform vec4 color_turn_around;

float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise(vec2 p){
	vec2 ip = floor(p);
	vec2 u = fract(p);
	u = u*u*(3.0-2.0*u);
	
	float res = mix(
		mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
		mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
	return res*res;
}

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


/*
HSLUV-GLSL v4.2
HSLUV is a human-friendly alternative to HSL. ( http://www.hsluv.org )
GLSL port by William Malo ( https://github.com/williammalo )
Put this code in your fragment shader.
*/

vec3 hsluv_intersectLineLine(vec3 line1x, vec3 line1y, vec3 line2x, vec3 line2y) {
    return (line1y - line2y) / (line2x - line1x);
}

vec3 hsluv_distanceFromPole(vec3 pointx,vec3 pointy) {
    return sqrt(pointx*pointx + pointy*pointy);
}

vec3 hsluv_lengthOfRayUntilIntersect(float theta, vec3 x, vec3 y) {
    vec3 len = y / (sin(theta) - x * cos(theta));
    if (len.r < 0.0) {len.r=1000.0;}
    if (len.g < 0.0) {len.g=1000.0;}
    if (len.b < 0.0) {len.b=1000.0;}
    return len;
}

float hsluv_maxSafeChromaForL(float L){
    mat3 m2 = mat3(
         3.2409699419045214  ,-0.96924363628087983 , 0.055630079696993609,
        -1.5373831775700935  , 1.8759675015077207  ,-0.20397695888897657 ,
        -0.49861076029300328 , 0.041555057407175613, 1.0569715142428786  
    );
    float sub0 = L + 16.0;
    float sub1 = sub0 * sub0 * sub0 * .000000641;
    float sub2 = sub1 > 0.0088564516790356308 ? sub1 : L / 903.2962962962963;

    vec3 top1   = (284517.0 * m2[0] - 94839.0  * m2[2]) * sub2;
    vec3 bottom = (632260.0 * m2[2] - 126452.0 * m2[1]) * sub2;
    vec3 top2   = (838422.0 * m2[2] + 769860.0 * m2[1] + 731718.0 * m2[0]) * L * sub2;

    vec3 bounds0x = top1 / bottom;
    vec3 bounds0y = top2 / bottom;

    vec3 bounds1x =              top1 / (bottom+126452.0);
    vec3 bounds1y = (top2-769860.0*L) / (bottom+126452.0);

    vec3 xs0 = hsluv_intersectLineLine(bounds0x, bounds0y, -1.0/bounds0x, vec3(0.0) );
    vec3 xs1 = hsluv_intersectLineLine(bounds1x, bounds1y, -1.0/bounds1x, vec3(0.0) );

    vec3 lengths0 = hsluv_distanceFromPole( xs0, bounds0y + xs0 * bounds0x );
    vec3 lengths1 = hsluv_distanceFromPole( xs1, bounds1y + xs1 * bounds1x );

    return  min(lengths0.r,
            min(lengths1.r,
            min(lengths0.g,
            min(lengths1.g,
            min(lengths0.b,
                lengths1.b)))));
}

float hsluv_maxChromaForLH(float L, float H) {

    float hrad = radians(H);

    mat3 m2 = mat3(
         3.2409699419045214  ,-0.96924363628087983 , 0.055630079696993609,
        -1.5373831775700935  , 1.8759675015077207  ,-0.20397695888897657 ,
        -0.49861076029300328 , 0.041555057407175613, 1.0569715142428786  
    );
    float sub1 = pow(L + 16.0, 3.0) / 1560896.0;
    float sub2 = sub1 > 0.0088564516790356308 ? sub1 : L / 903.2962962962963;

    vec3 top1   = (284517.0 * m2[0] - 94839.0  * m2[2]) * sub2;
    vec3 bottom = (632260.0 * m2[2] - 126452.0 * m2[1]) * sub2;
    vec3 top2   = (838422.0 * m2[2] + 769860.0 * m2[1] + 731718.0 * m2[0]) * L * sub2;

    vec3 bound0x = top1 / bottom;
    vec3 bound0y = top2 / bottom;

    vec3 bound1x =              top1 / (bottom+126452.0);
    vec3 bound1y = (top2-769860.0*L) / (bottom+126452.0);

    vec3 lengths0 = hsluv_lengthOfRayUntilIntersect(hrad, bound0x, bound0y );
    vec3 lengths1 = hsluv_lengthOfRayUntilIntersect(hrad, bound1x, bound1y );

    return  min(lengths0.r,
            min(lengths1.r,
            min(lengths0.g,
            min(lengths1.g,
            min(lengths0.b,
                lengths1.b)))));
}

float hsluv_fromLinear(float c) {
    return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}
vec3 hsluv_fromLinear(vec3 c) {
    return vec3( hsluv_fromLinear(c.r), hsluv_fromLinear(c.g), hsluv_fromLinear(c.b) );
}

float hsluv_toLinear(float c) {
    return c > 0.04045 ? pow((c + 0.055) / (1.0 + 0.055), 2.4) : c / 12.92;
}

vec3 hsluv_toLinear(vec3 c) {
    return vec3( hsluv_toLinear(c.r), hsluv_toLinear(c.g), hsluv_toLinear(c.b) );
}

float hsluv_yToL(float Y){
    return Y <= 0.0088564516790356308 ? Y * 903.2962962962963 : 116.0 * pow(Y, 1.0 / 3.0) - 16.0;
}

float hsluv_lToY(float L) {
    return L <= 8.0 ? L / 903.2962962962963 : pow((L + 16.0) / 116.0, 3.0);
}

vec3 xyzToRgb(vec3 tuple) {
    const mat3 m = mat3( 
        3.2409699419045214  ,-1.5373831775700935 ,-0.49861076029300328 ,
       -0.96924363628087983 , 1.8759675015077207 , 0.041555057407175613,
        0.055630079696993609,-0.20397695888897657, 1.0569715142428786  );
    
    return hsluv_fromLinear(tuple*m);
}

vec3 rgbToXyz(vec3 tuple) {
    const mat3 m = mat3(
        0.41239079926595948 , 0.35758433938387796, 0.18048078840183429 ,
        0.21263900587151036 , 0.71516867876775593, 0.072192315360733715,
        0.019330818715591851, 0.11919477979462599, 0.95053215224966058 
    );
    return hsluv_toLinear(tuple) * m;
}

vec3 xyzToLuv(vec3 tuple){
    float X = tuple.x;
    float Y = tuple.y;
    float Z = tuple.z;

    float L = hsluv_yToL(Y);
    
    float div = 1./dot(tuple,vec3(1,15,3)); 

    return vec3(
        1.,
        (52. * (X*div) - 2.57179),
        (117.* (Y*div) - 6.08816)
    ) * L;
}


vec3 luvToXyz(vec3 tuple) {
    float L = tuple.x;

    float U = tuple.y / (13.0 * L) + 0.19783000664283681;
    float V = tuple.z / (13.0 * L) + 0.468319994938791;

    float Y = hsluv_lToY(L);
    float X = 2.25 * U * Y / V;
    float Z = (3./V - 5.)*Y - (X/3.);

    return vec3(X, Y, Z);
}

vec3 luvToLch(vec3 tuple) {
    float L = tuple.x;
    float U = tuple.y;
    float V = tuple.z;

    float C = length(tuple.yz);
    float H = degrees(atan(V,U));
    if (H < 0.0) {
        H = 360.0 + H;
    }
    
    return vec3(L, C, H);
}

vec3 lchToLuv(vec3 tuple) {
    float hrad = radians(tuple.b);
    return vec3(
        tuple.r,
        cos(hrad) * tuple.g,
        sin(hrad) * tuple.g
    );
}

vec3 hsluvToLch(vec3 tuple) {
    tuple.g *= hsluv_maxChromaForLH(tuple.b, tuple.r) * .01;
    return tuple.bgr;
}

vec3 lchToHsluv(vec3 tuple) {
    tuple.g /= hsluv_maxChromaForLH(tuple.r, tuple.b) * .01;
    return tuple.bgr;
}

vec3 hpluvToLch(vec3 tuple) {
    tuple.g *= hsluv_maxSafeChromaForL(tuple.b) * .01;
    return tuple.bgr;
}

vec3 lchToHpluv(vec3 tuple) {
    tuple.g /= hsluv_maxSafeChromaForL(tuple.r) * .01;
    return tuple.bgr;
}

vec3 lchToRgb(vec3 tuple) {
    return xyzToRgb(luvToXyz(lchToLuv(tuple)));
}

vec3 rgbToLch(vec3 tuple) {
    return luvToLch(xyzToLuv(rgbToXyz(tuple)));
}

vec3 hsluvToRgb(vec3 tuple) {
    return lchToRgb(hsluvToLch(tuple));
}

vec3 rgbToHsluv(vec3 tuple) {
    return lchToHsluv(rgbToLch(tuple));
}

vec3 hpluvToRgb(vec3 tuple) {
    return lchToRgb(hpluvToLch(tuple));
}

vec3 rgbToHpluv(vec3 tuple) {
    return lchToHpluv(rgbToLch(tuple));
}

vec3 luvToRgb(vec3 tuple){
    return xyzToRgb(luvToXyz(tuple));
}

// allow vec4's
vec4   xyzToRgb(vec4 c) {return vec4(   xyzToRgb( vec3(c.x,c.y,c.z) ), c.a);}
vec4   rgbToXyz(vec4 c) {return vec4(   rgbToXyz( vec3(c.x,c.y,c.z) ), c.a);}
vec4   xyzToLuv(vec4 c) {return vec4(   xyzToLuv( vec3(c.x,c.y,c.z) ), c.a);}
vec4   luvToXyz(vec4 c) {return vec4(   luvToXyz( vec3(c.x,c.y,c.z) ), c.a);}
vec4   luvToLch(vec4 c) {return vec4(   luvToLch( vec3(c.x,c.y,c.z) ), c.a);}
vec4   lchToLuv(vec4 c) {return vec4(   lchToLuv( vec3(c.x,c.y,c.z) ), c.a);}
vec4 hsluvToLch(vec4 c) {return vec4( hsluvToLch( vec3(c.x,c.y,c.z) ), c.a);}
vec4 lchToHsluv(vec4 c) {return vec4( lchToHsluv( vec3(c.x,c.y,c.z) ), c.a);}
vec4 hpluvToLch(vec4 c) {return vec4( hpluvToLch( vec3(c.x,c.y,c.z) ), c.a);}
vec4 lchToHpluv(vec4 c) {return vec4( lchToHpluv( vec3(c.x,c.y,c.z) ), c.a);}
vec4   lchToRgb(vec4 c) {return vec4(   lchToRgb( vec3(c.x,c.y,c.z) ), c.a);}
vec4   rgbToLch(vec4 c) {return vec4(   rgbToLch( vec3(c.x,c.y,c.z) ), c.a);}
vec4 hsluvToRgb(vec4 c) {return vec4( hsluvToRgb( vec3(c.x,c.y,c.z) ), c.a);}
vec4 rgbToHsluv(vec4 c) {return vec4( rgbToHsluv( vec3(c.x,c.y,c.z) ), c.a);}
vec4 hpluvToRgb(vec4 c) {return vec4( hpluvToRgb( vec3(c.x,c.y,c.z) ), c.a);}
vec4 rgbToHpluv(vec4 c) {return vec4( rgbToHpluv( vec3(c.x,c.y,c.z) ), c.a);}
vec4   luvToRgb(vec4 c) {return vec4(   luvToRgb( vec3(c.x,c.y,c.z) ), c.a);}
// allow 3 floats
vec3   xyzToRgb(float x, float y, float z) {return   xyzToRgb( vec3(x,y,z) );}
vec3   rgbToXyz(float x, float y, float z) {return   rgbToXyz( vec3(x,y,z) );}
vec3   xyzToLuv(float x, float y, float z) {return   xyzToLuv( vec3(x,y,z) );}
vec3   luvToXyz(float x, float y, float z) {return   luvToXyz( vec3(x,y,z) );}
vec3   luvToLch(float x, float y, float z) {return   luvToLch( vec3(x,y,z) );}
vec3   lchToLuv(float x, float y, float z) {return   lchToLuv( vec3(x,y,z) );}
vec3 hsluvToLch(float x, float y, float z) {return hsluvToLch( vec3(x,y,z) );}
vec3 lchToHsluv(float x, float y, float z) {return lchToHsluv( vec3(x,y,z) );}
vec3 hpluvToLch(float x, float y, float z) {return hpluvToLch( vec3(x,y,z) );}
vec3 lchToHpluv(float x, float y, float z) {return lchToHpluv( vec3(x,y,z) );}
vec3   lchToRgb(float x, float y, float z) {return   lchToRgb( vec3(x,y,z) );}
vec3   rgbToLch(float x, float y, float z) {return   rgbToLch( vec3(x,y,z) );}
vec3 hsluvToRgb(float x, float y, float z) {return hsluvToRgb( vec3(x,y,z) );}
vec3 rgbToHsluv(float x, float y, float z) {return rgbToHsluv( vec3(x,y,z) );}
vec3 hpluvToRgb(float x, float y, float z) {return hpluvToRgb( vec3(x,y,z) );}
vec3 rgbToHpluv(float x, float y, float z) {return rgbToHpluv( vec3(x,y,z) );}
vec3   luvToRgb(float x, float y, float z) {return   luvToRgb( vec3(x,y,z) );}
// allow 4 floats
vec4   xyzToRgb(float x, float y, float z, float a) {return   xyzToRgb( vec4(x,y,z,a) );}
vec4   rgbToXyz(float x, float y, float z, float a) {return   rgbToXyz( vec4(x,y,z,a) );}
vec4   xyzToLuv(float x, float y, float z, float a) {return   xyzToLuv( vec4(x,y,z,a) );}
vec4   luvToXyz(float x, float y, float z, float a) {return   luvToXyz( vec4(x,y,z,a) );}
vec4   luvToLch(float x, float y, float z, float a) {return   luvToLch( vec4(x,y,z,a) );}
vec4   lchToLuv(float x, float y, float z, float a) {return   lchToLuv( vec4(x,y,z,a) );}
vec4 hsluvToLch(float x, float y, float z, float a) {return hsluvToLch( vec4(x,y,z,a) );}
vec4 lchToHsluv(float x, float y, float z, float a) {return lchToHsluv( vec4(x,y,z,a) );}
vec4 hpluvToLch(float x, float y, float z, float a) {return hpluvToLch( vec4(x,y,z,a) );}
vec4 lchToHpluv(float x, float y, float z, float a) {return lchToHpluv( vec4(x,y,z,a) );}
vec4   lchToRgb(float x, float y, float z, float a) {return   lchToRgb( vec4(x,y,z,a) );}
vec4   rgbToLch(float x, float y, float z, float a) {return   rgbToLch( vec4(x,y,z,a) );}
vec4 hsluvToRgb(float x, float y, float z, float a) {return hsluvToRgb( vec4(x,y,z,a) );}
vec4 rgbToHslul(float x, float y, float z, float a) {return rgbToHsluv( vec4(x,y,z,a) );}
vec4 hpluvToRgb(float x, float y, float z, float a) {return hpluvToRgb( vec4(x,y,z,a) );}
vec4 rgbToHpluv(float x, float y, float z, float a) {return rgbToHpluv( vec4(x,y,z,a) );}
vec4   luvToRgb(float x, float y, float z, float a) {return   luvToRgb( vec4(x,y,z,a) );}

/*
END HSLUV-GLSL
*/

float lerp_hue(float h1,float h2,float v )
{
	if (abs(h1-h2)>180){
		//loop around lerp (i.e. modular lerp)
			float v2=(h1-h2)*v+h1;
			if (v2<0){
				float a1=h2-h1;
				float a=((360-h2)*a1)/(h1-a1);
				float b=h2-a;
				v2=(a)*(v)+b;
			}
			return v2;
		}
	else
		return mix(h1,h2,v);
}
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec4 mix_hsl(vec4 c1,vec4 c2,float v)
{
	//vec3 c1hsv=rgbToHsluv(c1.xyz);
	//vec3 c2hsv=rgbToHsluv(c2.xyz);
	vec3 c1hsv=rgbToHpluv(c1.xyz);
	vec3 c2hsv=rgbToHpluv(c2.xyz);
	

	vec3 ret;
	ret.x=lerp_hue(c1hsv.x,c2hsv.x,v);
	ret.yz=mix(c1hsv.yz,c2hsv.yz,v);
	float a=mix(c1.a,c2.a,v);
	return vec4(hpluvToRgb(ret.xyz),a);
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    //normed=normed/zoom+translate;
    float turn_around_actual=turn_around;
    //turn_around_actual*=normed.x;
    vec4 pixel=texture(tex_main,normed);
    //float v=log(pixel.x+1);
    float v=pow(abs(pixel.x)/turn_around_actual,1);
    //float v=pixel.x/turn_around_actual;
    //float v=gain(pixel.x/turn_around_actual,-0.8);
    //v=noise(pos.xy*rez/100);
    float select_color=0;
    if(pixel.x<0)
        select_color=1;

    vec4 c1=mix(color_fore,color_turn_around,select_color);
    vec4 c2=mix(color_fore,color_turn_around,select_color);
    vec4 c3=mix(color_turn_around,color_fore,select_color);
    ///*
    if(v<1)
    	color=mix(color_back,c1,v);
    else
    	color=mix(c2,c3,clamp((v-1)*1,0,1));
	//*/
    /*
    if(v<1)
    	color=mix_hsl(color_back,color_fore,v);
    else
    	color=mix_hsl(color_fore,color_turn_around,clamp((v-1)*1,0,1));
    //*/

    /*if(v<1)
    	color=vec4(palette(v,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.5,2.5,1.5),vec3(0.5,1.5,1.0)),1);
    else
    {
    	float tv=clamp((v-1),0,1);
    	color=vec4(palette(tv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.0,0.5,2.5),vec3(0.5,1.5,1.0)),1);
    }*/
}
]==]
local agent_logic_shader_fbk=shaders.Make(
[==[

#version 330
#line 388
layout(location = 0) in vec4 position;
out vec4 state_out;

uniform sampler2D tex_main;  //signal buffer state
uniform sampler2D background;
uniform vec2 background_swing;

uniform vec2 rez;

//agent settings uniforms
uniform float ag_sensor_distance;
uniform float ag_sensor_angle;
uniform float ag_turn_angle;
uniform float ag_step_size;
uniform float ag_turn_around;
uniform float ag_turn_avoid;
uniform float ag_clumpiness;
//
//float rand(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x))));}

#define M_PI 3.1415926535897932384626433832795
float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise(vec2 p){
	vec2 ip = floor(p);
	vec2 u = fract(p);
	u = u*u*(3.0-2.0*u);
	
	float res = mix(
		mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
		mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
	return res*res;
}
float sample_heading(vec2 p,float h,float dist)
{
	p+=vec2(cos(h),sin(h))*dist;
	return texture(tex_main,p/rez).x;
}
#define TURNAROUND
float cubicPulse( float c, float w, float x )
{
    x = abs(x - c);
    if( x>w ) return 0.0;
    x /= w;
    return 1.0 - x*x*(3.0-2.0*x);
}
float expStep( float x, float k, float n )
{
    return exp( -k*pow(x,n) );
}
float sample_back(vec2 pos)
{
	//return (log(texture(background,pos).x+1)-background_swing.x)/(background_swing.y-background_swing.x);
	return clamp(texture(background,pos).x,0,1);
}
float random_normed(vec3 state)
{
    return rand(state.xy*state.z*794347+state.xy*45721+vec2(7.5,2.813));
}
void main(){
	float step_size=ag_step_size;
	float sensor_distance=ag_sensor_distance;
	float sensor_angle=ag_sensor_angle;
	float turn_size=ag_turn_angle*sensor_angle;
	float turn_size_neg=ag_turn_avoid*sensor_angle;
	float turn_around=ag_turn_around;
    float clumpiness=ag_clumpiness;

	vec3 state=position.xyz;
    float type=position.w;

	vec2 normed_state=state.xy/rez;
	vec2 normed_p=(normed_state)*2-vec2(1,1);
	float tex_sample=sample_back(normed_state);//cubicPulse(0.6,0.3,abs(normed_p.x));//;

	float pl=length(normed_p);
    //sensor_distance*=clamp(0.2,1,(pl/2));
	//sensor_distance*=(1-tex_sample)*0.9+0.1;
	//sensor_distance*=normed_state.x;

	//sensor_distance*=1-cubicPulse(0.1,0.5,abs(normed_p.x));
	//sensor_distance=clamp(sensor_distance,2,15);

	//turn_around*=noise(state.xy/100);
	//turn_around-=cubicPulse(0.6,0.3,abs(normed_p.x));
	//turn_around*=tex_sample*0.3+0.7;
    //turn_around*=normed_state.x;
    //clumpiness*=abs(normed_p.x*10)+0.3;
    clumpiness*=clamp(1-pl*pl,0.3,10);
	//clamp(turn_around,0.2,5);
	//figure out new heading
	//sensor_angle*=(1-tex_sample)*.9+.1;
	//turn_size*=tex_sample*.9+0.1;
	//turn_size_neg*=tex_sample*.9+0.1;

	float head=state.z;
	float fow=abs(sample_heading(state.xy,head,sensor_distance));

	float lft=abs(sample_heading(state.xy,head-sensor_angle,sensor_distance));
	float rgt=abs(sample_heading(state.xy,head+sensor_angle,sensor_distance));

	if(fow<lft && fow<rgt)
	{
		head+=(random_normed(state)-0.5)*2*turn_size;

	}
	else if(rgt>fow)
	{
		//float ov=(rgt-fow)/fow;
	#ifdef TURNAROUND
		if(rgt>=turn_around)
			//step_size*=-1;
			head+=turn_size_neg;
		else
	#endif
			head+=turn_size;
	}
	else if(lft>fow)
	{
		//float ov=(lft-fow)/fow;
	#ifdef TURNAROUND
		if(lft>=turn_around)
			//step_size*=-1;
			head-=turn_size_neg;
		else
	#endif
			head-=turn_size;
	}
	#ifdef TURNAROUND
	else 
	#endif
	if(fow>turn_around)
	{
		//head+=(rand(position.xy*position.z*9999+state.xy*4572)-0.5)*turn_size*2;
		//head+=M_PI;//turn_size*2;//(rand(position.xy+state.xy*4572)-0.5)*turn_size*2;
		//step_size*=-1;
		//head+=random_normed(state)*turn_size_neg/2;
		head+=turn_size_neg;

	}
	//step_size/=clamp(rgt/lft,0.5,2);
	if(fow<=turn_around*2)
	{
		step_size*=1-clamp(fow/clumpiness,0.0,1-0.01);
	}

	/* turn head to center somewhat (really stupid way of doing it...)
	vec2 c=rez/2;
	vec2 d_c=(c-state.xy);
	d_c*=1/sqrt(dot(d_c,d_c));
	vec2 nh=vec2(cos(head),sin(head));
	float T_c=tex_sample*0.005;
	vec2 new_h=d_c*T_c+nh*(1-T_c);
	new_h*=1/sqrt(dot(new_h,new_h));
	head=atan(new_h.y,new_h.x);
	//*/
	//step_size*=1-clamp(cubicPulse(0,0.1,fow),0,1);
    
    //float diff=abs(fow-lft)+abs(fow-rgt)+abs(rgt-lft);
    //float diff=fow/turn_around;
    //float diff=abs(rgt-lft)/fow;
    float center=abs(sample_heading(state.xy,0,0));
    //float diff=fow/center;
    float diff=abs(center-fow)/fow;
    //diff*=0.333333333333;
    //if(fow<turn_around*1.2)
        //step_size*=1-clamp(diff/clumpiness,0.0,1);
	//step_size*=1-cubicPulse(0,0.4,abs(pl))*0.5;
	//step_size*=(clamp(fow/turn_around,0,1))*0.95+0.05;
	//step_size*=noise(state.xy/100);
	//step_size*=expStep(abs(pl-0.2),1,2);
	//step_size*=tex_sample*0.5+0.5;
    //step_size*=normed_state.y;
	//step_size=clamp(step_size,0.001,100);

	//step in heading direction
	state.xy+=vec2(cos(head)*step_size,sin(head)*step_size);
	state.z=head;
	state.xy=mod(state.xy,rez);
	state_out=vec4(state.xyz,type);

}
]==]
,[===[
void main()
{

}
]===],"state_out")

function do_agent_logic_fbk(  )

	agent_logic_shader_fbk:use()

    tex_pixel:use(0)
    agent_logic_shader_fbk:set_i("tex_main",0)
	if background_tex~=nil then
	    background_tex.t:use(1)
	    agent_logic_shader_fbk:set_i("background",1)
	    agent_logic_shader_fbk:set("background_swing",background_minmax[1],background_minmax[2])
	end
	agent_logic_shader_fbk:set("ag_sensor_distance",config.ag_sensor_distance)
	agent_logic_shader_fbk:set("ag_sensor_angle",config.ag_sensor_angle)
	agent_logic_shader_fbk:set("ag_turn_angle",config.ag_turn_angle)
	agent_logic_shader_fbk:set("ag_step_size",config.ag_step_size)
	agent_logic_shader_fbk:set("ag_turn_around",config.turn_around)
	agent_logic_shader_fbk:set("ag_turn_avoid",config.ag_turn_avoid)
    agent_logic_shader_fbk:set("ag_clumpiness",config.ag_clumpiness)
	agent_logic_shader_fbk:set("rez",map_w,map_h)

	agent_logic_shader_fbk:raster_discard(true)
	local ao=agent_buffers:get_other()
	ao:use()
	ao:bind_to_feedback()

	local ac=agent_buffers:get_current()
	ac:use()
	agent_logic_shader_fbk:draw_points(0,agent_count,4,1)
	__flush_gl()
	agent_logic_shader_fbk:raster_discard(false)
	--__read_feedback(agent_data.d,agent_count*agent_count*4*4)
	--print(agent_data:get(0,0).r)
	agent_buffers:flip()
	__unbind_buffer()
end
function agents_tocpu()
	--tex_agent:use(0)
	--agent_data:read_texture(tex_agent)
	agent_buffers:get_current():use()
	agent_buffers:get_current():get(agent_data.d,agent_count*4*4)
end
function agents_togpu()
	--tex_agent:use(0)
	--agent_data:write_texture(tex_agent)

	agent_buffers:get_current():use()
	agent_buffers:get_current():set(agent_data.d,agent_count*4*4)
	__unbind_buffer()
end
function fill_buffer(  )
	tex_pixel:use(0)
	signal_buf:read_texture(tex_pixel)
	for i=0,map_w-1 do
    	for j=0,map_h-1 do
    		signal_buf:set(math.floor(i),math.floor(j),math.random()*0.1)
    	end
    end
    signal_buf:write_texture(tex_pixel)
end
function agents_step_fbk(  )

	do_agent_logic_fbk()
	add_trails_fbk()

end
function diffuse_and_decay(  )
	if tex_pixel_alt==nil or is_remade then
		tex_pixel_alt=textures:Make()
		tex_pixel_alt:use(1)
		tex_pixel_alt:set(signal_buf.w,signal_buf.h,2)
		is_remade=false
	end
	decay_diffuse_shader:use()
    tex_pixel:use(0)
    --tex_pixel.t:set(size[1]*oversample,size[2]*oversample,3)
    decay_diffuse_shader:set_i("tex_main",0)
    decay_diffuse_shader:set("decay",config.decay)
    decay_diffuse_shader:set("diffuse",0.5)
    if not tex_pixel_alt:render_to(signal_buf.w,signal_buf.h) then
		error("failed to set framebuffer up")
	end
    decay_diffuse_shader:draw_quad()
    __render_to_window()
    local t=tex_pixel_alt
    tex_pixel_alt=tex_pixel
    tex_pixel=t
end
function save_img(  )
	img_buf=img_buf or make_image_buffer(win_w,win_h)
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    config_serial=config_serial..serialize_config(config)
    --print(config_serial)
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function rnd( v )
	return math.random()*v*2-v
end
function update()
    __clear()
    __no_redraw()
    __render_to_window()

    imgui.Begin("slimemold")
    draw_config(config)
    if imgui.Button("Save") then
        need_save=true
    end
    imgui.SameLine()
    if imgui.Button("Fill") then
    	fill_buffer()
    end
     imgui.SameLine()
    if imgui.Button("Clear") then
    	tex_pixel:use(0)
		--signal_buf:read_texture(tex_pixel)
		for x=0,signal_buf.w-1 do
		for y=0,signal_buf.h-1 do
			signal_buf:set(x,y,0)
		end
		end
		signal_buf:write_texture(tex_pixel)
    end
    imgui.SameLine()
    if imgui.Button("Agentswarm") then
    	for i=0,agent_count-1 do
    		-- [[
    		agent_data:set(i,0,
    			{math.random(0,map_w-1),
    			 math.random(0,math.floor((map_h-1)/2)),
    			 math.random()*math.pi*2,
    			 0})
    		--]]
    		--[[
    		local r=math.sqrt(math.random())*map_w/8
    		local phi=math.random()*math.pi*2
    		agent_data:set(i,0,
    			{math.cos(phi)*r+map_w/2,
    			 math.sin(phi)*r+map_h/2,
    			 math.random()*math.pi*2,
    			 0})
    		--]]
    		--[[
    		local a = math.random() * 2 * math.pi
			local r = map_w/8 * math.sqrt(math.random())
			local x = r * math.cos(a)
			local y = r * math.sin(a)

            local w=1
            if math.fmod(ra*3,1)>0.5 then
                w=-1
            end
			agent_data:set(i,0,
    			{math.cos(a)*r+map_w/2,
    			 math.sin(a)*r+map_h/2,
    			 a+(math.pi/2)+math.random()*math.pi/2,
    			w})
    		--]]
    		--[[
    		local side=math.random(1,4)
    		local x,y
    		if side==1 then
    			x=math.random()*map_w
    			y=0
    		elseif side==2 then
    			x=math.random()*map_w
    			y=map_h-1
			elseif side==3 then
    			x=map_w-1
				y=math.random()*map_h
			else
				x=0
				y=math.random()*map_h
			end
			--local d=math.sqrt(x*x+y*y)
			local a=math.atan(y-map_h/2,x-map_w/2)
			agent_data:set(i,0,
    			{x,
    			 y,
    			 a+math.pi,
    			 0})
			--]]
    	end
    	agents_togpu()
    end
    imgui.SameLine()
    if imgui.Button("ReloadBuffer") then
		background_tex=nil
		make_background_texture()
	end
    imgui.End()
    -- [[
    if not config.pause then
        --agents_step()
        agents_step_fbk()
        for i=1,5 do
            diffuse_and_decay()
        end
    end
    --if config.draw then
    --if false then
    draw_shader:use()
    tex_pixel:use(0)

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("rez",map_w,map_h)
    draw_shader:set("turn_around",config.turn_around)
    draw_shader:set("color_back",config.color_back[1],config.color_back[2],config.color_back[3],config.color_back[4])
    draw_shader:set("color_fore",config.color_fore[1],config.color_fore[2],config.color_fore[3],config.color_fore[4])
    draw_shader:set("color_turn_around",config.color_turn_around[1],config.color_turn_around[2],config.color_turn_around[3],config.color_turn_around[4])
    --draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
    --draw_shader:set("translate",config.t_x,config.t_y)
    --draw_shader:set("sun_color",config.color[1],config.color[2],config.color[3],config.color[4])
    draw_shader:draw_quad()
    --end

    if need_save then
        save_img()
        need_save=false
    end

end
