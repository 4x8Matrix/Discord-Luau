local WebsocketOperationKeys = require("../Enums/WebsocketOperationKeys")
local WebsocketOperationCodes = require("../Enums/WebsocketOperationCodes")

local State = require("../Dependencies/Github/State")
local Promise = require("../Dependencies/Github/Promise")
local Signal = require("../Dependencies/Github/Signal")
local Console = require("../Dependencies/Github/Console")
print(1)
local Provider = require("../Dependencies/Provider")
print(2)
local Buffer = require("../Dependencies/Buffer")
print(3)
local Net = require("@lune/net")
local Serde = require("@lune/serde")
local Task = require("@lune/task")

local ZLIB_SUFFIX_START = "\120"
local ZLIB_SUFFIX_END = "\84"

local SERDE_NULL_USERDATA = Serde.decode("json", "[null]")[1]

local DiscordWebsocket = {}

DiscordWebsocket.Type = "DiscordWebsocket"

DiscordWebsocket.Internal = {}
DiscordWebsocket.Interface = {}
DiscordWebsocket.Prototype = {
	Internal = DiscordWebsocket.Internal,
}

function DiscordWebsocket.Prototype:RecursiveReplaceTableValue(table, oldValue, newValue)
	for index, value in table do
		if value == oldValue then
			table[index] = newValue
		elseif type(value) == "table" then
			self:RecursiveReplaceTableValue(value, oldValue, newValue)
		end
	end
end

function DiscordWebsocket.Prototype:SendAsync(dataPacket)
	return Promise.new(function(resolve, reject)
		local messageSendOperationSuccessful, messageResult =
			pcall(self.SocketInstance.send, Serde.encode("json", dataPacket))

		if messageSendOperationSuccessful then
			self.Reporter:Debug(`Discord Websocket Message Sent: {dataPacket[WebsocketOperationKeys.OperationCode]}`)

			resolve()
		else
			reject(messageResult)
		end
	end)
end

function DiscordWebsocket.Prototype:ConnectAsync(websocketUrl)
	return Promise.new(function(resolve, reject)
		self.SocketRequestSuccess, self.SocketInstance = pcall(Net.socket, websocketUrl)

		if not self.SocketRequestSuccess then
			return reject(self.SocketInstance)
		end

		self.WebsocketActive:Set(true)
		self.WebsocketThread = Task.spawn(function()
			resolve()

			while self.WebsocketActive.Value do
				if self.SocketInstance.closeCode then
					self.WebsocketActive:Set(false)
					self.OnSocketDead:Fire(self.SocketInstance.closeCode)
				else
					local websocketMessage = self.SocketInstance.next()

					if not websocketMessage then
						self.WebsocketActive:Set(false)
						self.OnSocketDead:Fire(self.SocketInstance.closeCode)

						continue
					end

					self.OnMessageRecv:Fire(websocketMessage)
				end
			end
		end)
	end)
end

function DiscordWebsocket.Prototype:DisconnectAsync(closingCode)
	return Promise.new(function(resolve)
		if not self.SocketInstance then
			return resolve()
		end

		self.SocketInstance.close(closingCode)

		self.WebsocketActive:Set(false)
		self.OnSocketDead:Fire(closingCode)

		resolve()
	end)
end

function DiscordWebsocket.Prototype:ToString()
	return `{DiscordWebsocket.Type}<"{self.WebsocketActive.Value and "ONLINE" or "OFFLINE"}">`
end

function DiscordWebsocket.Interface.new(discordClient)
	local self = setmetatable({
		WebsocketActive = State.new(false),
		WebsocketBuffer = Buffer.new(),

		OnMessageRecv = Signal.new(),
		OnSocketDead = Signal.new(),

		Reporter = Console.new("DiscordWebsocket"),

		OperationProvider = Provider.new(),

		DiscordClient = discordClient,
	}, {
		__index = DiscordWebsocket.Prototype,
		__type = DiscordWebsocket.Type,
		__tostring = function(object)
			return object:ToString()
		end,
	})

	self.WebsocketActive:Observe(function(_, state)
		self.Reporter:Debug(`Discord Websocket {(state and "Connected") or "Disconnected"}!`)
	end)

	self.OnMessageRecv:Connect(function(discordPacket)
		local isJSON, dataPacket = pcall(Serde.decode, "json", discordPacket)

		if not isJSON then
			self.WebsocketBuffer:Add(discordPacket)

			if string.sub(discordPacket, 1, 1) ~= ZLIB_SUFFIX_START then
				return
			end

			if string.sub(discordPacket, 4, 4) ~= ZLIB_SUFFIX_END then
				return
			end

			local encodedDiscordPacket = self.WebsocketBuffer:Flush()
			local decodedDiscordPacket = Serde.decompress("zlib", encodedDiscordPacket)

			dataPacket = Serde.decode("json", decodedDiscordPacket)
		end

		self:RecursiveReplaceTableValue(dataPacket, SERDE_NULL_USERDATA, nil)

		if dataPacket[WebsocketOperationKeys.OperationCode] == WebsocketOperationCodes.Dispatch then
			self.Reporter:Debug(`Discord Websocket Message Received: {dataPacket[WebsocketOperationKeys.OperationCode]} - {dataPacket[WebsocketOperationKeys.EventName]}`)
		else
			self.Reporter:Debug(`Discord Websocket Message Received: {dataPacket[WebsocketOperationKeys.OperationCode]}`)
		end

		self.OperationProvider:InvokeObservers(
			dataPacket[WebsocketOperationKeys.OperationCode],
			dataPacket[WebsocketOperationKeys.Data],
			dataPacket[WebsocketOperationKeys.EventName],
			dataPacket[WebsocketOperationKeys.Sequence]
		)
	end)

	return self
end

return DiscordWebsocket.Interface
