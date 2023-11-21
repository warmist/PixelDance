require "common"
require "splines"
--basically implementing: http://hplgit.github.io/num-methods-for-PDEs/doc/pub/wave/html/._wave006.html
-- more resource: https://www.nature.com/articles/s41598-018-29244-6
--[[
	TODO:
		actually implement dx/dy that would help with bogus units problem
			-maybe only aspect ratio?
		* https://en.wikipedia.org/wiki/Daxophone#/media/File:DaxoTongues.jpg
		* sound output
		* bowstring input
		* add variance display/accumulation
		* thin film interference
--]]
local size_mult
local oversample=1
local win_w
local win_h
local aspect_ratio
function update_size( w,h )
	if w~= win_w or h~=win_h then
		win_w=1280*size_mult
		win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
		aspect_ratio=win_w/win_h
		__set_window_size(win_w,win_h)
	end
end
--update_size()
local bwrite = require "blobwriter"
local bread = require "blobreader"

--[[
	local b=bwrite()
	b:u32(visit_buf.w)
	b:u32(visit_buf.h)
	b:u32(4)--channels
	b:u32(0)--do log norm
	b:f32(min[1])
	b:f32(min[2])
	b:f32(min[3])
	b:f32(max[1])
	b:f32(max[2])
	b:f32(max[3])
	b:f32(avg)
	for x=0,visit_buf.w-1 do
	for y=0,visit_buf.h-1 do
		local v=visit_buf:get(x,y)
		b:f32(v.r)
		b:f32(v.g)
		b:f32(v.b)
		b:f32(v.a)
	end
	end
	local f=io.open(name,"wb")
	f:write(b:tostring())
	f:close()
	]]

function gain( x, k)
	local b=x
	if x>=0.5 then
		x=1.0-x
	end
	local a = 0.5*math.pow(2.0*b, k);
	if x<0.5 then
		return a
	else
		return 1.0-a
	end
end
local apply_norm_stuff_on_save=true
function buffer_save(buf,min,max, name )
	local b=bwrite()
	b:u32(buf.w)
	b:u32(buf.h)
	b:u32(1)
	b:u32(0)
	b:f32(min)
	b:f32(max)
	b:f32((max+min)/2)
	for x=0,buf.w-1 do
	for y=0,buf.h-1 do
		local v=buf:get(x,y)
		if apply_norm_stuff_on_save then
			local normed=(v-min)/(max-min)
			normed=gain(normed,config.gain);
			normed=math.pow(normed,config.gamma);
			b:f32(normed)
		else
			b:f32(v)
		end
	end
	end
	local f=io.open(name,"wb")
	f:write(b:tostring())
	f:close()
end
function read_visits_buf( fname )
	local file = io.open(fname, 'rb')
	local b = bread(file:read('*all'))
	file:close()

	local sx=b:u32()
	local sy=b:u32()
	visit_buf=make_float_buffer(sx,sy)
	visits_minmax={}
	visits_minmax[1]=b:f32()
	visits_minmax[2]=b:f32()
	for x=0,visit_buf.w-1 do
	for y=0,visit_buf.h-1 do
		local v=visit_buf:set(x,y,b:f32())
	end
	end
end
local force_reload_image=true
mask_file=mask_file or "saved_1699854183.png"
function make_visits_texture()
	--[[
	if visit_tex==nil then
		print("making tex")
		read_visits_buf("out.buf")
		visit_tex={t=textures:Make(),w=visit_buf.w,h=visit_buf.h}
		visit_tex.t:use(0,1)
		visit_buf:write_texture(visit_tex.t)
	end
	--]]
	if force_reload_image or visit_tex==nil then
		local image_mask=load_png(mask_file)
		visit_tex={t=textures:Make(),w=image_mask.w,h=image_mask.h}
		visit_tex.t:use(0,1)
		image_mask:write_texture(visit_tex.t)
 	end
end
make_visits_texture()

local size=STATE.size
img_buf=make_image_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	print("new size:",w,h)
end


texture_buffers=texture_buffers or {}
function make_sand_buffer()
	print("making sand tex")
	local t={t=textures:Make(),w=size[1]*oversample,h=size[2]*oversample}
	t.t:use(0,1)
	t.t:set(size[1]*oversample,size[2]*oversample,2)
	texture_buffers.sand=t
end
NUM_BUFFERS=3
function make_textures()
	if #texture_buffers==0 or
		texture_buffers[1].w~=size[1]*oversample or
		texture_buffers[1].h~=size[2]*oversample then
		
		for i=1,NUM_BUFFERS do
			print("making tex",i)
			local t={t=textures:Make(),w=size[1]*oversample,h=size[2]*oversample}
			t.t:use(0,1)
			t.t:set(size[1]*oversample,size[2]*oversample,2)
			texture_buffers[i]=t
		end
		make_sand_buffer()
	end
end
make_textures()

function make_io_buffer(  )
	if io_buffer==nil or io_buffer.w~=size[1]*oversample or io_buffer.h~=size[2]*oversample then
		io_buffer=make_float_buffer(size[1]*oversample,size[2]*oversample)
	end
end

make_io_buffer()

config=make_config({
	{"pause",false,type="boolean"},
	{"dt",1,type="float",min=0.001,max=2},
	{"freq",0.5,type="float",min=0,max=1},
	{"freq2",0.5,type="float",min=0,max=1},
	{"decay1",0.00001,type="floatsci",min=0,max=0.01,power=10},
	{"decay2",0.00001,type="floatsci",min=0,max=0.01,power=10},
	{"decay3",0.00001,type="floatsci",min=0,max=0.01,power=10},
	{"decay4",0.00001,type="floatsci",min=0,max=0.01,power=10},
	{"n",1,type="int",min=0,max=15},
	{"m",1,type="int",min=0,max=15},
	{"a",1,type="float",min=-1,max=1},
	{"b",1,type="float",min=-1,max=1},
	{"color",{124/255,50/255,30/255},type="color"},
	{"monotone",false,type="boolean"},
	{"gamma",1,type="float",min=0.01,max=5},
	{"gain",1,type="float",min=-5,max=5},
	{"draw",true,type="boolean"},
	{"accumulate",false,type="boolean"},
	{"size_mult",true,type="boolean"},
	{"draw_form",false,type="boolean"},
},config)


