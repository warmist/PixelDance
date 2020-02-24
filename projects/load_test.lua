
require "common"
local luv=require "colors_luv"
local size=STATE.size
local image_buf=load_png("glazed3.png")

measures=make_float_buffer(800,1)

config=make_config({
	{"cutoff",0,type="float"},
	{"level",0.2,type="float",min=0,max=10},
	{"show_df",false,type="boolean"},
	{"show_grad",false,type="boolean"},
},config)

local main_shader=shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;
uniform float cutoff;

uniform sampler2D tex_main;
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 c=texture(tex_main,normed*vec2(1,-1));
	float v=c.r*0.2126+0.7152*c.g+0.0722*c.b;
	//v=step(v,cutoff);
	color = c;//vec4(v,v,v,1);//vec4(0.2,0,0,1);
}
]]
local df_shader = shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;
uniform float level;

uniform sampler2D tex_main;
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 c=texture(tex_main,normed*vec2(1,-1));

	//float v=clamp(c.r,0,1);
	float v=sqrt(c.r)/level;
	v=smoothstep(0,v,1.5)-smoothstep(0,v,0.5);
	color = vec4(v,v,v,1);//vec4(0.2,0,0,1);
}
]]
local grad_shader = shaders.Make[[
#version 330

out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 c=texture(tex_main,normed*vec2(1,-1));
	float l=length(c.rg)/100;
	c.rg*=1/l;
	color = vec4(c.r,c.g,l,1);
}
]]
local con_tex=textures.Make()
local df_tex=textures.Make()
local grad_tex=textures.Make()
--from http://cs.brown.edu/people/pfelzens/dt/
function square( v )
	return v*v
end
local inf=1e20
function calc_dt1d( f ,n)
	local d={}
	local v={}
	local z={}
	local k=0
	v[0]=0
	z[0]=-inf
	z[1]=inf
	for q=1,n-1 do
		local s=((f[q]+square(q))-(f[v[k]]+square(v[k])))/(2*q-2*v[k])
		while s<=z[k] do
			k=k-1
			s  = ((f[q]+square(q))-(f[v[k]]+square(v[k])))/(2*q-2*v[k])
		end
		k=k+1
		v[k]=q
		z[k]=s
		z[k+1]=inf
	end
	k=0
	for q=0,n-1 do
		while z[k+1]<q do
			k=k+1
		end
		d[q]=square(q-v[k])+f[v[k]]
	end
	for i=0,n-1 do
		f[i]=d[i]
	end
end

function calc_dt2d( buf )
	local w=buf.w
	local h=buf.h
	if temp_col==nil or temp_col.w<math.max(w,h) then
		temp_col=make_float_buffer(math.max(w,h),1)
	end
	local f=temp_col
  	-- transform along columns
  	for x=0,w-1 do
  		for y=0,h-1 do
  			f[y]=buf:get(x,y)
  		end
  		calc_dt1d(f,h)
  		for y=0,h-1 do
  			buf:set(x,y,f[y])
  		end
  	end
	-- transform along rows
	for y=0,h-1 do
		for x=0,w-1 do
			f[x]=buf:get(x,y)
		end
		calc_dt1d(f,w)
		for x=0,w-1 do
			buf:set(x,y,f[x])
		end
	end
end
function calc_distance_field(img,cutoff)
	local w=img.w
	local h=img.h
	if dist_field==nil or dist_field.w~=w or dist_field.h~=h then
		dist_field=make_float_buffer(w,h)
	end

	for y=0,h-1 do
		for x=0,w-1 do
			local c=img:get(x,y)
			local v=0.2126*c.r/255+0.7152*c.g/255+0.0722*c.b/255;
			if v>1 then v=1 end
			if 1-v<1-cutoff then
				dist_field:set(x,y,0)
			else
				dist_field:set(x,y,inf)
			end
		end
	end
	calc_dt2d(dist_field)
