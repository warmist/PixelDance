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

__set_window_size(1024,1024)
local scale_factor=0.25
local size={STATE.size[1]*scale_factor,STATE.size[2]*scale_factor}
--size[1]=size[1]*0.125
--size[2]=size[2]*0.125
local global_tick=0
visits=visits or make_flt_buffer(size[1],size[2])
visits2=visits2 or make_flt_buffer(size[1],size[2])
vectorfield=vectorfield or make_flt_half_buffer(size[1],size[2])
function resize( w,h )
	size={STATE.size[1]*scale_factor,STATE.size[2]*scale_factor}
	visits=make_flt_buffer(size[1],size[2])
	visits2=make_flt_buffer(size[1],size[2])
	vectorfield=make_flt_half_buffer(size[1],size[2])
end
local max_vertex_count=10000
wavefront_vertices=wavefront_vertices or make_flt_half_buffer(max_vertex_count,1)


config=make_config({
	{"gamma",2.2,type="float",min=-5,max=5},
	{"wave_step_size",1.61803398875,type="float",min=0.01,max=5},
	{"update_dist",25,type="int",min=0,max=125},
	{"value_grow",0.001,type="floatsci",min=0,max=1,power=10},
	{"value_shrink",0.002,type="floatsci",min=0,max=1,power=10},
},config)

local wavefront=wavefront or {
	buf=wavefront_vertices,
	count=0,
	count_mirror=0,
}

function wavefront:insert( x,y )
	self.buf:set(self.count,0,{x,y})
	self.count=self.count+1
end
function wavefront:insert_mirror( x,y )
	self.buf:set(self.count+self.count_mirror,0,{x,y})
	self.count_mirror=self.count_mirror+1
end
function wavefront:clear_mirror()
	self.count_mirror=0
end
pos=pos or {size[1]/2,size[2]/2}

local draw_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;


uniform sampler2D tex_main;
uniform float gamma_value;
uniform float current_y;
uniform float current_age;
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	normed.y=1-normed.y;
	vec3 col=texture(tex_main,normed).xyz;
	//col*=(1-col.b*5);
	//col*=clamp(col.g*10,0.3,1);
	//float value=abs(current_age/255-col.z);//col.y;
	float value=col.y;
	value=clamp(value,0,1);
	if(gamma_value<0)
		value=1-pow(1-value,-gamma_value);
	else
		value=pow(value,gamma_value);

	//value+=col.x*0.05;
	//col=palette(value,vec3(0.5),vec3(0.5),vec3(0,1.5,1.05),vec3(0.5,0.25,0.7));
	col=vec3(value);
	//col.r=pow(col.g,1.2);
	//col=vec3(col.x);
	//float min_v=0.9;
	//float d=clamp(1-max(-normed.y+current_y,0),min_v,1);
	//if(current_y<normed.y)
	//	d=min_v;
	//d=pow(d,10);
	float d=1;
	color = vec4(col*d,1);
}
]==]

