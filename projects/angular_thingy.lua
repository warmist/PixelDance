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
    {"particle_opacity",0.01,type="floatsci",min=0,max=1,power=10},
    {"particle_reset_iter",1000,type="int",min=0,max=10000},
    {"particle_wait_iter",100,type="int",min=0,max=10000},
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
    //col.xyz=pow(col.xyz,vec3(1));
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
    ret_s+=sin(textureOffset(tex_rotation,pos,ivec2(dx,dy)))*w;\
    ret_c+=cos(textureOffset(tex_rotation,pos,ivec2(dx,dy)))*w

vec4 avg_at_pos(vec2 pos)
{
    vec4 ret_s=vec4(0);
    vec4 ret_c=vec4(0);

    SC_SAMPLE(-1,-1,0.25);
    SC_SAMPLE(-1,1,0.25);
    SC_SAMPLE(1,-1,0.25);
    SC_SAMPLE(1,1,0.25);

    SC_SAMPLE(0,-1,0.5);
    SC_SAMPLE(0,1,0.5);
    SC_SAMPLE(1,0,0.5);
    SC_SAMPLE(-1,0,0.5);

    SC_SAMPLE(0,0,3);

    return atan(ret_s,ret_c);
}
vec4 laplace_at_pos(vec2 pos)
{
    vec4 ret_s=vec4(0);
    vec4 ret_c=vec4(0);

    SC_SAMPLE(-1,-1,0.25);
    SC_SAMPLE(-1,1,0.25);
    SC_SAMPLE(1,-1,0.25);
    SC_SAMPLE(1,1,0.25);

    SC_SAMPLE(0,-1,0.5);
    SC_SAMPLE(0,1,0.5);
    SC_SAMPLE(1,0,0.5);
    SC_SAMPLE(-1,0,0.5);

    SC_SAMPLE(0,0,-3);

    return vec4(ret_c.x,ret_s.x,ret_c.y,ret_s.y);
}
#undef SC_SAMPLE
vec4 gray_scott(vec4 c,vec2 normed)
{
    vec4 scale=vec4(0.07,0.1,0,0);
    vec4 offset=vec4(0);

    vec4 k=vec4(0.5,0.5,0,0);

    k=k*scale+offset;
    c.xy+=vec2(2*M_PI);
    float abb=c.x*c.y*c.y;
    return vec4(-abb,abb,0,0)+vec4(k.x*(M_PI-c.x),-(k.y+k.x)*c.y,0,0);
}
vec2 func(vec4 c,vec2 pos)
{
    return gray_scott(c,pos).xy;
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))*vec2(0.5,0.5);
    vec4 rotation=texture(tex_rotation,normed);
    vec4 speeds=texture(tex_speeds,normed);
    float dt=0.125;
