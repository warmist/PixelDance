--[===[
2D CA but!:
	* no create/destroy! only move
	* if can't move, dont!
	* gen random rules, check out the "dynamics" and "meta-atoms"
	* "permutation city"
--]===]
require 'common'
require 'bit'

local win_w=1024
local win_h=1024

__set_window_size(win_w,win_h)
local oversample=1/2

local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local aspect_ratio=win_w/win_h
local map_aspect_ratio=map_w/map_h
local size=STATE.size

is_remade=false
local figure_w=45
local max_particle_count=figure_w*figure_w

function update_buffers()
	if particles_pos==nil or particles_pos.w~=max_particle_count then
		particles_pos=make_flt_half_buffer(max_particle_count,1)
		particles_age=make_float_buffer(max_particle_count,1)
        is_remade=true
	end
    if static_layer==nil or static_layer.w~=map_w or static_layer.h~=map_h then
        static_layer=make_image_buffer(map_w,map_h)
        movement_layer_target=make_char_buffer(map_w,map_h) --a 0,1,2 would be enough
        movement_layer_source=make_char_buffer(map_w,map_h) --direction of movement
        is_remade=true
    end
end
update_buffers()


config=make_config({
    {"pause",false,type="bool"},
    {"draw",true,type="bool"},
    {"noise_count",4,type="int",min=0,max=figure_w*figure_w},
    {"long_dist_range",2,type="int",min=0,max=5},
    {"long_dist_offset",0,type="int",min=0,max=7},
    {"zoom",1,type="float",min=1,max=10},
    {"t_x",0,type="float",min=0,max=1},
    {"t_y",0,type="float",min=0,max=1},
    },config)
dist_constraints={}


local draw_shader=shaders.Make(
[==[
#version 330
#line 47
out vec4 color;
in vec3 pos;

uniform ivec2 res;
uniform sampler2D tex_main;
uniform vec2 zoom;
uniform vec2 translate;
#define DOWNSAMPLE 0
#define SMOOTHDOWNSAMPLE 0
void main(){
    vec2 normed=(pos.xy+vec2(1,-1))*vec2(0.5,-0.5);
    normed=(normed-vec2(0.5,0.5)-translate)/zoom+vec2(0.5,0.5);
    //normed/=2;
#if DOWNSAMPLE
    normed*=vec2(res)/2;
    normed=floor(normed)/(vec2(res)/2);
#endif
#if SMOOTHDOWNSAMPLE
    vec4 pixel=textureOffset(tex_main,normed,ivec2(0,0))+
        textureOffset(tex_main,normed,ivec2(1,0))+
        textureOffset(tex_main,normed,ivec2(0,1))+
        textureOffset(tex_main,normed,ivec2(1,1));
    pixel/=4;
#else
    vec4 pixel=texture(tex_main,normed);
#endif
    color=vec4(pixel.xyz,1);
}
]==])
local place_pixels_shader=shaders.Make(
[==[
#version 330
layout(location = 0) in vec3 position;
layout(location = 1) in float particle_age;

out vec3 pos;
out vec4 col;

uniform int pix_size;
uniform vec2 res;
uniform vec2 zoom;
uniform vec2 translate;

#define NO_TRANSIENTS 0
#define LOG_AGE 0
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
    gl_PointSize=int(pix_size*abs(zoom.y));
    vec2 pix_int_pos=floor(position.xy+vec2(0.5,0.5))+vec2(0.5,0.5);
    vec2 pix_pos=(pix_int_pos/res-vec2(0.5,0.5))*vec2(2,-2);
    gl_Position.xy=pix_pos;
    gl_Position.xy=(gl_Position.xy*zoom+translate*vec2(2,-2));
    gl_Position.zw=vec2(0,1.0);//position.z;
    pos=gl_Position.xyz;
    

    //col=texelFetch(pcb_colors,ivec2(particle_type,0),0);
#if LOG_AGE
    float pa=log(particle_age+1);
#else
    float pa=particle_age;
#endif
    //vec3 c=palette(pa,vec3(0.5),vec3(0.5),vec3(1),vec3(0.0,0.33,0.67));
    vec3 c=palette(pa,vec3(0.8,0.5,0.4),vec3(0.2,0.4,0.2),vec3(2,1,1),vec3(0.0,0.25,0.25));
    //vec3 c=palette(pa,vec3(0.2,0.7,0.4),vec3(0.6,0.9,0.2),vec3(0.6,0.8,0.7),vec3(0.5,0.1,0.0));
#if NO_TRANSIENTS
    if(particle_age<0.05)
        c=vec3(0);
#endif
    col=vec4(c,1);
    //if(col.a!=0)
    //    col.a=1;
    /*
    if (particle_type==1u)
        col=vec4(0,0,1,0.8);
    else if(particle_type==0u)
        col=vec4(0,0,0,0);
    else
    {
        float v=particle_type;
        col=vec4(1,v/255.0,v/255.0,0.5);
    }
    //*/
}
]==],[==[
#version 330

out vec4 color;
in vec4 col;
in vec3 pos;
void main(){
    color=col;//vec4(1,(particle_type*110)/255,0,0.5);
}
]==])
dir_to_dx={
	[0]={0,0},
	[1]={1,0},
	[2]={1,1},
	[3]={0,1},
	[4]={-1,1},
	[5]={-1,0},
	[6]={-1,-1},
	[7]={0,-1},
	[8]={1,-1},
}
--[[
    432
    501
    678
--]]
rules=rules or {

}
function rnd( v )
    return math.random()*v*2-v