local draw_wavefront_shader=shaders.Make(
--Vertex shader
[==[
#version 330

layout(location = 0) in vec2 pos_line;

out vec2 pos;
void main()
{
	//vec2 mpos=mod(pos_line,vec2(1));
	vec2 mpos=pos_line;
    gl_Position.xy = (mpos-vec2(0.5))*2;
    gl_Position.z=0;
    gl_Position.w = 1.0;
    pos.xy=pos_line;
}
]==],
--Pixel shader
[==[
#version 330
in vec2 pos;
out vec4 color;

void main()
{
	color= vec4(0.5,0.01,0.1,1);
}
]==]
)
local need_save
visit_tex =visit_tex or textures.Make()
visit_tex:use(0)
visits:write_texture(visit_tex)
last_pos=last_pos or {0,0}
function save_img(tile_count)
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
--[[	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end]]
	img_buf=make_image_buffer(size[1]/scale_factor,size[2]/scale_factor)
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
local current_y=1
local min_r=5
local current_r=min_r
function draw_visits(  )

	draw_shader:use()
	visit_tex:use(0)
	if global_tick %2==0 then
		visits2:write_texture(visit_tex)
	else
		visits:write_texture(visit_tex)
	end
	draw_shader:set_i("tex_main",0)
	draw_shader:set("gamma_value",config.gamma)
	draw_shader:set('current_age',front_id or 0)
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
--[[ maze 
CA_rule_dead={
	[0]=0,
	[1]=0,
	[2]=0,
	[3]=1,
	[4]=0,
	[5]=0,
	[6]=0,
	[7]=0,
	[8]=0,
	[9]=0,
}
CA_rule_alive={
	[0]=0,
	[1]=1,
	[2]=1,
	[3]=1,
	[4]=1,
	[5]=1,
	[6]=0,
	[7]=0,
	[8]=0,
	[9]=0,
}
--]]
CA_rule_dead={
	[0]=0,
	[1]=0,
	[2]=0,
	[3]=1,
	[4]=0,
	[5]=1,
	[6]=1,
	[7]=1,
	[8]=0,
	[9]=0,
}
CA_rule_alive={
	[0]=0,
	[1]=0,
	[2]=1,
	[3]=1,
	[4]=0,
	[5]=0,
	[6]=0,
	[7]=0,
	[8]=0,
	[9]=0,
}
local cx=math.floor(size[1]/2)
local cy=math.floor(size[2]/2)
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
		-- [[
		local dx=x-size[1]/2
		local dy=y-size[2]/2
		local d=math.sqrt(dx*dx+dy*dy)
		if d<size[1]/2.2 then
			local p=visits:get(x,y)
			p.r=1
			p.g=0
			p.b=0
			visits2:set(x,y,p)
		else
			visits:set(x,y,{0,0,0,0})
			visits2:set(x,y,{0,0,0,0})
		end
		--]]
		--[===[
		local vc=vectorfield:sget(x,y)
		local tcx=x-cx
		local tcy=y-cy
		local tcl=math.sqrt(tcx*tcx+tcy*tcy)

		local curl_scale=0.002*tcl/(size[1]/2)
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
		--]===]
	end
	end
	visit_tex:use(0)
	visits2:write_texture(visit_tex)
	--relax_flowfield(20,0.001)
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
	--wavefront={}
	wavefront.count=0
	local count=100
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
	local h=math.random()
	for i=0,count do
		local v=i/count
		local vn=(i+1)/count
		--table.insert(wavefront,{v*size[1],h})
		wavefront:insert(v,h)
		if i~=0 and i~=count then
			wavefront:insert(v,h)
		end
		--insert_to_wavefront(vn,h)
	end
	print("Vertex after reset:",wavefront.count)
	wavefront.buf:update_buffer_data(wavefront.count)
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
--reset_buffer()
function get_points_around(x,y)
	local x=math.floor(x)
	local y=math.floor(y)
	local count=0
	local count_s=0
	for dx=-1,1 do
	for dy=-1,1 do
		local tx,ty=fix_coord(x+dx,y+dy)
		local v=visits:sget(tx,ty).r
		if v>0.5 then
			count=count+1
			if dx==0 and dy==0 then
				count_s=count_s+1
			end
		end
	end
	end
	return count,count_s
end
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
function do_rule( x,y,dx,dy ,id)
	-- [[
	if math.abs(visits:sget(x,y).b*255-id)<config.update_dist then
		return
	end
	--]]
	local v,vs=get_points_around(x,y)
	local rule_res
	if vs==0 then
		rule_res=CA_rule_dead[v] or 0
	else
		rule_res=CA_rule_alive[v] or 0
	end
	--[[
	local scale=10
	local ox=x-dx*scale
	local oy=y-dy*scale
	--]]
	--local tx,ty=fix_coord(ox,oy)
	--tx=math.floor(tx)
	--ty=math.floor(ty)
	--local p=visits:sget(tx,ty)
	--[==[
	local dist=math.sqrt(dx*dx+dy*dy)
	local vv=sample_visits(ox,oy)
	local vv2=sample_visits(ox-dy,oy+dx)
	local vv3=sample_visits(ox+dy,oy+dx)
	local rr=get_rules({vv2,vv,vv3})
	--]==]

	--[[
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
	rr={r=rule_res}
	rr.g=id
	rr.b=rr.r
	--sample_visits_out(x,y,rr)
	--]]
	local tr=visits2:sget(x,y)
	tr.r=rule_res

	if rule_res>0.5 then
		tr.g=tr.g+config.value_grow
		--if tr.g<0.5 then tr.g=0.5 end
		if tr.g>1 then tr.g=1 end
	else
		tr.g=tr.g-config.value_shrink
		if tr.g<0 then tr.g=0 end
		--if tr.g>0.5 then tr.g=0.5 end
	end
	tr.b=id/255
	--]]
