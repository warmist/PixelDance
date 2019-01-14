-- https://twitter.com/lorenschmidt/status/1084092188345204736
require "common"
require "colors"
local luv=require "colors_luv"

local win_w=1024--2560
local win_h=1024--1440
__set_window_size(win_w,win_h)
local aspect_ratio=win_w/win_h
local size=STATE.size
local max_palette_size=50

local need_clear=false
local oversample=0.5


function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
end
function make_visits_texture()
	if visit_tex==nil or visit_tex.w~=size[1]*oversample or visit_tex.h~=size[2]*oversample then
		print("making tex")
		visit_tex={t=textures:Make(),w=size[1]*oversample,h=size[2]*oversample}
		visit_tex.t:use(0,1)
		visit_tex.t:set(size[1]*oversample,size[2]*oversample,2)
	end
end
function make_visits_buf(  )
	if visit_buf==nil or visit_buf.w~=size[1]*oversample or visit_buf.h~=size[2]*oversample then
		visit_buf=make_float_buffer(size[1]*oversample,size[2]*oversample)
	end
end
function make_variation_buf(  )
	local undersample=8
	local w=math.floor(size[1]/undersample)
	local h=math.floor(size[2]/undersample)
	if variation_buf==nil or variation_buf.w~=w or variation_buf.h~=h then
		variation_buf=make_float_buffer(w,h)
	end
end
function print_arr( array ,w,h)
	local str=""
	for i=1,w*h do
		str=str..string.format(" % 3d",array[i])
		if i%w==0 then
			print(str)
			str=""
		end
	end
end

