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
		-- カーソル位置のパネルと上隣のパネルを交換する.
		board:swapCells(0, -1)
	elseif pd.buttonJustPressed(pd.kButtonB) then
		local eraseList = board:checkEraseList()
		print("消すリストの数: " .. #eraseList.groups)
		for groupIndex, group in ipairs(eraseList.groups) do
			print(string.format("グループ %d のセル数: %d", groupIndex, #group.indices))
			for _, index in ipairs(group.indices) do
				local pos = board:convertIndexToPosition(index)
				print(string.format("  消す位置: (%d, %d)", pos.x, pos.y))
			end
		end
		if #eraseList.groups > 0 then
			-- 消去実行.
			board:eraseByList(eraseList)
		else
			-- 新しいブロックを出現.
			board:slideUpNewRow()
		end
	end	

	-- 盤面の更新と描画.
	board:update()
    board:draw()

	-- FPS.
    playdate.drawFPS(4, 4)
	-- カーソル位置の描画。
	playdate.graphics.drawText(string.format("Cursor: (%d, %d)", board.cursorX, board.cursorY), 4, 20)
end
