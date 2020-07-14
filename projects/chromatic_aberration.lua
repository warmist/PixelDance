
require "common"
local luv=require "colors_luv"
local size=STATE.size
local image_buf=load_png("saved_1584003393.png")
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
},config)

local main_shader=shaders.Make[[
#version 330
#line 16
out vec4 color;
in vec3 pos;

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
	vec3 Rc=xyz2rgb(L_out);
	//color = vec4(xyz2rgb(xyzFromWavelength(mix(3800,7400,normed.x))*85),1);
	//color.xyz=pow(color.xyz,vec3(2.2));
	color = vec4(Rc,1);//vec4(v,v,v,1);//vec4(0.2,0,0,1);
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

	
	main_shader:use()
	con_tex:use(0,1)
	image_buf:write_texture(con_tex)
	main_shader:set_i("tex_main",0)
	main_shader:set("barrel_power",config.bulge_r+1,config.bulge_g+1,config.bulge_b+1);
	main_shader:set("barrel_offset",config.bulge_radius_offset)
	--main_shader:set("barrel_noise",config.bulge_noise)
	main_shader:draw_quad()
	imgui.Begin("Image")
	if imgui.Button("save") then
		save_img()
	end
	imgui.End()
	
end