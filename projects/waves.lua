require "common"
--basically implementing: http://hplgit.github.io/num-methods-for-PDEs/doc/pub/wave/html/._wave006.html
--[[
	TODO:
		actually implement dx/dy that would help with bogus units problem
			-maybe only aspect ratio?

--]]
local size_mult
local oversample=1
local win_w
local win_h
local aspect_ratio
function update_size(  )
	win_w=1280*size_mult
	win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
--update_size()

local size=STATE.size
function count_lines( s )
	local n=0
	for i in s:gmatch("\n") do n=n+1 end
	return n
end
function shader_make( s_in )
	local sl=count_lines(s_in)
	s="#version 330\n#line "..(debug.getinfo(2, 'l').currentline-sl).."\n"
	s=s..s_in
	return shaders.Make(s)
end

img_buf=make_image_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	print("new size:",w,h)
end


texture_buffers=texture_buffers or {}
function make_sand_buffer()
	local t={t=textures:Make(),w=size[1]*oversample,h=size[2]*oversample}
	t.t:use(0,1)
	t.t:set(size[1]*oversample,size[2]*oversample,2)
	texture_buffers.sand=t
end
function make_textures()
	if #texture_buffers==0 or
		texture_buffers[1].w~=size[1]*oversample or
		texture_buffers[1].h~=size[2]*oversample then
		--print("making tex")
		for i=1,3 do
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
	{"decay",0,type="floatsci",min=0,max=0.01,power=10},
	{"n",1,type="int",min=0,max=15},
	{"m",1,type="int",min=0,max=15},
	{"a",1,type="float",min=-1,max=1},
	{"b",1,type="float",min=-1,max=1},
	{"color",{124/255,50/255,30/255},type="color"},
	{"gamma",1,type="float",min=0.01,max=5},
	{"gain",1,type="float",min=-5,max=5},
	{"draw",true,type="boolean"},
	{"accumulate",false,type="boolean"},
	{"animate",false,type="boolean"},
	{"animate_simple",false,type="boolean"},
	{"size_mult",true,type="boolean"},
},config)


add_shader=shader_make[==[
out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float mult;

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float lv=abs(texture(values,normed).x*mult);
	color=vec4(lv,lv,lv,1);
}
]==]
draw_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;
uniform sampler2D values;
uniform float mult;
uniform float add;
uniform float v_gamma;
uniform float v_gain;
uniform vec3 mid_color;
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
	//color=vec4(palette(lv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(0.5,2.0,1.5),vec3(0.1,0.4,0.4)),1);
	color.a=1;
	vec3 col_back=vec3(0);
	vec3 col_top=vec3(1);
	/* color with a down to dark break
	
	if(lv>0.5)
		color.xyz=mix(col_back,col_top,(lv-0.5)*2);
	else
	{
		float nv=sin(lv*2*M_PI);
		color.xyz=mix(col_back,mid_color,nv);
	}
	//*/
	
	///* continuous color
	if(lv>0.5)
	{
		color.xyz=mix(mid_color,col_top,(lv-0.5)*2);
	}
	else
	{
		color.xyz=mix(col_back,mid_color,lv*2);
	}
	//*/

