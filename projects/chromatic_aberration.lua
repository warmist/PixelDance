
require "common"
local luv=require "colors_luv"
local size=STATE.size
local image_buf=load_png("saved_1588959289.png")
__set_window_size(image_buf.w,image_buf.h)
function resize( w,h )
	size=STATE.size
end
config=make_config({
	--{"blur",0,type="int"}, TODO
	{"bulge_r",0,type="float",max=0.1},
	{"bulge_g",0.014,type="float",max=0.1},
	{"bulge_b",0.033,type="float",max=0.1},
	--{"bulge_noise",0.033,type="float",max=0.1},
	{"bulge_radius_offset",0,type="float",max=4},
	{"gamma",1,type="float",min=0.01,max=5},
	{"gain",1,type="float",min=-5,max=5},
},config)

function make_visits_texture()
	if visit_tex==nil or visit_tex.w~=size[1] or visit_tex.h~=size[2] then

		visit_tex={t=textures:Make(),w=size[1],h=size[2]}
		visit_tex.t:use(0,1)
		visit_tex.t:set(size[1],size[2],2)
	end
end

function make_visits_buf(  )
	if visit_buf==nil or visit_buf.w~=size[1] or visit_buf.h~=size[2] then
		visit_buf=make_flt_buffer(size[1],size[2])
	end
