require "common"
local max_size=math.min(STATE.size[1],STATE.size[2])/2
img_buf=img_buf or buffers.Make("color")

config=make_config({
	{"color",{0,1,0},type="color"},
	{"scale",0,type="float",min=0,max=10},
	{"px",0,type="float",min=-1,max=1},
	{"py",0,type="float",min=-1,max=1},
	{"pz",0,type="float",min=-1,max=1},
	{"pw",0,type="float",min=-1,max=1},
},config)
image_no=image_no or 0



local terminal_symbols={
["x"]=2,["y"]=2,
["px"]=1,["py"]=1,["pz"]=1,["pw"]=1,
["1.0"]=0.1,["0.0"]=0.1,
}

local normal_symbols={
["max(R,R)"]=0.05,["min(R,R)"]=0.05,
["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,
["abs(R)"]=0.1,["sqrt(R)"]=0.1,["exp(R)"]=0.01,
["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,
["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,["log(R)"]=1,
["(R)/(R)"]=1,["(R)*(R)"]=2,
["(R)-(R)"]=3,["(R)+(R)"]=3
}

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
			if type(rep)=="function" then
				return rep()
			else
				return rep
			end
		else
			num_rep=num_rep-1
			return false
		end
	end
	local ret=string.gsub(s,substr,rep_one)
	return ret
end
function make_rand_math( normal_s,terminal_s,forced_s )
	forced_s=forced_s or {}
	return function ( steps,seed )
		local cur_string=seed or "R"

		function M(  )
			return rand_weighted(normal_s)
		end
		function MT(  )
			return rand_weighted(terminal_s)
		end

		for i=1,steps do
			cur_string=replace_random(cur_string,"R",M)
		end
		for i,v in ipairs(forced_s) do
			cur_string=replace_random(cur_string,"R",v)
		end
		cur_string=string.gsub(cur_string,"R",MT)
		return cur_string
	end
end
random_math=make_rand_math(normal_symbols,terminal_symbols)

str_function=str_function or "x*x+y*y"

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
local func
function update_func(  )
	func=load(string.format(
	[==[
		local x,y,px,py,pz,pw=...
		return %s
	]==],str_function),"thingy","t",env)
end
update_func()

local dirty=true
function update(  )
	imgui.Begin("Hello")
	local s=STATE.size
	draw_config(config)
	local c_u8={config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	if imgui.Button("Clear image") then
		print("Clearing:"..s[1].."x"..s[2])
		for x=0,s[1]-1 do
			for y=0,s[2]-1 do
				img_buf:set(x,y,{0,0,0,0})
			end
		end
		dirty=true
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),"Saved by PixelDance")
		image_no=image_no+1
	end
	if imgui.Button("Rand math") then
		str_function=random_math(30)
		print(str_function)
		update_func()
		dirty=true
	end
	imgui.End()
	if dirty then
		local eps=0.000001
		local min_v=math.huge
		local max_v=-math.huge
		local arr={}
		for x=0,s[1]-1 do
			for y=0,s[2]-1 do
				local v=func((x-s[1]/2)*config.scale,(y-s[2]/2)*config.scale,config.px,config.py,config.pz,config.pw)
				arr[x+y*s[1]]=v
				if v>max_v and v~=math.huge then max_v=v end
				if v<min_v and v~=-math.huge then min_v=v end
			end
		end
		print(max_v,min_v)
		for x=0,s[1]-1 do
			for y=0,s[2]-1 do
				local v=arr[x+y*s[1]]
				v=(v-min_v)/(max_v-min_v)
				c_u8[1]=config.color[1]*255*v
				c_u8[2]=config.color[2]*255*v
				c_u8[3]=config.color[3]*255*v
				c_u8[4]=config.color[4]*255
				img_buf:set(x,y,c_u8)
			end
		end
		dirty=false
	end
	img_buf:present()
end