require "common"
require "colors"
--insipred by: https://www.reddit.com/r/generative/comments/hb0tli/recursive_disc_placement_algorithm/
--[[
	IDEAS:
		* export locations to vornoi and fill it out
		* markov style state changes (i.e. with chances for each one)
		* apply ALL subrules
		* apply ALL subrules in random order
--]]
local size_mult=1
local size=STATE.size
local aspect_ratio
local new_max_circles=500000
cur_circles=cur_circles or 0
local circle_size=8
--[[
function update_size(  )
	win_w=1280*size_mult
	win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
update_size()
]]
color_thingy=color_thingy or {
	{4,3,2},
	{6,4,3}
}
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

config=make_config({
	{"autostep",false,type="boolean"},
	{"depth_first",true,type="boolean"},
},config)

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
uniform vec3 c1;
uniform vec3 c2;
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
	float v=rand(trunc(pos.w)*100+3);
	vec3 c=palette(v,vec3(0.3),vec3(0.8),c1,c2);
	float aaf = fwidth(l);
	color=vec4(c,1)*smoothstep(l-aaf/2,l+aaf/2,fract(pos.w));
}
]==])
rules=rules or {
[1]={ is_random=false,
{2.44346,0.271191,1},
{-2.44346,0.774267,2},
{2.79253,0.431851,7},
},
[2]={ is_random=false,
{-1.74533,0.537546,2},
{-2.0944,0.689558,6},
},
[3]={ is_random=false,
{-0.349066,0.717698,3},
{2.44346,0.818042,6},
{-1.74533,0.896198,1},
{1.0472,0.295528,7},
},
[4]={ is_random=false,
{-1.39626,0.726966,6},
{2.44346,0.9133,7},
{0.698132,0.55345,2},
{1.39626,0.489166,5},
},
[5]={ is_random=false,
{1.0472,0.203509,7},
{0,0.211623,5},
{1.0472,0.550584,5},
{1.0472,0.624713,1},
},
[6]={ is_random=false,
{-1.0472,0.286695,3},
{-0.698132,0.487075,6},
{2.79253,0.327371,1},
{-1.39626,0.744421,2},
{1.0472,0.718456,5},
},
[7]={ is_random=false,
{2.44346,0.602303,5},
{0.349066,0.756157,7},
{0.698132,0.922361,1},
},
}
function make_subrule( id_self,max_state )
	local chance_self=0.05
	local max_rules=7
	local chance_random=0.5
	local c_rules=math.random(3,max_rules)
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
		local angle
		--angle=math.random()*math.pi/2-math.pi/4
		angle=math.random(-3,3)*rules.angle_step
		local size
		--size=rules.sizes[id_change]
		size=math.random()*0.8+0.2
		table.insert(ret,{angle,size,id_change})
	end
	return ret
end
function print_rules(  )
	print("rules={")
	for i,v in ipairs(rules) do
		print(string.format("[%d]={ is_random=%s,",i,tostring(v.is_random or false)))
		for ii,vv in ipairs(v) do
			print(string.format("{%g,%g,%g},",vv[1],vv[2],vv[3]))
		end
		print("},")
	end
	print("}")
end
function generate_rules(  )
	rules={}
	local count_states=math.random(2,7)
	rules.sizes={}
	--rules.angle_step=math.random()*math.pi*2
	rules.angle_step=math.pi/math.random(11,23)
	for i=1,count_states do
		rules.sizes[i]=math.random()*0.8+0.2
	end
	for i=1,count_states do
		rules[i]=make_subrule(i,count_states)
	end
	print_rules()
end
circle_data=circle_data or {
	heads={},
	heads_fails={}
}
function encode_rad( rad,type )
	return rad/circle_size+type
end
function decode_rad( v )
	local t=math.floor(v)
	return (v-t)*circle_size,t
end
function add_circle( c, is_head)
	if max_circles>cur_circles+1 then
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
	if x<0 or y<0 or x>size[1] or y>size[2] then
		return false
	end
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
	local a=angle+r[1]--*(math.random()*0.9+0.3)
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
function step_head( v )
	circle_data.heads_fails[v]=(circle_data.heads_fails[v] or 0)+1
	if not apply_rule(v) then
		if circle_data.heads_fails[v]<5 then
			table.insert(circle_data.heads,v)
		end
	else
		--if math.random()>0.5 then
		if circle_data.heads_fails[v]<5 then
			table.insert(circle_data.heads,v)
		end
		--end
	end
