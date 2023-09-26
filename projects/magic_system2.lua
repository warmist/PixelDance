--[[
    simple vector field. Stuff happens if "particles" linger.

    place things that modify the grad-field. find places where fields becomes low, draw stuff there

    maybe too easy so we could do N fields and only when few of them overlap magic happens. Then you
    could make tools manipulate few fields at once and thus not be clear what needs to be done.

    random ideas:
        * outside field (i.e. normally particles are not stopped, thus no magic)
        * interaction types:
            * orthogonal-like - i.e. four basic ones (push, pull, curl, anticurl)
            * mixed nonsense - e.g. could be because your gem is with a flaw
        * interaction distance:
            * also falloff - linear, square, exp, etc...
        * insane interactions, like f(vec)=sin(cos(|vec|))*exp(-|vec|^2)/....
        * set max speed as "light speed" i.e. need infinite time/energy to reach it
]]


require "common"

local win_w=1280
local win_h=1280
local oversample=1/4
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local influence_size=0.8
local max_tool_count=30
current_tool_count=current_tool_count or 0
--x,y,type,???
tool_data={}--make_flt_buffer(max_tool_count,1)
--x,y,??,??
if field==nil or field.w~=map_w or field.h~=map_h then
    field=make_flt_buffer(map_w,map_h)
end

local max_agent_count=10000
agent_count=agent_count or 0
if agents==nil or agents.w~=max_agent_count then
    agents=make_flt_buffer(max_agent_count,1)
    agents_color=make_flt_buffer(max_agent_count,1)
end

local outside_angle=math.random()*math.pi*2


config=make_config({
    {"draw_trails",false,type="bool"},
    {"sim_agents",false,type="bool"},
    {"blob_count",5,type="int",min=1,max=max_tool_count},
    --[[{"placement",0,type="choice",choices={
        "single_center",
        }},]]
    --[[ blob type choice]]
    {"blob_order",14,type="int",min=2,max=14},
    {"seed",0,type="int",min=0,max=10000000},
    {"outside_strength",1.0,type="float",min=0,max=2},
    {"tool_scale",0.25,type="float",min=0,max=2},

    {"draw_layer",0,type="int",min=0,max=2,watch=true},
    {"agent_opacity",1,type="floatsci",min=0.01,max=1,watch=true},
    {"agent_gamma",1,type="float",min=0.01,max=2,watch=true},
},config)



function random_coefs( count )
    local order={
        1,1,
        2,2,2,
        3,3,3,3,
        4,4,4,4,4
    }
    local ret={}
    for i=1,14 do
        if i<count then
            ret[i]=math.random()*2-1
            --ret[i]=(math.random()*2-1)/order[i]
            --ret[i]=(math.random()*2-1)/math.pow(2,order[i])
        else
            ret[i]=0
        end
    end
    return ret
end
function init_tools(  )
    
    tool_data={}
    --[[
    current_tool_count=1
    tool_data[1]={0.5,0.5,1,random_coefs(14)}
    tool_data[2]={0.25,0.5,1,random_coefs(9)}
    tool_data[3]={0.75,0.5,1,random_coefs(9)}
    --]]
    --[[
    local dist=0.2
    local pos={
        {dist,dist},
        {dist,1-dist},
        {1-dist,dist},
        {1-dist,1-dist}
    }
    local general_scale=0.5
    current_tool_count=#pos
    for i=1,#pos do
        tool_data[i]={pos[i][1],pos[i][2],math.random()*general_scale*2-general_scale,random_coefs(14)}
    end
    --]]
    -- [[
    local dist=0.35
    
    local general_scale=config.tool_scale
    current_tool_count=config.blob_count
    for i=1,current_tool_count do
        local a=(i/current_tool_count)*math.pi*2
        --tool_data[i]={math.cos(a)*dist+0.5,math.sin(a)*dist+0.5,math.random()*general_scale*2-general_scale,random_coefs(config.blob_order)}
        --tool_data[i]={math.random(),math.random(),math.random()*general_scale*2-general_scale,random_coefs(config.blob_order)}
        --tool_data[i]={0.5,0.5,general_scale,random_coefs(config.blob_order)}
        tool_data[i]={math.random(),math.random(),general_scale,random_coefs(config.blob_order)}
    end
    --]]
    --[[
    local general_scale=0.5
    current_tool_count=2
    for i=1,current_tool_count do
        tool_data[i]={math.random(),math.random(),math.random()*general_scale*2-general_scale,random_coefs(14)}
    end
    --]]
    --[[
    current_tool_count=1
    tool_data:set(0,0,{0.5,0.5,25,2})
    tool_data:set(2,0,{0.37,0.55,-35,0})
    tool_data:set(3,0,{0.65,0.5,0,1})
    tool_data:set(4,0,{0.65,0.5,30,0})
    --]]
    --[[
    current_tool_count=max_tool_count
    for i=0,current_tool_count-1 do
        if math.random()<0 then
            tool_data:set(i,0,{math.random(),math.random(),math.random()*60-30,2})
        else
            tool_data:set(i,0,{math.random(),math.random(),math.random()*60-30,3})
        end
    end
    --]]
