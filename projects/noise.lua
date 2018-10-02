require 'common'

image = image or make_image_buffer(STATE.size[1],STATE.size[2])
color = color or pixel{255,0,0,255};
pos=pos or {STATE.size[1]/2,STATE.size[2]/2}

function resize( w,h )
	image=make_image_buffer(w,h)
end
function update(  )
	local x=pos[1]
	local y=pos[2]
	local w=STATE.size[1]
	local h=STATE.size[2]
	for i=1,100000 do
		image.d[x+y*w]=color
		color.red=color.red+math.random(-1,1)
		color.green=color.green+math.random(-1,1)
		color.blue=color.blue+math.random(-1,1)
		if math.random()>0.5 then
			x=x+math.random(-1,1)
		else
			y=y+math.random(-1,1)
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