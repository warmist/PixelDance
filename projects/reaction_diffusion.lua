require "common"
--[[
	TODO:
		* add oversample
		* add MAX Over T for some T
		* multi scale turing patterns: https://faculty.ac/image-story/a-machine-in-motion/
		* https://elifesciences.org/articles/14022
		* https://examples.pyviz.org/attractors/attractors.html

]]
config=make_config({
	{"pause",false,type="boolean"},
	{"clamp_edges",false,type="boolean"},
	{"do_sum",false,type="boolean"},
	{"do_norm",false,type="boolean"},
	{"diff_a",1,type="float",min=0,max=1},
	{"diff_b",0.5,type="float",min=0,max=1},
	{"diff_c",0.25,type="float",min=0,max=1},
	{"diff_d",0.125,type="float",min=0,max=1},
	{"k1",0.5,type="float",min=0,max=1},
	{"k2",0.5,type="float",min=0,max=1},
	{"k3",0.5,type="float",min=0,max=1},
	{"k4",0.5,type="float",min=0,max=1},
	{"reaction_scale",1,type="floatsci",min=0,max=1},
	{"region_size",0.5,type="float",min=0.01,max=1},
	{"gamma",1,type="float",min=0.01,max=5},
	{"gain",1,type="float",min=-5,max=5},
	{"draw_comp",0,type="int",min=0,max=3},
	{"animate",false,type="boolean"},
},config)

mapping_parameters={1,2}

local oversample=0.25 --TODO: not working correctly
function update_size()
	local trg_w=1024
	local trg_h=1024
	--this is a workaround because if everytime you save
	--  you do __set_window_size it starts sending mouse through windows. SPOOKY
	if win_w~=trg_w or win_h~=trg_h or (img_buf==nil or img_buf.w~=trg_w) then
		win_w=trg_w
		win_h=trg_h
		aspect_ratio=win_w/win_h
		__set_window_size(win_w,win_h)
	end
end
update_size()

local size=STATE.size
img_buf=img_buf or make_image_buffer(size[1],size[2])
react_buffer=react_buffer or multi_texture(size[1],size[2],2,1)
collect_buffer=collect_buffer or multi_texture(size[1],size[2],2,1)
io_buffer=io_buffer or make_flt_buffer(size[1],size[2])

map_region=map_region or {-1,0,0,0}
thingy_string=thingy_string or "-c.x*c.y*c.y,0,0,+c.x*c.y*c.y"

--feed_kill_string=feed_kill_string or "feed_rate*(1-c.x),-(kill_rate)*c.y,-(kill_rate)*(c.z),-(kill_rate)*c.w"
feed_kill_string="-k.y,-k.y,-k.y,k.x"

--cos(c.z),cos((k.z)-(((c.z)*((k.w)-(k.x)))-(c.x))),cos((c.y)-((c.w)+((k.y)*(c.x)))),cos((c.w)*(c.x))

function resize( w,h )
	local ww=w*oversample
	local hh=h*oversample
	img_buf=make_image_buffer(w,h)
	size=STATE.size
	react_buffer:update_size(ww,hh)
	collect_buffer:update_size(ww,hh)
	io_buffer=make_flt_buffer(ww,hh);
end
if react_buffer.w~=win_w*oversample then
	resize(win_w,win_h)
end
function count_lines( s )
	local n=0
	for i in s:gmatch("\n") do n=n+1 end
	return n
end

function shader_make( s_in )
	local sl=count_lines(s_in)
	s="#version 330\n#line "..(debug.getinfo(2, 'l').currentline-sl).."\n"
	s=s..s_in
	return shaders.Make(s)
end


