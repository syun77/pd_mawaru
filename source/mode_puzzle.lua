----------------------------------------------
--- Puzzle Mode
----------------------------------------------
---@diagnostic disable
import "CoreLibs/object"
import "CoreLibs/graphics"
import "game_context"
import "board"
import "beatmachine"

local pd <const> = playdate
local gfx <const> = pd.graphics

class("ModePuzzle").extends()

local GAMESTATE = {
	STAGE_SELECT = -1,
	PLAYING = 0,
	CHECK_ERASE = 1,
	ERASING = 2,
	SLIDEUP = 3,
	GAME_CLEAR = 100,
	GAME_OVER = 101,
}

local CRANK_ROTATE_VALUE = 5
local DEFAULT_AUTO_RISE_SECONDS = 30

local STAGES = {
	{
		version = 1,
		id = "stage_sample_001",
		name = "First Loop",
		pack = "tutorial",
		board = {
			columns = 10,
			rows = 6,
			cells = {
				{0,0,0,0,0,0,0,0,0,0},
				{0,0,0,0,0,0,0,0,0,0},
				{0,0,0,0,0,0,0,0,0,0},
				{0,0,0,0,0,0,0,0,0,0},
				{1,2,1,2,3,4,1,2,1,2},
				{2,1,2,1,4,3,2,1,2,1},
			}
		},
		cursorStart = {
			col = 1,
			row = 2,
		},
		rules = {
			moveLimit = 12,
			timeLimit = nil,
			manualRiseEnabled = false,
			autoRiseEnabled = false,
			autoRiseInterval = nil,
		},
		clearCondition = {
			type = "erasePanels",
			count = 8,
			mark = nil,
		},
		riseQueue = {}
	}
}

