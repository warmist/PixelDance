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
    * https://iquilezles.org/articles/morenoise/
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
  visit_tex=textures:Make()
  visit_tex:use(0)
  visit_tex:set(win_w,win_h,1)
end
if win_w==nil then
  update_size()
end

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
uniform vec3 seed;
uniform vec3 seed2;
uniform mat4 view_mat;
uniform vec2 rez;
in vec3 pos;
out vec4 color;
#define MAX_ITER 300
#define M_PI 3.14159
float hash(vec3 p)  // replace this by something better
{
    p  = 50.0*fract( p*0.3183099 + vec3(0.71,0.113,0.419));
    return -1.0+2.0*fract( p.x*p.y*p.z*(p.x+p.y+p.z) );
}
// returns 3D value noise and its 3 derivatives
 vec4 noised( in vec3 x )
 {
    vec3 p = floor(x);
    vec3 w = fract(x);

    vec3 u = w*w*w*(w*(w*6.0-15.0)+10.0);
    vec3 du = 30.0*w*w*(w*(w-2.0)+1.0);

    float a = hash( p+vec3(0,0,0) );
    float b = hash( p+vec3(1,0,0) );
    float c = hash( p+vec3(0,1,0) );
    float d = hash( p+vec3(1,1,0) );
    float e = hash( p+vec3(0,0,1) );
    float f = hash( p+vec3(1,0,1) );
    float g = hash( p+vec3(0,1,1) );
    float h = hash( p+vec3(1,1,1) );

    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return vec4( -1.0+2.0*(k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z),
                 2.0* du * vec3( k1 + k4*u.y + k6*u.z + k7*u.y*u.z,
                                 k2 + k5*u.z + k4*u.x + k7*u.z*u.x,
                                 k3 + k6*u.x + k5*u.y + k7*u.x*u.y ) );
}
const mat3 m3  = mat3( 0.00,  0.80,  0.60,
                      -0.80,  0.36, -0.48,
                      -0.60, -0.48,  0.64 );
const mat3 m3i = mat3( 0.00, -0.80, -0.60,
                       0.80,  0.36, -0.48,
                       0.60, -0.48,  0.64 );
// returns 3D fbm and its 3 derivatives
vec4 fbm( in vec3 x, int octaves )
{
    float f = 1.98;  // could be 2.0
    float s = 0.49;  // could be 0.5
    float a = 0.0;
    float b = 0.5;
    vec3  d = vec3(0.0);
    mat3  m = mat3(1.0,0.0,0.0,
    0.0,1.0,0.0,
    0.0,0.0,1.0);
    for( int i=0; i < octaves; i++ )
    {
        vec4 n = noised(x);
        a += b*n.x;          // accumulate values
        d += b*m*n.yzw;      // accumulate derivatives
        b *= s;
        x = f*m3*x;
        m = f*m3i*m;
    }
    return vec4( a, d );
}

