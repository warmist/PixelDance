--simple 2d shapes
require "common"
config=make_config({
	{"n",1,type="int",min=0,max=15},
},config)

local size=STATE.size
img_buf=make_image_buffer(size[1],size[2])

function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
end

function count_lines( s )
	local n=0
	for i in s:gmatch("\n") do n=n+1 end
	return n
end



shapes_shader=shaders.Make[==[

#version 330
#line __LINE__

#define PI 3.14159265
#define TAU (2*PI)
#define PHI (sqrt(5)*0.5 + 0.5)

out vec4 color;
in vec3 pos;

uniform vec2 rez;
uniform vec4 params;
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

// Repeat space along one axis. Use like this to repeat along the x axis:
// <float cell = pMod1(p.x,5);> - using the return value is optional.
float pMod1(inout float p, float size) {
	float halfsize = size*0.5;
	float c = floor((p + halfsize)/size);
	p = mod(p + halfsize, size) - halfsize;
	return c;
}

// Rotate around a coordinate axis (i.e. in a plane perpendicular to that axis) by angle <a>.
// Read like this: R(p.xz, a) rotates "x towards z".
// This is fast if <a> is a compile-time constant and slower (but still practical) if not.
void pR(inout vec2 p, float a) {
	p = cos(a)*p + sin(a)*vec2(p.y, -p.x);
}

// Shortcut for 45-degrees rotation
void pR45(inout vec2 p) {
	p = (p + vec2(p.y, -p.x))*sqrt(0.5);
}


float smooth_mod(float x,float y)
{
	float eps=0.25;
	float num=cos(PI*x/y)*sin(PI*x/y);
	float s=sin(PI*x/y);
	float den=s*s+eps*eps;
	return y*(0.5-(1/PI)*atan(num/den));
}
float F2(vec2 pos)
{

	float v=sdCircle(pos,0.8);
	v=abs(v+0.125)-0.125;
	//v=smooth_mod(v+0.1,0.25)-0.1;
	//v=cos(v*PI*64);
	v=opUnion(v,sdEquilateralTriangle(pos*3));
	pR(pos,PI/3);
	float t=sdEquilateralTriangle(pos*1.5);
	t=abs(t+0.025)-0.025;
	v=opSubtraction(t,v);
	//for(int i=0;i<125;++i)
	//	v=abs(v-0.025)-0.025;
	return v;
}
float p2(float x)
{
	return x*x*(params.x+x*params.y+x*x*params.z+x*x*x*params.w);
	
}
float p(float x)
{
	float a0=params.x;
	float a1=params.y;
	float a2=0.5;
	float a3=params.z;
	float a4=params.w;

	float a=-(6.0/5.0)*(a0+a1+a2+a3+a4);
	float b=(6.0/4.0)*(a0*(a1+a2+a3+a4)+a1*(a2+a3+a4)+a2*(a3+a4));
	float c=-(6.0/3.0)*(a0*a1*(a2+a3+a4)+a0*a2*a3+a1*a2*(a3+a4)+a0*a3*a4+a1*a3*a4+a2*a3*a4);
	float d=3*(a0*a1*a2*a3+a0*a1*a2*a4+a0*a1*a3*a4+a0*a2*a3*a4+a1*a2*a3*a4);
	float e=-(a0*a1*a2*a3*a4);

	return (((((x+a)*x+b)*x+c)*x+d)*x+e)*x;
}
float F(vec2 pos)
{

	//float v=length(pos);
	/*
	float k1=4;
	float k2=5;
	float v=pow(pow(abs(pos.x),k1)+pow(abs(pos.y),k2),1/k1);
	*/
	/*
	vec2 c=vec2(0.1,0.1);
	float v=length(pos-c);
	//*/
	/*
	float x=pos.x;
	float y=pos.y;

	float a=(params.x+1)/2;
	float b=params.y;
	float c=params.z;
	float d=-b;
	float e=1-a-c;

	float v=abs(a*x*x*x*x+b*x*x*x+c*x*x+d*x+e-y);//abs(a*pos.x*pos.x+c-pos.y)/sqrt(a*a+b*b);
	//*/
	float v=abs(p2(pos.x)-pos.y);
	return v;
}
vec2 grad( in vec2 x )
{
    vec2 h = vec2( 0.0001, 0.0 );
    return vec2( F(x+h.xy) - F(x-h.xy),
                 F(x+h.yx) - F(x-h.yx) )/(2.0*h.x);
}
float rand1(float n){return fract(sin(n) * 43758.5453123);}
float rand2(float n){return fract(sin(n) * 78745.6326871);}
vec2 c_mul(vec2 self, vec2 other) {
    return vec2(self.x * other.x - self.y * other.y, 
                self.x * other.y + self.y * other.x);
}
//from: https://www.alanzucconi.com/2017/07/15/improving-the-rainbow-2/
vec3 bump3y (vec3 x, vec3 yoffset)
{
    vec3 y = 1 - x * x;
    y = clamp(y-yoffset,0,1);
    return y;
}
vec3 spectral_zucconi6 (float w)
{
    // w: [400, 700]
    // x: [0,   1]
    //fixed x = clamp((w - 400.0)/ 300.0,0,1);
    float x=w;
    vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
    vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
    vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);
    vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
    vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
    vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);
    return
        bump3y(c1 * (x - x1), y1) +
        bump3y(c2 * (x - x2), y2) ;
}
float d_measure(vec2 a,vec2 b)
{
	vec2 p1=vec2(0.1,-0.5);
	vec2 p2=vec2(0.5,0.5);
#if 0 //polar
	float ar=atan(a.y,a.x);
	float br=atan(b.y,b.x);
	float ad=length(a);
	float bd=length(b);
	return distance(vec2(ar,ad),vec2(br,bd));
#elif 0 //polar fixed
	//a-=p1;
	//b-=p2;
	float ar=atan(a.y,a.x);
	float br=atan(b.y,b.x);
	float ad=length(a);
	float bd=length(b);
	float dr=ar-br;//min(ar-br,min(abs(ar-br+PI*2),abs(ar-br-PI*2)));
	if(dr>PI)
		dr-=2*PI;
	else if(dr<-PI)
		dr+=2*PI;
	float dd=ad-bd;
	//return length(vec2(cos(dr),sin(dr))*dd);
	return sqrt(dr*dr+dd*dd);
#elif 0 //random bs
	float v1=cos(a.x-b.x);
	float v2=sin(a.y-b.y);
	return sqrt(v1*v1+v2*v2);
#elif 0 //random bs polynomial
	//todo more
	return pow(distance(a*a*a,b*b*b),1/3.0f);
#elif 0 //z^2 complex
	return sqrt(distance(c_mul(a,a),c_mul(b,b)));
#elif 0 //z^3 complex
	return sqrt(distance(c_mul(a,c_mul(a,a)),c_mul(b,c_mul(b,b))));
#elif 0 //julia
	for(int i=0;i<5;i++)
	{
		a=c_mul(a,a)+p1;
		b=c_mul(b,b)+p2;
	}
	return distance(a,b);
#elif 0 //mandelbrot
	for(int i=0;i<100;i++)
	{
		p1=c_mul(p1,p1)+a;
		p2=c_mul(p2,p2)+b;
	}
	return distance(p1,p2);
#else
	return distance(a,b); //normal
#endif
}
void main_rnd(){
	float aspect=rez.x/rez.y;
	
	vec2 p=pos.xy*vec2(1,1/aspect);

	float r0=abs(params.x);
	float r1=abs(params.y);
	float r2=abs(params.z);

	const int max_id=50;
	float v=0;
	float d_min=100000;
	for(int i=0;i<max_id;i++)
	{

		vec2 ptrg=vec2(rand1(i*45.123+548*params.x),rand2(i*45.123+548*params.y))*2-vec2(1);

		float l=d_measure(p,ptrg);
		if(l<d_min)
		{
			v=i;
			d_min=l;
		}
	}
	float lv=v/max_id;
	color=vec4(spectral_zucconi6(lv),1);
	//color=vec4(vec3(lv),1);
}
int circle_intersect(vec2 p1, vec2 p2, float r1,float r2,out vec2 out1,out vec2 out2)
{
	float R=distance(p1,p2);
	float rd=r1*r1-r2*r2;
	if(R<r1+r2)
	{
		vec2 c=(p1+p2)*0.5;
		vec2 d2=(p2-p1)*(rd)/(2*R*R);
		float D=0.5*sqrt(2*(r1*r1+r2*r2)/(R*R)-(rd*rd/(R*R*R*R))-1);
		out1=c+d2+D*vec2(p2.y-p1.y,p1.x-p2.x);
		out2=c+d2-D*vec2(p2.y-p1.y,p1.x-p2.x);
		return 2;
	}
	else
		return 0;
}
vec2 rotate_point(vec2 p,ivec2 lat_coord)
{
	//test mirror
#if 0
	if(lat_coord.x%2)
		p.x*=-1;
#endif
	return p;
}
void main(){ //lattice version

	float aspect=rez.x/rez.y;
	
	vec2 p=pos.xy*vec2(1,1/aspect);
	p*=5;
	//lattice axis and size
	vec2 lat_dx=vec2(1,0);
	//vec2 lat_dy=vec2(-0.5,sqrt(3)/2); //120 deg, 2/3*pi
	float alpha=(3.14159265359)/3;
	vec2 lat_dy=vec2(cos(alpha),sin(alpha));

	vec2 local_p;
	//TODO: could be simplified if we take lat_dx/dy as mat2
	local_p.x=(dot(p,lat_dx)/dot(lat_dx,lat_dx));
	local_p.y=(dot(p,lat_dy)/dot(lat_dy,lat_dy));
	//repeat the lattice
	vec2 lat_p;
	local_p.x=modf(local_p.x,lat_p.x);
	local_p.y=modf(local_p.y,lat_p.y);
	if(local_p.x<0)
	{
		//local_p.x*=-1;
		lat_p.x-=1;
	}
	if(local_p.y<0)
	{
		//local_p.y*=-1;
		lat_p.y-=1;
	}
	ivec2 ilat_p=ivec2(lat_p);
	
	//local_p-=vec2(0.0,0.7)*((lat_p.y+lat_p.x)%2);

	float d_min=1e23;
	

	float v=0;
	//list of points inside lattice
	vec2 point_list[]={
		vec2(0.1,0.1),
		vec2(.25,.125),
		vec2(.125,.3),
		vec2(0.5-0.1,0.5-0.1),
		vec2(0.5-.25,0.5-.125),
		vec2(0.5-.125,0.5-.3),
	};
#if 1
	ivec2 nn[]={
		ivec2(0,1),
		ivec2(1,1),
		ivec2(1,0),
		ivec2(1,-1),
		ivec2(0,-1),
		ivec2(-1,-1),
		ivec2(-1,0),
		ivec2(-1,1),
	};
#else
	ivec2 nn[]={
		ivec2(0,1),
		ivec2(1,0),
		ivec2(0,-1),
		ivec2(-1,0),
	};
#endif
	for(int i=0;i<point_list.length();i++)
	{
		//check if p is nearest to inner point
		float l=d_measure(local_p,rotate_point(point_list[i],ilat_p));
		if(l<d_min)
		{
			v=i%3;
			d_min=l;
		}
		//also check nearest next lattice cell
		for(int k=0;k<nn.length();k++)
		{
			//TODO: mirror rotate here too!
			vec2 nn_offset=nn[k].x*lat_dx+nn[k].y*lat_dy;
			float l=d_measure(local_p,rotate_point(point_list[i],ilat_p+nn[k])+nn_offset);
			if(l<d_min)
			{
				//v=i+point_list.length()*k;
				v=i%3;
				d_min=l;
			}
		}
	}
	//float lv=v/(point_list.length()*nn.length());
	float lv=v/(point_list.length()/2);
	color=vec4(spectral_zucconi6(lv*0.9+0.1),1);
}
void main_circles(){
	float aspect=rez.x/rez.y;
	
	vec2 p=pos.xy*vec2(1,1/aspect);

	float r0=abs(params.x); //middle circle at 0,0
	float r1=abs(params.y); //dist from center
	float r2=abs(params.z); //other circles

	const int count_circles=21;
	float v=0.33;
	float d_min=length(p);//100000;
	vec2 i1,i2;

	vec2 c1_center=vec2(0,0);
	for(int i=0;i<count_circles;i++)
	{
		float a=i/float(count_circles)*TAU;
		vec2 c2_center=vec2(cos(a),sin(a))*r1;//+(vec2(rand1(i*45.123+548*params.w),rand2(i*45.123+548*params.w))*2-vec2(1))*0.1;
		for(int j=0;j<count_circles;j++)
		{
			float b=j/float(count_circles)*TAU+0.7;
			vec2 c3_center=vec2(cos(b),sin(b))*(r1+0.25);
			if(i!=j)
			{
				int icount=circle_intersect(c2_center,c3_center,r1,r2,i1,i2);
				if(icount==2)
				{
					float l=d_measure(p,i1);
					if(l<d_min)
					{
						v=(a+b)/2;
						//v=i*count_circles+j;
						//v=(abs(c2_center.x)+abs(c3_center.x)+abs(c2_center.y)+abs(c3_center.y))*0.25;
						d_min=l;
					}
					l=d_measure(p,i2);
					if(l<d_min)
					{
						v=(a+b)/2;
						//v=i*count_circles+j;
						//v=(abs(c2_center.x)+abs(c3_center.x)+abs(c2_center.y)+abs(c3_center.y))*0.25;
						d_min=l;
					}
				}
			}
		}
		//intersect center
		int icount=circle_intersect(c1_center,c2_center,r0,r2,i1,i2);
		if(icount==2)
		{
			float l=d_measure(p,i1);
			if(l<d_min)
			{
				v=i*count_circles;
				//v=(abs(c2_center.x));
				v=a;
				d_min=l;
			}
			l=d_measure(p,i2);
			if(l<d_min)
			{
				//v=i*count_circles;
				//v=(abs(c2_center.y));
				v=a;
				d_min=l;
			}
		}
	}
	//float lv=v*1+0.5;//(count_circles*count_circles);
	//float lv=v/(count_circles*count_circles);
	float lv=v/(TAU);
	color=vec4(spectral_zucconi6(lv),1);
	//color=vec4(vec3(lv),1);
}
void main2(){
	float aspect=rez.x/rez.y;
	float s=5;
	vec2 p=pos.xy*vec2(1,1/aspect);
	float v=F(p*s);
	//vec2 g=grad(p);
	//float de=abs(v)/length(g);
	float w=0.003*s;
	float line_thick=0.01;
	float lv=v;
	float ldist=0.3;
	//lv=abs(fract(lv/ldist+0.5)-0.5)*ldist;
	lv=smoothstep(line_thick+w,line_thick-w,lv);
	//lv=abs(v)/(length(g));
	//*
	lv+=0.4*(1-smoothstep(0,w,abs(pos.x*s)));
	lv+=0.2*(1-smoothstep(0,w,abs(pos.x*s+1)));
	lv+=0.2*(1-smoothstep(0,w,abs(pos.x*s-1)));
	lv+=0.4*(1-smoothstep(0,w,abs(pos.y*s)));
	lv+=0.2*(1-smoothstep(0,w,abs(pos.y*s+1)));
	lv+=0.2*(1-smoothstep(0,w,abs(pos.y*s-1)));
	//*/
	color=vec4(vec3(lv),1);
}
]==]
params=params or {0,0,0,0,0,0,0}

function randomize_params(  )
	local h=2
	for i=1,#params do
		params[i]=math.random()*h-h/2
	end
end
function gui(  )
	imgui.Begin("Shapes")
	draw_config(config)
	if imgui.Button("Randomize") then
		randomize_params()
	end
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
end
function save_img( id )
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
function update( )
	gui()
	__no_redraw()
	__clear()

	--for i=1,10 do
		shapes_shader:use()
		shapes_shader:blend_add()
		shapes_shader:set("rez",size[1],size[2])
		shapes_shader:set("params",params[1],params[2],params[3],params[4])
		shapes_shader:draw_quad()
		--randomize_params()
	--end
	if need_save then
		save_img()
		need_save=nil
	end
end