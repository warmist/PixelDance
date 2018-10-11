require 'common'
local size=STATE.size
visits=visits or make_flt_buffer(size[1],size[2])

function resize( w,h )
	visits=make_flt_buffer(size[1],size[2])
end

pos=pos or {STATE.size[1]/2,STATE.size[2]/2}


local log_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec2 min_max;
uniform sampler2D tex_main;
uniform int auto_scale_color;


void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec3 col=texture(tex_main,normed).xyz;
	vec2 lmm=min_max;

	if(auto_scale_color==1)
		col=(log(col+vec3(1,1,1))-vec3(lmm.x))/(lmm.y-lmm.x);
	else
		col=log(col+vec3(1))/lmm.y;
	col=clamp(col,0,1);
	//nv=math.min(math.max(nv,0),1);
	//--mix(pix_out,c_u8,c_back,nv)
	//mix_palette(pix_out,nv)
	//img_buf:set(x,y,pix_out)
	color = vec4(col,1);
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
function draw_visits(  )
	local lmax=0
	local lmin=math.huge
	local vst=visits

	for x=0,size[1]-1 do
	for y=0,size[2]-1 do
		local vp=vst:get(x,y)
		local v=vp.r*vp.r+vp.g*vp.g+vp.b*vp.b
		if v>0.0001 then
			if lmax<v then lmax=v end
			if lmin>v then lmin=v end
		end
	end
	end
	lmax=math.log(math.sqrt(lmax)+1)
	lmin=math.log(math.sqrt(lmin)+1)
	log_shader:use()
	visit_tex:use(0)
	visits:write_texture(visit_tex)
	log_shader:set("min_max",lmin,lmax)
	log_shader:set_i("tex_main",0)
	local auto_scale=1
	log_shader:set_i("auto_scale_color",auto_scale)
	log_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
end

function resize( w,h )
	image=make_image_buffer(w,h)
end
function update(  )
	__no_redraw()
	__clear()
	local x=pos[1]
	local y=pos[2]
	local w=STATE.size[1]
	local h=STATE.size[2]
	local col={math.random(),math.random(),math.random()}
	local rand_col=0.00001
	for i=1,1000000 do
		local c=visits:get(x,y)
		for i=1,3 do
			col[i]=col[i]+math.random()*rand_col-rand_col/2
			if col[i] > 1 then col[i]=1 end
			if col[i] < 0 then col[i]=0 end
		end
		c.r=c.r+col[1]
		c.g=c.g+col[2]
		c.b=c.b+col[3]

		c.a=1
		if math.random()>0.5 then
			x=x+math.random(-1,1)
		else
			y=y+math.random(-1,1)
		end
		if x<0 then x=w-2 end
		if y<0 then y=h-2 end
		if x>=w-1 then x=0 end
		if y>=h-1 then y=0 end
		pos[1]=x
		pos[2]=y
	end
	draw_visits()
end