end

function linear_scaling( pos_len )
    return 1-pos_len/influence_size
end
function quadratic_scaling( pos_len )
    local s=1-pos_len/influence_size
    return s*s
end
local exp_p=0.35
local exp_psq=exp_p*exp_p
--value to reach at dist 1
function exp_sq( v )
    return math.exp(-v*v/exp_psq)
end
function exp_falloff( v )
    return (exp_sq(v)-exp_sq(1))/(exp_sq(0)-exp_sq(1))
end
function exp_scaling( v )
    return exp_falloff(v/influence_size)
end
local scaling_function=exp_scaling
--push/pull
function tool_direct_linear( pos,power,pos_len )
    local l=pos_len/influence_size
    local scale=1-l
    if scale<0 then scale=0 end
    return pos*power*scale
end
--curl/anticurl
function tool_orthogonal_linear( pos,power,pos_len )
    local tmp=tool_direct_linear(pos,power,pos_len)
    return Point(tmp[2],-tmp[1])
end


--push/pull
function tool_direct_sqr( pos,power,pos_len )
    local l=pos_len/influence_size
    local scale=1-l
    if scale<0 then scale=0 end
    return pos*power*scale*scale
end
--curl/anticurl
function tool_orthogonal_sqr( pos,power,pos_len )
    local tmp=tool_direct_sqr(pos,power,pos_len)
    return Point(tmp[2],-tmp[1])
end


--push/pull
function tool_direct_exp( pos,power,pos_len )
    local l=pos_len/influence_size
    local scale=l
    if scale>1 then scale=1 end
    scale=exp_falloff(scale)
    return pos*power*scale
end
--curl/anticurl
function tool_orthogonal_exp( pos,power,pos_len )
    local tmp=tool_direct_exp(pos,power,pos_len)
    return Point(tmp[2],-tmp[1])
end
local tools={
    tool_direct_linear,
    tool_orthogonal_linear,
    tool_direct_sqr,
    tool_orthogonal_sqr,
    tool_direct_exp,
    tool_orthogonal_exp
}

