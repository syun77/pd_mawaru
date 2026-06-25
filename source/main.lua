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
BeatMachine.SetVolume(0.05) -- 音量を設定.

pd.display.setRefreshRate(50) -- 50Hzに設定.

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
	CHECK_SLIDEUP = 3, -- せり上げチェック.
	SLIDEUP = 4, -- せり上げアニメーション中.
	GAMEOVER = 99, -- ゲームオーバー.
}

-- ゲームの状態を管理する変数.
local gameState = GAMESTATE.CHECK_SLIDEUP -- 初期状態はせり上げチェックに設定.
local frameCount = 0 -- フレームカウンタ.
local cntSlideY = 3 -- せり上がり回数.
local lives = 3 -- 残りライフ数.
-- スライドアップの制限時間.
local TIMER_SLIDEUP <const> = 30 * 30 -- せり上げの制限時間（いったん30FPSとして30秒）.
local timeLimitSlideUpMax = TIMER_SLIDEUP -- せり上げの制限時間の最大値.
local timeLimitSlideUp = TIMER_SLIDEUP -- せり上げのフレームカウンタ.

-- 円形ゲージを描画する関数.
local function drawCircularGauge(centerX, centerY, radius, ratio)
	local startAngle = -math.pi / 2 -- 12時方向開始.

	-- 進捗を扇形で塗りつぶす.
	if ratio >= 1 then
		gfx.fillCircleAtPoint(centerX, centerY, radius)
	elseif ratio > 0 then
		local totalSegments = 64
		local activeSegments = math.max(1, math.floor(totalSegments * ratio + 0.5))
		local points = { centerX, centerY }

		for i = 0, activeSegments do
			-- 時計回り.
			local angle = startAngle + ((i / totalSegments) * math.pi * 2)
			table.insert(points, centerX + math.cos(angle) * radius)
			table.insert(points, centerY + math.sin(angle) * radius)
		end

		gfx.fillPolygon(table.unpack(points))
	end

	-- 外枠.
	gfx.setLineWidth(2)
	gfx.drawCircleAtPoint(centerX, centerY, radius)
end

function _updatePlaying()
	timeLimitSlideUp -= 1
	if timeLimitSlideUp <= 0 then
		-- せり上げの制限時間が終了した場合は、せり上げチェックへ.
		cntSlideY = 1 -- 1回せり上がる.
		gameState = GAMESTATE.CHECK_SLIDEUP
	end

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
		-- 自分でせり上げる.
		timeLimitSlideUp = timeLimitSlideUpMax -- せり上げのフレームカウンタをリセット.
		board:slideUpNewRow()
		-- せり上げアニメーション中に移行.
		gameState = GAMESTATE.SLIDEUP

		--BeatMachine.SetBPM(150) -- BPMを設定.
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
		-- 消すことができなかったが、せり上げチェックへ.
		gameState = GAMESTATE.CHECK_SLIDEUP
	end
end

function _updateErasing()
	-- 消去アニメーションの更新.
	if board:isEndEraseAnimation() then
		-- 点滅アニメーションが終了したら、もう一度消去判定を行う.
		gameState = GAMESTATE.CHECK_ERASE
	end
end

function _updateCheckSlideUp()
	-- せり上げチェック中の処理.
	-- せり上げ回数が残っている場合は、せり上げアニメーションへ.
	if cntSlideY > 0 then
		cntSlideY -= 1
		board:slideUpNewRow()
		gameState = GAMESTATE.SLIDEUP
	else
		-- せり上げ回数が残っていない場合は、プレイヤー操作中に戻す.
		if timeLimitSlideUp <= 0 then
			-- 時間切れの場合のみ、せり上げのフレームカウンタをリセット.
			timeLimitSlideUp = TIMER_SLIDEUP
			timeLimitSlideUpMax = TIMER_SLIDEUP
		end
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

-- 残り時間の描画.
function drawTimeLimit()
	local ratio = math.max(0, math.min(1, timeLimitSlideUp / timeLimitSlideUpMax))
	if ratio < 0.2 and frameCount % 10 < 5 then
		-- 残り時間が20%未満の場合は点滅させる.
		ratio = 1
	end
	drawCircularGauge(200, 120, 20, 1 - ratio)
end

function playdate.update()
    gfx.clear(gfx.kColorWhite)

    gfx.setColor(gfx.kColorBlack)

	frameCount += 1

	if gameState == GAMESTATE.PLAYING then
		-- プレイヤー操作中の処理.
		_updatePlaying()
	elseif gameState == GAMESTATE.CHECK_ERASE then
		-- 消去判定中の処理.
		_updateCheckErase()
	elseif gameState == GAMESTATE.ERASING then
		-- 消去アニメーション中の処理.
		_updateErasing()
	elseif gameState == GAMESTATE.CHECK_SLIDEUP then
		_updateCheckSlideUp()
	elseif gameState == GAMESTATE.SLIDEUP then
		-- せり上げアニメーション中の処理.
		_updateSlideUp()
	end

	-- 盤面の更新と描画.
	board:update()
    board:draw()

	-- せり上がりの残り時間を中央に描画する.
	drawTimeLimit()

	-- FPS.
    playdate.drawFPS(4, 4)
	-- カーソル位置の描画.
	playdate.graphics.drawText(string.format("Cursor: (%d, %d)", board.cursorX, board.cursorY), 4, 20)
	-- 状態の描画.
	playdate.graphics.drawText(string.format("GameState: %d", gameState), 4, 240-20)
end