end
do_step=1
function gui(  )
	imgui.Begin("CA")
	draw_config(config)
	if imgui.Button("Reset") then
		reset_buffer()
		current_y=1
		current_r=min_r
		wavefront_step=0
	end
	if imgui.Button("step") then
		do_step=150
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
	--[[local vv={r=0,g=1,b=0}
	if clear then
		vv.g=0
	end
	for i,v in ipairs(wavefront) do
		local x,y=fix_coord(v[1],v[2])
		sample_visits_out(x,y,vv)

		if clear then
			visits:set(math.floor(v[1]),math.floor(v[2]),vv)
		end
	end]]
	
	draw_wavefront_shader:use()
	--draw_wavefront_shader:blend_add()
	visit_tex:use(1)
	--visits2:write_texture(visit_tex)
	--
	--local bd=wavefront.buf:buffer_data()
	--bd:use()
	draw_wavefront_shader:push_attribute(wavefront.buf.d,"pos_line",2,nil,2*4)

	if not visit_tex:render_to(size[1],size[2]) then
		__unbind_buffer()
		__render_to_window()
		error("failed to set framebuffer up")
	end
	__clear()
	draw_wavefront_shader:draw_lines(nil,wavefront.count+wavefront.count_mirror,false)
	--draw_wavefront_shader:draw_points(nil,wavefront.count,true)
	draw_wavefront_shader:blend_default()
	__unbind_buffer()
	__render_to_window()
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
function wrap_coords_noop(p)
	local dx=0
	local dy=0
	if p.r<0 then dx=1 end
	if p.r>1 then dx=-1 end
	if p.g<0 then dy=1 end
	if p.g>1 then dy=-1 end
	return dx,dy
end
function wrap_coords(p)
	local dx=0
	local dy=0
	if p.r<0 then p.r=p.r+1;dx=1 end
	if p.r>1 then p.r=p.r-1;dx=-1 end
	if p.g<0 then p.g=p.g+1;dy=1 end
	if p.g>1 then p.g=p.g-1;dy=-1 end
	return dx,dy
end
function line_len(p1,p2 )
	local dx=p1.r-p2.r
	local dy=p1.g-p2.g
	return math.sqrt(dx*dx+dy*dy)
end
function fix_wavefront(  )
	if first<1 then
		return
	end

	wavefront:clear_mirror()
	local max_len=0.1
	local cur_wv_count=wavefront.count
	for i=0,cur_wv_count,2 do
		local v1=wavefront.buf:get(i,0)
		local v2=wavefront.buf:get(i+1,0)
		local L=line_len(v1,v2)
		if L> max_len and wavefront.count+2<max_vertex_count then
			local ox=v2.r
			local oy=v2.g
			local mx=(v1.r+v2.r)/2
			local my=(v1.g+v2.g)/2
			v2.r=mx
			v2.g=my
			wavefront:insert(mx,my)
			wavefront:insert(ox,oy)
		end
	end
	for i=0,wavefront.count-1,2 do
		local v1=wavefront.buf:get(i,0)
		local v2=wavefront.buf:get(i+1,0)
		local count_outside=0
		if v1.r<0 or v1.r>1 or v1.g<0 or v1.g>1 then
			count_outside=count_outside+1
		end
		if v2.r<0 or v2.r>1 or v2.g<0 or v2.g>1 then
			count_outside=count_outside+1
		end
		if count_outside==2 then
			local len_bef=line_len(v1,v2)
			local pts_bef={v1.r,v1.g,v2.r,v2.g}
			local dx,dy=wrap_coords(v1)
			v2.r=v2.r+dx
			v2.g=v2.g+dy
			dx,dy=wrap_coords(v2)
			v1.r=v1.r+dx
			v1.g=v1.g+dy
			local len_after=line_len(v1,v2)
			if len_after-len_bef>0.1 then
				print("WTF:",i,len_bef,len_after)
				for i,v in ipairs(pts_bef) do
					print(v)
				end
				do_step=0
			end
			--wavefront.buf:set(i,0,v1)
			--wavefront.buf:set(i+1,0,v2)
		elseif count_outside==1 then
			local dx,dy=wrap_coords_noop(v1)
			if dx==0 and dy==0 then
				wrap_coords_noop(v2)
			end
			if wavefront.count+wavefront.count_mirror+2<max_vertex_count then
				wavefront:insert_mirror(v1.r+dx,v1.g+dy)
				wavefront:insert_mirror(v2.r+dx,v2.g+dy)
			end
		end
	end

	--[==[local min_dist=1
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
	--]==]
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
wavefront_step=0
front_id=0
function advance_wavefront()
	wavefront_step=wavefront_step+config.wave_step_size
	if wavefront_step>math.sqrt(2)*size[1]/2 then
	 	wavefront_step=wavefront_step-math.sqrt(2)*size[1]/2
	 	front_id=front_id+1
	 	if front_id>255 then front_id=0 end
	 	config.wave_step_size=math.random()+0.2
	end
	local radius=wavefront_step

	function set_pixel( tx,ty )
		if tx>=0 and ty>=0 and tx<size[1] and ty<size[2] then
			do_rule(tx,ty,0,0,front_id)
		end
	end
	function set_pixels( x,y )
		local cx=size[1]/2
		local cy=size[2]/2
		set_pixel(cx+x,cy+y)
		set_pixel(cx-x,cy+y)
		set_pixel(cx+x,cy-y)
		set_pixel(cx-x,cy-y)

		set_pixel(cx+y,cy+x)
		set_pixel(cx-y,cy+x)
		set_pixel(cx+y,cy-x)
		set_pixel(cx-y,cy-x)
	end
	local x=radius
	local y=0
	local err=1-radius
	while x>y do
		set_pixels(math.floor(x),math.floor(y))
		y=y+1
		if err<0 then
			err=err+2*y+1
		else
			x=x-1
			err=err+2*(y-x)+1
		end
	end