function zernike_der_function( pos,arguments )
    --0th is 0 both in x and y
    local X=pos[1]
    local Y=pos[2]
    local ox=
        --11-1 is 0
        2*arguments[2]+

        math.sqrt(6)*2*Y*arguments[3]+
        math.sqrt(3)*4*X*arguments[4]+
        math.sqrt(6)*2*X*arguments[5]+

        math.sqrt(8)*6*X*Y*(arguments[6]+
                                    arguments[7])+
        math.sqrt(8)*(9*X*X+3*Y*Y-2)*arguments[8]+
        math.sqrt(8)*3*(X*X-Y*Y)*arguments[9]+

        math.sqrt(10)*(12*X*X*Y-4*Y*Y*Y)*arguments[10]+
        math.sqrt(10)*(24*X*X*Y+8*Y*Y*Y-6*Y)*arguments[11]+
        math.sqrt(5)*(24*X*X*X+24*X*Y*Y-12*X)*arguments[12]+
        math.sqrt(10)*(16*X*X*X-6*X)*arguments[13]+
        math.sqrt(10)*(4*X*X*X-12*X*Y*Y)*arguments[14]

    local oy=
        2*arguments[1]+
        --111 is 0
        math.sqrt(6)*2*X*arguments[3]+
        math.sqrt(3)*4*Y*arguments[4]+
        math.sqrt(6)*(-2)*Y*arguments[5]+

        math.sqrt(8)*3*(X*X-Y*Y)*arguments[6]+
        math.sqrt(8)*(3*X*X+9*Y*Y-2)*arguments[7]+
        math.sqrt(8)*6*X*Y*(arguments[8]-
                                    arguments[9])+

        math.sqrt(10)*(4*X*X*X-12*X*Y*Y)*arguments[10]+
        math.sqrt(10)*(24*X*Y*Y+8*X*X*X-6*X)*arguments[11]+
        math.sqrt(5)*(24*Y*Y*Y+24*X*X*Y-12*Y)*arguments[12]+
        math.sqrt(10)*(-16*Y*Y*Y+6*Y)*arguments[13]+
        math.sqrt(10)*(-12*X*X*Y+4*Y*Y*Y)*arguments[14]
    return Point(ox,oy)
end
function outside_field_calc(x,y)
    return Point(math.cos(outside_angle),math.sin(outside_angle))*config.outside_strength
    --[[
    --local center=Point(map_w/2,map_h/2)
    local center=Point(map_w,map_h)
    local dc=center-Point(x,y)
    dc:normalize()
    --return dc*config.outside_strength
    return Point(dc[2],-dc[1])
    --]]
end
function update_field(  )
    --zernike version
    for x=0,map_w-1 do
    for y=0,map_h-1 do
        local value=outside_field_calc(x,y)--*(y/map_h)
        for i=0,current_tool_count-1 do
            local td=tool_data[i+1]--tool_data:get(i,0)
            local local_pos=Point(x/map_w,y/map_h)-Point(td[1],td[2])
            local local_pos_len=local_pos:len()
            local normed_pos=(1/influence_size)*local_pos
            if local_pos_len<influence_size then
                local angle=math.atan(local_pos[2],local_pos[1])
                --value=local_pos*local_pos_len
                value=value+zernike_der_function(normed_pos,td[4])*scaling_function(local_pos_len)*td[3]
            end
        end
        field:set(x,y,{value[1],value[2],0,0})
    end
    end
    --[[
    for x=0,map_w-1 do
    for y=0,map_h-1 do
        local value=default_field--*(y/map_h)
        for i=0,current_tool_count-1 do
            local td=tool_data[i+1]--tool_data:get(i,0)
            local tool_fun=tools[math.floor(td[4])+1]
            local local_pos=Point(x/map_w,y/map_h)-Point(td[1],td[2])
            local local_pos_len=local_pos:len()
            if local_pos_len<influence_size then
                --value=local_pos*local_pos_len
                value=value+tool_fun(local_pos,td[3],local_pos_len)
            end
        end
        field:set(x,y,{value[1],value[2],0,0})
    end
    end
    --]]
    draw_field.update(field)
end
function generate_uniform_string( v )
    return string.format("uniform %s %s;\n",v[1],v[2])
end
function generate_uniforms_string( uniform_list,texture_list )
    local uniform_string=""
    if uniform_list~=nil then
        for i,v in ipairs(uniform_list) do
            uniform_string=uniform_string..generate_uniform_string(v)
        end
    end
    if texture_list~=nil then
        for i,v in ipairs(texture_list) do
            uniform_string=uniform_string..generate_uniform_string({"sampler2D",v[2]})
        end
    end
    return uniform_string
end
function update_uniform( shader,utype,name,value_table )
    local types={
        int=shader.set_i,
        float=shader.set
    }
    types[utype](shader,name,value_table[name])