add_shader=shaders.Make[==[
#version 330
#line __LINE__

out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float mult;

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float lv=texture(values,normed).x*mult;
	lv=abs(lv);
	//lv=1-exp(-lv*lv/1);
	//lv*=lv;
	color=vec4(lv,lv,lv,1);
}
]==]
draw_shader=shaders.Make[==[
#version 330
#line __LINE__

out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float mult;
uniform float add;
uniform float v_gamma;
uniform float v_gain;
uniform vec3 mid_color;
uniform int monotone;
#define M_PI 3.14159265358979323846264338327950288
float f(float v)
{
#if LOG_MODE
	return log(v+1);
#else
	return v;
#endif
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec3 isoline_color (in float d) {
    vec3 col = vec3(1.0) - sign(d)*vec3(0.1,0.4,0.7);
    col *= 1.0 - exp(-3.0*abs(d));
    float c = cos(150.0*d);
    col *= 0.8 + 0.2*c*c*c;
    col = mix( col, vec3(1.0), 1.0-smoothstep(0.0,0.01,abs(d)) );
    return col;
  }
//#define RG
void main(){

	vec2 normed=(pos.xy+vec2(1,1))/2;
#ifdef RG
	float lv=(texture(values,normed).x+add)*mult;
	if (lv>0)
		{
			lv=f(lv);
			lv=pow(lv,gamma);
			color=vec4(lv,0,0,1);
		}
	else
		{
			lv=f(-lv);
			lv=pow(lv,gamma);
			color=vec4(0,0,lv,1);
		}
#else
	float lv=f(abs(texture(values,normed).x+add))*mult;
	//float lv=f(abs(log(texture(values,normed).x+1)+add))*mult;
	//lv=pow(1-lv,gamma);
	lv=gain(lv,v_gain);
	lv=pow(lv,v_gamma);
	/* quantize
	float q=7;
	lv=clamp(floor(lv*q)/q,0,1);
	//*/
	//color.xyz=vec3(lv);
	//color.xyz=isoline_color((lv-0.5)*2);
	//color=vec4(palette(lv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.0,3.0,3.0),vec3(3.5,2.5,1.5)),1);
	if(monotone==1)
		color=vec4(vec3(lv),1);
	else
		color=vec4(palette(lv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.0,1.0,1.0),vec3(0.3,0.2,0.2)+vec3(0.2)),1);
	color.a=1;
	vec3 col_back=vec3(0);
	vec3 col_top=vec3(1);
	float break_pos=0.5;
	float break_inv=1/break_pos;
	/* color with a down to dark break
	//lv=1-lv;
	if(lv>break_pos)
		color.xyz=mix(col_back,col_top,(lv-break_pos)/(1-break_pos));
	else
	{
		float nv=sin(lv*break_inv*M_PI);
		color.xyz=mix(col_back,mid_color,nv);
	}
	//*/
	
	/* continuous color
	if(lv>break_pos)
	{
		color.xyz=mix(mid_color,col_top,(lv-break_pos)/(1-break_pos));
	}
	else
	{
		color.xyz=mix(col_back,mid_color,lv*break_inv);
	}
	//*/

#endif
}
]==]
solver_shader=shaders.Make[==[
#version 330
#line __LINE__

out vec4 color;
in vec3 pos;
uniform sampler2D values[4];

uniform sampler2D input_map;
uniform vec2 input_map_swing;
uniform vec4 source_pos;
uniform float v_gamma;
uniform float v_gain;

uniform float init;
uniform float dt;
uniform float c_const;
uniform float time;
uniform vec4 decay;
uniform float freq;
uniform float freq2;
uniform vec2 tex_size;
uniform vec2 nm_vec;
uniform vec2 ab_vec;
//uniform vec2 dpos;
uniform int draw_form;

#define M_PI 3.14159265358979323846264338327950288
//randoms
float nrand( vec2 n )
{
	return fract(sin(dot(n.xy, vec2(12.9898, 78.233)))* 43758.5453);
}
//note: remaps v to [0;1] in interval [a;b]
float remap( float a, float b, float v )
{
	return clamp( (v-a) / (b-a), 0.0, 1.0 );
}
//note: quantizes in l levels
float truncate( float a, float l )
{
	return floor(a*l)/l;
}

float n1rand( vec2 n )
{
	float t = fract( time );
	float nrnd0 = nrand( n + 0.07*t );
	return nrnd0;
}
float n2rand( vec2 n )
{
	float t = fract( time );
	float nrnd0 = nrand( n + 0.07*t );
	float nrnd1 = nrand( n + 0.11*t );
	return (nrnd0+nrnd1) / 2.0;
}

float n2rand_faster( vec2 n )
{
	float t = fract( time );
	float nrnd0 = nrand( n + 0.07*t );

    // Convert uniform distribution into triangle-shaped distribution.
    float orig = nrnd0*2.0-1.0;
    nrnd0 = orig*inversesqrt(abs(orig));
    nrnd0 = max(-1.0,nrnd0); // Nerf the NaN generated by 0*rsqrt(0). Thanks @FioraAeterna!
    nrnd0 = nrnd0-sign(orig)+0.5;
    
    // Result is range [-0.5,1.5] which is
    // useful for actual dithering.
    // convert to [0,1] for histogram.
    return (nrnd0+0.5) * 0.5;
}
float n3rand( vec2 n )
{
	float t = fract( time );
	float nrnd0 = nrand( n + 0.07*t );
	float nrnd1 = nrand( n + 0.11*t );
	float nrnd2 = nrand( n + 0.13*t );
	return (nrnd0+nrnd1+nrnd2) / 3.0;
}
float n4rand( vec2 n )
{
	float t = fract( time );
	float nrnd0 = nrand( n + 0.07*t );
	float nrnd1 = nrand( n + 0.11*t );	
	float nrnd2 = nrand( n + 0.13*t );
	float nrnd3 = nrand( n + 0.17*t );
	return (nrnd0+nrnd1+nrnd2+nrnd3) / 4.0;
}
float n4rand_inv( vec2 n )
{
	float t = fract( time );
	float nrnd0 = nrand( n + 0.07*t );
	float nrnd1 = nrand( n + 0.11*t );	
	float nrnd2 = nrand( n + 0.13*t );
	float nrnd3 = nrand( n + 0.17*t );
    float nrnd4 = nrand( n + 0.19*t );
	float v1 = (nrnd0+nrnd1+nrnd2+nrnd3) / 4.0;
    float v2 = 0.5 * remap( 0.0, 0.5, v1 ) + 0.5;
    float v3 = 0.5 * remap( 0.5, 1.0, v1 );
    return (nrnd4<0.5) ? v2 : v3;
}
//sdfs
float sdCircle( vec2 p, float r )
{
  return length(p) - r;
}
float sdCircle2( vec2 p, float r )
{
	float a=(atan(p.y,p.x)+M_PI)/(2*M_PI);
	a*=8;
	a=abs(mod(a,1)-0.5);
  	return length(p) - r*(0.6+a*0.4);
}
float sdBox( in vec2 p, in vec2 b )
{
    vec2 d = abs(p)-b;
    return length(max(d,vec2(0))) + min(max(d.x,d.y),0.0);
}
float sdEquilateralTriangle( in vec2 p )
{
    const float k = sqrt(3.0);
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0/k;
    if( p.x+k*p.y>0.0 ) p = vec2(p.x-k*p.y,-k*p.x-p.y)/2.0;
    p.x -= clamp( p.x, -2.0, 0.0 );
    return -length(p)*sign(p.y);
}
float sdTriangle( in vec2 p, in vec2 p0, in vec2 p1, in vec2 p2 )
{
    vec2 e0 = p1-p0, e1 = p2-p1, e2 = p0-p2;
    vec2 v0 = p -p0, v1 = p -p1, v2 = p -p2;
    vec2 pq0 = v0 - e0*clamp( dot(v0,e0)/dot(e0,e0), 0.0, 1.0 );
    vec2 pq1 = v1 - e1*clamp( dot(v1,e1)/dot(e1,e1), 0.0, 1.0 );
    vec2 pq2 = v2 - e2*clamp( dot(v2,e2)/dot(e2,e2), 0.0, 1.0 );
    float s = sign( e0.x*e2.y - e0.y*e2.x );
    vec2 d = min(min(vec2(dot(pq0,pq0), s*(v0.x*e0.y-v0.y*e0.x)),
                     vec2(dot(pq1,pq1), s*(v1.x*e1.y-v1.y*e1.x))),
                     vec2(dot(pq2,pq2), s*(v2.x*e2.y-v2.y*e2.x)));
    return -sqrt(d.x)*sign(d.y);
}
float sdPoly2(in vec2 st,in float num,in float size,in float rot)
{
	float a=atan(st.x,st.y)+rot;
	float b=6.28319/num;
	return cos(floor(0.5+a/b)*b-a)*length(st.xy);
}
float sdStar(in vec2 p, in float r, in int n, in float m)
{
    // next 4 lines can be precomputed for a given shape
    float an = 3.141593/float(n);
    float en = 3.141593/m;  // m is between 2 and n
    vec2  acs = vec2(cos(an),sin(an));
    vec2  ecs = vec2(cos(en),sin(en)); // ecs=vec2(0,1) for regular polygon,

    float bn = mod(atan(p.x,p.y),2.0*an) - an;
    p = length(p)*vec2(cos(bn),abs(sin(bn)));
    p -= r*acs;
    p += ecs*clamp( -dot(p,ecs), 0.0, r*acs.y/ecs.y);
    return length(p)*sign(p.x);
}
float sdPoly(in vec2 p, in float r, in int n)
{
    // next 4 lines can be precomputed for a given shape
    float an = 3.141593/float(n);
    vec2  acs = vec2(cos(an),sin(an));
    vec2 ecs=vec2(0,1);

    float bn = mod(atan(p.x,p.y),2.0*an) - an;
    p = length(p)*vec2(cos(bn),abs(sin(bn)));
    p -= r*acs;
    p += ecs*clamp( -dot(p,ecs), 0.0, r*acs.y/ecs.y);
    return length(p)*sign(p.x);
}
//sdops
float opUnion( float d1, float d2 ) {  return min(d1,d2); }

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

float opIntersection( float d1, float d2 ) { return max(d1,d2); }

float opSmoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float opSmoothIntersection( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h); }

//shapes

float sh_circle(in vec2 st,in float rad,in float fw)
{
	return 1-smoothstep(rad-fw*0.75,rad+fw*0.75,dot(st,st)*4);
}
float sh_ring(in vec2 st,in float rad1,in float rad2,in float fw)
{
	return sh_circle(st,rad1,fw)-sh_circle(st,rad2,fw);
}
float sh_polyhedron(in vec2 st,in float num,in float size,in float rot,in float fw)
{
	float a=atan(st.x,st.y)+rot;
	float b=6.28319/num;
	return 1-(smoothstep(size-fw,size+fw, cos(floor(0.5+a/b)*b-a)*length(st.xy)));
}
void t_rot(inout vec2 st,float angle)
{
	float c=cos(angle);
	float s=sin(angle);
	mat2 m=mat2(c,-s,s,c);
	st*=m;
}
void t_ref(inout vec2 st,float angle)
{
	float c=cos(2*angle);
	float s=sin(2*angle);
	mat2 m=mat2(c,s,s,-c);
	st*=m;
}
float flower(in vec2 st,float fw)
{
	float size=0.15;
	st-=vec2(0.15,0.15);
	vec2 off=vec2(0.0,0.2);
	float ret=0;
	for(int i=0;i<6;i++)
	{
		st=st+off;
		t_rot(st,(M_PI/6)*2);
		ret=max(ret,sh_polyhedron(st*vec2(1,0.3),5,size,M_PI,fw*0.1));
	}
	return ret;
}
float dagger(in vec2 st,float fw)
{
	float v=sh_polyhedron(st*vec2(0.4,0.5)+vec2(0,0.122),3,0.1,0,fw/2);
	v=max(v,sh_polyhedron(st+vec2(0,-0.2),3,0.25,M_PI/3,fw));
	return v;
}
float leaf(in vec2 st,float fw)
{
	float size=0.35;
	float x_dist=(size*sqrt(2)/2)*1.8;
	float y_dist=size;
	float v=sh_polyhedron(st*vec2(1,0.6),4,size,M_PI/4,fw/2);
	v=max(v-sh_circle(st+vec2(x_dist,y_dist),x_dist,fw/2),0);
	v=max(v-sh_circle(st+vec2(-x_dist,y_dist),x_dist,fw/2),0);
	return v;
}
float chalice(in vec2 st,float fw)
{
	float ret=max(leaf(st,fw)-sh_circle(st+vec2(0,-0.4),0.8,fw),0);
	ret=max(ret,sh_circle(st+vec2(0,-0.2),0.35,fw));
	return ret;
}
float sh_wavy(in vec2 st,float rad)
{
	float a=atan(st.y,st.x);
	float r=length(st);
	return 1-smoothstep(rad-0.01,rad+0.01,r+cos(a*7)*0.05);
}
float balance(in vec2 st,float fw)
{
	int count=6;
	float ret=sh_polyhedron(st,count,0.5,0,fw);
	for(int i=0;i<count/2;i++)
	{
		float ang=(i/float(count))*M_PI*4+M_PI/2;
		ret=max(ret-sh_circle(st+vec2(cos(ang),sin(ang))*0.5,0.35,fw),0);
	}
	return ret;
}
float sh_jaws(in vec2 st,float fw)
{
	float ret=sh_polyhedron(st,4,0.4,M_PI/4,fw);
	vec2 center=vec2(0,0.25);
	ret=max(ret-sh_circle(st-center,0.5,fw),0);
	ret=max(ret-sh_polyhedron(st+vec2(0,0.5),4,0.2,M_PI/4,fw),0);
	int count=4;
	float dist=0.35;
	float ang_offset=M_PI/count;
	for(int i=0;i<=count;i++)
	{
		float ang=(i/float(count))*(M_PI-ang_offset)+ang_offset/2;
		ret=max(ret,sh_polyhedron(st-center+vec2(cos(ang),sin(ang))*dist,3,0.04,ang*4,fw));
	}
	return ret;
}
float ankh(in vec2 st,float fw)
{
	float ring=sh_circle(st+vec2(0,-0.3),0.35,fw)-sh_circle(st+vec2(0,-0.3),0.2,fw);
	float ret=max(ring,0);
	float h1=sh_polyhedron(st*vec2(1.0,6)+vec2(0.2,0),3,0.2,M_PI/2,fw);
	float h2=sh_polyhedron(st*vec2(1.0,6)-vec2(0.2,0),3,0.2,-M_PI/2,fw);
	float d=sh_polyhedron(st*vec2(6.0,1)+vec2(0,0.4),4,0.4,0,fw);
	return max(max(ret,h1),max(d,h2));
}
float ankh_sdf(in vec2 st)
{
	float ring=abs(sdCircle(st+vec2(0,-0.3),0.25))-0.15/4;
	//float ring=abs(sdCircle(st+vec2(0,-0.3),0.275))-0.15/2;//-sdCircle(st+vec2(0,-0.3),0.2);
	//float ret=max(ring,0);
	float d=sdBox(st+vec2(0,0.35),vec2(0.07,0.4));
	t_rot(st,M_PI/2);
	float h1=sdEquilateralTriangle(st*vec2(15.0,4.0)+vec2(0.0,1));
	t_rot(st,-M_PI);
	float h2=sdEquilateralTriangle(st*vec2(15.0,4.0)+vec2(0.0,1));
	float v=opUnion(opUnion(ring,d),opUnion(h1,h2))-0.02;

	return step(v,0);//max(max(ret,h1),max(d,h2));
}
float holed_tri(in vec2 st)
{
	float ret=-sdEquilateralTriangle(st.xy/0.8);
	ret=opUnion(ret,sdCircle(st,0.1));

	return step(ret-0.05,0);
}
float damaged_circle2(in vec2 st)
{
	//sh_polyhedron(pos.xy,12,max_d,0,w)-sh_polyhedron(pos.xy,8,0.2,0,w)
	float ret=-sdPoly(st.xy,0.8,12);
	ret=opUnion(ret,sdPoly(st.xy,0.1,8));
	/*
	ret=opSubtraction(sdCircle(st+vec2(0.55,0),0.15),ret);
	ret=opSubtraction(sdCircle(st+vec2(-0.55,0),0.15),ret);
	ret=opSubtraction(sdCircle(st+vec2(0,0.55),0.15),ret);
	ret=opSubtraction(sdCircle(st+vec2(0,-0.55),0.15),ret);
	*/

	/*
	ret=opSubtraction(sdCircle(st+vec2(0.55,0.55),0.05),ret);
	ret=opSubtraction(sdCircle(st+vec2(-0.55,-0.55),0.05),ret);
	ret=opSubtraction(sdCircle(st+vec2(-0.55,0.55),0.05),ret);
	ret=opSubtraction(sdCircle(st+vec2(0.55,-0.55),0.05),ret);
	*/
	return step(ret-0.05,0);
}
float damaged_circle(in vec2 st)
{
	float ret=sdCircle(st,0.8);
	ret=opSubtraction(sdCircle(st+vec2(0.55,0),0.15),ret);
	ret=opSubtraction(sdCircle(st+vec2(-0.55,0),0.15),ret);
	ret=opSubtraction(sdCircle(st+vec2(0,0.55),0.15),ret);
	ret=opSubtraction(sdCircle(st+vec2(0,-0.55),0.15),ret);

	ret=opSubtraction(sdCircle(st+vec2(0.55,0.55),0.05),ret);
	ret=opSubtraction(sdCircle(st+vec2(-0.55,-0.55),0.05),ret);
	ret=opSubtraction(sdCircle(st+vec2(-0.55,0.55),0.05),ret);
	ret=opSubtraction(sdCircle(st+vec2(0.55,-0.55),0.05),ret);
	return step(ret,0);
}
float petals(in vec2 st, float fw)
{
	float ret=0;
	float ang=(M_PI/3.0);
	for(int i=0;i<6;i++)
	{
		//*float(i);
		vec2 v2=st;
		t_rot(v2,ang*float(i));
		v2-=vec2(0.25,0);
		v2*=vec2(0.5,1);
		//t_rot(v2,-ang*float(i));
		//v2/=vec2(0.5,1);
		//v2-=vec2(0.13,0);
		ret=max(sh_polyhedron(v2,6,0.1,0,0),ret);
	}
	return ret;
}
float slit_experiment(in vec2 st, float fw)
{
	float w=0.02;
	float l=0.005;
	float w_in=0.025;
	float ret=0;
	float s=sdBox(st,vec2(0.5,0.5));
	#if 1 //twoslits
	s=opSubtraction(sdBox(st+vec2(0,0.5+w+w_in),vec2(l,0.5)),s);
	s=opSubtraction(sdBox(st-vec2(0,0.5+w+w_in),vec2(l,0.5)),s);
	s=opSubtraction(sdBox(st,vec2(l,w_in)),s);
	#else //oneslit
	s=opSubtraction(sdBox(st+vec2(0,0.5+w/2),vec2(l,0.5)),s);
	s=opSubtraction(sdBox(st-vec2(0,0.5+w/2),vec2(l,0.5)),s);
	#endif
	return s;
}
float radial_shape(in vec2 st)
{
	float a=atan(st.y,st.x);
	float r=length(st)*1.5;
	float ret=((sin(a*4+r*8))*cos(r*6)+0.1+smoothstep(0.15,0.05,r))*step(r,1.2);
	return step(ret,0);
}
float grid(in vec2 st,float fw)
{
	st=mod(st,0.25)-vec2(0.125,0.125);
	st*=vec2(5,5);
	float r=leaf(st,fw);
	return r;
}

/*
float DX(int dx,int dy,vec2 normed)
{
	vec2 dtex=1/tex_size;
	vec2 pos=normed+vec2(dx,dy)*dtex;
	int rot=0;
	//p4 or p2 dont remember but tile with 4 tiles rotated
	if(pos.x>1)
	{
		pos=vec2(pos.y,-pos.x);
	}
	else if(pos.x<0)
	{
		pos=vec2(pos.y,-pos.x);
	}
	else if(pos.y>1)
	{
		pos=vec2(-pos.y,pos.x);
	}
	else if(pos.y<0)
	{
		pos=vec2(-pos.y,pos.x);
	}

	return texture(values_cur,pos).x;
}*/
float hash(float n) { return fract(sin(n) * 1e4); }
float hash(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x)))); }
//sound generating function or driving function
float func(vec2 pos)
{
	//if(length(pos)<0.0025 && time<100)
	//	return cos(time/freq)+cos(time/(2*freq/3))+cos(time/(3*freq/2));
	//vec2 pos_off=vec2(cos(time*0.001)*0.5,sin(time*0.001)*0.5);
	//if(sh_ring(pos,1.2,1.1,0.001)>0)
	float max_time=1000;
	float min_freq=1;
	float max_freq=5;
	float ang=atan(pos.y,pos.x);
	float rad=length(pos);
	float fr=freq;
	float fr2=freq2;
	float fn1=fr*M_PI/1000;
	float fn2=fr2*M_PI/1000;

	float max_a=7;
	float r=0.4;
	#if 1
		//if(time<max_time)
		if(length(pos+vec2(0.0,0.0))<0.1)
			return ab_vec.x*(fract(fn1*time)*2-1)
			+ab_vec.y*(fract(fn2*time)*2-1);
	#endif
	#if 0
		//if(time<max_time)
			//if(pos.x<-0.35)
				//return (hash(time*freq2)*hash(pos*freq))/2;
				//return ab_vec.x*n4rand(pos*fr2);
		float ret=0;
		float dist_val=99999;//
		const int MAX_P=4;
		for(int i=0;i<MAX_P;i++)
		{
			float a=M_PI*2*(float(i)/float(MAX_P));
			dist_val=min(dist_val,length(pos+vec2(cos(a),sin(a))*0.25));
		}
		float amp=1;
		float amp_scale=1/2;
		float freq_scale=1.5;
		if(time<max_time)
		if(dist_val<0.005)
			for(int i=1;i<4;i++)
			{
				ret+=amp*ab_vec.x*cos(time*fr)+ //+pos.x*hash(pos.y)
					 amp*ab_vec.y*cos(time*fr2); //+pos.y*hash(pos.x)
				amp=amp*amp_scale;
				fr=fr*freq_scale;
				fr2=fr2*freq_scale;
			}
		return ret/10;
	#endif
	#if 0
		if(time<max_time)
		if(pos.x+pos.y<-0.0)
			return (
		ab_vec.x*sin(fn1
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.x*M_PI*nm_vec.x)+
		ab_vec.y*sin(fn2
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.y*M_PI*nm_vec.y)
		);
	#endif
	#if 0
	for(float a=0;a<max_a;a++)
	{
		float ang=(a/max_a)*M_PI*2;

		vec2 dv=vec2(cos(ang)*r,sin(ang)*r);
		if(length(pos+dv)<0.005)
		if(time<max_time)
			return (
			ab_vec.x*sin(fn1*time+ang*nm_vec.x)
			+ab_vec.y*sin(fn2*time+ang*nm_vec.y)
			);
	}
	#endif
	#if 0
		vec2 normed=(pos.xy+vec2(1,1))/2;
		float val=texture(input_map,normed).x;

		val=(log(val+1)-input_map_swing.x)/(input_map_swing.y-input_map_swing.x);
		/*
		val=clamp(val,0,1);
		val=gain(val,v_gain);
		val=pow(val,vec4(v_gamma));
		*/
		return sin(time*fn1+val*fr2);
	#endif
	#if 0
	//if(time<max_time)
		return (
		ab_vec.x*sin(time*fn1
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.x*M_PI*nm_vec.x)+
		ab_vec.y*sin(time*fn2
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.y*M_PI*nm_vec.y)
		);
	#endif
	#if 0
		float r2=length(pos);
		float a2=atan(pos.y,pos.x);
	if(time<max_time)
		return (
		ab_vec.x*sin(time*fn1
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(r2*M_PI*nm_vec.x)+
		ab_vec.y*sin(time*fn2
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(a2*M_PI*nm_vec.y)
		);
	#endif
	#if 0


	vec2 p=vec2(cos(time*fr2*M_PI/1000),sin(time*fr2*M_PI/1000))*0.1;
	//if(time<max_time)
	if(abs(length(pos)-0.5)<0.005)
		return ab_vec.x*sin(-time*fr*M_PI/1000+ang*nm_vec.x+rad*nm_vec.y)+
			   ab_vec.y*sin(-time*fr2*M_PI/1000+ang*nm_vec.x+rad*nm_vec.y);
	//if(length(pos+vec2(0,0.5)+p)<0.005)
	//	return sin(time*fr2*M_PI/1000);


	#endif
	#if 0


	vec2 p=vec2(cos(time*fr2*M_PI/1000),sin(time*fr2*M_PI/1000))*0.1;
	float a=atan(pos.y,pos.x);
	//if(time<max_time)
	if(abs(length(pos)-0.5+cos(a*5)*0.01)<0.005)
		return ab_vec.x*sin(-time*fr*M_PI/1000+ang*nm_vec.x+rad*nm_vec.y)+
			   ab_vec.y*sin(-time*fr2*M_PI/1000+ang*nm_vec.x+rad*nm_vec.y);
	//if(length(pos+vec2(0,0.5)+p)<0.005)
	//	return sin(time*fr2*M_PI/1000);


	#endif
	#if 0


	if(  length(pos+vec2(0.0,0.3))<0.005
	  //|| length(pos+vec2(-0.1,0.2))<0.005
	  )
	//if(time<max_time)
		return ab_vec.x*sin(time*fn1)+ab_vec.y*sin(time*fn2);
		//return ab_vec.x*sin(time*fn1)/(time*fn1+1);
		//return ab_vec.x*(n4rand(pos*fr+vec2(time*freq*M_PI/1000,0))*2-1);
		//return ab_vec.x*sin(0.5*(fn2-fn1)*(time+cos(ab_vec.y*time)/ab_vec.y)+fn1*time);
	#endif
	#if 0
	if(length(pos-source_pos.xy)<0.005)
		return source_pos.z*ab_vec.x*sin(time*fn1)+source_pos.w*ab_vec.y*sin(time*fn2);
	#endif
	//return 0.1;//0.0001*sin(time/1000)/(1+length(pos));
	return 0;
}
float func_init_speed(vec2 pos)
{
	float p=length(pos);
	float w=M_PI/0.5;
	float m1=3;
	float m2=7;

	//float d=exp(-dot(pos,pos)/0.005);
	//return exp(-dot(pos,pos)/0.00005);

	//return (sin(p*w*m1)+sin(p*w*m2))*0.005;
	//if(max(abs(pos.x),abs(pos.y))<0.002)
	//	return 1;
	return 0;
}
float func_init(vec2 pos)
{
	//float theta=atan(pos.y,pos.x);
	//float r=length(pos);

	float w=M_PI/0.5;
	float m1=nm_vec.x;
	float m2=nm_vec.y;
	float a=1.2;
	float b=-1.1;
	//float d=exp(-dot(pos,pos)/0.005);
	//return exp(-dot(pos,pos)/0.00005);
	//solution from https://thelig.ht/chladni/
	//return (a*sin(pos.x*w*m1)*sin(pos.y*w*m2)+
	//		b*sin(pos.x*w*m2)*sin(pos.y*w*m1))*0.0005;
	//if(max(abs(pos.x),abs(pos.y))<0.002)
	//	return 1;
	return 0;
}
#define IDX(dx,dy) func_init(pos+vec2(dx,dy)*dtex)
#define DX(dx,dy,NOTUSED) textureOffset(values[3],normed,ivec2(dx,dy)).x
#define ST(id,dx,dy) textureOffset(values[id],normed,ivec2(dx,dy)).x
float calc_new_value(vec2 pos,vec2 c_sqr_avg)
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 dtex=1/tex_size;
#if 0
	//todo:c_sqr_avg
#else
	float dcsqr=c_const*c_const;
	float Dx=dcsqr/(dtex.x*dtex.x);
	float Dy=dcsqr/(dtex.y*dtex.y);
#endif

#if 0
	float dec1=dot(pos,pos)*decay.x;
	float dec2=dot(pos,pos)*decay.y;
#else
	float dec1=decay.x;
	float dec2=decay.y;
#endif

#if 0
	float A=dec2/(2*dt*dt*dt);
	float B=1/(dt*dt);
	float C=dec1/dt;

	float BdA=2*dt/dec2;
	float CdA=2*dec1*dt*dt/dec2;
	float DxdA=Dx/A;
	float DydA=Dy/A;

	/*
	float ret=(0.5*dec1*dt-1)*texture(values[0],normed).x+
		2*DX(0,0,normed)+
		dt*dt*Dx*(DX(1,0,normed)-2*DX(0,0,normed)+DX(-1,0,normed))+
		dt*dt*Dy*(DX(0,1,normed)-2*DX(0,0,normed)+DX(0,-1,normed))+
		dt*dt*func(pos);
	return ret/(1+0.5*dec1*dt);

	//*/
	/*
	float ret=0;
	ret+=texture(values[3],normed).x*(-BdA-CdA+2);
	ret+=texture(values[2],normed).x*(2*BdA-2*DxdA-2*DydA);
	ret+=texture(values[1],normed).x*(-BdA+CdA-2);
	ret+=texture(values[0],normed).x*A;
	ret+=DxdA*(DX(1,0,normed)+DX(-1,0,normed));
	ret+=DydA*(DX(0,1,normed)+DX(0,-1,normed));
	ret+=func(pos)/A;

	return ret;
	//*/
	/*
	float ret=0;
	ret+=texture(values[3],normed).x*(-B-C+2);
	ret+=texture(values[2],normed).x*(2*B-2*Dx-2*Dy);
	ret+=texture(values[1],normed).x*(-B+C-2*A);
	ret+=texture(values[0],normed).x*(A);
	ret+=Dx*(DX(1,0,normed)+DX(-1,0,normed));
	ret+=Dy*(DX(0,1,normed)+DX(0,-1,normed));
	ret+=func(pos);

	return ret/A;
	//*/


	///*
	float divisor=1/(B+C+3*A);

	float ret=0;
	ret+=texture(values[3],normed).x*(2*B+10*C-2*Dx-2*Dy)*divisor;
	ret+=texture(values[2],normed).x*(-B+C-12*A)*divisor;
	ret+=texture(values[1],normed).x*(6*A)*divisor;
	ret+=texture(values[0],normed).x*(-A)*divisor;
	ret+=Dx*(DX(1,0,normed)+DX(-1,0,normed))*divisor;
	ret+=Dy*(DX(0,1,normed)+DX(0,-1,normed))*divisor;
	ret+=func(pos)*divisor;

	return ret;
	//*/
#elif 1

	float c_const2=2;
	float GX=dcsqr*dt*dt*c_const2/(dtex.x*dtex.x);
	float GY=dcsqr*dt*dt*c_const2/(dtex.y*dtex.y);

	float HX=dcsqr*dt*dec2/(dtex.x*dtex.x);
	float HY=dcsqr*dt*dec2/(dtex.y*dtex.y);

	float ret=0;

	ret+=ST(1,0,0)*2;
	ret+=ST(0,0,0)*(-1);

	ret+=(GX+HX)*(ST(1,1,0)-2*ST(1,0,0)+ST(1,-1,0));
	ret+=(-1)*HX*(ST(0,1,0)-2*ST(0,0,0)+ST(0,-1,0));
	ret+=(GY+HY)*(ST(1,0,1)-2*ST(1,0,0)+ST(1,0,-1));
	ret+=(-1)*HY*(ST(0,0,1)-2*ST(0,0,0)+ST(0,0,-1));
	ret+=dt*dt*func(pos);
#else
	vec4 arg=decay;

	float xstep=dcsqr*dt/dtex.x;
	float ystep=dcsqr*dt/dtex.y;
	float mixed_step=dcsqr*dt/(dtex.x*dtex.y);

	float ret=0;
	ret+=ST(0,0,0);

	ret+=arg.x*0.5*xstep*(ST(0,1,0)-ST(0,-1,0));
	ret+=arg.x*0.5*ystep*(ST(0,0,1)-ST(0,0,-1));

	//ret-=0.5*arg.y*mixed_step*(ST(0,1,1)-ST(0,1,0)-ST(0,0,0)+ST(0,0,-1)+ST(0,0,1)-ST(0,0,0)-ST(0,-1,0)+ST(0,-1,-1));

	ret-=0.25*arg.y*mixed_step*(ST(0,1,1)-ST(0,1,-1)-ST(0,-1,1)+ST(0,-1,-1));

	ret+=xstep*arg.z*(ST(0,1,0)-2*ST(0,0,0)+ST(0,-1,0));
	ret+=ystep*arg.z*(ST(0,0,1)-2*ST(0,0,0)+ST(0,0,-1));

	ret+=arg.w*dt*func(pos);
#endif
	return ret;
}
float calc_init_value(vec2 pos,vec2 c_sqr_avg)
{
	return 0;
	//TODO?
	#if 1
	vec2 normed=(pos.xy+vec2(1,1))/2;

	vec2 dtex=1/tex_size;
	float dcsqr=dt*dt*c_const*c_const;
	/*
	float dcsqrx=dt*dt*c_sqr_avg.x/(dtex.x*dtex.x);
	float dcsqry=dt*dt*c_sqr_avg.y/(dtex.y*dtex.y);
	*/
	float dcsqrx=dcsqr/(dtex.x*dtex.x);
	float dcsqry=dcsqr/(dtex.y*dtex.y);

	float ret=
		IDX(0,0)+
		dt*func_init_speed(pos)+
		0.5*dcsqrx*(IDX(1,0)-2*IDX(0,0)+IDX(-1,0))+
		0.5*dcsqry*(IDX(0,1)-2*IDX(0,0)+IDX(0,-1))+
		0.5*dt*dt*func(pos);

	return ret;
	#endif
}
#define BOUND_N 0
float boundary_condition(vec2 pos,vec2 dir)
{
	//TODO: open boundary condition??

	//neumann boundary condition
#if BOUND_N
	//TODO
	float dx=1;
	float dy=1;
	vec2 normed=(pos.xy+vec2(1,1))/2;
	//float dist=1/length(tex_size,normed);

	//vec2 dtex=1/tex_size;

	float dcsqr=dt*dt*c_const*c_const;
	float dcsqrx=dcsqr;
	float dcsqry=dcsqr;


	if(abs(dir.x)>=abs(dir.y))
	{
		float u_2dy=DX(0,1)-DX(0,-1);
		float u_2dx=-(u_2dy*2*dx*dir.y)/(2*dy*dir.x);

		float ret=-texture(values_old,normed).x+
			2*DX(0,0)+
			dcsqrx*(u_2dx-2*(DX(0,0)-DX(-1,0)))+
			dcsqry*(DX(0,1)-2*DX(0,0)+DX(0,-1))+
			dt*dt*func(pos);
		return ret;
	}
	else
	{
		float u_2dx=DX(1,0)-DX(-1,0);
		float u_2dy=-(u_2dx*dir.x*2*dy)/(2*dx*pos.y);

		float ret=-texture(values_old,normed).x+
			2*DX(0,0)+
			dcsqrx*(DX(1,0)-2*DX(0,0)+DX(-1,0))+
			dcsqry*(u_2dy-2*(DX(0,0)-DX(0,-1)))+
			dt*dt*func(pos);

		return ret;
	}


	return 0;
#else
	//simples condition (i.e. bounce)
	return 0;
#endif
}
float boundary_condition_init(vec2 pos,vec2 dir)
{
	//TODO: open boundary condition??

	//neumann boundary condition
#if BOUND_N
	//TODO
	float dx=1;
	float dy=1;
	vec2 normed=(pos.xy+vec2(1,1))/2;
	//float dist=1/length(tex_size,normed);

	//vec2 dtex=1/tex_size;

	vec2 dtex=1/tex_size;
	//float dcsqr=dt*dt*c_const*c_const;
	float dcsqrx=dt*dt*c_const*c_const/(dtex.x*dtex.x);
	float dcsqry=dt*dt*c_const*c_const/(dtex.y*dtex.y);


	if(abs(dir.x)>=abs(dir.y))
	{
		float u_2dy=DX(0,1)-DX(0,-1);
		float u_2dx=-(u_2dy*2*dx*dir.y)/(2*dy*dir.x);


		float ret=
		2*IDX(0,0)+
		dt*func_init_speed(pos)+
		0.5*dcsqrx*(u_2dx-2*(IDX(0,0)-IDX(-1,0)))+
		0.5*dcsqry*(IDX(0,1)-2*IDX(0,0)+IDX(0,-1))+
		dt*dt*func(pos);

		return ret;
	}
	else
	{
		float u_2dx=DX(1,0)-DX(-1,0);
		float u_2dy=-(u_2dx*dir.x*2*dy)/(2*dx*pos.y);

	float ret=
		2*IDX(0,0)+
		dt*func_init_speed(pos)+
		0.5*dcsqrx*(IDX(1,0)-2*IDX(0,0)+IDX(-1,0))+
		0.5*dcsqry*(u_2dy-2*(IDX(0,0)-IDX(0,-1)))+
		dt*dt*func(pos);

		return ret;
	}


	return 0;
#else
	//simples condition (i.e. bounce)
	return 0;
#endif
}

float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec4 gain(vec4 x,float k)
{
	return vec4(gain(x.x,k),gain(x.y,k),gain(x.z,k),gain(x.w,k));
}
float c_shape(vec2 pos)
{
	return radial_shape(pos);
}
#define TDX(dx,dy) textureOffset(input_map,normed,ivec2(dx,dy)).x

void main(){
	float v=0;
	float max_d=0.8;
	float w=0.0025;

	vec2 normed=(pos.xy+vec2(1,1))/2;
	//float sh_v=0;
	//float sh_v=holed_tri(pos.xy);
	//float sh_v=sdEquilateralTriangle(pos.xy/max_d);
	//float sh_v=1-max(sh_polyhedron(pos.xy,12,max_d,0,w)-sh_polyhedron(pos.xy,8,0.2,0,w),0);
	//float sh_v=1-max(1-sdCircle(pos.xy,0.98)-sh_polyhedron(pos.xy,8,0.2,0,w),0);
	//float sh_v=1-damaged_circle(pos.xy);
	//float sh_v=damaged_circle2(pos.xy);
	//float sh_v=sh_wavy(pos.xy,max_d);
	//float sh_v=sdCircle(pos.xy,0.6);
	//float sh_v=sdCircle2(pos.xy,0.98);
	//float sh_v=dagger(pos.xy,w);
	//float sh_v=1-leaf(pos.xy,w);
	//float sh_v=1-chalice(pos.xy*0.75,w);
	//float sh_v=slit_experiment(pos.xy,w);
	//float sh_v=1-flower(pos.xy,w);
	//float sh_v=1-balance(pos.xy,w);
	//float sh_v=sh_jaws(pos.xy,w);
	float sh_v=1-sh_polyhedron(pos.xy,5,0.8,0,w);
	//float sh_v=1-ankh(pos.xy,w);
	//float sh_v=radial_shape(pos.xy);
	//vec2 mm=vec2(0.45);
	normed.y=1-normed.y;
	//float sh_v=step(texture(input_map,normed).x,0.3);
	float sh_v3=sdCircle(pos.xy,0.98);
#if 0
	vec4 sh_v2;
	sh_v2.x=TDX(0,0);
	sh_v2.y=TDX(0,1);
	sh_v2.z=TDX(1,0);
	sh_v2.w=TDX(1,1);

	sh_v2=(log(sh_v2+1)-vec4(input_map_swing.x))/(input_map_swing.y-input_map_swing.x);
	sh_v2=clamp(sh_v2,0,1);
	sh_v2=gain(sh_v2,v_gain);
	sh_v2=pow(sh_v2,vec4(v_gamma));
#else
	vec4 sh_v2=vec4(c_const);
#endif
	//vec2 pm=mod(pos.xy+0.5*mm,mm)-0.5*mm;
	//t_rot(pm.xy,M_PI/4);
	//float sh_v=ankh_sdf(pos.xy*0.7);

	//float sh_v=petals(pos.xy,w);
	//float sh_v=grid(pos.xy,w);
	//float sh_v=1;
	//sh_v=1-sh_v;

#if 0
	vec2 dtex=1/tex_size;
	float max_c=0.00005;// min(dtex.x,dtex.y)*0.8;
	float min_c=0.000005;
	//dt<= betta*delta_x/max(c_const)
	sh_v2=sh_v2*(max_c-min_c)+vec4(min_c);
	sh_v2=clamp(sh_v2,min_c,max_c);
#endif
	//sh_v2*=sh_v2;
	vec2 avg_c;
#if 1
	avg_c.x=2/(1/sh_v2.x+1/sh_v2.z);
	avg_c.y=2/(1/sh_v2.x+1/sh_v2.y);
#else
	avg_c.x=0.5*(sh_v2.x+sh_v2.z);
	avg_c.y=0.5*(sh_v2.x+sh_v2.y);
#endif
	avg_c*=avg_c;
	if(draw_form==1)
	{
		//v=(avg_c.x-min_c*min_c)/(max_c-min_c);
		v=sh_v;
		//vec2 dv=vec2(dFdx(sh_v),dFdy(sh_v));
		//normalize(dv);
		v=1-smoothstep(-w,w,v);
	}
	else
	{
		/*if(sh_v<=0)
		{
			if(init==1)
				v=calc_init_value(pos.xy,avg_c);
			else
				v=calc_new_value(pos.xy,avg_c);
		}
		else if(sh_v>0)*/
		{
			//todo: derivate
			/*vec2 dir=-normalize(pos.xy);
			if(init==1)
				v=boundary_condition_init(pos.xy,dir);
			else
				v=boundary_condition(pos.xy,dir);*/
		}
		float l=clamp(length(pos.xy),0,1);
		float radiation=0.99;
		if(sh_v<=0)
			v=calc_new_value(pos.xy,avg_c);
		else if(sh_v3<=0)
		//else
			v=calc_new_value(pos.xy,avg_c)*radiation;
		else
			v=calc_new_value(pos.xy,avg_c)*mix(radiation,radiation*radiation*radiation,l);
		//else v=0;
	}

	color=vec4(v,0,0,1);
}
]==]


