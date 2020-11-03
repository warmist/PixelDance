require "common"
local max_size=math.min(STATE.size[1],STATE.size[2])/2
img_buf=img_buf or buffers.Make("color")
tick=tick or 0
config=make_config({
	{"color",{0.5,0,0,1},type="color"},
	{"k",0.2,type="float"},
	{"l",0.4,type="float"},
	{"R",400,type="int",min=0,max=max_size},
	{"ticking",100,type="float",min=1,max=10000},
	{"ticking2",100,type="float",min=1,max=10000},
	{"dist",100,type="float",min=1,max=1000},
	{"dim",1,type="int",min=1,max=40},
},config)
image_no=image_no or 0
path =path or {}
function midpoint( p1,p2 )
	local ret={}
	for i,v in ipairs(p1) do
		ret[i]=(p1[i]+p2[i])/2
	end
	return ret
end
function lerp( p1,p2,v )
	local ret={}
	for i,_ in ipairs(p1) do
		ret[i]=p1[i]*(1-v)+p2[i]*v
	end
	return ret
end
function dist( p1,p2 )
	local s=0
	for i,v in ipairs(p1) do
		local d=p1[i]-p2[i]
		s=s+d*d
	end
	return math.sqrt(s)
end
function path_len(  )
	local l=0
	for i,v in ipairs(path) do
		local inext=i+1
		if inext>#path then
			inext=1
		end
		l=l+dist(path[i],path[inext])
	end
	return l
end
function pick_l_weighted( t )
	local l=0
	for i,v in ipairs(path) do
		local inext=i+1
		if inext>#path then
			inext=1
		end
		l=l+dist(path[i],path[inext])
	end
	t=t*l
	local nl=0
	for i,v in ipairs(path) do
		local inext=i+1
		if inext>#path then
			inext=1
		end
		nl=nl+dist(path[i],path[inext])
		if t<nl then
			return i
		end
	end
	return #path
end
local dimensionality=40
function gen_path(  )
	local num_dim=dimensionality
	--local path_len=10
	path={}
	for i=1,4 do
		local p={}
		for j=1,num_dim do
			p[j]=math.random()
		end
		path[i]=p
	end
	for i=1,50 do
		local t=pick_l_weighted(math.random())
		local p1=path[t]
		local tn=t+1
		if tn>#path then
			tn=1
		end
		local p2=path[tn]
		local np=midpoint(p1,p2)
		for j=1,num_dim do
			np[j]=np[j]+(math.random()-0.5)*0.05
		end
		table.insert(path,tn,np)
	end
	print(path_len())
end


function path_pos_org( t )
	if #path<2 then return {0,0} end
	local p_id=t*#path+1
	local p_low=math.floor(p_id)
	local p_high=p_low+1
	if p_high>#path then p_high=1 end
	return lerp(path[p_low],path[p_high],p_id-p_low)
end
function path_pos( t )
	if #path<2 then return {0,0} end
	local p_id=t*#path+1
	local p_mid=math.floor(p_id)
	local p_low=p_mid-1

	if p_low<1 then p_low=#path end
	local p_high=p_mid+1
	if p_high>#path then p_high=1 end
	--if math.random()>0.99999 then
	--	print(t,p_id,p_low,p_mid,p_high)
	--end
	local p1=path[p_mid]
	local p0=midpoint(path[p_low],p1)
	local p2=midpoint(p1,path[p_high])
	local v=p_id-p_mid
	local pp=lerp(p0,p2,v)
	return lerp(pp,p1,0.5-(4*v*v-4*v+1)*0.5)
end
step=0
function draw_path(  )
	local c_u8={config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	local c2={100,100,100,255}
	for i=1,config.ticking2 do
		step=step+1/config.ticking

		if step>1 then step=step-1 end
		local p
		local x
		local y
		local dx = config.dim
		local dy = config.dim+1
		if dy> dimensionality then
			dy=1
		end
		do

			p=path_pos(step)
			x=math.floor(p[dx]*STATE.size[1])
			y=math.floor(p[dy]*STATE.size[2])
			img_buf:set(x,y,c_u8)
		end
		--[[
		do
			p=path_pos_org(step)
			x=math.floor(p[dx]*STATE.size[1])
			y=math.floor(p[dy]*STATE.size[2])
			img_buf:set(x,y,c2)
		end
		--]]
	end
end
function update(  )
	imgui.Begin("Hello")
	local s=STATE.size
	draw_config(config)

	if imgui.Button("Clear image") then
		print("Clearing:"..s[1].."x"..s[2])
		for x=0,s[1]-1 do
			for y=0,s[2]-1 do
				img_buf:set(x,y,{0,0,0,0})
			end
		end
	end
	if imgui.Button("Gen") then
		gen_path()
	end
	local eps=0.000001
	imgui.End()
	draw_path()
	img_buf:present()
end