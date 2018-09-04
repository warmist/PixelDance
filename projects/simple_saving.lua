img_buf=img_buf or buffers.Make("color")

local bit = require("bit")

function get_func_source(loaded, func )
	local f=debug.getinfo(func)
	if f.source=="[C]" then
		return {}
	end
	local src
	if loaded[f.source]==nil then
		src=load_source(f.source)
		loaded[f.source]=src
	else
		src=loaded[f.source]
	end
	print("Function:",src.newlines[f.linedefined],src.newlines[f.lastlinedefined])
	local ret=src.str:sub(src.newlines[f.linedefined-1]+1,src.newlines[f.lastlinedefined])
	print(f.source)
	return ret
end
function load_source(fpath)
	if fpath:sub(1,1) == "@" then
		fpath=fpath:sub(2)
	end
	local f=io.open(fpath,"rb")
	local ret={newlines={},str=f:read("a")}
	f:seek("set",0)
	local cur_pos=0
	for l in f:lines("L") do
		cur_pos=cur_pos+#l
		table.insert(ret.newlines,cur_pos)
	end
	f:close()
	print("Loaded:",fpath)
	print("Lines:",#ret.newlines)
	print("Size:",#ret.str)
	return ret
end
local str_stream={}
function str_stream:init(str)
	local ret={}
	ret.str=str
	ret.str_index=1
	self.__index=self
	setmetatable(ret,self)
	return ret
end
function str_stream:consume_byte()
	local ret=self.str:byte(self.str_index)
	self.str_index=self.str_index+1
	return ret
end
function str_stream:append_byte( b )
	self.str=self.str..string.char(b)
end
function str_stream:size()
	return (#self.str-self.str_index+1)*8
end
--[[local img_stream={}
function img_stream:square_pixels( direction )
	
end
function img_stream:init( img,x,y,w,h,scale,next_pixel )
	local ret={}
	ret.img=img
	ret.pos={x or 0,y or 0}
	ret.size={w or 0, h or 0}
	ret.scale=scale
	ret.pixel={}
	ret.next_pixel=next_pixel or img_stream.square_pixels
	self.__index=self
	setmetatable(ret,self)
	return ret
end

function img_stream:consume_byte()
	if #self.pixel == 0 then
		self.pixel = img_buf:get(self.pos[1]*scale+xx,self.pos[2]*scale+yy)
		--consume one actual pixel
		self:next_pixel(-1)
	end
	return table.remove(self.pixel,1)
end
function img_stream:append_byte(b)
	table.insert(self.pixel,b)
	if #self.pixel >= 4 then
		local scale=self.scale
		for xx=0,scale-1 do
			for yy=0,scale-1 do
				img_buf:set(self.pos[1]*scale+xx,self.pos[2]*scale+yy,self.pixel)
			end
		end
		self.pixel={}
		self:next_pixel(1)
	end
end]]
local bitstream={}
function bitstream:init(stream)
	local ret={}
	if type(stream)=="string" then
		ret.stream=str_stream:init(stream)
	else
		ret.stream=stream
	end
	ret.current_byte=0
	ret.bit_count=0
	self.__index=self
	setmetatable(ret,self)
	return ret
end
function bitstream:consume_byte(  )
	self.current_byte=bit.bor(bit.lshift(self.current_byte,8) , self.stream:consume_byte())
	self.bit_count=self.bit_count+8
end
function bitstream:unconsume_byte(  )
	local ret = bit.band(255,self.current_byte)
	self.current_byte=bit.rshift(self.current_byte,8)
	--self.str_index=self.str_index+1
	self.bit_count=self.bit_count-8
	self.stream:append_byte(ret)
end
function bitstream:get_bits( n )
	local ret=0
	for i=1,n do
		if self.bit_count==0 then
			--self.current_byte=0
			self:consume_byte()
		end
		ret = bit.bor(bit.lshift(ret,1),bit.band(bit.rshift(self.current_byte,self.bit_count-1),1))
		--self.current_byte=bit.rshift(self.current_byte,1)
		self.bit_count=self.bit_count-1
	end
	return ret
end
function bitstream:add_bits(v, n )
	self.current_byte=bit.bor(bit.lshift(self.current_byte,n) , v)
	self.bit_count=self.bit_count+n
	if self.bit_count>=8 then
		self:unconsume_byte()
	end
end
function bitstream:size()
	return self.stream:size()*8+self.bit_count
end
function pack_string( s,masks,w,h ,scale,sx,sy)
	sx=sx or 0
	sy=sy or 0
	scale=scale or 1
	local x=sx
	local y=sy
	local bs=bitstream:init(s)
	local col={0,0,0,0}
	local cur_bit=0
	function add_bit( input )
		local cur_byte=math.floor(cur_bit/8)+1
		col[cur_byte]=bit.bor(bit.lshift(col[cur_byte],1),input)
	end
	function get_mask()
		local cur_byte=math.floor(cur_bit/8)+1
		--print("M:",cur_byte,math.fmod(cur_bit,8)+1)
		local start=math.fmod(cur_bit,8)+1
		local r=string.sub(masks[cur_byte],start,start)

		return r
	end
	while y-sy<h do
		local m=get_mask()
		--print(m)
		if m=="0" then
			add_bit(0)
		elseif m=="1" then
			add_bit(1)
		elseif m=="?" then
			add_bit(math.random(0,1))
		else
			if bs:size()>0 then
				add_bit(bs:get_bits(1))
			else
				--add_bit(math.random(0,1))
				add_bit(0)
			end
		end
		cur_bit=cur_bit+1
		if cur_bit >= 8*4 then
			for xx=0,scale-1 do
				for yy=0,scale-1 do
					img_buf:set(x*scale+xx,y*scale+yy,col)
				end
			end
			
			col={0,0,0,0}
			x=x+1
			if x>=w then
				y=y+1
				x=sx
			end
			cur_bit=0
		end
		--print(bs:size())
	end
	--[[
	for i=1,#s,bytes_per_pixel do
		local r,g,b,a=s:byte(i,i+bytes_per_pixel)
		print(x,y,"-->",r,g,b,a)
		if use_alpha then
			img_buf:set4(x,y,r or 0,g or 0,b or 0,a or 0)
		else
			img_buf:set4(x,y,r or 0,g or 0,b or 0,255)
		end
		x=x+1
		if x>=w then
			y=y+1
			x=sx or 0
		end
	end
	]]
end
function unpack_string(masks,w,h ,scale,sx,sy)
	local ret=""
	sx=sx or 0
	sy=sy or 0
	scale=scale or 1
	local x=sx
	local y=sy
	local bs=bitstream:init("")
	local cur_bit=0
	local pixel={}
	function get_pixel()
		pixel=img_buf:get(x*scale,y*scale)
	end
	function get_bit()
		local cur_byte=math.floor(cur_bit/8)+1
		local start=math.fmod(cur_bit,8)
		return bit.band(bit.rshift(pixel[cur_byte],7-start),1)
	end
	function get_mask()
		local cur_byte=math.floor(cur_bit/8)+1
		--print("M:",cur_byte,math.fmod(cur_bit,8)+1)
		local start=math.fmod(cur_bit,8)+1
		local r=string.sub(masks[cur_byte],start,start)

		return r
	end
	get_pixel()
	while y-sy<h do
		local m=get_mask()
		--print(m)
		if m=="0" then

		elseif m=="1" then
			
		elseif m=="?" then
			add_bit(math.random(0,1))
		else
			local v=get_bit()
			bs:add_bits(v,1)
		end
		cur_bit=cur_bit+1
		if cur_bit >= 8*4 then
			x=x+1
			if x>=w then
				y=y+1
				x=sx
			end
			cur_bit=0
			get_pixel()
		end
		--print(bs:size())
	end
	--[[
	for i=1,#s,bytes_per_pixel do
		local r,g,b,a=s:byte(i,i+bytes_per_pixel)
		print(x,y,"-->",r,g,b,a)
		if use_alpha then
			img_buf:set4(x,y,r or 0,g or 0,b or 0,a or 0)
		else
			img_buf:set4(x,y,r or 0,g or 0,b or 0,255)
		end
		x=x+1
		if x>=w then
			y=y+1
			x=sx or 0
		end
	end
	]]
	return bs.stream.str
end
function count_bits_per_pixel(masks)
	local ret=0
	for k,v in pairs(masks) do
		local _, count = string.gsub(v, "s", "")
		ret=ret+count
	end
	return ret
end
function serialize_class(loaded_files, cls )
	local str=""
	for k,v in pairs(cls) do
		if type(v)=="function" then
			str=str..get_func_source(loaded_files,v)
		end
	end
	return str
end
function do_stuff(cls)
	print"==================="
	--local src=split_newlines(__get_source())
	--Stuff in a comment() that looks like function
	--[[ stuff in big 
		comment that looks like function def() a end and then call a()
	]]
	--[[
		mask settings:
		*0 fixed 0 bit
		*1 fixed 1 bit
		*? random bit
		*s a bit from string
	]]
	local masks={
		"ssssssss",--r
		"01111sss",--g
		"01111sss",--b
		"11111111",--a
	}

	local loaded_files={}
	--local str=serialize_class(loaded_files,cls)
	str="ABC\nlol123"
	print(str)
	local x=(1+4)/123+math.sin(-3)/((-1)*5)
	print'--------------'
	--print(str)
	print("--------------")
	local bpp=count_bits_per_pixel(masks)
	if bpp == 0 then
		print("Zero bpp!")
		return
	end
	local pixel_count=(#str*8)/bpp
	local aspect = 88.9/63.5
	local wsize=math.ceil(math.sqrt(pixel_count/aspect))
	local hsize=aspect*wsize
	print("Size:",#str, " closest size:",wsize,"x",hsize, " size:",wsize*hsize)

	pack_string(str,masks,wsize,hsize,20)
	print("======================================================")
	print(unpack_string(masks,wsize,hsize,20))
end
function clear()
	local s=STATE.size
	print("Clearing:"..s[1].."x"..s[2])
	for x=0,s[1]-1 do
		for y=0,s[2]-1 do
			img_buf:set4(x,y,0,0,0,0)
		end
	end
end
function test_stream(  )
	local sout=bitstream:init("")
	local s=bitstream:init("abcABC")
	local bit_count=1
	print("Stream size:",s:size())
	local r=""
	for i=1,s:size()/bit_count do
		local v=s:get_bits(bit_count)
		r=r..tostring(v).." "
		if i % (8/bit_count)==0 then
			print(r)
			r=""
		end
		sout:add_bits(v,bit_count)
	end
	print("out:"..sout.source_str)
end
function update()
	imgui.Begin("Debug Testing")
	if imgui.Button("Clear image") then
		clear()
	end
	if imgui.Button("stuff") then
		do_stuff(bitstream)
		--test_stream()
	end
	if imgui.Button("Save image") then
		image_no= image_no or 0
		img_buf:save("saved_"..image_no..".png")
		image_no=image_no+1
	end
	imgui.End()
	img_buf:present()
end