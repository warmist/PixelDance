--[===[
a vector field which are spinning. Ideas:
    * perturb locations and weight by distances
    * symetric rotor positions
    * other math objects (e.g. spinors,quaternions etc...)
--]===]
require 'common'
require 'bit'

local win_w=1024
local win_h=1024

__set_window_size(win_w,win_h)
local oversample=1/1

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size

is_remade=false

local agent_count=10000

function update_buffers()
    if vector_layer==nil or vector_layer.w~=map_w or vector_layer.h~=map_h then

        vector_layer=make_flt_buffer(map_w,map_h) --current rotation(s)
        speed_layer=make_flt_buffer(map_w,map_h) --x - speed, y - mix(avg_neighthours, cur_angle+speed)
        trails_layer=make_flt_buffer(map_w,map_h) --color of pixels that are moving around

        is_remade=true
        need_clear=true
    end
    if agent_color==nil or agent_color.w~=agent_count then
        agent_color=make_flt_buffer(agent_count,1) --color of pixels that are moving around
        agent_state=make_flt_buffer(agent_count,1) --position and <other stuff>
    end
end
update_buffers()


config=make_config({
    {"pause",false,type="bool"},
    {"pause_particles",true,type="bool"},
    {"show_particles",false,type="bool"},
    {"sim_ticks",50,type="int",min=0,max=10},
    {"speed",0.1,type="floatsci",min=0,max=1,power=10},
    {"speedz",0.1,type="floatsci",min=0,max=1,power=10},
    {"particle_opacity",0.01,type="floatsci",min=0,max=1,power=10},
    {"particle_reset_iter",1000,type="int",min=0,max=10000},
    {"particle_wait_iter",100,type="int",min=0,max=10000},
    {"gamma",1,type="floatsci",min=0.5,max=2,power=0.5},
    },config)


