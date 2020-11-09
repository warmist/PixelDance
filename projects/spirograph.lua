require "common"
local max_size=math.min(STATE.size[1],STATE.size[2])/2
img_buf=img_buf or buffers.Make("color")
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
function catmull_gett( t,alpha,p0,p1 )
	local a=dist_sq(p0,p1)
	local b=math.pow(a,alpha*0.5)
	return b + t
end
function mult_add_points( a0,p0,a1,p1 )
	local ret={}
	for i,_ in ipairs(p0) do
		ret[i]=p0[i]*a0+p1[i]*a1
	end
	return ret
end
function apply_catmull( p0,p1,p2,p3,t,alpha )
	local t0=0
	local t1=catmull_gett(t0,alpha,p0,p1)
	local t2=catmull_gett(t1,alpha,p1,p2)
	local t3=catmull_gett(t2,alpha,p2,p3)

	t=t1*(1-t)+t2*t

	local A1=mult_add_points((t1-t)/(t1-t0),p0,(t-t0)/(t1-t0),p1)
	local A2=mult_add_points((t2-t)/(t2-t1),p1,(t-t1)/(t2-t1),p2)
	local A3=mult_add_points((t3-t)/(t3-t2),p2,(t-t2)/(t3-t2),p3)

	local B1=mult_add_points((t2-t)/(t2-t0),A1,(t-t0)/(t2-t0),A2)
	local B2=mult_add_points((t3-t)/(t3-t1),A2,(t-t1)/(t3-t1),A3)

	local C=mult_add_points((t2-t)/(t2-t1),B1,(t-t1)/(t2-t1),B2)

	return C
end
function path_pos_camull_rom( t )
	if #path<3 then return {0,0} end
	local path_step_count=#path
	local p_id=t*(path_step_count)
	local p_low=math.floor(p_id)
	local v=p_id-p_low
	return apply_catmull(
		path[(p_low)%path_step_count+1],
		path[(p_low+1)%path_step_count+1],
		path[(p_low+2)%path_step_count+1],
		path[(p_low+3)%path_step_count+1],v,0.5)
end
steps_in_loop=0
step=0
function draw_path(  )
	local dist_min=0.0001
	local eps=0.00001
	local c_u8={config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	local c2={100,100,100,255}
	for i=1,config.ticking2 do
		--step=step+1/config.ticking
		steps_in_loop=steps_in_loop+1
		if step>1 then
			step=step-1

			print(steps_in_loop)
			steps_in_loop=0
			--gen_path()
		end
		local p
		local x
		local y
		local dx = config.dim
		local dy = config.dim+1
		if dy> dimensionality then
			dy=1
		end

		p=path_pos_camull_rom(step,0.5)
		local cur_step=0
		local imax=10
		for i=1,imax do
			if cur_step>dist_min then
				--print(dist(start_pos,p))
				for j=1,3 do
					config.color[j]=i/imax
				end
				c_u8={config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
				break
			end
			step=step+eps

			if step>1 then
				step=step-1
				
				print(steps_in_loop)
				steps_in_loop=0
			end
			local old_pos=p
			p=path_pos_camull_rom(step,0.5)
			cur_step=cur_step+dist(old_pos,p)
		end

		do
			x=math.floor(p[dx]*STATE.size[1])
			y=math.floor(p[dy]*STATE.size[2])
			if x>0 and y>0 and x<STATE.size[1] and y<STATE.size[2] then
				img_buf:set(x,y,c_u8)
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