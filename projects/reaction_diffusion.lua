require "common"
--[[
	TODO:
		* add oversample
		* add MAX Over T for some T
		* multi scale turing patterns: https://faculty.ac/image-story/a-machine-in-motion/
		* https://elifesciences.org/articles/14022
]]
config=make_config({
	{"pause",false,type="boolean"},
	{"clamp_edges",false,type="boolean"},
	{"diff_a",0.024,type="float",min=0,max=1},
	{"diff_b",0.024,type="float",min=0,max=1},
	{"diff_c",2.5,type="float",min=0,max=1},
	{"diff_d",0.125,type="float",min=0,max=1},
	{"kill",0.2,type="float",min=0,max=1},
	{"feed",4.5,type="float",min=0,max=1},
	{"k3",0.2,type="float",min=0,max=1},
	{"k4",0.0,type="float",min=0,max=1},
	{"region_size",0.5,type="float",min=0.01,max=1},
	{"gamma",1,type="float",min=0.01,max=5},
	{"gain",1,type="float",min=-5,max=5},
	{"draw_comp",0,type="int",min=0,max=3},
	{"animate",false,type="boolean"},
},config)

function update_size()
	local trg_w=1080
	local trg_h=1080
	--this is a workaround because if everytime you save
	--  you do __set_window_size it starts sending mouse through windows. SPOOKY
	if win_w~=trg_w or win_h~=trg_h then
		win_w=trg_w
		win_h=trg_h
		aspect_ratio=win_w/win_h
		__set_window_size(win_w,win_h)
	end
end
update_size()

local size=STATE.size
img_buf=img_buf or make_image_buffer(size[1],size[2])
react_buffer=react_buffer or multi_texture(size[1],size[2],2,1)
io_buffer=io_buffer or make_flt_buffer(size[1],size[2])

map_region=map_region or {-1,0,0,0}
thingy_string=thingy_string or "-c.x*c.y*c.y,0,0,+c.x*c.y*c.y"

--feed_kill_string=feed_kill_string or "feed_rate*(1-c.x),-(kill_rate)*c.y,-(kill_rate)*(c.z),-(kill_rate)*c.w"
feed_kill_string="-kill_rate,-kill_rate,-kill_rate,feed_rate"
local oversample=1
function resize( w,h )
	local ww=w*oversample
	local hh=h*oversample
	img_buf=make_image_buffer(ww,hh)
	size=STATE.size
	react_buffer:update_size(ww,hh)
	io_buffer=make_flt_buffer(ww,hh);
end

function count_lines( s )
	local n=0
	for i in s:gmatch("\n") do n=n+1 end
	return n
end

function shader_make( s_in )
	local sl=count_lines(s_in)
	s="#version 330\n#line "..(debug.getinfo(2, 'l').currentline-sl).."\n"
	s=s..s_in
	return shaders.Make(s)
end


