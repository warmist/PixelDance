--[[
	* mass transfer and crystallization
	* block diffusion by other crystals
--]]
require "common"
local win_w=1024
local win_h=1024

__set_window_size(win_w,win_h)
local oversample=0.125
local map_w=math.floor(win_w*oversample)
local map_h=math.floor(win_h*oversample)

local size=STATE.size

img_buf=img_buf or make_image_buffer(map_w,map_h)
material=material or make_float_buffer(map_w,map_h)
function resize( w,h )
	img_buf=make_image_buffer(map_w,map_h)
	material=make_float_buffer(map_w,map_h)
end

local size=STATE.size

tick=tick or 0
config=make_config({
	{"color",{1,1,1,1},type="color"},
	{"material_needed",1,min=0,max=10,type="float"},
	{"material_max",100,min=0,max=100,type="float"},
	{"material_melt",100,min=0,max=100,type="float"},
	{"diffuse_steps",1,min=0,max=10,type="int"},
	--{"cryst_pow",1,min=0.0001,max=5,type="float"},
	--{"diffuse",0.5,type="float"},
	{"decay",0.01,type="floatsci",min=0,max=1,power=10},
	{"add_mat",0.5,type="float"},
	{"simulate",true,type="boolean"},
},config)
image_no=image_no or 0

local decay_diffuse_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform float diffuse;
uniform float decay;

uniform sampler2D tex_main;
uniform sampler2D tex_mask;

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
vec4 laplace_h(vec2 pos)
{
	vec4 ret=vec4(0);

	ret+=textureOffset(tex_main,pos,ivec2(0,-1))*.25;
	ret+=textureOffset(tex_main,pos,ivec2(-1,0))*.25;
	ret+=textureOffset(tex_main,pos,ivec2(1,0))*.25;
	ret+=textureOffset(tex_main,pos,ivec2(0,1))*.25;

	ret+=textureOffset(tex_main,pos,ivec2(0,0))*(-1);
	return ret;
}
float sample_around(vec2 pos)
{
	float ret=0;
	float w=0;
	float tw=0;

	#define sample_tex(dx,dy) tw=1-textureOffset(tex_mask,pos,ivec2(dx,dy)).w;\
	w+=tw;\
	ret+=textureOffset(tex_main,pos,ivec2(dx,dy)).x*tw

	/*sample_tex(-1,-1);
	sample_tex(-1,1);
	sample_tex(1,-1);
	sample_tex(1,1);*/

	sample_tex(1,0);
	sample_tex(-1,0);
	sample_tex(0,1);
	sample_tex(0,-1);

	sample_tex(-1,1);
	sample_tex(1,-1);

	if(w>0)
		return ret/w;
	else
		return 0;
}
void main(){
	//ivec2 ts=textureSize(tex_main,0);
	//float v=max(ts.x,ts.y);
	vec2 normed=(pos.xy+vec2(1,1))/2;

	float r=sample_around(normed)*diffuse;
	r+=texture(tex_main,normed).x*(1-diffuse);
	r*=decay;
	//r=clamp(r,0,1);
	color=vec4(r,0,0,1);
}
void main__()
{

}
]==]
function diffuse_and_decay( tex,tex_out,w,h,diffuse,decay,steps,mask )
	steps=steps or 1
	decay_diffuse_shader:use()
	mask:use(1)
	decay_diffuse_shader:set_i("tex_mask",1)
	for i=1,steps do
	    tex:use(0)
	    decay_diffuse_shader:set_i("tex_main",0)
	    decay_diffuse_shader:set("decay",1-decay)
	    decay_diffuse_shader:set("diffuse",diffuse)
	    if not tex_out:render_to(w,h) then
			error("failed to set framebuffer up")
		end
	    decay_diffuse_shader:draw_quad()
	    --swap textures
	    local c = tex
    	tex=tex_out
    	tex_out=c
	end
    __render_to_window()
    return tex_out
end


local need_save
local mat_tex1 = textures.Make()
local mat_tex2 = textures.Make()
function write_mat()
	mat_tex1:use(0)
	material:write_texture(mat_tex1)
	mat_tex2:use(0)
	material:write_texture(mat_tex2)
end
write_mat()
local img_tex1=textures.Make()
function write_img(  )
	img_tex1:use(0)
	img_buf:write_texture(img_tex1)
