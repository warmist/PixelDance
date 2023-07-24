require "common"
require "colors"
--insipred by: https://www.reddit.com/r/generative/comments/hb0tli/recursive_disc_placement_algorithm/
--[[
	IDEAS:
		* export locations to vornoi and fill it out
		* markov style state changes (i.e. with chances for each one)
		* apply ALL subrules
		* apply ALL subrules in random order
		* cellular automatton like rules
		* add vornoi vis to shader to see what is saved (and no postprocess step)
		* apply subrules in some priority order. E.g. all first rule, then all second rule,...
--]]
local size_mult=3
local size=STATE.size
local aspect_ratio
local new_max_circles=500000
cur_circles=cur_circles or 0
local circle_size=10
--[[
function update_size(  )
	win_w=1280*size_mult
	win_h=1280*size_mult--math.floor(win_w*size_mult*(1/math.sqrt(2)))
	aspect_ratio=win_w/win_h
	__set_window_size(win_w,win_h)
end
update_size()
--]]
color_thingy=color_thingy or {
	{4,3,2},
	{6,4,3}
}
function color_thingy_to_rgb( value )
	local ret={}
	for i=1,3 do
		ret[i]=0.3+0.8*math.cos(math.pi*2*(color_thingy[1][i]*value+color_thingy[2][i]))
		if ret[i]<0 then ret[i]=0 end
		if ret[i]>1 then ret[i]=1 end
		ret[i]=ret[i]*255
	end
	return ret
end
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
	{"start_angle",math.pi/3,type="angle",min=0,max=math.pi*2},
	{"rand_angle",math.pi/3,type="angle"},
	{"rand_states",7,type="int",min=2,max=20},
	{"rand_size_min",0.4,type="float",min=0,max=1},
	--[[
		local chance_self=0.05
	local max_rules=7
	local chance_random=0
	local c_rules=math.random(3,max_rules)]]
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
	float v=trunc(pos.w);//rand(trunc(pos.w)*100+3);
	vec3 c=palette(v,vec3(0.3),vec3(0.8),c1,c2);
	float aaf = fwidth(l);
	color=vec4(c,1)*smoothstep(l-aaf/2,l+aaf/2,fract(pos.w));
}
]==])

function big_circle_size( small_r,count )
	return small_r/math.sin(math.pi/count)
end
function small_circle_size( big_r,count )
	return math.sin(math.pi/count)*big_r
end
function small_circle_count( big_r,small_r )
	return math.pi/math.asin(small_r/big_r)