end
function init_draw_field(draw_string,settings)
    settings=settings or {}
    local uniform_list=settings.uniforms or {}
    local uniform_string=generate_uniforms_string(uniform_list,settings.textures)
    local shader_string=string.format([==[
#version 330
#line __LINE__ 99

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
#line __LINE__ 99
%s
#line __LINE__ 99
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5))+vec2(0.5,0.5);
    vec4 data=texture(tex_main,normed);
    %s
}
]==],uniform_string,draw_string)

    local draw_shader=shaders.Make(shader_string)
    local texture=textures:Make()

    local update_texture=function ( buffer )
        buffer:write_texture(texture)
    end
    local draw=function(  )
        -- clear
        if need_clear then
            __clear()
            need_clear=false
        end
        draw_shader:use()
        texture:use(0,0,0)
        for i,v in ipairs(settings.textures or {}) do
            v[1]:use(i)
            draw_shader:set_i(v[2],i)
        end
        draw_shader:set_i('tex_main',0)
        draw_shader:draw_quad()
    end
    local update_uniforms=function ( tbl )
        draw_shader:use()
        for i,v in ipairs(uniform_list) do
            --todo more formats!
            if tbl[v[2]]~=nil then
                update_uniform(draw_shader,v[1],v[2],tbl)
            end
        end
    end
    local ret={
        shader=draw_shader,
        draw=draw,
        update=update_texture,
        texture=textures,
        update_uniforms=update_uniforms,
        clear=function (  )
            need_clear=true
        end
    }
    
    return ret
end


function init_draw_agents(draw_string,settings)
    settings=settings or {offscreen=true}
    local uniform_list=settings.uniforms or {}
    local uniform_string=generate_uniforms_string(uniform_list)

    local draw_shader=shaders.Make(
[==[
#version 330
#line __LINE__ 99
layout(location = 0) in vec4 position;

uniform int pix_size;
uniform vec4 params;
uniform vec2 rez;

out vec4 pos_out;
void main()
{
    vec2 normed=(position.xy/vec2(1280/4))*2-vec2(1,1);
    normed.y=-normed.y;
    gl_Position.xy = normed;//mod(normed,vec2(1,1));
    gl_PointSize=1;
    gl_Position.z = 0;
    gl_Position.w = 1.0;
    pos_out=position;
}
]==],
string.format([==[
#version 330
#line __LINE__ 99

out vec4 color;
in vec4 pos_out;

#line __LINE__ 99
%s
#line __LINE__ 99
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    %s
#line __LINE__ 99
}
]==],uniform_string,draw_string))
    local need_clear=false
    local agent_buffers=buffer_data.Make()
    local tex_offscreen=textures:Make()
    tex_offscreen:use(0,1)
    tex_offscreen:set(map_w,map_h,1)
    local update_agents=function ( buffer,count )
        agent_buffers:use()
        agent_buffers:set(buffer.d,count*4*4)
        __unbind_buffer()
    end
    local draw=function( count )
        draw_shader:use()
        draw_shader:blend_add()
        -- [[ offscreen render
        if settings.offscreen then
            tex_offscreen:use(0)
            if not tex_offscreen:render_to(map_w,map_h) then
                error("failed to set framebuffer up")
            end
        end
        --]]
        -- clear
        if need_clear then
            __clear()
            need_clear=false
        end

        agent_buffers:use()
        draw_shader:draw_points(0,count,4)

        draw_shader:blend_default()
        if settings.offscreen then
            __render_to_window()
        end
        __unbind_buffer()
    end
    local update_uniforms=function ( tbl )
        draw_shader:use()
        for i,v in ipairs(uniform_list) do
            --todo more formats!
            if tbl[v[2]]~=nil then
                update_uniform(draw_shader,v[2],tbl)
            end
        end
    end
    local ret={
        shader=draw_shader,
        draw=draw,
        update=update_agents,
        texture=textures,
        update_uniforms=update_uniforms,
        clear=function (  )
            need_clear=true
        end,
        tex_offscreen=tex_offscreen
    }
    
    return ret
end



