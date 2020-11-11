require "common"
require "splines"
local luv=require "colors_luv"
local max_size=math.min(STATE.size[1],STATE.size[2])/2
img_buf=img_buf or buffers.Make("color")
depth_buf=depth_buf or make_float_buffer(STATE.size[1],STATE.size[2])
tick=tick or 0
config=make_config({
	{"color",{0.5,0,0,1},type="color"},
	{"k",0.2,type="float",max=0.999},
	{"l",0.4,type="float"},
	{"R",400,type="int",min=0,max=max_size},
	{"ticking",100,type="float",min=1,max=10000},
	{"ticking2",100,type="float",min=1,max=10000},
	{"dist",100,type="float",min=1,max=1000},
	{"dim",1,type="int",min=1,max=3},
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
function dist_sq( p1,p2 )
	local s=0
	for i,v in ipairs(p1) do
		local d=p1[i]-p2[i]
		s=s+d*d
	end
	return s
end
function dist( p1,p2 )
	return math.sqrt(dist_sq(p1,p2))
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
local dimensionality=4
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
function gen_path(  )
	local num_dim=dimensionality
	local offset=0.07
	path={}
	for i=1,6 do
		local p={}
		for j=1,num_dim do
			p[j]=math.random()*(1-offset*2)+offset
		end
		path[i]=p
	end
end
function gen_path_bez(  )
	local num_dim=dimensionality
	--[[
		TODO:
			* limit so that for all t it's inside 0,1!
			* |v| is const
				- on avg?
				- heuristic?
	]]--
	path={}
	local path_steps=10 --(only even supported!)
	--for odds this MUST hold: p0-p6+p4-p2=0
	path.steps=path_steps

	s_sp={}
	for i=1,num_dim do
		s_sp[i]=0
	end
	local dist_max=0.25
	--free parts
	for i=0,path_steps*2,2 do
		path[i+1]={}
		local mult=1
		if (i/2)%2==0 and i~=0 then
			mult=-1
		end
		
		for j=1,num_dim do
			path[i+1][j]=math.random()*dist_max-dist_max/2+0.5
			--calculate the second point
			s_sp[j]=s_sp[j]+path[i+1][j]*mult
		end
	end
	path[2]=s_sp
	--connecting parts
	for i=3,path_steps*2+1,2 do
		path[i+1]={}
		for j=1,num_dim do
			path[i+1][j]=2*path[i][j]-path[i-1][j]
		end
	end
end
function apply_bez( p0,p1,p2,v )
	local ret={}
	local vs=v*v
	local vinvs=(1-v)*(1-v)
	for i=1,#p0 do
		ret[i]=p1[i]+vinvs*(p0[i]-p1[i])+vs*(p2[i]-p1[i])
	end
	return ret
end
function path_pos_bez( t )
	if #path<3 then return {0,0} end
	local path_step_count=path.steps
	local p_id=t*(path_step_count+1)
	local p_low=math.floor(p_id)
	local v=p_id-p_low
	local id_last=p_low*2+3
	if #path<id_last then
		id_last=1
	end
	return apply_bez(path[p_low*2+1],path[p_low*2+2],path[id_last],v)
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


function draw_path_bez(  )
	local dist_min=0.0001
	local eps=0.000001
	local c_u8={config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	local c2={100,100,100,255}
	for i=1,config.ticking2 do
		--step=step+1/config.ticking

		if step>1 then
			step=step-1
			-- [[
			for i=1,3 do
				config.color[i]=math.random()
			end
			--]]
			--gen_path_bez()
		end
		local p
		local x
		local y
		local dx = config.dim
		local dy = config.dim+1
		if dy> dimensionality then
			dy=1
		end
		local start_pos=path_pos_bez(step)
		for i=1,100 do
			p=path_pos_bez(step)
			if dist(start_pos,p)>dist_min then
				break
			end
			step=step+eps
			if step>1 then
				step=step-1
			end
		end
		do

			x=math.floor(p[dx]*STATE.size[1])
			y=math.floor(p[dy]*STATE.size[2])
			if x>0 and y>0 and x<STATE.size[1] and y<STATE.size[2] then
				local v=config.color[4]
				local s=img_buf:get(x,y)
				s[1]=s[1]*(1-v)+c_u8[1]*v
				s[2]=s[2]*(1-v)+c_u8[2]*v
				s[3]=s[3]*(1-v)+c_u8[3]*v
				s[4]=255
				img_buf:set(x,y,s)
			end
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
color=color or {1,1,1}
local first_path_size=7
local second_path_size=3
cat_path=cat_path or Catmull(gen_points(first_path_size,3))
path_step=path_step or 0
cat_path_next=cat_path_next or Catmull(gen_points(second_path_step,first_path_size*3+3,0))
second_path_step=second_path_step or 0
function update_path( p )
	for i=1,#p-3 do
		local trg=cat_path.path[math.floor((i-1)/3)+1]
		--print(math.floor((i-1)/2)+1,(i-1)%2+1,trg,#trg)
		trg[i%3+1]=p[i]
	end
	for i=#p-3,#p do
		color[i-#p+3]=p[i]
	end
end
function step_second_path( )
	local p
	p,second_path_step=step_along_spline(cat_path_next,second_path_step, 0.000125, 0.00001)
	update_path(p)
end
function draw_path(  )
	local p
	local step=config.ticking
	for i=1,config.ticking2 do
		local x
		local y
		local old_step=path_step
		p,path_step=step_along_spline(cat_path,path_step, 1/step, 1/(step*10))
		if old_step>path_step then
			step_second_path()
		end
		x=math.floor(p[1]*STATE.size[1])
		y=math.floor(p[2]*STATE.size[2])
		if x>0 and y>0 and x<STATE.size[1] and y<STATE.size[2] then
			if p[3]>depth_buf:get(x,y) then
				local v=config.color[4]
				local s=img_buf:get(x,y)
				local a=1
				local r2=luv.hsluv_to_rgb{color[1]*360,color[2]*100,color[3]*100}
				s[1]=r2[1]*255
				s[2]=r2[2]*255
				s[3]=r2[3]*255
				s[4]=255
				img_buf:set(x,y,s)
				depth_buf:set(x,y,p[3])
			end
		end
	end
end
function func( t,args )
	local rt=t*math.pi*2*4
	-- [[
	return math.cos(args[9]*rt+args[1])*args[2]+math.cos(args[10]*rt+args[3])*args[4],
			math.sin(args[9]*rt+args[5])*args[6]+math.sin(args[10]*rt+args[7])*args[8]
	--]]
end
global_args={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
global_step=0
function draw_spirals()

	local step=config.ticking
	for i=1,config.ticking2 do
		local x
		local y

		x,y=func(global_step,global_args)
		global_step=global_step+1/step
		if global_step>1 then
			global_step=global_step-1
			global_args,path_step=step_along_spline(cat_path,path_step,1/step,1/(step*10))
			color[1]=global_args[9]
			color[2]=global_args[10]
			color[3]=global_args[11]
		end
		x=math.floor((x)*STATE.size[1]*0.25+STATE.size[1]/2)
		y=math.floor((y)*STATE.size[2]*0.25+STATE.size[2]/2)
		if x>0 and y>0 and x<STATE.size[1] and y<STATE.size[2] then
			local s=img_buf:get(x,y)
			local r2=luv.hsluv_to_rgb{color[1]*360,color[2]*100,color[3]*100}
			s[1]=r2[1]*255
			s[2]=r2[2]*255
			s[3]=r2[3]*255
			s[4]=255
			img_buf:set(x,y,s)
				--depth_buf:set(x,y,p[3])
		end
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
				local dx=(x-s[1]/2)/s[1]
				local dy=(y-s[2]/2)/s[2]
				img_buf:set(x,y,{0,0,0,0})
				local d=-10000--math.sqrt(dx*dx+dy*dy)/10
				depth_buf:set(x,y,d)
			end
		end
	end
	if imgui.Button("Gen") then
		cat_path_next=Catmull(gen_points(second_path_size,first_path_size*3+3))
		--cat_path=Catmull(gen_points(first_path_size,11))
	end
	if imgui.Button("Save") then
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))))
	end
	local eps=0.000001
	imgui.End()
	--draw_spirals()
	draw_path()
	img_buf:present()
end