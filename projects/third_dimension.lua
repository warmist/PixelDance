require 'common'
--[[ IDEAS
	* https://www.cse.wustl.edu/~taoju/research/dualContour.pdf
	* halfedge/winged edge data and then manipulate (randomly?)
	* plants growing?
]]
local tri_count=2
point_count=tri_count*3 --each tri is 3 points
tri_data=make_flt_buffer(point_count,1)
byte_count=point_count*4*4 --*4 floats *4bytes each
tri_buffer=tri_buffer or buffer_data.Make()

tri_normals=make_flt_buffer(point_count,1)
tri_normals_buffer=tri_normals_buffer or buffer_data.Make()

world_view_matrix=make_ident_matrix(4,4)
function calc_set_normal(id_start)
	local p={tri_data:get(id_start,0),
	tri_data:get(id_start+1,0),
	tri_data:get(id_start+2,0)}
	local a_x=p[1].r-p[2].r
	local a_y=p[1].g-p[2].g
	local a_z=p[1].b-p[2].b

	local b_x=p[3].r-p[2].r
	local b_y=p[3].g-p[2].g
	local b_z=p[3].b-p[2].b

	local s1=a_y*b_z-a_z*b_y;
	local s2=a_z*b_x-a_x*b_z;
	local s3=a_x*b_y-a_y*b_x;

	local l=math.sqrt(s1*s1+s2*s2+s3*s3)

	for i=id_start,id_start+2 do
		tri_normals:set(i,0,{s1/l,s2/l,s3/l,0})
	end
end
function gen_tris(  )
	tri_data:set(0,0,{-0.5,-0.5,0,1})
	tri_data:set(1,0,{-0.5,0.5,0,1})
	tri_data:set(2,0,{0.5,0.5,0,1})

	calc_set_normal(0)
	tri_data:set(3,0,{0.5,0.5,0,1})
	tri_data:set(4,0,{0.5,-0.5,0,1})
	tri_data:set(5,0,{-0.5,-0.5,0,1})
	calc_set_normal(3)

	tri_buffer:use()
	tri_buffer:set(tri_data.d,byte_count)


	tri_normals_buffer:use()
	tri_normals_buffer:set(tri_normals.d,byte_count)
	__unbind_buffer()
end
--TODO: finish matrix library
gen_tris()
draw_shader=shaders.Make(
[[
#version 330

uniform mat4 world_view_matrix;
uniform mat4 projection_matrix;
uniform mat4 worldview_inverse_transpose_matrix;

uniform vec3 axis;
uniform float angle;
uniform vec3 translate;

#define M_PI 3.14159265358979323846264338327950288

layout(location = 0) in vec4 position;
layout(location = 1) in vec4 normal;

out vec4 pos;
out vec4 norm;
mat4 gen_projection()
{
	float fov=M_PI/4;
	float aspect=1;

	float near=0.1;
	float far=5;
	/*float right=0.5;
	float top=0.5;*/

	float tanfov=tan(fov*0.5);

	mat4 ret=mat4(1);
	ret[0][0]=1/(tanfov*aspect);
	ret[1][1]=1/(tanfov);
	ret[2][2]=-(far+near)/(far-near);
	ret[3][2]=-(2*far*near)/(far-near);
	ret[2][3]=-1;
	return ret;
}
mat4 rodrigues_rotation()
{
	float s=sin(angle);
	float c=1-cos(angle);
	mat3 K=mat3(0,-axis.z,axis.y,axis.z,0,-axis.x,-axis.y,axis.x,0);
	mat3 I=mat3(1);
	mat3 R=I+s*K+c*K*K;
	mat4 ret=mat4(1);
	for(int x=0;x<3;x++)
	for(int y=0;y<3;y++)
		ret[x][y]=R[x][y];
	return ret;
}
void main()
{
	mat4 wv=rodrigues_rotation();
	mat4 p=gen_projection();
	wv[3].x=translate.x;
	wv[3].y=translate.y;
	wv[3].z=translate.z;
	gl_Position=p*wv*position;
	mat4 wv_inv=transpose(inverse(wv));

	pos=position;
	norm=wv_inv*normal;
}
]]
,
[[
#version 330
uniform mat4 world_view_matrix;
in vec4 pos;
in vec4 norm;
out vec4 color;
float value_inside(float x,float a,float b)
{
	return step(a,x)-step(b,x);
}
void main()
{
	vec4 light_dir=vec4(0,0,1,0);
	float diff=max(dot(norm,light_dir),0);
	float ambient=1;

	float v=0;
	/*for(int i=0;i<4;i++)
	for(int j=0;j<4;j++)
	{
		float xx=i/4.0-0.5;
		float yy=j/4.0-0.5;
		float g=world_view_matrix[i][j];
		v+=g*value_inside(pos.x,xx,xx+0.25)*value_inside(pos.y,yy,yy+0.25);
	}*/

	color=vec4(1,abs(pos.y+0.5),abs(pos.x+0.5),1)*mix(diff,ambient,0.5);
}
]])
--print(world_view_matrix:tostring_full())
time=time or 0
function update(  )
	__clear()
    __no_redraw()

    --[[
    for i=0,3 do
    	for j=0,3 do
    		--[=[
    		if i==j then
    			world_view_matrix:set(i,j,1)
    		else
    			world_view_matrix:set(i,j,0)
    		end
    		]=]
    		world_view_matrix:set(i,j,math.random())
    	end
    end
    --]]
    time=time+1
    --[[ around Z
    local c=math.cos(time*0.1)
    local s=math.sin(time*0.1)
    world_view_matrix:set(0,0,c)
    world_view_matrix:set(1,0,-s)
    world_view_matrix:set(0,1,s)
    world_view_matrix:set(1,1,c)
    
    world_view_matrix:set(1,1,c)
    world_view_matrix:set(2,1,-s)
    world_view_matrix:set(1,2,s)
    world_view_matrix:set(2,2,c)
	--]]
	draw_shader:use()
	
	--draw_shader:set_m("world_view_matrix",world_view_matrix.d)
	draw_shader:set("axis",1/math.sqrt(2),1/math.sqrt(2),0)
	draw_shader:set("angle",time*0.01)
	draw_shader:set("translate",0,0,-5)
	tri_normals_buffer:use()
	draw_shader:push_attribute(0,"normal",4)
	tri_buffer:use()
	draw_shader:draw_triangles(0,point_count,4,0)
	__render_to_window()
	__unbind_buffer()
end