end
print("C:",small_circle_count(0.99+0.99,0.99))
--format: angle, size, type
local sl=0.99
local sm=small_circle_size(sl,5)
rules= rules or {
	types={
		0.99,0.5,0.5,0.25,
	},

[1]={ is_random=false,
{0,.99,2},
{math.pi/3,0.99,2},
{2*math.pi/3,0.99,2},
{3*math.pi/3,0.99,2},
{-math.pi/3,0.99,2},
{-2*math.pi/3,0.99,2},

--[[
{math.pi/6,0.99,1},
{2*math.pi/6,0.99,1},
{3*math.pi/6,0.99,1},
--]]
},
[2]={ is_random=false,

{0,sm,3},
{math.pi/5,sm,3},
{-math.pi/5,sm,3},
{2*math.pi/5,sm,3},
{-2*math.pi/5,sm,3},
},
[3]={ is_random=false,
{0,0.99,4},
--{-math.pi/4,0.99,1},
},
[4]={ is_random=false,
{0,sm,2},
--{-math.pi/4,0.99,1},
},
}
function make_subrule( id_self,max_state)
	local chance_self=0.1
	local max_rules=10
	local chance_random=0
	local c_rules=math.random(5,max_rules)
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
		--angle=angle_override or (math.random(-5,5)*rules.angle_step)
		angle=rules.angles[id_change]--*math.random(-5,5)
		local size
		--size=0.5--rules.sizes[id_change]
		size=rules.sizes[id_change]
		--size=math.random(1,15)/16
		--size=math.random()*0.8+0.2
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
	angle_choices={
		0,
		45/2,
		45,
		15,
		30,
		60,
		90,
		180,
	}
	rules={}
	local count_states=config.rand_states--math.random(2,7)
	rules.sizes={}
	rules.angles={}
	--rules.angle_step=math.random()*math.pi*2
	rules.angle_step=config.rand_angle--2*math.pi/math.random(3,5)
	for i=1,count_states do
		rules.sizes[i]=math.random()*(1-config.rand_size_min)+config.rand_size_min
	end
	for i=1,count_states do
		local r=(math.random(0,1)*2-1)*math.random(1,5)

		--rules.angles[i]=r*(math.pi*2*math.random(1,7)/7)
		--rules.angles[i]=math.random(-10,10)*rules.angle_step
		rules.angles[i]=r*angle_choices[math.random(1,#angle_choices)]*math.pi/180
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
	if rule==nil then
		print(rad,t)
	end
	if rule.is_random then
		local r=rule[math.random(1,#rule)]
		local nc,fh=circle_form_rule(cdata.r,cdata.g,rad,cdata.b,r)
		cdata.b=cdata.b+(r[4] or 0)
		return add_circle_with_test(nc,true)
	else
		local applied_rule=0
		for i,v in ipairs(rule) do
			local nc,fh=circle_form_rule(cdata.r,cdata.g,rad,cdata.b,v)
			if add_circle_with_test(nc,true) then
				cdata.b=cdata.b+(v[4] or 0)
				applied_rule=applied_rule+1
			end
		end
		return applied_rule
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
	write_circle_buffer()
	return steps_done
end
function save_img(  )
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
function lerp_color( a,b,val )
	return {
		r=a.r*(1-val)+b.r*val,
		g=a.g*(1-val)+b.g*val,
		b=a.b*(1-val)+b.b*val,
		a=a.a*(1-val)+b.a*val,
	}
end
function save_img_vor(  )
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local palette={}
	for i,v in ipairs(rules) do
		--local pix=img_buf.pixel()

		pix={r=0,g=0,b=0,a=0}
		palette[i]=pix
		--[[
		pix.r=math.random(0,255)
		pix.g=math.random(0,255)
		pix.b=math.random(0,255)
		--]]
		local col=color_thingy_to_rgb(i)
		pix.r=col[1]
		pix.g=col[2]
		pix.b=col[3]
		pix.a=255
	end
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	pix={r=0,g=0,b=0,a=0}
	for x=0,size[1]-1 do
		for y=0,size[2]-1 do

			
			--[[
			local nn=agent_tree:knn(5,{x,y})
			local count=0
			for i,v in ipairs(nn) do
				local cdata=agent_data:get(v[1],0)
				local rad2,typ=decode_rad(cdata.a)
				--local w=v[2]+1
				--local w=1/(1+v[2])+1
				--local w=math.abs(math.cos(v[2]/20))+1
				--local w=math.log(v[2]+1)+1
				--local w=1
				local w=math.exp(-v[2]/((5-i)*10))
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
			--]]
			--[===[simple vornoi
			local nn=agent_tree:knn(1,{x,y})
			local cdata=agent_data:get(nn[1][1],0)
			local rad2,typ=decode_rad(cdata.a)
			img_buf:set(x,y,palette[typ])
			--]===]
			--[===[vornoi with borders
			local border_size=1
			local nn=agent_tree:knn(2,{x,y})
			local pix_border={r=50,g=50,b=50,a=255}
			local bssq=border_size*border_size
			if #nn==2 then
				if math.abs(math.sqrt(nn[1][2])-math.sqrt(nn[2][2]))<border_size then
					img_buf:set(x,y,pix_border)
				else
					local cdata=agent_data:get(nn[1][1],0)
					local rad2,typ=decode_rad(cdata.a)
					img_buf:set(x,y,palette[typ])
				end
			end
			--]===]
			--[===[vornoi with borders (between different cells)
			local border_size=1
			local nn=agent_tree:knn(2,{x,y})
			local pix_border={r=50,g=50,b=50,a=255}
			local pix_back={r=15,g=10,b=10,a=255}
			local bssq=border_size*border_size
			local metaballness=0.25
			if #nn==2 then
				local cdata=agent_data:get(nn[1][1],0)
				local rad1,typ1=decode_rad(cdata.a)
				local cdata2=agent_data:get(nn[2][1],0)
				local rad2,typ2=decode_rad(cdata2.a)
				local d1=math.sqrt(nn[1][2])
				local d2=math.sqrt(nn[2][2])
				if typ1~=typ2 and math.abs(d1-d2)<border_size then
					img_buf:set(x,y,pix_border)
					--img_buf:set(x,y,pix_back)
				else
					--if 1/d1+1/d2<metaballness and typ1==typ2 then
					--if 1/d1+1/d2<metaballness then
					--if 1/d1+1/d2<metaballness and typ1~=typ2 then
					--if typ1~=typ2 then
						--img_buf:set(x,y,pix_back)
					--else
						local cdata=agent_data:get(nn[1][1],0)
						local rad2,typ=decode_rad(cdata.a)
						img_buf:set(x,y,palette[typ])
					--end
				end
			end
			--]===]
			-- [===[vornoi with borders AA
			local border_size=1.5
			local nn=agent_tree:knn(2,{x,y})
			local pix_border={r=50,g=50,b=50,a=255}
			if #nn==2 then
				local a1=agent_data:get(nn[1][1],0)
				local a2=agent_data:get(nn[2][1],0)
				--vector from one to the other
				local vec={a2.r-a1.r,a2.g-a1.g}
				local len=math.sqrt(vec[1]*vec[1]+vec[2]*vec[2])
				local dprod=(x-a1.r)*vec[1]+(y-a1.g)*vec[2]
				local scale=dprod/(len*len)
				local border_dist=len*math.abs(0.5-scale)

				if border_dist>border_size then
					local cdata=agent_data:get(nn[1][1],0)
					local rad2,typ=decode_rad(cdata.a)
					img_buf:set(x,y,palette[typ])
				else
					local cdata=agent_data:get(nn[1][1],0)
					local rad2,typ=decode_rad(cdata.a)

					local ndist=border_dist/border_size
					img_buf:set(x,y,lerp_color(pix_border,palette[typ],ndist))
					--img_buf:set(x,y,pix_border)
				end
			end
			
			--]===]
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
function write_circle_buffer(  )
	agent_buffer:use()
	agent_buffer:set(agent_data.d,max_circles*4*4)
	__unbind_buffer()
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

		local max_val=math.random(4,40)
		--[[ Single in the center
		x=size[1]/2
		y=size[2]/2

		--add_circle({x,y,math.random()*math.pi*2,encode_rad(0.99*circle_size,1)},true)
		add_circle(circle_form_rule_init(x,y,math.random()*math.pi*2,rule[rr]),true)
		--]]
		--[[ Single in the center
		x=0
		y=0

		--add_circle({x,y,math.random()*math.pi*2,encode_rad(0.99*circle_size,1)},true)
		add_circle(circle_form_rule_init(x,y,math.random()*math.pi*2,rule[rr]),true)
		--]]

		--[[ circle around center

		local dist=math.random()*0.3+0.2
		local s=math.min(size[1],size[2])
		for i=0,max_val-1 do
			local spiral=1--(i+1)/max_val
			x=size[1]/2+s*dist*math.cos(i*math.pi*2/max_val)*spiral
			y=size[2]/2+s*dist*math.sin(i*math.pi*2/max_val)*spiral
			local a=math.random()*math.pi*2--angle_to_center(x,y)
			
			add_circle(circle_form_rule_init(x,y,a,rule[rr]),true)
		end
		--]]
		-- [[ dense circle around center
		local circle_rad=rule[rr][2]*circle_size
		local dist=big_circle_size(circle_rad,max_val)
		local s=math.min(size[1],size[2])
		for i=0,max_val-1 do
			local spiral=1--(i+1)/max_val
			x=size[1]/2+dist*math.cos(i*math.pi*2/max_val)*spiral
			y=size[2]/2+dist*math.sin(i*math.pi*2/max_val)*spiral
			local a=angle_to_center(x,y)
			add_circle(circle_form_rule_init(x,y,a+config.start_angle,rule[rr]),true)
		end
		--]]
		--[=[ borders
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
		--[[ Dense border
		local angle=config.start_angle--math.random()*math.pi*2
		local circle_rad=rule[rr][2]*circle_size
		x=circle_rad
		y=circle_rad
		local count=math.floor(size[1]/(circle_rad*2))
		--for i=0,0 do
		for i=0,count do
			add_circle(circle_form_rule_init(x+i*circle_rad*2,y,angle,rule[rr]),true)
			--add_circle(circle_form_rule_init(x+i*circle_rad*2,size[2]-y,angle+math.pi,rule[rr]),true)
		end

		--]]
	end
	write_circle_buffer()
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
    	--for i=1,5 do
    		step()
    	--end
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