local react_diffuse
function update_diffuse(  )
react_diffuse=shaders.Make(string.format([==[
#version 330
#line __LINE__

out vec4 color;
in vec3 pos;

uniform vec4 diffusion;
uniform vec4 kill_feed;

uniform sampler2D tex_main;
uniform float dt;
uniform float reaction_scale;

uniform vec4 map_region[4];//w,h,used?,x or y
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
#define MAPPING
vec4 gray_scott(vec4 c,vec2 normed)
{
	//NOTE: can increase the dt somewhat generally...
	//x=0;0.5
	//y=0;0.25
	/*
		X+2Y=3Y
	*/
	vec4 scale=vec4(0.07,0.1,0,0);
	vec4 offset=vec4(0);

	vec4 k=kill_feed;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;
#if 0
	vec2 kcenter=vec2(0.861682,0.439294);
	float w=0.0625;
	//0.861682,0.439294), width:0.0625
	//0.694565,0.190942
	//0.697397,0.19309), width:0.03125
	float dist=1-clamp(length(normed-vec2(0.5))*2,0,1);
	kill_rate=(kcenter.x-w*0.5+dist*w)*0.07;
	feed_rate=(kcenter.y-w*0.5+dist*w)*0.1;
#endif
	float abb=c.x*c.y*c.y;
	return vec4(-abb,abb,0,0)+vec4(k.x*(1-c.x),-(k.y+k.x)*c.y,0,0);
}
vec4 schnakenberk_reaction_kinetics(vec4 cnt,vec2 normed)
{
#if 0
	float k1=kill_feed.x;
	float k2=kill_feed.y;
	float k3=kill_feed.z;
	float k4=kill_feed.w;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k3=mix(map_region[0].x,map_region[0].y,normed.x);
		k4=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	float aab=cnt.x*cnt.x*cnt.y;
	return vec2(k1,k4)-vec2(k2*cnt.x,0)+vec2(k3*aab,-k3*aab);
#endif
	vec4 k=kill_feed;
	vec4 scale=vec4(4,4,4,4);
	vec4 offset=vec4(0,0,0,0);

#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;
	return k.z*vec4(k.x-cnt.x-cnt.x*cnt.x*cnt.y,k.y-cnt.x*cnt.x*cnt.y,0,0);
}
vec4 gierer_meinhard(vec4 cnt,vec2 normed)
{
	//not dimensional
	float k1=kill_feed.x;
	float k2=kill_feed.y;
	float k3=kill_feed.z;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k1=mix(map_region[0].x,map_region[0].y,normed.x);
		k2=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif

	return k3*vec4(k1-k2*cnt.x+cnt.x*cnt.x/cnt.y,cnt.x*cnt.x-cnt.y,0,0);
}
vec4 ruijgrok(vec4 cnt,vec2 normed)
{
	/*
		X+Y=>2X
		Y+Z=>2Y
		Z+X=>2Z

		X+2Y=>3Y
		Y+2Z=>3Z
		Z+2X=>3X
	*/
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	kill_rate=mix(map_region[0].x,map_region[0].y,normed.x);
	feed_rate=mix(map_region[0].z,map_region[0].w,normed.y);
#endif
	float pos_x1=cnt.y*cnt.x;
	float pos_x2=cnt.z*cnt.x*cnt.x;

	float pos_y1=cnt.z*cnt.y;
	float pos_y2=cnt.x*cnt.y*cnt.y;

	float pos_z1=cnt.z*cnt.x;
	float pos_z2=cnt.z*cnt.y*cnt.y;

	float neg_x1=pos_y2;
	float neg_x2=pos_z1;

	float neg_y1=pos_x1;
	float neg_y2=pos_z2;

	float neg_z1=pos_x2;
	float neg_z2=pos_y1;
	return vec4(
		pos_x1+pos_x2-neg_x1-neg_x2+feed_rate*(1-cnt.x),
		pos_y1+pos_y2-neg_y1-neg_y2-(kill_rate+feed_rate)*cnt.y,
		pos_z1+pos_z2-neg_z1-neg_z2,
		0);
}
vec4 rossler(vec4 cnt,vec2 normed)
{
	//k1=0.2
	//k2=0.2
	//k3=5.7

	//k1=0.1
	//k2=0.1
	//k3=14
	float k1=kill_feed.x*0.2+0.1;
	float k2=kill_feed.y*0.2+0.1;
	float k3=kill_feed.z*20+4;

	float k4=kill_feed.w;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		//k1=mix(map_region[0].x,map_region[0].y,normed.x)*0.2+0.1;
		k2=mix(map_region[0].z,map_region[0].w,normed.y)*0.2+0.1;
		//k3=mix(map_region[0].x,map_region[0].y,normed.x)*20+4;
	}
#endif

	return vec4(
		-(cnt.y+cnt.z),
		cnt.x+k1*cnt.y,
		cnt.x*cnt.z-k2*cnt.z+k3,
		0
	)*k4;
}
vec4 rossler4(vec4 c,vec2 normed)
{
	//http://www.scholarpedia.org/article/Hyperchaos
	//explodes very fast
	vec4 scale=vec4(0.125,1.5,0.25,0.025);
	vec4 offset=vec4(0.25,3,0.5,0.05);

	vec4 k=kill_feed;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;

	return vec4(
		-c.y-c.z,
		c.x+k.x*c.y+c.w,
		k.y+c.x*c.z,
		-k.z*c.z+k.w*c.w
	);
}
vec4 two_reacts(vec4 cnt,vec2 normed)
{
	/*
		X+2Y=3Y
		Z+X=2Z

	*/
	float kill_rate=kill_feed.x;
	float feed_rate=kill_feed.y;
#ifdef MAPPING
	vec2 c=vec2(0.5,0.5);
	vec2 cs=vec2(0.5,0.5);
	kill_rate=mix(c.x-cs.x,c.x+cs.x,normed.x);
	feed_rate=mix(c.y-cs.y,c.y+cs.y,normed.y);
#endif
	float pos_y1=cnt.x*cnt.y*cnt.y;
	float pos_z1=cnt.z*cnt.x;

	float neg_x1=pos_y1;
	float neg_x2=pos_z1;

	return vec4(
		-neg_x2-neg_x1+feed_rate*(1-cnt.x),
		pos_y1,
		pos_z1-(kill_rate+feed_rate)*cnt.z,
		0);
}
vec4 thingy_formulas(vec4 c,vec2 normed)
{
	vec4 scale=vec4(20);
	vec4 offset=vec4(-10);
	vec4 k=kill_feed;

#ifdef MAPPING
	//if (map_region[0].z>=0 || map_region[1].z>=0 || map_region[2].z>=0 || map_region[3].z>=0)
	{
		#define MAPPED_VALUE(id,value) value=mix(value,mix(map_region[id].x,map_region[id].y,mix(normed.x,normed.y,map_region[id].w)),map_region[id].z)
		MAPPED_VALUE(0,k.x);
		//k.x=mix(k.x,mix(0,1,mix(normed.x,normed.y,0)),1);
		//k.y=mix(k.y,mix(0,1,mix(normed.x,normed.y,1)),1);
		MAPPED_VALUE(1,k.y);
		MAPPED_VALUE(2,k.z);
		MAPPED_VALUE(3,k.w);		
	}
#endif
	k=k*scale+offset;

	float max_len=1;
	vec4 values=vec4(%s);
	//float l=length(values);
	//float l=length(c);
	//float l=max(max(abs(values.x),abs(values.y)),max(abs(values.z),abs(values.w)));
	float l=max(max(abs(c.x),abs(c.y)),max(abs(c.z),abs(c.w)));
	float nl=clamp(l/max_len,0,1);
	values=mix(values,-c,nl);
	//r=r/(l);
	//return r*exp(-l*l/100);
	//*k.y+vec4(%s)*k.w;
	//return r;
	return values*reaction_scale;
}
vec4 hyper_chaos(vec4 c,vec2 normed)
{
	//BROKEN SOURCE?
	vec4 scale=vec4(1);
	vec4 offset=vec4(0);

	vec4 k=kill_feed;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;
	return vec4(
		c.x*(1-c.y)+k.x*c.z,
		k.y*(c.x*c.x-1)*c.y,
		k.z*(1-c.y)*c.w,
		k.w*c.z
	);
}
vec4 lorenz_system(vec4 c,vec2 normed)
{
	//k1=10
	//k2=28
	//k3=8/3

	vec4 scale=vec4(6,6,1,0);
	vec4 offset=vec4(7,22,8/3-0.5,0);

	vec4 k=kill_feed;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;

	return vec4(
		k.x*(c.y-c.x),
		c.x*(k.y-c.z)-c.y,
		c.x*c.y-k.z*c.z,
		0
	);
}
vec4 chen_attractor(vec4 c,vec2 normed)
{
	//BROKEN?
	//chaos at: a = 40, b = 3, c = 28
	//k.x=36,k.y=20,k.z=0 (and k.z=3)
	//float k1=kill_feed.x*40+20;
	//float k2=kill_feed.y*6;
	//float k3=kill_feed.z*56;

	vec4 scale=vec4(2,2,3,0);
	vec4 offset=vec4(35,19,0,0);

	vec4 k=kill_feed;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		//k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
		k.z=mix(map_region[0].x,map_region[0].y,normed.x);
	}
#endif

	k=k*scale+offset;

	return vec4(
		k.x*(c.y-c.x),
		(k.z-k.x)*c.x-c.x*c.z+k.z*c.y,
		c.x*c.y-k.y*c.z,
		0
	);
}
vec4 clifford_attractor(vec4 c, vec2 normed)
{
	vec4 scale=vec4(2,2,2,2);
	vec4 offset=vec4(0,0,-1,-1);
	vec4 k=kill_feed;

#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.x);
		//k.z=mix(map_region[0].z,map_region[0].w,normed.y);
		//k.w=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif

	k=k*scale+offset;
	return vec4(
			sin(k.x*c.y)+k.z*cos(k.x*c.x),
			sin(k.y*c.x)+k.w*cos(k.y*c.y),
			0,
			0
	);
}
vec4 hopalong_attractor1(vec4 c,vec2 normed)
{
	vec4 k=kill_feed*8-vec4(4);

#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x)*4-2;
		k.y=mix(map_region[0].z,map_region[0].w,normed.y)*4-2;
	}
#endif
	return vec4(
			c.y-sqrt(abs(k.y*c.x-k.z))*sign(c.x),
			k.x-c.x,
			0,
			0
	);
}

vec4 hopalong_attractor2(vec4 c,vec2 normed)
{
	vec4 k=kill_feed*8-vec4(4);

#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif

	//k=k*scale+offset;

	return vec4(
			c.y-1.0-sqrt(abs(k.y*c.x-1.0-k.z))*sign(c.x-1.0),
			k.x-c.x-1.0,
			0,
			0
	);
}
vec4 coullet_attractor(vec4 c, vec2 normed)
{
	
	vec4 scale=vec4(2,2,2,2);
	vec4 offset=vec4(0.8,-1.1,-0.45,-1);
	vec4 k=kill_feed;

#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.x);
		//k.z=mix(map_region[0].z,map_region[0].w,normed.y);
		//k.w=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif

	k=k*scale+offset;
	return vec4(
			c.y,
			c.z,
			dot(vec4(c.x,c.y,c.z,c.x*c.x*c.x),k),
			0
	);
}
vec4 chaos_4d(vec4 c, vec2 normed)
{
	//https://www.sciencedirect.com/science/article/pii/S209044791730014X
	//EXPLODES VERY FAST
	vec4 scale=vec4(4,4,0,0);
	vec4 offset=vec4(21,7,0,0);

	vec4 k=kill_feed;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;
	return vec4(
			k.x*(c.x-c.w),
			k.y*c.w-c.w*c.y,
			c.w*c.x-c.x*c.z,
			c.y*(c.x-1)
	);
}
float GM_helper(float x,float mu)
{
	return mu*x+2*(1-mu)*x*x/(1+x*x);
}
vec4 gumowski_mira_attractor(vec4 c,vec2 normed)
{
	//NB: probably broken
	//http://kgdawiec.bplaced.net/badania/pdf/cacs_2010.pdf
	//3 param
	vec4 scale=vec4(0.001,1,0.05,0);
	vec4 offset=vec4(0.001,-.5,0,0);

	vec4 k=kill_feed;

#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.z=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;
	float xn=c.y+k.x*(1-k.y*c.y*c.y)*c.y+GM_helper(c.x,k.z);
	return vec4(
			xn,
			-c.x+GM_helper(xn,k.z),
			0,
			0
	);
}
vec4 rampe1_modded(vec4 c,vec2 normed)
{
	//https://softologyblog.wordpress.com/2009/10/19/3d-strange-attractors/

	vec4 scale=vec4(2,2,2,2);
	vec4 offset=vec4(-1,-1,-1,-1);

	vec4 k=kill_feed;
	float ke=-0.8;
	float kf=0.7;
#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		k.y=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;
	vec4 r=vec4(
			cos(k.x*c.x)+cos(k.y*c.y),
			cos(k.z*c.y)+cos(k.w*c.z),
			cos(ke*c.z)+cos(kf*c.x),
			0
	);
	float l=length(r);
	l=max(l,0.00001);
	return r/l;
}
vec4 coupled_attractors(vec4 c,vec2 normed)
{
	//AGiga-StableOscillatorwithHiddenandSelf-ExcitedAttractorsAMegastableOscillatorForcedbyHisTwin.pdf
	vec4 scale=vec4(0.2,0.5,0.75,0);
	vec4 offset=vec4(0.1,2.77,0,0);

	vec4 k=kill_feed;

#ifdef MAPPING
	if (map_region[0].x>=0)
	{
		k.x=mix(map_region[0].x,map_region[0].y,normed.x);
		//k.y=mix(map_region[0].z,map_region[0].w,normed.y);
		k.z=mix(map_region[0].z,map_region[0].w,normed.y);
	}
#endif
	k=k*scale+offset;
	vec4 r=vec4(
			c.y,
			-k.x*k.x*c.x+c.y*cos(c.x)+k.z*c.z,
			k.y*c.w,
			k.y*(-k.x*k.x*c.z+c.w*cos(c.z))
	);
	return r;
}
vec4 actual_function(vec4 c,vec2 normed)
{
	return
		//gray_scott(c,normed)
		//ruijgrok(c,normed)
		//two_reacts(c,normed)
		thingy_formulas(c,normed)
		//schnakenberk_reaction_kinetics(c,normed)
		//gierer_meinhard(c,normed)
		//rossler(c,normed)
		//rossler4(c,normed)
		//hyper_chaos(c,normed)
		//lorenz_system(c,normed)
		//chen_attractor(c,normed)
		//clifford_attractor(c,normed)
		//hopalong_attractor1(c,normed)
		//hopalong_attractor2(c,normed)
		//gumowski_mira_attractor(c,normed)
		//chaos_4d(c,normed)
		//coullet_attractor(c,normed)
		//rampe1_modded(c,normed)
		//coupled_attractors(c,normed)
		;
}
vec4 runge_kutta_4(vec4 c,vec2 normed,float step_dt)
{

	vec4 k1=step_dt*actual_function(c,normed);
	vec4 k2=step_dt*actual_function(c+0.5*k1,normed);
	vec4 k3=step_dt*actual_function(c+0.5*k2,normed);
	vec4 k4=step_dt*actual_function(c+k3,normed);

	return c+(k1+2*k2+2*k3+k4)/6.0;
}

void main(){
	vec4 diffusion_value=diffusion;
	vec2 normed=(pos.xy+vec2(1,1))/2;

	float dist=clamp(length(pos.xy)+0.5,0.5,1.5);

	//diffusion_value.xy*=dist;
	vec4 L=laplace(normed);
	vec4 cnt=texture(tex_main,normed);
#if 1
	vec4 ret=cnt+(diffusion_value*L
		+actual_function(cnt,normed)
		)*dt;
#elif 0
	int step_count=10;
	float step_dt=dt/float(step_count);

	vec4 ret=cnt;
	for(int i=0;i<step_count;i++)
		{
			ret+=actual_function(ret,normed)*step_dt;
		}
	ret+=diffusion_value*L*dt;
#elif 1
	vec4 ret=diffusion_value*L*dt+runge_kutta_4(cnt,normed,dt);
#else
	int step_count=10;
	float step_dt=dt/float(step_count);

	vec4 ret=vec4(cnt);
	for(int i=0;i<step_count;i++)
		{
			ret=runge_kutta_4(ret,normed,step_dt);
		}
	ret+=diffusion_value*L*dt;
#endif
	//ret=clamp(ret,-1,1);
	//float l=length(ret);
	//l=max(l,0.0001);
	color=ret;///l;
}
]==],thingy_string,feed_kill_string))
end
update_diffuse()
local draw_shader = shader_make[==[
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;

uniform float v_gamma;
uniform float v_gain;
uniform int draw_comp;
uniform vec4 value_scale;
uniform vec4 value_offset;
float gain(float x, float k)
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}
vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}

