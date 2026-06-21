---@diagnostic disable
import "CoreLibs/graphics"
import "CoreLibs/object"
import "array2d"

local gfx <const> = playdate.graphics

local BLOCK = {
    EMPTY = 0,
    SLASH = 1,      -- /
    BACKSLASH = 2,  -- \
    VALLEY = 3,     -- \/ 谷型.
    PEAK = 4        -- /\ 山型.
}

class("Board").extends()

Board.BLOCK = BLOCK

function Board:init(config)
    self.config = {
        cx = 200,
        cy = 120,
        width = 340,
        height = 200,
        depth = 6,
        columns = 16,
        valleyHeightRatio = 0.6, -- 谷型の中央の高さ調整用.
        peakHeightRatio = 0.2, -- 山型の中央の高さ調整用. 0に近いほど尖る.
        innerScale = 0.35,
        lineWidth = 2,
        nodeRadius = 2
    }

    if config ~= nil then
        for key, value in pairs(config) do
            self.config[key] = value
        end
    end

    self.cells = Array2D(self.config.columns, self.config.depth, BLOCK.EMPTY)
    self.cursorX = 1
    self.cursorY = 1
    self:randomize()
end

function Board:randomize()
    for r = 1, self.config.depth do
        for c = 1, self.config.columns do
            self.cells:set(c, r, math.random(0, 4))
        end
    end
end

function Board:setCell(col, row, blockType)
    self.cells:set(col, row, blockType)
end

function Board:getCell(col, row)
    return self.cells:get(col, row)
end

function Board:draw()
    self:drawBoardGuide()
    self:drawBlocks()
    self:drawCursor()
end

function Board:setCursor(x, y)
    -- 列は円周上なのでループ、行は範囲内にクランプ.
    self.cursorX = ((x - 1) % self.config.columns) + 1
    self.cursorY = math.max(1, math.min(y, self.config.depth))
end

function Board:getCursor()
    return self.cursorX, self.cursorY
end

function Board:moveCursorBy(dx, dy)
    self:setCursor(self.cursorX + dx, self.cursorY + dy)
end

function Board:moveCursorLeft()
    self:moveCursorBy(-1, 0)
end

function Board:moveCursorRight()
    self:moveCursorBy(1, 0)
end

function Board:moveCursorUp()
    self:moveCursorBy(0, -1)
end

function Board:moveCursorDown()
    self:moveCursorBy(0, 1)
end

function Board:ellipsePoint(cx, cy, rx, ry, angle)
    return cx + math.cos(angle) * rx,
           cy + math.sin(angle) * ry
end

function Board:getRowBoundaryRadius(boundary)
    local outerRx = self.config.width / 2
    local outerRy = self.config.height / 2
    local t = boundary / self.config.depth
    local scale = 1.0 - (1.0 - self.config.innerScale) * t
    return outerRx * scale, outerRy * scale
end

function Board:getColumnBoundaryAngle(boundary)
    return boundary / self.config.columns * math.pi * 2 - math.pi / 2
end

function Board:getCellCorners(row, col)
    local leftBoundary = col - 1
    local rightBoundary = col
    local outerBoundary = row - 1
    local innerBoundary = row

    local leftAngle = self:getColumnBoundaryAngle(leftBoundary)
    local rightAngle = self:getColumnBoundaryAngle(rightBoundary)
    local outerRx, outerRy = self:getRowBoundaryRadius(outerBoundary)
    local innerRx, innerRy = self:getRowBoundaryRadius(innerBoundary)

    local outerLeftX, outerLeftY = self:ellipsePoint(self.config.cx, self.config.cy, outerRx, outerRy, leftAngle)
    local outerRightX, outerRightY = self:ellipsePoint(self.config.cx, self.config.cy, outerRx, outerRy, rightAngle)
    local innerLeftX, innerLeftY = self:ellipsePoint(self.config.cx, self.config.cy, innerRx, innerRy, leftAngle)
    local innerRightX, innerRightY = self:ellipsePoint(self.config.cx, self.config.cy, innerRx, innerRy, rightAngle)

    return outerLeftX, outerLeftY, outerRightX, outerRightY, innerLeftX, innerLeftY, innerRightX, innerRightY
end

function Board:drawEllipsePolyline(rx, ry)
    local steps = 96
    local prevX, prevY

    for i = 0, steps do
        local a = i / steps * math.pi * 2
        local x, y = self:ellipsePoint(self.config.cx, self.config.cy, rx, ry, a)

        if prevX then
            gfx.drawLine(prevX, prevY, x, y)
        end

        prevX, prevY = x, y
    end
end