end
function fix_pos( p )
	local ret={r=p.r,g=p.g}
	if ret.r<0 then ret.r=map_w-1 end
	if ret.g<0 then ret.g=map_h-1 end
	if ret.r>=map_w then ret.r=0 end
	if ret.g>=map_h then ret.g=0 end
	return ret
end
function displace_by_dir_nn( pos,dir,dist )
    dist=dist or 1
	local ret={r=pos.r,g=pos.g}
	local dx=dir_to_dx[dir]
	ret.r=round(ret.r+dx[1]*dist)
	ret.g=round(ret.g+dx[2]*dist)
	return fix_pos(ret)
end
function get_nn( pos )
	--local ret={}
	local value=0
	for i=1,8 do
		local t=displace_by_dir_nn(pos,i)
		local v=static_layer:get(t.r,t.g)
		if v.a>0 then
			--ret[i]=true
			value=value+math.pow(2,i-1)
		end
	end
	return value
end
function value_to_nn_string( v )
    local ret=""
    local permutation={4,3,2,5--[[0]],1,6,7,8}

    local id=0
    for i=1,8 do
        if (id)%3==0 then
            ret=ret.."\n"
        end
        if i==5 then
            ret=ret.."X"
            id=id+1
        end
        id=id+1
        local vv=permutation[i]
        if bit.band(v,math.pow(2,vv-1))>0 then
            ret=ret..'*'
        else
            ret=ret..'o'
        end
    end
    return ret
end
function dir_to_arrow_string( d )
    local tbl={
        [0]=
[[
   
 * 
   
]],
        [1]=
[[
   
 ->
   
]],
        [2]=
[[
  ^
 / 
   
]],
        [3]=
[[
 ^ 
 | 
   
]],
        [4]=
[[
^  
 \ 
   
]],
        [5]=
[[
   
<- 
   
]],
        [6]=
[[
   
 / 
v  
]],
        [7]=
[[
   
 | 
 v 
]],
        [8]=
[[
   
 \ 
  v
]],
    }
    return tbl[d]
end
function concat_byline( s1,s2 )
    local ret=""
    local f,ns,s_other_start=s2:gmatch("[^\r\n]+")
    for s in s1:gmatch("[^\r\n]+") do
        
        local s_other=f(ns,s_other_start)
        ret=ret..s..s_other.."\n"
    end
    return ret