transforms=nil
transforms=transforms or {
	min=-8,
	max=8,
	max_values=400,
	array={
	 1,-1, 1,
	 1, 0,-1,
	-1,-1, 1,
	},
	undo_steps={},
	lookup=function( self,dl,dr )
		if dl>self.max then dl=self.max end
		if dl<self.min then dl=self.min end

		if dr>self.max then dr=self.max end
		if dr<self.min then dr=self.min end
		local size=self.max-self.min+1

		dl=dl-self.min
		dr=dr-self.min
		local idx=dl+dr*size+1
		if self.array[idx]==nil then
			print("NIL With:",dl,dr,idx)
		end
		return self.array[idx]
	end,
	randomize=function ( self )
		table.insert(self.undo_steps,self.array)
		self.array={}
		local size=self.max-self.min+1
		for i=1,size*size do
			--float version
			--self.array[i]=math.random()*(self.max-self.min)+self.min
			--int version
			self.array[i]=math.random(self.min,self.max)

		end
		for x=1,size do
			for y=x+1,size do
				local idx=(y-1)+(x-1)*size+1
				local idx2=(x-1)+(y-1)*size+1
				print(idx,idx2)
				self.array[idx]=self.array[idx2]
			end
		end
		print_arr(self.array,size,size)
	end,
	mutate=function ( self ,count)
		table.insert(self.undo_steps,self.array)
		local new_array={}
		for i=1,#self.array do
			new_array[i]=self.array[i]
		end
		self.array=new_array
		local size=self.max-self.min+1
		for i=1,count do
			local idx=math.random(1,#self.array)
			self.array[idx]=math.random(self.min,self.max)
			print(idx,self.array[idx])
		end
	end,
	undo=function ( self )
		if #self.undo_steps>0 then
			self.array=self.undo_steps[#self.undo_steps]
			table.remove(self.undo_steps,#self.undo_steps)
		end
	end,
	ensure_valid=function ( self )
		local size=self.max-self.min+1
		local arr_size=size*size
		if #self.array<arr_size then
			print("Mismatch:",#self.array,arr_size)
			self.array={}
			for i=1,arr_size do
				self.array[i]=0
			end
		end
	end
}
--[[for i,v in ipairs(transforms.array) do
	print(i,v)
end]]

transforms:ensure_valid()
print_arr(transforms.array,transforms.max-transforms.min+1,transforms.max-transforms.min+1)
transforms.max_values=80
config=make_config({
	{"draw",true,type="boolean"},
	{"tick",true,type="boolean"},
	{"mutate_count",1,type="int",min=1,max=25},
	{"animation",0,type="float",min=0,max=1},
},config)

local log_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec4 palette[50];
uniform int palette_size;

uniform vec2 min_max;
uniform sampler2D tex_main;

vec4 mix_palette2(float value )
{
	if (palette_size==0)
		return vec4(0);
	value=clamp(value,0,1);
	float tg=value*(float(palette_size)-1); //[0,1]-->[0,#colors]
	float tl=floor(tg);

	float t=tg-tl;
	vec4 c1=palette[int(tl)];
	int hidx=min(int(ceil(tg)),palette_size-1);
	vec4 c2=palette[hidx];
	return mix(c1,c2,t);
}

void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float nv=texture(tex_main,normed).x;
	vec2 lmm=min_max;
	/*
	float left=textureOffset(tex_main,normed,ivec2(-1,0)).x;
	float right=textureOffset(tex_main,normed,ivec2(1,0)).x;
	nv-=(right+left)/2;
	*/
	nv=(nv-lmm.x)/(lmm.y-lmm.x);

	//nv=floor(nv*50)/50; //stylistic quantization
	nv=clamp(nv,0,1);
	color = mix_palette2(nv);
}
]==]

local need_save
function draw_visits(  )
	local lmax=0
	local lmin=math.huge
	make_visits_texture()
	make_visits_buf()

	--[[
	visit_tex.t:use(0,1)
	visit_buf:read_texture(visit_tex.t)
	for x=0,visit_buf.w-1 do
	for y=0,visit_buf.h-1 do
		local v=visit_buf:get(x,y)
		if lmax<v then lmax=v end
		if lmin>v then lmin=v end

	end
	end
	lmax=lmax
	lmin=lmin
	--]]
	log_shader:use()
	visit_tex.t:use(0)
	--visits:write_texture(visit_tex)

	set_shader_palette(log_shader)
	log_shader:set("min_max",-transforms.max_values,transforms.max_values)
	log_shader:set_i("tex_main",0)
	log_shader:draw_quad()
	if need_save then
		save_img()
		need_save=nil
	end
end

palette=palette or {show=false,
current_gen=1,
colors_input={{1,0,0,1,0},{0,0,0,1,math.floor(max_palette_size*0.5)},{0,0.7,0.7,1,max_palette_size-1}}}
function update_palette_img(  )
	if palette_img.w~=#palette.colors_input then
		palette_img=make_flt_buffer(#palette.colors_input,1)
	end
	for i,v in ipairs(palette.colors_input) do
		palette_img:set(i-1,0,v)
	end
end
function mix_color(c1,c2,v)
	local c1_v=c1[5]
	local c2_v=c2[5]
	local c_v=c2_v-c1_v
	local my_v=v-c1_v
	local local_v=my_v/c_v

	local ret={}
	for i=1,4 do
		ret[i]=(c2[i]-c1[i])*local_v+c1[i]
	end
	return ret
end
function set_shader_palette(s)
	s:set_i("palette_size",max_palette_size)
	local cur_color=2
	for i=0,max_palette_size-1 do
		if palette.colors_input[cur_color][5] < i then
			cur_color=cur_color+1
		end
		local c=mix_color(palette.colors_input[cur_color-1],palette.colors_input[cur_color],i)

		s:set(string.format("palette[%d]",i),c[1],c[2],c[3],c[4])
	end
end
function iterate_color(tbl, hsl1,hsl2,steps )
	local hd=hsl2[1]-hsl1[1]
	local sd=hsl2[2]-hsl1[2]
	local ld=hsl2[3]-hsl1[3]

	for i=0,steps-1 do
		local v=i/steps
		local r=luv.hsluv_to_rgb{(hsl1[1]+hd*v)*360,(hsl1[2]+sd*v)*100,(hsl1[3]+ld*v)*100}
		--local r=luv.hpluv_to_rgb{(hsl1[1]+hd*v)*360,(hsl1[2]+sd*v)*100,(hsl1[3]+ld*v)*100}
		r[4]=1
		r[5]=table.insert(tbl,r)
	end
end
function rand_range( t )
	return math.random()*(t[2]-t[1])+t[1]
end
function new_color( h,s,l,pos )
	local r=luv.hsluv_to_rgb{(h)*360,(s)*100,(l)*100}
	r[4]=1
	r[5]=pos
	return r
end
palette.generators={
	{"random",function (ret, hue_range,sat_range,lit_range )
		local count=math.random(2,10)
		for i=1,count do
			local nh,ns,nl
			nh=rand_range(hue_range)
			ns=rand_range(sat_range)
			nl=rand_range(lit_range)
			local pos=math.floor(((i-1)/(count-1))*(max_palette_size-1))
			local r=new_color(nh,ns,nl,pos)

			r[4]=1
			if i==count then
				r[5]=max_palette_size-1
			end
			table.insert(ret,r)
		end

	end
	},{"shades",function(ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)

		local r1=new_color(h1,s,l,0)
		local r2=new_color(h1,s2,l2,max_palette_size-1)

		table.insert(ret,r1)
		table.insert(ret,r2)
	end,
	},{"complementary",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)
		local r1=luv.hsluv_to_rgb{(h1)*360,(s)*100,(l)*100}
		r1[4]=1
		local r2=luv.hsluv_to_rgb{(1-h1)*360,(s2)*100,(l2)*100}
		r2[4]=1
		r1[5]=0
		r2[5]=max_palette_size-1
		table.insert(ret,r1)
		table.insert(ret,r2)
	end,
	},{"complementary_dark",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)
		local r1=luv.hsluv_to_rgb{(h1)*360,(s)*100,(l)*100}
		r1[4]=1
		local r2=luv.hsluv_to_rgb{(1-h1)*360,(s2)*100,(l2)*100}
		r2[4]=1
		r1[5]=0
		r2[5]=max_palette_size-1
		table.insert(ret,r1)
		table.insert(ret,{0,0,0,1,math.floor(max_palette_size/2)})
		table.insert(ret,r2)
	end,
	},{"triadic",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)
		local s3=rand_range(sat_range)
		local l3=rand_range(lit_range)
		local h2=math.fmod(h1+0.33,1)
		local h3=math.fmod(h1+0.66,1)

		table.insert(ret,new_color(h1,s,l,0))
		table.insert(ret,new_color(h2,s2,l2,math.floor(max_palette_size/2)))
		table.insert(ret,new_color(h3,s3,l3,max_palette_size-1))
	end,
	},{"compound",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)

		local s2=rand_range(sat_range)
		local l2=rand_range(lit_range)
		local s3=rand_range(sat_range)
		local l3=rand_range(lit_range)
		local d=math.random()*0.3
		local h2=math.fmod(h1+0.5-d,1)
		local h3=math.fmod(h1+0.5+d,1)

		table.insert(ret,new_color(h1,s,l,0))
		table.insert(ret,new_color(h2,s2,l2,math.floor(max_palette_size/2)))
		table.insert(ret,new_color(h3,s3,l3,max_palette_size-1))
	end,
	},{"anologous",function (ret, hue_range,sat_range,lit_range )
		local h1=rand_range(hue_range)
		local s=rand_range(sat_range)
		local l=rand_range(lit_range)
		local hue_step=0.05
		local max_step=3
		for i=0,max_step do
			local h2=math.fmod(h1+hue_step*i,1)
			local s2=s+math.random()*0.4-0.2
			if s2>1 then s2=1 end
			if s2<0 then s2=0 end
			local l2=l+math.random()*0.4-0.2
			if l2>1 then l2=1 end
			if l2<0 then l2=0 end

			table.insert(ret,new_color(h2,s2,l2,((i)/max_step)*(max_palette_size-1)))
		end
	end}
}
function gen_palette( )
	local ret={}
	palette.colors_input=ret
	local hue_range={0,1}
	local sat_range={0,1}
	local lit_range={0,1}

	local h1=rand_range(hue_range)
	local s=rand_range(sat_range)
	local l=rand_range(lit_range)
	
	local function gen_shades(tbl, h_start,s_start,l_start,l_end,count)
		local diff=l_end-l_start
		for i=0,count-1 do
			table.insert(tbl,luv.hsluv_to_rgb({h_start,s_start,l_start+diff*(i/(count-1))}))
		end
	end
	palette.generators[palette.current_gen][2](ret,hue_range,sat_range,lit_range)
