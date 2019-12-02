require "common"
function compare_images( i1,i2 )
	local w=i1.w
	local h=i1.h
	if w~=i2.w or h~=i2.h then
		error("Sizes do not match!")
	end
	local diff_sum=0
	for x=0,w-1 do
	for y=0,h-1 do
		local p1=i1:get(x,y)
		local p2=i2:get(x,y)
		local r=p1.r-p2.r
		local g=p1.g-p2.g
		local b=p1.b-p2.b
		diff_sum=diff_sum+r*r+g*g+b*b
	end
	end
	return math.sqrt(diff_sum)/(w*h)
end
output_data=output_data or {}
function calculate_delta( start_id )
	output_data={}
	start_id=start_id or 1
	local start_img
	local cur_id=start_id
	repeat
	 	start_img=load_png(string.format("video/saved (%d).png",cur_id))
	 	print(cur_id)
	 	output_data[cur_id]=0
	 	cur_id=cur_id+1
	 	if cur_id>start_id+100 then
	 		error("start not found!")
	 	end
	until (start_img.w~=0)
	--print("Start found at:",cur_id-1)
	local min_v=math.huge
	local min_idx=0
	local test_img
	local skip_count=cur_id+25
	repeat
		test_img=load_png(string.format("video/saved (%d).png",cur_id))
	 	if test_img.w~=0 then
		 	local v=compare_images(start_img,test_img)
		 	if cur_id>skip_count then
			 	if v<min_v then
			 		min_v=v
			 		min_idx=cur_id
			 		--print("New min:",cur_id,v)
			 	else
			 		--print("Bigger:",cur_id,v)
			 	end
		 	end
		 	output_data[cur_id]=v
		 	cur_id=cur_id+1
		end
	until (test_img.w==0)
	print("Min difference:",start_id,min_idx,min_v)
	local f=io.open("out_log.txt","w")
	for i,v in ipairs(output_data) do
		f:write(string.format("%d\t%g\n",i,v))
	end
	f:close()
end
function update(  )
	imgui.Begin("LoopFinder")
	if imgui.Button("Cacl delta") then
		--for i=1,180 do
			calculate_delta()
		--end
	end
	imgui.End()
end