void main(){

	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 cnt=texture(tex_main,normed);
	cnt+=value_offset;
	cnt*=value_scale;
	//cnt=clamp(cnt,0,1);
	float lv=cnt.x;
	if(draw_comp==1)
		lv=cnt.y;
	else if(draw_comp==2)
		lv=cnt.z;
	else if(draw_comp==3)
		lv=cnt.w;

	//lv+=value_offset;
	//lv*=value_scale;
	
	lv=gain(lv,v_gain);
	lv=pow(lv,v_gamma);
	//color=vec4(cnt.xyz,1);
	color=vec4(lv,lv,lv,1);
	//color=vec4(palette(lv,vec3(0.5,0.5,0.5),vec3(0.5,0.5,0.5),vec3(1.5,1.5,1.25),vec3(1.0,1.05,1.4)),1);
	//color=vec4(palette(lv,vec3(0.6,0,0.3),vec3(.4,0,0.7),vec3(1,1,1),vec3(0,0.33,0.66)),1);
	/* accent
	float accent_const=0.5;
	if(lv<accent_const)
		color=vec4(vec3(1)*(lv/accent_const),1);
	else
		color=mix(vec4(1),vec4(0.05,0.1,0.3,1),(lv-accent_const)/(1-accent_const));
	//*/
	/*
	if(lv>0)
		color.xyz=vec3(lv,0,0);
	else
		color.xyz=vec3(0,0,lv);
	color.w=1;
	//*/
}
]==]

