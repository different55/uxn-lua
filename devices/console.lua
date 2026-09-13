local Device = require("device")

local console = Device:new()
console.name = "console"
console.stdout = ""
console.stderr = ""

console:addPort(2, false)
console:addPort(8, false, nil, function(self, byte)
	local character = string.char(byte)
	io.write(character)
	self.stdout = self.stdout .. character
end)
console:addPort(9, false, nil, function(self, byte)
	self.stderr = self.stderr .. string.char(byte)
end)

return console
