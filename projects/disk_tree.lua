require "common"
require "colors"
--insipred by: https://www.reddit.com/r/generative/comments/hb0tli/recursive_disc_placement_algorithm/
local size_mult=1
local size=STATE.size
local aspect_ratio
local new_max_circles=100000
cur_circles=cur_circles or 0
local circle_size=16
--[[
function update_size(  )
	win_w=1280*size_mult
	win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
update_size()
]]

function update_circle_buffer(  )
	if max_circles~=new_max_circles then
		max_circles=new_max_circles
		agent_data=make_flt_buffer(max_circles,1)
		agent_buffer=buffer_data.Make()
		agent_tree=kd_tree.Make(2)
	end

	agent_buffer:use()
	agent_buffer:set(agent_data.d,max_circles*4*4)
	__unbind_buffer()
end
update_circle_buffer()

function resize( w,h )
	size=STATE.size
	aspect_ratio=size[1]/size[2]
	img_buf=nil
end

draw_circles=shaders.Make(
[==[
#version 330
uniform int csize;
uniform vec2 rez;
layout(location = 0) in vec4 position;

out vec4 pos;
void main()
{
	vec2 normed=(position.xy/rez)*2-vec2(1,1);
	gl_PointSize=csize;
    gl_Position.xy = normed;
    gl_Position.z=0;
    gl_Position.w = 1.0;
    pos.xy=normed;
    pos.zw=position.zw;
}
]==],
[==[
#version 330
#line 37

uniform vec2 rez;

in vec4 pos;
out vec4 color;
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
float rand(float n){return fract(sin(n) * 43758.5453123);}
void main(){
	//center
	vec2 p = (gl_PointCoord - 0.5)*2;
	float l=length(p);
	float v=rand(trunc(pos.w)+154);
	vec3 c=palette(v,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.4,1.3,4.7),vec3(2.1,1.3,0.4));
	color=vec4(c,1)*smoothstep(l-0.05,l+0.05,fract(pos.w));
}
]==])
rules=rules or{
	[1]={
		is_random=false,
		{2*math.pi/3,0.8,1},
		{5*math.pi/3,0.8,2},
		{4*math.pi/3,0.8,1},
		{3*math.pi/3,0.8,2},
		{math.pi/3,0.8,2},
		--[[{angle_delta,radius,type,force_new},
		{angle_delta,radius,type,force_new},
		{angle_delta,radius,type,force_new},]]
	},
	[2]={
		is_random=true,
		{3*math.pi/6,0.4,1},
		{4*math.pi/6,0.4,1},
		{math.pi/6,0.4,1},
		{5*math.pi/6,0.4,1},
		{2*math.pi/6,0.4,1},
		{0,0.4,2},
		--[[{angle_delta,radius,type,force_new},
		{angle_delta,radius,type,force_new},
		{angle_delta,radius,type,force_new},]]
	},
}
function make_subrule( id_self,max_state )
	local chance_self=0.1
	local max_rules=15
	local chance_random=0.3
	local c_rules=math.random(4,max_rules)
	local ret={}
	if math.random()<chance_random then
		ret.is_random=true
	end
	for i=1,c_rules do
		local id_change
		if math.random()<chance_self then
			id_change=id_self
		else
			id_change=math.random(1,max_state)
		end
		table.insert(ret,{math.random()*math.pi*2,rules.sizes[id_change],id_change})
	end
	return ret
end
function generate_rules(  )
	rules={}
	local count_states=math.random(2,15)
	rules.sizes={}
	for i=1,count_states do
		rules.sizes[i]=math.random()*0.7+0.3
	end
	for i=1,count_states do
		rules[i]=make_subrule(i,count_states)
	end
end
circle_data=circle_data or {
	heads={}
}
function encode_rad( rad,type )
	return rad/circle_size+type
end
function decode_rad( v )
	local t=math.floor(v)
	return (v-t)*circle_size,t
end
function add_circle( c, is_head)

	agent_data:set(cur_circles,0,c)
	--print("Adding:",c[1],c[2],c[3],decode_rad(c[4]))
	agent_buffer:use()
	agent_buffer:set(agent_data.d,max_circles*4*4)
	__unbind_buffer()

	if is_head then
		table.insert(circle_data.heads,cur_circles)
	end

	agent_tree:add({c[1],c[2]})
	cur_circles=cur_circles+1