local draw_shader=shaders.Make(
[==[
#version 330
#line 47
out vec4 color;
in vec3 pos;

uniform ivec2 res;
uniform sampler2D tex_main;
uniform int draw_particles;

uniform float v_gamma;
uniform vec3 col_min,col_max,col_avg;

float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}

vec3 rgb2xyz( vec3 c ) {
    vec3 tmp=c;
    /*
    tmp.x = ( c.r > 0.04045 ) ? pow( ( c.r + 0.055 ) / 1.055, 2.4 ) : c.r / 12.92;
    tmp.y = ( c.g > 0.04045 ) ? pow( ( c.g + 0.055 ) / 1.055, 2.4 ) : c.g / 12.92,
    tmp.z = ( c.b > 0.04045 ) ? pow( ( c.b + 0.055 ) / 1.055, 2.4 ) : c.b / 12.92;
    */
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
//http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
//TODO: works bad when out of bounds
vec3 xyz2rgb( vec3 c ) {
    vec3 v =  c / 100.0 * mat3(
        3.2406255, -1.5372080, -0.4986286,
        -0.9689307, 1.8757561, 0.0415175,
        0.0557101, -0.2040211, 1.0569959
    );
    vec3 r;
    r=v;
    /* srgb conversion
    r.x = ( v.r > 0.0031308 ) ? (( 1.055 * pow( v.r, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.r;
    r.y = ( v.g > 0.0031308 ) ? (( 1.055 * pow( v.g, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.g;
    r.z = ( v.b > 0.0031308 ) ? (( 1.055 * pow( v.b, ( 1.0 / 2.4 ))) - 0.055 ) : 12.92 * v.b;
    //*/
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

vec3 tonemap(vec3 light,float cur_exp)
{
    float white_point=10;
    float lum_white =white_point*white_point;// pow(10,white_point);
    //lum_white*=lum_white;
    float Y=light.y;
    float avg_lum=1;
#if SHOW_PALETTE
    Y=Y*exp(cur_exp)/(9.6);
#else
    Y=Y*exp(cur_exp)/(avg_lum);
#endif
    //Y=Y*exp(cur_exp);
    //Y=(Y-min_max.x)/(min_max.y-min_max.x);
    //Y=(log(Y+1)-log(min_max.x+1))/(log(min_max.y+1)-log(min_max.x+1));
    //Y=log(Y+1)/log(min_max.y+1);
#if 0
    //Y=Tonemap_Uchimura(Y);
    Y=Tonemap_ACES(Y);
#else
    if(white_point<0)
        Y = Y / (1 + Y); //simple compression
    else
        Y = (Y*(1 + Y / lum_white)) / (Y + 1); //allow to burn out bright areas
#endif

    float m=Y/light.y;
    light.y=Y;
    light.xz*=m;

    //light=clamp(light,0,2);
    //float mm=max(light.x,max(light.y,light.z));
    //vec3 ret=xyz2rgb((light)*100);
    //float s=smoothstep(0,1,length(light));
    //float s=smoothstep(0,1,dot(light,light));
    //float s=smoothstep(0,1,max(light.x,max(light.y,light.z)));//length(light));
    //float s=smoothstep(0.8,1.2,max(light.x,max(light.y,light.z))-1);//length(light));
    //float s=0;
    /*
    if(ret.x>1)ret.x=1;
    if(ret.y>1)ret.y=1;
    if(ret.z>1)ret.z=1;
    //*/
   // return mix(ret,vec3(1),pow(s,8));
    return light;
}

vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
vec4 calc_vector_image(vec2 normed)
{
    vec4 color;
    vec4 pixel=texture(tex_main,normed);
    vec3 c=pixel.xyz;//(pixel.xyz/3.14+1)/2;
    //c=clamp(c,0,1);
    float p=1;
    //c.x=c.x-c.y;
    //c.x=c.y;
    if(c.x>0)
        c.x=pow(abs(c.x),p);
    else
        c.x=-pow(abs(c.x),p);
    vec2 fvec=vec2(cos(c.x),sin(c.x));
#if 0
    //gradient
    vec2 grad=vec2(dFdx(fvec.x),dFdy(fvec.y));
    float grad_offset=0.5;
    grad=(grad+grad_offset)/2;
    //fvec=grad*10000;
    color=vec4(grad.xy,0,1);
#elif 0
    //divergence
    vec2 grad=vec2(dFdx(fvec.x),dFdy(fvec.y));
    float grad_offset=0.05;
    grad=(grad+grad_offset)/2;
    color=vec4(grad.x+grad.y,0,0,1);
#elif 0
    //curl:
    float curl=dFdx(fvec.y)-dFdy(fvec.x);
    //curl=curl/2+0.5;
    color=vec4(curl*10,fvec.xy*0,1);
#elif 1
    //float pa=c.x/3.145926;
    float pa=cos(c.x)/2+0.5;
    float pa2=cos(c.y)/2+0.5;
    //vec3 co=palette(pa,vec3(0.5),vec3(0.5),vec3(1),vec3(0.0,0.33,0.67));
    //vec3 co=palette(pa,vec3(0.8,0.5,0.4),vec3(0.2,0.4,0.2),vec3(2,1,1),vec3(0.0,0.25,0.25));
    vec3 co=palette(pa,vec3(0.2,0.7,0.4),vec3(0.6,0.9,0.2),vec3(0.6,0.8,0.7),vec3(0.5,0.1,0.0));
    //vec3 co=palette(pa,vec3(0.5),vec3(0.5),vec3(0.6,0.6,0.2),vec3(0.1,0.7,0.3));
    //vec3 co=palette(pa,vec3(0.5),vec3(0.5),vec3(0.33,0.4,0.7),vec3(0.5,0.12,0.8));
    //vec3 co=palette(pa,vec3(0.5),vec3(0.5),vec3(0.5),vec3(0.5));
    //vec3 co=palette(pa,vec3(0.999032,0.259156,0.217277),vec3(0.864574,0.440455,0.0905941),vec3(0.333333,0.4,0.333333),vec3(0.111111,0.2,0.1)); //Dark red/orange stuff
    //vec3 co=palette(pa,vec3(0.884088,0.4138,0.538347),vec3(0.844537,0.95481,0.818469),vec3(0.875,0.875,1),vec3(3,1.5,1.5)); //white and dark and blue very nice
    //vec3 co=palette(pa,vec3(0.971519,0.273919,0.310136),vec3(0.90608,0.488869,0.144119),vec3(5,10,2),vec3(1,1.8,1.28571)); //violet and blue
    //vec3 co=palette(pa,vec3(0.960562,0.947071,0.886345),vec3(0.850642,0.990723,0.499583),vec3(0.1,0.2,0.111111),vec3(0.6,0.75,1)); //violet and yellow
    color=vec4(co,1);
#else

    fvec=fvec/2+vec2(0.5);
    color=vec4(0,fvec.xy,1);
#endif
    return color;
}
vec4 calc_particle_image(vec2 pos)
{
    //return vec4(cos(pos.x)*0.5+0.5,sin(pos.y)*0.5+0.5,0,1);
    vec4 col=texture(tex_main,pos);
    vec3 mmin=col_min;
    vec3 mmax=col_max;
#if 0
    mmin=vec3(min(min(mmin.x,mmin.y),mmin.z));
    mmax=vec3(max(max(mmax.x,mmax.y),mmax.z));
#elif 0
    mmin=vec3(max(max(mmin.x,mmin.y),mmin.z));
    mmax=vec3(min(min(mmax.x,mmax.y),mmax.z));
#elif 0
    mmin=vec3(mmin.x+mmin.y+mmin.z)/3;
    mmax=vec3(mmax.x+mmax.y+mmax.z)/3;
#else
    //noop
#endif
#if 1
    col.xyz=log(col.xyz+vec3(1));
    col.xyz-=log(mmin+vec3(1));
    col.xyz/=log(mmax+vec3(1))-log(mmin+vec3(1));
    col.xyz=pow(col.xyz,vec3(v_gamma));
#else
    col.xyz-=mmin;
    col.xyz/=(mmax-mmin);
    col.xyz=pow(col.xyz,vec3(1));
#endif
    return col;
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    if(draw_particles==0)
        color=calc_vector_image(normed);
    else
        color=calc_particle_image(normed);
}
]==])

local update_rotations_shader=shaders.Make(
[==[
#version 330

#line 69
out vec4 color;
in vec3 pos;

#define M_PI   3.14159265358979323846264338327950288
uniform sampler2D tex_rotation;
uniform sampler2D tex_speeds;

#define SC_SAMPLE(dx,dy,w) \
    {\
        vec4 c=cos(textureOffset(tex_rotation,pos,ivec2(dx,dy)));\
        vec4 s=sin(textureOffset(tex_rotation,pos,ivec2(dx,dy)));\
        sx+=c.x*c.y*w;\
        sy+=s.x*c.y*w;\
        sz+=s.y*w;\
    }

vec4 avg_at_pos(vec2 pos)
{
    float sx=0;
    float sy=0;
    float sz=0;

    SC_SAMPLE(-1,-1,0.25);
    SC_SAMPLE(-1,1,0.25);
    SC_SAMPLE(1,-1,0.25);
    SC_SAMPLE(1,1,0.25);

    SC_SAMPLE(0,-1,0.5);
    SC_SAMPLE(0,1,0.5);
    SC_SAMPLE(1,0,0.5);
    SC_SAMPLE(-1,0,0.5);

    SC_SAMPLE(0,0,3);
    sx/=6;
    sy/=6;
    sz/=6;
    //return vec4(atan(sy,sx),atan(sqrt(sx*sx+sy*sy),sz),0,0);
    //return vec4(atan(sy,sx),acos(clamp(sz,-1,1)),0,0);
    return vec4(atan(sy,sx),atan(sqrt(sx*sx+sy*sy)/sz),0,0);
}
vec4 laplace_at_pos(vec2 pos)
{
    float sx=0;
    float sy=0;
    float sz=0;

    SC_SAMPLE(-1,-1,0.25);
    SC_SAMPLE(-1,1,0.25);
    SC_SAMPLE(1,-1,0.25);
    SC_SAMPLE(1,1,0.25);

    SC_SAMPLE(0,-1,0.5);
    SC_SAMPLE(0,1,0.5);
    SC_SAMPLE(1,0,0.5);
    SC_SAMPLE(-1,0,0.5);

    SC_SAMPLE(0,0,-3);
/*
    sx/=3;
    sy/=3;
    sz/=3;
*/
    return vec4(sx,sy,sz,0);
}
#undef SC_SAMPLE
vec4 gray_scott(vec4 c,vec2 normed)
{
    vec4 scale=vec4(0.07,0.1,0,0);
    vec4 offset=vec4(0);

    vec4 k=vec4(8,9,0,0);

    //k=k*scale+offset;
    c.xy+=vec2(M_PI);
    c.xy/=M_PI;
    float abb=c.x*c.y*c.y*cos(c.y*M_PI*2-c.x*M_PI);
    return (vec4(-abb,abb,0,0)+vec4(k.x*(1-c.x),-(k.y+k.x)*c.y,0,0))*2*M_PI-M_PI;
}
vec2 func(vec4 c,vec2 pos)
{
    return gray_scott(c,pos).xy;
}
vec4 input_rotated(vec4 rotation,vec4 speed)
{
    vec4 c=cos(rotation+speed);
    vec4 s=sin(rotation+speed);

    return vec4(c.x*c.y,s.x*c.y,s.y,0);
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))*vec2(0.5,0.5);
    vec4 rotation=texture(tex_rotation,normed);
    vec4 speeds=texture(tex_speeds,normed);
    float dt=0.125;
#if 1
    vec4 cnt_input=input_rotated(rotation,speeds*dt);
    vec4 cnt=cnt_input;
    float L=0.5;
    cnt+=laplace_at_pos(normed)*L*dt;

    //vec2 fval=func(rotation,normed)*dt;
    //cnt+=vec4( cos(fval.x),sin(fval.x),
    //           cos(fval.y),sin(fval.y))*0.05;
    //rotation.x=mix(atan(cnt.y,cnt.x),atan(cnt_input.y,cnt_input.x),speeds.w);
    //rotation.y=mix(atan(cnt.w,cnt.z),atan(cnt_input.w,cnt_input.z),speeds.w);
    //rotation=vec4(atan(cnt.y,cnt.x),atan(sqrt(cnt.x*cnt.x+cnt.y*cnt.y),cnt.z),0,0);

    rotation=vec4(atan(cnt.y,cnt.x),acos(clamp(cnt.z/length(cnt),-1,1)),0,0);
#else
    //rotation.x=mod(rotation.x+speeds.x*dt,M_PI*2);
    //rotation.y=mod(rotation.y+speeds.y*dt,M_PI*2);
    rotation=avg_at_pos(normed)+vec4(speeds.xy,0,0)*dt;//mix(avg_at_pos(normed),rotation,speeds.w);

#endif
    color=vec4(rotation.xyz,1);
}
]==])


