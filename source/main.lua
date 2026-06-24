---@diagnostic disable
import "CoreLibs/graphics"
import "CoreLibs/object" -- classを使うために必要.
import "CoreLibs/sprites" -- spriteを使うために必要.
import "game_context"
import "board"
import "beatmachine"

local pd <const> = playdate
local gfx <const> = pd.graphics

BeatMachine.Create()
BeatMachine.LoadBeat("beats/demo.bmf")
BeatMachine.PlayTheBeat(0)

pd.display.setRefreshRate(0) -- 50Hzに設定.

local gameContext = GameContext.getInstance()
gameContext:setup()

local board = Board()

local CRANK_ROTATE_VALUE = 5 -- クランクを回すときの角度の変化量の閾値.

function isJustPressedLeft()
	if pd.isCrankDocked() then
		-- 左ボタン.
		if pd.buttonJustPressed(pd.kButtonLeft) then
			return true
		end
	elseif pd.isCrankDocked() == false then
		-- クランクを左に回した場合.
		local crankChange = pd.getCrankChange()
		if crankChange < -CRANK_ROTATE_VALUE then
			return true
		end
	end	

	return false
end

function isJustPressedRight()
	if pd.isCrankDocked() then
	-- 右ボタン.
		if pd.buttonJustPressed(pd.kButtonRight) then
			return true
		end
	elseif pd.isCrankDocked() == false then
		-- クランクを右に回した場合.
		if pd.isCrankDocked() == false then
			local crankChange = pd.getCrankChange()
			if crankChange > CRANK_ROTATE_VALUE then
				return true
			end
		end	
	end

	return false
end

-- ゲームの状態を管理するための列挙型.
local GAMESTATE = {
	PLAYING = 0, -- プレイヤー操作中.
	CHECK_ERASE = 1, -- 消去判定中.
	ERASING = 2, -- 消去アニメーション中.
	SLIDEUP = 3, -- せり上げアニメーション中.
}

-- ゲームの状態を管理する変数.
local gameState = GAMESTATE.CHECK_ERASE

function _updatePlaying()
	local sound = gameContext.sound
	-- カーソルの移動.
	if pd.buttonJustPressed(pd.kButtonUp) then
		board:moveCursorUp()
		sound:play("pi")
	elseif pd.buttonJustPressed(pd.kButtonDown) then
		board:moveCursorDown()
		sound:play("pi")
	elseif isJustPressedLeft() then
		board:moveCursorLeft()
		sound:play("pi")
	elseif isJustPressedRight() then
		board:moveCursorRight()
		sound:play("pi")
	elseif pd.buttonJustPressed(pd.kButtonA) then
		-- カーソル位置のパネルと上隣のパネルを交換する.
		board:swapCells(0, -1)
		sound:play("swap")
		-- 消去チェックへ.
		gameState = GAMESTATE.CHECK_ERASE
	elseif pd.buttonJustPressed(pd.kButtonB) then
		-- 新しいブロックを出現.
		board:slideUpNewRow()
		-- せり上げアニメーション中に移行.
		gameState = GAMESTATE.SLIDEUP

		BeatMachine.SetBPM(150) -- BPMを設定.
	end	
end

-- 消去判定.
function _updateCheckErase()
	local eraseList = board:checkEraseList()
	print("消すリストの数: " .. #eraseList.groups)
	for groupIndex, group in ipairs(eraseList.groups) do
		print(string.format("グループ %d のセル数: %d", groupIndex, #group.indices))
		for _, index in ipairs(group.indices) do
			local pos = board:convertIndexToPosition(index)
			print(string.format("  消す位置: (%d, %d)", pos.x, pos.y))
		end
	end
	if board:startEraseBlinkAnimation(eraseList) then
		-- 消すことができた.
		gameContext.sound:play("erase")
		gameState = GAMESTATE.ERASING
	else
		-- 消せないので、プレイヤー操作中に戻す.
		gameState = GAMESTATE.PLAYING
	end
end

function _updateErasing()
	-- 消去アニメーションの更新.
	if board:isEndEraseAnimation() then
		-- 点滅アニメーションが終了したら、ブロックを消去する.
		-- board:eraseBlocks()
		-- ゲーム状態をプレイヤー操作中に戻す.
		gameState = GAMESTATE.PLAYING
	end
end

function _updateSlideUp()
	-- せり上げアニメーションの更新.
	if board:isEndSlidingUp() then
		-- せり上げアニメーションが終了したら、消去判定へ.
		gameState = GAMESTATE.CHECK_ERASE
	end
end

function playdate.update()
    gfx.clear(gfx.kColorWhite)

    gfx.setColor(gfx.kColorBlack)

	if gameState == GAMESTATE.PLAYING then
		-- プレイヤー操作中の処理.
		_updatePlaying()
	elseif gameState == GAMESTATE.CHECK_ERASE then
		-- 消去判定中の処理.
		_updateCheckErase()
	elseif gameState == GAMESTATE.ERASING then
		-- 消去アニメーション中の処理.
		_updateErasing()
	elseif gameState == GAMESTATE.SLIDEUP then
		-- せり上げアニメーション中の処理.
		_updateSlideUp()
	end

	-- 盤面の更新と描画.
	board:update()
    board:draw()

	-- FPS.
    playdate.drawFPS(4, 4)
	-- カーソル位置の描画.
	playdate.graphics.drawText(string.format("Cursor: (%d, %d)", board.cursorX, board.cursorY), 4, 20)
	-- 状態の描画.
	playdate.graphics.drawText(string.format("GameState: %d", gameState), 4, 240-20)
end