end
function displace_by_dir( pos,dir )
    local ret={r=pos.r,g=pos.g}
    local dx=dir_to_dx[dir]
    ret.r=round(ret.r+dx[1])
    ret.g=round(ret.g+dx[2])
    return fix_pos(ret)
end
function calculate_long_range_rule( pos )

    for r=2,config.long_dist_range do
        local count_in_range=0
        local last_dir=0
        for j=1,8 do
            local tpos=displace_by_dir_nn(pos,j,r)
            local sl=static_layer:get(tpos.r,tpos.g)
            if sl.a>0 then
                count_in_range=count_in_range+1
                last_dir=j
            end
        end
        if count_in_range>1 then
            return 0 --more than one direction to move, so don't
        elseif count_in_range==1 then
            --if r>3 then
                return rotate_dir(last_dir,config.long_dist_offset)
            --else
            --    return last_dir
            --end
        end
    end
    return 0 --couldn't find any thing
end
function calculate_rule( pos )
	if #rules==0 then
		return math.random(0,8)
	else
		local v=get_nn(pos)
        if v==0 and config.long_dist_range>=2 then
            return calculate_long_range_rule(pos)
        end
		return rules[v] or 0
	end
end

function round( x )
	return math.floor(x+0.5)
end

function particle_step(  )
	for x=0,map_w-1 do
		for y=0,map_h-1 do
			movement_layer_target:set(x,y,0)
		end
	end

	local trg_pos={}

    for i=0,max_particle_count-1 do
        local pos=fix_pos(particles_pos:get(i,0))
        local dir=calculate_rule(pos)
        local tpos=displace_by_dir(pos,dir)
        local sl=static_layer:get(tpos.r,tpos.g)
        if sl.a>0 then
        	dir=0
        	tpos=displace_by_dir(pos,dir)
        end
        trg_pos[i]={dir,tpos}
        local tp=movement_layer_target:get(tpos.r,tpos.g)
        if tp<254 then
        	tp=tp+1
        end
        movement_layer_target:set(tpos.r,tpos.g,tp)
        --movement_layer_source:set(round(pos.r),round(pos.g),dir)
    end

    for i=0,max_particle_count-1 do
        local pos=fix_pos(particles_pos:get(i,0))
        --local dir=movement_layer_source:get(round(pos.r),round(pos.g))
        --local tpos=displace_by_dir(pos,dir)
        local tpos=trg_pos[i][2]
        local dir=trg_pos[i][1]
        local tp=movement_layer_target:get(tpos.r,tpos.g)

        if tp<2 and dir~=0 then
        	pos.r=tpos.r
        	pos.g=tpos.g
        	particles_pos:set(i,0,pos)
        	particles_age:set(i,0,0)
        else
        	--movement_layer_target:set(tpos.r,tpos.g,tp-1)
    		local a=particles_age:get(i,0)
        	particles_age:set(i,0,a+0.002)
        end
    end
end
if tex_pixel==nil then
    update_buffers()
    tex_pixel=textures:Make()
    tex_pixel:use(0,0,1)
    tex_pixel:set(static_layer.w,static_layer.h,0)
end

function scratch_update(  )
	--clear the texture
    draw_shader:use()
    tex_pixel:use(0,0,1)
    if not tex_pixel:render_to(static_layer.w,static_layer.h) then
        error("failed to set framebuffer up")
    end
    __setclear(0,0,0,0)
    __clear()

    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("res",map_w,map_h)
    draw_shader:set("zoom",1*map_aspect_ratio,1)
    draw_shader:set("translate",0,0)
    --draw_shader:draw_quad()

    place_pixels_shader:use()
    tex_pixel:use(0,0,1)
    if not tex_pixel:render_to(static_layer.w,static_layer.h) then
        error("failed to set framebuffer up")
    end

    place_pixels_shader:set_i("pix_size",1)
    place_pixels_shader:set("res",map_w,map_h)
    place_pixels_shader:set("zoom",1*map_aspect_ratio,-1)
    place_pixels_shader:set("translate",0,0)

    place_pixels_shader:push_attribute(particles_age.d,"particle_age",1,GL_FLOAT)
    place_pixels_shader:draw_points(particles_pos.d,max_particle_count)
    __render_to_window()
    static_layer:read_texture(tex_pixel)