function auto_clear(  )
	local pos_start=0
	local pos_end=0
	local pos_anim=0;
	for i,v in ipairs(config) do
		if v[1]=="size_mult" then
			pos_start=i
		end
		if v[1]=="size_mult" then
			pos_end=i
		end
	end

	for i=pos_start,pos_end do
		if config[i].changing then
			need_clear=true
			break
		end
	end
end
function clear_sand(  )
	make_sand_buffer()
end
function clear_buffers(  )
	texture_buffers={}
	make_textures()
	--TODO: @PERF
end

function reset_state(  )
	current_time=0
	solver_iteration=0
	clear_buffers()
end

local need_save
local single_shot_value
sim_thread=false
sim_thread_progress=0
function animate_accumulation()
    local wait_for_settle=10000
    local frame_count=100
    local frame_wait=5
    reset_state()
    config.accumulate=false
    --start emitting waves
    for k=1,wait_for_settle do
    	coroutine.yield()
    end
	-- [[ disable waves and wait to settle
	config.a=0
	config.b=0
	for k=1,wait_for_settle do
    	coroutine.yield()
    end
    --]]
    config.accumulate=true
    --start capturing frames
    for i=1,frame_count do
    	sim_thread_progress=i/frame_count
    	config.draw=false
    	for i=1,frame_wait do
    		coroutine.yield()
    	end
    	config.draw=true
    	need_save=true
    	coroutine.yield()
    end
    sim_thread=nil