agent_shader=shaders.Make(
[==[
#version 330

layout(location = 0) in vec4 position;

out vec4 point_out;

#define M_PI 3.1415926535897932384626433832795

uniform sampler2D tex_angles;
uniform float speed;

void main()
{
    vec2 normed=(position.xy+vec2(1,1))*vec2(0.5,0.5);
    //TODO: this bilinear/nn iterpolates. Does this make sense?
    float angle=texture(tex_angles,normed).x;
    vec2 delta=vec2(cos(angle),sin(angle))*speed;
    vec2 p=position.xy+delta;
    if(p.x<-1)
        p.x=1;
    if(p.x>1)
        p.x=-1;
    if(p.y<-1)
        p.y=1;
    if(p.y>1)
        p.y=-1;
    point_out=vec4(p,0,0);
}
]==],
[==[ void main(){} ]==],"point_out"
)
agent_draw_shader=shaders.Make(
[==[
#version 410

layout(location = 0) in vec4 position;
layout(location = 1) in vec4 particle_color;

//out vec3 pos;
out vec4 col;
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main()
{
    gl_Position.xyz = position.xyz;
    gl_Position.w = 1.0;
    //pos=position;
    //vec3 co=palette(particle_color.b,vec3(0.2,0.7,0.4),vec3(0.6,0.9,0.2),vec3(0.6,0.8,0.7),vec3(0.5,0.1,0.0));
    //vec3 co=palette(particle_color.b,vec3(0.971519,0.273919,0.310136),vec3(0.90608,0.488869,0.144119),vec3(5,10,2),vec3(1,1.8,1.28571)); //violet and blue
    vec3 co=palette(particle_color.b,vec3(0.5),vec3(0.5),vec3(1),vec3(0.0,0.33,0.67));
    col=vec4(co,1);
}
]==],
[==[
#version 410

in vec4 col;

out vec4 color;
uniform float opacity;
void main()
{
    color=col*opacity;
}
]==]
)
function rand_gaussian(sigma,mu_x,mu_y)
    mu_x=mu_x or 0
    mu_y=mu_y or 0
    local u1=math.random()
    local u2=math.random()
    local x=sigma*math.sqrt(-2*math.log(u1))*math.cos(2*math.pi*u2)+mu_x
    local y=sigma*math.sqrt(-2*math.log(u1))*math.sin(2*math.pi*u2)+mu_y
    return x,y
