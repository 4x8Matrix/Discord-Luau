print("j")
local Buffer = {}

Buffer.Type = "Buffer"

Buffer.Internal = {}
Buffer.Prototype = {
	Internal = Buffer.Internal,
}
Buffer.Interface = {
	Internal = Buffer.Internal,
}

function Buffer.Prototype:Flush()
	local data = self.Data

	self.Data = ""

	return data
end

function Buffer.Prototype:Add(data)
	self.Data ..= data
end

function Buffer.Prototype:ToString()
	return `{Buffer.Type}<"{self.Data}">`
end

function Buffer.Interface.new()
	return setmetatable({
		Data = ""
	}, {
		__index = Buffer.Prototype,
		__type = Buffer.Type,
		__tostring = function(self)
			return self:ToString()
		end,
	})
end

print("ret buffer!")

return Buffer.Interface