end
write_img()
--[===[
local img_tex2=textures.Make()
function write_img(  )
	img_tex1:use(0)
	img_buf:write_texture(img_tex1)
	img_tex2:use(0)
	img_buf:write_texture(img_tex2)
end
write_img()
local crystalize_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;
void main()
{

}
--]===]
function count_nn( x,y )
	-- [[
	local dx={1,0,1,-1,-1,0}
	local dy={0,1,1,0,-1,-1}
	--]]
	--[[
	local dx={1,0,-1,0}
	local dy={0,-1,0,1}
	--]]
	--[[
					sample_tex(1,0);
				sample_tex(0,1);
				sample_tex(1,1);

				sample_tex(-1,0);
				sample_tex(-1,-1);
				sample_tex(0,-1);
				]]
	local ret=0
	for i=1,#dx do
		local tx=x+dx[i]
		if tx<0 then tx=map_w-1 end
		if tx>=map_w then tx=0 end
		local ty=y+dy[i]
		if ty<0 then ty=map_h-1 end
		if ty>=map_h then ty=0 end
		local v=img_buf:get(tx,ty)
		if v.a~=0 then
			ret=ret+1
		end
	end
	return ret
end
function clear_nn( x,y )
	local dx={1,0,1,-1,-1,0}
	local dy={0,1,1,0,-1,-1}
	for i=1,#dx do
		local tx=x+dx[i]
		if tx<0 then tx=map_w-1 end
		if tx>=map_w then tx=0 end
		local ty=y+dy[i]
		if ty<0 then ty=map_h-1 end
		if ty>=map_h then ty=0 end

		material:set(tx,ty,material:get(tx,ty)-config.material_needed/6)
	end
end
function count_mat_nn( x,y )
	-- [[
	local dx={1,0,1,-1,-1,0}
	local dy={0,1,1,0,-1,-1}
	--]]
	--[[
	local dx={1,0,-1,0}
	local dy={0,-1,0,1}
	--]]
	--[[
					sample_tex(1,0);
				sample_tex(0,1);
				sample_tex(1,1);

				sample_tex(-1,0);
				sample_tex(-1,-1);
				sample_tex(0,-1);
				]]
	local ret=0
	for i=1,#dx do
		local tx=x+dx[i]
		if tx<0 then tx=map_w-1 end
		if tx>=map_w then tx=0 end
		local ty=y+dy[i]
		if ty<0 then ty=map_h-1 end
		if ty>=map_h then ty=0 end
		local v=material:get(tx,ty)
		ret=ret+v
	end
	return ret
end
function crystal_step()
	material:read_texture(mat_tex1)
	local crystal_chances={
		[0]=0.0001, --0
		0.0,--1
		0.1,
		0.2,
		0.0,--4
		0.0,
		0,
		0.000001,
		0,
	}
	local chance_mod=0.25
	for x=0,map_w-1 do
		for y=0,map_h-1 do
			local v=material:get(x,y)
			if v>config.material_needed and v<config.material_max then
				local c=count_nn(x,y)
				--[[local pp=config.cryst_pow
				pp=pp*pp
				local r =1-math.exp(pp/(-c*c))--crystal_chances[c]
				]]
				local r =crystal_chances[c]*chance_mod
				if  v>config.material_needed and r>math.random() then
					--material:set(x,y,0)
					material:set(x,y,material:get(x,y)-config.material_needed*1.1)
					clear_nn(x,y)
					local c=config.color
					img_buf:set(x,y,{c[1]*255,c[2]*255,c[3]*255,255})
				end
			end
			local mnn=count_mat_nn(x,y)/6
			if mnn>=config.material_melt or (x==0 and y==0) then
				if img_buf:get(x,y).a~=0 then
					material:set(x,y,material:get(x,y)+config.material_needed)
					img_buf:set(x,y,{0,0,0,0})
				end
			end

		end
	end
	write_img()
	write_mat()
end

function save_img()
	if save_buf==nil or save_buf.w~=win_w or save_buf.h~=win_h then
		save_buf=make_image_buffer(win_w,win_h)
	end

	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	save_buf:read_frame()
	save_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end