end
function sim_tick(  )
    int_count=0
    scratch_update()
    particle_step()
    scratch_update()
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
function save_gif_frame(  )
	if img_buf_save==nil or img_buf_save.w~=size[1] then
    	img_buf_save=make_image_buffer(size[1],size[2])
    end
	if giffer==nil then
		return
	end
    img_buf_save:read_frame()
    giffer:frame(img_buf_save)
end
function rotate_pattern(p)
	local ret=p*2
	if ret>=256 then
		ret=ret-256+1
	end
	return ret
end
function rotate_pattern_left(p)
	local v=p%2
	local ret=math.floor(p/2)
	if v==1 then
		ret=ret+128
	end
	return ret
end
function rotate_dir( d,r )
	if d==0 then
		return 0
	end
	return (d+r-1)%8+1
end
function classify_patterns()
	print("=========================")
	local store_id=1
	local ret_patern_store={}
	local pattern_store={}

	for i=1,255 do
		local old_pattern
		local r=0
		local rp=i
		for j=1,8 do
			rp=rotate_pattern_left(rp)
			local sp=pattern_store[rp]
			if sp then
				old_pattern={id=sp.id,sym=sp.sym,rot=j}
				ret_patern_store[i]=old_pattern
				break
			end
			if rp==i then
				r=j
				break
			end
		end
		if old_pattern then
			print(i,old_pattern.id,old_pattern.sym,old_pattern.rot)
		else
			pattern_store[i]={id=store_id,sym=r,rot=0}
			print(i,store_id,r,0)
			store_id=store_id+1
			ret_patern_store[i]=pattern_store[i]
		end
	end
	return ret_patern_store
end

