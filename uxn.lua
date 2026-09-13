local bit = require("bit")
local math = require("math")

local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local arshift, rshift, lshift = bit.arshift, bit.rshift, bit.lshift

local function uint8_to_int8(byte)
	byte = band(byte, 0xff)
	if band(byte, 0x80) ~= 0 then
		byte = byte - 0x100
	end

	return byte
end

local Stack = {}

Stack.__index = Stack

function Stack:new(limit)
	local limit = limit or 256
	local stack = setmetatable({
		limit = limit,
		head = 0,
	}, self)

	for i = 0, limit - 1 do
		stack[i] = 0
	end

	return stack
end

function Stack:push(byte)
	local head = band(self.head + 1, 0xff)
	self[head] = byte
	self.head = head
end

function Stack:pop()
	local head = self.head
	local byte = self[head]
	self.head = band(head - 1, 0xff)
	return byte
end

-- 0-indexed non-destructive get
function Stack:getnth(n)
	return self[band(self.head - n, 0xff)]
end

function Stack:len()
	return self.head
end

function Stack:setlen(index)
	self.head = band(index, 0xff)
end

function Stack:debug()
	local t = { band(self.head - 8, 0xff) > 0 and " " or "|" }
	for i = self.head - 7, self.head do
		t[#t + 1] = bit.tohex(self[band(i, 0xff)], 2) .. ((band(i, 0xff) == 0x00) and "|" or " ")
	end
	t[#t + 1] = "<" .. self.head .. "\n"
	return table.concat(t, "")
end

local Memory = {
	__index = function(self, k)
		if type(k) == "number" then
			return rawget(self, band(k, 0xffff)) or 0
		end
	end,
	__newindex = function(self, k, v)
		if type(k) == "number" then
			rawset(self, band(k, 0xffff), v)
		end
	end,
}

local Banks = {
	__index = function(self, k)
		if type(k) == "number" then
			local bank = rawget(self, band(k, 0xffff))
			if bank then
				return bank
			else
				self[band(k, 0xffff)] = setmetatable({}, Memory)
				return self[band(k, 0xffff)]
			end
		end
	end,
}

local Uxn = {}

Uxn.__index = Uxn

function Uxn:new(mem)
	local memory = setmetatable(mem or {}, Memory)
	return setmetatable({
		ip = 1,
		program_stack = Stack:new(),
		return_stack = Stack:new(),
		memory = memory,
		banks = setmetatable({ [0] = memory }, Banks),
		devices = {},
		vectors = {},
		state = 0,
		-- DEBUG TABLES
		debug_profile = {},
		device_triggers = {}, -- Debug
		device_reads = {}, -- DEBUG
		device_writes = {}, -- DEBUG
	}, self)
end

function Uxn:profile(...)
	local name = table.concat({ ... }, "_")
	self.debug_profile[name] = (self.debug_profile[name] or 0) + 1
end

function Uxn:print_profile()
	local output = "name\t\tcount\n"
	for k, v in pairs(self.debug_profile) do
		output = output .. k .. "\t\t" .. v .. "\n"
	end
	return output
end

function Uxn:peek_byte(address, bank)
	bank = bank or 0
	return self.banks[bank][address]
end

function Uxn:poke_byte(value, address, bank)
	bank = bank or 0
	self.banks[bank][address] = band(value, 0xFF)
end

function Uxn:peek_short(address, bank)
	bank = bank or 0
	return bytes_to_short(self.banks[bank][address], self.banks[bank][address + 1])
end

function Uxn:poke_short(value, address, bank)
	bank = bank or 0
	local high, low = shorts_to_bytes({ band(value, 0xffff) })
	self.banks[bank][address] = high
	self.banks[bank][address + 1] = low
end

function Uxn:load_program(program)
	for i = 1, #program do
		local offset = 0x100 + i - 1
		local bank = math.floor(offset / 0x10000)
		local address = offset % 0x10000
		self:poke_byte(program[i], address, bank)
	end
end

function bytes_to_shorts(bytes)
	local shorts = {}
	for i = 1, #bytes, 2 do
		local high_byte = bytes[i]
		local low_byte = bytes[i + 1]
		shorts[#shorts + 1] = band(lshift(high_byte, 8) + low_byte, 0xffff)
	end
	return shorts
end

function bytes_to_short(high, low)
	if not low then
		low = high[2]
		high = high[1]
	end
	return band(lshift(high, 8) + low, 0xffff)
end

function shorts_to_bytes(shorts)
	local bytes = {}

	for i = 1, #shorts do
		local short = shorts[i]
		local high_byte = rshift(short, 8)
		-- Mask out the low byte
		local low_byte = band(short, 0xff)
		bytes[#bytes + 1] = high_byte
		bytes[#bytes + 1] = low_byte
	end

	return bytes
end

function Uxn:get_n(n, keep_bit, return_bit, short_bit)
	-- Choose which stack to operate on
	local stack = return_bit and self.return_stack or self.program_stack

	-- Fetch 2 bytes for each number needed
	if short_bit then
		n = n * 2
	end

	local output = {}

	for i = 1, n do
		if keep_bit then
			output[(n - i) + 1] = stack:getnth(i - 1)
		else
			output[(n - i) + 1] = stack:pop()
		end
	end

	if short_bit then
		output = bytes_to_shorts(output)
	end

	return output
end

function Uxn:push(value, k, r, s)
	local stack = r and self.return_stack or self.program_stack

	if s then
		stack:push(band(rshift(value, 8), 0xff))
	end
	stack:push(band(value, 0xff))
end

function Uxn:pop(k, r, s)
	local stack = r and self.return_stack or self.program_stack
	local value
	if k then
		local offset = self.peek_offset
		if s then
			local low = stack:getnth(offset)
			local high = stack:getnth(offset + 1)
			value = low and high and bytes_to_short(high, low)
			offset = offset + 2
		else
			value = stack:getnth(offset)
			offset = offset + 1
		end
		self.peek_offset = offset
	else
		if s then
			local low = stack:pop()
			local high = stack:pop()
			value = low and high and bytes_to_short(high, low)
		else
			value = stack:pop()
		end
	end
	return value
end

local function extractOpcode(byte)
	local keep_bit = band(byte, 0x80) ~= 0 -- 0b1000 0000
	local return_bit = band(byte, 0x40) ~= 0 -- 0b0100 0000
	local short_bit = band(byte, 0x20) ~= 0 -- 0b0010 0000

	local opcode = band(byte, 0x1f) -- 0b0001 1111

	return opcode, keep_bit, return_bit, short_bit
end

function Uxn:device_read(addr, k, r, s)
	local device_num = rshift(addr, 4)
	local device = self.devices[device_num]

	if device then
		self.device_reads[device_num] = (self.device_reads[device_num] or 0) + 1
		local port = band(addr, 0x0f)

		local value
		if s then
			value = device:readShort(port)
		else
			value = band(device[port], 0xff)
		end

		return value
	else
		return 0
	end
end

function Uxn:device_write(addr, value, k, r, s)
	local device_num = rshift(addr, 4)
	local device = self.devices[device_num]

	local port_num = band(addr, 0x0f)

	if device then
		--self:profile("DEO", device_num, port_num)
		self.device_writes[device_num] = (self.device_writes[device_num] or 0) + 1
		if self.PRINT then
			print("wrote", bit.tohex(value), "to", bit.tohex(addr))
		end

		if s then
			device:writeShort(port_num, value)
		else
			device[port_num] = value
		end
	end
end

function Uxn:addDevice(device_num, device)
	if self.devices[device_num] then
		error("Device already exists at ", bit.tohex(device_num))
	end

	device.cpu = self
	device.device_num = device_num

	self.devices[device_num] = device

	return device
end

function Uxn:triggerDevice(device_num)
	local vector = self.vectors[device_num]
	--local vector = self.devices[device_num]:readShort(0)
	if vector then
		self.device_triggers[device_num] = (self.device_triggers[device_num] or 0) + 1
		self.ip = vector
		return self:runUntilBreak()
	end
end

local opNames = {
	[0] = "LIT",
	"INC",
	"POP",
	"DUP",
	"NIP",
	"SWAP",
	"OVER",
	"ROT",

	"EQU",
	"NEQ",
	"GTH",
	"LTH",
	"JMP",
	"JCN",
	"JSR",
	"STASH",

	"LDZ",
	"STZ",
	"LDR",
	"STR",
	"LDA",
	"STA",
	"DEI",
	"DEO",

	"ADD",
	"SUB",
	"MUL",
	"DIV",
	"AND",
	"OR",
	"XOR",
	"SHIFT",
}

local opTable = {
	-- STACK
	--
	-- 0x00 BRK/LIT
	function(self, k, r, s)
		if k then
			local value
			if s then
				value = self:peek_short(self.ip)
			else
				value = self:peek_byte(self.ip)
			end
			if self.PRINT then
				print("Push " .. (s and "short" or "byte") .. " value = ", bit.tohex(value))
			end
			self:push(value, k, r, s)
			self.ip = self.ip + (s and 2 or 1)
		else
			local addr = self:peek_short(self.ip)
			-- 0x20 JCI
			if s and not r then
				local flag = self:pop(false, false, false)
				if flag ~= 0 then
					self.ip = band(self.ip + 2 + addr, 0xffff)
				else
					self.ip = band(self.ip + 2, 0xffff)
				end
			elseif r and not s then
				self.ip = band(self.ip + 2 + addr, 0xffff)
			elseif s and r then
				self:push(self.ip + 2, false, true, true)
				self.ip = band(self.ip + 2 + addr, 0xffff)
			end
		end
	end,

	-- 0x01 INC
	function(self, k, r, s)
		local a = self:pop(k, r, s)
		self:push(a + 1, k, r, s)
	end,

	-- 0x02 POP
	function(self, k, r, s)
		self:pop(k, r, s)
	end,

	-- 0x03 NIP
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		self:pop(k, r, s)
		self:push(b, k, r, s)
	end,

	-- 0x04 SWAP
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(b, k, r, s)
		self:push(a, k, r, s)
	end,

	-- 0x05 ROT
	function(self, k, r, s)
		local c = self:pop(k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(b, k, r, s)
		self:push(c, k, r, s)
		self:push(a, k, r, s)
	end,

	-- 0x06 DUP
	function(self, k, r, s)
		local a = self:pop(k, r, s)
		self:push(a, k, r, s)
		self:push(a, k, r, s)
	end,

	-- 0x07 OVER
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(a, k, r, s)
		self:push(b, k, r, s)
		self:push(a, k, r, s)
	end,

	-- LOGIC
	--
	-- 0x08 EQU
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		-- Push the flag as a single byte, so short mode is false in Uxn:push
		self:push(a == b and 1 or 0, k, r, false)
	end,

	-- 0x09 NEQ
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(a ~= b and 1 or 0, k, r, false)
	end,

	-- 0x0a GTH
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(a > b and 1 or 0, k, r, false)
	end,

	-- 0x0b LTH
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(a < b and 1 or 0, k, r, false)
	end,

	-- 0x0c JMP
	function(self, k, r, s)
		local addr = self:pop(k, r, s)
		if not s then
			-- relative jump
			addr = uint8_to_int8(addr) + self.ip
		end

		self.ip = addr
	end,

	-- 0x0d JCN
	function(self, k, r, s)
		local addr = self:pop(k, r, s)
		local flag = self:pop(k, r, false)

		if flag ~= 0 then
			if not s then
				addr = self.ip + uint8_to_int8(addr)
			end

			self.ip = addr
		end
	end,

	-- 0x0e JSR
	function(self, k, r, s)
		local addr = self:pop(k, r, s)
		if not s then
			addr = uint8_to_int8(addr) + self.ip
		end

		-- Stash
		self:push(self.ip, k, not r, true)

		self.ip = addr
	end,

	-- 0x0f STH
	function(self, k, r, s)
		local a = self:pop(k, r, s)
		self:push(a, k, not r, s)
	end,

	-- MEMORY
	--
	-- 0x10 LDZ
	function(self, k, r, s)
		local offset = self:pop(k, r, false)

		local value = self:peek_byte(offset)

		if s then
			value = bytes_to_short(value, self:peek_byte(band(offset + 1, 0xff)))
		end

		self:push(value, k, r, s)
	end,

	-- 0x11 STZ
	function(self, k, r, s)
		local data = self:get_n(s and 3 or 2, k, r, false)

		local offset = table.remove(data)

		self:poke_byte(data[1], offset)

		if s then
			self:poke_byte(data[2], band(offset + 1, 0xff))
		end
	end,

	-- 0x12 LDR
	function(self, k, r, s)
		local offset = self:pop(k, r, false)

		local addr = uint8_to_int8(offset) + self.ip

		local value = self:peek_byte(addr)

		if s then
			value = self:peek_short(addr)
		end

		self:push(value, k, r, s)
	end,

	-- 0x13 STR
	function(self, k, r, s)
		local data = self:get_n(s and 3 or 2, k, r, false)

		local address = uint8_to_int8(table.remove(data)) + self.ip

		self:poke_byte(data[1], address)

		if s then
			self:poke_byte(data[2], address + 1)
		end
	end,

	-- 0x14 LDA
	function(self, k, r, s)
		local addr = self:pop(k, r, true)

		local value = self:peek_byte(addr)

		if s then
			value = self:peek_short(addr)
		end

		self:push(value, k, r, s)
	end,

	-- 0x15 STA
	function(self, k, r, s)
		local data = self:get_n(s and 4 or 3, k, r, false)

		local address = bytes_to_short(data[#data - 1], data[#data])

		self:poke_byte(data[1], address)

		if s then
			self:poke_byte(data[2], address + 1)
		end
	end,

	-- 0x16 DEI
	function(self, k, r, s)
		local offset = self:pop(k, r, false)
		self:push(self:device_read(offset, k, r, s), k, r, s)
	end,

	-- 0x17 DEO
	function(self, k, r, s)
		local address = self:pop(k, r, false)
		local value = self:pop(k, r, s)

		self:device_write(address, value, k, r, s)
	end,

	-- ARITHMETIC
	--
	-- 0x18 ADD
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(a + b, k, r, s)
	end,

	-- 0x19 SUB
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(a - b, k, r, s)
	end,

	-- 0x1a MUL
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(a * b, k, r, s)
	end,

	-- 0x1b DIV
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		if b == 0 then
			self:push(0, k, r, s)
		else
			self:push(math.floor(a / b), k, r, s)
		end
	end,

	-- 0x1c AND
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(band(a, b), k, r, s)
	end,

	-- 0x1d OR
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(bor(a, b), k, r, s)
	end,

	-- 0x1e EOR
	function(self, k, r, s)
		local b = self:pop(k, r, s)
		local a = self:pop(k, r, s)
		self:push(bxor(a, b), k, r, s)
	end,

	-- 0x1f SFT
	-- "Shift in short mode expects a single byte"
	function(self, k, r, s)
		local amount = self:pop(k, r, false)
		local value = self:pop(k, r, s)

		value = arshift(value, band(amount, 0x0f))
		value = lshift(value, rshift(band(amount, 0xf0), 4))

		self:push(value, k, r, s)
	end,
}

function Uxn:runUntilBreak()
	local count = 0
	local extractOpcode = extractOpcode
	while true do
		local opline
		local opByte = self:peek_byte(self.ip)
		if opByte == 0 then
			break
		end
		if self.PRINT then
			opline = bit.tohex(self.ip)
		end
		self.ip = self.ip + 1

		local opcode, k, r, s = extractOpcode(opByte)
		--self:profile(opNames[opcode])
		if self.PRINT then
			print(opline .. " : " .. opNames[opcode] .. (s and "2" or "") .. (r and "r" or "") .. (k and "k" or ""))
			print("PS", self.program_stack:debug())
			print("RS", self.return_stack:debug())
		end
		-- Reset the peek offset so consective calls to :pop maintain state
		if k then
			self.peek_offset = 0
		end
		opTable[opcode + 1](self, k, r, s)

		count = count + 1
	end

	if self.state ~= 0 then
		local error_code = band(self.state, 0x7F)
		love.event.quit(error_code)
	end

	return count
end

return { Uxn = Uxn, uint8_to_int8 = uint8_to_int8 }
