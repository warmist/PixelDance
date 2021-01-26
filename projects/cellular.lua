--[===[
some ideas:
	* voronoi centers with 1d CA outwards
	* CA with "rule switches"
		- on borders?
		- on smooth noise
		- on some value (e.g. region alive count >0.5)
	* more complicated N state CA
	* random vectorfield and then a wave from one direction with dx/dy from vectorfield
--]===]
require "common"
require "perlin"
local size=STATE.size
--size[1]=size[1]*0.125
--size[2]=size[2]*0.125
visits=visits or make_flt_buffer(size[1],size[2])
visits2=visits2 or make_flt_buffer(size[1],size[2])
vectorfield=vectorfield or make_flt_half_buffer(size[1],size[2])
function resize( w,h )
	visits=make_flt_buffer(size[1],size[2])
	visits2=make_flt_buffer(size[1],size[2])
	vectorfield=make_flt_half_buffer(size[1],size[2])
end

pos=pos or {size[1]/2,size[2]/2}

local draw_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;


uniform sampler2D tex_main;

uniform float current_y;

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	normed.y=1-normed.y;
	vec3 col=texture(tex_main,normed).xyz;
	//float min_v=0.9;
	//float d=clamp(1-max(-normed.y+current_y,0),min_v,1);
	//if(current_y<normed.y)
	//	d=min_v;
	//d=pow(d,10);
	float d=1;
	color = vec4(col*d,1);
}
]==]
local need_save
local visit_tex = textures.Make()
last_pos=last_pos or {0,0}
function save_img(tile_count)
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
--[[	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end]]
	img_buf=make_image_buffer(size[1],size[2])
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
local current_y=1
local min_r=5
local current_r=min_r
function draw_visits(  )

	draw_shader:use()
	visit_tex:use(0)
	visits2:write_texture(visit_tex)
	draw_shader:set_i("tex_main",0)
	draw_shader:set("current_y",current_r/size[2])
	draw_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
end

function relax_flowfield( step_count,step_size )
	local tmp=make_flt_half_buffer(size[1],size[2])
	local tmp2=vectorfield
	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		tmp:set(x,y,tmp2:sget(x,y))
	end
	end
	for step=1,step_count do
		local max_del=-math.huge
		for x=0,size[1]-1 do
		for y=0,size[2]-1 do
			local nx=x+1
			if nx==size[1] then nx=0 end
			local px=x-1
			if px<0 then px=size[1]-1 end

			local ny=y+1
			if ny==size[2] then ny=0 end
			local py=y-1
			if py<0 then py=size[2]-1 end

			local t00=tmp:sget(x,y)
			local t10=tmp:sget(nx,y)
			local t01=tmp:sget(x,ny)

			local t20=tmp:sget(px,y)
			local t02=tmp:sget(x,py)
			local t21=tmp:sget(px,ny)
			local t12=tmp:sget(nx,py)
			local del00=step_size*(
				t00.r-t10.r+
				t00.g-t01.g);

			if max_del<math.abs(del00) then
				max_del=math.abs(del00)
			end

			local del10=step_size*(
				t20.r-t00.r+
				t20.g-t21.g);

			local del01=step_size*(
				t02.r-t12.r+
				t02.g-t00.g);

			local out_p=tmp2:sget(x,y)
			out_p.r=out_p.r-del00+del10
			out_p.g=out_p.g-del00+del01
		end
		end
		if step==1 or step==step_count then
			print("S:",step," d:",max_del)
		end
		local t=tmp
		tmp=tmp2
		tmp2=t
	end
	vectorfield=tmp
end
function resize( w,h )
	image=make_image_buffer(w,h)
end
CA_rule={
	[1]=1,
	[2]=1,
	[3]=1,
	[4]=0,
	[5]=1,
	[6]=1,
}
local cx=math.floor(size[1]/2)
local cy=math.floor(size[2]/2)
local wavefront={}
function fix_coord( x,y )
	x=x%(size[1])
	y=y%(size[2])
	--[[if math.floor(x) <0 then error("X neg") end
	if math.floor(y) <0 then error("Y neg") end
	if math.floor(x)>size[1]-1 then error("X too big") end
	if math.floor(y)>size[2]-1 then error("Y too big") end]]
	return x,y
end
function add_sources(x,y, cnts )
	local retx=0
	local rety=0

	for i,v in ipairs(cnts) do
		local dx=x-v[1]
		local dy=y-v[2]
		local dist=math.sqrt(dx*dx+dy*dy)
		retx=retx+dx/(dist+1)
		rety=rety+dy/(dist+1)
	end
	return retx,rety