end
--[=[
function is_clear_check( id,x,y,my_rad,max_radius )

	local trg=agent_tree:rnn(max_radius*max_radius,{x,y})
	print(id,x,y,my_rad,max_radius,#trg)
	for i,v in ipairs(trg) do
		print(v[1])
		if v[1]~=id then
			local cdata=agent_data:get(v[1],0)
			local rad2=decode_rad(cdata.a)
			local dist_delta=math.sqrt(v[2])-my_rad-rad2
			print(string.format("CH:%d r:%g d:%g dd:%g",v[1],rad2,math.sqrt(v[2]),dist_delta))
			if dist_delta<0 then return false end
		end
	end
	return true
end
--]=]
function is_clear( x,y,my_rad,max_radius )
	local trg=agent_tree:rnn(max_radius*max_radius,{x,y})
	for i,v in ipairs(trg) do
		local cdata=agent_data:get(v[1],0)
		local rad2=decode_rad(cdata.a)
		local dist_delta=math.sqrt(v[2])-my_rad-rad2
		--print(string.format("CH:%d r:%g d:%g dd:%g",v[1],rad2,math.sqrt(v[2]),dist_delta))
		if dist_delta<0 then return false end
	end
	return true
end
function add_circle_with_test( c, is_head )
	local rad1=decode_rad(c[4])
	local ok=is_clear(c[1],c[2],rad1,circle_size*2)
	if ok then
		add_circle(c,is_head)
		return true
	end
end
function circle_form_rule( x,y,radius,angle,r )
	local sum_rad=(radius+r[2]*circle_size)+0.01
	--print("radius:",sum_rad)
	local a=angle+r[1]
	return {x+math.cos(a)*sum_rad,y+math.sin(a)*sum_rad,a,encode_rad(r[2]*circle_size,r[3])},r[4]
end
function circle_form_rule_init( x,y,angle,r )
	local a=angle+r[1]
	return {x,y,a,encode_rad(r[2]*circle_size,r[3])},r[4]
end
function apply_rule( c )
	local cdata=agent_data:get(c,0)

	local rad,t=decode_rad(cdata.a);
	--print("Head",c,rad,t)
	local rule=rules[t]
	if rule.is_random then
		local nc,fh=circle_form_rule(cdata.r,cdata.g,rad,cdata.b,rule[math.random(1,#rule)])
		return add_circle_with_test(nc,true)
	else
		for i,v in ipairs(rule) do
			local nc,fh=circle_form_rule(cdata.r,cdata.g,rad,cdata.b,v)
			if add_circle_with_test(nc,true) then
				return true
			end
		end
	end
end
function step(  )
	local old_heads=circle_data.heads
	circle_data.heads={}
	for i,v in ipairs(old_heads) do
		if not apply_rule(v) then
			table.insert(circle_data.heads,v)
		end
	end
end
function save_img(  )
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function restart( soft )
	local x,y
	if not soft then
		circle_data={
		heads={},
		list={}
		}
		agent_tree=kd_tree.Make(2)
		cur_circles=0
		x=size[1]/2
		y=size[2]/2
		--local rule=rules[1]
		--add_circle(circle_form_rule_init(x,y,math.random()*math.pi*2,rule[math.random(1,#rule)]),true)
	else
		local rule=rules[1]
		local rr=math.random(1,#rule)
		local max_val=math.random(4,25)
		local dist=math.random()*0.2+0.1
		for i=0,max_val-1 do
			x=size[1]/2+size[1]*dist*math.cos(i*math.pi*2/max_val)
			y=size[2]/2+size[2]*dist*math.sin(i*math.pi*2/max_val)
			add_circle(circle_form_rule_init(x,y,i*math.pi*2/max_val,rule[rr]),true)
		end
		
	end
	

	
	--add_circle({x,y,0,encode_rad(0.999*circle_size,1)},true)
	--add_circle({x+circle_size*2,y,0,encode_rad(0.999*circle_size,1)},true)
end
function draw(  )
	draw_circles:blend_add()
	draw_circles:use()
	draw_circles:set_i("csize",circle_size*2)
	draw_circles:set("rez",size[1],size[2]);
	agent_buffer:use()
	draw_circles:draw_points(0,cur_circles,4)
	__unbind_buffer()
	if need_save then
		save_img()
		need_save=nil
	end
end
function is_mouse_down(  )
    local ret=__mouse.clicked1 and not __mouse.owned1
    if ret then
        current_down=true
    end
    if __mouse.released1 then
        current_down=false
    end
    return current_down, __mouse.x,__mouse.y
end
function update(  )
    __clear()
    __no_redraw()
    __render_to_window()
    imgui.Begin("diskery")
    if imgui.Button("Step") then
    	for i=1,50 do
    		step()
    	end
    end
    if imgui.Button("Restart") then
    	restart()
    end
    imgui.SameLine()
    if imgui.Button("SoftRestart") then
    	restart(true)
    end
    if imgui.Button("save") then
    	need_save=true
    end
    if imgui.Button("RandRules") then
    	generate_rules()
    end
    imgui.End()

    --[[local d,x,y=is_mouse_down()
    if d then
    	local data=agent_data:get(1,0)
    	data.r=x
    	data.g=size[2]-y
    	local r,t=decode_rad(data.a)
    	if is_clear_check(0,x,size[2]-y,r,circle_size*2) then
    		t=1
    	else
    		t=30
    	end
    	data.a=encode_rad(r,t)
    	agent_data:set(1,0,data)
		agent_buffer:use()
		agent_buffer:set(agent_data.d,max_circles*4*4)
		__unbind_buffer()
    end]]
	draw()
end