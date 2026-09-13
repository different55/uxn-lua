local Device = require("device")

local mouse = Device:new()
mouse.name = "mouse"
mouse:addPort(2, true)
mouse:addPort(4, true)
mouse:addPort(6, false)
mouse:addPort(7, false)

return mouse
