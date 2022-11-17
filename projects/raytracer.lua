require "common"
require "colors" 
--[[
	add some diffusion to the rays (i.e how fluid sims do) thus getting something blurry?
	Inspirations:
		* https://www.reddit.com/r/generative/comments/yq9zyu/proper_displacement_in_my_raymarcher/
		* https://imgur.com/gallery/NrphmDk
	Resources:
		* https://iquilezles.org/articles/normalsSDF/
		* https://gist.github.com/patriciogonzalezvivo/670c22f3966e662d2f83
]]
local luv=require "colors_luv"
local bwrite = require "blobwriter"
local bread = require "blobreader"

local size_mult=1
local size=STATE.size
local win_w
local win_h
local aspect_ratio

local accum_buffers=accum_buffers or multi_texture(size[1],size[2],2,FLTA_PIX)

function update_size(  )
	win_w=1280*size_mult
	win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
update_size()

img_buf=make_image_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	accum_buffers:update_size(w,h)
end

shoot_rays=shaders.Make(
[==[
#version 330
#line 40
uniform float time;
uniform mat4 view_mat;
uniform vec2 rez;
in vec3 pos;
out vec4 color;
#define MAX_ITER 100
#define M_PI 3.14159

float rand(vec2 c){
	return fract(sin(dot(c.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

//	Classic Perlin 3D Noise 
//	by Stefan Gustavson
//
vec4 permute(vec4 x){return mod(((x*34.0)+1.0)*x, 289.0);}
vec4 taylorInvSqrt(vec4 r){return 1.79284291400159 - 0.85373472095314 * r;}
vec3 fade(vec3 t) {return t*t*t*(t*(t*6.0-15.0)+10.0);}

float cnoise(vec3 P){
  vec3 Pi0 = floor(P); // Integer part for indexing
  vec3 Pi1 = Pi0 + vec3(1.0); // Integer part + 1
  Pi0 = mod(Pi0, 289.0);
  Pi1 = mod(Pi1, 289.0);
  vec3 Pf0 = fract(P); // Fractional part for interpolation
  vec3 Pf1 = Pf0 - vec3(1.0); // Fractional part - 1.0
  vec4 ix = vec4(Pi0.x, Pi1.x, Pi0.x, Pi1.x);
  vec4 iy = vec4(Pi0.yy, Pi1.yy);
  vec4 iz0 = Pi0.zzzz;
  vec4 iz1 = Pi1.zzzz;

  vec4 ixy = permute(permute(ix) + iy);
  vec4 ixy0 = permute(ixy + iz0);
  vec4 ixy1 = permute(ixy + iz1);

  vec4 gx0 = ixy0 / 7.0;
  vec4 gy0 = fract(floor(gx0) / 7.0) - 0.5;
  gx0 = fract(gx0);
  vec4 gz0 = vec4(0.5) - abs(gx0) - abs(gy0);
  vec4 sz0 = step(gz0, vec4(0.0));
  gx0 -= sz0 * (step(0.0, gx0) - 0.5);
  gy0 -= sz0 * (step(0.0, gy0) - 0.5);

  vec4 gx1 = ixy1 / 7.0;
  vec4 gy1 = fract(floor(gx1) / 7.0) - 0.5;
  gx1 = fract(gx1);
  vec4 gz1 = vec4(0.5) - abs(gx1) - abs(gy1);
  vec4 sz1 = step(gz1, vec4(0.0));
  gx1 -= sz1 * (step(0.0, gx1) - 0.5);
  gy1 -= sz1 * (step(0.0, gy1) - 0.5);

  vec3 g000 = vec3(gx0.x,gy0.x,gz0.x);
  vec3 g100 = vec3(gx0.y,gy0.y,gz0.y);
  vec3 g010 = vec3(gx0.z,gy0.z,gz0.z);
  vec3 g110 = vec3(gx0.w,gy0.w,gz0.w);
  vec3 g001 = vec3(gx1.x,gy1.x,gz1.x);
  vec3 g101 = vec3(gx1.y,gy1.y,gz1.y);
  vec3 g011 = vec3(gx1.z,gy1.z,gz1.z);
  vec3 g111 = vec3(gx1.w,gy1.w,gz1.w);

  vec4 norm0 = taylorInvSqrt(vec4(dot(g000, g000), dot(g010, g010), dot(g100, g100), dot(g110, g110)));
  g000 *= norm0.x;
  g010 *= norm0.y;
  g100 *= norm0.z;
  g110 *= norm0.w;
  vec4 norm1 = taylorInvSqrt(vec4(dot(g001, g001), dot(g011, g011), dot(g101, g101), dot(g111, g111)));
  g001 *= norm1.x;
  g011 *= norm1.y;
  g101 *= norm1.z;
  g111 *= norm1.w;

  float n000 = dot(g000, Pf0);
  float n100 = dot(g100, vec3(Pf1.x, Pf0.yz));
  float n010 = dot(g010, vec3(Pf0.x, Pf1.y, Pf0.z));
  float n110 = dot(g110, vec3(Pf1.xy, Pf0.z));
  float n001 = dot(g001, vec3(Pf0.xy, Pf1.z));
  float n101 = dot(g101, vec3(Pf1.x, Pf0.y, Pf1.z));
  float n011 = dot(g011, vec3(Pf0.x, Pf1.yz));
  float n111 = dot(g111, Pf1);

  vec3 fade_xyz = fade(Pf0);
  vec4 n_z = mix(vec4(n000, n100, n010, n110), vec4(n001, n101, n011, n111), fade_xyz.z);
  vec2 n_yz = mix(n_z.xy, n_z.zw, fade_xyz.y);
  float n_xyz = mix(n_yz.x, n_yz.y, fade_xyz.x); 
  return 2.2 * n_xyz;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}
vec2 map(vec3 pos) //returns distance and material
{
	return vec2(sdBox(pos+cnoise(pos.xyz*8)*0.125,vec3(1,1,1)),1);
	//return vec2(length(pos)-1,1);
}
vec3 calcNormal( in vec3 p ) // for function map(p)
{
    const float eps = 0.00001; // or some other value
    const vec2 h = vec2(eps,0);
    return normalize( vec3(map(p+h.xyy).x - map(p-h.xyy).x,
                           map(p+h.yxy).x - map(p-h.yxy).x,
                           map(p+h.yyx).x - map(p-h.yyx).x ) );
}
vec2 shoot_ray(vec3 ro,vec3 rd,out vec3 pnorm,out vec3 pos)
{
	float t_min=0.01;
	float tmax=300;
	float t=t_min;
	vec2 hit;
	for(int i=0;i<MAX_ITER;i++)
	{
		hit=map(ro+t*rd);
		if(abs(hit.x)<0.001 || t>tmax)
		{
			pos=ro+t*rd;
			pnorm=calcNormal(pos);
			break;
		}
		t+=hit.x;
		//count=i;
	}
	if(t>tmax)
		return vec2(0,0);

	return vec2(t,hit.y);
}

void main(){

	//vec3 light_dir=normalize(vec3(0,0.4,0.8));
	vec3 light_pos=vec3(cos(time),sin(time),1.2)*20;
	vec3 light_dir=normalize(light_pos);
	vec3 view_origin=vec3(cos(time),sin(time),0.5)*10;
	vec3 view_at=vec3(0,0,0);

	vec3 up_vector=vec3(0,0,1);
	float fov=0.5*40/M_PI;

	vec3 view_dir=normalize(view_at-view_origin);
	vec3 x_dir=cross(view_dir,up_vector);
	vec3 y_dir=up_vector;
	//STUPID way of doing view_dir

	vec3 view_center=view_origin+view_dir*2;
	vec3 col_accum=vec3(0);
	int sample_count=5;
	for(int i=0;i<sample_count;i++)
	{
		vec3 ray_direction=normalize(view_center+x_dir*pos.x+y_dir*pos.y-view_origin+rand(vec2(i*0.02,0))*0.001);
		//vec3 ray_direction=normalize(view_center+x_dir*cos(pos.x*fov)+y_dir*sin(pos.y*fov)-view_origin);
		vec3 n;
		vec3 hit_pos;
		vec2 rez=shoot_ray(view_origin,ray_direction,n,hit_pos);

		float light_v=max(dot(n,light_dir),0.1);
		if(rez.y>0)
		{
			vec3 nn;
			vec3 htpos;
			//hit_pos=hit_pos+n*0.01;//move away from surf
			vec2 h2=shoot_ray(light_pos,normalize(hit_pos+n*0.001-light_pos),nn,htpos);
			if(h2.y>0 && length(htpos-hit_pos)>0.001)
			{
				light_v*=0.3;
			}
		}

		vec3 background=vec3(0.4,0,0.8);
		vec3 color_main=vec3(1,1,1);
		col_accum+=mix(background,color_main*light_v,rez.y);
	}
	color=vec4(col_accum/sample_count,1);
}
]==])
time=time or 0
function integrate(  )
	shoot_rays:use()
	shoot_rays:set("rez",size[1],size[2])
	shoot_rays:set("time",time);
	shoot_rays:draw_quad()
end
function update(  )
    __clear()
    __no_redraw()
    __render_to_window()
	integrate()
	time=time+0.001
end