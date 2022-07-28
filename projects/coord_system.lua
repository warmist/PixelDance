require 'common'

config=make_config({

    },config)

local size=STATE.size
local zoom=4

grid=grid or make_float_buffer(math.floor(size[1]/zoom),math.floor(size[2]/zoom))
local draw_shader=shaders.Make[==[
#version 330
#line 13
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform float count_steps;

vec3 palette(float v)
{
    vec3 a=vec3(0.5,0.5,0.5);
    vec3 b=vec3(0.5,0.5,0.5);
    /* blue-black-red
    vec3 c=vec3(0.25,0.3,0.4);
    vec3 d=vec3(0.5,0.3,0.2);
    //*/
    /*
    vec3 c=vec3(0.8,2.7,1.0);
    vec3 d=vec3(0.2,0.5,0.8);
    //*/
    /* gold and blue
    vec3 c=vec3(1,1,0.5);
    vec3 d=vec3(0.8,0.9,0.3);
    //*/
    ///* gold and violet
    vec3 c=vec3(0.5,0.5,0.45);
    vec3 d=vec3(0.6,0.5,0.35);
    //*/
    /* ice and blood
    vec3 c=vec3(1.25,1.0,1.0);
    vec3 d=vec3(0.75,0.0,0.0);
    //*/
    return a+b*cos(3.1459*2*(c*v+d));
}
void main(){
    vec2 normed=(pos.xy+vec2(1,1))/2;
    float col=texture(tex_main,normed).x;

    if(count_steps>0)
        col=floor(col*count_steps)/count_steps;
#if 0
    color = vec4(palette(col),1);
#else
    col=pow(col,2.2);
    color.xyz=vec3(col);
    color.w=1;
#endif
}
]==]
grid_tex =grid_tex or textures.Make()
function draw_grid(  )
    draw_shader:use()
    grid_tex:use(0)
    grid:write_texture(grid_tex)
    draw_shader:set_i("tex_main",0)
    draw_shader:draw_quad()
    if need_save then
        save_img()
        need_save=nil
    end
end
func_t=func_t or 0
cur_pos=cur_pos or {x=0,y=0}
state_count=0
states=states or {}
function pos_f( t )
    local radius=35
    local p=16
    local r2=3
    --return math.cos(t)*radius+math.cos(t*p)*radius/r2+math.cos(t*p*3)*radius/3,math.sin(t)*radius+math.sin(t*p)*radius/r2+math.sin(t*p*3)*radius/3
    return math.cos(t)*radius+math.cos(t*p)*radius/r2,math.sin(t)*radius+math.sin(t*p)*radius/r2
end
function set_new_pos( nx,ny )
    if states[nx+ny*grid.w]==nil then
        states[nx+ny*grid.w]=true
        state_count=state_count+1
    end
    grid:set(cur_pos.x,cur_pos.y,0.8)
    cur_pos={x=nx,y=ny}
    --grid:set(cur_pos.x,cur_pos.y,1)
end
function advance_func(  )
    local cx=math.floor(grid.w/2)
    local cy=math.floor(grid.h/2)
    local max_step=100
    local dt=0.00001
    local nx,ny
    for i=1,max_step do
        nx,ny=pos_f(func_t+dt*i)
        nx=math.floor(nx+0.5)+cx
        ny=math.floor(ny+0.5)+cy
        if nx~=cur_pos.x or ny~=cur_pos.y then
            set_new_pos(nx,ny)
            func_t=func_t+dt*i
            return true
        end
    end
    func_t=func_t+dt*max_step
    return false
end
function save_img(  )
    img_buf=img_buf or make_image_buffer(size[1],size[2])
    local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
    config_serial=config_serial..serialize_config(config).."\n"
    img_buf:read_frame()
    img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function update()
    __clear()
    __no_redraw()

    imgui.Begin("coord systems")
    draw_config(config)
    if imgui.Button "Save" then
        need_save=true
    end
    if imgui.Button "Clear" then
        grid:clear()
        states={}
        state_count=0
    end
    imgui.Text(string.format("Unique states:%d",state_count))
    imgui.End()
    advance_func()
    draw_grid(  )
    if need_save then
        save_img()
        need_save=false
    end
end