local sum_texture = shader_make[==[
out vec4 color;
in vec3 pos;

uniform sampler2D tex_main;
uniform sampler2D tex_old;
vec4 smooth_max_p_norm(vec4 a,vec4 b,float alpha)
{
	return pow(pow(a,vec4(alpha))+pow(b,vec4(alpha)),vec4(1/alpha));
}
vec4 smooth_max_2(vec4 a,vec4 b,float alpha)
{
	return ((a+b)+sqrt((a+b)*(a+b)+alpha))/2;
}
vec4 smooth_max(vec4 a,vec4 b,float alpha)
{
	return (a*exp(alpha*a)+b*exp(alpha*b))/(exp(alpha*a)+exp(alpha*b));
}
void main(){

	vec2 normed=(pos.xy+vec2(1,1))/2;
	vec4 cnt=texture(tex_main,normed);
	vec4 cnt_old=texture(tex_old,normed);

	//color=max(abs(cnt),abs(cnt_old));
	color=max(cnt,cnt_old);
	//color=max(cnt,cnt_old)-min(cnt,cnt_old);
	//color=(abs(cnt)+abs(cnt_old))/2;
	//color=cnt+cnt_old;
	//color=smooth_max(cnt,cnt_old,5);
	//color=smooth_max_p_norm(cnt,cnt_old,5);
	//color.a=1;
}
]==]
local terminal_symbols={["c.x"]=10,["c.y"]=10,["c.z"]=10,["c.w"]=10,["1.0"]=0.1,["0.0"]=0.1}
local normal_symbols={
["max(R,R)"]=0.5,["min(R,R)"]=0.5,["mod(R,R)"]=0.1,["fract(R)"]=0.1,["floor(R)"]=0.1,["abs(R)"]=0.1,
["sqrt(R)"]=0.1,["exp(R)"]=0.01,["atan(R,R)"]=1,["acos(R)"]=0.1,["asin(R)"]=0.1,["tan(R)"]=1,["sin(R)"]=1,
["cos(R)"]=1,
["log(R+1.0)"]=0.5,
["(R)/(R+1)"]=0.1,["(R)*(R)"]=10,["(R)-(R)"]=10,["(R)+(R)"]=10}


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
	num_rep=math.random(0,num_match-1)
	function rep_one(  )
		if num_rep==0 then
			num_rep=num_rep-1
			if type(rep)=="function" then
				return rep()
			else
				return rep
			end
		else
			num_rep=num_rep-1
			return false
		end
	end
	local ret=string.gsub(s,substr,rep_one)
	return ret