function Board:drawBoardGuide()
    gfx.setLineWidth(1)

    for b = 0, self.config.depth do
        local rx, ry = self:getRowBoundaryRadius(b)
        self:drawEllipsePolyline(rx, ry)
    end

    for c = 1, self.config.columns do
        local angle = (c - 1) / self.config.columns * math.pi * 2 - math.pi / 2

        local outerRx = self.config.width / 2
        local outerRy = self.config.height / 2
        local innerRx = outerRx * self.config.innerScale
        local innerRy = outerRy * self.config.innerScale

        local x1, y1 = self:ellipsePoint(self.config.cx, self.config.cy, outerRx, outerRy, angle)
        local x2, y2 = self:ellipsePoint(self.config.cx, self.config.cy, innerRx, innerRy, angle)

        gfx.drawLine(x1, y1, x2, y2)
    end
end

function Board:drawNode(x, y)
    gfx.fillCircleAtPoint(x, y, self.config.nodeRadius)
end

function Board:clamp01(v)
    if v < 0 then
        return 0
    elseif v > 1 then
        return 1
    end
    return v
end

function Board:lerp(a, b, t)
    return a + (b - a) * t
end

function Board:drawGunpeyBlock(row, col, blockType)
    if blockType == BLOCK.EMPTY then
        return
    end

    local outerLeftX, outerLeftY, outerRightX, outerRightY,
          innerLeftX, innerLeftY, innerRightX, innerRightY = self:getCellCorners(row, col)

    local leftMidX = (outerLeftX + innerLeftX) * 0.5
    local leftMidY = (outerLeftY + innerLeftY) * 0.5
    local rightMidX = (outerRightX + innerRightX) * 0.5
    local rightMidY = (outerRightY + innerRightY) * 0.5

    local outerMidX = (outerLeftX + outerRightX) * 0.5
    local outerMidY = (outerLeftY + outerRightY) * 0.5
    local innerMidX = (innerLeftX + innerRightX) * 0.5
    local innerMidY = (innerLeftY + innerRightY) * 0.5

    local valleyT = self:clamp01(self.config.valleyHeightRatio)
    local peakT = self:clamp01(self.config.peakHeightRatio)
    local valleyApexX = self:lerp(outerMidX, innerMidX, valleyT)
    local valleyApexY = self:lerp(outerMidY, innerMidY, valleyT)
    local peakApexX = self:lerp(outerMidX, innerMidX, peakT)
    local peakApexY = self:lerp(outerMidY, innerMidY, peakT)

    gfx.setLineWidth(self.config.lineWidth)

    if blockType == BLOCK.SLASH then
        gfx.drawLine(outerLeftX, outerLeftY, innerRightX, innerRightY)

    elseif blockType == BLOCK.BACKSLASH then
        gfx.drawLine(innerLeftX, innerLeftY, outerRightX, outerRightY)

    elseif blockType == BLOCK.VALLEY then
        gfx.drawLine(outerLeftX, outerLeftY, valleyApexX, valleyApexY)
        gfx.drawLine(outerRightX, outerRightY, valleyApexX, valleyApexY)

    elseif blockType == BLOCK.PEAK then
        gfx.drawLine(innerLeftX, innerLeftY, peakApexX, peakApexY)
        gfx.drawLine(innerRightX, innerRightY, peakApexX, peakApexY)
    end

    -- 接続点の表示を有効化する場合はこのコメントを外す.
    -- if blockType == BLOCK.VALLEY then
    --     self:drawNode(outerLeftX, outerLeftY)
    --     self:drawNode(outerRightX, outerRightY)
    -- elseif blockType == BLOCK.PEAK then
    --     self:drawNode(innerLeftX, innerLeftY)
    --     self:drawNode(innerRightX, innerRightY)
    -- else
    --     self:drawNode(leftMidX, leftMidY)
    --     self:drawNode(rightMidX, rightMidY)
    -- end
end

function Board:drawBlocks()
    for r = 1, self.config.depth do
        for c = 1, self.config.columns do
            self:drawGunpeyBlock(r, c, self.cells:get(c, r))
        end
    end
end

function Board:drawCursor()
    local outerLeftX, outerLeftY, outerRightX, outerRightY,
          innerLeftX, innerLeftY, innerRightX, innerRightY = self:getCellCorners(self.cursorY, self.cursorX)

    gfx.setColor(gfx.kColorXOR)
    gfx.fillPolygon(
        outerLeftX, outerLeftY,
        outerRightX, outerRightY,
        innerRightX, innerRightY,
        innerLeftX, innerLeftY
    )
    gfx.setColor(gfx.kColorBlack)
end