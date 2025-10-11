require "common"
local luv=require "colors_luv"
local size=STATE.size

--[[
	TODO:
		defocus aberration
		thin film interference
		ref: real lens distortion?
		https://www.osapublishing.org/DirectPDFAccess/101E1C8A-E1F7-4ED8-90D6F581926F24BF_269193/ETOP-2013-EThA6.pdf?da=1&id=269193&uri=ETOP-2013-EThA6&seq=0&mobile=no

		Ideas:
			* "syntetic" pigments:
				- types (looks like) exist:
					- signal + shifted signal (e.g. dioxazine_purple_tints)
					- inverted (e.g. somewhat k_cerulean_blue)
					- laplassian of signal? (e.g. arylide_yellow)
					- mix (Quin Mag and Dioxazine P)
				- complex index of refraction?
				- back to the basics, simulate as a layered media with diffuse particles
					* https://en.wikipedia.org/wiki/Rayleigh_scattering
					* https://en.wikipedia.org/wiki/Mie_scattering
					* https://refractiveindex.info
					
--]]
local image_buf

-- [[
local bwrite = require "blobwriter"
local bread = require "blobreader"

function tonemap( light,avg_lum )
	local lum_white = math.pow(10,2);
	--tocieYxy
	local sum=light.r+light.g+light.b;
	local x=light.r/sum;
	local y=light.g/sum;
	local Y=light.g;

	Y = (Y* 9.6 )/avg_lum;
	if(false) then
    	Y = Y / (1 + Y); --simple compression
	else
    	Y = (Y*(1 + Y / lum_white)) / (Y + 1); --allow to burn out bright areas
    end
	--[[if math.random()>0.9999 then
		print(Y)
	end]]

    --transform back to cieXYZ
    light.g=Y;
    local small_x = x;
    local small_y = y;
    light.r = light.g*(small_x / small_y);
    light.b = light.r / small_x - light.r - light.g;

    return light;
end
function tonemap2( light,min_lum,max_lum )

	--tocieYxy
	local sum=light.r+light.g+light.b;
	local x=light.r/sum;
	local y=light.g/sum;
	local Y=light.g;


	--Y=(math.log(Y)-min_lum)/(max_lum-min_lum)
	Y=(Y-min_lum)/(max_lum-min_lum)
	--Y=math.exp(Y)

	--Y=math.max(Y,1e-12)
    --transform back to cieXYZ
    light.g=Y;
    local small_x = x;
    local small_y = y;
    light.r = light.g*(small_x / small_y);
    light.b = light.r / small_x - light.r - light.g;
    light.r=math.max(light.r,0)
    light.g=math.max(light.g,0)
    light.b=math.max(light.b,0)
    --[[
    if light.r<0 or light.r>1e6 then print("r:",light.r) end
    if light.g<0 or light.g>1e6 then print("g:",light.g) end
    if light.b<0 or light.b>1e6 then print("b:",light.b) end
    --]]
    --[[
    light.r=math.min(light.r,1e12)
    light.g=math.min(light.g,1e12)
    light.b=math.min(light.b,1e12)
    ]]
    return light;
end
function read_hd_png_buf( fname )
	local file = io.open(fname, 'rb')
	local b = bread(file:read('*all'))
	file:close()

	local sx=b:u32()
	local sy=b:u32()
	local chan_count = 4
	local do_log_norm=true
	local old_version=false
	if not old_version then
 		chan_count=b:u32()
 		do_log_norm=false --b:u32()
 		b:u32()
 	end
	local background_buf=make_flt_buffer(sx,sy)
	local background_minmax={}
	if chan_count>=3 then
		b:f32()
		background_minmax[1]=b:f32()
		b:f32()

		b:f32()
		background_minmax[2]=b:f32()
		b:f32()
	else
		background_minmax[1]=b:f32()
		background_minmax[2]=b:f32()
	end
	local lavg=b:f32()
	--local loc_avg=0
	--local count=0
	for x=0,background_buf.w-1 do
	for y=0,background_buf.h-1 do
		if chan_count==4 then
			local cr=b:f32()
			local cg=b:f32()
			local cb=b:f32()
			local a=b:f32()
			--if do_log_norm then
			--	background_buf:set(x,y,{math.log(cr+2.8),math.log(cg+2.8),math.log(cb+2.8),1})
			--else
				background_buf:set(x,y,{cr,cg,cb,1})
				--loc_avg=loc_avg+math.log(cg+2.8)
				--count=count+1
			--end
		else
			local v=b:f32()
			--v=background_minmax[2]-v
			background_buf:set(x,y,{v,v,v,1})
		end
	end
	end

	--loc_avg = math.exp(loc_avg / count);
	--print(loc_avg,lavg)
	if do_log_norm then
		background_minmax[1]=math.log(background_minmax[1]+2.8)
		background_minmax[2]=math.log(background_minmax[2]+2.8)
		lavg=math.log(lavg+2.8)
	end
	print("Loaded:",background_minmax[1],background_minmax[2])
	--[=[
	for x=0,background_buf.w-1 do
	for y=0,background_buf.h-1 do
		tonemap2(background_buf:get(x,y),background_minmax[1],background_minmax[2])
		--tonemap(background_buf:get(x,y),lavg)
		--[[
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
		--]]
	end
	end
	--]=]
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
--image_buf=read_hd_png_buf("sim_aneal.dat")
--]]
function safe_set_size( w,h )
	if STATE.size[1]~=w or STATE.size[2]~=h then
		__set_window_size(w,h)
	end