if draw_agents==nil or regen_shader then
draw_agents=init_draw_agents([==[
#line __LINE__
    //color=vec4(pos_out.w,0,0,1);
    color=vec4(palette(atan(pos_out.w,pos_out.z),vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);
    //color=vec4(palette(length(pos_out.wz),vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75)),1);

]==])
end

if draw_field==nil or regen_shader then
draw_field=init_draw_field([==[
#line __LINE__
    float angle=(atan(data.y,data.x)/3.14159265359+1)/2;
    float len=min(length(data.xy),1);
    vec4 out_col;
    if (draw_layer==0)
        out_col=vec4(palette(angle,vec3(0.4),vec3(0.6,0.4,0.3),vec3(1,2,3),vec3(0.5,0.25,0.75))*len,1);
    else if(draw_layer==1)
    {
        len=1-len;
        out_col=vec4(len,len,len,1);
    }else
    {
        out_col=vec4(0,0,0,1);
        normed.y=-normed.y;
        vec4 data2=texture(tex_agents,normed);
        vec3 agent_data=clamp(data2.xyz/agent_iterations,0,1);

        vec3 col_agent=pow(log(agent_data+vec3(1)),vec3(agent_gamma));
        //vec3 col_agent=pow(agent_data,vec3(agent_gamma));
        float l=length(col_agent);
        col_agent/=l;
        l = (l*(1 + l / agent_opacity)) / (l + 1);
        col_agent*=l;
        out_col.xyz+=col_agent;
    }
    color=out_col;

]==],{
    uniforms={
        {"int","draw_layer"},
        {"float","agent_opacity"},
        {"float","agent_gamma"},
        {"float","agent_iterations"},
    },
    textures={{draw_agents.tex_offscreen,"tex_agents"}}
})
end

function save_img()
    img_buf=make_image_buffer(win_w,win_h)
    img_buf:read_frame()
    img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))))
end

local agents_per_bundle=10
function add_bundles( max_val )
    max_val=max_val or math.huge
    local bundles_left=math.floor((max_agent_count-agent_count)/agents_per_bundle)
    bundles_left=math.min(bundles_left,max_val)
    local choices={}
    for x=0,map_w-1 do
    for y=0,map_h-1 do
        --find location where to put
        local v=field:get(x,y)
        local len=math.sqrt(v.r*v.r+v.g*v.g)
        if len<1 then
            table.insert(choices,{len,x,y})
        end
    end
    end
    shuffle_table(choices)
    --place agents with spread X
    local spread=5
    if #choices<bundles_left then
        bundles_left=#choices
    end    
    for i=1,bundles_left do
        local choice_center=choices[i]
        for j=1,agents_per_bundle do
            local x,y=random_in_circle(spread,choice_center[2],choice_center[3])
            agents:set(agent_count,0,{x,y,0,0})
            agents_color:set(agent_count,0,{1,0,0,1})
            agent_count=agent_count+1
        end
    end

    draw_agents.update(agents,agent_count)
end
function reset_agents(  )
    --place agents with spread X
    local agent_bundles=10
    local spread=5
    agent_count=0
    add_bundles(agent_bundles)
    --upload into buffer
    draw_agents.update(agents,agent_count)
end
function clamp_coord( x,y )
    --torus
    if x>=map_w then x=x-map_w end
    if y>=map_h then y=y-map_h end
    if x<0 then x=x+map_w end
    if y<0 then y=y+map_h end
    return x,y
end
function sample_at( x,y )
    local lx=math.floor(x)
    local ly=math.floor(y)
    local hx=lx+1
    local hy=ly+1

    local tx=x-lx
    local ty=y-ly

    lx,ly=clamp_coord(lx,ly)
    hx,hy=clamp_coord(hx,hy)

    local vll=field:get(lx,ly)
    local vhl=field:get(hx,ly)
    local vlh=field:get(lx,hy)
    local vhh=field:get(hx,hy)

    local vxl_x=vll.r*(1-tx)+vhl.r*tx
    local vxl_y=vll.g*(1-tx)+vhl.g*tx

    local vxh_x=vlh.r*(1-tx)+vhh.r*tx
    local vxh_y=vlh.g*(1-tx)+vhh.g*tx

    local v_x=vxl_x*(1-ty)+vxh_x*ty
    local v_y=vxl_y*(1-ty)+vxh_y*ty
    return v_x,v_y
