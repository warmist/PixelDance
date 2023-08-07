require "common"
require "colors"
--insipred by: https://www.reddit.com/r/generative/comments/hb0tli/recursive_disc_placement_algorithm/
--[[
	FORK OF: disk_tree.lua
	IDEAS:
		* cellular automatton like rules
		* add vornoi vis to shader to see what is saved (and no postprocess step)
		* all cells added calculate their position by calculating some potential function
			* only depending on existing cells
			* depending on existing AND new cells
		* try all the rules and see which has best potential
		* add angle(s) to potential function calc
		* do initial probes and then try gradient descent or sth for a few steps
--]]
local size_mult=1
local size=STATE.size
local aspect_ratio
local new_max_circles=500000
cur_circles=cur_circles or 0
local circle_size=20
local rules_apply_local_rotation=true
local rules_gen_angle_fixed_per_type=false
local rules_gen_angle_fixed_list=false

local placement_initial_probe=300 --TODO: full around
local plot_around=Grapher(placement_initial_probe)
local placement_iterations=10
local placement_radius_check=circle_size*50
local rules_global_priority=true

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
	{0.2,0.1,0.5},
	{2,1,4}
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
	{"depth_first",false,type="boolean"},
	{"start_angle",math.pi/3,type="angle",min=0,max=math.pi*2},
	{"start_angle2",math.pi/3,type="angle",min=0,max=math.pi*2},
	{"rand_angle",math.pi/3,type="angle"},
	{"rand_states",7,type="int",min=2,max=20},
	{"rand_size_min",0.4,type="float",min=0,max=1},
	{"placement",0,type="choice",choices={
		"single_center",
		"single_corner",
		"circle",
		"circle_dense",
		"borders",
		"border(s)_dense",
		"border split",
		}},
	{"seed",0,type="int",min=0,max=10000000},
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

rules= rules or {
	sizes={.8,0.4,0.3},
	interactions={
		[1]={ -1, 0.5,  200},
		[2]={0.5,   -100,  100},
		[3]={  200,   100,  -100}
	},
	recipes={
		[1]={{2,0.5},3},
		[2]={{3,0.05},1},
		[3]={{1,0.1},2}
	}
}
function print_rules_html(  )
	local ret=""
	string.format([[
###Rules
sizes=$[%s]$,
interactions=$<TODO array>$
recipes
]])
end
function rule_weight( rule,subrule )
	return -rules[rule][subrule][2]
end