end
function reset_buffer(  )
	local cdx=0
	local cdy=1.6
	local scale=0.25
	local scale_out=0.6
	local per_scale=0.0
	local noise_scale=3
	local per_offset_x={math.random()*500-200,math.random()*500-200}
	local per_offset_y={math.random()*500-200,math.random()*500-200}
	local cnts={
		{size[1]/3,size[2]/3},
		{size[1]*2/3,size[2]*2/2},
	}
	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		--[[
		local p=visits:get(x,y)
		p.r=math.random()*0
		p.g=math.random()*0
		p.b=math.random()*0
		visits2:set(x,y,p)
		--]]
		local vc=vectorfield:sget(x,y)
		local tcx=x-cx
		local tcy=y-cy
		local tcl=math.sqrt(tcx*tcx+tcy*tcy)

		local curl_scale=0--0.002*tcl/(size[1]/2)
		local dx=cdx+
			perlin:noise(x*per_scale+per_offset_x[1],y*per_scale+per_offset_x[2])-
			tcy*curl_scale/(tcl+1)

		--local dx=math.random()-0.5+cdx+tcx*scale_out/(tcl+1)
		local dy=cdy+
			perlin:noise(x*per_scale+per_offset_y[1],y*per_scale+per_offset_y[2])+
			tcx*curl_scale/(tcl+1)
		local sx,sy=add_sources(x,y,cnts)
		dx=dx+sx*scale_out
		dy=dy+sy*scale_out
		
		--[[
		dx=dx+(math.random()-0.5)*noise_scale
		dy=dy+(math.random()-0.5)*noise_scale
		--]]
		local a,r
		a=math.atan(dy,dx)
		r=math.sqrt(dx*dx+dy*dy)
		a=a+math.random()*noise_scale
		r=r*(math.random()*noise_scale+0.5)

		dx=r*math.cos(a)
		dy=r*math.sin(a)
		--local dy=math.random()-0.5+cdy+tcy*scale_out/(tcl+1)
		--[[local l=math.sqrt(dx*dx+dy*dy)
		vc.r=dx/l
		vc.g=dy/l]]
		vc.r=dx*scale
		vc.g=dy*scale
	end
	end
	relax_flowfield(20,0.001)
	--[[
	for x=0,size[1]-1 do
		local c=visits:sget(x,0)
		c.r=math.random()
		c.g=math.random()
		c.b=math.random()
		
	end
	--table.insert(wavefront,{size[1]/4,0})
	--table.insert(wavefront,{math.floor(size[1]*3/4),0})

	--]]
	wavefront={}
	local count=12
	--[[
	local r=50
	for i=0,count-1 do
		local phi=(i/count)*(math.pi*2)
		local x=cx+math.cos(phi)*r
		local y=cy+math.sin(phi)*r
		x,y=fix_coord(x,y)
		table.insert(wavefront,{math.floor(x),math.floor(y)})
	end
	--]]
	local h=math.random()*size[2]
	for i=0,count-1 do
		local v=i/count
		table.insert(wavefront,{v*size[1],h})
	end
	--[[
	local radius=min_r
	for r=0,radius do
		local step=math.atan(1/size[1],r)
		for phi=0,math.pi*2,step do
			local tx=math.floor(cx+math.cos(phi)*r)
			local ty=math.floor(cy+math.sin(phi)*r)
			local c=visits:sget(tx,ty)
			c.r=math.random()
			c.g=math.random()
			c.b=math.random()
		end
	end
	--]]
end
reset_buffer()
function get_points_rect(x,y)
	local ret={}
	local nx=x+1
	if nx>=size[1] then nx=0 end
	local px=x-1
	if px<0 then px=size[1]-1 end
	ret[1]=visits:sget(px,y)
	ret[2]=visits:sget(x,y)
	ret[3]=visits:sget(nx,y)
	return ret
end
function get_points(phi,rad,phisize)
	local ret={}
	local a={
	phi+phisize,
	phi,
	phi-phisize
	}
	for i=1,3 do
		local tx=math.floor(cx+math.cos(a[i])*rad)
		local ty=math.floor(cy+math.sin(a[i])*rad)
		ret[i]=visits:sget(tx,ty)
	end
	return ret
end
function get_rule( pts )
	local ret=0
	for i,v in ipairs(pts) do
		if v.r>0.5 then
			ret=ret+math.pow(2,i-1)
		end
	end
	return CA_rule[ret] or 0
end
function get_rules( pts )
	local ret={0,0,0}
	for i,v in ipairs(pts) do
		if v.r>0.5 then
			ret[1]=ret[1]+math.pow(2,i-1)
		end
		if v.g>0.5 then
			ret[2]=ret[2]+math.pow(2,i-1)
		end
		if v.b>0.5 then
			ret[3]=ret[3]+math.pow(2,i-1)
		end
	end
	return {r=CA_rule[ret[1]] or 0,
			g=CA_rule[ret[2]] or 0,
			b=CA_rule[ret[3]] or 0,}