function update()
    __clear()
    __no_redraw()

    imgui.Begin("Cellular move")
    draw_config(config)

    --imgui.SameLine()
    if imgui.Button("Reset world") then
        static_layer=nil
        update_buffers()
        need_clear=true
    end
    local sim_done=false
    if imgui.Button("step") then
        sim_tick()
        sim_done=true
    end
 	if imgui.Button("rand rules") then
 		rules={}
 		rules[0]=0
        --[[
        for i=1,255 do
        	rules[i]=math.random(0,8)
        end
        --]]
        --[[
        for i=1,8 do
        	rules[math.pow(2,i)]=math.random(0,8)
        end

        for i=1,8 do
        	for j=1,8 do
        		if i~=j then
        			rules[math.pow(2,i)+math.pow(2,j)]=math.random(0,8)
        		end
        	end
        end
        --]]
        -- [==[
        local pt=classify_patterns()
        local pt_rules={}
        for i,v in pairs(pt) do
        	-- [[
            if pt_rules[v.id]==nil then
                if v.sym==8  then
                    pt_rules[v.id]={math.random(0,8),i}
                else
                    pt_rules[v.id]={0,i}
                end
            end
        	--]]
        end
        local already_printed={}
        for i,v in ipairs(pt) do
            if not already_printed[v.id] then
                if v.sym==8 then
                    print("Group id:",v.id)
                    local actual_dir=rotate_dir(pt_rules[v.id][1],v.rot)
                    print(concat_byline(value_to_nn_string(pt_rules[v.id][2]),dir_to_arrow_string(actual_dir)))
                    already_printed[v.id]=true
                end
            end
        end
        for i,v in pairs(pt) do
        	-- [[
        	if v.sym==8 then
        		rules[i]=rotate_dir(pt_rules[v.id][1],v.rot)
        	else
        		rules[i]=0
        	end
        	--]]
        end
        --]==]
    end
    if imgui.Button("save rules") then
        local f=io.open("rules.txt","w")
        for i=1,255 do
        	f:write(i," ",rules[i],"\n")
        end
        f:close()
    end
    if imgui.Button("clear rules") then
        rules={}
    end
	if imgui.Button("Save Gif") then
		if giffer~=nil then
			giffer:stop()
		end
		save_gif_frame()
		giffer=gif_saver(string.format("saved_%d.gif",os.time(os.date("!*t"))),
			img_buf_save,500,4)
	end
	imgui.SameLine()
	if imgui.Button("Stop Gif") then
		if giffer then
			giffer:stop()
			giffer=nil
		end
	end
    if is_remade then
        --print("==============================")
        is_remade=false

        -- [[
        for i=0,max_particle_count-1 do
            --[[
            local x=math.random(0,map_w-1)
            local y=math.random(0,map_h-1)
            if static_layer:get(x,y).a==0 then
                particles_pos:set(i,0,{x,y})
            else
                local x=math.random(0,map_w-1)
                local y=math.random(0,map_h-1)
                particles_pos:set(i,0,{x,y})
            end
            --]]
            -- [[
            local r=math.sqrt(math.random())*map_w/2

            local a=math.random()*math.pi*2

            --]]
            --particles_pos:set(i,0,{math.random()*map_w/2+map_w/4,math.random()*map_h/2+map_h/4})
            --particles_pos:set(i,0,{map_w/2+math.cos(a)*r,map_h/2+math.sin(a)*r})
            -- [[
            local w=figure_w
            particles_pos:set(i,0,{map_w/2+i%w-math.floor(w/2),map_h/2+math.floor(i/w)-math.floor(w/2)})
            particles_age:set(i,0,0)
            --]]
        end
        --]]
        -- [[
        local noise_count=config.noise_count
        for i=1,noise_count do
            local i=math.floor((max_particle_count-1)*(i-1)/(noise_count-1)+0.5)--math.random(0,max_particle_count-1)
            local x=math.random(0,map_w-1)
            local y=math.random(0,map_h-1)
            particles_pos:set(i,0,{x,y})
        end
        --]]
        scratch_update()
    end
    if not config.pause then
        sim_tick()
       	sim_done=true
        --add_particle{map_w/2,0,math.random()*0.25-0.125,math.random()-0.5,3}
    end
    imgui.SameLine()
    if imgui.Button("Save") then
        need_save=true
    end
    imgui.End()
    __render_to_window()

    update_buffers()
    --[[
    for x=0,map_w-1 do
    	for y=0,map_h-1 do
    		local v=static_layer:get(x,y)
    		if math.random()>0.99 and v.a>0 then
    			print(x,y,math.abs(v.a-255*0.05))
    		end
    	end
    end
    --]]
    draw_shader:use()

    tex_pixel:use(0,0,1)
    static_layer:write_texture(tex_pixel)


    draw_shader:set_i("tex_main",0)
    draw_shader:set_i("res",map_w,map_h)
    draw_shader:set("zoom",config.zoom*map_aspect_ratio,config.zoom)
    draw_shader:set("translate",config.t_x,config.t_y)
    draw_shader:draw_quad()
	if giffer and sim_done then
        if giffer:want_frame() then
			save_gif_frame()
		end
		giffer:frame(img_buf_save)
	end
    if need_save then
        save_img()
        need_save=false
    end
    --[[
    local tx,ty=config.t_x,config.t_y
    local c,x,y,dx,dy= is_mouse_down2()
    local update_bounds=false
    if c then
        dx,dy=dx/size[1],dy/size[2]
        config.t_x=config.t_x-dx/config.zoom
        config.t_y=config.t_y+dy/config.zoom
        update_bounds=true
    end
    if __mouse.wheel~=0 then
        local pfact=math.exp(__mouse.wheel/10)
        config.zoom=config.zoom*pfact
        --config.t_x=config.t_x*pfact
        --config.t_y=config.t_y*pfact
        update_bounds=true
    end
    if update_bounds then
        config.t_x=clamp(config.t_x,0,1-1/config.zoom)
        config.t_y=clamp(config.t_y,0,1-1/config.zoom)
    end
    ]]
end