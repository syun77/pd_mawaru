---@diagnostic disable
import "CoreLibs/graphics"
import "CoreLibs/object" -- classを使うために必要.
import "CoreLibs/sprites" -- spriteを使うために必要.
import "actor_manager"
import "game_context"
import "array2d"

local pd <const> = playdate
local gfx <const> = pd.graphics
local sprite <const> = gfx.sprite

local gameContext = GameContext.getInstance()
gameContext:setup()

local SCREEN_W <const> = 400
local SCREEN_H <const> = 240

-- Gunpey風ブロック種別
local BLOCK = {
    EMPTY = 0,
    SLASH = 1,      -- /
    BACKSLASH = 2,  -- \
    VALLEY = 3,     -- \/ 谷型.
    PEAK = 4        -- /\ 山型.
}

local board = {
    cx = 200,
    cy = 120,

    -- 外側楕円サイズ
    width = 340,
    height = 200,

    -- テトリスでいう「積み上がる高さ」
    depth = 6,

    -- 円周方向の分割数
    columns = 16,

    -- 山型・谷型の頂点位置比率（0.0=外側, 1.0=内側）
    valleyHeightRatio = 0.6,
    peakHeightRatio = 0.2,

    lineWidth = 2,
    nodeRadius = 2
}

local INNER_SCALE <const> = 0.35

-- 仮の盤面データ [depth][columns]
local cells = Array2D(board.columns, board.depth, BLOCK.EMPTY)

-- テストデータ.
for r = 1, board.depth do
    for c = 1, board.columns do
        cells:set(c, r, math.random(0, 4)) -- 0から4のランダムなブロック種別を設定
		--cells:set(c, r, BLOCK.BACKSLASH) -- テスト用にすべて同じにする.
    end
end

local function ellipsePoint(cx, cy, rx, ry, angle)
    return cx + math.cos(angle) * rx,
           cy + math.sin(angle) * ry
end

local function getCellEllipseRadius(row)
    local outerRx = board.width / 2
    local outerRy = board.height / 2

    local t = (row - 0.5) / board.depth

    local scale = 1.0 - (1.0 - INNER_SCALE) * t

    return outerRx * scale, outerRy * scale
end

local function getRowBoundaryRadius(boundary)
    local outerRx = board.width / 2
    local outerRy = board.height / 2
    local t = boundary / board.depth
    local scale = 1.0 - (1.0 - INNER_SCALE) * t
    return outerRx * scale, outerRy * scale
end

local function getColumnBoundaryAngle(boundary)
    return boundary / board.columns * math.pi * 2 - math.pi / 2
end

local function getCellCorners(row, col)
    local leftBoundary = col - 1
    local rightBoundary = col
    local outerBoundary = row - 1
    local innerBoundary = row

    local leftAngle = getColumnBoundaryAngle(leftBoundary)
    local rightAngle = getColumnBoundaryAngle(rightBoundary)
    local outerRx, outerRy = getRowBoundaryRadius(outerBoundary)
    local innerRx, innerRy = getRowBoundaryRadius(innerBoundary)

    local outerLeftX, outerLeftY = ellipsePoint(board.cx, board.cy, outerRx, outerRy, leftAngle)
    local outerRightX, outerRightY = ellipsePoint(board.cx, board.cy, outerRx, outerRy, rightAngle)
    local innerLeftX, innerLeftY = ellipsePoint(board.cx, board.cy, innerRx, innerRy, leftAngle)
    local innerRightX, innerRightY = ellipsePoint(board.cx, board.cy, innerRx, innerRy, rightAngle)

    return outerLeftX, outerLeftY, outerRightX, outerRightY, innerLeftX, innerLeftY, innerRightX, innerRightY
end

local function getCellCenter(row, col)
    local angle = (col - 0.5) / board.columns * math.pi * 2 - math.pi / 2
    local rx, ry = getCellEllipseRadius(row)

    local x, y = ellipsePoint(board.cx, board.cy, rx, ry, angle)
	return x, y, angle
end

local function drawEllipsePolyline(rx, ry)
    local steps = 96
    local prevX, prevY

    for i = 0, steps do
        local a = i / steps * math.pi * 2
        local x, y = ellipsePoint(board.cx, board.cy, rx, ry, a)

        if prevX then
            gfx.drawLine(prevX, prevY, x, y)
        end

        prevX, prevY = x, y
    end
