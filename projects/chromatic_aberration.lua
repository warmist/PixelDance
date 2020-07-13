
require "common"
local luv=require "colors_luv"
local size=STATE.size
local image_buf=load_png("saved_1574845066.png")

measures=make_float_buffer(800,3)
palette=palette or make_flt_buffer(255,1)
config=make_config({
	--{"blur",0,type="int"}, TODO
	{"bulge_r",0,type="float",max=0.1},
	{"bulge_g",0.014,type="float",max=0.1},
	{"bulge_b",0.033,type="float",max=0.1},
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
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 x_pos=Distort(pos.xy,barrel_power.x);
	vec2 y_pos=Distort(pos.xy,barrel_power.y);
	vec2 z_pos=Distort(pos.xy,barrel_power.z);
	/*TODO
		another way to do this: calculate spectrum of point, distort by it's 
		wave length. Needs some sort of smoothing/reverse interpolation?
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
	main_shader:draw_quad()
	imgui.Begin("Image")
	if imgui.Button("save") then
		save_img()
	end
	imgui.End()
	
end