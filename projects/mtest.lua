require "common"
m33=m33 or make_ident_matrix(3,3)
function rand_mat( m )
	for x=0,m.w-1 do
		for y=0,m.h-1 do
			m:set(x,y,math.random(0,10))
		end
	end
end
function update(  )
	imgui.Begin("MatrixTest")
	if imgui.Button("Do Stuff") then
		print(m33:tostring_full())
		for i=1,10000 do
			local m2=make_matrix(1000,3000)
		end
		
		rand_mat(m2)
		print(m2:tostring_full())
		local m3=make_matrix(3,1)
		rand_mat(m3)
		print(m3:tostring_full())
		local mO=make_matrix(3,3)
		print('==========')
		print("m2 x m3")
		print(matrix.mult(m3,m2))
	end
	imgui.End()
end