
require "common"
require "colors"
local luv=require "colors_luv"
--local size_mult=0.25
local win_w=1024--2560
local win_h=1024--1440
__set_window_size(win_w,win_h)
local aspect_ratio=win_w/win_h
local size=STATE.size
local max_palette_size=50
local sample_count=50000
local need_clear=false
local oversample=1
str_x=str_x or "s.x"
str_y=str_y or "s.y"
str_preamble=str_preamble or ""
str_postamble=str_postamble or ""
img_buf=make_image_buffer(size[1],size[2])
function resize( w,h )
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	print("new size:",w,h)
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
tick=tick or 0
config=make_config({
	{"render",true,type="boolean"},
	{"only_last",false,type="boolean"},
	{"auto_scale_color",false,type="boolean"},
	{"ticking",1,type="int",min=1,max=2},
	{"v0",-0.211,type="float",min=-5,max=5},
	{"v1",-0.184,type="float",min=-5,max=5},
	{"v2",-0.184,type="float",min=-5,max=5},
	{"v3",-0.184,type="float",min=-5,max=5},
	{"IFS_steps",10,type="int",min=1,max=100},
	{"move_dist",0.1,type="float",min=0.001,max=2},
	{"scale",1,type="float",min=0.00001,max=2},
	{"rand_angle",0,type="float",min=0,max=math.pi*2},
	{"rand_dist",0.01,type="float",min=0.00001,max=1},
	{"cx",0,type="float",min=-10,max=10},
	{"cy",0,type="float",min=-10,max=10},
	{"min_value",0,type="float",min=0,max=20},
	{"gen_radius",1,type="float",min=0,max=10},
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
uniform sampler2D tex_palette;
uniform int auto_scale_color;

vec4 mix_palette(float value )
{
	if (palette_size==0)
		return vec4(0);

	//value=clamp(value,0,1);
	return texture(tex_palette,vec2(value,0));
}
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
vec2 local_minmax(vec2 pos)
{
	float nv=texture(tex_main,pos).x;
	float min=nv;
	float max=nv;
	float avg=0;
	float wsum=0;
	for(int i=0;i<50;i++)
		for(int j=0;j<50;j++)
		{
			vec2 delta=vec2(float(i-25)/1024,float(j-25)/1024);
			float dist=length(delta);
			float v=texture(tex_main,pos+delta).x;
			if(max<v)max=v;
			if(min>v)min=v;
			avg+=v*(1/(dist*dist+1));
			wsum+=(1/(dist*dist+1));
		}
	avg/=wsum;
	return vec2(log(avg/10+1),log(avg*10+1));
}
float mean_tex(vec2 pos)
{
	float ret=0;

	ret+=textureOffset(tex_main,pos,ivec2(0,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(0,1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,0)).x;
	ret+=textureOffset(tex_main,pos,ivec2(0,-1)).x;

	ret+=textureOffset(tex_main,pos,ivec2(1,1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(1,-1)).x;
	ret+=textureOffset(tex_main,pos,ivec2(-1,1)).x;


	return ret/9;
}
#define DX(xoff,yoff) {float n=meant-textureOffset(tex_main,pos,ivec2(xoff,yoff)).x;ret+=n*n;}
float var_tex(vec2 pos)
{
	float meant=mean_tex(pos);

	float ret=0;

	DX(0,0);
	DX(1,0);
	DX(-1,0);
	DX(0,1);
	DX(0,-1);

	DX(1,1);
	DX(-1,-1);
	DX(-1,1);
	DX(1,-1);

	return ret/9;
}
void main(){
	vec2 normed=(pos.xy+vec2(1,1))/2;
	float nv=texture(tex_main,normed).x;
	//float nv=mean_tex(normed);
	//float nv=var_tex(normed);
	//color = vec4(nv,0,0,1);
	
	vec2 lmm=min_max;
	//vec2 lmm=local_minmax(normed);
	if(auto_scale_color==1)
		nv=(log(nv+1)-lmm.x)/(lmm.y-lmm.x);
	else
		nv=log(nv+1)/lmm.y;
	//nv=floor(nv*8)/8; //stylistic quantization
	nv=clamp(nv,0,1);
	//nv=math.min(math.max(nv,0),1);
	//--mix(pix_out,c_u8,c_back,nv)
	//mix_palette(pix_out,nv)
	//img_buf:set(x,y,pix_out)
	color = mix_palette2(nv);
	
/*
    color.rgb = pow(color.rgb, vec3(1.0/gamma));
	color.rgb*=contrast;
	color.rgb+=vec3(brightness);
*/
}
]==]
local need_save
function draw_visits(  )
	local lmax=0
	local lmin=math.huge
	make_visits_texture()
	make_visits_buf()
	visit_tex.t:use(0,1)
	visit_buf:read_texture(visit_tex.t)
	for x=0,visit_buf.w-1 do
	for y=0,visit_buf.h-1 do
		local v=visit_buf:get(x,y)
		if v>math.exp(config.min_value)-1 then --skip non-visited tiles
			if lmax<v then lmax=v end
			if lmin>v then lmin=v end
		end
	end
	end
	lmax=math.log(lmax+1)
	lmin=math.log(lmin+1)
	log_shader:use()
	visit_tex.t:use(0,1)
	--visits:write_texture(visit_tex)

	set_shader_palette(log_shader)
	log_shader:set("min_max",lmin,lmax)
	log_shader:set_i("tex_main",0)
	local auto_scale=0
	if config.auto_scale_color then auto_scale=1 end
	log_shader:set_i("auto_scale_color",auto_scale)
	log_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
end

function clear_buffers(  )
	need_clear=true
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
		r[5]=
		table.insert(tbl,r)
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

function save_img(tile_count)
	if tile_count==1 then

		local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
		for k,v in pairs(config) do
			if type(v)~="table" then
				config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
			end
		end
		config_serial=config_serial..string.format("str_x=%q\n",str_x)
		config_serial=config_serial..string.format("str_y=%q\n",str_y)
		config_serial=config_serial..string.format("str_preamble=%q\n",str_preamble)
		config_serial=config_serial..string.format("str_postamble=%q\n",str_postamble)
		img_buf:read_frame()
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	else
		img_buf:read_frame()
		local w=img_buf.w
		local h=img_buf.h
		local tile_image=make_image_buffer(w*tile_count,h*tile_count)
		for x=0,(w-1)*tile_count do
		for y=0,(h-1)*tile_count do
			local tx,ty=coord_mapping(x-w*tile_count/2+w/2,y-h*tile_count/2+h/2)
			tx=math.floor(tx)
			ty=math.floor(ty)
			if tx>=0 and math.floor(tx)<w and ty>=0 and math.floor(ty)<h then
				tile_image:set(x,y,img_buf:get(tx,ty))
			end
		end
		end
		tile_image:save(string.format("tiled_%d.png",os.time(os.date("!*t"))),config_serial)
	end
end

local terminal_symbols={["s.x"]=5,["s.y"]=5,["p.x"]=3,["p.y"]=3,["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,["normed_i"]=2}
local terminal_symbols_alt={["p.x"]=3,["p.y"]=3}
local terminal_symbols_param={["s.x"]=5,["s.y"]=5,["params.x"]=1,["params.y"]=1,["params.z"]=1,["params.w"]=1,["normed_i"]=2}
local normal_symbols={["max(R,R)"]=0.05,["min(R,R)"]=0.05,["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,["abs(R)"]=0.1,["sqrt(R)"]=0.1,["exp(R)"]=0.01,["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,["tan(R)"]=1,["sin(R)"]=1,["cos(R)"]=1,["log(R)"]=1,["(R)/(R)"]=8,["(R)*(R)"]=16,["(R)-(R)"]=60,["(R)+(R)"]=60}

function normalize( tbl )
	local sum=0
	for i,v in pairs(tbl) do
		sum=sum+v
	end
	for i,v in pairs(tbl) do
		tbl[i]=tbl[i]/sum
	end
end
normalize(terminal_symbols)
normalize(terminal_symbols_alt)
normalize(terminal_symbols_param)
normalize(normal_symbols)
function rand_weighted(tbl)
	local r=math.random()
	local sum=0
	for i,v in pairs(tbl) do
		sum=sum+v
		if sum>= r then
			return i
		end
	end
end
function replace_random( s,substr,rep )
	local num_match=0
	local function count(  )
		num_match=num_match+1
		return false
	end
	string.gsub(s,substr,count)
	print("input:",s," found:",count)
	num_rep=math.random(0,num_match-1)
	print("replacing:",num_rep)
	function rep_one(  )
		if num_rep==0 then
			num_rep=num_rep-1
			return rep()
		else
			num_rep=num_rep-1
			return false
		end
	end
	local ret=string.gsub(s,substr,rep_one)
	print("returning:",ret)
	return ret
end
function random_math( steps,seed )
	local cur_string=seed or "R"

	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end

	for i=1,steps do
		cur_string=replace_random(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end

function random_math_fourier( steps,complications ,seed)
	local cur_string=seed or "(R)/2"
	for i=1,steps do
		cur_string=cur_string..("+(R)*sin(2*%d*M_PI*(Q)+R)"):format(i)
	end
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end
	function MQT( )
		return rand_weighted(terminal_symbols_alt)
	end

	for i=1,complications do
		cur_string=string.gsub(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"Q",MQT)
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
function random_math_power( steps,complications,seed )
	local cur_string=seed or "R"
	for i=1,steps do
		local QS=""
		for j=1,i do
			QS=QS.."*(Q)"
		end
		cur_string=cur_string..("+(R)%s"):format(QS)
	end
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols_param)
	end
	function MQT( )
		return rand_weighted(terminal_symbols_alt)
	end

	for i=1,complications do
		cur_string=string.gsub(cur_string,"R",M)
	end
	cur_string=string.gsub(cur_string,"Q",MQT)
	cur_string=string.gsub(cur_string,"R",MT)
	return cur_string
end
animate=false
function gui()
	imgui.Begin("IFS play")
	palette_chooser()
	draw_config(config)
	local s=STATE.size
	if imgui.Button("Clear image") then
		clear_buffers()
	end

	tile_count=tile_count or 1
	_,tile_count=imgui.SliderInt("Tile count",tile_count,1,8)
	if imgui.Button("Save image") then
		--this saves too much (i.e. all gui and stuff, we need to do it in correct place (or render to texture)
		--save_img(tile_count)
		need_save=tile_count
	end
	rand_complexity=rand_complexity or 3
	if imgui.Button("Rand function") then
		str_x=random_math(rand_complexity)
		str_y=random_math(rand_complexity)
		--str_x=random_math_fourier(2,rand_complexity)
		--str_y=random_math_fourier(4,rand_complexity)

		--str_x=random_math_power(3,rand_complexity)
		--str_y=random_math_power(3,rand_complexity)
		--str_x="s.x"
		--str_y="s.y"

		--str_y="-"..str_x
		--str_x=random_math(rand_complexity,"cos(R)*R")
		--str_y=random_math(rand_complexity,"sin(R)*R")
		--str_y="sin("..str_x..")"
		--str_x="cos("..str_x..")"
		--str_x=random_math_power(2,rand_complexity).."/"..random_math_power(2,rand_complexity)
		--str_y=random_math_fourier(2,rand_complexity).."/"..str_x
		str_preamble=""
		str_postamble=""
		-- [[ offset
		str_preamble=str_preamble.."s+=params.xy;"
		--]]
		--[[ normed-like
		str_preamble=str_preamble.."float l=length(s);"
		str_postamble=str_postamble.."s/=l;s*=move_dist;"
		--]]
		-- [[ normed-like2
		str_preamble=str_preamble..""
		str_postamble=str_postamble.."s/=length(s);s*=move_dist;s+=p;"
		--]]
		--[[ polar-like
		str_preamble=str_preamble.."s=to_polar(s);p=to_polar(p);"
		str_postamble=str_postamble.."s=from_polar(s);p=from_polar(p);"
		--]]
		--[[ centered-polar
		str_preamble=str_preamble.."s=to_polar(s-p);"
		str_postamble=str_postamble.."s=from_polar(s)+p;"
		--]]
		print("==============")
		print(str_preamble)
		print(str_x)
		print(str_y)
		print(str_postamble)
		make_visit_shader(true)
		need_clear=true
	end
	imgui.SameLine()

	_,rand_complexity=imgui.SliderInt("Complexity",rand_complexity,1,8)

	if imgui.Button("Animate") then
		animate=true
		need_clear=true
		config.animation=0
	end
	imgui.End()
end
function update( )
	gui()
	if config.render then
		update_real()
		--update_func()
	else
		update_func_shader()
	end
end
function mix_palette(out,input_t )
	if #palette.colors<=1 then
		return
	end
	if input_t>1 then input_t=1 end
	if input_t<0 then input_t=0 end
--[[
	local tbin=input_t*20
	bins[math.floor(tbin)]=bins[math.floor(tbin)] or 0
	bins[math.floor(tbin)]=bins[math.floor(tbin)]+1
]]
	local tg=input_t*(#palette.colors-1) -- [0,1]--> [0,#colors]
	local tl=math.floor(tg)

	local t=tg-tl
	local it=1-t
	local c1=palette.colors[tl+1]
	local c2=palette.colors[math.ceil(tg)+1]
	if c1==nil or c2==nil then
		out={0,0,0,255}
		return
	end
	--hsv mix
	if false then
		local hsv1={rgbToHsv(c1[1]*255,c1[2]*255,c1[3]*255,255)}
		local hsv2={rgbToHsv(c2[1]*255,c2[2]*255,c2[3]*255,255)}
		local hsv_out={}
		for i=1,3 do
			hsv_out[i]=hsv1[i]*it+hsv2[i]*t
		end
		local rgb_out={hsvToRgb(hsv_out[1],hsv_out[2],hsv_out[3],255)}
		out.r=rgb_out[1]
		out.g=rgb_out[2]
		out.b=rgb_out[3]
		--]]
	else
		out.r=(c1[1]*it+c2[1]*t)*255
		out.g=(c1[2]*it+c2[2]*t)*255
		out.b=(c1[3]*it+c2[3]*t)*255
	end
	out.a=(c1[4]*it+c2[4]*t)*255
end

local func_shader=shaders.Make[==[
#version 330

out vec4 color;
in vec3 pos;

uniform vec4 palette[15];
uniform int palette_size;

uniform vec4 params;
uniform vec2 center;
uniform vec2 scale;
uniform float move_dist;

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

vec2 fun(vec2 pos)
{
	float v0=params.x;
	float v1=params.y;

	float x_1=pos.x;
	float x_2=pos.x*pos.x/2;
	float x_3=pos.x*pos.x*pos.x/6;

	float y_1=pos.y;
	float y_2=pos.y*pos.y/2;
	float y_3=pos.y*pos.y*pos.y/6;

	float nx=sqrt(abs(cos(x_1-y_2)*v0+sin(y_2-x_3)*v1))-sqrt(abs(sin(x_1-y_2)*v1+cos(y_2-x_3)*v0));
	float ny=sin(y_1-x_2)*v1+cos(x_2-y_3)*v0;

	vec2 ret=vec2(nx,ny);
	float r=length(ret);
	if (r<0.0001) r=1;
	float d=move_dist/r;
	return ret*d;
}

void main(){

	vec2 tpos=(pos.xy*0.5)*scale+center*vec2(1,-1);
	vec2 np=fun(tpos);

	float nv=length(np-tpos);
	nv=mod(nv,1);
	color=mix_palette2(nv);
}
]==]
function gl_mod( x,y )
	return x-y*math.floor(x/y)
end
function update_func_shader(  )
	__no_redraw()
	__clear()
	func_shader:use()
	set_shader_palette(func_shader)
	func_shader:set_i("palette_size",#palette.colors)
	func_shader:set("params",config.v0,config.v1,config.v2,config.v3)
	func_shader:set("center",config.cx,config.cy)
	func_shader:set("scale",config.scale,config.scale*aspect_ratio)
	func_shader:set("move_dist",config.move_dist)
	func_shader:draw_quad()
	if need_save then
		save_img(tile_count)
		need_save=nil
	end
end
function auto_clear(  )
	local pos_start=0
	local pos_end=0
	for i,v in ipairs(config) do
		if v[1]=="v0" then
			pos_start=i
		end
		if v[1]=="cy" then
			pos_end=i
		end
	end
	
	for i=pos_start,pos_end do
		if config[i].changing then
			need_clear=true
			break
		end
	end
end
function mod(a,b)
	local r=math.fmod(a,b)
	if r<0 then
		return r+b
	else
		return r
    end
end

function line_visit( x0,y0,x1,y1 )
	local dx = x1 - x0;
    local dy = y1 - y0;
    if math.sqrt(dx*dx+dy*dy)>5000 then
    	return
    end
    add_visit(mod(x0,size[1]),mod(y0,size[1]),1)
    if (dx ~= 0) then
        local m = dy / dx;
        local b = y0 - m*x0;
        if x1 > x0 then
            dx = 1
        else
            dx = -1
        end
        while math.floor(x0) ~= math.floor(x1) do
            x0 = x0 + dx
            y0 = math.floor(m*x0 + b + 0.5);
            add_visit(mod(x0,size[1]),mod(y0,size[1]),1)
            --print(x0,y0)
        end

    end
end
function rand_line_visit( x0,y0,x1,y1 )
	local dx=x1-x0
	local dy=y1-y0
	local d=math.sqrt(dx*dx+dy*dy)
	dx=dx/d
	dy=dy/d
	for i=1,config.line_visits do
		local r=math.random()*d

		local tx=mod(x0+dx*r,size[1])
		local ty=mod(y0+dy*r,size[2])
		smooth_visit(tx,ty)
	end
end
function rot_coord( x,y,angle )
	local c=math.cos(angle)
	local s=math.sin(angle)
	--[[
		| c -s |
		| s  c |
	--]]
	return x*c-y*s,x*s+y*c
end
function reflect_coord( x,y,angle )
	local c=math.cos(2*angle)
	local s=math.sin(2*angle)
	--[[
		| c  s |
		| s -c |
	--]]
	return x*c+y*s,x*s-y*c
end
function barycentric( x,y,ax,ay,bx,by,cx,cy )
	local v0x=bx-ax
	local v0y=by-ay

	local v1x=cx-ax
	local v1y=cy-ay

	local v2x=x-ax
	local v2y=y-ay

	local d00=v0x*v0x+v0y*v0y
	local d01=v0x*v1x+v0y*v1y
	local d11=v1x*v1x+v1y*v1y
	local d20=v2x*v0x+v2y*v0y
	local d21=v2x*v1x+v2y*v1y

	local denom=d00*d11-d01*d01
	local v=(d11*d20-d01*d21)/denom
	local w=(d00*d21-d01*d20)/denom
	local u=1-v-w
	return v,w,u
end
function from_barycentric( v,w,u,ax,ay,bx,by,cx,cy )
	local x=v*ax+w*bx+u*cx
	local y=v*ay+w*by+u*cy
	return x,y
end
function mod_reflect( a,max )
	local ad=math.floor(a/max)
	a=mod(a,max)
	if ad%2==1 then
		a=max-a
	end
	return a
end
function to_hex_coord( x,y )
	local size=300
	local q=(math.sqrt(3)/3*x-(1/3)*y)/size
	local r=((2/3)*y)/size
	return q,r
end
function from_hex_coord( q,r )
	local size=300
	local x=(math.sqrt(3)*q+(math.sqrt(3)/2)*r)*size
	local r=((3/2)*r)*size
	return x,r
end
function round( x )
	return math.floor(x+0.5)
end
function axial_to_cube( q,r )
	return q,-q-r,r
end
function cube_to_axial(x,y,z )
	return x,z
end
function cube_round( x,y,z )
	local rx = round(x)
    local ry = round(y)
    local rz = round(z)

    local x_diff = math.abs(rx - x)
    local y_diff = math.abs(ry - y)
    local z_diff = math.abs(rz - z)

    if x_diff > y_diff and x_diff > z_diff then
        rx = -ry-rz
    elseif y_diff > z_diff then
        ry = -rx-rz
    else
        rz = -rx-ry
    end

    return rx, ry, rz
end

function coord_mapping( tx,ty )
	local s=STATE.size
	local dist=s[1]
	local angle=(2*math.pi)/3
	local sx=s[1]/2
	local sy=s[2]/2
	-- [[
	local cx,cy=tx-sx,ty-sy
	--return tx,ty
	--]]
	-- [[
	local r=math.sqrt(cx*cx+cy*cy)
	local a=math.atan2(cy,cx)

	r=mod(r,dist)
	a=mod(a,angle)
	r=r/dist
	a=a/angle
	return r*s[1],a*s[2]
	--]]
	--https://www.redblobgames.com/grids/hexagons/#pixel-to-hex
	--[=[
	cx,cy=to_hex_coord(cx,cy)
	local rx,ry,rz=axial_to_cube(cx,cy)
	local rrx,rry,rrz=cube_round(rx,ry,rz)
	rx=rx-rrx
	ry=ry-rry
	rz=rz-rrz
	--]]
	--[[if rrx%2==1 and rrz%2==1 then
		rz=-rz
		rx=-rx
	end]]
	--print(max_rz,min_rz,math.sqrt(3))
	cx,cy=cube_to_axial(rx,ry,rz)
	cx,cy=from_hex_coord(cx,cy)
	return cx+sx,cy+sy
	--[=[
	local angle=2*math.pi/3
	

	local ax,ay=math.cos(angle)*dist,math.sin(angle)*dist
	local bx,by=math.cos(2*angle)*dist,math.sin(2*angle)*dist
	local cx,cy=math.cos(3*angle)*dist,math.sin(3*angle)*dist
	local v,w,u=barycentric(tx-sx,ty-sy,ax,ay,bx,by,cx,cy)
	--print(tx,ty,v,w,u)
	if v<0 then
		w=mod(w,1)
		u=mod(u,1)
		v=mod(1-w-u,1)
	elseif u<0 then
		v=mod(v,1)
		w=mod(w,1)
		u=mod(1-v-w,1)
	else
		v=mod(v,1)
		u=mod(u,1)
		w=mod(1-v-u,1)
	end

	local nx,ny=from_barycentric(v,w,u,ax,ay,bx,by,cx,cy)
	return nx+sx,ny+sy
	--]=]
	--[=[
	local nx = tx
	local ny = ty
	nx=nx-s[1]/2
	ny=ny-s[2]/2
	local dist=200
	local angle=math.pi/6
	local dx=math.cos(angle)*dist
	local dy=math.sin(angle)*dist
	nx=nx+dx
	ny=ny+dy
	--ny=ny-s[2]/2
	nx,ny=rot_coord(nx,ny,angle)
	nx=mod(nx,dist)
	--nx,ny=rot_coord(nx,ny,-angle)
	nx=nx-dx
	ny=ny-dy

	

	--[[dx=math.cos(-angle)*dist
	dy=math.sin(-angle)*dist
	nx=nx+dx
	ny=ny+dy
	nx,ny=rot_coord(nx,ny,-angle)
	nx=mod(nx,dist)
	nx,ny=rot_coord(nx,ny,angle)
	nx=nx-dx
	ny=ny-dy

	dx=math.cos(2*angle)*dist
	dy=math.sin(2*angle)*dist
	nx=nx+dx
	ny=ny+dy
	nx,ny=rot_coord(nx,ny,2*angle)
	nx=mod(nx,dist)
	nx,ny=rot_coord(nx,ny,-2*angle)
	nx=nx-dx
	ny=ny-dy
	]]
	nx=nx+s[1]/2
	ny=ny+s[2]/2
	
	--ny=ny+s[2]/2
	return nx,ny
	--]=]
	--[=[
	
	local cx=tx-s[1]/2
	local cy=ty-s[2]/2
	local rmax=math.min(s[1],s[2])/2
	

	
	--r=math.fmod(r,math.min(s[1],s[2])/2)
	
	local num=6
	local top=math.cos(math.pi/num)
	local bottom=math.cos(a-(math.pi*2/num)*math.floor((num*a+math.pi)/(math.pi*2)))

	local dr=top/bottom
	dr=(dr*rmax)
	local d=math.floor(r/dr)
	a=a-(math.pi*2/num)*d
	r=math.fmod(r,dr)
	if d%2==1 then
		r=dr-r
	end
	local nx=math.cos(a)*r+s[1]/2
	local ny=math.sin(a)*r+s[2]/2
	return nx,ny
	--]=]
	--[=[
	local rx,ry
	if tx>s[1]/2 then
		rx,ry=rot_coord(tx-s[1]/2,ty-s[2]/2,math.pi/4)
		rx=rx+s[1]/2
		ry=ry+s[2]/2
	else
		rx,ry=tx,ty
	end
	return math.fmod(rx,s[1]),math.fmod(ry,s[2])
	--]=]
	--[[ PENTAGON
	local k = {0.809016994,0.587785252,0.726542528};
	ty=-ty;
	tx=math.abs(tx)
	local ntx=tx
	local nty=ty
	local v=2*math.min((-k[1]*ntx+k[2]*nty),0)
	ntx=ntx-v*(-k[1])
	nty=nty-v*(k[2])
	local v2=2*math.min((k[1]*ntx+k[2]*nty),0)
	ntx=ntx-v*(k[1])
	nty=nty-v*(k[2])
	return ntx,nty
	--[=[

	void t_rot(inout vec2 st,float angle)
	{
		float c=cos(angle);
		float s=sin(angle);
		mat2 m=mat2(c,-s,s,c);
		st*=m;
	}
	void t_ref(inout vec2 st,float angle)
	{
		float c=cos(2*angle);
		float s=sin(2*angle);
		mat2 m=mat2(c,s,s,-c);
		st*=m;
	}

    p -= 2.0*min(dot(vec2(-k.x,k.y),p),0.0)*vec2(-k.x,k.y);
    p -= 2.0*min(dot(vec2( k.x,k.y),p),0.0)*vec2( k.x,k.y);
    --]=]
	--]]
	--return tx,ty
	--return mod(tx,s[1]),mod(ty,s[2])
	--[[
	local div_x=math.floor(tx/s[1])
	local div_y=math.floor(ty/s[2])
	tx=mod(tx,s[1])
	ty=mod(ty,s[2])
	if div_x%2==1 then
		tx=s[1]-tx-1
	end
	if div_y%2==1 then
		ty=s[2]-ty-1
	end
	return tx,ty
	--]]
	--[[
	local div=math.floor(tx/s[1]+ty/s[2])
	tx=mod(tx,s[1])
	ty=mod(ty,s[2])
	if div>0 then
		return s[1]-ty-1,tx
	end
	return tx,ty
	--]]
end
function rand_circl(  )
	local a=math.random()*math.pi*2
	local r=math.sqrt(math.random())*config.gen_radius
	return math.cos(a)*r,math.sin(a)*r
end
knock_buf=knock_buf or load_png("knock.png")
local knock_texture
function make_visit_shader( force )
if add_visit_shader==nil or force then
	add_visit_shader=shaders.Make(
string.format([==[
#version 330
#line 870
layout(location = 0) in vec3 position;
out vec3 pos;

#define M_PI 3.1415926535897932384626433832795

uniform vec2 center;
uniform vec2 scale;
uniform int iters;
uniform int max_iters;
uniform float seed;
uniform float move_dist;
uniform vec4 params;

vec2 to_polar(vec2 p)
{
	return vec2(length(p),atan(p.y,p.x));
}
vec2 from_polar(vec2 p)
{
	return vec2(cos(p.y)*p.x,sin(p.y)*p.x);
}
vec2 func(vec2 p,int it_count)
{
	vec2 s=vec2(p.x,p.y);
	
	for(int i=0;i<it_count;i++)
		{
			float normed_i=float(i)/float(it_count);
			%s
			s=vec2(%s,%s);
			%s
		}
	return s;
}
float hash(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x)))); }
vec2 gaussian(float mean,float var,vec2 rnd)
{
    return vec2(sqrt(-2 * var * log(rnd.x)) *
            cos(2 * 3.14159265359 * rnd.y) + mean,
            sqrt(-2 * var * log(rnd.x)) *
            sin(2 * 3.14159265359 * rnd.y) + mean);
}
vec2 mapping(vec2 p)
{
	return p;
	//return mod(p+vec2(1),2)-vec2(1);

	/* polar
	float angle=(2*M_PI)/3;
	float r=length(p);
	float a=atan(p.y,p.x);
	r=mod(r,2);
	a=mod(a,angle);
	a/=angle;
	return vec2(r-1,a*2-1);
	//*/
	//spherical... needs compression in poles
	/*
	float w=2;
	float h=2;

	p+=vec2(w/2,h/2);
	float d=floor(p.y/h);
	if(mod(d,2)<1)
	{
		p.y=mod(p.y,h);
	}
	else
	{
		p.y=h-mod(p.y,h);
		p.x+=w/2;
	}
	p.x=mod(p.x,w);
	return p-vec2(w/2,h/2);
	*/
}
vec2 dfun(vec2 p,int iter,float h)
{
	vec2 x1=func(p+vec2(1,1)*h,iter);
	vec2 x2=func(p+vec2(1,-1)*h,iter);
	vec2 x3=func(p+vec2(-1,1)*h,iter);
	vec2 x4=func(p+vec2(-1,-1)*h,iter);
	
	return (x1-x2-x3+x4)/(4*h*h);

}
void main()
{
	float d=0;
	

	//float h1=hash(position.xy*seed);
	//float h2=hash(position.xy*5464+vec2(1244,234)*seed);
	//vec2 p_rnd=position.xy+gaussian(0,1,vec2(h1,h2));
	/*vec2 p_far=func(p_rnd,max_iters);
	if(d>1)
		pos.x=1;
	else
		pos.x=0;*/
	//gl_Position.xy = mapping(dfun(position.xy,iters,0.1)*scale+center);
	gl_Position.xy = mapping(func(position.xy,iters)*scale+center);
	//gl_PointSize=length(gl_Position.xy)*15+1; //vary this by preliminary visits here
	//gl_PointSize=dot(position.xy,position.xy)+1; //vary this by preliminary visits here
	gl_PointSize=2;
	gl_Position.z = 0;
    gl_Position.w = 1.0;
    pos=gl_Position.xyz;
}
]==],str_preamble,str_x,str_y,str_postamble),
[==[
#version 330
#line 1228

out vec4 color;
in vec3 pos;
uniform sampler2D img_tex;
void main(){
	//vec4 txt=texture(img_tex,mod(pos.xy*vec2(0.5,-0.5)+vec2(0.5,0.5),1));
	//float rr=clamp(1-txt.r,0,1);
	//float rr = abs(pos.x+1);
	//float rr = pos.y-0.5;
	//float rr = length(pos.xy)/1.0;
	//rr=clamp(rr,0,1);
	//float delta_size=(1-0.2)*rr+0.2;
	float delta_size=1;
	//float delta_size=txt.r;
 	float r = 2*length(gl_PointCoord - 0.5)/(delta_size);
	float a = 1 - smoothstep(0, 1, r);
	//rr=clamp((1-rr),0,1);
	//rr*=rr;
	//color=vec4(a,0,0,1);
	color=vec4(1,0,0,1);
}
]==])
end

end
make_visit_shader(true)
if samples==nil or samples.w~=sample_count then
	samples=make_flt_half_buffer(sample_count,1)
end
function math.sign(x)
   if x<0 then
     return -1
   elseif x>0 then
     return 1
   else
     return 0
   end
end
function visit_iter()
	

	make_visits_texture()
	make_visit_shader()
	add_visit_shader:use()
	if knock_texture==nil then
		knock_texture=textures:Make()
		knock_texture:use(0,1)
		knock_buf:write_texture(knock_texture)
	end
	add_visit_shader:set("center",config.cx,config.cy)
	add_visit_shader:set("scale",config.scale,config.scale*aspect_ratio)
	add_visit_shader:set("params",config.v0,config.v1,config.v2,config.v3)
	add_visit_shader:set("move_dist",config.move_dist)

	visit_tex.t:use(0)
	knock_texture:use(1)
	add_visit_shader:blend_add()
	add_visit_shader:set_i("max_iters",config.IFS_steps)
	add_visit_shader:set_i("img_tex",1)
	if not visit_tex.t:render_to(visit_tex.w,visit_tex.h) then
		error("failed to set framebuffer up")
	end
	local gen_radius=config.gen_radius

	for i=1,config.ticking do
		if need_clear then
			__clear()
			need_clear=false
			--print("Clearing")
		end
		local step=2
		
		for i=0,samples.w*samples.h-1,step do
			--[[ square
			local x=math.random()*gen_radius-gen_radius/2
			local y=math.random()*gen_radius-gen_radius/2
			--]]
			--gaussian blob with moving center
			--local x,y=gaussian2(-config.cx/config.scale,gen_radius,-config.cy/config.scale,gen_radius)
			--gaussian blob
			local x,y=gaussian2(0,gen_radius,0,gen_radius)
			--[[ n gaussian blobs
			local count=4
			local rad=1.5+gen_radius*gen_radius
			local n=math.random(0,count-1)
			local a=(n/count)*math.pi*2
			local cx=math.cos(a)*rad
			local cy=math.sin(a)*rad
			local x,y=gaussian2(cx,gen_radius,cy,gen_radius)
			--]]
			--[[ circle perimeter
			local a=math.random()*math.pi*2
			local x=math.cos(a)*gen_radius
			local y=math.sin(a)*gen_radius
			--]]

			--[[ circle area
			local a = math.random() * 2 * math.pi
			local r = gen_radius * math.sqrt(math.random())
			local x = r * math.cos(a)
			local y = r * math.sin(a)
			--]]
			--[[ spiral
			local angle_speed=500;
			local t=math.random();
			local x=math.cos(t*angle_speed)*math.sqrt(t)*gen_radius;
			local y=math.sin(t*angle_speed)*math.sqrt(t)*gen_radius;
			--]]
			-------------mods
			--[[ polar grid mod
			local r=math.sqrt(x*x+y*y)
			local a=math.atan(y,x)
			local grid_r=0.01
			local grid_a=0.01
			--r=math.floor(r/grid_r)*grid_r
			a=math.floor(a/grid_a)*grid_a

			x=math.cos(a)*r
			y=math.sin(a)*r
			--]]
			--[[ grid mod
			--local gr=math.sqrt(x*x+y*y)
			local grid_size=0.05
			x=math.floor(x/grid_size)*grid_size
			y=math.floor(y/grid_size)*grid_size
			--]]
			--[[ blur mod
			local blur_str=0.00001
			x,y=gaussian2(x,blur_str,y,blur_str)
			--]]
			--[[ circles mod
			local circle_size=0.001
			local a2 = math.random() * 2 * math.pi
			x=x+math.cos(a2)*circle_size
			y=y+math.sin(a2)*circle_size
			--]]
			local angle_off=math.atan2(y,x)
			local dx=math.cos(config.rand_angle+angle_off)*config.rand_dist
			local dy=math.sin(config.rand_angle+angle_off)*config.rand_dist
			samples.d[i]={x,y,0,0}
			if step==2 then
				
				samples.d[i+1]={x+dx,y+dy,0,0}
			end
		end

		if config.only_last then
			add_visit_shader:set("seed",math.random())
			add_visit_shader:set_i("iters",config.IFS_steps)
			add_visit_shader:draw_lines(samples.d,samples.w*samples.h,false)
		else
			for i=1,config.IFS_steps do
				add_visit_shader:set("seed",math.random())
				add_visit_shader:set_i("iters",i)
				add_visit_shader:draw_lines(samples.d,samples.w*samples.h,false)
			end
		end
	end
	add_visit_shader:blend_default()
	__render_to_window()
end

local draw_frames=100
local frame_count=500

function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function update_animation_values( )
	local a=config.animation*math.pi*2
	config.v0=math.cos(a)*1
	config.v1=math.sin(a)*2
end
function update_real(  )
	__no_redraw()
	if animate then
		tick=tick or 0
		tick=tick+1
		if tick%draw_frames==0 then
			__clear()
			update_animation_values()
			need_clear=true
			need_save=true
			draw_visits()
			config.animation=config.animation+1/frame_count
			if config.animation>1 then
				animate=false
			end
		end
	else
		__clear()
		draw_visits()
	end
	auto_clear()
	visit_iter()
	local scale=config.scale
	local cx,cy=config.cx,config.cy
	local c,x,y= is_mouse_down()
	if c then
		--mouse to screen
		x=(x/size[1]-0.5)*2
		y=(-y/size[2]+0.5)*2
		--screen to world
		x=(x-cx)/scale
		y=(y-cy)/(scale*aspect_ratio)

		print(x,y)
		--now set that world pos so that screen center is on it
		config.cx=(-x)*scale
		config.cy=(-y)*(scale*aspect_ratio)
		need_clear=true
	end
	if __mouse.wheel~=0 then
		local pfact=math.exp(__mouse.wheel/10)
		config.scale=config.scale*pfact
		config.cx=config.cx*pfact
		config.cy=config.cy*pfact
		need_clear=true
	end
end