local draw_shader=shaders.Make(
[==[
#version 330
#line 118
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform sampler2D tex_cryst;
uniform float angle;
uniform float b_len;
vec2 pixel_to_array(vec2 pos)
{
	//bravais lattice to pixel
	//we normalize the "a" to be 1
	//then we only have "b" and angle
	return vec2(0);
}
vec2 pixel_to_axial_hex(vec2 pos)
{
	///*
	vec2 ret;
 	float temp = floor(pos.x + sqrt(3) * pos.y + 1);
	ret.x = floor((floor(2*pos.x+1) + temp) / 3);
	ret.y = floor((temp + floor(-pos.x + sqrt(3) * pos.y + 1))/3);
	return ret;
	//*/
	/*
	mat2 cnv=mat2(sqrt(3.0)/3.0,-1.0/3.0,0,2.0/3.0);
	return cnv*pos;
	*/
	/*
	vec2 ret;
	ret.x=sqrt(3.0)*pos.x/3.0-pos.y/3.0;
	ret.y=pos.y*(2.0/3.0);
	return ret;
	//*/
	/*
	vec2 ret;
	ret.x=2.0/3.0*pos.x;
	ret.y=-1.0/3.0*pos.x+sqrt(3.0)/3.0*pos.y;
	return ret;
	//*/
}
vec3 pix_to_hex(vec2 pos,float size)
{
	vec2 cp=pos/size;

	vec3 fr=vec3(
		-2.0/3.0*cp.x,
		1.0/3.0*cp.x+(1.0/sqrt(3.0))*cp.y,
		1.0/3.0*cp.x-(1.0/sqrt(3.0))*cp.y);

	vec3 tri_coord=vec3(fr.x-fr.y,fr.y-fr.z,fr.z-fr.x);
	tri_coord=ceil(tri_coord);

	return round(
		vec3(
			tri_coord.x - tri_coord.z,
			tri_coord.y - tri_coord.x,
			tri_coord.z - tri_coord.y
			)/3.0
			);
}
vec2 hex_to_array(vec2 h,float size)
{
	//return vec2(h.x,h.y-max(0,size-h.y));
	return vec2(h.x+floor(h.y/2),h.y);
}
float hex_dist(vec2 a,vec2 b)
{
	return (abs(a.x-b.x)+abs(a.y-b.y)+abs(a.x+a.y-b.x-b.y))/2.0;
}
void main(){
	ivec2 ts=textureSize(tex_main,0);
	float v=max(ts.x,ts.y);
	float hex_size=0.5;

	vec2 normed=pos.xy;//(pos.xy+vec2(1,1))/2;
	normed=pix_to_hex(normed*v,hex_size).xy+0.1;
	//normed=pixel_to_axial_hex(normed*v);
	//normed.y+=floor(normed.x/2);
	//normed=hex_to_array(normed,v);
	normed/=v;
	normed+=vec2(0.5);
	//normed-=vec2(sqrt(3)/2,0);
	//normed=clamp(normed,0,1);
	//color.xyz=vec3(abs(normed.x),abs(normed.y),0);//,abs(-normed.x-normed.y));
	//color.a=1;

/*
	float d=normed.y;//hex_dist(normed,pix_to_hex(vec2(v/2),hex_size).xy);
	//d-=v/2;
	d+=1;
	d*=0.05;
	//d*=100;


	vec3 col = vec3(1.0) - sign(d)*vec3(0.1,0.4,0.7);
	col *= 1.0 - exp(-3.0*abs(d));
	col *= 0.8 + 0.2*cos(150.0*d);
	col = mix( col, vec3(1.0), 1.0-smoothstep(0.0,0.015,abs(d)) );
	color.xyz=col;
	color.a=1;
*/
    vec4 pixel=texture(tex_main,normed);
    vec4 pixel_c=texture(tex_cryst,normed);
    //color=vec4(max(pixel.x,pixel_c.x),pixel_c.y,pixel_c.z,1);

    color=vec4(clamp(pixel*(1-pixel_c.a)+pixel_c,0,1).xyz,1);
#if 0
    if(normed.x<0 || normed.x>1 || normed.y<0 || normed.y>1)
    	color.xyz=vec3(0);
#endif
}
]==])
function draw(  )
	draw_shader:use()
    mat_tex1:use(0)
    img_tex1:use(1)
	draw_shader:set_i("tex_main",0)
	draw_shader:set_i("tex_cryst",1)
	draw_shader:draw_quad()
end
function add_mat( x,y,v )
	if x>=map_w then x=x-map_w end
	if y>=map_h then y=y-map_h end

	if x>=0 and y>=0 and x<map_w and y<map_h then
		material:set(x,y,v+material:get(x,y))
	end
end
function round( num )
	if num >= 0 then return math.floor(num+.5)
        else return math.ceil(num-.5) end
end
function pix_to_hex(pos,size)
	size=size or 1
	local cp={pos[1]/size,pos[2]/size};

	local fr={
		-2.0/3.0*cp[1],
		1.0/3.0*cp[1]+(1.0/math.sqrt(3.0))*cp[2],
		1.0/3.0*cp[1]-(1.0/math.sqrt(3.0))*cp[2]
	}

	local tri_coord={fr[1]-fr[2],fr[2]-fr[3],fr[3]-fr[1]};
	tri_coord={math.ceil(tri_coord[1]),math.ceil(tri_coord[2]),math.ceil(tri_coord[3])};

	return
			round((tri_coord[1] - tri_coord[3])/3.0),
			round((tri_coord[2] - tri_coord[1])/3.0),
			round((tri_coord[3] - tri_coord[2])/3.0)
end
function hex_to_array( hx,hy )
	return hx+math.floor(hy/2)+map_w/2,hy+map_h/2
