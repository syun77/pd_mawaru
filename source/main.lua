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

function pd.update()
    gfx.clear()
	sprite.update() -- すべてのスプライトを更新と描画.



	-- ショットの数を画面に表示.
	gfx.drawText("Test MAWARU", 10, 30)
end

import "CoreLibs/graphics"

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

    lineWidth = 2,
    nodeRadius = 2
}

-- 仮の盤面データ [depth][columns]
local cells = Array2D(board.columns, board.depth, BLOCK.EMPTY)

for r = 1, board.depth do
    for c = 1, board.columns do
        --cells:set(c, r, math.random(0, 4)) -- 0から4のランダムなブロック種別を設定
		cells:set(c, r, BLOCK.BACKSLASH) -- テスト用にすべて空にする.
    end
end

local function ellipsePoint(cx, cy, rx, ry, angle)
    return cx + math.cos(angle) * rx,
           cy + math.sin(angle) * ry
end

local function getCellEllipseRadius(row)
    local outerRx = board.width / 2
    local outerRy = board.height / 2

    local innerScale = 0.35
    local t = (row - 0.5) / board.depth

    local scale = 1.0 - (1.0 - innerScale) * t

    return outerRx * scale, outerRy * scale
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
    for r = 1, board.depth do
        local rx, ry = getCellEllipseRadius(r)
        drawEllipsePolyline(rx, ry)
    end

    -- 円周方向の区切り線
    for c = 1, board.columns do
        local angle = (c - 1) / board.columns * math.pi * 2 - math.pi / 2

        local outerRx = board.width / 2
        local outerRy = board.height / 2
        local innerRx = outerRx * 0.35
        local innerRy = outerRy * 0.35

        local x1, y1 = ellipsePoint(board.cx, board.cy, outerRx, outerRy, angle)
        local x2, y2 = ellipsePoint(board.cx, board.cy, innerRx, innerRy, angle)

        gfx.drawLine(x1, y1, x2, y2)
    end
end

local function drawNode(x, y)
    gfx.fillCircleAtPoint(x, y, board.nodeRadius)
end

local function drawGunpeyBlock(row, col, blockType)
    if blockType == BLOCK.EMPTY then
        return
    end

    local x, y, angle = getCellCenter(row, col)

    -- セルの見かけサイズ
    local tangentSize = 12
    local radialSize = 9

    local cosA = math.cos(angle)
    local sinA = math.sin(angle)

    -- 接線方向
    local tx = -sinA
    local ty = cosA

    -- 半径方向
    local rx = cosA
    local ry = sinA

    local leftX  = x - tx * tangentSize
    local leftY  = y - ty * tangentSize
    local rightX = x + tx * tangentSize
    local rightY = y + ty * tangentSize

    local upX    = x - rx * radialSize
    local upY    = y - ry * radialSize
    local downX  = x + rx * radialSize
    local downY  = y + ry * radialSize

    -- セル局所座標の4隅をワールド座標へ変換.
    local leftUpX = x - tx * tangentSize - rx * radialSize
    local leftUpY = y - ty * tangentSize - ry * radialSize
    local rightUpX = x + tx * tangentSize - rx * radialSize
    local rightUpY = y + ty * tangentSize - ry * radialSize
    local leftDownX = x - tx * tangentSize + rx * radialSize
    local leftDownY = y - ty * tangentSize + ry * radialSize
    local rightDownX = x + tx * tangentSize + rx * radialSize
    local rightDownY = y + ty * tangentSize + ry * radialSize

    gfx.setLineWidth(board.lineWidth)

    if blockType == BLOCK.SLASH then
        -- /
        gfx.drawLine(leftDownX, leftDownY, rightUpX, rightUpY)

    elseif blockType == BLOCK.BACKSLASH then
        -- \
        gfx.drawLine(leftUpX, leftUpY, rightDownX, rightDownY)

    elseif blockType == BLOCK.VALLEY then
        -- 中央から左右下へ
        gfx.drawLine(upX, upY, leftDownX, leftDownY)
        gfx.drawLine(upX, upY, rightDownX, rightDownY)

    elseif blockType == BLOCK.PEAK then
        gfx.drawLine(leftUpX, leftUpY, downX, downY)
        gfx.drawLine(rightUpX, rightUpY, downX, downY)
    end

    -- 接続点を丸で強調
    drawNode(leftX, leftY)
    drawNode(rightX, rightY)
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