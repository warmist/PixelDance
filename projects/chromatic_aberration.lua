
require "common"
local luv=require "colors_luv"
local size=STATE.size
local image_buf
image_buf=load_png("saved_1596204719.png")
-- [[
local bwrite = require "blobwriter"
local bread = require "blobreader"
function read_hd_png_buf( fname,log_norm )
	local file = io.open(fname, 'rb')
	local b = bread(file:read('*all'))
	file:close()

	local sx=b:u32()
	local sy=b:u32()
	local background_buf=make_flt_buffer(sx,sy)
	local background_minmax={}
	background_minmax[1]=b:f32()
	background_minmax[2]=b:f32()

	for x=0,background_buf.w-1 do
	for y=0,background_buf.h-1 do
		local v=b:f32()
		background_buf:set(x,y,{v,v,v,1})
	end
	end

	print("Loaded:",background_minmax[1],background_minmax[2])

	for x=0,background_buf.w-1 do
	for y=0,background_buf.h-1 do
		local iv=background_buf:get(x,y).r
		if log_norm then
			local min=background_minmax[1]
			local max=background_minmax[2]
			local v=(math.log(iv+1)-min)/(max-min)
			background_buf:set(x,y,{v,v,v,1})
		else
			local v=(iv-background_minmax[1])/(background_minmax[2]-background_minmax[1])
			background_buf:set(x,y,{v,v,v,1})
		end
	end
	end

	return background_buf,background_minmax
end
function load_hd_png()
	if background_tex==nil then
		print("making tex")
		read_background_buf("out.buf")
		background_tex={t=textures:Make(),w=background_buf.w,h=background_buf.h}
		background_tex.t:use(0,1)
		background_buf:write_texture(background_tex.t)
		__unbind_buffer()
	end
end
image_buf=read_hd_png_buf("out.buf",true)
--]]

__set_window_size(image_buf.w,image_buf.h)
function resize( w,h )
	size=STATE.size
end
config=make_config({
	--{"blur",0,type="int"}, TODO
	{"iteration_step",0.001,type="floatsci",max=1},
	{"bulge_r",0.1,type="float",max=0.5},
	{"bulge_radius_offset",0,type="float",max=1},
	{"gamma",2.2,type="float",min=0.01,max=5},
	{"gain",0.33,type="float",min=-0.01,max=1},
	{"exposure",50,type="float",min=0.001,max=100},
},config)

function make_compute_texture()
	if compute_tex==nil or compute_tex.w~=size[1] or compute_tex.h~=size[2] then

		compute_tex={t=textures:Make(),w=size[1],h=size[2]}
		compute_tex.t:use(0,1)
		compute_tex.t:set(size[1],size[2],FLTA_PIX)
	end
end

function make_compute_buf(  )
	if compute_buf==nil or compute_buf.w~=size[1] or compute_buf.h~=size[2] then
		compute_buf=make_flt_buffer(size[1],size[2])
	end
end
make_compute_buf()



