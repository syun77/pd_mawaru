---@diagnostic disable
import "CoreLibs/graphics"
import "CoreLibs/object" -- classを使うために必要.
import "CoreLibs/sprites" -- spriteを使うために必要.
import "game_context"
import "board"

local pd <const> = playdate
local gfx <const> = pd.graphics

local gameContext = GameContext.getInstance()
gameContext:setup()

local board = Board()

function playdate.update()
    gfx.clear(gfx.kColorWhite)

    gfx.setColor(gfx.kColorBlack)

	-- カーソルの移動.
	if pd.buttonJustPressed(pd.kButtonUp) then
		board:moveCursorUp()
	elseif pd.buttonJustPressed(pd.kButtonDown) then
		board:moveCursorDown()
	elseif pd.buttonJustPressed(pd.kButtonLeft) then
		board:moveCursorLeft()
	elseif pd.buttonJustPressed(pd.kButtonRight) then
		board:moveCursorRight()
	elseif pd.buttonJustPressed(pd.kButtonA) then
	end	

    board:draw()

	-- FPS.
    playdate.drawFPS(4, 4)
	-- カーソル位置の描画。
	playdate.graphics.drawText(string.format("Cursor: (%d, %d)", board.cursorX, board.cursorY), 4, 20)
end
