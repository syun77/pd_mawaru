---@diagnostic disable
import "CoreLibs/object"
import "CoreLibs/graphics"

local pd <const> = playdate
local gfx <const> = pd.graphics

class("TitleScene").extends()

local MODE_ITEMS = {
	{
		id = "endless",
		nameKey = "mode_endless_name",
		descKey = "mode_endless_desc",
	},
	{
		id = "puzzle",
		nameKey = "mode_puzzle_name",
		descKey = "mode_puzzle_desc",
	}
}

local CRANK_ROTATE_VALUE = 8

local function isMovePrev()
	if pd.buttonJustPressed(pd.kButtonUp) or pd.buttonJustPressed(pd.kButtonLeft) then
		return true
	end
	if not pd.isCrankDocked() then
		return pd.getCrankChange() < -CRANK_ROTATE_VALUE
	end
	return false
end

local function isMoveNext()
	if pd.buttonJustPressed(pd.kButtonDown) or pd.buttonJustPressed(pd.kButtonRight) then
		return true
	end
	if not pd.isCrankDocked() then
		return pd.getCrankChange() > CRANK_ROTATE_VALUE
	end
	return false
end

function TitleScene:init(onSelectMode)
	self.onSelectMode = onSelectMode
	self.selectedIndex = 1
	self.frameCount = 0
end

function TitleScene:enter()
	self.frameCount = 0
end

function TitleScene:update()
	self.frameCount += 1

	if isMovePrev() then
		self.selectedIndex -= 1
		if self.selectedIndex < 1 then
			self.selectedIndex = #MODE_ITEMS
		end
	elseif isMoveNext() then
		self.selectedIndex += 1
		if self.selectedIndex > #MODE_ITEMS then
			self.selectedIndex = 1
		end
	end

	if pd.buttonJustPressed(pd.kButtonA) then
		local selected = MODE_ITEMS[self.selectedIndex]
		if selected ~= nil and self.onSelectMode ~= nil then
			self.onSelectMode(selected.id)
		end
	end
end

function TitleScene:drawModeItem(item, index, x, y)
	local isSelected = (index == self.selectedIndex)
	local rowHeight = 28
	local top = y + (index - 1) * rowHeight

	if isSelected then
		gfx.fillRect(x, top, 250, rowHeight - 2)
		gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
	end

	gfx.drawText(L(item.nameKey), x + 8, top + 7)

	if isSelected then
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
	end
end

function TitleScene:draw()
	gfx.drawTextAligned("MAWARU", 200, 36, kTextAlignment.center)
	gfx.drawTextAligned(L("title_game_mode_select"), 200, 56, kTextAlignment.center)

	local listX = 74
	local listY = 92
	gfx.drawRoundRect(listX - 8, listY - 8, 266, 74, 6)

	for i = 1, #MODE_ITEMS do
		self:drawModeItem(MODE_ITEMS[i], i, listX, listY)
	end

	local selected = MODE_ITEMS[self.selectedIndex]
	if selected ~= nil then
		gfx.drawTextAligned(L(selected.descKey), 200, 178, kTextAlignment.center)
	end

	if (self.frameCount % 40) < 30 then
		gfx.drawTextAligned(L("ui_confirm"), 200, 208, kTextAlignment.center)
	end
end