local main_shader=shaders.Make[[
#version 330
#line 39
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
uniform float barrel_power;
uniform float barrel_offset;
uniform float v_gain;
uniform float v_gamma;
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec2 Distort(vec2 p,vec2 offset,float power)
{
    float theta  = atan(p.y+offset.y, p.x+offset.x);
    float radius = length(p+offset)+barrel_offset;
    radius = pow(radius, power)-barrel_offset;
    p.x = radius * cos(theta);
    p.y = radius * sin(theta);
    p-=offset;
    return p;
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
vec3 xyz_from_masked(float d,float mask,float spread) {
	vec3 ret;
	ret.x = gaussian_conv(d,  1.056, 0.6106, 0.10528, 0.0861,mask,spread)
		+ gaussian_conv(d,  0.362, 0.1722, 0.04444, 0.0742,mask,spread)
		+ gaussian_conv(d, -0.065, 0.3364, 0.05667, 0.0728,mask,spread);

	ret.y = gaussian_conv(d,  0.821, 0.5244, 0.1303, 0.1125,mask,spread)
	    + gaussian_conv(d,  0.286, 0.4192, 0.0452, 0.0864,mask,spread);

	ret.z = gaussian_conv(d,  1.217, 0.1583, 0.0328, 0.1,mask,spread)
	    + gaussian_conv(d,  0.681, 0.2194, 0.0722, 0.0383,mask,spread);

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
uniform float iteration;
uniform float iteration_step;
float black_body_spectrum(float l,float temperature )
{
	/*float h=6.626070040e-34; //Planck constant
	float c=299792458; //Speed of light
	float k=1.38064852e-23; //Boltzmann constant
	*/
	float const_1=5.955215e-17;//h*c*c
	float const_2=0.0143878;//(h*c)/k
	float top=(2*const_1);
	float bottom=(exp((const_2)/(temperature*l))-1)*l*l*l*l*l;
	return top/bottom;
}
float black_body(float iter,float temp)
{
	return black_body_spectrum(mix(380*1e-9,740*1e-9,iter),temp);
}
vec2 tangent_distort(vec2 p,vec2 arg)
{
	float r=dot(p,p);
	float xy=p.x*p.y;

	return p+vec2(2*arg.x*xy+             arg.y*(r+2*p.x*p.x),
				    arg.x*(r+2*p.y*p.y)+2*arg.y*xy            );
}
float easeOutQuad(float x)
{
	return 1 - (1 - x) * (1 - x);
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 offset=vec2(0,0);
	vec2 dist_pos=pos.xy;
	dist_pos=Distort(dist_pos,offset,barrel_power*iteration+1);
	//dist_pos=tangent_distort(dist_pos,vec2(0,barrel_power*iteration)*0.1);
	dist_pos=(dist_pos+vec2(1))/2;
	//vec2 dist_pos=normed+vec2(barrel_power)*iteration;


	/*TODO
		another way to do this: calculate spectrum of point, distort by it's 
		wave length. Needs some sort of smoothing/reverse interpolation?
		Another idea: get wavelength sort of like this: https://www.semrock.com/Data/Sites/1/semrockpdfs/whitepaper_howtocalculateluminositywavelengthandpurity.pdf
		and then shift it somewhat
		Another idea: calculate something like a lightsource (i.e. spectrum) is 
		falling down and image is distorting it by it's VALUE.
	*/

	float c=texture(tex_main,dist_pos*vec2(1,-1)).x;
	vec3 nv=rgb2xyz(texture(tex_main,dist_pos*vec2(1,-1)).xyz);

	//vec3 nv=texture(tex_main,dist_pos*vec2(1,-1)).xyz;

	//nv=gain(nv,v_gain);
	//nv=pow(nv,v_gamma);

	float v=clamp(length(pos.xy),0,1);
	//color = vec4(xyz2rgb(xyzFromWavelength(mix(3800,7400,v))*85),1);
	//color.xyz=pow(color.xyz,vec3(2.2));
	//color = vec4(Rc,1);//vec4(v,v,v,1);//vec4(0.2,0,0,1);
	vec3 ss;
	float spread=barrel_offset;
	float power=1e-2;

	//ss=xyz2rgb(sample_thing(v,spread))*power;

	//color=vec4(ss,1);
	//vec3 rcol=xyz2rgb(sample_circle_w(normed));
	//color=vec4(rcol,1);

	//color.x=log(black_body(normed.x))*power;

	float T=5778;//Sun
	//float T=8000;
	//float T=6503.6; //D65 illiuminant

	//color.xyz=xyz_from_normed_waves(iteration)*black_body(iteration,mix(2000,T,easeOutQuad(c)))*iteration_step;
	color.xyz=xyz_from_normed_waves(iteration)*black_body(iteration,T)*nv*iteration_step;
	//color.xyz=nv;
	//color.xyz=vec3(1,0.1,0.1);
	color.a=1;
}
]]
local draw_shader=shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float iteration_step;
uniform vec3 min_v;
uniform vec3 max_v;
uniform float v_gamma;
uniform float v_gain;
uniform float exposure;
uniform float avg_lum;
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
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec3 tonemapFilmic(vec3 x) {
  vec3 X = max(vec3(0.0), x - 0.004);
  vec3 result = (X * (6.2 * X + 0.5)) / (X * (6.2 * X + 1.7) + 0.06);
  return pow(result, vec3(2.2));
}
vec3 eye_adapt_and_stuff(vec3 light)
{
	float lum_white = pow(10,v_gain);
	//lum_white*=lum_white;

	//tocieYxy
	float sum=light.x+light.y+light.z;
	float x=light.x/sum;
	float y=light.y/sum;
	float Y=light.y;

	Y = (Y* exposure )/avg_lum;
	if(v_gain<0)
    	Y = Y / (1 + Y); //simple compression
	else
    	Y = (Y*(1 + Y / lum_white)) / (Y + 1); //allow to burn out bright areas


    //transform back to cieXYZ
    light.y=Y;
    float small_x = x;
    float small_y = y;
    light.x = light.y*(small_x / small_y);
    light.z = light.x / small_x - light.x - light.y;

    return light;
}
void main()
{
	vec2 normed=(pos.xy*vec2(1,-1)+vec2(1,1))/2;
	color=texture(tex_main,normed);
	//color.xyz*=iteration_step;
	//color.xyz-=min_v;
	//color.xyz/=max(max_v.x,max(max_v.y,max_v.z));//-min_v);
	//color.xyz/=max_v.x+max_v.y+max_v.z;


	//nv=gain(nv,v_gain);
	/*
	color.xyz*=exposure;
	color.xyz=xyz2rgb(color.xyz);

	*/
	//color.xyz=tonemapFilmic(color.xyz);
	//color.xyz=pow(color.xyz,vec3(1/2.2));

	color.xyz=eye_adapt_and_stuff(color.xyz);
	color.xyz=xyz2rgb(color.xyz);

	color.xyz=pow(color.xyz,vec3(v_gamma));
	//color.xyz=vec3(gain(color.x,v_gain),gain(color.y,v_gain),gain(color.z,v_gain));
}
]]
local con_tex=textures.Make()