end
function animation_system(  )
	if imgui.CollapsingHeader("Animation") then
	    if not sim_thread then
	        if imgui.Button("Start Animate") then
	           sim_thread=coroutine.create(animate_accumulation)
	        end
	    else
	        if imgui.Button("Stop Animate") then
	            sim_thread=nil
	        end
	        imgui.Text(string.format("Progress:%g",sim_thread_progress))
	    end
	end
end
function gui()
	imgui.Begin("Waviness")
	draw_config(config)

	local ok,new_mask=imgui.InputText("Mask",mask_file)
	mask_file=new_mask

	imgui.SameLine()
	if imgui.Button("Reload mask") then
		make_visits_texture()
	end
	if config.size_mult then
		size_mult=1
	else
		size_mult=2
	end
	update_size()
	local s=STATE.size
	if imgui.Button("Reset") then
		reset_state()
		current_tick=0
		current_frame=0
	end
	imgui.SameLine()
	if imgui.Button("Reset Accumlate") then
		clear_sand()
		need_clear=true
	end
	if imgui.Button("SingleShotNorm") then
		single_shot_value=true
	end
	imgui.SameLine()
	if imgui.Button("ClearNorm") then
		single_shot_value=nil
	end
	imgui.SameLine()
	if imgui.Button("Silence") then
		config.a=0
		config.b=0
	end
