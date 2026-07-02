---------------------------------------------
--- Endless Mode
---------------------------------------------
---@diagnostic disable
import "CoreLibs/object"
import "CoreLibs/graphics"
import "game_context"
import "board"
import "beatmachine"

local pd <const> = playdate
local gfx <const> = pd.graphics

class("ModeEndless").extends()

-- ゲーム状態.
local GAMESTATE = {
	PLAYING = 0,
	CHECK_ERASE = 1,
	ERASING = 2,
	CHECK_SLIDEUP = 3,
	SLIDEUP = 4,
}

local TIMER_SLIDEUP <const> = 30 * 30

-- 左方向の入力判定.
local function isJustPressedLeft()
	if pd.buttonJustPressed(pd.kButtonLeft) then
		return true
	end
	return false
end

-- 右方向の入力判定.
local function isJustPressedRight()
	if pd.buttonJustPressed(pd.kButtonRight) then
		return true
	end
	return false
end

-- 円形ゲージを描画.
local function drawCircularGauge(centerX, centerY, radius, ratio)
	local startAngle = -math.pi / 2

	if ratio >= 1 then
		-- 塗りつぶす.
		gfx.fillCircleAtPoint(centerX, centerY, radius)
	elseif ratio > 0 then
		-- ratioに応じた塗りつぶしを描画する.
		local totalSegments = 64
		local activeSegments = math.max(1, math.floor(totalSegments * ratio + 0.5))
		local points = { centerX, centerY }

		for i = 0, activeSegments do
			local angle = startAngle + ((i / totalSegments) * math.pi * 2)
			table.insert(points, centerX + math.cos(angle) * radius)
			table.insert(points, centerY + math.sin(angle) * radius)
		end

		gfx.fillPolygon(table.unpack(points))
	end

	-- 外枠の描画.
	gfx.setLineWidth(2)
	gfx.drawCircleAtPoint(centerX, centerY, radius)
	gfx.setLineWidth(1)
end

-- 初期化.
function ModeEndless:init(onExitToTitle)
	self.onExitToTitle = onExitToTitle
end

-- 開始.
function ModeEndless:enter()
	-- BGMを再生.
	BeatMachine.Create()
	BeatMachine.LoadBeat("beats/demo.bmf")
	BeatMachine.PlayTheBeat(0)
	BeatMachine.SetVolume(0.05)

	self.gameContext = GameContext.getInstance()
	self.gameContext:setup()

	-- メニューにリスタートとタイトルに戻るを追加.
	local sysMenu = pd.getSystemMenu()
	sysMenu:addMenuItem("Restart", function()
		self:enter()
	end)
	sysMenu:addMenuItem("Back to Title", function()
		self.onExitToTitle()
	end)

	self.board = Board()
	self.gameState = GAMESTATE.CHECK_SLIDEUP
	self.frameCount = 0
	self.cntSlideY = 3 -- 3回せり上げる.
	self.timeLimitSlideUp = TIMER_SLIDEUP
	self.timeLimitSlideUpMax = TIMER_SLIDEUP
end

-- 終了.
function ModeEndless:exit()
	-- BeatMachineには停止APIが未実装のため、ここでは何もしない.
end

-- 更新 > プレイ中.
function ModeEndless:updatePlaying()
	self.timeLimitSlideUp -= 1
	if self.timeLimitSlideUp <= 0 then
		self.cntSlideY = 1
		self.gameState = GAMESTATE.CHECK_SLIDEUP
	end

	local sound = self.gameContext.sound
	if pd.buttonJustPressed(pd.kButtonUp) then
		self.board:moveCursorUp()
		sound:play("pi")
	elseif pd.buttonJustPressed(pd.kButtonDown) then
		self.board:moveCursorDown()
		sound:play("pi")
	elseif isJustPressedLeft() then
		self.board:moveCursorLeft()
		sound:play("pi")
	elseif isJustPressedRight() then
		self.board:moveCursorRight()
		sound:play("pi")
	elseif pd.buttonJustPressed(pd.kButtonA) then
		-- 入れ替え.
		self.board:swapCells(0, -1)
		sound:play("swap")
		self.gameState = GAMESTATE.CHECK_ERASE
	elseif pd.buttonJustPressed(pd.kButtonB) then
		-- スライドアップ.
		self.board:slideUpColumn(self.board.cursorX)
		sound:play("slideup")
		self.gameState = GAMESTATE.SLIDEUP
	end
end

-- 更新 > 消去判定.
function ModeEndless:updateCheckErase()
	local eraseList = self.board:checkEraseList()
	if self.board:startEraseBlinkAnimation(eraseList) then
		self.gameContext.sound:play("erase")
		self.gameState = GAMESTATE.ERASING
	else
		self.gameState = GAMESTATE.CHECK_SLIDEUP
	end
end

-- 更新 > 消去中.
function ModeEndless:updateErasing()
	if self.board:isEndEraseAnimation() then
		self.gameState = GAMESTATE.CHECK_ERASE
	end
end

-- 更新 > スライドアップ判定.
function ModeEndless:updateCheckSlideUp()
	if self.cntSlideY > 0 then
		self.cntSlideY -= 1
		self.board:slideUpNewRow()
		self.gameContext.sound:play("slideup")
		self.gameState = GAMESTATE.SLIDEUP
	else
		if self.timeLimitSlideUp <= 0 then
			self.timeLimitSlideUp = TIMER_SLIDEUP
			self.timeLimitSlideUpMax = TIMER_SLIDEUP
		end
		self.gameState = GAMESTATE.PLAYING
	end
end

-- 更新 > スライドアップ中.
function ModeEndless:updateSlideUp()
	if self.board:isEndSlidingUp() then
		self.gameState = GAMESTATE.CHECK_ERASE
	end
end

-- 描画 > タイムリミット.
function ModeEndless:drawTimeLimit()
	local ratio = math.max(0, math.min(1, self.timeLimitSlideUp / self.timeLimitSlideUpMax))
	if ratio < 0.2 and self.frameCount % 10 < 5 then
		ratio = 1
	end
	drawCircularGauge(200, 120, 20, 1 - ratio)
end

-- 更新.
function ModeEndless:update()
	self.frameCount += 1

	if self.gameState == GAMESTATE.PLAYING then
		self:updatePlaying() -- プレイ中.
	elseif self.gameState == GAMESTATE.CHECK_ERASE then
		self:updateCheckErase() -- 消去判定.
	elseif self.gameState == GAMESTATE.ERASING then
		self:updateErasing() -- 消去中.
	elseif self.gameState == GAMESTATE.CHECK_SLIDEUP then
		self:updateCheckSlideUp() -- スライドアップ判定.
	elseif self.gameState == GAMESTATE.SLIDEUP then
		self:updateSlideUp() -- スライドアップ中.
	end

	self.board:update()
end

-- 描画.
function ModeEndless:draw()
	self.board:draw()
	self:drawTimeLimit()

	gfx.drawText(L("endless_mode_label"), 4, 20)
	gfx.drawText(L("endless_menu_hint"), 4, 220)
end