end
make_visits_buf()
local main_shader=shaders.Make[[
#version 330
#line 23
out vec4 color;
in vec3 pos;
#define M_PI 3.14159265359
vec3 rgb2xyz( vec3 c ) {
    vec3 tmp;
    tmp.x = ( c.r > 0.04045 ) ? pow( ( c.r + 0.055 ) / 1.055, 2.4 ) : c.r / 12.92;
    tmp.y = ( c.g > 0.04045 ) ? pow( ( c.g + 0.055 ) / 1.055, 2.4 ) : c.g / 12.92,
    tmp.z = ( c.b > 0.04045 ) ? pow( ( c.b + 0.055 ) / 1.055, 2.4 ) : c.b / 12.92;
    return 100.0 * tmp *
        mat3( 0.4124, 0.3576, 0.1805,
              0.2126, 0.7152, 0.0722,
              0.0193, 0.1192, 0.9505 );
}

vec3 xyz2lab( vec3 c ) {
    vec3 n = c / vec3( 95.047, 100, 108.883 );
    vec3 v;
    v.x = ( n.x > 0.008856 ) ? pow( n.x, 1.0 / 3.0 ) : ( 7.787 * n.x ) + ( 16.0 / 116.0 );
    v.y = ( n.y > 0.008856 ) ? pow( n.y, 1.0 / 3.0 ) : ( 7.787 * n.y ) + ( 16.0 / 116.0 );
    v.z = ( n.z > 0.008856 ) ? pow( n.z, 1.0 / 3.0 ) : ( 7.787 * n.z ) + ( 16.0 / 116.0 );
    return vec3(( 116.0 * v.y ) - 16.0, 500.0 * ( v.x - v.y ), 200.0 * ( v.y - v.z ));
}

vec3 rgb2lab(vec3 c) {
    vec3 lab = xyz2lab( rgb2xyz( c ) );
    return vec3( lab.x / 100.0, 0.5 + 0.5 * ( lab.y / 127.0 ), 0.5 + 0.5 * ( lab.z / 127.0 ));
}

vec3 lab2xyz( vec3 c ) {
    float fy = ( c.x + 16.0 ) / 116.0;
    float fx = c.y / 500.0 + fy;
    float fz = fy - c.z / 200.0;
    return vec3(
         95.047 * (( fx > 0.206897 ) ? fx * fx * fx : ( fx - 16.0 / 116.0 ) / 7.787),
        100.000 * (( fy > 0.206897 ) ? fy * fy * fy : ( fy - 16.0 / 116.0 ) / 7.787),
        108.883 * (( fz > 0.206897 ) ? fz * fz * fz : ( fz - 16.0 / 116.0 ) / 7.787)
    );
}

vec3 xyz2rgb( vec3 c ) {
    vec3 v =  c / 100.0 * mat3( 
        3.2406, -1.5372, -0.4986,
        -0.9689, 1.8758, 0.0415,
        0.0557, -0.2040, 1.0570
    );
    vec3 r;
    r.x = ( v.r > 0.0031308 ) ? (( 1.055 * pow( v.r, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.r;
    r.y = ( v.g > 0.0031308 ) ? (( 1.055 * pow( v.g, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.g;
    r.z = ( v.b > 0.0031308 ) ? (( 1.055 * pow( v.b, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.b;
    return r;
}

vec3 lab2rgb(vec3 c) {
    return xyz2rgb( lab2xyz( vec3(100.0 * c.x, 2.0 * 127.0 * (c.y - 0.5), 2.0 * 127.0 * (c.z - 0.5)) ) );
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
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

vec3 xyzFromWavelength(float wavelength) {
	vec3 ret;
  ret.x = gaussian(wavelength,  1.056, 5998, 379, 310)
         + gaussian(wavelength,  0.362, 4420, 160, 267)
         + gaussian(wavelength, -0.065, 5011, 204, 262);

  ret.y = gaussian(wavelength,  0.821, 5688, 469, 405)
         + gaussian(wavelength,  0.286, 5309, 163, 311);

  ret.z = gaussian(wavelength,  1.217, 4370, 118, 360)
         + gaussian(wavelength,  0.681, 4590, 260, 138);
  return ret;
}

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
	return res*res*2-1;
}

vec2 noise2(vec2 p){
	return vec2(noise(p),noise(p+vec2(111,-2139)));
}

uniform sampler2D tex_main;
uniform vec3 barrel_power;
uniform float barrel_offset;
uniform float v_gain;
uniform float v_gamma;
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec2 Distort(vec2 p,float power)
{
    float theta  = atan(p.y, p.x);
    float radius = length(p)+barrel_offset;
    radius = pow(radius, power)-barrel_offset;
    p.x = radius * cos(theta);
    p.y = radius * sin(theta);
    return 0.5 * (p + 1.0);
}
uniform float barrel_noise;
float two_gauss(vec2 pos,float p,float c)
{
	return c*exp(-(pos.x*pos.x*pos.y*pos.y)/(p*p*2));
}

vec3 xyz_from_thing(float d1,float spread) {
	float d=d1;
	float scale=1.1;
	float new_spread=spread/(d*scale);
	vec3 ret;
	ret.x = gaussian_conv(d,  1.056, 0.6106, 0.10528, 0.0861,d*scale,new_spread)
		+ gaussian_conv(d,  0.362, 0.1722, 0.04444, 0.0742,d*scale,new_spread)
		+ gaussian_conv(d, -0.065, 0.3364, 0.05667, 0.0728,d*scale,new_spread);

	ret.y = gaussian_conv(d,  0.821, 0.5244, 0.1303, 0.1125,d,new_spread)
	    + gaussian_conv(d,  0.286, 0.4192, 0.0452, 0.0864,d,new_spread);

	ret.z = gaussian_conv(d,  1.217, 0.1583, 0.0328, 0.1,d,new_spread)
	    + gaussian_conv(d,  0.681, 0.2194, 0.0722, 0.0383,d,new_spread);

  	return ret;
}
vec3 xyz_from_normed_waves(float v_in)
{
	vec3 ret;
	ret.x = gaussian(v_in,  1.056, 0.6106, 0.10528, 0.0861)
		+ gaussian(v_in,  0.362, 0.1722, 0.04444, 0.0742)
		+ gaussian(v_in, -0.065, 0.3364, 0.05667, 0.0728);

	ret.y = gaussian(v_in,  0.821, 0.5244, 0.1303, 0.1125)
	    + gaussian(v_in,  0.286, 0.4192, 0.0452, 0.0864);

	ret.z = gaussian(v_in,  1.217, 0.1583, 0.0328, 0.1)
	    + gaussian(v_in,  0.681, 0.2194, 0.0722, 0.0383);

	return ret;
}
vec3 sample_thing(float dist,float spread)
{
	//float w=two_gauss(vec2(dist,v-dist),spread,1);
	int max_samples=40;
	vec3 ret=vec3(0);
	float wsum=0;
	for(int i=0;i<max_samples;i++)
	{
		float v=i/float(max_samples);
		float w=gaussian1(v,1,dist,spread/dist);
		ret+=w*xyz_from_normed_waves(v);
		wsum+=1;//w;
	}
	return ret/wsum;
}
vec4 sample_circle(vec2 pos)
{
	int radius=5;
	int rad_sq=radius*radius;
	vec4 ret=vec4(0);
	float weight=0;
	for(int x=0;x<radius;x++)
	{
		int max_y=int(sqrt(rad_sq-x*x));
		for(int y=0;y<max_y;y++)
		{
			float w=1/float(x*x+y*y+1);
			vec2 offset=vec2(x,y)/textureSize(tex_main,0);

			/*ret+=textureOffset(tex_main,pos,ivec2(x,y))*w;
			ret+=textureOffset(tex_main,pos,ivec2(-x,y))*w;
			ret+=textureOffset(tex_main,pos,ivec2(x,-y))*w;
			ret+=textureOffset(tex_main,pos,ivec2(-x,-y))*w;*/

			ret+=texture(tex_main,pos+offset)*w;
			ret+=texture(tex_main,pos+offset*vec2(1,-1))*w;
			ret+=texture(tex_main,pos+offset*vec2(-1,1))*w;
			ret+=texture(tex_main,pos+offset*vec2(-1,-1))*w;
			weight+=4*w;
		}
	}
	return ret/weight;
}
vec3 sample_xyz_ex(vec2 pos,float power)
{
	vec3 xy_t=xyzFromWavelength(mix(3800,7400,texture(tex_main,pos).x)*power);
	return xy_t;
}
vec3 sample_xyz(vec2 pos,float power)
{
	float nv=texture(tex_main,pos).x;
#if 0
	nv=gain(nv,v_gain);
	nv=pow(nv,v_gamma);
#else
	power=gain(power,v_gain);
	power=pow(power,v_gamma);
#endif
	vec3 xy_t=xyzFromWavelength(mix(3800,7400,power)*nv);
	return xy_t;
}
vec3 sample_sample(vec2 pos, float dist)
{

	vec3 nv=texture(tex_main,pos).xyz;

	nv.x=gain(nv.x,v_gain);
	nv.y=gain(nv.y,v_gain);
	nv.z=gain(nv.z,v_gain);
	nv=pow(nv,vec3(v_gamma));

	nv=rgb2xyz(nv);
	vec3 xy_t=sample_thing(dist,0.005)*nv;
	return xy_t;
}
vec3 sample_circle_w(vec2 pos)
{
	int radius=10;
	int rad_sq=radius*radius;
	vec3 ret=vec3(0);
	float weight=0;
	float p=700;
	float ep=32;
	float eparam=ep*ep;
	for(int x=0;x<radius;x++)
	{
		int max_y=int(sqrt(rad_sq-x*x));
		for(int y=0;y<max_y;y++)
		{
			float dist_sq=float(x*x+y*y);
			float dist=sqrt(dist_sq)/radius;
			//float w=1/(dist_sq+1);
			float w=exp(-dist_sq/eparam);
			//float w=1;
			vec2 offset=vec2(x,y)/textureSize(tex_main,0);

			ret+=sample_sample(pos+offset,dist)*w;
			ret+=sample_sample(pos+offset*vec2(1,-1),dist)*w;
			ret+=sample_sample(pos+offset*vec2(-1,1),dist)*w;
			ret+=sample_sample(pos+offset*vec2(-1,-1),dist)*w;
			weight+=4*w;
		}
	}
	return ret*p/weight;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	#if 0 //dont like this :<
	vec2 n1=vec2(noise2(pos.xy*8))*barrel_noise;
	vec2 n2=vec2(noise2(pos.xy*8.1+vec2(999,77.5)))*barrel_noise;
	vec2 n3=vec2(noise2(pos.xy*7.9+vec2(-1023,787)))*barrel_noise;

	vec2 x_pos=Distort(pos.xy+n1,barrel_power.x)-n1;
	vec2 y_pos=Distort(pos.xy+n2,barrel_power.y)-n2;
	vec2 z_pos=Distort(pos.xy+n3,barrel_power.z)-n3;
	#else
	vec2 x_pos=Distort(pos.xy,barrel_power.x);
	vec2 y_pos=Distort(pos.xy,barrel_power.y);
	vec2 z_pos=Distort(pos.xy,barrel_power.z);
	#endif
	/*TODO
		another way to do this: calculate spectrum of point, distort by it's 
		wave length. Needs some sort of smoothing/reverse interpolation?
		Another idea: get wavelength sort of like this: https://www.semrock.com/Data/Sites/1/semrockpdfs/whitepaper_howtocalculateluminositywavelengthandpurity.pdf
		and then shift it somewhat
		Another idea: calculate something like a lightsource (i.e. spectrum) is 
		falling down and image is distorting it by it's VALUE.
	*/
	vec3 L_out;
	{
		vec4 c=texture(tex_main,x_pos*vec2(1,-1));
		vec3 Lc=rgb2xyz(c.xyz);
		L_out.x=Lc.x;
	}
	{
		vec4 c=texture(tex_main,y_pos*vec2(1,-1));
		vec3 Lc=rgb2xyz(c.xyz);
		L_out.y=Lc.y;
	}
	{
		vec4 c=texture(tex_main,z_pos*vec2(1,-1));
		vec3 Lc=rgb2xyz(c.xyz);
		L_out.z=Lc.z;
	}
	float nv=texture(tex_main,normed).x;

	nv=gain(nv,v_gain);
	nv=pow(nv,v_gamma);


	//vec3 Rc=xyz2rgb(L_out);
	float v=clamp(length(pos.xy),0,1);
	//color = vec4(xyz2rgb(xyzFromWavelength(mix(3800,7400,v))*85),1);
	//color.xyz=pow(color.xyz,vec3(2.2));
	//color = vec4(Rc,1);//vec4(v,v,v,1);//vec4(0.2,0,0,1);
	vec3 ss;
	float spread=barrel_offset;
	float power=0.1;

	ss=xyz2rgb(sample_thing(v,spread))*power;

	color=vec4(ss,1);
	//vec3 rcol=xyz2rgb(sample_circle_w(normed));
	//color=vec4(rcol,1);
}
]]
local con_tex=textures.Make()

function save_img()
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))))
end

function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Image")
	draw_config(config)
	imgui.End()

	make_visits_buf()
	make_visits_texture()

	main_shader:use()
	con_tex:use(0,1)
	main_shader:blend_add()
	image_buf:write_texture(con_tex)
	main_shader:set_i("tex_main",0)
	main_shader:set("barrel_power",config.bulge_r+1,config.bulge_g+1,config.bulge_b+1);
	main_shader:set("barrel_offset",config.bulge_radius_offset)
	main_shader:set("v_gamma",config.gamma)
	main_shader:set("v_gain",config.gain)
	visit_tex.t:use(1)
	--main_shader:set("barrel_noise",config.bulge_noise)
	if not visit_tex.t:render_to(visit_tex.w,visit_tex.h) then
		error("failed to set framebuffer up")
	end
	if need_clear then
		__clear()
		need_clear=false
	end
	main_shader:draw_quad()
	__render_to_window()
	imgui.Begin("Image")
	if imgui.Button("save") then
		save_img()
	end
	imgui.SameLine()
	if imgui.Button("clear") then
		need_clear=true
	end
	imgui.End()
	
end