end
function palette_chooser()
	if imgui.RadioButton("Show palette",palette.show) then
		palette.show=not palette.show
	end
	imgui.SameLine()
	if imgui.Button("Randomize") then
		gen_palette()
	end
	imgui.SameLine()
	local generators={
	}
	for k,v in ipairs(palette.generators) do
		table.insert(generators,v[1])
	end
	local changing = false
	changing,palette.current_gen=imgui.Combo("Generator",palette.current_gen-1,generators)
	palette.current_gen=palette.current_gen+1
	if palette.colors_input[palette.current]==nil then
		palette.current=1
	end
	palette.current=palette.current or 1

	if palette.show then
		if #palette.colors_input>0 then
			_,palette.current=imgui.SliderInt("Color id",palette.current,1,#palette.colors_input)
		end
		imgui.SameLine()
		if #palette.colors_input<max_palette_size then
			if imgui.Button("Add") then
				table.insert(palette.colors_input,{0,0,0,1})
				if palette.current<1 then
					palette.current=1
				end
			end
		end
		if #palette.colors_input>0 then
			imgui.SameLine()
			if imgui.Button("Remove") then
				table.remove(palette.colors_input,palette.current)
				palette.current=1
			end
			if imgui.Button("Print") then
				for i,v in ipairs(palette.colors_input) do
					print(string.format("#%02X%02X%02X%02X  %d",math.floor(v[1]*255),math.floor(v[2]*255),math.floor(v[3]*255),math.floor(v[4]*255),v[5]))
				end
			end
		end
		if #palette.colors_input>0 then
			local cur_v=palette.colors_input[palette.current]
			local new_col,ne_pos
			_,new_col=imgui.ColorEdit4("Current color",cur_v,true)
			_,new_pos=imgui.SliderInt("Color place",cur_v[5],0,max_palette_size-1)
			if palette.current==1 then
				new_pos=0
			elseif palette.current==#palette.colors_input then
				new_pos=max_palette_size-1
			end
			for i=1,4 do
				cur_v[i]=new_col[i]
			end
			cur_v[5]=new_pos
		end
	end
end
function palette_serialize(  )
	local ret="palette={show=false,current_gen=%d,colors_input={%s}}\n"
	local pal=""
	for i,v in ipairs(palette.colors_input) do
		pal=pal..string.format("{%f,%f,%f,%f,%d},",v[1],v[2],v[3],v[4],v[5])
	end
	return string.format(ret,palette.current_gen,pal)
end
function transforms_serialize(  )
	local ret="transforms.min=%d;transforms.max=%d;transforms.max_values=%d\n"
	local array_str="transforms.array={"
	for i=1,#transforms.array do
		if i~=1 then
			array_str=array_str..","..transforms.array[i]
		else
			array_str=array_str..transforms.array[i]
		end
	end
	array_str=array_str.."}\n"
	return string.format(ret,transforms.min,transforms.max,transforms.max_values)..array_str
end
function save_img()
	img_buf=make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	config_serial=config_serial..transforms_serialize()
	config_serial=config_serial..palette_serialize()
	img_buf:read_frame()
	img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
end

function gui()
	imgui.Begin("IFS play")
	palette_chooser()
	draw_config(config)
	local s=STATE.size
	if imgui.Button("Clear image") then
		need_clear=true
	end
	imgui.SameLine()
	if imgui.Button("Rnd image") then
		need_clear="rnd"
	end
	imgui.SameLine()
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.SameLine()
	if imgui.Button("Randomize Rules") then
		transforms:randomize()
	end
	imgui.SameLine()

	if imgui.Button("Mutate") then
		transforms:mutate(config.mutate_count)
	end
	imgui.SameLine()
	if imgui.Button("Undo") then
		transforms:undo()
	end
	imgui.End()
end
function update( )
	gui()
	update_real()
end

function gl_mod( x,y )
	return x-y*math.floor(x/y)
end


function mod(a,b)
	local r=math.fmod(a,b)
	if r<0 then
		return r+b
	else
		return r
    end
end
function clip( nv )
	if nv>transforms.max_values then
		--nv=0
		--nv=-transforms.max_values
		nv=nv-transforms.max_values
	end
	if nv<-transforms.max_values then
		--nv=0
		--nv=transforms.max_values
		nv=nv+transforms.max_values
	end
	return nv
end
function visit_iter(  )
	local w=visit_buf.w
	local h=visit_buf.h
	
	if need_clear then
		if need_clear~="rnd" then
			for y=0,h-1 do
			for x=0,w-1 do
				visit_buf:set(x,y,0)--math.random()*transforms.max_values*2- transforms.max_values)
			end
			end
			visit_buf:set(math.floor(w/2),0,transforms.max_values)
		else
			for y=0,h-1 do
			for x=0,w-1 do
				visit_buf:set(x,y,0)--math.random()*transforms.max_values*2- transforms.max_values)
			end
			end
			local cur_value=math.random()*transforms.max_values*2- transforms.max_values

			for x=0,w-1 do
				cur_value=cur_value+math.random()*(transforms.max-transforms.min)+transforms.min
				cur_value=clip(cur_value)
				visit_buf:set(x,0,cur_value)
			end
		end
		need_clear=false
	else
		for x=0,w-1 do
		for y=h-1,1,-1 do
			local v=visit_buf:get(x,y-1)
			visit_buf:set(x,y,v)
		end
		end
		local y=0
		for x=0,w-1 do
			local l
			if x>0 then
				l=visit_buf:get(x-1,y+1)
			else
				l=visit_buf:get(w-1,y+1)
			end

			local r
			if x<w-1 then
				r=visit_buf:get(x+1,y+1)
			else
				r=visit_buf:get(0,y+1)
			end

			local c=visit_buf:get(x,y+1)
			local dl=math.floor(l-c)
			local dr=math.floor(r-c)
			local nv=c+transforms:lookup(dl,dr)
			nv=clip(nv)
			visit_buf:set(x,y,nv)

		end
	end
	visit_buf:write_texture(visit_tex.t)
end
function update_real(  )
	__no_redraw()

	__clear()
	if config.draw then
		draw_visits()
	end

	if config.tick then
		visit_iter()
	end
end