function save_img()
	img_buf=make_image_buffer(size[1],size[2])
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))))
end
local iteration=0
local need_clear=true
function find_min_max(  )
	compute_tex.t:use(0,1)
	local lmin={math.huge,math.huge,math.huge}
	local lmax={-math.huge,-math.huge,-math.huge}

	compute_buf:read_texture(compute_tex.t)
	local avg_lum=0
	local count=0
	for x=0,compute_buf.w-1 do
	for y=0,compute_buf.h-1 do
		local v=compute_buf:get(x,y)
		if v.r<lmin[1] then lmin[1]=v.r end
		if v.g<lmin[2] then lmin[2]=v.g end
		if v.b<lmin[3] then lmin[3]=v.b end

		if v.r>lmax[1] then lmax[1]=v.r end
		if v.g>lmax[2] then lmax[2]=v.g end
		if v.b>lmax[3] then lmax[3]=v.b end
		local lum=v.g
		avg_lum=avg_lum+math.log(1+lum)
		count=count+1
	end
	end
	avg_lum = math.exp(avg_lum / count);
	print(avg_lum)
	for i,v in ipairs(lmax) do
		print(i,v)
	end
	return lmin,lmax,avg_lum
end
local lmin,lmax,avg_lum
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Image")
	draw_config(config)
	

	make_compute_buf()
	make_compute_texture()
	if need_clear then
		iteration=0
	end
	if iteration<1 then
		main_shader:use()
		con_tex:use(0,1)
		main_shader:blend_add()
		image_buf:write_texture(con_tex)
		main_shader:set_i("tex_main",0)
		main_shader:set("barrel_power",config.bulge_r);
		main_shader:set("barrel_offset",config.bulge_radius_offset)
		main_shader:set("v_gamma",config.gamma)
		main_shader:set("v_gain",config.gain)
		main_shader:set("iteration",iteration)
		main_shader:set("iteration_step",config.iteration_step)
		compute_tex.t:use(1)
		--main_shader:set("barrel_noise",config.bulge_noise)
		if not compute_tex.t:render_to(compute_tex.w,compute_tex.h) then
			error("failed to set framebuffer up")
		end
		iteration=iteration+config.iteration_step
		if need_clear then
			__clear()
			need_clear=false
		end
		main_shader:draw_quad()
		__render_to_window()
		done=false
	end

	if imgui.Button("snap max") or lmin==nil or (not done and iteration>1)then
		lmin,lmax,avg_lum=find_min_max()
		done=true
	end
	draw_shader:use()
	compute_tex.t:use(0)
	draw_shader:set_i("tex_main",0)
	draw_shader:set("iteration_step",config.iteration_step)
	draw_shader:set("min_v",lmin[1],lmin[2],lmin[3])
	draw_shader:set("max_v",lmax[1],lmax[2],lmax[3])
	draw_shader:set("v_gamma",config.gamma)
	draw_shader:set("v_gain",config.gain)
	draw_shader:set("avg_lum",avg_lum)
	draw_shader:set("exposure",config.exposure)
	draw_shader:draw_quad()

	
	if imgui.Button("save") then
		save_img()
	end
	imgui.SameLine()
	if imgui.Button("clear") then
		need_clear=true
	end
	imgui.End()
	
end