end
function make_rand_math(def_seed, normal_s,terminal_s,forced_s )
	forced_s=forced_s or {}
	return function ( steps,seed,force_values)
		local cur_string=seed or def_seed
		force_values=force_values or forced_s
		function M(  )
			return rand_weighted(normal_s)
		end
		function MT(  )
			return rand_weighted(terminal_s)
		end

		for i=1,steps do
			cur_string=replace_random(cur_string,"R",M)
		end
		for i,v in ipairs(force_values) do
			cur_string=replace_random(cur_string,"R",v)
		end
		cur_string=string.gsub(cur_string,"R",MT)
		return cur_string
	end
end
random_math=make_rand_math("R,R,R,R",normal_symbols,terminal_symbols)
random_math_cos=make_rand_math("cos(R),cos(R),cos(R),cos(R)",normal_symbols,terminal_symbols)

function random_math_balanced( steps,seed )
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end
	local ret=""
	for i=1,4 do
		local cur_string=seed or "R"

		for i=1,steps do
			cur_string=replace_random(cur_string,"R",M)
		end
		cur_string=string.gsub(cur_string,"R",MT)
		if i==1 then
			ret=cur_string
		else
			ret=ret..","..cur_string
		end
	end
	return ret
end
function random_math_poly(  )
	local rf=function (  )
		return math.random()*2-1
	end
	local ret=string.format("dot(c,vec4(%g,%g,%g,%g)),dot(c,vec4(%g,%g,%g,%g)),dot(c,vec4(%g,%g,%g,%g)),dot(c,vec4(%g,%g,%g,%g))",
			rf(),rf(),rf(),rf(),
			rf(),rf(),rf(),rf(),
			rf(),rf(),rf(),rf(),
			rf(),rf(),rf(),rf())
	return ret
end
function random_math_transfers( steps,seed,count_transfers )
	count_transfers=count_transfers or 3
	function M(  )
		return rand_weighted(normal_symbols)
	end
	function MT(  )
		return rand_weighted(terminal_symbols)
	end
	local ret={"0","0","0","0"}
	for i=1,count_transfers do
		local cur_string=seed or "R"

		for i=1,steps do
			cur_string=replace_random(cur_string,"R",M)
		end
		cur_string=string.gsub(cur_string,"R",MT)
		local remove=math.random(1,4)
		local add=math.random(1,4)
		while add==remove do
			add=math.random(1,4)
		end
		ret[remove]=ret[remove].."-"..cur_string
		ret[add]=ret[add].."+"..cur_string

	end
	local rstr=table.concat(ret,",")
	return rstr
end
function set_region( id,v1,v2,is_used,xory )
	react_diffuse:set("map_region["..(id-1).."]",v1,v2,is_used,xory)
end
function sim_tick(  )
	local dt=0.05
	react_diffuse:use()
--	react_diffuse:blend_disable()
	react_diffuse:blend_default()
	react_diffuse:set("diffusion",config.diff_a,config.diff_b,config.diff_c,config.diff_d)
	react_diffuse:set("kill_feed",config.k1,config.k2,config.k3,config.k4)
	react_diffuse:set("dt",dt)
	react_diffuse:set("reaction_scale",config.reaction_scale)
	for i=1,4 do
		if mapping_parameters[1]==i and map_region[1]>=0 then
			set_region(i,map_region[1],map_region[2],1,0)
		elseif mapping_parameters[2]==i and map_region[1]>=0 then
			set_region(i,map_region[3],map_region[4],1,1)
		else
			set_region(i,0,0,0,0)
		end
	end
	local cur_buff=react_buffer:get()
	local do_clamp
	if config.clamp_edges then
		do_clamp=1
	else
		do_clamp=0
	end
	cur_buff:use(0,1,do_clamp)
	react_diffuse:set_i("tex_main",0)

	local next_buff=react_buffer:get_next()
	next_buff:use(1,1,do_clamp)
	if not next_buff:render_to(react_buffer.w,react_buffer.h) then
		error("failed to set framebuffer up")
	end

	react_diffuse:draw_quad()

	__render_to_window()
	react_buffer:advance()
