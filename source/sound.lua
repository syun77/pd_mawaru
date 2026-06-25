---@diagnostic disable

import "CoreLibs/object"

local pd <const> = playdate

-- サウンドテーブル.
local soundTable = {
	"erase",
	"pi",
	"swap",
	"slideup"
}

class('Sound').extends()

function Sound:init()
	Sound.super.init(self)

	self.pool = {}
	for _, soundName in ipairs(soundTable) do
		print("Sound:init() - loading sound: " .. soundName)
		self.pool[soundName] = pd.sound.sample.new("sounds/" .. soundName)
	end
end

function Sound:play(soundName)
	if self.pool[soundName] then
		self.pool[soundName]:play()
	else
		print("Sound:play() - sound '" .. soundName .. "' not found.")
	end
end
