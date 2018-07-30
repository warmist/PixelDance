--[[ Example:
imgui_config=make_config{
	{"debug_display",false},
	{"complexity",0.5,type="float"}, --implied min=0,max=1
	{"shapes","3"},
	{"w",3,type="int",min=1,max=5},
}

Begin
End
Bullet
BulletText
RadioButton
CollapsingHeader
SliderFloat
SliderAngle
SliderInt
InputText
]]
function make_config(tbl,defaults)
	local ret={}
	defaults=defaults or {}
	for i,v in ipairs(tbl) do
		ret[v[1]]=defaults[v[1]] or v[2]
		ret[i]=v
	end
	return ret
end

img_buf=img_buf or buffers.Make("color")
tick=tick or 0
config=make_config({
	{"color",{0.5,0,0,1},type="color"},
	{"k",0.2,type="float"},
	{"l",0.4,type="float"},
	{"R",400,type="int",min=0,max=512},
	{"ticking",100,type="float",min=1,max=10000},
},config)

function draw_config( tbl )
	for _,entry in ipairs(tbl) do
		local name=entry[1]
		local v=tbl[name]
		local k=name
		if type(v)=="boolean" then
			if imgui.Button(k) then
				tbl[k]=not tbl[k]
			end
		elseif type(v)=="string" then
			local changing
			changing,tbl[k]=imgui.InputText(k,tbl[k])
			entry.changing=changing
		else --if type(v)~="table" then
			
			if entry.type=="int" then
				local changing
				changing,tbl[k]=imgui.SliderInt(k,tbl[k],entry.min or 0,entry.max or 100)
				entry.changing=changing
			elseif entry.type=="float" then
				local changing
				changing,tbl[k]=imgui.SliderFloat(k,tbl[k],entry.min or 0,entry.max or 1)
				entry.changing=changing
			elseif entry.type=="angle" then
				local changing
				changing,tbl[k]=imgui.SliderAngle(k,tbl[k],entry.min or 0,entry.max or 360)
				entry.changing=changing
			elseif entry.type=="color" then
				local changing
				changing,tbl[k]=imgui.ColorEdit4(k,tbl[k],true)
				entry.changing=changing
			end
		
		end
	end
end
function pos( t )
	local k=config.k
	local l=config.l
	return config.R*((1-k)*math.cos(t)+l*k*math.cos(((1-k)/k)*t)),
		   config.R*((1-k)*math.sin(t)-l*k*math.sin(((1-k)/k)*t))
end
function update(  )
	imgui.Begin("Hello")
	
	draw_config(config)
	local c_u8={config.color[1]*255,config.color[2]*255,config.color[3]*255,config.color[4]*255}
	if imgui.Button("Clear image") then
		local s=STATE.size
		for x=0,s[1]-1 do
			for y=0,s[2]-1 do
				img_buf:set(x,y,{0,0,0,0})
			end
		end
	end
	imgui.End()
	for i=1,config.ticking do
		local x,y=pos(tick/config.ticking);
		img_buf:set(x+512,y+512,c_u8)
		tick=tick+1
	end
	buffers.Present(img_buf)
end