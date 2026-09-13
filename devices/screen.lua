local bit = require("bit")
local Device = require("device")

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local ONE_BPP_PALETTE = {
	[0] = { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 },
	{ 1, 0 }, { "none", 1 }, { 1, 2 }, { 1, 3 },
	{ 2, 0 }, { 2, 1 }, { "none", 2 }, { 2, 3 },
	{ 3, 0 }, { 3, 1 }, { 3, 2 }, { "none", 3 },
}

local TWO_BPP_PALETTE = {
	[0] = { 0, 0, 1, 2 }, { 0, 1, 2, 3 }, { 0, 2, 3, 1 }, { 0, 3, 1, 2 },
	{ 1, 0, 1, 2 }, { "none", 1, 2, 3 }, { 1, 2, 3, 1 }, { 1, 3, 1, 2 },
	{ 2, 0, 1, 2 }, { 2, 1, 2, 3 }, { "none", 2, 3, 1 }, { 2, 3, 1, 2 },
	{ 3, 0, 1, 2 }, { 3, 1, 2, 3 }, { 3, 2, 3, 1 }, { "none", 3, 1, 2 },
}

local function getBit(value, index)
	return rshift(band(value, lshift(1, index)), index)
end

return function(width, height)
	local screen = Device:new()
	screen.name = "screen"
	screen.back = love.graphics.newCanvas(width, height)
	screen.front = love.graphics.newCanvas(width, height)

	love.graphics.setCanvas(screen.back)
	love.graphics.clear(0, 0, 0, 1)
	love.graphics.setCanvas(screen.front)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.setCanvas()
	screen.back:setFilter("nearest", "nearest")
	screen.front:setFilter("nearest", "nearest")

	screen:addPort(2, true, function()
		return width
	end)
	screen:addPort(4, true, function()
		return height
	end)
	screen:addPort(6, false, nil, function(self, byte)
		self.auto_x = band(byte, 0x01) ~= 0
		self.auto_y = band(byte, 0x02) ~= 0
		self.auto_addr = band(byte, 0x04) ~= 0
	end)
	screen:addPort(8, true)
	screen:addPort(10, true)
	screen:addPort(12, true)

	screen:addPort(14, false, nil, function(self, pixel)
		local layer = band(pixel, 0x40) == 0 and self.back or self.front
		local index = band(pixel, 0x03)
		local alpha = index == 0 and layer == self.front and 0 or 1

		love.graphics.setBlendMode("replace", "premultiplied")
		love.graphics.setCanvas(layer)
		love.graphics.setColor(index / 4.0, 0, 0, alpha)
		local x, y = self:readShort(8), self:readShort(10)
		love.graphics.points(x + 0.5, y + 0.5)
		love.graphics.setCanvas()

		if self.auto_x then self:writeShort(8, x + 1) end
		if self.auto_y then self:writeShort(10, y + 1) end
	end)

	screen:addPort(15, false, nil, function(self, spriteByte)
		local spriteMode = getBit(spriteByte, 7)
		local layer = band(spriteByte, 0x40) == 0 and self.back or self.front
		local verticalFlip = band(spriteByte, 0x20) ~= 0
		local horizontalFlip = band(spriteByte, 0x10) ~= 0
		local x, y = self:readShort(8), self:readShort(0x0a)
		local spriteAddr = self:readShort(0x0c)
		local palette = (spriteMode == 0 and ONE_BPP_PALETTE or TWO_BPP_PALETTE)[band(spriteByte, 0x0f)]
		local points = {}

		love.graphics.setCanvas(layer)
		for i = 0, 7 do
			local rowAddr = verticalFlip and 7 - i or i
			local row = self.cpu:peek_byte(spriteAddr + rowAddr)
			local row2 = spriteMode == 1 and self.cpu:peek_byte(spriteAddr + rowAddr + 8)

			for j = 0, 7 do
				local bitAddr = horizontalFlip and j or 7 - j
				local value = getBit(row, bitAddr)
				if spriteMode == 1 then
					value = bor(lshift(getBit(row2, bitAddr), 1), value)
				end
				local colourIndex = palette[value + 1]
				if colourIndex ~= "none" then
					local alpha = colourIndex == 0 and layer == self.front and 0 or 1
					points[#points + 1] = { x + j + 0.5, y + i + 0.5, colourIndex / 4.0, 0, 0, alpha }
				end
			end
		end

		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.setBlendMode("replace", "premultiplied")
		love.graphics.points(points)
		love.graphics.setCanvas()
		love.graphics.setBlendMode("alpha")

		if self.auto_x then self:writeShort(8, x + 8) end
		if self.auto_y then self:writeShort(10, y + 8) end
		if self.auto_addr then self:writeShort(0x0c, spriteAddr + 8 + (8 * spriteMode)) end
	end)

	return screen
end