end
function step(  )
	local steps_done=0
	local old_heads=circle_data.heads
	circle_data.heads={}
	local is_depth_first=config.depth_first
	if not is_depth_first then
		for i,v in ipairs(old_heads) do
			step_head(v)
			steps_done=steps_done+1
		end
	else
		for i=1,#old_heads-1 do
			table.insert(circle_data.heads,old_heads[i])
		end
		if #old_heads>0 then
			step_head(old_heads[#old_heads])
		end
		steps_done=1
	end
	return steps_done
end
function save_img(  )
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function save_img_vor(  )
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local palette={}
	for i,v in ipairs(rules) do
		--local pix=img_buf.pixel()
		pix={r=0,g=0,b=0,a=0}
		palette[i]=pix
		pix.r=math.random(0,255)
		pix.g=math.random(0,255)
		pix.b=math.random(0,255)
		pix.a=255
	end
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	pix={r=0,g=0,b=0,a=0}
	for x=0,size[1]-1 do
		for y=0,size[2]-1 do

			local nn=agent_tree:knn(3,{x,y})
			local count=0
			for i,v in ipairs(nn) do
				local cdata=agent_data:get(v[1],0)
				local rad2,typ=decode_rad(cdata.a)
				--local w=v[2]+1
				--local w=1/(1+v[2])+1
				--local w=math.abs(math.cos(v[2]/20))+1
				--local w=math.log(v[2]+1)+1
				--local w=1
				local w=math.exp(-v[2]/5)
				count=count+w

				pix.r=pix.r+palette[typ].r*w
				pix.g=pix.g+palette[typ].g*w
				pix.b=pix.b+palette[typ].b*w
				pix.a=pix.a+palette[typ].a*w
			end
			pix.r=pix.r/count
			pix.g=pix.g/count
			pix.b=pix.b/count
			pix.a=255--pix.a/count

			--img_buf:set(x,y,palette[typ])
			img_buf:set(x,y,pix)
			pix={r=0,g=0,b=0,a=0}
		end
		print("done x:",x)
	end
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function angle_to_center( x,y )
	local vx=size[1]/2-x
	local vy=size[2]/2-y
	local l=math.sqrt(vx*vx+vy*vy)
	return math.atan2(vy/l,vx/l)
end
function restart( soft )
	local x,y
	if not soft then
		circle_data={
		heads={},
		heads_fails={},
		}
		agent_tree=kd_tree.Make(2)
		cur_circles=0
		x=size[1]/2
		y=size[2]/2
		--local rule=rules[1]
		--add_circle(circle_form_rule_init(x,y,math.random()*math.pi*2,rule[math.random(1,#rule)]),true)
	else
		local rule=rules[math.random(1,#rules)]
		local rr=math.random(1,#rule)

		local max_val=math.random(4,25)
		-- [[
		x=size[1]/2
		y=size[2]/2
		add_circle(circle_form_rule_init(x,y,math.random()*math.pi*2,rule[rr]),true)
		--]]

		--[[

		local dist=math.random()*0.3+0.2
		local s=math.min(size[1],size[2])
		for i=0,max_val-1 do
			local spiral=1--(i+1)/max_val
			x=size[1]/2+s*dist*math.cos(i*math.pi*2/max_val)*spiral
			y=size[2]/2+s*dist*math.sin(i*math.pi*2/max_val)*spiral
			local a=angle_to_center(x,y)
			print(x,y,a)
			add_circle(circle_form_rule_init(x,y,a,rule[rr]),true)
		end
		--]]
		--[=[
		local x_count=math.random(4,25)
		local y_count=x_count
		local x_step=math.floor(size[1]/x_count)
		local y_step=math.floor(size[2]/y_count)
		local offset=0--math.random(0,500)
		for ix=0,x_count do
			x=ix*x_step-offset
			y=0+offset

			local ang=angle_to_center(x,y)
			add_circle(circle_form_rule_init(x,y,ang,rule[rr]),true)
			y=size[2]-offset
			ang=angle_to_center(x,y)
			add_circle(circle_form_rule_init(x,y,ang,rule[rr]),true)
		end
		-- [=[
		for iy=0,y_count do
			x=0+offset
			y=iy*y_step-offset
			local ang=angle_to_center(x,y)
			add_circle(circle_form_rule_init(x,y,ang,rule[rr]),true)
			x=size[1]-offset
			ang=angle_to_center(x,y)
			add_circle(circle_form_rule_init(x,y,ang,rule[rr]),true)
		end
		--]=]
	end
	--add_circle({x,y,0,encode_rad(0.999*circle_size,1)},true)
	--add_circle({x+circle_size*2,y,0,encode_rad(0.999*circle_size,1)},true)
end
function draw(  )
	draw_circles:blend_add()
	draw_circles:use()
	draw_circles:set_i("csize",circle_size*2)
	draw_circles:set("rez",size[1],size[2]);
	draw_circles:set("c1",color_thingy[1][1],color_thingy[1][2],color_thingy[1][3])
	draw_circles:set("c2",color_thingy[2][1],color_thingy[2][2],color_thingy[2][3])
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
local count_frames=1
current_frame=0
function update(  )
    __clear()
    __no_redraw()
    __render_to_window()
    imgui.Begin("diskery")
    draw_config(config)
    if config.autostep then
    	current_frame=current_frame+1
    	if current_frame>count_frames then
    		local sum_steps=0
    		while sum_steps< 200 do
    			local s=step()
    			if s ==0 then break end
    			sum_steps=sum_steps+s
    		end
    		current_frame=0
    	end
    	if #circle_data.heads==0 then
    		config.autostep=false
    	end
    end
    if imgui.Button("Step") then
    	for i=1,5 do
    		step()
    	end
    end
    imgui.SameLine()
    imgui.Text(string.format("H:%d",#circle_data.heads))
    if imgui.Button("Restart") then
    	restart()
    end
    imgui.SameLine()
    if imgui.Button("Add Points") then
    	restart(true)
    end
    if imgui.Button("save") then
    	need_save=true
    end
    imgui.SameLine()
    if imgui.Button("save vornoi") then
    	save_img_vor()
    end
    if imgui.Button("RandRules") then
    	generate_rules()
    end
    imgui.SameLine()
    if imgui.Button("RandColors") then
    	for i,v in ipairs(color_thingy) do
    		for ii,vv in ipairs(v) do
    			v[ii]=math.random()*5
    		end
    	end
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