-- stage/ フォルダの JSON ファイルからステージリストを読み込む.
local function loadStageListFromFiles()
	local files = playdate.file.listFiles("stage") or {}
	local stages = {}

	for _, filename in ipairs(files) do
		if string.match(filename, "^stage_%d+%.json$") then
			local path = "stage/" .. filename
			local data = json.decodeFile(path)
			if data ~= nil then
				stages[#stages + 1] = data
			end
		end
	end

	-- id 順にソート.
	table.sort(stages, function(a, b)
		return (a.id or "") < (b.id or "")
	end)

	-- ファイルが見つからない場合はハードコードのデータにフォールバック.
	if #stages == 0 then
		stages = STAGES
	end

	return stages
end

local function isJustPressedLeft()
	if pd.isCrankDocked() then
		return pd.buttonJustPressed(pd.kButtonLeft)
	end
	return pd.getCrankChange() < -CRANK_ROTATE_VALUE
end

local function isJustPressedRight()
	if pd.isCrankDocked() then
		return pd.buttonJustPressed(pd.kButtonRight)
	end
	return pd.getCrankChange() > CRANK_ROTATE_VALUE
end

local function sumErasedPanels(eraseList)
	local total = 0
	if eraseList == nil then
		return total
	end
	for _, group in ipairs(eraseList.groups) do
		total += #group.indices
	end
	return total
end

local function hasWrapLoop(eraseList, columns)
	if eraseList == nil then
		return false
	end
	for _, group in ipairs(eraseList.groups) do
		local hasLeft = false
		local hasRight = false
		for _, index in ipairs(group.indices) do
			local col = ((index - 1) % columns) + 1
			if col == 1 then
				hasLeft = true
			elseif col == columns then
				hasRight = true
			end
			if hasLeft and hasRight then
				return true
			end
		end
	end
	return false
end

local function parseMarkSet(markText)
	if markText == nil or markText == "" then
		return nil
	end

	local result = {}
	for token in string.gmatch(markText, "[^;]+") do
		local c, r = string.match(token, "(%d+),(%d+)")
		if c ~= nil and r ~= nil then
			local key = tostring(tonumber(c)) .. ":" .. tostring(tonumber(r))
			result[key] = true
		end
	end

	return result
end

function ModePuzzle:init(onExitToTitle)
	self.onExitToTitle = onExitToTitle
	self.stageIndex = 1
	self.stageSelectIndex = 1
	self.stages = {}
end

function ModePuzzle:enter()
	self.stages = loadStageListFromFiles()
	self.stageSelectIndex = 1
	self.gameState = GAMESTATE.STAGE_SELECT
	self.frameCount = 0

	BeatMachine.Create()
	BeatMachine.LoadBeat("beats/demo.bmf")
	BeatMachine.PlayTheBeat(0)
	BeatMachine.SetVolume(0.03)

	self.gameContext = GameContext.getInstance()
	self.gameContext:setup()

	-- システムメニューにリスタート / ステージ選択を登録.
	local sysMenu = pd.getSystemMenu()
	sysMenu:removeAllMenuItems()
	sysMenu:addMenuItem("Restart", function()
		if self.gameState ~= GAMESTATE.STAGE_SELECT then
			self:loadStage(self.stageIndex)
		end
	end)
	sysMenu:addMenuItem("Stage Select", function()
		self.stageSelectIndex = self.stageIndex
		self.gameState = GAMESTATE.STAGE_SELECT
	end)
end

function ModePuzzle:exit()
	-- BeatMachineには停止APIが未実装のため、ここでは何もしない.
	-- システムメニューのアイテムをクリア.
	pd.getSystemMenu():removeAllMenuItems()
end

function ModePuzzle:loadStage(index)
	local stage = self.stages[index]
	if stage == nil then
		stage = self.stages[1]
		self.stageIndex = 1
	else
		self.stageIndex = index
	end
	self.stage = stage

	local columns = stage.board.columns
	local rows = stage.board.rows
	self.board = Board({ columns = columns, depth = rows })

	local startCol = stage.cursorStart and stage.cursorStart.col or 1
	local startRow = stage.cursorStart and stage.cursorStart.row or 2

	-- cursorStart.col をオフセットとしてパネル配置をシフト（カーソルは列1固定）.
	-- stage データ上の startCol 列がカーソル位置(列1)に来るよう回転させる.
	local colOffset = startCol - 1
	for r = 1, rows do
		local srcRow = stage.board.cells[r] or {}
		for c = 1, columns do
			local v = srcRow[c] or 0
			-- (c - colOffset - 1) % columns + 1 で列を左シフト.
			local destCol = ((c - colOffset - 1) % columns) + 1
			self.board:setCell(destCol, r, v)
		end
	end

	self.board:setCursor(1, startRow)

	self.gameState = GAMESTATE.PLAYING
	self.frameCount = 0
	self.movesUsed = 0
	self.erasedPanels = 0
	self.loopCount = 0
	self.wrapLoopMade = false
	self.riseQueueIndex = 1
	self.markSet = parseMarkSet(stage.clearCondition and stage.clearCondition.mark or nil)

	local timeLimitSeconds = stage.rules and stage.rules.timeLimit or nil
	self.timeLimitFrames = nil
	if timeLimitSeconds ~= nil then
		self.timeLimitFrames = math.max(0, math.floor(timeLimitSeconds * 50))
	end

	self.autoRiseFrames = nil
	local autoRiseEnabled = stage.rules and stage.rules.autoRiseEnabled or false
	if autoRiseEnabled then
		local interval = stage.rules.autoRiseInterval or DEFAULT_AUTO_RISE_SECONDS
		self.autoRiseFrames = math.max(1, math.floor(interval * 50))
	end

	self.statusMessage = ""
end

function ModePuzzle:applyQueuedRiseRow()
	local queue = self.stage.riseQueue
	if queue == nil or #queue == 0 then
		self.board:slideUpNewRow()
		return
	end

	self.board:slideUpNewRow()
	local queued = queue[self.riseQueueIndex]
	if queued ~= nil and self.board.slideUpAnimation ~= nil then
		local incoming = {}
		for c = 1, self.stage.board.columns do
			incoming[c] = queued[c] or 0
		end
		self.board.slideUpAnimation.incomingRow = incoming
	end

	self.riseQueueIndex += 1
	if self.riseQueueIndex > #queue then
		self.riseQueueIndex = 1
	end
end

function ModePuzzle:isBoardCleared()
	local columns = self.stage.board.columns
	local rows = self.stage.board.rows
	for r = 1, rows do
		for c = 1, columns do
			if self.board:getCell(c, r) ~= 0 then
				return false
			end
		end
	end
	return true
end

function ModePuzzle:isMarkedCleared()
	if self.markSet == nil then
		return false
	end

	for key, _ in pairs(self.markSet) do
		local c, r = string.match(key, "(%d+):(%d+)")
		if c ~= nil and r ~= nil then
			if self.board:getCell(tonumber(c), tonumber(r)) ~= 0 then
				return false
			end
		end
	end

	return true
end

function ModePuzzle:isClearAchieved()
	local cond = self.stage.clearCondition or { type = "eraseAll" }
	local condType = cond.type or "eraseAll"
	local count = cond.count or 1

	if condType == "eraseAll" then
		return self:isBoardCleared()
	elseif condType == "erasePanels" then
		return self.erasedPanels >= count
	elseif condType == "makeLoops" then
		return self.loopCount >= count
	elseif condType == "makeWrapLoop" then
		return self.wrapLoopMade
	elseif condType == "eraseMarked" then
		return self:isMarkedCleared()
	end

	return false
end

function ModePuzzle:updateStageSelect()
	local stageCount = #self.stages

	if pd.buttonJustPressed(pd.kButtonUp) or isJustPressedLeft() then
		self.stageSelectIndex -= 1
		if self.stageSelectIndex < 1 then
			self.stageSelectIndex = stageCount
		end
	elseif pd.buttonJustPressed(pd.kButtonDown) or isJustPressedRight() then
		self.stageSelectIndex += 1
		if self.stageSelectIndex > stageCount then
			self.stageSelectIndex = 1
		end
	end

	if pd.buttonJustPressed(pd.kButtonA) then
		self:loadStage(self.stageSelectIndex)
	elseif pd.buttonJustPressed(pd.kButtonB) and self.onExitToTitle ~= nil then
		self.onExitToTitle()
	end
end

function ModePuzzle:updatePlaying()
	if pd.buttonIsPressed(pd.kButtonA) and pd.buttonJustPressed(pd.kButtonB) and self.onExitToTitle ~= nil then
		self.onExitToTitle()
		return
	end

	if self.timeLimitFrames ~= nil then
		self.timeLimitFrames -= 1
		if self.timeLimitFrames <= 0 then
			self.timeLimitFrames = 0
			self.statusMessage = "時間切れ"
			self.gameState = GAMESTATE.GAME_OVER
			return
		end
	end

	if self.autoRiseFrames ~= nil then
		self.autoRiseFrames -= 1
		if self.autoRiseFrames <= 0 then
			local interval = self.stage.rules.autoRiseInterval or DEFAULT_AUTO_RISE_SECONDS
			self.autoRiseFrames = math.max(1, math.floor(interval * 50))
			self:applyQueuedRiseRow()
			self.gameContext.sound:play("slideup")
			self.gameState = GAMESTATE.SLIDEUP
			return
		end
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
		self.board:swapCells(0, -1)
		sound:play("swap")
		self.movesUsed += 1
		self.gameState = GAMESTATE.CHECK_ERASE
	elseif pd.buttonJustPressed(pd.kButtonB) then
		local canManualRise = self.stage.rules.manualRiseEnabled
		if canManualRise then
			self.board:slideUpColumn(self.board.cursorX)
			sound:play("slideup")
			self.gameState = GAMESTATE.SLIDEUP
		end
	end
end

function ModePuzzle:updateCheckErase()
	local eraseList = self.board:checkEraseList()
	if self.board:startEraseBlinkAnimation(eraseList) then
		self.erasedPanels += sumErasedPanels(eraseList)
		self.loopCount += #eraseList.groups
		if hasWrapLoop(eraseList, self.stage.board.columns) then
			self.wrapLoopMade = true
		end

		self.gameContext.sound:play("erase")
		self.gameState = GAMESTATE.ERASING
		return
	end

	if self:isClearAchieved() then
		self.statusMessage = "ステージクリア"
		self.gameState = GAMESTATE.GAME_CLEAR
		return
	end

	local moveLimit = self.stage.rules.moveLimit
	if moveLimit ~= nil and self.movesUsed >= moveLimit then
		self.statusMessage = "手数切れ"
		self.gameState = GAMESTATE.GAME_OVER
		return
	end

	self.gameState = GAMESTATE.PLAYING
end

function ModePuzzle:updateErasing()
	if self.board:isEndEraseAnimation() then
		self.gameState = GAMESTATE.CHECK_ERASE
	end
end

function ModePuzzle:updateSlideUp()
	if self.board:isEndSlidingUp() then
		self.gameState = GAMESTATE.CHECK_ERASE
	end
end

function ModePuzzle:updateResult()
	if pd.buttonJustPressed(pd.kButtonA) then
		if self.gameState == GAMESTATE.GAME_CLEAR then
			-- 次のステージへ（最後なら先頭に戻る）.
			local nextIndex = self.stageIndex + 1
			if nextIndex > #self.stages then
				nextIndex = 1
			end
			self.stageSelectIndex = nextIndex
			self:loadStage(nextIndex)
		else
			-- ゲームオーバー時はリスタート.
			self:loadStage(self.stageIndex)
		end
	elseif pd.buttonJustPressed(pd.kButtonB) then
		-- ステージ選択画面に戻る.
		self.stageSelectIndex = self.stageIndex
		self.gameState = GAMESTATE.STAGE_SELECT
	end
end

function ModePuzzle:update()
	self.frameCount += 1

	if self.gameState == GAMESTATE.STAGE_SELECT then
		self:updateStageSelect()
		return
	end

	if self.gameState == GAMESTATE.PLAYING then
		self:updatePlaying()
	elseif self.gameState == GAMESTATE.CHECK_ERASE then
		self:updateCheckErase()
	elseif self.gameState == GAMESTATE.ERASING then
		self:updateErasing()
	elseif self.gameState == GAMESTATE.SLIDEUP then
		self:updateSlideUp()
	elseif self.gameState == GAMESTATE.GAME_CLEAR or self.gameState == GAMESTATE.GAME_OVER then
		self:updateResult()
	end

	self.board:update()
end

function ModePuzzle:getConditionText()
	local cond = self.stage.clearCondition or { type = "eraseAll" }
	local condType = cond.type or "eraseAll"
	local count = cond.count or 1

	if condType == "eraseAll" then
		return "条件: 全消し"
	elseif condType == "erasePanels" then
		return string.format("条件: %d枚消去 (%d)", count, self.erasedPanels)
	elseif condType == "makeLoops" then
		return string.format("条件: %dループ作成 (%d)", count, self.loopCount)
	elseif condType == "makeWrapLoop" then
		local text = self.wrapLoopMade and "達成" or "未達成"
		return "条件: 円環ループ " .. text
	elseif condType == "eraseMarked" then
		return "条件: マーク消去"
	end

	return "条件: 不明"
end

function ModePuzzle:drawResultText()
	if self.gameState == GAMESTATE.GAME_CLEAR then
		gfx.drawTextAligned("CLEAR", 200, 92, kTextAlignment.center)
	elseif self.gameState == GAMESTATE.GAME_OVER then
		gfx.drawTextAligned("FAILED", 200, 92, kTextAlignment.center)
	end

	if self.statusMessage ~= "" then
		gfx.drawTextAligned(self.statusMessage, 200, 114, kTextAlignment.center)
	end
	if self.gameState == GAMESTATE.GAME_CLEAR then
		gfx.drawTextAligned("A: NEXT  B: SELECT", 200, 136, kTextAlignment.center)
	else
		gfx.drawTextAligned("A: RESTART  B: SELECT", 200, 136, kTextAlignment.center)
	end
end

function ModePuzzle:drawStageSelect()
	gfx.drawTextAligned("STAGE SELECT", 200, 16, kTextAlignment.center)

	local listX = 40
	local listY = 46
	local rowHeight = 24
	local visibleCount = 7
	local stageCount = #self.stages

	-- スクロールオフセットを計算.
	local scrollOffset = math.max(0, self.stageSelectIndex - math.ceil(visibleCount / 2))
	scrollOffset = math.min(scrollOffset, math.max(0, stageCount - visibleCount))

	for i = 1, visibleCount do
		local stageIdx = i + scrollOffset
		if stageIdx > stageCount then break end
		local stage = self.stages[stageIdx]
		local isSelected = (stageIdx == self.stageSelectIndex)
		local y = listY + (i - 1) * rowHeight

		if isSelected then
			gfx.fillRect(listX - 4, y - 2, 320 - (listX - 4) * 2, rowHeight - 2)
			gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		end

		local label = string.format("%d. %s", stageIdx, stage.name or stage.id or ("Stage " .. stageIdx))
		gfx.drawText(label, listX, y + 4)

		if isSelected then
			gfx.setImageDrawMode(gfx.kDrawModeCopy)
		end
	end

	-- スクロールインジケーター.
	if scrollOffset > 0 then
		gfx.drawTextAligned("▲", 200, listY - 16, kTextAlignment.center)
	end
	if scrollOffset + visibleCount < stageCount then
		gfx.drawTextAligned("▼", 200, listY + visibleCount * rowHeight, kTextAlignment.center)
	end

	gfx.drawTextAligned("A: START  B: TITLE", 200, 228, kTextAlignment.center)
end

function ModePuzzle:draw()
	-- ステージ選択画面.
	if self.gameState == GAMESTATE.STAGE_SELECT then
		self:drawStageSelect()
		return
	end

	self.board:draw()

	gfx.drawText("MODE: PUZZLE", 4, 20)
	gfx.drawText("STAGE: " .. (self.stage.name or self.stage.id or "unknown"), 4, 36)

	local moveLimit = self.stage.rules.moveLimit
	if moveLimit ~= nil then
		gfx.drawText(string.format("MOVES: %d/%d", self.movesUsed, moveLimit), 4, 52)
	else
		gfx.drawText(string.format("MOVES: %d", self.movesUsed), 4, 52)
	end

	if self.timeLimitFrames ~= nil then
		local sec = math.ceil(self.timeLimitFrames / 50)
		gfx.drawText(string.format("TIME: %d", sec), 4, 68)
	end

	gfx.drawText(self:getConditionText(), 4, 84)
	gfx.drawText("MENU: RESTART / SELECT", 4, 220)

	if self.gameState == GAMESTATE.GAME_CLEAR or self.gameState == GAMESTATE.GAME_OVER then
		gfx.fillRect(90, 80, 220, 74)
		gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		self:drawResultText()
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
	end
end