end
function lerp( v1,v2,t )
	return {r=v1.r*(1-t)+v2.r*t,
			g=v1.g*(1-t)+v2.g*t,
			b=v1.b*(1-t)+v2.b*t}
end
function lerp2( v1,v2,t )
	return {r=v1.r*(1-t)+v2.r*t,
			g=v1.g*(1-t)+v2.g*t,
			}
end
function sample_visits( x,y )
	local lx=math.floor(x)
	local hx=lx+1
	local ly=math.floor(y)
	local hy=ly+1

	local frx=x-lx
	local fry=y-ly

	lx,ly=fix_coord(lx,ly)
	hx,hy=fix_coord(hx,hy)

	local ll=visits:sget(lx,ly)
	local lh=visits:sget(lx,hy)
	local hl=visits:sget(hx,ly)
	local hh=visits:sget(hx,hy)

	local xl=lerp(ll,hl,frx)
	local xh=lerp(lh,hh,frx)

	return lerp(xl,xh,fry)
	--return lerp(ll,hh,fry)
end
function sample_visits_out( x,y ,col)
	local lx=math.floor(x)
	local hx=lx+1
	local ly=math.floor(y)
	local hy=ly+1

	local frx=x-lx
	local fry=y-ly

	lx,ly=fix_coord(lx,ly)
	hx,hy=fix_coord(hx,hy)
	--TODO: actual out-sampling

	local ll=visits:sget(lx,ly)
	local lh=visits:sget(lx,hy)
	local hl=visits:sget(hx,ly)
	local hh=visits:sget(hx,hy)

	visits2:set(lx,ly,lerp(col,ll,frx*fry))
	visits2:set(lx,hy,lerp(col,lh,frx*(1-fry)))
	visits2:set(hx,ly,lerp(col,hl,(1-frx)*fry))
	visits2:set(hx,hy,lerp(col,hh,(1-frx)*(1-fry)))

end
function do_rule( x,y,dx,dy )
	local ox=x-dx
	local oy=y-dy
	--local tx,ty=fix_coord(ox,oy)
	--tx=math.floor(tx)
	--ty=math.floor(ty)
	--local p=visits:sget(tx,ty)

	local dist=math.sqrt(dx*dx+dy*dy)
	local vv=sample_visits(ox,oy)
	--local vv2=sample_visits(ox-dy,oy+dx)
	--local vv3=sample_visits(ox+dy,oy+dx)
	--local rr=get_rules({vv2,vv,vv3})

	-- [[
	local noise_scale=0.1
	vv.r=vv.r+math.random()*noise_scale-noise_scale/2
	vv.g=vv.g+math.random()*noise_scale-noise_scale/2
	vv.b=vv.b+math.random()*noise_scale-noise_scale/2
	vv.a=1
	--l=l*l
	if vv.r>1 then vv.r=1 end
	if vv.g>1 then vv.g=1 end
	if vv.b>1 then vv.b=1 end
	if vv.r<0 then vv.r=0 end
	if vv.g<0 then vv.g=0 end
	if vv.b<0 then vv.b=0 end
	--if math.random()>0.5 then
	--visits2:set(tx,ty,vv)
	sample_visits_out(x,y,vv)
	--end
	--]]
	--[[
	rr.g=rr.r
	rr.b=rr.r
	sample_visits_out(x,y,rr)
	--]]
end
do_step=false
function gui(  )
	imgui.Begin("CA")
	if imgui.Button("Reset") then
		reset_buffer()
		current_y=1
		current_r=min_r
	end
	if imgui.Button("step") then
		do_step=true
	end
	if imgui.Button("fx") then
		first=3
	end
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
end

function draw_wavefront( clear )
	local vv={r=0,g=1,b=0}
	if clear then
		vv.g=0
	end
	for i,v in ipairs(wavefront) do
		local x,y=fix_coord(v[1],v[2])
		sample_visits_out(x,y,vv)

		if clear then
			visits:set(math.floor(v[1]),math.floor(v[2]),vv)
		end
	end
end

function fix_coord_delta( x,y,nx,ny )
	local hw=size[1]/2
	local hh=size[2]/2

	local dx=nx-x
	-- [[
	if dx>hw then
		dx=size[1]-dx
	end
	if dx<-hw then
		dx=dx+size[1]
	end
	--]]

	local dy=ny-y
	-- [[
	if dy>hh then
		dy=size[2]-dy
	end
	if dy<-hh then
		dy=dy+size[2]
	end
	--]]
	
	return dx,dy
end

