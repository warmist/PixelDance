for i=1,10 do
	print(i)
end
color={0,0,0,0}

function update(  )
	imgui.Begin("Hello")
	local changed
	changed,color=imgui.ColorEdit3("thing",color)
	imgui.End()
end