--[[
	if imgui.Button("Clear image") then
		clear_buffers()
	end
]]
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.SameLine()
	if imgui.Button("Save buffer") then
		need_buf_save=true
	end
	animation_system()
	imgui.End()
end

function update( )
	gui()
	update_real()
end
spline=spline or Catmull(gen_points(5,4))
spline_step=spline_step or 0

solver_iteration=solver_iteration or 0
current_time=current_time or 0
function waves_solve(  )
	local spline_p
	spline_p,spline_step=step_along_spline(spline,spline_step,0.00025,0.000005)
	spline_p[1]=spline_p[1]-0.5
	spline_p[2]=spline_p[2]-0.5
	spline_p[3]=spline_p[3]-0.5
	spline_p[4]=spline_p[4]-0.5
	solver_iteration=solver_iteration+1
	if solver_iteration>NUM_BUFFERS-1 then solver_iteration=0 end

	make_textures()

	solver_shader:use()

	if visit_tex then
		visit_tex.t:use(7)
		solver_shader:set_i("input_map",7)
		--solver_shader:set("input_map_swing",visits_minmax[1],visits_minmax[2])
		solver_shader:set("input_map_swing",0,1)
	end
	for i=0,NUM_BUFFERS-2 do
		local id=(solver_iteration+i) % NUM_BUFFERS +1
		texture_buffers[id].t:use(i)
		solver_shader:set_i("values["..i.."]",i)
	end
	local id_next=(solver_iteration+NUM_BUFFERS-1) % NUM_BUFFERS +1

	solver_shader:set("v_gamma",config.gamma)
	solver_shader:set("v_gain",config.gain)
	solver_shader:set("source_pos",spline_p[1],spline_p[2],spline_p[3],spline_p[4])
	if current_time==0 then
		solver_shader:set("init",1);
	else
		solver_shader:set("init",0);
	end
	solver_shader:set("dt",config.dt);
	solver_shader:set("c_const",0.0001);
	solver_shader:set("time",current_time);
	solver_shader:set("decay",config.decay1,config.decay2,config.decay3,config.decay4);
	solver_shader:set("freq",config.freq)
	solver_shader:set("freq2",config.freq2)
	solver_shader:set("nm_vec",config.n,config.m)
	solver_shader:set("ab_vec",config.a,config.b)
	if config.draw_form then
		solver_shader:set_i("draw_form",1)
	else
		solver_shader:set_i("draw_form",0)
	end
	local trg_tex=texture_buffers[id_next];
	trg_tex.t:use(NUM_BUFFERS)
	solver_shader:set("tex_size",trg_tex.w,trg_tex.h)
	if not trg_tex.t:render_to(trg_tex.w,trg_tex.h) then
		error("failed to set framebuffer up")
	end
	solver_shader:draw_quad()
	__render_to_window()



	current_time=current_time+config.dt