end
function pixel_to_axial_hex( x,y )
 	local temp = math.floor(x + math.sqrt(3) * y + 1);
	local rx = math.floor((math.floor(2*x+1) + temp) / 3);
	local ry = math.floor((temp + math.floor(-x + math.sqrt(3) * y + 1))/3);
	return rx,ry;
end
function pixel_to_hex( x,y )
	local tx,ty=pixel_to_axial_hex(x,y)
	--ty=ty+math.floor(tx/2)
	return tx,ty
end
function hex_distance( x,y,q,r )
	return (math.abs(x-q)+math.abs(x+y-q-r)+math.abs(y-r))/2
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Crystals")
	local s=STATE.size
	draw_config(config)
	if imgui.Button("test_tex") then
		-- [[
		for j=0,map_h-1 do
			for i=0,map_w-1 do
				img_buf:set(i,j,{j*255/map_h,i*255/map_w,0,0})
			end
		end
		--]]
		write_img()
	end
	if imgui.Button("Clear image") then
		--clear_screen(true)
		for j=0,map_h-1 do
			for i=0,map_w-1 do
				material:set(i,j,0)
				img_buf:set(i,j,{0,0,0,0})
			end
		end
		for i=1,5 do
			img_buf:set(math.random(0,map_w-1),math.random(0,map_h-1),{255,255,255,255})
		end
		write_mat()
		write_img()
	end
	imgui.SameLine()
	if imgui.Button("Save") then
		need_save=true
	end
	imgui.End()
	if config.simulate then
		--config.simulate=false
		if config.add_mat >0 then
			mat_tex1:use(0)
			material:read_texture(mat_tex1)
			-- [[ center rect

			local cx,cy,cz=pix_to_hex({0,0})
			--cx,cy=hex_to_array(cx,cy)
			local dist=math.min(math.floor(map_w/15),math.floor(map_h/15))
			--print(cx,cy,cz)
			-- [==[
			add_mat(cx,cy,config.add_mat) --0,0,0

			--[[add_mat(cx+1,cy,config.add_mat)
			add_mat(cx-1,cy,config.add_mat)
			add_mat(cx,cy+1,config.add_mat)
			add_mat(cx,cy-1,config.add_mat)
			]]
			--add_mat(cx-1,cy+1,config.add_mat)
			--add_mat(cx+1,cy-1,config.add_mat)

			--add_mat(cx,cy-1,config.add_mat)
			--add_mat(cx,cy+1,config.add_mat)
			--add_mat(cx-1,cy,config.add_mat)
			--add_mat(cx+1,cy,config.add_mat)

			--add_mat(cx-1,cy-1,config.add_mat)
			--add_mat(cx,cy+1,config.add_mat)
			--add_mat(cx+1,cy,config.add_mat) --  1,0,-1   1/2
			--add_mat(cx,cy+1,config.add_mat) --  0,1,-1   1/2
			--add_mat(cx+1,cy+1,config.add_mat)-- 1,1,-2   4/2

			--add_mat(cx-1,cy,config.add_mat) -- -1,0,1	 1/2
			--add_mat(cx-1,cy-1,config.add_mat) -- -1,-1,2 4/2
			--add_mat(cx,cy-1,config.add_mat)  -- 0,-1,1   1/2
			--]==]
			--[[
			for x=cx-dist*2,cx+dist*2 do
			for y=cy-dist*2,cy+dist*2 do
			--for z=cz-dist,cz+dist do
				if math.ceil(hex_distance(x,y,cx,cy))<dist then
				--local tx,ty=pixel_to_axial_hex(x,y)
					add_mat(x,y,config.add_mat)
				end
			--end
			end
			end
			--]]
			--[[
			for x=0,map_w-1 do
				local tx,ty=pixel_to_axial_hex(x,0)
				add_mat(tx,ty,config.add_mat)
				tx,ty=pixel_to_axial_hex(x,map_h-1)
				add_mat(tx,ty,config.add_mat)
			end
			for y=0,map_h-1 do
				local tx,ty=pixel_to_axial_hex(0,y)
				add_mat(tx,ty,config.add_mat)
				tx,ty=pixel_to_axial_hex(map_w-1,y)
				add_mat(tx,ty,config.add_mat)
			end
			--]]
			material:write_texture(mat_tex1)
		end
		-- [[
		diffuse_and_decay(mat_tex1,mat_tex2,map_w,map_h,0.5,config.decay,config.diffuse_steps,img_tex1)
		if(config.diffuse_steps%2==1) then
			local c=mat_tex1
			mat_tex1=mat_tex2
			mat_tex2=c
	    end
	    crystal_step()
	    --]]
	end
	draw()
	if need_save then
		save_img()
		need_save=false
	end
end