end
--safe_set_size(image_buf.w,image_buf.h)
--safe_set_size(1024,1024)
function resize( w,h )
	size=STATE.size
end
config=make_config({
	--{"blur",0,type="int"}, TODO
	{"iteration_step",0.001,type="floatsci",max=0.25},
	{"bulge_r",0.1,type="float",max=0.5},
	{"bulge_radius_offset",0,type="float",max=1},
	{"gamma",2.2,type="float",min=0.01,max=5},
	{"whitepoint",0.3,type="float",min=-0.01,max=1},
	{"exposure",1,type="floatsci",min=0.0001,max=1},
	{"temperature",6503.5,type="float",min=0.001,max=10000},
	{"image_is_intensity",true,type="boolean"},
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

function load_csv_pigments( path )
	local ret={}
	local sep=','

	local f=io.open(path,'r')
	local line=f:read("l")
	local first_line=true
	local names={}
	local wavelen=0
	while line do
		local id=1
		local pos=1
		while true do
			local startp,endp = string.find(line,sep,pos)
			if startp then
				local s=string.sub(line,pos,startp-1)
				if first_line then
					ret[s]={}
					--print("NAME:",s)
					table.insert(names,s)
				elseif id>1 then
					--print("INSERT:",names[id],s)
					table.insert(ret[names[id]],{wavelen,tonumber(s)})
				else
					wavelen=tonumber(s)
					--print("Wavelen:",wavelen)
				end
				pos = endp + 1
				id=id+1
			else
				local s=string.sub(line,pos)
				--print("END:",names[id],s)
				if first_line then
					ret[s]={}
					table.insert(names,s)
				else
					table.insert(ret[names[id]],{wavelen,tonumber(s)})
				end
				id=id+1
				break
			end
		end
		line=f:read("l")
		first_line=false
	end
	f:close()
	return ret
end
function tbl_min_max(tbl,min_v,max_v )
	min_v=min_v or math.huge
	max_v=max_v or -math.huge

	for k,v in pairs(tbl) do
		if min_v>v[2] then
			min_v=v[2]
		end
		if max_v<v[2] then
			max_v=v[2]
		end
	end
	return min_v,max_v
end
function normalize( tbl,min_v,max_v)
	for k,v in pairs(tbl) do
		tbl[k][2]=(v[2]-min_v)/(max_v-min_v)
	end
end
function load_csv_mie_pigment( path ,radius)
	local ret={{},{},{}}
	local sep=','

	local f=io.open(path,'r')
	local line=f:read("l")
 	line=f:read("l") --skip first line
	local wavelen=0
	while line do
		local id=1
		local pos=1
		while true do
			local startp,endp = string.find(line,sep,pos)
			if startp then
				local s=string.sub(line,pos,startp-1)
				if id==1 then
					wavelen=tonumber(s)
					--print("Wavelen:",wavelen)
				else
					--print("INSERT:",id,s)
					table.insert(ret[id-1],{wavelen,tonumber(s)})
				end
				pos = endp + 1
				id=id+1
			else
				local s=string.sub(line,pos)
				--print("END:",id,s)
				table.insert(ret[id-1],{wavelen,tonumber(s)})
				id=id+1
				break
			end
		end
		line=f:read("l")
	end
	f:close()
	--normalize the values
	--[[
	local min_v,max_v=tbl_min_max(ret[2])
	min_v,max_v=tbl_min_max(ret[2],min_v,max_v)

	normalize(ret[2],min_v,max_v)
	normalize(ret[3],min_v,max_v)
	--]]
	normalize(ret[2],0,math.pi*radius*radius*1e-18)
	normalize(ret[3],0,math.pi*radius*radius*1e-18)
	return ret
end
function add_mie_pigment(name,tbl_K,tbl_S,radius)
	local r=load_csv_mie_pigment("../assets/mie/"..name..".csv",radius)
	tbl_S[name]=r[2]
	tbl_K[name]=r[3]
end
function load_dat_mie_pigment( path )
	--source: https://saviot.cnrs.fr/mie/index.en.html
	local ret={{},{},{}}
	local f=io.open(path,'r')
	local f=io.open(path,'r')
	f:read("l")--skip first line
 	f:read("l")--skip second line
 	local wavelen=f:read("*n")
 	while wavelen do
 		for i=1,3 do
 			local v=f:read("*number")
 			if v<0.000001 then
 				v=0.0000001
 			end
 			table.insert(ret[i],{wavelen,v})
 		end
 		wavelen=f:read("*n")
 	end
 	return ret
end
function add_mie_pigment_dat( name,tbl_K,tbl_S )
	local r=load_dat_mie_pigment("../assets/mie/"..name..".dat")
	tbl_S[name]=r[2]
	tbl_K[name]=r[3]
end
local main_shader=shaders.Make[===[
#version 330
#line __LINE__
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
uniform float input_temp;
uniform float do_intensity;
uniform vec4 wave_reflect;
uniform vec2 pigment[7];


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
float D65_approx(float iter)
{
	//3rd order fit on D65
	float wl=mix(380,740,iter);
	//return (-1783+9.98*wl-(0.0171)*wl*wl+(9.51e-06)*wl*wl*wl)*1e12;
	return (-1783.1047729784+9.977734354*wl-(0.0171304983)*wl*wl+(0.0000095146)*wl*wl*wl);
}
float D65_blackbody(float iter,float temp)
{
	float wl=mix(380,740,iter);
	/*
	float mod=-5754+27.3*wl-0.043*wl*wl+(2.26e-05)*wl*wl*wl;
	return black_body(wl*1e-9,temp)-mod;
	*/
	//6th order poly fit on black_body/D65
	/*
	float mod=6443-67.8*wl*(
			1-0.004365781*wl*(
				1-(2.31e-3)*wl*(
					1-(1.29e-03)*wl*(
						1-(6.68e-04)*wl*(
							1-(2.84e-04)*wl
										)
									)
								)
						  	 )
						  	);
	*/
	//float mod=6443-67.8*wl+0.296*wl*wl-(6.84E-04)*wl*wl*wl+(8.84E-07)*wl*wl*wl*wl-
	//	6.06E-10*wl*wl*wl*wl*wl+1.72E-13*wl*wl*wl*wl*wl*wl;

	/*float mod=6449.3916465248
	+wl*(
		-67.868524542
		+wl*(0.2960426028
			+wl*((-0.0006846726)
				+wl*((8.852e-7)+
					wl*((-6e-10)+0*wl)
					)
				)
			)
		);

	return black_body(wl*1e-9,temp)*mod*1e-8;*/
	float b65=black_body(wl*1e-9,6503.5);
	return D65_approx(iter)*(black_body(wl*1e-9,temp)/b65);

}
vec2 tangent_distort(vec2 p,vec2 arg)
{
	float r=dot(p,p);
	float xy=p.x*p.y;

	return p+vec2(2*arg.x*xy+             arg.y*(r+2*p.x*p.x),
				    arg.x*(r+2*p.y*p.y)+2*arg.y*xy            );
}
vec2 distort_x(vec2 p,vec2 offset, float arg)
{
	float tx=p.x+offset.x;
	return p+vec2((tx*tx*tx)*arg,0);
}
vec2 distort_y(vec2 p,vec2 offset, float arg)
{
	float ty=p.y+offset.y;
	return p+vec2((ty*ty)*arg,0);
}
vec2 distort_y2(vec2 p,vec2 offset, float arg)
{
	float ty=p.y+offset.y;
	return p+vec2(0,(ty*ty*ty+ty)*arg);
}
vec2 rotate(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	mat2 m = mat2(c, -s, s, c);
	return m * v;
}
vec2 distort_spiral(vec2 p,vec2 offset,float arg)
{
	vec2 tp=p-offset;
	return rotate(tp,arg*3.1459*2)+offset;
}
float easeOutQuad(float x)
{
	return 1 - (1 - x) * (1 - x);
}
float easeInQuad(float x)
{
	return x*x;
}
float easyInOutQuad(float x)
{
	float p=(-2 * x + 2);
	p*=p;
	return x < 0.5 ? 2 * x * x : 1 - p / 2;
}
//how much the interference happens
//if v is int then it's 1 and if v-0.5 is int then it's 0
float interfere(float v )
{
	return abs((v-floor(v-0.5)-1)*2);
}
float interference_spectrum(float wavelen,float film_size,float angle)
{
	float n=1.4;// index of refraction for soapy water
	//10 nanometers to 1000 nm
	//float angle=light_angle*3.1459;
	float m=(2*n*(film_size)*cos(angle));
	float i=m/(wavelen*(740-380)+380);

	return interfere(i);
}
vec4 sample_22(vec2 pos)
{
	vec4 ret=vec4(0);
	float w=0.15;
	ret+=textureOffset(tex_main,pos,ivec2(1,1))*w;
	ret+=textureOffset(tex_main,pos,ivec2(-1,1))*w;
	ret+=textureOffset(tex_main,pos,ivec2(1,-1))*w;
	ret+=textureOffset(tex_main,pos,ivec2(-1,-1))*w;
	ret+=textureOffset(tex_main,pos,ivec2(0,0))*(1-4*w);
	return ret;
}
float cotangh(float v)
{
	return (exp(2*v)+1)/(exp(2*v)-1);
}
float reflectivity(float SX,float Rg,float Rinf)
{
	//SX is scatter*thickness
	//Rg reflectance of backing layer
	//Rinf reflectance of infinite layer of pigment
	float a=0.5*(1/Rinf+Rinf);
	float b=0.5*(1/Rinf-Rinf);
	float ctb=b*cotangh(b*SX);

	return (1-Rg*(a-ctb))/(a+ctb-Rg);
}
float kubelka_munk(vec2 val)
{
	float K=val.x;
	float S=val.y;
#if 1
	float KS=K/S;
 	return 1+KS-sqrt(KS*KS+2*KS);
#elif 0
 	//modified KM theory
 	float layer_size=0.1;
 	float temp=S+K-K*layer_size*S-K*K*layer_size*0.5;
 	float ret=0;
 	ret+=2*temp;
 	ret-=2*sqrt(temp*temp-S*S);
 	ret/=2*S;
 	return ret;
#else
	return (sqrt(2*K*S)-S)/(2*K-S);
#endif
}
//mixture of pigments
float mixture(vec2 v1,vec2 v2,float c1)
{
	vec2 r=mix(v1,v2,c1);
	return kubelka_munk(r);
}
//layering of pigments
float reflectivity_KS(vec2 v1,float height,float Rg)
{
	float k=v1.x;
	float s=v1.y;
	float R_inf=kubelka_munk(v1);
	if(height<0.00005)
		return Rg;
#if 0
	float eterm=exp(s*height*(1/R_inf-R_inf));
	float rterm=(Rg-1/R_inf);

	float ret=0;
	ret+=(Rg-R_inf)/R_inf;
	ret-=R_inf*rterm*eterm;
	ret/=(Rg-R_inf-rterm*eterm);
	return ret;
#else
	float a=0.5*(1/R_inf+R_inf);
	float b=0.5*(1/R_inf-R_inf);

	if(b*s*height>3)
		return R_inf;
	float bctg=b*cotangh(b*s*height);

	float top=1-Rg*(a-bctg);
	float bottom=a+bctg-Rg;
	return top/bottom;
#endif
}
vec3 permute(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }

float snoise(vec2 v){
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
           -0.577350269189626, 0.024390243902439);
  vec2 i  = floor(v + dot(v, C.yy) );
  vec2 x0 = v -   i + dot(i, C.xx);
  vec2 i1;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
  + i.x + vec3(0.0, i1.x, 1.0 ));
  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy),
    dot(x12.zw,x12.zw)), 0.0);
  m = m*m ;
  m = m*m ;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}