#if 1
    vec4 cnt_input=vec4(
        cos(rotation.x+speeds.x*dt),sin(rotation.x+speeds.x*dt),
        cos(rotation.y+speeds.y*dt),sin(rotation.y+speeds.y*dt));
    vec4 cnt=cnt_input;
    float L=0.5;
    cnt+=laplace_at_pos(normed)*L*dt;
    vec2 fval=func(rotation,normed)*dt;

    //cnt+=vec4( cos(fval.x),sin(fval.x),
    //           cos(fval.y),sin(fval.y))*0.05;
    //rotation.x=mix(atan(cnt.y,cnt.x),atan(cnt_input.y,cnt_input.x),speeds.w);
    //rotation.y=mix(atan(cnt.w,cnt.z),atan(cnt_input.w,cnt_input.z),speeds.w);
    rotation=vec4(atan(cnt.y,cnt.x),atan(cnt.w,cnt.z),0,0);
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
void main()
{
    gl_Position.xyz = position.xyz;
    gl_Position.w = 1.0;
    //pos=position;
    col=particle_color;
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
function reset_agent_data()
    agent_color=make_flt_buffer(agent_count,1) --color of pixels that are moving around
    agent_state=make_flt_buffer(agent_count,1) --position and <other stuff>

    for i=0,agent_count-1 do
        local x=math.random()*2-1
        local y=math.random()*2-1
        agent_color:set(i,0,{x*0.5+0.5,y*0.5+0.5,(math.abs(x+y))*0.5,0.0001})
        agent_state:set(i,0,{x,y,0,0})
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
    agent_shader:set("speed",(1/map_w)*1)
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
            --vector_layer:set(x,y,{0,0,0,0})
            if x>cx-25 and x<cx+25 then
                vector_layer:set(x,y,{(math.random()-0.5)*math.pi*2,(math.random()-0.5)*math.pi*2,0,0})
            else
                vector_layer:set(x,y,{0,(math.random()-0.5)*math.pi*2,0,0})
            end
            speed_layer:set(x,y,{0,0,0,0})
            trails_layer:set(x,y,{0,0,0,1})
        end
        end


        local s=config.speed
        --[[
        for i=-cx+1,cx-1 do
            local eps=math.random()*0.001
            local v=i/100
            vector_layer:set(cx+i,cy,{v*math.pi+eps,0,0,0})
            vector_layer:set(cx,cy+i,{v*math.pi-eps,0,0,0})
            if i>0 then
                speed_layer:set(cx+i,cy,{s,1,0,0})
                speed_layer:set(cx,cy+i,{s,1,0,0})
            else
                speed_layer:set(cx+i,cy,{s,1,0,0})
                speed_layer:set(cx,cy+i,{s,1,0,0})
            end
        end
        --]]
        local function put_pixel( cx,cy,x,y,a )
            speed_layer:set(cx+x,cy+y,{s,-s/2,0,1})
            vector_layer:set(cx+x,cy+y,{math.cos(a*8)*math.pi,math.sin(a*16)*math.pi,0,0})
        end
        local r=math.floor(cx*0.95)
        --[[
        for a=0,math.pi*2,0.001 do
            local x=math.floor(math.cos(a)*r)
            local y=math.floor(math.sin(a)*r)
            put_pixel(cx,cy,x,y,a)
        end
        local s=-1
        for i=1,8 do
            r=r-40
            for a=0,math.pi*2,0.001 do
                local x=math.floor(math.cos(a)*r)
                local y=math.floor(math.sin(a)*r)
                put_pixel(cx,cy,x,y,a*s)
            end
            s=s*(-6/8)
        end
        --]]
        -- [[
        for x=-r,r do
            local a=(x/r)*math.pi
            put_pixel(cx,cy,x,-r,a)
            put_pixel(cx,cy,x,r,a)
            put_pixel(cx,cy,r,x,a)
            put_pixel(cx,cy,-r,x,a)
        end
        r=math.floor(r*0.95)
        for x=-r,r do
            local a=(x/r)*math.pi*0.25

            put_pixel(cx,cy,x,-r,a)
            put_pixel(cx,cy,x,r,a)
            put_pixel(cx,cy,r,x,a)
            put_pixel(cx,cy,-r,x,a)
        end
        --]]
        --[[
        for i=1,500 do
            --local x=math.random(0,cx)+math.floor(cx/2)
            --local y=math.random(0,cy)+math.floor(cy/2)
            --local x=math.random(0,map_w-1)
            --local y=math.random(0,map_h-1)
            local r=math.sqrt(math.random())*cx/4
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

    imgui.End()

    __render_to_window()

    draw_shader:use()

    draw_shader:set_i("res",map_w,map_h)
    if config.show_particles then
        trails_buffer:get():use(0,0,1)
        draw_shader:set_i("tex_main",0)
        draw_shader:set_i("draw_particles",1)
    else
        local t1=vector_buffer:get()
        t1:use(0,0,1)
        draw_shader:set_i("tex_main",0)
        draw_shader:set_i("draw_particles",0)
    end
    draw_shader:draw_quad()

    if need_save then
        save_img()
        need_save=false
    end

end