end

function save_img( id )
	--make_image_buffer()
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	img_buf:read_frame()
	if id then
		img_buf:save(string.format("video/saved (%d).png",id),config_serial)
	else
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	end
end
function save_tex( tex ,minv,maxv)
	make_io_buffer()
	io_buffer:read_texture(tex.t)
	buffer_save(io_buffer,minv,maxv,"waves_out.buf")
	bwrite()
end
function calc_range_value( tex )
	make_io_buffer()
	io_buffer:read_texture(tex.t)
	local m1=math.huge;
	local m2=-math.huge;
	for x=0,io_buffer.w-1 do
		for y=0,io_buffer.h-1 do
			local v=io_buffer:get(x,y)
			if v~= math.huge and v~=-math.huge then
				if v>m2 then m2=v end
				if v<m1 then m1=v end
			end
		end
	end
	return m1,m2
end
need_clear=true
function draw_texture( id )
	local id_next=(solver_iteration+NUM_BUFFERS-1) % NUM_BUFFERS +1
	local src_tex=texture_buffers[id_next];
	local trg_tex=texture_buffers.sand;

	add_shader:use()
	src_tex.t:use(0,1)
	add_shader:set_i("values",0)
	add_shader:set("mult",1)
	local need_draw=false
	if config.accumulate and not config.pause then
		add_shader:blend_add()
		--add_shader:blend_default()
		--draw_shader:set("in_col",config.color[1],config.color[2],config.color[3],config.color[4])
		if need_clear then
			__clear()
			need_clear=false
		end
		if not trg_tex.t:render_to(trg_tex.w,trg_tex.h) then
			error("failed to set framebuffer up")
		end
		add_shader:draw_quad()
		__render_to_window()

		if config.draw or id  then
			draw_shader:use()
			if config.monotone then
				draw_shader:set_i("monotone",1)
			else
				draw_shader:set_i("monotone",0)
			end
			draw_shader:blend_default()
			trg_tex.t:use(0,1)
			local minv,maxv
			minv,maxv=calc_range_value(trg_tex)
			if need_buf_save then
				save_tex(trg_tex,minv,maxv)
				need_buf_save=false
			end
			draw_shader:set_i("values",0)
			draw_shader:set("v_gamma",config.gamma)
			draw_shader:set("v_gain",config.gain)
			draw_shader:set("mid_color",config.color[1],config.color[2],config.color[3])
			--[[
			draw_shader:set("add",0)
			draw_shader:set("mult",1/(math.max(math.abs(maxv),math.abs(minv))))
			--]]
			-- [[
			draw_shader:set("add",-minv)
			draw_shader:set("mult",1/(maxv-minv))
			--]]
			--[[
			draw_shader:set("add",-math.log(minv+1))
			draw_shader:set("mult",1/(math.log(maxv+1)-math.log(minv+1)))
			--]]
			--[[
			draw_shader:set("add",0)
			draw_shader:set("mult",1/math.log(maxv+1))
			--]]
			draw_shader:draw_quad()
		else
			need_draw=true
		end
	else
		need_draw=true
	end
	if need_draw then
		add_shader:use()
		if config.draw or single_shot_value then
			local minv,maxv
			if single_shot_value==true then
				minv,maxv=calc_range_value(src_tex)
				single_shot_value={minv,maxv}
				print(minv,maxv)
			elseif type(single_shot_value)=="table" then
				minv,maxv=single_shot_value[1],single_shot_value[2]
			else
				minv,maxv=calc_range_value(src_tex)
			end
			add_shader:set("mult",1/(math.max(math.abs(maxv),math.abs(minv))))
		end
		add_shader:blend_default()
		add_shader:draw_quad()
	end

	if need_save or id then
		save_img(id)
		need_save=nil
	end