end

function reset_agent_data()
    agent_color=agent_color or make_flt_buffer(agent_count,1) --color of pixels that are moving around
    agent_state=agent_state or make_flt_buffer(agent_count,1) --position and <other stuff>
    -- [=[
    local b=agent_state_buffer.buffers[1]
    b:use()
    b:read(agent_state.d,agent_count*4*4)
    --]=]
    local chance_move=0.8
    local chance_no_move=0.5
    for i=0,agent_count-1 do
        if math.random()> chance_move then
            -- [[
            local x=math.random()*2-1
            local y=math.random()*2-1
            --]]
            --local x,y=rand_gaussian(0.5)
            if x>1 then x=x-2 end
            if y>1 then y=y-2 end
            if x<-1 then x=x+2 end
            if y<-1 then y=y+2 end
            agent_color:set(i,0,{x*0.5+0.5,y*0.5+0.5,(math.abs(x+y))*0.5,0.0001})
            agent_state:set(i,0,{x,y,0,0})
        else
            local max_r=(1/map_w)*(map_w)

            local v=agent_state:get(i,0)
            local x,y
            if math.random()>chance_no_move then

                local r=math.sqrt(math.random())*max_r
                local a=math.random()*math.pi*2
                x=v.r+math.cos(a)*r
                y=v.g+math.sin(a)*r
            else
                x=v.r
                y=v.g
            end
            --]]
            --local x,y=rand_gaussian(0.5)
            if x>1 then x=x-2 end
            if y>1 then y=y-2 end
            if x<-1 then x=x+2 end
            if y<-1 then y=y+2 end
            agent_state:set(i,0,{x,y,0,0})
        end
    end
    for i=1,agent_state_buffer.count do
        local b=agent_state_buffer.buffers[i]
        b:use()
        b:set(agent_state.d,agent_count*4*4)
    end
    agent_color_buffer:use()
    agent_color_buffer:set(agent_color.d,agent_count*4*4)
    __unbind_buffer()