local react_diffuse
function update_diffuse(  )
react_diffuse=shaders.Make(string.format([==[
#version 330
#line 49

out vec4 color;
in vec3 pos;

uniform vec4 diffusion;
uniform vec4 kill_feed;

uniform sampler2D tex_main;
uniform float dt;

uniform vec4 map_region;
vec4 laplace(vec2 pos) //with laplacian kernel (cnt -1,near .2,diag 0.05)
{
	vec4 ret=vec4(0);
	ret+=textureOffset(tex_main,pos,ivec2(-1,-1))*0.05;
	ret+=textureOffset(tex_main,pos,ivec2(-1,1))*0.05;
	ret+=textureOffset(tex_main,pos,ivec2(1,-1))*0.05;
	ret+=textureOffset(tex_main,pos,ivec2(1,1))*0.05;

	ret+=textureOffset(tex_main,pos,ivec2(0,-1))*.2;
	ret+=textureOffset(tex_main,pos,ivec2(-1,0))*.2;
	ret+=textureOffset(tex_main,pos,ivec2(1,0))*.2;
	ret+=textureOffset(tex_main,pos,ivec2(0,1))*.2;

	ret+=textureOffset(tex_main,pos,ivec2(0,0))*(-1);
	return ret;
}
#define MAPPING
vec2 gray_scott(vec4 cnt,vec2 normed)
{
	/*
		X+2Y=3Y
	*/
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	if (map_region.x>=0)
	{
		kill_rate=mix(map_region.x,map_region.y,normed.x);
		feed_rate=mix(map_region.z,map_region.w,normed.y);
	}
#endif
	float abb=cnt.x*cnt.y*cnt.y;
	return vec2(-abb,abb)+vec2(feed_rate*(1-cnt.x),-(kill_rate+feed_rate)*cnt.y);
}
vec2 schnakenberk_reaction_kinetics(vec4 cnt,vec2 normed)
{
#if 0
	float k1=kill_feed.x;
	float k2=kill_feed.y;
	float k3=kill_feed.z;
	float k4=kill_feed.w;
#ifdef MAPPING
	if (map_region.x>=0)
	{
		k3=mix(map_region.x,map_region.y,normed.x);
		k4=mix(map_region.z,map_region.w,normed.y);
	}
#endif
	float aab=cnt.x*cnt.x*cnt.y;
	return vec2(k1,k4)-vec2(k2*cnt.x,0)+vec2(k3*aab,-k3*aab);
#endif
	float k1=kill_feed.x;
	float k2=kill_feed.y;
	float k3=kill_feed.z;
	float k4=kill_feed.w;
#ifdef MAPPING
	if (map_region.x>=0)
	{
		k1=mix(map_region.x,map_region.y,normed.x);
		k2=mix(map_region.z,map_region.w,normed.y);
	}
#endif

	return k3*vec2(k1-cnt.x-cnt.x*cnt.x*cnt.y,k2-cnt.x*cnt.x*cnt.y);
}
vec2 gierer_meinhard(vec4 cnt,vec2 normed)
{
	//not dimensional
	float k1=kill_feed.x;
	float k2=kill_feed.y;
	float k3=kill_feed.z;
#ifdef MAPPING
	if (map_region.x>=0)
	{
		k1=mix(map_region.x,map_region.y,normed.x);
		k2=mix(map_region.z,map_region.w,normed.y);
	}
#endif

	return k3*vec2(k1-k2*cnt.x+cnt.x*cnt.x/cnt.y,cnt.x*cnt.x-cnt.y);
}
vec3 ruijgrok(vec4 cnt,vec2 normed)
{
	/*
		X+Y=>2X
		Y+Z=>2Y
		Z+X=>2Z

		X+2Y=>3Y
		Y+2Z=>3Z
		Z+2X=>3X
	*/
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	kill_rate=mix(0.06,0.08,normed.x);
	feed_rate=mix(0.01,.0175,normed.y);
#endif
	float pos_x1=cnt.y*cnt.x;
	float pos_x2=cnt.z*cnt.x*cnt.x;

	float pos_y1=cnt.z*cnt.y;
	float pos_y2=cnt.x*cnt.y*cnt.y;

	float pos_z1=cnt.z*cnt.x;
	float pos_z2=cnt.z*cnt.y*cnt.y;

	float neg_x1=pos_y2;
	float neg_x2=pos_z1;

	float neg_y1=pos_x1;
	float neg_y2=pos_z2;

	float neg_z1=pos_x2;
	float neg_z2=pos_y1;
	return vec3(
		pos_x1+pos_x2-neg_x1-neg_x2+feed_rate*(1-cnt.x),
		pos_y1+pos_y2-neg_y1-neg_y2-(kill_rate+feed_rate)*cnt.y,
		pos_z1+pos_z2-neg_z1-neg_z2);
}
vec3 rossler(vec4 cnt,vec2 normed)
{
	float k1=kill_feed.x;
	float k2=kill_feed.y;
	float k3=kill_feed.z;
#ifdef MAPPING
	if (map_region.x>=0)
	{
		k1=mix(map_region.x,map_region.y,normed.x);
		k2=mix(map_region.z,map_region.w,normed.y);
	}
#endif

	return vec3(
		-(cnt.y+cnt.z),
		cnt.x+k1*cnt.y,
		cnt.x*cnt.z-k2*cnt.z+k3
	);
}
vec3 two_reacts(vec4 cnt,vec2 normed)
{
	/*
		X+2Y=3Y
		Z+X=2Z

	*/
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	vec2 c=vec2(0.5,0.5);
	vec2 cs=vec2(0.5,0.5);
	kill_rate=mix(c.x-cs.x,c.x+cs.x,normed.x);
	feed_rate=mix(c.y-cs.y,c.y+cs.y,normed.y);
#endif
	float pos_y1=cnt.x*cnt.y*cnt.y;
	float pos_z1=cnt.z*cnt.x;

	float neg_x1=pos_y1;
	float neg_x2=pos_z1;

	return vec3(
		-neg_x2-neg_x1+feed_rate*(1-cnt.x),
		pos_y1,
		pos_z1-(kill_rate+feed_rate)*cnt.z);
}
vec4 thingy_formulas(vec4 c,vec2 normed)
{
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	if (map_region.x>=0)
	{
		kill_rate=mix(map_region.x,map_region.y,normed.x);
		feed_rate=mix(map_region.z,map_region.w,normed.y);
	}
#endif
	return vec4(%s)+
		vec4(%s);
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;

	vec4 L=laplace(normed);
	vec4 cnt=texture(tex_main,normed);
	vec4 ret=cnt+(diffusion*L
		//+vec4(gray_scott(cnt,normed),0,0)
		//+vec4(ruijgrok(cnt,normed),0)
		//+vec4(two_reacts(cnt,normed),0)
		//+thingy_formulas(cnt,normed)
		//+vec4(schnakenberk_reaction_kinetics(cnt,normed),0,0)
		//+vec4(gierer_meinhard(cnt,normed),0,0)
		+vec4(rossler(cnt,normed),0)
		)*dt;

	//ret=clamp(ret,0,1);

	color=ret;
}
]==],thingy_string,feed_kill_string))
end
update_diffuse()
local draw_shader = shader_make[==[
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;

uniform float v_gamma;
uniform float v_gain;
uniform int draw_comp;
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}

void main(){

	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 cnt=texture(tex_main,normed);

	float lv=cnt.x;
	if(draw_comp==1)
		lv=cnt.y;
	else if(draw_comp==2)
		lv=cnt.z;
	else if(draw_comp==3)
		lv=cnt.w;

	lv=gain(lv,v_gain);
	lv=pow(lv,v_gamma);

	color=vec4(lv,lv,lv,1);
	//color=vec4(palette(lv,vec3(0.5,0.5,0.5),vec3(0.25,0.25,0.25),vec3(2,0.5,0.5),vec3(1.5,0.25,0.25)),1);
	/* accent
	float accent_const=0.5;
	if(lv<accent_const)
		color=vec4(vec3(1)*(lv/accent_const),1);
	else
		color=mix(vec4(1),vec4(0.05,0.1,0.3,1),(lv-accent_const)/(1-accent_const));
	//*/
	/*
	if(lv>0)
		color.xyz=vec3(lv,0,0);
	else
		color.xyz=vec3(0,0,lv);
	color.w=1;
	*/
}
]==]


