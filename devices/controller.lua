local Device = require("device")

local controller = Device:new()
controller.name = "controller"
controller:addPort(2, false)
controller:addPort(3, false)

return controller