end
local frame_count=60
local tick_skip=1000

--480/100 452
--4800/10 99
--1000/1  877
--1000/3  322
--1000/9  620
local tick_count=20000
local tick_wait=1000--tick_count*0.75


current_frame=current_frame or 0
current_tick=current_tick or 0
function ncos(t)
	return (math.cos(t*math.pi*2)+1)/2
end
function nsin(t)
	return (math.sin(t*math.pi*2)+1)/2
end
function lerp( st,en,v )
	return (1-v)*st+v*en
end
anim_spline=anim_spline or Catmull(gen_points(3,3))
anim_spline_step=anim_spline_step or 0




function update_real(  )
	__no_redraw()
	if config.pause then
		__clear()
		draw_texture()
	else
		__clear()
		draw_texture()
    	if sim_thread then
        --print("!",coroutine.status(sim_thread))
	        local ok,err=coroutine.resume(sim_thread)
	        if not ok then
	            print("Error:",err)
	            sim_thread=nil
	        end
    	end
		auto_clear()
		waves_solve()
	end
	local scale=config.scale
	--[[
	local c,x,y= is_mouse_down()
	if c then
		--mouse to screen
		x=(x/size[1]-0.5)*2
		y=(-y/size[2]+0.5)*2
		--screen to world
		x=(x-cx)/scale
		y=(y-cy)/(scale*aspect_ratio)

		--now set that world pos so that screen center is on it
		config.cx=(-x)*scale
		config.cy=(-y)*(scale*aspect_ratio)
		need_clear=true
	end
	if __mouse.wheel~=0 then
		local pfact=math.exp(__mouse.wheel/10)
		config.scale=config.scale*pfact
		config.cx=config.cx*pfact
		config.cy=config.cy*pfact
		need_clear=true
	end
	]]
end

