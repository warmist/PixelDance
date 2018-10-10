require 'common'

image = image or make_image_buffer(STATE.size[1],STATE.size[2])
color = color or pixel{255,0,0,255};
pos=pos or {STATE.size[1]/2,STATE.size[2]/2}
rnd=rnd or pcg_rand.Make()
rnd:seed(10)
r_count=0
r_avg=0
function resize( w,h )
	image=make_image_buffer(w,h)
end
function update(  )
	r_count=r_count+1
	r_avg=r_avg+pcg_rand.gen(-1,1)
	print(r_avg/r_count)
	local x=pos[1]
	local y=pos[2]
	local w=STATE.size[1]
	local h=STATE.size[2]
	for i=1,100000 do
		image.d[x+y*w]=color
		color.r=color.r+rnd(-1,1)
		color.g=color.g+rnd(-1,1)
		color.b=color.b+rnd(-1,1)
		if rnd()>0.5 then
			x=x+rnd(-1,1)
		else
			y=y+rnd(-1,1)
		end
		if x<0 then x=w-1 end
		if y<0 then y=h-1 end
		if x>=w-1 then x=0 end
		if y>=h-1 then y=0 end
		pos[1]=x
		pos[2]=y
	end
	image:present()
end