end
function advance_wavefront_ex(  )
	--[==[
	for i=0,wavefront.count-1 do
		local v=wavefront.buf:get(i,0)
		local x=v.r*size[1]
		local y=v.g*size[2]
		local vec=sample_flowfield(x,y)
		--local step_size=math.max(math.abs(vec[1]),math.abs(vec[2]))
		-- [[
		x=x+vec.r--/step_size
		y=y+vec.g--/step_size
		--]]
		--[[
		local vv=v.r
		if vv>1 then vv=1 end
		if vv<0 then vv=0 end
		x=x+0.3
		y=y+(0.3)*vv+(0.8)*(1-vv)
		--]]
		--x,y=fix_coord(x,y)
		do_rule(x,y,vec.r,vec.g)
		wavefront.buf:set(i,0,{x/size[1],y/size[2]})
	end
	--]==]
	local step=1/size[1]

	for i=0,wavefront.count-1,2 do
		local v1=wavefront.buf:get(i,0)
		local v2=wavefront.buf:get(i+1,0)

		local len=line_len(v1,v2)
		local vec1={0,0}
		local w1=0
		local vec2={0,0}
		local w2=0
		for dt=0,len,step do
			local it=dt/len
			local x=(v1.r*(1-it)+v2.r*it)*size[1]
			local y=(v1.g*(1-it)+v2.g*it)*size[2]
			local vec=sample_flowfield(x,y)

			do_rule(x,y,vec.r,vec.g)
			-- [[
			local ww1=(1-it)*(1-it)
			local ww2=it*it
			vec1[1]=vec1[1]+vec.r*ww1
			vec1[2]=vec1[2]+vec.g*ww1
			w1=w1+ww1
			vec2[1]=vec2[1]+vec.r*ww2
			vec2[2]=vec2[2]+vec.g*ww2
			w2=w2+ww2
			--]]
			--[[
			if dt==0 then
				vec1=vec
				w1=1
				vec2=vec
				w2=1
			else
				vec2=vec
				w2=1
			end
			--]]
		end
		--[[
		v1.r=v1.r+(vec1.r/w1)/size[1]
		v1.g=v1.g+(vec1.g/w1)/size[2]
		v2.r=v2.r+(vec2.r/w2)/size[1]
		v2.g=v2.g+(vec2.g/w2)/size[2]
		--]]
		v1.r=v1.r+(vec1[1]/w1)/size[1]
		v1.g=v1.g+(vec1[2]/w1)/size[2]
		v2.r=v2.r+(vec2[1]/w2)/size[1]
		v2.g=v2.g+(vec2[2]/w2)/size[2]
	end
	--print("wavefront1:",#wavefront)
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
		if do_step>0 then
			if global_tick%20~=0 then
				--draw_wavefront(true)
			end
			advance_wavefront()
			--draw_wavefront()

			local w=visits
			visits=visits2
			visits2=w
			global_tick=global_tick+1
			--do_step=do_step-1
		end
	end
	draw_visits()
end