end
if vector_buffer==nil then
    update_buffers()
    vector_buffer=multi_texture(vector_layer.w,vector_layer.h,2,FLTA_PIX)
    speed_buffer=multi_texture(vector_layer.w,vector_layer.h,1,FLTA_PIX)
    trails_buffer=multi_texture(vector_layer.w,vector_layer.h,2,FLTA_PIX)

    agent_state_buffer=multi_buffer(2)
    agent_color_buffer=buffer_data.Make()
    reset_agent_data()
end



need_clear=false
function save_img(  )
    img_buf_save=make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    for k,v in pairs(config) do
        if type(v)~="table" then
            config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
        end
    end
    img_buf_save:read_frame()
    img_buf_save:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function sim_tick(  )
    update_rotations_shader:use()
    local t1=vector_buffer:get()
    local t_out=vector_buffer:get_next()
    t1:use(1)
    t_out:use(2)
    speed_buffer:get():use(3)
    update_rotations_shader:set_i("tex_rotation",1);
    update_rotations_shader:set_i("tex_speeds",3);

    if not t_out:render_to(vector_layer.w,vector_layer.h) then
        error("failed to set framebuffer up")
    end
    update_rotations_shader:draw_quad()
    __render_to_window()

    vector_buffer:advance()
end
function agent_tick(  )
    agent_shader:use()
    local so=agent_state_buffer:get_next()
    so:use()
    so:bind_to_feedback()

    agent_state_buffer:get():use()
    vector_buffer:get():use(1)
    agent_shader:set_i("tex_angles",1)
    agent_shader:set("speed",(1/map_w)*.1)
    agent_shader:raster_discard(true)
    agent_shader:draw_points(0,agent_count,4,1)
    agent_shader:raster_discard(false)
    agent_state_buffer:advance()
    __unbind_buffer()