end
function dist_field_to_gradient(buf)
	local w=buf.w
	local h=buf.h
	if grad_field==nil or grad_field.w~=w or grad_field.h~=h then
		grad_field=make_flt_half_buffer(w,h)
	end
	for x=0,w-1 do
		grad_field:set(x,0,{buf:get(x,0),0})
		grad_field:set(x,h-1,{buf:get(x,h-1),0})
	end
	for y=0,h-1 do
		grad_field:set(0,y,{buf:get(0,y),0})
		grad_field:set(w-1,y,{buf:get(w-1,y),0})
	end
	for x=1,w-2 do
		for y=1,h-2 do
			local dx=-buf:get(x-1,y)+buf:get(x+1,y)
			local dy=-buf:get(x,y-1)+buf:get(x,y+1)

			grad_field:set(x,y,{dx,dy})
		end
	end
end
function update_measures( buf )
	local channel=2
	for i=0,measures.w-1 do
		measures:set(i,0,0)
	end
	local skip_x=math.floor(buf.w*0.2)
	local end_x=math.floor(buf.w*0.8)
	local sy=math.floor(buf.h/2)
	local ey=math.floor(buf.h-1)
	for x=skip_x,end_x do
		for y=sy,ey do
			local c=buf:get(x,y)
			local hs=luv.rgb_to_hsluv({c.r/255,c.g/255,c.b/255})
			local v=hs[channel]--0.2126*c.r/255+0.7152*c.g/255+0.0722*c.b/255;
			--local mx=math.floor(((y-sy)/(ey-sy))*measures.w)
			local mx=y
			measures:set(mx,0,measures:get(mx,0)+v)
			--measures:set(y,0,measures:get(y,0)+v)
		end
		for y=sy,0,-1 do
			local c=buf:get(x,y)
			local hs=luv.rgb_to_hsluv({c.r/255,c.g/255,c.b/255})
			local v=hs[channel]--0.2126*c.r/255+0.7152*c.g/255+0.0722*c.b/255;

			local mx=buf.h-y-1
			measures:set(mx,0,measures:get(mx,0)+v)
		end
	end
	local f=io.open("out.txt","w")
	for i=0,measures.w-1 do
		measures:set(i,0,measures:get(i,0)/(2*(end_x-skip_x)))
		f:write(string.format("%d %g\n",i,measures:get(i,0)))
	end
	f:close()
end
function gradient_to_dist_field( buf )
	local w=buf.w
	local h=buf.h
	if dist_field==nil or dist_field.w~=w or dist_field.h~=h then
		dist_field=make_float_buffer(w,h)
	end
	for x=0,w-1 do
		dist_field:set(x,0,buf:get(x,0))
		dist_field:set(x,h-1,buf:get(x,h-1))
	end
	for y=0,h-1 do
		dist_field:set(0,y,buf:get(0,y))
		dist_field:set(w-1,y,buf:get(w-1,y))
	end
	for x=1,w-2 do
		for y=1,h-2 do
			local dx=-buf:get(x-1,y)+buf:get(x+1,y)
			local dy=-buf:get(x,y-1)+buf:get(x,y+1)

			grad_field:set(x,y,{dx,dy})
		end
	end
end
function update(  )
	__no_redraw()
	__clear()
	imgui.Begin("Image")
	draw_config(config)
	if imgui.Button("Calc df") then
		--calc_distance_field(knock_buf,config.cutoff)
		--dist_field_to_gradient(dist_field)
		--config.show_df=true
		update_measures(image_buf)
		print(image_buf.w)
	end
	imgui.PlotLines("Lines",measures.d,measures.w)
	imgui.End()

	
	if config.show_df then
		df_shader:use()
		df_tex:use(0)
		dist_field:write_texture(df_tex)
		df_shader:set_i("tex_main",0)
		df_shader:set("level",config.level)
		df_shader:draw_quad()
	elseif config.show_grad then
		grad_shader:use()
		grad_tex:use(0)
		grad_field:write_texture(grad_tex)
		grad_shader:set_i("tex_main",0)
		grad_shader:draw_quad()
	else
		main_shader:use()
		con_tex:use(0)
		image_buf:write_texture(con_tex)
		main_shader:set_i("tex_main",0)
		main_shader:set("cutoff",config.cutoff)
		main_shader:draw_quad()
	end
	
end