#endif
}
]==]
solver_shader=shader_make[==[
out vec4 color;
in vec3 pos;
uniform sampler2D values_cur;
uniform sampler2D values_old;
uniform float init;
uniform float dt;
uniform float c_const;
uniform float time;
uniform float decay;
uniform float freq;
uniform float freq2;
uniform vec2 tex_size;
uniform vec2 nm_vec;
uniform vec2 ab_vec;
//uniform vec2 dpos;

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
float radial_shape(in vec2 st)
{
	float a=atan(st.y,st.x);
	float r=length(st)*1.5;
	return step(r/(sin(a*3)+1.1)+cos(a*9+sin(r*r)*M_PI*4)/16-0.5,0);
}
float grid(in vec2 st,float fw)
{
	st=mod(st,0.25)-vec2(0.125,0.125);
	st*=vec2(5,5);
	float r=leaf(st,fw);
	return r;
}
#define DX(dx,dy) textureOffset(values_cur,normed,ivec2(dx,dy)).x
float hash(float n) { return fract(sin(n) * 1e4); }
float hash(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x)))); }
float func(vec2 pos)
{
	//if(length(pos)<0.0025 && time<100)
	//	return cos(time/freq)+cos(time/(2*freq/3))+cos(time/(3*freq/2));
	//vec2 pos_off=vec2(cos(time*0.001)*0.5,sin(time*0.001)*0.5);
	//if(sh_ring(pos,1.2,1.1,0.001)>0)
	float max_time=500;
	float min_freq=1;
	float max_freq=5;
	float ang=atan(pos.y,pos.x);
	float rad=length(pos);
	float fr=freq;
	float fr2=freq2;
	//fr*=mix(min_freq,max_freq,time/max_time);
	float max_a=4;
	float r=0.08;
	#if 0
		//if(time<max_time)
			//if(pos.x<-0.35)
				//return (hash(time*freq2)*hash(pos*freq))/2;
				return n4rand(pos);
	#endif
	#if 0
		//if(time<max_time)
		//if(pos.x<-0.35)
			return (
		ab_vec.x*sin(time*fr*M_PI/1000
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.x*M_PI*nm_vec.x)+
		ab_vec.y*sin(time*fr2*M_PI/1000
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
		if(length(pos+dv)<0.005 && time<max_time)
		//if(time<max_time)
			return (
			sin(time*fr*M_PI/1000)
			+sin(time*fr*M_PI/1000*1.618)
			/*+sin(time*freq*3*M_PI/1000)*/
										)*0.00005;
	}
	#endif
	#if 0
	//if(time<max_time)
		return (
		ab_vec.x*sin(time*fr*M_PI/1000
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.x*M_PI*nm_vec.x)+
		ab_vec.y*sin(time*fr2*M_PI/1000
		//+pos.x*M_PI*2*nm_vec.x
		//+pos.y*M_PI*2*nm_vec.y
		)*cos(pos.y*M_PI*nm_vec.y)
		)*0.00005;
	#endif

	#if 1


	vec2 p=vec2(cos(time*fr2*M_PI/1000),sin(time*fr2*M_PI/1000))*0.65;
	//if(time<max_time)
	if(abs(length(pos)-0.7)<0.005)
		return sin(time*fr*M_PI/1000+ang*nm_vec.x+rad*nm_vec.y);
	//if(length(pos+vec2(0,0.5)+p)<0.005)
	//	return sin(time*fr2*M_PI/1000);


	#endif
	#if 0
	if(length(pos+vec2(0,0.5))<0.005)
		return sin(time*freq*7.13*M_PI/1000)*0.0005;
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
float calc_new_value(vec2 pos)
{
	vec2 normed=(pos.xy+vec2(1,1))/2;
	
	float dcsqr=dt*dt*c_const*c_const;
#if 0
	vec2 p2=pos+vec2(0,-0.3);
	dcsqr*=(dot(p2,p2)+0.05);
#endif
	float dcsqrx=dcsqr;
	float dcsqry=dcsqr;
#if 0
	float dec=dot(pos,pos)*decay;//abs(hash(pos*100))*decay;
#else
	float dec=decay;
#endif
	float ret=(0.5*dec*dt-1)*texture(values_old,normed).x+
		2*DX(0,0)+
		dcsqrx*(DX(1,0)-2*DX(0,0)+DX(-1,0))+
		dcsqry*(DX(0,1)-2*DX(0,0)+DX(0,-1))+
		dt*dt*func(pos);

	return ret/(1+0.5*dec*dt);
}
float calc_init_value(vec2 pos)
{
	vec2 normed=(pos.xy+vec2(1,1))/2;

	vec2 dtex=1/tex_size;
	//float dcsqr=dt*dt*c_const*c_const;
	float dcsqrx=dt*dt*c_const*c_const/(dtex.x*dtex.x);
	float dcsqry=dt*dt*c_const*c_const/(dtex.y*dtex.y);

	float ret=
		2*IDX(0,0)+
		dt*func_init_speed(pos)+
		0.5*dcsqrx*(IDX(1,0)-2*IDX(0,0)+IDX(-1,0))+
		0.5*dcsqry*(IDX(0,1)-2*IDX(0,0)+IDX(0,-1))+
		dt*dt*func(pos);

	return ret;
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

#define DRAW_FORM 0
void main(){
	float v=0;
	float max_d=2;
	float w=0.005;
	//float sh_v=max(sh_polyhedron(pos.xy,12,max_d,0,w)-sh_polyhedron(pos.xy,6,0.2,0,w),0);
	//float sh_v=sh_circle(pos.xy,max_d,w);
	//float sh_v=sh_wavy(pos.xy,max_d);
	//float sh_v=dagger(pos.xy,w);
	//float sh_v=leaf(pos.xy,w);
	//float sh_v=chalice(pos.xy,w);
	//float sh_v=flower(pos.xy,w);
	//float sh_v=balance(pos.xy,w);
	//float sh_v=sh_jaws(pos.xy,w);
	//float sh_v=sh_polyhedron(pos.xy*vec2(0.2,1),4,0.2,0,w);
	//float sh_v=ankh(pos.xy,w);
	float sh_v=radial_shape(pos.xy);
	//vec2 mm=vec2(0.45);

	//vec2 pm=mod(pos.xy+0.5*mm,mm)-0.5*mm;
	//t_rot(pm.xy,M_PI/4);
	//float sh_v=ankh_sdf(pos.xy*0.7);

	//float sh_v=petals(pos.xy,w);
	//float sh_v=grid(pos.xy,w);
	//float sh_v=1;
#if DRAW_FORM
	v=sh_v;
#else
	if(sh_v>1-w)
	{

		if(init==1)
			v=calc_init_value(pos.xy);
		else
			v=calc_new_value(pos.xy);
	}
	else if(sh_v>0)
	{
		//todo: derivate
		/*vec2 dir=-normalize(pos.xy);
		if(init==1)
			v=boundary_condition_init(pos.xy,dir);
		else
			v=boundary_condition(pos.xy,dir);*/
		v=0;

	}
#endif
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
function gui()
	imgui.Begin("Waviness")
	draw_config(config)
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
	end
	if imgui.Button("SingleShotNorm") then
		single_shot_value=true
	end
	imgui.SameLine()
	if imgui.Button("ClearNorm") then
		single_shot_value=nil
	end
--[[
	if imgui.Button("Clear image") then
		clear_buffers()
	end
]]
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.End()
end

function update( )
	gui()
	update_real()
end
solver_iteration=solver_iteration or 0
current_time=current_time or 0
function waves_solve(  )

	solver_iteration=solver_iteration+1
	if solver_iteration>2 then solver_iteration=0 end

	make_textures()

	solver_shader:use()
	local id_old=solver_iteration % 3 +1
	local id_cur=(solver_iteration+1) % 3 +1
	local id_next=(solver_iteration+2) % 3 +1
	texture_buffers[id_old].t:use(0)
	texture_buffers[id_cur].t:use(1)
	solver_shader:set_i("values_old",0)
	solver_shader:set_i("values_cur",1)
	if current_time==0 then
		solver_shader:set("init",1);
	else
		solver_shader:set("init",0);
	end
	solver_shader:set("dt",config.dt);
	solver_shader:set("c_const",0.1);
	solver_shader:set("time",current_time);
	solver_shader:set("decay",config.decay);
	solver_shader:set("freq",config.freq)
	solver_shader:set("freq2",config.freq2)
	solver_shader:set("nm_vec",config.n,config.m)
	solver_shader:set("ab_vec",config.a,config.b)
	local trg_tex=texture_buffers[id_next];
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
function calc_range_value( tex )
	make_io_buffer()
	io_buffer:read_texture(tex.t)
	local m1=math.huge;
	local m2=-math.huge;
	for x=0,io_buffer.w-1 do
		for y=0,io_buffer.h-1 do
			local v=io_buffer:get(x,y)
			if v>m2 then m2=v end
			if v<m1 then m1=v end
		end
	end
	return m1,m2
end

function draw_texture( id )
	local id_next=(solver_iteration+2) % 3 +1
	local src_tex=texture_buffers[id_next];
	local trg_tex=texture_buffers.sand;

	add_shader:use()
	src_tex.t:use(0,1)
	add_shader:set_i("values",0)
	add_shader:set("mult",1)
	local need_draw=false
	if config.accumulate then
		add_shader:blend_add()
		--add_shader:blend_default()
		--draw_shader:set("in_col",config.color[1],config.color[2],config.color[3],config.color[4])
		if not trg_tex.t:render_to(trg_tex.w,trg_tex.h) then
			error("failed to set framebuffer up")
		end
		add_shader:draw_quad()
		__render_to_window()

		if config.draw or id  then
			draw_shader:use()
			draw_shader:blend_default()
			trg_tex.t:use(0,1)
			local minv,maxv
			minv,maxv=calc_range_value(trg_tex)
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
		if config.draw or single_shot_value then
			local minv,maxv
			if single_shot_value==true then
				minv,maxv=calc_range_value(src_tex)
				single_shot_value={minv,maxv}
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
local frame_count=10000
local tick_skip=9

--480/100 452
--4800/10 99
--1000/1  877
--1000/3  322
--1000/9  620
local tick_count=5000
local tick_wait=tick_count*0.75


current_frame=current_frame or 0
current_tick=current_tick or 0
function ncos(t)
	return (math.cos(t*math.pi*2)+1)/2
end
function nsin(t)
	return (math.sin(t*math.pi*2)+1)/2
end
function animate_step(  )
	local t=current_frame/frame_count
	if t>=1 then
		config.animate=false
	end

	local start_frq=2.5
	local end_frq=3.5

	local start_frq2=1
	local end_frq2=0
	config.freq=t*(end_frq-start_frq)+start_frq--ncos(t)*(end_frq-start_frq)+start_frq
	--config.freq2=--nsin(t)*(end_frq2-start_frq2)+start_frq2
	current_frame=current_frame+1
	print(config.freq,config.freq2)
end

last_animate=false
function auto_clear_ticks(  )
	if last_animate~= config.animate_simple then
		last_animate= config.animate_simple
		current_tick=0
		current_frame=0
	end
end
function update_real(  )
	__no_redraw()
	if config.pause then
		__clear()
		draw_texture()
	else
		auto_clear_ticks()
		if config.animate then
			current_tick=current_tick+1
			if current_tick>=tick_count then
				animate_step(  )
				__clear()
				draw_texture(current_frame)

				current_tick=0
				reset_state()
			elseif current_tick>=tick_wait then
				__clear()
				draw_texture()
			end
		elseif config.animate_simple then
			current_tick=current_tick+1
			if current_tick>=tick_skip then
				__clear()
				config.draw=true
				draw_texture(current_frame)
				current_tick=0
				current_frame=current_frame+1
				config.draw=false
				if current_frame>frame_count then
					config.animate_simple=false
				end
			else
				__clear()
				draw_texture()
			end
		else
			__clear()
			draw_texture()
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
