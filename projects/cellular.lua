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
local size=STATE.size
--size[1]=size[1]*0.125
--size[2]=size[2]*0.125
visits=visits or make_flt_buffer(size[1],size[2])
vectorfield=vectorfield or make_flt_half_buffer(size[1],size[2])
function resize( w,h )
	visits=make_flt_buffer(size[1],size[2])
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
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	image_no=image_no+1
end
local current_y=1
local min_r=5
local current_r=min_r
function draw_visits(  )

	draw_shader:use()
	visit_tex:use(0)
	visits:write_texture(visit_tex)
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
		tmp:set(x,y,tmp2:get(x,y))
	end
	end
	for step=1,step_count do
		local max_del=-math.huge
		for x=0,size[1]-1 do
		for y=0,size[2]-1 do
			local nx=x+1
			if nx==size[1]-1 then nx=0 end
			local px=x-1
			if px<0 then px=size[1]-1 end

			local ny=y+1
			if ny==size[2]-1 then ny=0 end
			local py=y-1
			if py<0 then py=size[2]-1 end

			local t00=tmp:get(x,y)
			local t10=tmp:get(nx,y)
			local t01=tmp:get(x,ny)

			local t20=tmp:get(px,y)
			local t02=tmp:get(x,py)
			local t21=tmp:get(px,ny)
			local t12=tmp:get(nx,py)
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

			local out_p=tmp2:get(x,y)
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
	[5]=1,
	[6]=1,
}
local cx=math.floor(size[1]/2)
local cy=math.floor(size[2]/2)
local wavefront={}
function reset_buffer(  )
	local cdx=0
	local cdy=0
	local scale=2
	local scale_out=0.4
	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local c=visits:get(x,y)
		local vvv=math.random()*0
		c.r=vvv
		c.g=vvv
		c.b=vvv
		local vc=vectorfield:get(x,y)
		local tcx=x-cx
		local tcy=y-cy
		local tcl=math.sqrt(tcx*tcx+tcy*tcy)

		local dx=math.random()-0.5+cdx+tcx*scale_out/tcl
		local dy=math.random()-0.5+cdy+tcy*scale_out/tcl
		--[[local l=math.sqrt(dx*dx+dy*dy)
		vc.r=dx/l
		vc.g=dy/l]]
		vc.r=dx*scale
		vc.g=dy*scale
	end
	end
	relax_flowfield(20,0.001)
	-- [[
	for x=0,size[1]-1 do
		local c=visits:get(x,0)
		c.r=math.random()
		c.g=math.random()
		c.b=math.random()
		
	end
	--table.insert(wavefront,{size[1]/4,0})
	--table.insert(wavefront,{math.floor(size[1]*3/4),0})

	--]]
	wavefront={}
	local r=100
	local count=12
	for i=0,count-1 do
		local phi=(i/count)*(math.pi*2)
		local x=cx+math.cos(phi)*r
		local y=cy+math.sin(phi)*r
		table.insert(wavefront,{math.floor(x),math.floor(y)})
	end
	--[[
	local radius=min_r
	for r=0,radius do
		local step=math.atan(1/size[1],r)
		for phi=0,math.pi*2,step do
			local tx=math.floor(cx+math.cos(phi)*r)
			local ty=math.floor(cy+math.sin(phi)*r)
			local c=visits:get(tx,ty)
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
	ret[1]=visits:get(px,y)
	ret[2]=visits:get(x,y)
	ret[3]=visits:get(nx,y)
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
		ret[i]=visits:get(tx,ty)
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
function sample_visits( x,y )
	local lx=math.floor(x)
	local hx=lx+1
	local ly=math.floor(y)
	local hy=ly+1

	local frx=x-lx
	local fry=y-ly

	lx,ly=fix_coord(lx,ly)
	hx,hy=fix_coord(hx,hy)

	local ll=visits:get(lx,ly).r
	local lh=visits:get(lx,hy).r
	local hl=visits:get(hx,ly).r
	local hh=visits:get(hx,hy).r

	local xl=ll*(1-frx)+hl*frx
	local xh=lh*(1-frx)+hh*frx

	return xl*(1-fry)+xh*fry
end
function do_rule( ox,oy,x,y )
	local dx=x-ox
	local dy=y-oy
	local tx,ty
	tx=math.floor(ox)
	ty=math.floor(oy)
	local p=visits:get(tx,ty)
	local sx,sy
	sx=ox-dx
	sy=oy-dy
	local vv=sample_visits(sx,sy)
	local l=vv+math.random()*0.05--math.sqrt(dx*dx+dy*dy)*4
	--l=l*l
	if l>1 then l=1 end
	--if math.random()>0.5 then
		p.r=l
		p.g=l
		p.b=l
	--end
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
	imgui.End()
end
function draw_wavefront( clear )
	for i,v in ipairs(wavefront) do
		local c_out=visits:get(math.floor(v[1]),math.floor(v[2]))
		c_out.r=0
		if clear then
			c_out.g=0
		else
			c_out.g=1
		end
		c_out.b=0
	end
end
function fix_coord( x,y )
	if math.floor(x)<0 then x=size[1]+x end
	if math.floor(y)<0 then y=size[2]+y end
	if math.floor(x)>size[1]-1 then x=x-size[1] end
	if math.floor(y)>size[2]-1 then y=y-size[2] end
	return x,y
end
function fix_coord_delta( x,y,nx,ny )
	local hw=size[1]/2
	local hh=size[2]/2

	local dx=nx-x
	if dx>hw then
		dx=dx-size[1]
	elseif dx<-hw then
		dx=dx+size[1]
	end

	local dy=ny-y
	if dy>hh then
		dy=dy-size[2]
	elseif dy<-hh then
		dy=dy+size[2]
	end
	
	return dx,dy
end

first=4
function fix_wavefront(  )
	local min_dist=math.sqrt(2)
	local ret={}
	local count=1
	local tt={wavefront[1][1],wavefront[1][2]}
	--print(i,tt[1],tt[2])
	for i=2,#wavefront+1 do
		local np=wavefront[i]
		if i==#wavefront+1 then
			np=wavefront[1]
		end
		local dx,dy=fix_coord_delta(tt[1]/count,tt[2]/count,np[1],np[2])
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
			for i=1,dist-0.5,min_dist do
				table.insert(ret,{tt[1]/count,tt[2]/count})
				local x=tot[1]+tdx*i
				local y=tot[2]+tdy*i
				x,y=fix_coord(x,y)
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
	print("wavefront2:",#ret)
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

	local ll=vectorfield:get(lx,ly)
	local lh=vectorfield:get(lx,hy)
	local hl=vectorfield:get(hx,ly)
	local hh=vectorfield:get(hx,hy)

	local xl_x=ll.r*(1-frx)+hl.r*frx
	local xl_y=ll.g*(1-frx)+hl.g*frx
	local xh_x=lh.r*(1-frx)+hh.r*frx
	local xh_y=lh.g*(1-frx)+hh.g*frx

	return {xl_x*(1-fry)+xh_x*fry,xl_y*(1-fry)+xh_y*fry}
end
function advance_wavefront(  )
	for i,v in ipairs(wavefront) do
		local x=v[1]
		local y=v[2]
		local vec=sample_flowfield(x,y)
		local step_size=math.max(math.abs(vec[1]),math.abs(vec[2]))
		local old_x,old_y
		old_x=x
		old_y=y
		x=x+vec[1]--/step_size
		y=y+vec[2]--/step_size
		x,y=fix_coord(x,y)
		do_rule(old_x,old_y,x,y)
		v[1]=x
		v[2]=y
	end
	print("wavefront1:",#wavefront)
	fix_wavefront()
	--print("wavefront2:",#wavefront)
end
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
			local c_out=visits:get(tx,ty)
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
			local c_out=visits:get(x,current_y)
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
			--draw_wavefront(true)
			advance_wavefront()
			draw_wavefront()
			do_step=false
		--end
	end
	draw_visits()
end