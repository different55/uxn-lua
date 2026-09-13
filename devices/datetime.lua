local Device = require("device")

local datetime = Device:new()
datetime.name = "datetime"
datetime:addPort(0, true, function()
	return tonumber(os.date("%Y"))
end)
datetime:addPort(2, false, function()
	return tonumber(os.date("%m")) - 1
end)
datetime:addPort(3, false, function()
	return tonumber(os.date("%d"))
end)
datetime:addPort(4, false, function()
	return tonumber(os.date("%H"))
end)
datetime:addPort(5, false, function()
	return tonumber(os.date("%M"))
end)
datetime:addPort(6, false, function()
	return tonumber(os.date("%S"))
end)
datetime:addPort(7, false, function()
	return tonumber(os.date("%u")) % 7
end)
datetime:addPort(8, true, function()
	return tonumber(os.date("%j")) - 1
end)
datetime:addPort(10, true, function()
	return 0
end)

return datetime