first=4
function fix_wavefront(  )
	local min_dist=1
	local ret={}
	local count=1
	local last_t={wavefront[1][1],wavefront[1][2]}
	local tt={wavefront[1][1],wavefront[1][2]}
	--print(i,tt[1],tt[2])
	for i=2,#wavefront+1 do
		local np=wavefront[i]
		if i==#wavefront+1 then
			np=wavefront[1]
		end
		local dx,dy=fix_coord_delta(last_t[1],last_t[2],np[1],np[2])
		local dist=math.sqrt(dx*dx+dy*dy)
		--print(i,dx,dy,dist)
		if dist>min_dist then --if distance too great, add pixels
			--print("A:",tt[1]/count,tt[2]/count)
			--table.insert(ret,{tt[1]/count,tt[2]/count})
			local tdx=dx/dist
			local tdy=dy/dist
			--local step=math.max(math.abs(tdx),math.abs(tdy))
			--tdx=tdx/step
			--tdy=tdy/step
			--print(tdx,tdy)
			local tot={tt[1]/count,tt[2]/count}
			tot=last_t
			for i=1,dist-0.5,min_dist do

				table.insert(ret,{tt[1]/count,tt[2]/count})
				last_t={tt[1]/count,tt[2]/count}
				local x=tot[1]+tdx*i
				local y=tot[2]+tdy*i
				--x,y=fix_coord(x,y)
				tt={x,y}
				count=1
			end
		else --if distance is small average points
			tt[1]=tt[1]+np[1]
			tt[2]=tt[2]+np[2]
			count=count+1
		end
	end
	--print("A:",tt[1]/count,tt[2]/count)

	table.insert(ret,{tt[1]/count,tt[2]/count})
	--print("wavefront2:",#ret)
	--if first>2 then
		wavefront=ret
	--end
	if first>1 then
		first=first-1
	end
end
function sample_flowfield( x,y )
	local lx=math.floor(x)
	local hx=lx+1
	local ly=math.floor(y)
	local hy=ly+1

	local frx=x-lx
	local fry=y-ly

	lx,ly=fix_coord(lx,ly)
	hx,hy=fix_coord(hx,hy)

	local ll=vectorfield:sget(lx,ly)
	local lh=vectorfield:sget(lx,hy)
	local hl=vectorfield:sget(hx,ly)
	local hh=vectorfield:sget(hx,hy)

	local xl=lerp2(ll,hl,frx)
	local xh=lerp2(lh,hh,frx)
	return lerp2(xl,xh,fry)
end
function advance_wavefront(  )
	for i,v in ipairs(wavefront) do
		local x=v[1]
		local y=v[2]
		local vec=sample_flowfield(x,y)
		--local step_size=math.max(math.abs(vec[1]),math.abs(vec[2]))
		x=x+vec.r--/step_size
		y=y+vec.g--/step_size
		--x,y=fix_coord(x,y)
		do_rule(x,y,vec.r,vec.g)
		v[1]=x
		v[2]=y
	end
	--print("wavefront1:",#wavefront)
	fix_wavefront()
	--print("wavefront2:",#wavefront)
end
local global_tick=0
function update(  )
	__no_redraw()
	__clear()
	gui()
	for step=1,1 do
		--[[
		local step_size=math.atan(1/size[1],current_r)
		for phi=0,math.pi*2,step_size do
			local tx=math.floor(cx+math.cos(phi)*current_r)
			local ty=math.floor(cy+math.sin(phi)*current_r)
			local c_out=visits:sget(tx,ty)
			local pr=current_r-1
			if pr<min_r-1 then pr=math.floor(size[1]/2)-1 end
			local step_size_p=math.atan(1/size[1],pr)
			local input=get_points(phi,pr,step_size_p)
			local v=get_rule(input)
			if v>0.5 then
				c_out.r=1
				c_out.g=1
				c_out.b=1
			else
				c_out.r=0
				c_out.g=0
				c_out.b=0
			end
		end
		current_r=current_r+1
		if current_r>=size[1]/2 then current_r=min_r end
		--]]
		--[[
		for x=0,size[1]-1 do
			local py=current_y-1
			if py<0 then py=size[2]-1 end
			local input=get_points_rect(x,py)
			local c_out=visits:sget(x,current_y)
			local v=get_rule(input)
			if math.random()>0.999999 then
				v=1-v
			end
			if v>0.5 then
				c_out.r=1
				c_out.g=1
				c_out.b=1
			else
				c_out.r=0
				c_out.g=0
				c_out.b=0
			end
		end
		current_y=current_y+1
		if current_y>=size[2] then current_y=0 end
		--]]
		--if do_step then
			if global_tick%20~=0 then
				draw_wavefront(true)
			end
			advance_wavefront()
			draw_wavefront()
			do_step=false
			local w=visits
			visits=visits2
			visits2=w
			global_tick=global_tick+1
		--end
	end
	draw_visits()
end