float sdBox( in vec2 p, in vec2 b )
{
    vec2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}
float sdSphere(in vec2 p,float s)
{
	return length(p)-s;
}
float sminCubic( float a, float b, float k )
{
    float h = max( k-abs(a-b), 0.0 )/k;
    return min( a, b ) - h*h*h*k*(1.0/6.0);
}
vec2 opRep( vec2 p, vec2 c )
{
    return mod(p,c)-0.5*c;
   // return mod(p,c) - 0.5 * c;
}
float mix_saturate(float v)
{
	float padding=0.2;
	float center=1-padding*2;
	return clamp((v-padding)*(1/center),0,1);
}

float saturate(float x)
{
	return clamp(x,0,1);
}
float mix3(float a,float b,float c,float v)
{
	float w0=fract(saturate(1-abs(v-0.0)*2));
	float w1=fract(saturate(1-abs(v-0.5)*2));
	float w2=fract(saturate(1-abs(v-1.0)*2));
	return w0*a+w1*b+w2*c;
}

float scene(vec2 pos)
{
#if 1
	//back is first pigment i.e. dark
	float back=kubelka_munk(pigment[0]);
#elif 0
	//second dark pigment
	float back=kubelka_munk(pigment[2]);
#elif 0
	//second light pigment
	float back=kubelka_munk(pigment[3]);
#else
	//back is second pigment i.e. light
	float back=kubelka_munk(pigment[1]);
#endif
	float id_f=(pos.y+1)/2;
	int id=int(id_f*7);
#if 0
	//pigments layerd on backing (with x increasing depth)
	float r=reflectivity_KS(pigment[id],(pos.x+1)*0.5,back);
#elif 1
	//mixed pigments
	float r=kubelka_munk(mix(pigment[0],pigment[id],(pos.x+1)*0.5));
#else
	//pure pigments
	float r=kubelka_munk(pigment[id]);
#endif
	return r;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec2 offset=vec2(0,0);
	vec2 dist_pos=pos.xy;
	//dist_pos=Distort(dist_pos,offset,barrel_power*iteration+1);
	//dist_pos=tangent_distort(dist_pos,vec2(barrel_power*iteration,barrel_power*iteration)*0.1);
	//dist_pos=distort_x(dist_pos,offset,barrel_power*iteration);
	//dist_pos=distort_y(dist_pos,offset,barrel_power*iteration);
	//dist_pos=distort_y2(dist_pos,offset,barrel_power*iteration);
	//dist_pos=distort_spiral(dist_pos,offset,barrel_power*iteration);
	dist_pos=(dist_pos+vec2(1))/2;


	float c=texture(tex_main,dist_pos*vec2(1,-1)).y;

	vec3 nv=texture(tex_main,dist_pos*vec2(1,-1)).xyz;


	float v=1-clamp(abs(length(pos.xy)-0.4)+0.6,0,1);

	vec3 ss;

	float scale_height=10;
	//vec3 h=vec3(v*scale_height);
	vec3 h=pow(nv,vec3(3))*scale_height;
	vec3 cnorm=clamp(nv*4,0,1);
	//h=clamp(h,0.01,100);
	float T=input_temp;
	//float T=5778;//Sun
	//float T=4500;
	//float T=8000;
	//float T=6503.6; //D65 illiuminant

	//nv.xyz=vec3(pos.xy+1,0)/2;
	float sw=0.05;
	/*
	float back_v=1-smoothstep(sw,-sw,
		//sminCubic(sdSphere(pos.xy,0.12),1-sdSphere(pos.xy,1),0.05)
		abs(sdSphere(pos.xy,0.6))-0.3
		);//smoothstep(-sw,sw,0.5-abs(pos.x))*smoothstep(-sw,sw,0.5-abs(pos.y));
	//*/
	//if(pos.x>0)
	//	back_v=1-back_v;
	/*float angle=atan(pos.y,pos.x)+M_PI;
	float back_v=cos(angle*3)*0.5+0.5;
	back_v*=cos(length(pos.xy)*16)*0.5+0.5;
	back_v=back_v*0.6+0.4;*/
	//back_v*=clamp(length(pos.xy),0,0.4)*2.5;
	/*
	//float back_v=0.8;
	float back=kubelka_munk(pigment[0])*back_v+
			   kubelka_munk(pigment[5])*(1-back_v);
	*/
	//vec2 back_ks=mix(pigment[0],pigment[1],back_v);
	//float back=reflectivity_KS(pigment[0],back_v*5,kubelka_munk(pigment[5]));
	//float back=kubelka_munk(back_ks);
	float back=kubelka_munk(pigment[0]);
	//float stripes=step(mod(normed.y+1/24.0,1/6.0),1/12.0)*0.4;
	//float back=kubelka_munk(mix(pigment[0],pigment[5],stripes));
	float vv=clamp(abs(pos.y)+0.1,0,1);//step((pos.x+pos.y)/2,0);
	//float vv=0;
	//float r=reflectivity(nv.x,reflectivity(nv.y,vv,wave_reflect.y),wave_reflect.x);
	//float r=mixture(pigment_K.z,pigment_K.w,pigment_S.z,pigment_S.w,v);
	//float r=reflectivity_KS(pigment_K.y,pigment_S.y,nv.x*2,kubelka_munk(pigment_K.x,pigment_S.x))*vv+
	//	mixture(pigment_K.x,pigment_K.y,pigment_S.x,pigment_S.y,nv.x)*(1-vv);
	//float r=reflectivity_KS(pigment_K.z,pigment_S.z,abs(pos.y*scale_height),back)*vv+
	//		reflectivity_KS(pigment_K.w,pigment_S.w,abs(pos.y*scale_height),back)*(1-vv);
	//float r=reflectivity_KS(pigment_K.w,pigment_S.w,h.y,
	//		reflectivity_KS(pigment_K.z,pigment_S.z,h.x,back));
	vec2 rect_size=vec2(1/4.0,1/6.0);
	vec2 mcoord=opRep(normed,rect_size);
	mcoord/=rect_size;
	mcoord+=vec2(0.5);
	vec2 icoord=floor(normed/rect_size);

	int p=int(icoord.x+icoord.y*4);

	/*
	float mix_v=clamp(c,0,1);
	float w_mix=0.5;
	vec2 p1=mix(pigment[1],pigment[3],smoothstep(-w_mix,w_mix,pos.x));
	vec2 p2=mix(pigment[2],pigment[4],smoothstep(-w_mix,w_mix,pos.y));

	vec2 mix_ks=mix(p1,p2,mix_v);
	
	//float r0=reflectivity_KS(p1,h.x,back);
	//float r=reflectivity_KS(p2,h.y,r0);

	float r0=reflectivity_KS(p1,pos.x+1,back);
	float r=reflectivity_KS(p2,pos.y+1,r0);

	//float mask=(1-smoothstep(-sw,sw,length(pos.xy)-0.8));
	//float r=kubelka_munk(mix_k,mix_s)*mask+back*(1-mask);
	//*/
	//float border=step(abs(pos.x)-0.9,0)*step(abs(pos.y)-0.9,0);
	//r=r*border+back*(1-border);
	float r=scene(pos.xy);
	if(do_intensity==1)
	{
		//float illuminant=black_body(iteration,T);
		//float illuminant=D65_approx(iteration);
		float illuminant=D65_blackbody(iteration,T);
		//if(pos.x>0)
			//illuminant=D65_blackbody(iteration,T);
		color.xyz=xyz_from_normed_waves(iteration)*illuminant*iteration_step*r;
	}
	else
	{
		//float illuminant=black_body(iteration,mix(6000,T,easyInOutQuad(c)));
		float illuminant=black_body(iteration,mix(0,T,c));
		color.xyz=xyz_from_normed_waves(iteration)*illuminant*iteration_step*r;
	}
	color.a=1;
}
]===]
local draw_shader=shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float iteration_step;
uniform vec3 min_v;
uniform vec3 max_v;
uniform float v_gamma;
uniform float whitepoint;
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
  return result;
}
float Tonemap_ACES(float x) {
    // Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}
float llog(float x)
{return log(x+2.8);}
vec3 eye_adapt_and_stuff(vec3 light)
{
	float lum_white = pow(10,whitepoint);
	//lum_white*=lum_white;

	//tocieYxy
	float sum=light.x+light.y+light.z;
	float x=light.x/sum;
	float y=light.y/sum;
	float Y=light.y;
	//Y=(llog(Y)-llog(min_v.y))/(llog(max_v.y)-llog(min_v.y));
	//Y=exp(Y);
	Y = (Y* exposure )/avg_lum;
#if 1
	if(whitepoint<0)
    	Y = Y / (1 + Y); //simple compression
	else
    	Y = (Y*(1 + Y / lum_white)) / (Y + 1); //allow to burn out bright areas
#else
    Y=Tonemap_ACES(Y);
#endif
    //transform back to cieXYZ
    light.y=Y;
    float small_x = x;
    float small_y = y;
    light.x = light.y*(small_x / small_y);
    light.z = light.x / small_x - light.x - light.y;

    return light*100;
}
void main()
{
	vec2 normed=(pos.xy*vec2(1,-1)+vec2(1,1))/2;
	color=texture(tex_main,normed);
	//color.xyz*=iteration_step;
	//color.xyz-=min_v;
	//color.xyz/=(max_v-min_v);
	//color.xyz/=max(max_v.x,max(max_v.y,max_v.z));//-min_v);
	//color.xyz/=max_v.x+max_v.y+max_v.z;


	//nv=gain(nv,v_gain);
	/*
	color.xyz*=exposure;
	color.xyz=xyz2rgb(color.xyz);

	*/
	//color.xyz=pow(color.xyz,vec3(1/2.2));
	//color.xyz*=exposure/(max(color.x,max(color.y,color.z)));
	color.xyz=eye_adapt_and_stuff(color.xyz);
	//color.xyz=xyz2rgb(color.xyz*exposure);
	color.xyz=pow(color.xyz,vec3(v_gamma));
	color.xyz=xyz2rgb(color.xyz);
	float s=smoothstep(1,8,dot(color.xyz,color.xyz));

    color.xyz=mix(color.xyz,vec3(1),s);
	//color.xyz=tonemapFilmic(color.xyz);

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
		local lum=math.abs(v.g)
		if lum<math.huge and lum>1 then
			avg_lum=avg_lum+math.log(2.8+lum)
			count=count+1
		end
	end
	end
	avg_lum = math.exp(avg_lum / count);
	print(avg_lum)
	for i,v in ipairs(lmax) do
		print(i,v)
	end
	return lmin,lmax,avg_lum
end
--lmin,lmax,avg_lum
local done
function sample_pigment(p, iter ,w)
	local w=w or 0.01
	local min_wl=380
	local max_wl=740

	local wl=iter*(max_wl-min_wl)+min_wl

	for i,v in ipairs(p) do
		if v[1]>wl then
			local before=p[i-1]
			local weight=(wl-before[1])/(v[1]-before[1])
			local ret=((1-weight)*before[2]+weight*v[2])*w
			--return math.max(math.min(ret,1),0)
			return ret
		end
	end
	return 0
end
function calculate_KS(p_base,p_powder,p_m,iter,c )
	--assume S_base=1
	local r_base=sample_pigment(p_base,iter)
	local k_base=(1-r_base)*(1-r_base)/(2*r_base)

	local r_mix=sample_pigment(p_m,iter)
	local r_pow=sample_pigment(p_powder,iter)


	local s=(k_base*(1-c)-r_mix*(1+c))/(c*(r_mix-r_pow))
	local k=r_pow*s
	return k,s
end
oil_part_volume={
	lampblaxk=0.75,
	rawumber=0.66,
	burntsienna=0.61,
	rawsienna=0.55,
	prussianblue=0.45,
	titaniumwhite=0.46
}
function calculate_KS_byname(name,iter)
	return calculate_KS(pigments_oil.Linseedoil,pigments[name],pigments_oil[name],iter,oil_part_volume[name])
end

function set_samples(  )
	pigment_inputs={
	"carbon_50",
	"TiO2_50",
	--"carbon_500",
	--"TiO2_500",
	"arylide_yellow",
	"gold_50",
	--"gold_75",
	--"gold_100",
	"Cu50",
	"Fe2O3_50",
	"Cu100",
	--"Al2O3",

}
	local names={}
	for k,v in pairs(pigments_K) do
		if k~="A"
			and k~="titanium_white" and k~="bone_black"
			then
			table.insert(names,k)
		end
	end
	--nice mix: phathlo_green_blue_shade & cadmium_orange
	--[[
	for i=2,5 do
		local n=names[math.random(1,#names)]
		pigment_inputs[i]=n
	end
	--]]
	for i=1,7 do
		print(i,pigment_inputs[i])
	end
end
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
		--image_buf:write_texture(con_tex)
		main_shader:set_i("tex_main",0)
		main_shader:set("barrel_power",config.bulge_r);
		main_shader:set("barrel_offset",config.bulge_radius_offset)
		main_shader:set("v_gamma",config.gamma)
		main_shader:set("whitepoint",config.whitepoint)
		main_shader:set("iteration",iteration)
		main_shader:set("iteration_step",config.iteration_step)
		if pigments_K then
			if pigment_inputs==nil then
				set_samples()
			end
			--[[local sample_pigments={
				"prussianblue",
				"burntsienna",
				"titaniumwhite",
				"rawumber"
			}
			local w={}
			local K={}
			local S={}
			for i=1,4 do
				local name=sample_pigments[i]
				w[i]=sample_pigment(pigments[name],iteration)
				local k,s=calculate_KS_byname(name,iteration)
				K[i]=k
				S[i]=s
			end

			main_shader:set("wave_reflect",unpack(w))
			]]

			local K={}
			local S={}
			for i=1,7 do
				local name=pigment_inputs[i]
				K[i]=sample_pigment(pigments_K[name],iteration,1)
				S[i]=sample_pigment(pigments_S[name],iteration,1)
			end
			--print(iteration,K[1],S[1])
			for i,v in ipairs(K) do
				main_shader:set("pigment[".. (i-1) .."]",K[i],S[i])
			end
		end
		if config.image_is_intensity then
			main_shader:set("do_intensity",1)
		else
			main_shader:set("do_intensity",0)
		end
		main_shader:set("input_temp",config.temperature)
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

	if imgui.Button("snap max") or lmin==nil --[[or (not done and iteration>1)]]then
		lmin,lmax,avg_lum=find_min_max()
		done=true
	end
	imgui.SameLine()
	imgui.Text(string.format("Done:%g",iteration))
	draw_shader:use()
	compute_tex.t:use(0)
	draw_shader:set_i("tex_main",0)
	draw_shader:set("iteration_step",config.iteration_step)
	draw_shader:set("iteration_step",config.iteration_step)
	draw_shader:set("min_v",lmin[1],lmin[2],lmin[3])
	draw_shader:set("max_v",lmax[1],lmax[2],lmax[3])
	draw_shader:set("v_gamma",config.gamma)
	draw_shader:set("whitepoint",config.whitepoint)
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
	imgui.SameLine()
	if imgui.Button("rand pigments") then
		set_samples()
	end
	if imgui.Button("Load CSV") then
		--pigments_oil=load_csv_pigments("../assets/FORS spectra/linseed oil.csv")
		--pigments=load_csv_pigments("../assets/FORS spectra/powder.csv")

		pigments_K=load_csv_pigments("../assets/Artist Paint Spectral Database/k_values.csv")
		pigments_S=load_csv_pigments("../assets/Artist Paint Spectral Database/s_values.csv")

		--add_mie_pigment("gold_75",pigments_K,pigments_S,75)
		--add_mie_pigment("gold_50",pigments_K,pigments_S,50)
		local mie_dats={
			"carbon_50",
			"carbon_500",
			"TiO2_50",
			"TiO2_500",
			"gold_50",
			"gold_75",
			"gold_100",
			"Cu50",
			"Cu100",
			"Fe2O3_50",
			"Fe2O3_100",
			"Al2O3",
		}
		for i,v in ipairs(mie_dats) do
			add_mie_pigment_dat(v,pigments_K,pigments_S)
		end
	end
	imgui.End()

end