end
function agent_draw(  )
    agent_draw_shader:use()
    agent_draw_shader:set("opacity",config.particle_opacity)
    agent_draw_shader:blend_add()
    trails_buffer:get():use(0)
    agent_color_buffer:use()
    agent_draw_shader:push_attribute(0,"particle_color",4,GL_FLOAT)
    agent_state_buffer:get():use()
    if not trails_buffer:get():render_to(vector_layer.w,vector_layer.h) then
        error("failed to set framebuffer up")
    end
    agent_draw_shader:draw_points(0,agent_count,4)
    agent_draw_shader:blend_default()
    __render_to_window()
    __unbind_buffer()
end
function find_min_max( tex,buf )
    not_pixelated=not_pixelated or 0
    tex:use(0,not_pixelated)
    local lmin={math.huge,math.huge,math.huge}
    local lmax={-math.huge,-math.huge,-math.huge}

    trails_layer:read_texture(tex)
    local avg_lum=0
    local count=0
    for x=0,trails_layer.w-1 do
    for y=0,trails_layer.h-1 do
        local v=trails_layer:get(x,y)
        if v.r<lmin[1] then lmin[1]=v.r end
        if v.g<lmin[2] then lmin[2]=v.g end
        if v.b<lmin[3] then lmin[3]=v.b end

        if v.r>lmax[1] then lmax[1]=v.r end
        if v.g>lmax[2] then lmax[2]=v.g end
        if v.b>lmax[3] then lmax[3]=v.b end
        --local lum=math.sqrt(v.g*v.g+v.r*v.r+v.b*v.b)--math.abs(v.g+v.r+v.b)
        --local lum=math.abs(v.g)
        --local lum=math.abs(v.g)+math.abs(v.r)+math.abs(v.b)
        local lum=math.abs(v.b)
        --if lum > config.min_value then
            avg_lum=avg_lum+math.log(1+lum)
            count=count+1
        --end
    end
    end
    avg_lum = math.exp(avg_lum / count);
    --[[print(avg_lum)
    for i,v in ipairs(lmax) do
        print(i,v)
    end
    --]]
    return lmin,lmax,avg_lum