end
init_size=1
function reset_buffers(rnd,do_rand)
	local b=io_buffer

	local center=0
	local scale=2
	local min_value=center-scale/2
	local max_value=center+scale/2
	--[[
	local min_value=-1
	local max_value=1
	]]
	do_rand=false
	local v = {math.random()*(max_value-min_value)+min_value,
		math.random()*(max_value-min_value)+min_value,
		math.random()*(max_value-min_value)+min_value,
		math.random()*(max_value-min_value)+min_value}
	for x=0,b.w-1 do
		for y=0,b.h-1 do
			local dx=x-b.w/2
			local dy=y-b.h/2
			local dist=math.sqrt(dx*dx+dy*dy)
			-- [[
			if rnd=="circle" then
				if dist<b.w/4 then
					if do_rand then
						b:set(x,y,{
						math.random()*(max_value-min_value)+min_value,
						math.random()*(max_value-min_value)+min_value,
						math.random()*(max_value-min_value)+min_value,
						math.random()*(max_value-min_value)+min_value})
					else
						b:set(x,y,v)
					end
				else
					b:set(x,y,{1,
					math.random()*(max_value-min_value)+min_value,
					math.random()*(max_value-min_value)+min_value,
					math.random()*(max_value-min_value)+min_value})
				end
			elseif rnd=="noise" then
				b:set(x,y,{
				math.random()*(max_value-min_value)+min_value,math.random()*(max_value-min_value)+min_value,
					math.random()*(max_value-min_value)+min_value,math.random()*(max_value-min_value)+min_value})
			elseif rnd=="chaos" then

			local v=(x+y)/(b.w+b.h-2)
			b:set(x,y,{
					(x/(b.w-1)+0.1)*(max_value-min_value)+min_value,
					(1-y/(b.h-1)-0.1)*(max_value-min_value)+min_value,
					--dist/10,
					--dist/10,
					--dist/10,
					(x/(b.w-1)+0.1)*(max_value-min_value)+min_value,
					(y/(b.w-1)+0.1)*(max_value-min_value)+min_value})

			else
				b:set(x,y,{1,0,0,0})

			end
			--]]
		end
	end

	if rnd=="square" then
		local cx=math.floor(b.w/2)
		local cy=math.floor(b.h/2)
		local s=math.random(1,b.w*0.25)

		for x=cx-s,cx+s do
			for y=cy-s,cy+s do
				local dx=x-cx
				local dy=y-cy
				--if math.sqrt(dx*dx+dy*dy)<s then
				if do_rand then
					b:set(x,y,{
						math.random()*(max_value-min_value)+min_value,
						math.random()*(max_value-min_value)+min_value,
						math.random()*(max_value-min_value)+min_value,
						math.random()*(max_value-min_value)+min_value
					})
				else
					b:set(x,y,v)
				end
				--end
			end
		end
	end

	local buf=react_buffer:get()
	buf:use(0)
	b:write_texture(buf)
	react_buffer:advance()

	buf=react_buffer:get()
	buf:use(0)
	b:write_texture(buf)

	reset_collect()
end
function reset_collect()
	local b=io_buffer
	for x=0,b.w-1 do
		for y=0,b.h-1 do
			b:set(x,y,{0,0,0,0})
		end
	end
	local buf=collect_buffer:get()
	buf:use(0)
	b:write_texture(buf)
	collect_buffer:advance()

	buf=collect_buffer:get()
	buf:use(0)
	b:write_texture(buf)
end
function is_inf( v )
	if v==math.huge or v==-math.huge then
		return true
	end
	return false
end
function clip_maxmin( tbl1,tbl2,id )
	if is_inf(tbl1[id]) or is_inf(tbl2[id]) then
		print("clip",id)
		tbl1[id]=0
		tbl2[id]=1
	elseif math.abs(tbl1[id]-tbl2[id])<0.0001 then
		tbl1[id]=0
		tbl2[id]=1
	end
end
function eval_thingy_string()
	local MAX_DIFF_VALUE=0.25
	local env={
		max=math.max,
		min=math.min,
		mod=math.modf,
		fract=function ( x )
			return select(2,math.modf(x))
		end,
		floor=math.floor,
		abs=math.abs,
		sqrt=math.sqrt,
		exp=math.exp,
		atan=math.atan,
		acos=math.acos,
		asin=math.asin,
		tan=math.tan,
		sin=math.sin,
		cos=math.cos,
		log=math.log,
		math=math,
		dot=function ( a,b )
			return a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w
		end,
		vec4=function ( x,y,z,w )
			return {x=x,y=y,z=z,w=w}
		end
	}
	local f=load(string.format(
		[==[
		local inf=math.huge
		local val_min={inf,inf,inf,inf}
		local val_max={-inf,-inf,-inf,-inf}
		local step_size=0.05
		local itg={0,0,0,0}
			for x=0,1,step_size do
				for y=0,1,step_size do
					for z=0,1,step_size do
						for w=0,1,step_size do
							local c={x=x,y=y,z=z,w=w}
							local tx,ty,tz,tw=%s
							if tx>val_max[1] then val_max[1]=tx end
							if ty>val_max[2] then val_max[2]=ty end
							if tz>val_max[3] then val_max[3]=tz end
							if tw>val_max[4] then val_max[4]=tw end

							if tx<val_min[1] then val_min[1]=tx end
							if ty<val_min[2] then val_min[2]=ty end
							if tz<val_min[3] then val_min[3]=tz end
							if tw<val_min[4] then val_min[4]=tw end
							itg[1]=itg[1]+tx*step_size*step_size*step_size
							itg[2]=itg[2]+ty*step_size*step_size*step_size
							itg[3]=itg[3]+tz*step_size*step_size*step_size
							itg[4]=itg[4]+tw*step_size*step_size*step_size
						end
					end
				end
			end
			return val_min,val_max,itg
		]==],thingy_string),"thingy","t",env)
	local ret,vmin,vmax,itg=pcall(f)
	if ret then

		print("Min:",vmin[1],vmin[2],vmin[3],vmin[4])
		print("Max:",vmax[1],vmax[2],vmax[3],vmax[4])
		print("Integral:",itg[1],itg[2],itg[3],itg[4])
		local swing={}
		for i=1,4 do
			clip_maxmin(vmin,vmax,i)
			if itg[i]==0 then itg[i]=1 end
			if math.abs(itg[i])==math.huge then itg[i]=1 end
			if itg[i]~=itg[i] then itg[i]=1 end

			swing[i]=vmax[i]-vmin[i]
			--swing[i]=math.abs(vmax[i]-vmin[i])
		end
		thingy_string=string.format("(vec4(%s)+vec4(%g,%g,%g,%g))*vec4(%g,%g,%g,%g)"
			,thingy_string,
			-vmin[1],-vmin[2],-vmin[3],-vmin[4],
			--itg[1],-itg[2],-itg[3],-itg[4],
			MAX_DIFF_VALUE/swing[1],MAX_DIFF_VALUE/swing[2],-MAX_DIFF_VALUE/swing[3],-MAX_DIFF_VALUE/swing[4]
			--MAX_DIFF_VALUE/itg[1],MAX_DIFF_VALUE/itg[2],-MAX_DIFF_VALUE/itg[3],-MAX_DIFF_VALUE/itg[4]
			--1,1,1,1
			)
		print(thingy_string)
	else
		print("ERR:",vmin)
	end