end

local function drawBoardGuide()
    gfx.setLineWidth(1)

    -- 深さ方向の楕円線
    for b = 0, board.depth do
        local rx, ry = getRowBoundaryRadius(b)
        drawEllipsePolyline(rx, ry)
    end

    -- 円周方向の区切り線
    for c = 1, board.columns do
        local angle = (c - 1) / board.columns * math.pi * 2 - math.pi / 2

        local outerRx = board.width / 2
        local outerRy = board.height / 2
        local innerRx = outerRx * INNER_SCALE
        local innerRy = outerRy * INNER_SCALE

        local x1, y1 = ellipsePoint(board.cx, board.cy, outerRx, outerRy, angle)
        local x2, y2 = ellipsePoint(board.cx, board.cy, innerRx, innerRy, angle)

        gfx.drawLine(x1, y1, x2, y2)
    end
end

local function drawNode(x, y)
    gfx.fillCircleAtPoint(x, y, board.nodeRadius)
end

local function clamp01(v)
    if v < 0 then
        return 0
    elseif v > 1 then
        return 1
    end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function drawGunpeyBlock(row, col, blockType)
    if blockType == BLOCK.EMPTY then
        return
    end

    local outerLeftX, outerLeftY, outerRightX, outerRightY,
          innerLeftX, innerLeftY, innerRightX, innerRightY = getCellCorners(row, col)

    local leftMidX = (outerLeftX + innerLeftX) * 0.5
    local leftMidY = (outerLeftY + innerLeftY) * 0.5
    local rightMidX = (outerRightX + innerRightX) * 0.5
    local rightMidY = (outerRightY + innerRightY) * 0.5

    local outerMidX = (outerLeftX + outerRightX) * 0.5
    local outerMidY = (outerLeftY + outerRightY) * 0.5
    local innerMidX = (innerLeftX + innerRightX) * 0.5
    local innerMidY = (innerLeftY + innerRightY) * 0.5

    local valleyT = clamp01(board.valleyHeightRatio)
    local peakT = clamp01(board.peakHeightRatio)
    local valleyApexX = lerp(outerMidX, innerMidX, valleyT)
    local valleyApexY = lerp(outerMidY, innerMidY, valleyT)
    local peakApexX = lerp(outerMidX, innerMidX, peakT)
    local peakApexY = lerp(outerMidY, innerMidY, peakT)

    gfx.setLineWidth(board.lineWidth)

    if blockType == BLOCK.SLASH then
        -- /
        gfx.drawLine(outerLeftX, outerLeftY, innerRightX, innerRightY)

    elseif blockType == BLOCK.BACKSLASH then
        -- \
        gfx.drawLine(innerLeftX, innerLeftY, outerRightX, outerRightY)

    elseif blockType == BLOCK.VALLEY then
        -- 谷型 \/ : 外側の左右角 → 可変頂点
        gfx.drawLine(outerLeftX, outerLeftY, valleyApexX, valleyApexY)
        gfx.drawLine(outerRightX, outerRightY, valleyApexX, valleyApexY)

    elseif blockType == BLOCK.PEAK then
        -- 山型 /\ : 内側の左右角 → 可変頂点
        gfx.drawLine(innerLeftX, innerLeftY, peakApexX, peakApexY)
        gfx.drawLine(innerRightX, innerRightY, peakApexX, peakApexY)
    end

	--[[
    -- 接続点を丸で強調（VALLEY=外側角, PEAK=内側角, その他=左右辺中点）
    if blockType == BLOCK.VALLEY then
        drawNode(outerLeftX, outerLeftY)
        drawNode(outerRightX, outerRightY)
    elseif blockType == BLOCK.PEAK then
        drawNode(innerLeftX, innerLeftY)
        drawNode(innerRightX, innerRightY)
    else
        drawNode(leftMidX, leftMidY)
        drawNode(rightMidX, rightMidY)
    end
	--]]
end

local function drawBlocks()
    for r = 1, board.depth do
        for c = 1, board.columns do
            drawGunpeyBlock(r, c, cells:get(c, r))
        end
    end
end

function playdate.update()
    gfx.clear(gfx.kColorWhite)

    gfx.setColor(gfx.kColorBlack)

    drawBoardGuide()
    drawBlocks()

    playdate.drawFPS(4, 4)
end