end
particle_iter=particle_iter or 0
function update()
    __clear()
    __no_redraw()

    imgui.Begin("Angular propagations")
    draw_config(config)

    --imgui.SameLine()
    need_clear=false
    if imgui.Button("Reset world") then
        vector_layer=nil
        update_buffers()
        need_clear=true
    end
    local step
    if imgui.Button("Step") then
        step=true
    end
    if imgui.Button("clear speeds") then
        for x=0,map_w-1 do
        for y=0,map_h-1 do
           speed_layer:set(x,y,{0,0,0,0})
        end
        end
        speed_layer:write_texture(speed_buffer:get())
    end
    if imgui.Button("reset particles") then
        reset_agent_data()
    end
    imgui.SameLine()
    if imgui.Button("reset particle image") then
        for x=0,map_w-1 do
        for y=0,map_h-1 do
            trails_layer:set(x,y,{0,0,0,1})
        end
        end
        trails_layer:write_texture(trails_buffer:get())
        trails_layer:write_texture(trails_buffer:get_next())
    end
    if is_remade or (config.__change_events and config.__change_events.any) then
        is_remade=false
        local cx=math.floor(map_w/2)
        local cy=math.floor(map_h/2)
        for x=0,map_w-1 do
        for y=0,map_h-1 do
            vector_layer:set(x,y,{0,0,0,0})
            --if x>cx-25 and x<cx+25 then
            --    vector_layer:set(x,y,{(math.random()-0.5)*math.pi*2,(math.random()-0.5)*math.pi*2,0,0})
            --else
                --vector_layer:set(x,y,{0,(math.random()-0.5)*math.pi*2,0,0})
            --end
            speed_layer:set(x,y,{0,0,0,0})
            trails_layer:set(x,y,{0,0,0,1})
        end
        end


        local s=config.speed
        local s2=config.speedz
        --[==[
        local w=1
        local eps=math.random()*(w/2)-w
        for i=-cx+25,cx-25 do
            local v=i/cx
            local dy=math.floor(math.abs(v)*i)
            local vv=math.cos(v*math.pi*4)
            --vector_layer:set(cx+i,cy-dy,{v*math.pi+eps,0,0,0})
            --vector_layer:set(cx+dy,cy+i,{v*math.pi-eps,0,0,0})
            --if i>0 then
                speed_layer:set(cx+i,cy-dy,{s*vv+eps,1,0,0})
                speed_layer:set(cx+dy,cy+i,{-s*vv+eps,1,0,0})
            --[[else
                speed_layer:set(cx+i,cy+dy,{-s*0.5,1,0,0})
                speed_layer:set(cx+dy,cy+i,{-s,1,0,0})
            end]]
        end
        --]==]
        local function put_pixel( cx,cy,x,y,a,s1,s2 )
            speed_layer:set(cx+x,cy+y,{s1,s2,0,0})
            vector_layer:set(cx+x,cy+y,{math.cos(a*8)*math.pi,math.sin(a*8)*math.pi,0,0})
        end
        local r=math.floor(cx*0.75)
        --[[
        for a=0,math.pi*2,0.0001 do
            local x=math.floor(math.cos(a)*r)
            local y=math.floor(math.sin(a)*r)
            put_pixel(cx,cy,x,y,a)
        end
        local s=-1
        for i=1,12 do
            r=r-i*5
            for a=0,math.pi*2,0.0001 do
                local x=math.floor(math.cos(a)*r)
                local y=math.floor(math.sin(a)*r)
                put_pixel(cx,cy,x,y,a*s)
            end
            s=s*(-5/8)
        end
        --]]
        --[=[
        local r2=cx*0.25
        local dist=0.3
        for a=0,math.pi*2,0.0001 do
            local x=math.floor(math.cos(a)*r2)
            local y=math.floor(math.sin(a)*r2)
            put_pixel(cx,math.floor(cy*(1-dist)),x,y,a,s,-s*0.75)
        end
        for a=0,math.pi*2,0.0001 do
            local x=math.floor(math.cos(a)*r)
            local y=math.floor(math.sin(a)*r)
            put_pixel(cx,cy,x,y,a,-s,s)
        end
        for a=0,math.pi*2,0.0001 do
            local x=math.floor(math.cos(a)*r2)
            local y=math.floor(math.sin(a)*r2)
            put_pixel(cx,math.floor(cy*(1+dist)),x,y,a,s,-s*0.75)
        end
        --]=]
        -- [[
        for i=-5,5 do
            local nr=r+i
            for x=-nr,nr do
                local a=(x/nr)*math.pi
                put_pixel(cx,cy,x,-nr,a,s,s2)
                put_pixel(cx,cy,x,nr,a,s,s2)
                put_pixel(cx,cy,nr,x,a,s,s2)
                put_pixel(cx,cy,-nr,x,a,s,s2)
            end
        end
        r=math.floor(r*0.8)
        for i=-10,10 do
            local nr=r+i
            for x=-nr,nr do
                local a=(x/nr)*math.pi*0.5

                put_pixel(cx,cy,x,-nr,a,s,-s2)
                put_pixel(cx,cy,x,nr,a,s,-s2)
                put_pixel(cx,cy,nr,x,a,s,-s2)
                put_pixel(cx,cy,-nr,x,a,s,-s2)
            end
        end
        --[==[
        r=math.floor(r*0.6)
        for i=-10,10 do
            local nr=r+i
            for x=-nr,nr do
                local a=(x/nr)*math.pi*2

                put_pixel(cx,cy,x,-nr,a)
                put_pixel(cx,cy,x,nr,a)
                put_pixel(cx,cy,nr,x,a)
                put_pixel(cx,cy,-nr,x,a)
            end
        end
        r=math.floor(r*0.6)
        for i=-10,10 do
            local nr=r+i
            for x=-nr,nr do
                local a=(x/nr)*math.pi*0.25

                put_pixel(cx,cy,x,-nr,a)
                put_pixel(cx,cy,x,nr,a)
                put_pixel(cx,cy,nr,x,a)
                put_pixel(cx,cy,-nr,x,a)
            end
        end
        --]==]
        --]]
        --[[
        for i=1,500 do
            --local x=math.random(0,cx)+math.floor(cx/2)
            --local y=math.random(0,cy)+math.floor(cy/2)
            --local x=math.random(0,map_w-1)
            --local y=math.random(0,map_h-1)
            local r=math.sqrt(math.random())*cx
            local a=math.random()*math.pi*2
            local x=math.floor(math.cos(a)*r)+cx
            local y=math.floor(math.sin(a)*r)+cx
            speed_layer:set(x,y,{s*(math.random()*0.01+0.99),1,0,0})
            --vector_layer:set(x,y,{math.random()*math.pi*2-math.pi,0,0,0})
            vector_layer:set(x,y,{math.cos(r*math.pi/cx)*math.pi,0,0,0})
        end
        --]]
        vector_layer:write_texture(vector_buffer:get())
        vector_layer:write_texture(vector_buffer:get_next())
        speed_layer:write_texture(speed_buffer:get())
        trails_layer:write_texture(trails_buffer:get())
        trails_layer:write_texture(trails_buffer:get_next())
        need_clear=true
        reset_agent_data()
    end
    if not config.pause or step then
        for i=1,config.sim_ticks do
            sim_tick()
        end
        sim_done=true
        --add_particle{map_w/2,0,math.random()*0.25-0.125,math.random()-0.5,3}
    end

    if not config.pause_particles then
        particle_iter=particle_iter+1
        if particle_iter> config.particle_reset_iter and config.particle_reset_iter>0 then
            reset_agent_data()
            particle_iter=0
        end
        for i=1,config.sim_ticks do
            agent_tick()
            if particle_iter>=config.particle_wait_iter then
                agent_draw()
            end
        end
    end
    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    if imgui.Button("renorm") then
        need_renorm=true
    end
    imgui.End()

    __render_to_window()
    draw_shader:use()

    draw_shader:set_i("res",map_w,map_h)
    if config.show_particles then
        if need_renorm or glow==nil then
            local avg
            glow,ghigh,avg=find_min_max(trails_buffer:get())
            need_renorm=false
        end
        trails_buffer:get():use(0,0,1)
        draw_shader:set_i("tex_main",0)
        draw_shader:set_i("draw_particles",1)
        draw_shader:set("col_min",glow[1],glow[2],glow[3])
        draw_shader:set("col_max",ghigh[1],ghigh[2],ghigh[3])
    else
        local t1=vector_buffer:get()
        t1:use(0,0,1)
        draw_shader:set_i("tex_main",0)
        draw_shader:set_i("draw_particles",0)
    end
    draw_shader:set("v_gamma",config.gamma)
    draw_shader:draw_quad()

    if need_save then
        save_img()
        need_save=false
    end

end
