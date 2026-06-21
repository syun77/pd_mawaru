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

class("ErasePanelGroup").extends()

function ErasePanelGroup:init()
    self.indices = {}
end

function ErasePanelGroup:addIndex(index)
    table.insert(self.indices, index)
end

function ErasePanelGroup:isEmpty()
    return #self.indices == 0
end

class("ErasePanelList").extends()

function ErasePanelList:init()
    self.groups = {}
end

function ErasePanelList:addGroup(group)
    if group ~= nil and not group:isEmpty() then
        table.insert(self.groups, group)
    end
end

function ErasePanelList:isEmpty()
    return #self.groups == 0
end

Board.BLOCK = BLOCK

function Board:init(config)
    self.config = {
        cx = 200,
        cy = 120,
        width = 340,
        height = 200,
        depth = 6,
        columns = 16,
        columnAngleOffsetColumns = 0.5,
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

function Board:convertIndexToPosition(index)
	local col = ((index - 1) % self.cells.width) + 1
	local row = math.floor((index - 1) / self.cells.width) + 1
	return { x = col, y = row }
end

function Board:setCell(col, row, blockType)
    self.cells:set(col, row, blockType)
end

function Board:getCell(col, row)
    return self.cells:get(col, row)
end

function Board:indexToCell(index)
    local col = ((index - 1) % self.cells.width) + 1
    local row = math.floor((index - 1) / self.cells.width) + 1
    return col, row
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

-- 指定した位置のパネルを交換する.
function Board:swapCells(dx, dy)
	local x1, y1 = self.cursorX, self.cursorY
	local x2, y2 = x1 + dx, y1 + dy
	self.cells:swap(x1, y1, x2, y2, true, false)
end

function Board:getNodeKey(rowBoundary, columnBoundary)
    local normalizedColumn = ((columnBoundary - 1) % self.config.columns) + 1
    return string.format("%d:%d", rowBoundary, normalizedColumn)
end

function Board:getCellEdges(row, col, blockType)
	--[[
		[outerLeft]  ---- [outerRight]
		     |              |
	         |     cell     |
		     |              |
		[innerLeft]  ---- [innerRight]
	--]]
    local outerLeft  = self:getNodeKey(row - 1, col - 1) -- 左上の境界点
    local outerRight = self:getNodeKey(row - 1, col)     -- 右上の境界点
    local innerLeft  = self:getNodeKey(row,     col - 1) -- 左下の境界点
    local innerRight = self:getNodeKey(row,     col)     -- 右下の境界点

    if blockType == BLOCK.SLASH then
        return {
            { outerLeft, innerRight }
        }
    elseif blockType == BLOCK.BACKSLASH then
        return {
            { innerLeft, outerRight }
        }
    elseif blockType == BLOCK.VALLEY then
        return {
            { outerLeft, outerRight }
        }
    elseif blockType == BLOCK.PEAK then
        return {
            { innerLeft, innerRight }
        }
    end

    return {}
end

function Board:addAdjacency(adjacency, a, b)
    adjacency[a] = adjacency[a] or {}
    adjacency[b] = adjacency[b] or {}

    if adjacency[a][b] == nil then
        adjacency[a][b] = true
        adjacency[b][a] = true
    end
end

function Board:buildCellGraph()
    local cellNodes = {}
    local nodeToCells = {}

    for row = 1, self.config.depth do
        for col = 1, self.config.columns do
            local blockType = self.cells:get(col, row)
            if blockType ~= BLOCK.EMPTY then
				-- セルのインデックスを取得
                local index = self.cells:_get_index(col, row)
                local edges = self:getCellEdges(row, col, blockType)
                local nodeSet = {}

                for _, edge in ipairs(edges) do
                    local a, b = edge[1], edge[2]
                    nodeSet[a] = true
                    nodeSet[b] = true

                    nodeToCells[a] = nodeToCells[a] or {}
                    nodeToCells[b] = nodeToCells[b] or {}
                    table.insert(nodeToCells[a], index)
                    table.insert(nodeToCells[b], index)
                end

                cellNodes[index] = nodeSet
            end
        end
    end

    local adjacency = {}
    for _, cellsAtNode in pairs(nodeToCells) do
        for i = 1, #cellsAtNode do
            for j = i + 1, #cellsAtNode do
                self:addAdjacency(adjacency, cellsAtNode[i], cellsAtNode[j])
            end
        end
    end

    return cellNodes, adjacency
end

function Board:walkCycle(startIndex, adjacency, componentSet, visited)
    local ordered = {}
    local neighbors = adjacency[startIndex]
    if neighbors == nil then
        return ordered
    end

    local firstNeighbor
    for neighborIndex, _ in pairs(neighbors) do
        if componentSet[neighborIndex] then
            firstNeighbor = neighborIndex
            break
        end
    end

    if firstNeighbor == nil then
        return ordered
    end

    table.insert(ordered, startIndex)
    visited[startIndex] = true

    local previous = startIndex
    local current = firstNeighbor

    while current ~= nil and not visited[current] do
        table.insert(ordered, current)
        visited[current] = true

        local nextIndex = nil
        local nextNeighbors = adjacency[current] or {}
        for neighborIndex, _ in pairs(nextNeighbors) do
            if componentSet[neighborIndex] and neighborIndex ~= previous then
                nextIndex = neighborIndex
                break
            end
        end

        previous = current
        current = nextIndex

        if current == startIndex then
            break
        end
    end

    return ordered
end

function Board:checkEraseList()
    local _, adjacency = self:buildCellGraph()
    local visited = {}
    local eraseList = ErasePanelList()

    for row = 1, self.config.depth do
        for col = 1, self.config.columns do
            local index = self.cells:_get_index(col, row)
            local blockType = self.cells:get(col, row)
            if blockType ~= BLOCK.EMPTY and not visited[index] then
                local stack = { index }
                local component = {}
                local componentSet = {}

                while #stack > 0 do
                    local current = table.remove(stack)
                    if not visited[current] then
                        visited[current] = true
                        componentSet[current] = true
                        table.insert(component, current)

                        local neighbors = adjacency[current] or {}
                        for neighborIndex, _ in pairs(neighbors) do
                            if not visited[neighborIndex] then
                                table.insert(stack, neighborIndex)
                            end
                        end
                    end
                end

                local isCycle = #component >= 3
                if isCycle then
                    for _, cellIndex in ipairs(component) do
                        local degree = 0
                        local neighbors = adjacency[cellIndex] or {}
                        for neighborIndex, _ in pairs(neighbors) do
                            if componentSet[neighborIndex] then
                                degree = degree + 1
                            end
                        end
                        if degree ~= 2 then
                            isCycle = false
                            break
                        end
                    end
                end

                if isCycle then
                    local group = ErasePanelGroup()
                    local ordered = self:walkCycle(component[1], adjacency, componentSet, {})
                    if #ordered == 0 then
                        ordered = component
                    end

                    for _, cellIndex in ipairs(ordered) do
                        group:addIndex(cellIndex)
                    end
                    eraseList:addGroup(group)
                end
            end
        end
    end

    return eraseList
end

function Board:checkeraselist()
    return self:checkEraseList()
end

function Board:eraseByList(eraseList)
    if eraseList == nil or eraseList:isEmpty() then
        return
    end

    for _, group in ipairs(eraseList.groups) do
        for _, index in ipairs(group.indices) do
            local col, row = self:indexToCell(index)
            self:setCell(col, row, BLOCK.EMPTY)
        end
    end
end

function Board:eraseeraselist(eraseList)
    self:eraseByList(eraseList)
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
    local offsetColumns = self.config.columnAngleOffsetColumns or 0
    return (boundary + offsetColumns) / self.config.columns * math.pi * 2 - math.pi / 2
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
    local steps = 320
    local dash = 2 -- 描く区間
    local gap  = 2 -- 空ける区間

    local prevX, prevY

    for i = 0, steps do
        local a = i / steps * math.pi * 2
        local x, y = self:ellipsePoint(self.config.cx, self.config.cy, rx, ry, a)

        if prevX then
            local period = dash + gap
            if (i % period) < dash then
                gfx.drawLine(prevX, prevY, x, y)
            end
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
        local angle = self:getColumnBoundaryAngle(c - 1)

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