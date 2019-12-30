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

function shader_make( s_in )
	local sl=count_lines(s_in)
	s="#version 330\n#line "..(debug.getinfo(2, 'l').currentline-sl).."\n"
	s=s..s_in
	return shaders.Make(s)
end


shapes_shader=shader_make[==[

#define PI 3.14159265
#define TAU (2*PI)
#define PHI (sqrt(5)*0.5 + 0.5)

out vec4 color;
in vec3 pos;

uniform vec2 rez;
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

float F(vec2 pos)
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
vec2 grad( in vec2 x )
{
    vec2 h = vec2( 0.0001, 0.0 );
    return vec2( F(x+h.xy) - F(x-h.xy),
                 F(x+h.yx) - F(x-h.yx) )/(2.0*h.x);
}
void main(){
	float aspect=rez.x/rez.y;
	vec2 p=pos.xy*vec2(1,1/aspect);
	float v=F(p);
	//vec2 g=grad(p);
	//float de=abs(v)/length(g);
	float w=0.003;
	float line_thick=0.05;
	float lv=v;
	float ldist=0.3;
	lv=abs(fract(lv/ldist+0.5)-0.5)*ldist;
	lv=smoothstep(line_thick+w,line_thick-w,lv);
	//lv=abs(v)/(length(g));
	color=vec4(vec3(lv),1);
}
]==]

function gui(  )
	imgui.Begin("Shapes")
	draw_config(config)
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
	shapes_shader:use()
	shapes_shader:set("rez",size[1],size[2])
	shapes_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end