function shuffle_table(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end
function make_recipe( id )
	local ret={}
	local chance_any_transform=0.3
	local chance_self=0
	
	for i=1,config.rand_states do
		if i==id then
			if math.random()<chance_self then
				table.insert(ret,{i,math.random()})
			end
		else
			if math.random()<chance_any_transform then
				table.insert(ret,{i,math.random()})
			end
		end
	end
	if #ret==0 then
		--TODO: breaks chance self...
		table.insert(ret,math.random(1,config.rand_states))
	end
	shuffle_table(ret)
	return ret
end
function generate_rules(  )
	math.randomseed(os.time())
	math.random()
	math.random()
	math.random()
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
	for i=1,count_states do
		rules.sizes[i]=math.random()*(1-config.rand_size_min)+config.rand_size_min
	end
	rules.interactions={}
	for i=1,count_states do
		rules.interactions[i]={}
	end
	for i=1,count_states do
		for j=i,count_states do
			local r=math.random()*2-1
			rules.interactions[i][j]=r
			rules.interactions[j][i]=r
		end
	end
	rules.recipes={}
	for i=1,count_states do
		rules.recipes[i]=make_recipe(i)
	end
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

function make_circle( x,y,radius,angle,type )
	local sum_rad=(radius+rules.sizes[type]*circle_size)
	--print("radius:",sum_rad)
	local a=angle

	return {x+math.cos(a)*sum_rad,y+math.sin(a)*sum_rad,a,encode_rad(rules.sizes[type]*circle_size,type)}
end
function circle_form_rule_init( x,y,angle,type )
	local a=angle
	return {x,y,a,encode_rad(rules.sizes[type]*circle_size,type)}
end
function ab_potential(dist_sqrd,a_type,b_type,p1,p2 )
	--local y=p1[2]
	--local dx=a[1]-b[1]
	--local dy=a[2]-b[2]
	--local dist=math.sqrt(dx*dx+dy*dy)
	--local dist=dist_sqrd
	--local dist=math.sqrt(dist_sqrd)

	--return rules.interactions[a_type][b_type]*dist
	--return rules.interactions[a_type][b_type]*math.exp(-dist_sqrd/(y+10))
	return rules.interactions[a_type][b_type]*math.exp(-dist_sqrd/100)
end
function calculate_potential( pos,new_circle,radius )
	local around=agent_tree:rnn(radius,pos)
	local sum=0
	local rad1,type1=decode_rad(new_circle[4])
	for i,v in ipairs(around) do
		local cdata=agent_data:get(v[1],0)
		local rad2,type2=decode_rad(cdata.a)
		sum=sum+ab_potential(v[2],type1,type2,pos,cdata)
	end
	return sum
end
local graph_done=false
function apply_rule( c,specific_rule)
	--get data about this circle
	local cdata=agent_data:get(c,0)
	local rad,t=decode_rad(cdata.a)
	--get the rule
	--print("Head",c,rad,t)
	local rule=rules.recipes[t]
	if rule==nil then
		print(rad,t)
		error("OOOOPS")
	end


	if rule.is_random then --TODO
		error("TODO")
		local r=rule[math.random(1,#rule)]
		local nc,fh=circle_form_rule(cdata.r,cdata.g,rad,cdata.b,r)
		cdata.b=cdata.b+(r[4] or 0)
		return add_circle_with_test(nc,true)
	else
		local applied_rule=0

		--local placement_iterations=10
		local angle_step=math.pi*2/placement_initial_probe
		local checks_done=0
		local best={potential=-math.huge}
		for i,v in ipairs(rule) do
			for angle=0,math.pi*2,angle_step do
				local a
				if rules_apply_local_rotation then
					a=angle+cdata.b
				else
					a=angle
				end
				local cell_type=v
				local weight=1
				if type(v)=="table" then
					cell_type=v[1]
					weight=v[2]
				end
				local nc=make_circle(cdata.r,cdata.g,rad,a,cell_type)
				local rad1=decode_rad(nc[4])
				if is_clear(nc[1],nc[2],rad1,circle_size*2) then
					checks_done=checks_done+1
					local potential=calculate_potential({nc[1],nc[2]},nc,placement_radius_check)*weight

					if potential>best.potential then
						best.potential=potential
						best.nc=nc
					end
					if not graph_done then
						plot_around:add_value(potential)
					end
				else
					if not graph_done then
						plot_around:add_value(0)
					end
				end
			end
		end
		graph_done=true
		if best.nc~=nil then
			if rules_global_priority then
				return best
			end
			applied_rule=applied_rule+1
			if add_circle(best.nc,true) then
				--break --uncomment for only one rule per circle
			end
		end
		return applied_rule
	end
end
function step_head( v ,specific_rule)
	local result=apply_rule(v,specific_rule)
	if rules_global_priority and result~=0 then
		table.insert(circle_data.heads,v)
		return result
	end
	if result~=0 then
		--if specific_rule==nil then --see if any applications for specific head exist in another place
			table.insert(circle_data.heads,v)
		--end
	end
end
function step(  )
	local steps_done=0
	local old_heads=circle_data.heads
	circle_data.heads={}
	local is_depth_first=config.depth_first
	graph_done=false
	if not is_depth_first then
		local best={potential=-math.huge}
		for i,v in ipairs(old_heads) do
			local result=step_head(v)
			if rules_global_priority then
				if result and best.potential<result.potential then
					best=result
				end
			end
			steps_done=steps_done+1
		end
		if rules_global_priority and best.nc then
			add_circle(best.nc,true)
		end
	else
		for i=1,#old_heads-1 do
			table.insert(circle_data.heads,old_heads[i])
		end
		-- [[
		if #old_heads>0 then
			step_head(old_heads[#old_heads])
		end
		--]]
		--[[
		if #old_heads>0 then
			step_head(old_heads[1])
		end
		--]]
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
function save_img_vor(path)
	img_buf=img_buf or make_image_buffer(size[1],size[2])
	local palette={}
	for i,v in ipairs(rules.sizes) do
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
	path=path or string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial
	if path=="<mem>" then
		return img_buf:save_mem()
	else
		img_buf:save(path)
		return path
	end
end
local ffi = require("ffi")
local b64= require("base64")
function encode_base64( buffer,size )
	print(buffer,size)
	local str=ffi.cast("unsigned char**",buffer)[0]

	for i=0,5 do
		print(str[i],string.char(str[i]))
	end
	
	return b64.encode_arr(str,size)
end
function save_html(  )
	
	local template=[==[
	                       <meta charset="utf-8" emacsmode="-*- markdown -*-">
                                  **Generated image infocard**
                               **Disk tree with potential well**

![Generated image](saved_1691395736.png)

# Principle

Try placing non-overlapping circles by calculating potential at fixed points around each existing point.

# Ruleset

Ruleset is defined as:

Sizes=$(1,2,3)$

Interactions strength $N=\left|\begin{matrix}1 & 0 & 2\\0 & 1 & 2\\0 & 0 & 3\\ \end{matrix}\right|$

Potential defined as 
$$f(a,b)=N_{a',b'}e^{|b-a|^2/100}$$ 
here $a'$ and $b'$ is type of circle trying to be added and existing circle.

# Starting seed

Starting seed in this case is: dense circle around center (X circles type Y)

# Palette

Used palette:
* 1 <span style="color:#FF0000">■□0xFF0000</span>
* 2 <span style="color:#00FF00">■□0x00FF00</span>
<!-- Markdeep: --><script src="https://casual-effects.com/markdeep/latest/markdeep.min.js?" charset="utf-8"></script>

]==]
-- [image.png]:data:image/png;base64,]==] doesnt work ;(
	local footer=[==[
<!-- Markdeep: --><script src="https://casual-effects.com/markdeep/latest/markdeep.min.js?" charset="utf-8"></script>
]==]
	--local base64_image=encode_base64(save_img_vor("<mem>"))
	--[[
		TODO
			* add inheritance tree (i.e. that idea-> other idea -> this one)
			* add rules in nice format
			* add potential function format
	--]]
	local fname=save_img_vor()
	local f=io.open("out.md.html","wb")
	f:write(string.format(header,fname))
	f:write(footer)
	f:close()
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
		math.randomseed(config.seed)
		local rr=math.random(1,#rules.sizes)

		local max_val=math.random(4,40)
		local placements={
			[0]=function ( 	)
				--Single in the center
				x=size[1]/2
				y=size[2]/2
				--add_circle({x,y,math.random()*math.pi*2,encode_rad(0.99*circle_size,1)},true)
				add_circle(circle_form_rule_init(x,y,config.start_angle,rr),true)	
			end,
			function (  )
				--single in corner
				x=0
				y=0
				--add_circle({x,y,math.random()*math.pi*2,encode_rad(0.99*circle_size,1)},true)
				add_circle(circle_form_rule_init(x,y,config.start_angle,rule[rr]),true)
			end,
			function (  )
				--circle around center
				local dist=math.random()*0.3+0.2
				local s=math.min(size[1],size[2])
				for i=0,max_val-1 do
					local spiral=1--(i+1)/max_val
					x=size[1]/2+s*dist*math.cos(i*math.pi*2/max_val)*spiral
					y=size[2]/2+s*dist*math.sin(i*math.pi*2/max_val)*spiral
					local a=math.random()*math.pi*2--angle_to_center(x,y)
					
					add_circle(circle_form_rule_init(x,y,a,rule[rr]),true)
				end
			end,
			function (  )
				-- dense circle at center
				local circle_rad=rules.sizes[rr]*circle_size
				local dist=big_circle_size(circle_rad,max_val)
				local s=math.min(size[1],size[2])
				for i=0,max_val-1 do
					local spiral=1--(i+1)/max_val
					x=size[1]/2+dist*math.cos(i*math.pi*2/max_val)*spiral
					y=size[2]/2+dist*math.sin(i*math.pi*2/max_val)*spiral
					local a=angle_to_center(x,y)
					add_circle(circle_form_rule_init(x,y,a+config.start_angle,rr),true)
				end
			end,
			function (  )
				-- borders
				local x_count=math.random(4,25)
				local y_count=x_count
				local x_step=math.floor(size[1]/x_count)
				local y_step=math.floor(size[2]/y_count)
				local offset=0--math.random(0,500)
				for ix=0,x_count do
					x=ix*x_step-offset
					y=0+offset

					local ang=angle_to_center(x,y)+config.start_angle
					add_circle(circle_form_rule_init(x,y,ang,rr),true)
					y=size[2]-offset
					ang=angle_to_center(x,y)+config.start_angle
					add_circle(circle_form_rule_init(x,y,ang,rr),true)
				end
				-- [=[
				for iy=0,y_count do
					x=0+offset
					y=iy*y_step-offset
					local ang=angle_to_center(x,y)+config.start_angle
					add_circle(circle_form_rule_init(x,y,ang,rr),true)
					x=size[1]-offset
					ang=angle_to_center(x,y)+config.start_angle
					add_circle(circle_form_rule_init(x,y,ang,rr),true)
				end
				--]=]
			end,
			function (  )
				-- dense border
				local angle=config.start_angle--math.random()*math.pi*2
				local circle_rad=rules.sizes[rr]*circle_size
				x=circle_rad
				y=circle_rad
				local count=math.floor(size[1]/(circle_rad*2))
				--for i=0,0 do
				for i=0,count do
					add_circle(circle_form_rule_init(x+i*circle_rad*2,y,angle,rr),true)
					--add_circle(circle_form_rule_init(x+i*circle_rad*2,size[2]-y,angle+math.pi,rule[rr]),true)
				end
			end,
			function (  )
				-- dense border x2
				local angle2=config.start_angle2--math.random()*math.pi*2
				local angle=config.start_angle--math.random()*math.pi*2

				local circle_rad=rule[rr][2]*circle_size
				local offset=circle_rad*4
				x=circle_rad
				y=circle_rad
				local count=math.floor(size[1]/(circle_rad*2))
				local count1=math.floor(count/2)
				local count2=count-count1
				local ofx=math.cos(angle)*offset
				local ofy=math.sin(angle)*offset
				--for i=0,0 do
				for i=0,count1 do
					add_circle(circle_form_rule_init(x+i*circle_rad*2,y,angle2,rule[rr]),true)
				end
				x=x+count1*circle_rad*2
				for i=0,count2 do
					add_circle(circle_form_rule_init(x+i*circle_rad*2+ofx,y+ofy,angle2,rule[rr]),true)
				end
			end
		}

		placements[config.placement]()
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
		save_img(need_save)
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
function full_sim(  )
	--[[
	local start_angle_min=215
	local start_angle_max=360
	--]]
	local start_angle_min=6.5
	local start_angle_max=6.7
	local step_count=20
	local step=(start_angle_max-start_angle_min)/step_count
	local counter=1
	for i=start_angle_min,start_angle_max,step do
		config.start_angle=i*math.pi/180
		restart()
		restart(true)
		config.autostep=true
		while #circle_data.heads > 0 do
			coroutine.yield()
		end
		save_img_vor(string.format("video/saved (%03d).png",counter))
		counter=counter+1
	end
    sim_thread=nil
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
    imgui.SameLine()
    if imgui.Button("save html") then
    	save_html()
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
    if not sim_thread then
        if imgui.Button("Simulate") then
           sim_thread=coroutine.create(full_sim)
        end
    else
        if imgui.Button("Stop Simulate") then
            sim_thread=nil
        end
    end
    plot_around:draw("Potential")
    imgui.End()
    if sim_thread then
        --print("!",coroutine.status(sim_thread))
        local ok,err=coroutine.resume(sim_thread)
        if not ok then
            print("Error:",err)
            sim_thread=nil
        end
    end
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