end
function rotate( x,y,angle )
  local s = math.sin(angle);
  local c = math.cos(angle);

  local xnew = x * c - y * s;
  local ynew = x * s + y * c;
  return xnew,ynew
end
function update_agents(  )
    local max_speed=2
    local max_speed_destroy=5
    local move_mult=0.125 --or dt
    local move_mult2=0.05
    local speed_mix=1
    local chance_min=0.00125
    --local gravity=0.5

    local i=1
    while i<agent_count do
        local a=agents:get(i-1,0)
        --get flow direction at location
        local dx,dy=sample_at(a.r,a.g)
        --[[
        local cx=map_w/2-a.r
        local cy=map_h/2-a.g

        local lc=math.sqrt(cx*cx+cy*cy)
        cx=cx/lc
        cy=cy/lc
        ]]

        local speed=math.sqrt(dx*dx+dy*dy)
        local normed_speed=speed/max_speed_destroy


        --print(i,a.r,a.g,dx,dy,speed)
        --at speed==max_speed chance=0.01
        --at speed==max_speed_destroy chance= 1
        local chance=((speed-max_speed)/(max_speed_destroy-max_speed))*(1-chance_min)+chance_min
        if chance<chance_min then
            chance=chance_min
        end
        --remove if too fast
        local remove=false
        if chance>math.random() then
            remove=true
        else
            --update speed
            --[[
            a.b=a.b+dx*move_mult2
            a.a=a.a+dy*move_mult2
            --]]
            -- [[
            local cur_speed=math.sqrt(a.b*a.b+a.a*a.a)
            cur_speed=cur_speed/max_speed_destroy
            --cur_speed=(cur_speed-max_speed)/max_speed_destroy
            if cur_speed<0 then cur_speed=0 end
            --idea is that when speed is close to max, force is backwards
            dx,dy=rotate(dx,dy,math.pi*cur_speed)
            a.b=a.b+dx*move_mult2
            a.a=a.a+dy*move_mult2
            --]]
            --[[
            a.b=a.b*(1-speed_mix)+dx*speed_mix
            a.a=a.a*(1-speed_mix)+dy*speed_mix
            --]]
            --update position

            a.r=a.r+a.b*move_mult
            a.g=a.g+a.a*move_mult
            if a.r<0 or a.g<0 or a.r>map_w or a.g>map_h then
                remove=true
            end
            a.r,a.g=clamp_coord(a.r,a.g)
            
        end
        if remove then
            agents:set(i-1,0,agents:get(agent_count-1,0))
            agents_color:set(i-1,0,agents_color:get(agent_count-1,0))
            agent_count=agent_count-1
        else
            i=i+1
        end
    end
    add_bundles()
    draw_agents.update(agents,agent_count)
end
iterations=iterations or 1
function update()
    __no_redraw()
    __clear()
    imgui.Begin("Magic system test")
    draw_config(config)
    if config.__change_events.any then
        draw_field.update_uniforms(config)
    end
    draw_field.update_uniforms{agent_iterations=iterations}
    if config.sim_agents then
        update_agents()
    end
    if config.draw_trails then
        draw_agents.draw(agent_count)
        iterations=iterations+1
    end
    draw_field.draw()
    imgui.Text(string.format("Agent count:%d",agent_count))
    if imgui.Button("Reset agents") then
        reset_agents()
        draw_agents.clear()
        iterations=1
    end
    if imgui.Button("Step agents") then
        update_agents()
    end
    if imgui.Button("Regen") then
        init_tools()
        update_field()
    end
    if imgui.Button("Clear") then
        draw_agents.clear()
        draw_field.clear()
        iterations=1
    end
    if imgui.Button("Save") then
        save_img()
    end
    imgui.End()
end