end

anim_state={
	current_frame=0,
	frame_skip=10,
	max_frame=12000,
	}
local do_normalize=false
function gui(  )
	imgui.Begin("GrayScott")
	draw_config(config)
	if imgui.Button("Reset") then
		reset_buffers("noise")
	end
	imgui.SameLine()
	if imgui.Button("Reset Square") then
		reset_buffers("square")
	end
	imgui.SameLine()
	if imgui.Button("Reset Circle") then
		reset_buffers("circle")
	end
	imgui.SameLine()
	if imgui.Button("Reset Chaos") then
		reset_buffers("chaos")
	end
	if imgui.Button("RandMath") then
		thingy_string=random_math(10,"R+k.x*c.x*c.y,R+k.y*c.y*c.z,R+k.z*c.z*c.w,R+k.w*c.w*c.x",{"c.x","c.y","c.z","c.w","k.x","k.y","k.z","k.w"})
		print(thingy_string)
		--eval_thingy_string()
		update_diffuse()
		reset_buffers("noise")
	end
	imgui.SameLine()
	if imgui.Button("ClearCollec") then
		reset_collect()
	end

	if imgui.Button("NotMapping") then
		if map_region[1]>=0 then
			map_region={-1,0,0,0}
		else
			local cx=config["k"..mapping_parameters[1]]
			local cy=config["k"..mapping_parameters[2]]

			local low_x=math.max(0,cx-config.region_size)
			local low_y=math.max(0,cy-config.region_size)
			local high_x=math.min(1,cx+config.region_size)
			local high_y=math.min(1,cy+config.region_size)

			map_region={low_x,high_x,low_y,high_y}
		end
	end
	imgui.SameLine()
	if imgui.Button("FullMap") then
		map_region={0,1,0,1}
		config.region_size=0.5
		reset_buffers("noise")
	end
	imgui.SameLine()

	if imgui.Button("NextMap") then
		if mapping_parameters[1]==1 then
			mapping_parameters[1]=3
			mapping_parameters[2]=4
		else
			mapping_parameters[1]=1
			mapping_parameters[2]=2
		end
		config.region_size=0.5
		print("Mapping:",mapping_parameters[1],mapping_parameters[2])
		local cx=config["k"..mapping_parameters[1]]
		local cy=config["k"..mapping_parameters[2]]

		local low_x=math.max(0,cx-config.region_size)
		local low_y=math.max(0,cy-config.region_size)
		local high_x=math.min(1,cx+config.region_size)
		local high_y=math.min(1,cy+config.region_size)

		map_region={low_x,high_x,low_y,high_y}
		reset_buffers("noise")
	end
	imgui.SameLine()
	if imgui.Button("Zoom in") then
		config.region_size=config.region_size/2
		local cx=(map_region[2]-map_region[1])/2
		local cy=(map_region[4]-map_region[3])/2

		local low_x=math.max(0,cx-config.region_size)
		local low_y=math.max(0,cy-config.region_size)
		local high_x=math.min(1,cx+config.region_size)
		local high_y=math.min(1,cy+config.region_size)

		map_region={low_x,high_x,low_y,high_y}
		reset_buffers("noise")
	end
	imgui.SameLine()
	if imgui.Button("Zoom out") then
		config.region_size=config.region_size*2

		local cx=(map_region[2]-map_region[1])/2
		local cy=(map_region[4]-map_region[3])/2

		local low_x=math.max(0,cx-config.region_size)
		local low_y=math.max(0,cy-config.region_size)
		local high_x=math.min(1,cx+config.region_size)
		local high_y=math.min(1,cy+config.region_size)
		map_region={low_x,high_x,low_y,high_y}
		reset_buffers("noise")
	end
	if imgui.Button("Save image") then
		need_save=true
	end
	imgui.SameLine()
	if imgui.Button("Save Gif") then
		print(img_buf.w,img_buf.h)
		if giffer~=nil then
			giffer:stop()
		end
		giffer=gif_saver(string.format("saved_%d.gif",os.time(os.date("!*t"))),
			img_buf,500,15)
	end
	imgui.SameLine()
	if imgui.Button("Stop Gif") then
		if giffer then
			giffer:stop()
			giffer=nil
		end
	end
	imgui.SameLine()
	if imgui.Button("Print math") then
		print(thingy_string)
	end
	if imgui.Button("norm") then
		do_normalize="single"
	end
	if imgui.Button("Start animate") then
		anim_state.current_frame=0
		config.animate=true
	end
	imgui.End()
end
function save_img( id )
	--make_image_buffer()
	--img_buf=make_image_buffer(size[1],size[2])
	local config_serial=__get_source().."\n--AUTO SAVED CONFIG:\n"
	for k,v in pairs(config) do
		if type(v)~="table" then
			config_serial=config_serial..string.format("config[%q]=%s\n",k,v)
		end
	end
	config_serial=config_serial.."\n"..string.format("thingy_string=%q",thingy_string)
	config_serial=config_serial.."\n"..string.format("feed_kill_string=%q",feed_kill_string)
	img_buf:read_frame()
	if id then
		img_buf:save(string.format("video/saved (%d).png",id),config_serial)
	else
		img_buf:save(string.format("saved_%d.png",os.time(os.date("!*t"))),config_serial)
	end
end


