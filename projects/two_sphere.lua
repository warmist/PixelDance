require "common"


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
local oversample=1

function check_textures( s )
	
	img_buf=img_buf or make_image_buffer(s[1],s[2])
	io_buffer=io_buffer or make_f4_buffer(s[1],s[2])
	--todo: probably could be reduced to 3 floats per point
	if particle_state==nil then
		particle_state={}
		for i=1,6 do
			particle_state[i]=multi_texture(s[1],s[2],2,FLTA_PIX)
		end
	end
end
check_textures(size)

config=make_config({
	{"pause",false,type="boolean"},
},config)

function resize( w,h )
	local ww=w*oversample
	local hh=h*oversample
	size=STATE.size
	img_buf=make_image_buffer(w,h)
	io_buffer=make_f4_buffer(ww,hh);
	for i,v in ipairs(particle_state) do
		v:update_size(ww,hh)
	end
end
if img_buf.w~=win_w*oversample then
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