local terminal_symbols={["c.x"]=10,["c.y"]=10,["c.z"]=10,["c.w"]=10,["1.0"]=0.1,["0.0"]=0.1}
local normal_symbols={["max(R,R)"]=0.05,["min(R,R)"]=0.05,["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,["abs(R)"]=0.1,["sqrt(R)"]=0.1,["exp(R)"]=0.01,["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,["log(R+1.0)"]=1,["(R)/(R+1)"]=5,["(R)*(R)"]=5,["(R)-(R)"]=5,["(R)+(R)"]=5}


function normalize( tbl )
	local sum=0
	for i,v in pairs(tbl) do
		sum=sum+v
	end
	for i,v in pairs(tbl) do
		tbl[i]=tbl[i]/sum
	end
end

normalize(terminal_symbols)
normalize(normal_symbols)

function rand_weighted(tbl)
	local r=math.random()
	local sum=0
	for i,v in pairs(tbl) do
		sum=sum+v
		if sum>= r then
			return i
		end
	end
end
function replace_random( s,substr,rep )
	local num_match=0
	local function count(  )
		num_match=num_match+1
		return false
	end
	string.gsub(s,substr,count)
	num_rep=math.random(0,num_match-1)
	function rep_one(  )
		if num_rep==0 then
			num_rep=num_rep-1
			return rep()
		else
			num_rep=num_rep-1
			return false
		end
	end
	local ret=string.gsub(s,substr,rep_one)
	return ret
end
function random_math( steps,seed )
	local cur_string=seed or "R,R,R,R"

	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end

	for i=1,steps do
		cur_string=replace_random(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
function random_math_balanced( steps,seed )
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end
	local ret=""
	for i=1,4 do
		local cur_string=seed or "R"

		for i=1,steps do
			cur_string=replace_random(cur_string,"R",M)
		end
		cur_string=string.gsub(cur_string,"R",MT)
		if i==1 then
			ret=cur_string
		else
			ret=ret..","..cur_string
		end
	end
	return ret
end
function random_math_poly(  )
	local rf=function (  )
		return math.random()*2-1
	end
	local ret=string.format("dot(c,vec4(%g,%g,%g,%g)),dot(c,vec4(%g,%g,%g,%g)),dot(c,vec4(%g,%g,%g,%g)),dot(c,vec4(%g,%g,%g,%g))",
			rf(),rf(),rf(),rf(),
			rf(),rf(),rf(),rf(),
			rf(),rf(),rf(),rf(),
			rf(),rf(),rf(),rf())
	return ret
end
function random_math_transfers( steps,seed,count_transfers )
	count_transfers=count_transfers or 3
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end
	local ret={"0","0","0","0"}
	for i=1,count_transfers do
		local cur_string=seed or "R"

		for i=1,steps do
			cur_string=replace_random(cur_string,"R",M)
		end
		cur_string=string.gsub(cur_string,"R",MT)
		local remove=math.random(1,4)
		local add=math.random(1,4)
		while add==remove do
			add=math.random(1,4)
		end
		ret[remove]=ret[remove].."-"..cur_string
		ret[add]=ret[add].."+"..cur_string

	end
	local rstr=table.concat(ret,",")
	return rstr
end
function sim_tick(  )
	local dt=0.0025
	react_diffuse:use()
	react_diffuse:blend_default()
	react_diffuse:set("diffusion",config.diff_a,config.diff_b,config.diff_c,config.diff_d)
	react_diffuse:set("kill_feed",config.kill,config.feed,config.k3,config.k4)
	react_diffuse:set("dt",dt)
	react_diffuse:set("map_region",map_region[1],map_region[2],map_region[3],map_region[4])
	local cur_buff=react_buffer:get()
	local do_clamp
	if config.clamp_edges then
		do_clamp=1
	else
		do_clamp=0
	end
	cur_buff:use(0,1,do_clamp)
	react_diffuse:set_i("tex_main",0)

	local next_buff=react_buffer:get_next()
	next_buff:use(1,1,do_clamp)
	if not next_buff:render_to(react_buffer.w,react_buffer.h) then
		error("failed to set framebuffer up")
	end

	react_diffuse:draw_quad()

	__render_to_window()
	react_buffer:advance()
end
init_size=1
function reset_buffers(rnd  )
	local b=io_buffer
	for x=0,b.w-1 do
		for y=0,b.h-1 do
			local dx=x-b.w/2
			local dy=y-b.h/2
			local dist=math.sqrt(dx*dx+dy*dy)
			if rnd then
				if dist<b.w/2 then
					b:set(x,y,{math.random(),math.random(),math.random(),math.random()})
				else
					b:set(x,y,{0,0,0,0})
				end
			else
				b:set(x,y,{1,0,0,0})
			end
		end
	end
	-- [[
	if not rnd then
		local cx=math.floor(b.w/2)
		local cy=math.floor(b.h/2)
		local s=math.random(1,200)
		local v = {math.random(),math.random(),math.random(),math.random()}
		for x=cx-s,cx+s do
			for y=cy-s,cy+s do
				local dx=x-cx
				local dy=y-cy
				--if math.sqrt(dx*dx+dy*dy)<s then
					b:set(x,y,v)
				--end
			end
		end
	end
	--]]
	local buf=react_buffer:get()
	buf:use(0)
	b:write_texture(buf)
	react_buffer:advance()

	buf=react_buffer:get()
	buf:use(0)
	b:write_texture(buf)
end
function is_inf( v )
	if v==math.huge or v==-math.huge then
		return true
	end
	return false
end
function clip_maxmin( tbl1,tbl2,id )
	if is_inf(tbl1[id]) or is_inf(tbl2[id]) then
		print("clip",id)
		tbl1[id]=0
		tbl2[id]=1
	elseif math.abs(tbl1[id]-tbl2[id])<0.0001 then
		tbl1[id]=0
		tbl2[id]=1
	end
end
function eval_thingy_string()
	local MAX_DIFF_VALUE=0.25
	local env={
		max=math.max,
		min=math.min,
		mod=math.modf,
		fract=function ( x )
			return select(2,math.modf(x))
		end,
		floor=math.floor,
		abs=math.abs,
		sqrt=math.sqrt,
		exp=math.exp,
		atan=math.atan,
		acos=math.acos,
		asin=math.asin,
		tan=math.tan,
		sin=math.sin,
		cos=math.cos,
		log=math.log,
		math=math,
		dot=function ( a,b )
			return a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w
		end,
		vec4=function ( x,y,z,w )
			return {x=x,y=y,z=z,w=w}
		end
	}
	local f=load(string.format(
		[==[
		local inf=math.huge
		local val_min={inf,inf,inf,inf}
		local val_max={-inf,-inf,-inf,-inf}
		local step_size=0.05
		local itg={0,0,0,0}
			for x=0,1,step_size do
				for y=0,1,step_size do
					for z=0,1,step_size do
						for w=0,1,step_size do
							local c={x=x,y=y,z=z,w=w}
							local tx,ty,tz,tw=%s
							if tx>val_max[1] then val_max[1]=tx end
							if ty>val_max[2] then val_max[2]=ty end
							if tz>val_max[3] then val_max[3]=tz end
							if tw>val_max[4] then val_max[4]=tw end

							if tx<val_min[1] then val_min[1]=tx end
							if ty<val_min[2] then val_min[2]=ty end
							if tz<val_min[3] then val_min[3]=tz end
							if tw<val_min[4] then val_min[4]=tw end
							itg[1]=itg[1]+tx*step_size*step_size*step_size
							itg[2]=itg[2]+ty*step_size*step_size*step_size
							itg[3]=itg[3]+tz*step_size*step_size*step_size
							itg[4]=itg[4]+tw*step_size*step_size*step_size
						end
					end
				end
			end
			return val_min,val_max,itg
		]==],thingy_string),"thingy","t",env)
	local ret,vmin,vmax,itg=pcall(f)
	if ret then

		print("Min:",vmin[1],vmin[2],vmin[3],vmin[4])
		print("Max:",vmax[1],vmax[2],vmax[3],vmax[4])
		print("Integral:",itg[1],itg[2],itg[3],itg[4])
		local swing={}
		for i=1,4 do
			clip_maxmin(vmin,vmax,i)
			if itg[i]==0 then itg[i]=1 end
			if math.abs(itg[i])==math.huge then itg[i]=1 end
			if itg[i]~=itg[i] then itg[i]=1 end

			swing[i]=vmax[i]-vmin[i]
			--swing[i]=math.abs(vmax[i]-vmin[i])
		end
		thingy_string=string.format("(vec4(%s)+vec4(%g,%g,%g,%g))*vec4(%g,%g,%g,%g)"
			,thingy_string,
			-vmin[1],-vmin[2],-vmin[3],-vmin[4],
			--itg[1],-itg[2],-itg[3],-itg[4],
			MAX_DIFF_VALUE/swing[1],MAX_DIFF_VALUE/swing[2],-MAX_DIFF_VALUE/swing[3],-MAX_DIFF_VALUE/swing[4]
			--MAX_DIFF_VALUE/itg[1],MAX_DIFF_VALUE/itg[2],-MAX_DIFF_VALUE/itg[3],-MAX_DIFF_VALUE/itg[4]
			--1,1,1,1
			)
		print(thingy_string)
	else
		print("ERR:",vmin)
	end
end

anim_state={
	current_frame=0,
	frame_skip=10,
	max_frame=12000,
	}
function gui(  )
	imgui.Begin("GrayScott")
	draw_config(config)
	if imgui.Button("Reset") then
		reset_buffers()
	end
	imgui.SameLine()
	if imgui.Button("ResetRand") then
		reset_buffers(true)
	end
	imgui.SameLine()
	if imgui.Button("RandMath") then
		thingy_string=random_math_poly(30)
		print(thingy_string)
		eval_thingy_string()
		update_diffuse()
		reset_buffers(true)
	end
	imgui.SameLine()
	if imgui.Button("NotMapping") then
		map_region={-1,0,0,0}
	end
	imgui.SameLine()
	if imgui.Button("FullMap") then
		map_region={0,1,0,1}
	end
	if imgui.Button("Save image") then
		need_save=true
	end
	if imgui.Button("Start animate") then
		anim_state.current_frame=0
		config.animate=true
	end
	imgui.End()
end
function save_img( id )
	--make_image_buffer()
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	config_serial=config_serial.."\n"..string.format("thingy_string=%q",thingy_string)
	config_serial=config_serial.."\n"..string.format("feed_kill_string=%q",feed_kill_string)
	img_buf:read_frame()
	if id then
		img_buf:save(string.format("video/saved (%d).png",id),config_serial)
	else
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	end
end
function draw_texture( id )
	draw_shader:use()
	local buf=react_buffer:get()
	buf:use(0,0,0)
	draw_shader:set_i('tex_main',0)
	draw_shader:set("v_gamma",config.gamma)
	draw_shader:set("v_gain",config.gain)
	draw_shader:set_i("draw_comp",config.draw_comp)
	draw_shader:draw_quad()
	if need_save or id then
		save_img(id)
		if need_save=="r" then
			reset_buffers()
		end
		need_save=nil
	end
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function update( )
	__no_redraw()
	__clear()
	__render_to_window()
	gui()
	if config.pause then
		draw_texture()
	else
		sim_tick()
		local save_id
		if config.animate then
			anim_state.current_frame=anim_state.current_frame+1
			if anim_state.current_frame>anim_state.max_frame then
				config.animate=false
			end
			if anim_state.current_frame % anim_state.frame_skip ==0 then
				save_id=anim_state.current_frame/anim_state.frame_skip
			end
		end
		draw_texture(save_id)
	end
	local c,x,y= is_mouse_down()
	if c then

		local scale_x
		local scale_y
		local offset_x=map_region[1]
		local offset_y=map_region[3]
		if map_region[1]>=0 then
			scale_x=map_region[2]-map_region[1]
			scale_y=map_region[4]-map_region[3]
		else
			scale_x=1
			scale_y=1
			offset_x=0
			offset_y=0
		end
		local xx=(x/size[1])*scale_x+offset_x
		local yy=(1-y/size[2])*scale_y+offset_y

		print(xx,",",yy)
		config.k1=xx
		config.k2=yy

		-- [[
		local low_x=math.max(0,xx-config.region_size)
		local low_y=math.max(0,yy-config.region_size)
		local high_x=math.min(1,xx+config.region_size)
		local high_y=math.min(1,yy+config.region_size)
		--]]
		--[[
		local low_x=xx-config.region_size
		local low_y=yy-config.region_size
		local high_x=xx+config.region_size
		local high_y=yy+config.region_size
		--]]
		map_region={low_x,high_x,low_y,high_y}
		reset_buffers(true)
		config.region_size=config.region_size/2
	end
end
