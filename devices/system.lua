local bit = require("bit")
local Device = require("device")

local system = Device:new()
system.name = "system"

system.palette = {
	[0] = { 0, 0, 0 },
	{ 1, 0, 0 },
	{ 0, 1, 0 },
	{ 0, 0, 1 },
}

local function regeneratePalette(self)
	local r, g, b = self:readShort(8), self:readShort(10), self:readShort(12)
	r, g, b = bit.tohex(r, 4), bit.tohex(g, 4), bit.tohex(b, 4)

	for i = 0, 3 do
		local colour = {
			string.sub(r, i + 1, i + 1),
			string.sub(g, i + 1, i + 1),
			string.sub(b, i + 1, i + 1),
		}

		self.palette[i] = {
			tonumber(colour[1], 16) / 0xf,
			tonumber(colour[2], 16) / 0xf,
			tonumber(colour[3], 16) / 0xf,
		}
	end

	paletteShader:send("palette", self.palette[0], self.palette[1], self.palette[2], self.palette[3])
end

local function parseMetadata(self)
	local metadata = self:readShort(0x06)
	if self.cpu:peek_byte(metadata) ~= 0x00 then
		return -- Only metadata version 0x00 is supported.
	end

	local text = {}
	for address = metadata + 1, metadata + 0xff do
		local byte = self.cpu:peek_byte(address)
		if byte == 0 then
			break
		end
		text[#text + 1] = string.char(byte)
	end

	local title = table.concat(text):gsub("\n", " / ")
	love.window.setTitle(title)
end

system.initColours = false

system:addPort(0x02, true, nil, function(self)
	local addr = self:readShort(0x02)
	local mem = self.cpu.memory
	local op = mem[addr]
	local length = self.cpu:peek_short(addr + 1)

	if op == 0x00 then
		local bank = self.cpu.banks[self.cpu:peek_short(addr + 3)]
		local start = self.cpu:peek_short(addr + 5)
		local value = self.cpu:peek_byte(addr + 7)
		length = math.min(length, math.max(0, 0x10000 - start))

		for i = 0, length - 1 do
			bank[start + i] = value
		end
	elseif op == 0x01 then
		local src_bank = self.cpu.banks[self.cpu:peek_short(addr + 3)]
		local src_addr = self.cpu:peek_short(addr + 5)
		local dst_bank = self.cpu.banks[self.cpu:peek_short(addr + 7)]
		local dst_addr = self.cpu:peek_short(addr + 9)
		length = math.min(length, math.max(0, 0x10000 - src_addr), math.max(0, 0x10000 - dst_addr))

		for i = 0, length - 1 do
			dst_bank[dst_addr + i] = src_bank[src_addr + i]
		end
	elseif op == 0x02 then
		local src_bank = self.cpu.banks[self.cpu:peek_short(addr + 3)]
		local src_addr = self.cpu:peek_short(addr + 5)
		local dst_bank = self.cpu.banks[self.cpu:peek_short(addr + 7)]
		local dst_addr = self.cpu:peek_short(addr + 9)
		length = math.min(length, math.max(0, 0x10000 - src_addr), math.max(0, 0x10000 - dst_addr))

		for i = length - 1, 0, -1 do
			dst_bank[dst_addr + i] = src_bank[src_addr + i]
		end
	end
end)

system:addPort(0x04, false, function(self)
	return self.cpu.program_stack:len()
end)
system:addPort(0x05, false, function(self)
	return self.cpu.return_stack:len()
end)
system:addPort(0x06, true, nil, parseMetadata)
system:addPort(0x08, true, nil, regeneratePalette)
system:addPort(0x0a, true, nil, regeneratePalette)
system:addPort(0x0c, true, nil, regeneratePalette)
system:addPort(0x0e, false, nil, function(self)
	io.stderr:write("WST" .. self.cpu.program_stack:debug())
	io.stderr:write("RST" .. self.cpu.return_stack:debug())
end)
system:addPort(0x0f, false, nil, function(self, byte)
	self.cpu.state = byte
end)

return system
