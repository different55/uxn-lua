local bit = require("bit")
local Device = require("device")

local function openFile(self, mode)
	local cpu = self.cpu
	local name_address = self:readShort(8)
	local seek = bit.lshift(self:readShort(4), 16) + self:readShort(6)
	local fileName = ""
	local counter = name_address
	local char

	while char ~= 0x00 do
		char = cpu:peek_byte(counter)
		fileName = fileName .. string.char(char)
		counter = counter + 1
	end

	print("Trying to open file called ", fileName)
	local file = love.filesystem.newFile(fileName)
	local ok = file:open(mode)
	if not ok then
		return nil
	end
	file:seek(seek)
	return file
end

local file = Device:new()
file:addPort(2, true)
file:addPort(4, true)
file:addPort(6, true)
file:addPort(8, true)
file:addPort(10, true)
file:addPort(12, true, nil, function(self)
	local length = self:readShort(10)
	local target_address = self:readShort(12)
	local opened = openFile(self, "r")

	if not opened then
		print("file doesn't exist")
		return self:writeShort(2, 0)
	end

	local contents, real_size = opened:read("data", length)
	print("read", real_size, "bytes")
	self:writeShort(2, bit.band(real_size, 0xffff))

	local dataTable = { love.data.unpack(string.rep("B", real_size), contents) }
	for i = 1, #dataTable - 1 do
		self.cpu:poke_byte(dataTable[i], target_address + i - 1)
	end
end)
file:addPort(14, true, function(self)
	local length = self:readShort(10)
	local target_address = self:readShort(12)
	local opened = openFile(self, "w")

	if not opened then
		print("file can't be opened")
		return self:writeShort(2, 0)
	end

	-- File writing is not implemented yet.
end)

return file