float rand(vec2 c){
  return fract(sin(dot(c.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

//  Simplex 3D Noise 
//  by Ian McEwan, Ashima Arts
//
vec4 permute(vec4 x){return mod(((x*34.0)+1.0)*x, 289.0);}
vec4 taylorInvSqrt(vec4 r){return 1.79284291400159 - 0.85373472095314 * r;}

float snoise(vec3 v){ 
  const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
  const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

// First corner
  vec3 i  = floor(v + dot(v, C.yyy) );
  vec3 x0 =   v - i + dot(i, C.xxx) ;

// Other corners
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min( g.xyz, l.zxy );
  vec3 i2 = max( g.xyz, l.zxy );

  //  x0 = x0 - 0. + 0.0 * C 
  vec3 x1 = x0 - i1 + 1.0 * C.xxx;
  vec3 x2 = x0 - i2 + 2.0 * C.xxx;
  vec3 x3 = x0 - 1. + 3.0 * C.xxx;

// Permutations
  i = mod(i, 289.0 ); 
  vec4 p = permute( permute( permute( 
             i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0 )) 
           + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

// Gradients
// ( N*N points uniformly over a square, mapped onto an octahedron.)
  float n_ = 1.0/7.0; // N=7
  vec3  ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z *ns.z);  //  mod(p,N*N)

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = y_ *ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4( x.xy, y.xy );
  vec4 b1 = vec4( x.zw, y.zw );

  vec4 s0 = floor(b0)*2.0 + 1.0;
  vec4 s1 = floor(b1)*2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
  vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

  vec3 p0 = vec3(a0.xy,h.x);
  vec3 p1 = vec3(a0.zw,h.y);
  vec3 p2 = vec3(a1.xy,h.z);
  vec3 p3 = vec3(a1.zw,h.w);

//Normalise gradients
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

// Mix final noise value
  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1), 
                                dot(p2,x2), dot(p3,x3) ) );
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}
vec4 sdSphere(vec3 p,float radius)
{
  return vec4(length(p)-radius,p);
}
vec4 sdHalfPlane(float p)
{
  return vec4(p,1,0,0);
}
vec4 maxd(vec4 v1,vec4 v2)
{
  return (v1.x>v2.x)?v1:v2;
}
vec4 mind(vec4 v1,vec4 v2)
{
  return (v1.x<v2.x)?v1:v2;
}
vec4 map_d(vec3 p)
{
  float sn=snoise(p*16);
  //vec4 d1=fbm(p*4,4);
  //d1.x-=0.4;
  //d1.x*=0.5;

  vec4 s1=sdSphere(p,1);
  vec4 h1=sdHalfPlane(p.x*(1+sn*0.05)+0.5);

  vec4 s2=sdSphere(p,1);
  vec4 h2=sdHalfPlane(-p.x*(1+sn*0.05)-0.4);



  return mind(maxd(s1,h1),maxd(s2,h2));
  //return maxd(s1,h1);

  //if(d2.x>1)
  //  return d2;

  ///*
  
  //d1.x*=1.5;
  //d1.x-=0.35;
  //d1.x*=0.5;
  //*/
  //vec4 d1=sdSphere(p-vec3(0.5,0,0),1);

  //return (d1.x>d2.x)?d1:d2;
  //return d2;
}

vec3 calcNormal( in vec3 p ) // for function map(p)
{
    const float eps = 0.0001; // or some other value
    const vec2 h = vec2(eps,0);
    return normalize( vec3(map_d(p+h.xyy).x - map_d(p-h.xyy).x,
                           map_d(p+h.yxy).x - map_d(p-h.yxy).x,
                           map_d(p+h.yyx).x - map_d(p-h.yyx).x ) );
}

vec2 shoot_ray(vec3 ro,vec3 rd,out vec3 pnorm,out vec3 pos)
{
  float t_min=0.01;
  float tmax=300;

  float t=t_min;
  vec4 hit;

  /*
  vec3 L=vec3(0)-ro;
  float tc=dot(L,rd);
  if(tc<0)
    return vec2(0,0);
  float d=sqrt(dot(L,L)-tc*tc);
  if(d<0 || d>1)
    return vec2(0,0);
  */
  for(int i=0;i<MAX_ITER;i++)
  {
    hit=map_d(ro+t*rd);
    if(abs(hit.x)<0.0001)
    {
      pos=ro+t*rd;
      //pnorm=normalize(hit.yzw);
      pnorm=calcNormal(pos);
      break;
    }
    t+=hit.x;
    if(t>tmax)
      break;
    //count=i;
  }
  if(t>tmax)
    return vec2(0,0);

  return vec2(t,1);
}
vec3 rnd_spherical(vec2 s)
{
  float phi=rand(s);
  float theta=rand(s.yx);
  return vec3(sin(phi)*cos(theta),sin(phi)*sin(theta),cos(theta));
}
vec3 rnd_half_spherical(vec2 s)
{
  float phi=rand(s);
  float theta=rand(s.yx);
  return vec3(sin(phi)*cos(theta),sin(phi)*sin(theta),abs(cos(theta)));
}
vec3 forwardSF( float i, float n) 
{
    const float PI  = 3.141592653589793238;
    const float PHI = 1.618033988749894848;
    float phi = 2.0*PI*fract(i/PHI);
    float zi = 1.0 - (2.0*i+1.0)/n;
    float sinTheta = sqrt( 1.0 - zi*zi);
    return vec3( cos(phi)*sinTheta, sin(phi)*sinTheta, zi);
}

void main(){
  vec2 aapos=pos.xy;
  aapos+=(2*rand(seed.xy)-1)/rez;
  //vec3 light_dir=normalize(vec3(0,0.4,0.8));
  vec3 light_pos=vec3(cos(time),sin(time),3)*10;
  vec3 l_pos_perturbed=light_pos+rnd_spherical(vec2(seed.xy))*5;

  vec3 light_dir=normalize(l_pos_perturbed);
  vec3 view_origin=vec3(cos(time),sin(time),0.5)*7;
  vec3 view_at=vec3(0,0,0);

  vec3 up_vector=normalize(vec3(0,1,1));
  float fov=0.5*40/M_PI;

  vec3 view_dir=normalize(view_at-view_origin);
  vec3 x_dir=cross(view_dir,up_vector);
  vec3 y_dir=up_vector;
  //STUPID way of doing view_dir

  vec3 view_center=view_origin+view_dir*3;
  vec3 col_accum=vec3(0);
  //int sample_count=5;
  //for(int i=0;i<sample_count;i++)
  {
    vec3 ray_direction=normalize(view_center+x_dir*aapos.x+y_dir*aapos.y-view_origin);
    //vec3 ray_direction=normalize(view_center+x_dir*cos(pos.x*fov)+y_dir*sin(pos.y*fov)-view_origin);
    vec3 n;
    vec3 hit_pos;
    vec2 rez=shoot_ray(view_origin,ray_direction,n,hit_pos);

    float light_v=max(dot(n,light_dir),0);
    if(rez.y>0)
    {
      vec3 nn;
      vec3 htpos;
      //hit_pos=hit_pos+n*0.01;//move away from surf

      vec2 h2=shoot_ray(l_pos_perturbed,normalize(hit_pos-l_pos_perturbed),nn,htpos);
      if(h2.y>0)
      {
        light_v*=max(dot(nn,light_dir),0);
      }
      else
        light_v*=0;
    }
    light_v=clamp(light_v,0,1);
    vec3 background=vec3(0.4,0,0.8)*1;
    vec3 color_main=vec3(1,1,1);
    col_accum+=mix(background,mix(background*0.0,color_main,light_v),rez.y);
  }
  color=vec4(col_accum,1);
}
]==])
time=time or 0
function integrate(  )
  shoot_rays:use()
  shoot_rays:blend_add()
  shoot_rays:set("rez",size[1],size[2])
  shoot_rays:set("time",time);
  shoot_rays:set("seed",math.random(),math.random(),math.random());
  shoot_rays:set("seed2",math.random(),math.random(),math.random());
  if not visit_tex:render_to(win_w,win_h) then
      error("failed to set framebuffer up")
  end
  if need_clear then
    __clear()
    need_clear=nil
  end
  shoot_rays:draw_quad()
  __render_to_window()
  shoot_rays:blend_default()
end
display_shader=shaders.Make(
[==[
#version 330
#line 246
uniform float multiplier;
in vec3 pos;
out vec4 color;
uniform sampler2D tex_main;

void main(){
  vec2 normed=(pos.xy+vec2(1,1))/2;
  vec3 rl_col=texture(tex_main,normed).xyz*multiplier;
  //rl_col=pow(rl_col,vec3(1/2.4));
  color=vec4(rl_col,1);
}
]==])
local counter=0
local max_counter=500
function display( ... )
  display_shader:use()
  visit_tex:use(0)
  display_shader:set("multiplier",1/counter)
  display_shader:set_i("tex_main",0)
  display_shader:draw_quad()

end
need_clear=true
function update(  )
  --time=3
  __clear()
  __no_redraw()
  __render_to_window()
  display()
  if counter<max_counter then
    counter=counter+1
    integrate()
  else
    --need_clear=true
    --time=time+0.01
    --integrate()
    --counter=1
  end
end