function find_min_max( buf )
	buf:use(0,0,0)
	local lmin={math.huge,math.huge,math.huge,math.huge}
	local lmax={-math.huge,-math.huge,-math.huge,-math.huge}

	io_buffer:read_texture(buf)
	
	local count=0
	for x=0,io_buffer.w-1 do
	for y=0,io_buffer.h-1 do
		local v=io_buffer:get(x,y)
		if v.r<lmin[1] then lmin[1]=v.r end
		if v.g<lmin[2] then lmin[2]=v.g end
		if v.b<lmin[3] then lmin[3]=v.b end
		if v.a<lmin[4] then lmin[4]=v.a end

		if v.r>lmax[1] then lmax[1]=v.r end
		if v.g>lmax[2] then lmax[2]=v.g end
		if v.b>lmax[3] then lmax[3]=v.b end
		if v.a>lmax[4] then lmax[4]=v.a end
	end
	end
	return lmin,lmax
end


function draw_texture( id )
	draw_shader:use()
	local buf=react_buffer:get()
	if config.do_sum then
		buf=collect_buffer:get()
	end
	local need_normalize=
		do_normalize or
		(global_mm==nil) or
		(config.do_norm) or
		(giffer and giffer:want_frame() and not config.pause)
	if need_normalize then
		global_mm,global_mx=find_min_max(buf)
		if do_normalize=="single" then
			do_normalize=false
		-- [[
		
		print("=======================")
		for i,v in ipairs(global_mm) do
			print(i,v)
		end
		for i,v in ipairs(global_mx) do
			print(i,v)
		end
		--]]
		end
	end
	buf:use(0,0,0)
	draw_shader:set_i('tex_main',0)
	draw_shader:set("v_gamma",config.gamma)
	draw_shader:set("v_gain",config.gain)
	draw_shader:set_i("draw_comp",config.draw_comp)

	local mm=global_mm
	local mx=global_mx
	-- [[
	local mmin=math.min(mm[1],mm[2])
	mmin=math.min(mmin,mm[3])
	mmin=math.min(mmin,mm[4])
	local mmax=math.max(mx[1],mm[2])
	mmax=math.max(mmax,mm[3])
	mmax=math.max(mmax,mm[4])
	--]]
	--[[
	local mmin=mm[config.draw_comp+1]
	local mmax=mx[config.draw_comp+1]
	--]]
	draw_shader:set("value_offset",-mm[1],-mm[2],-mm[3],-mm[4])
	draw_shader:set("value_scale",1/(mx[1]-mm[1]),1/(mx[2]-mm[2]),1/(mx[3]-mm[3]),1/(mx[4]-mm[4]))
	draw_shader:blend_disable()
	draw_shader:draw_quad()
	if need_save or id then
		save_img(id)
		if need_save=="r" then
			reset_buffers("noise")
		end
		need_save=nil
	end
	if giffer and not config.pause then
		if giffer:want_frame() then
			img_buf:read_frame()
		end
		giffer:frame(img_buf)
	end
end
function apply_sum_texture()
	sum_texture:use()
	local buf=react_buffer:get()
	buf:use(0,0,0)
	sum_texture:set_i('tex_main',0)

	local cur_buff=collect_buffer:get()
	local do_clamp
	if config.clamp_edges then
		do_clamp=1
	else
		do_clamp=0
	end
	cur_buff:use(1,0,do_clamp)
	sum_texture:set_i("tex_old",1)

	local next_buff=collect_buffer:get_next()
	next_buff:use(2,0,do_clamp)
	if not next_buff:render_to(collect_buffer.w,collect_buffer.h) then
		error("failed to set framebuffer up")
	end
	--sum_texture:blend_disable()
	sum_texture:blend_default()
	sum_texture:draw_quad()

	__render_to_window()
	collect_buffer:advance()
end
function is_mouse_down(  )
	return __mouse.clicked1 and not __mouse.owned1, __mouse.x,__mouse.y
end
function is_mouse_down_0( ... )
	return __mouse.clicked0 and not __mouse.owned0, __mouse.x,__mouse.y
end
function update( )
	__no_redraw()
	__clear()
	__render_to_window()
	gui()
	if config.pause then
		draw_texture()
	else
		sim_tick()
		apply_sum_texture()
		local save_id
		if config.animate then
			anim_state.current_frame=anim_state.current_frame+1
			if anim_state.current_frame>anim_state.max_frame then
				config.animate=false
			end
			if anim_state.current_frame % anim_state.frame_skip ==0 then
				save_id=anim_state.current_frame/anim_state.frame_skip
			end
		end
		draw_texture(save_id)
	end
	local c0
	local c,x,y= is_mouse_down()
	c0,x,y= is_mouse_down_0()
	if c or c0 then

		local scale_x
		local scale_y
		local offset_x=map_region[1]
		local offset_y=map_region[3]
		if map_region[1]>=0 then
			scale_x=map_region[2]-map_region[1]
			scale_y=map_region[4]-map_region[3]
		else
			scale_x=1
			scale_y=1
			offset_x=0
			offset_y=0
		end
		local xx=(x/size[1])*scale_x+offset_x
		local yy=(1-y/size[2])*scale_y+offset_y

		print(string.format("Center(%g,%g), width:%g",xx,yy,config.region_size))
		if c then
			config["k"..mapping_parameters[1]]=xx
			config["k"..mapping_parameters[2]]=yy
			--config.k3=xx

			-- [[
			local low_x=math.max(0,xx-config.region_size)
			local low_y=math.max(0,yy-config.region_size)
			local high_x=math.min(1,xx+config.region_size)
			local high_y=math.min(1,yy+config.region_size)
			--]]
			--[[
			local low_x=xx-config.region_size
			local low_y=yy-config.region_size
			local high_x=xx+config.region_size
			local high_y=yy+config.region_size
			--]]
			map_region={low_x,high_x,low_y,high_y}
			reset_buffers("noise")
			config.region_size=config.region_size/2
		end
	end
end
