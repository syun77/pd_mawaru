---@diagnostic disable
import "CoreLibs/graphics"
import "CoreLibs/object"
import "array2d"

local gfx <const> = playdate.graphics

-- 動作モード
BOARD_MODE = {
	SINGLE = 1, -- カーソルが単一.
	VERTICAL_SWAP = 2, -- カーソルが縦2列で、上下を入れ替える.
}
 
-- ブロックの種類.
local BLOCK = {
    EMPTY = 0,
    SLASH = 1,      -- /
    BACKSLASH = 2,  -- \
    VALLEY = 3,     -- \/ 谷型.
    PEAK = 4        -- /\ 山型.
}

-- 消去パネル判定用.
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

class("Board").extends()

Board.BLOCK = BLOCK

function Board:init(config)
	-- ゲーム設定.
    self.config = {
        cx = 200,
        cy = 120,
        width = 340,
        height = 200,
        columns = 12, -- 列数.
        depth = 6, -- 行数.
        columnAngleOffsetColumns = 0.5,
        valleyHeightRatio = 0.6, -- 谷型の中央の高さ調整用.
        peakHeightRatio = 0.2, -- 山型の中央の高さ調整用. 0に近いほど尖る.
        cursorFollowRotationStep = 0.2,
        swapDrawOffsetScale = 0.7,
        swapDrawAnimationStep = 0.2,
        slideUpAnimationStep = 0.2,
        innerScale = 0.35,
        lineWidth = 3, -- ラインの太さ.
        nodeRadius = 2,
        guideDashLength = 6,
        guideGapLength = 6,
        boardGuideRadialCacheStep = 0.125
    }

    if config ~= nil then
        for key, value in pairs(config) do
            self.config[key] = value
        end
    end

    self.currentColumnAngleOffset = self.config.columnAngleOffsetColumns
    self.targetColumnAngleOffset = self.config.columnAngleOffsetColumns
    self.cells = Array2D(self.config.columns, self.config.depth, BLOCK.EMPTY)
	self.mode = BOARD_MODE.VERTICAL_SWAP -- 現在は縦入れ替えモードのみ.
    self.swapDrawAnimation = nil
    self.eraseBlinkAnimation = nil
    self.slideUpAnimation = nil
	self.framePointCache = {}
	self.frameCellCenterCache = {}
	self:buildRowRadiusCache()
    self.boardGuideEllipseCache = self:buildBoardGuideEllipseCache()
    self.boardGuideRadialCache = nil
    self.boardGuideRadialCacheOffset = nil
	self:setCursor(1, 1) -- カーソル位置を設定.
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

-- 盤面の更新.
function Board:update()
	-- 盤面の回転.
    self:updateBoardRotation()
	-- 入れ替えアニメーションの更新.
    self:updateSwapDrawAnimation()
    -- 消去前の点滅アニメーション更新.
    self:updateEraseBlinkAnimation()
	-- せり上げアニメーション更新.
	self:updateSlideUpAnimation()
end

-- 盤面の描画.
function Board:draw()
    self:rebuildFrameGeometryCache()
	-- ガイド線の描画.
    self:drawBoardGuide()
	-- ブロックの描画.
    self:drawBlocks()
	-- カーソルの描画.
    self:drawCursor(self.cursorX, self.cursorY)
	if self.mode == BOARD_MODE.VERTICAL_SWAP then
		-- 縦入れ替えモードの場合、カーソルの上のセルもハイライトする.
		self:drawCursor(self.cursorX, self.cursorY - 1)
	end
end

function Board:normalizeColumn(col)
    return ((col - 1) % self.config.columns) + 1
end

function Board:isValidRow(row)
    return row >= 1 and row <= self.config.depth
end

function Board:getCellCenter(col, row)
    local rowCache = self.frameCellCenterCache[row]
    if rowCache ~= nil then
        local center = rowCache[col]
        if center ~= nil then
            return center.x, center.y
        end
    end

    local outerLeftX, outerLeftY, outerRightX, outerRightY,
        innerLeftX, innerLeftY, innerRightX, innerRightY = self:getCellCorners(col, row)
    return (outerLeftX + outerRightX + innerLeftX + innerRightX) * 0.25,
           (outerLeftY + outerRightY + innerLeftY + innerRightY) * 0.25
end

function Board:startSwapDrawAnimation(colA, rowA, colB, rowB)
    local indexA = self.cells:_get_index(colA, rowA)
    local indexB = self.cells:_get_index(colB, rowB)
    self.swapDrawAnimation = {
        progress = 1.0,
        byIndex = {
            [indexA] = { col = colA, row = rowA, fromCol = colB, fromRow = rowB },
            [indexB] = { col = colB, row = rowB, fromCol = colA, fromRow = rowA }
        }
    }
end

function Board:updateSwapDrawAnimation()
    if self.swapDrawAnimation == nil then
        return
    end

    self.swapDrawAnimation.progress = self.swapDrawAnimation.progress - self.config.swapDrawAnimationStep
    if self.swapDrawAnimation.progress <= 0 then
        self.swapDrawAnimation = nil
    end
end

function Board:getCellDrawOffset(col, row)
    local animation = self.swapDrawAnimation
    if animation == nil then
        return 0, 0 -- アニメーション中でない.
    end

    local index = self.cells:_get_index(col, row)
    local animCell = animation.byIndex[index]
    if animCell == nil then
        return 0, 0
    end

    local dstX, dstY = self:getCellCenter(col, row)
    local srcX, srcY = self:getCellCenter(animCell.fromCol, animCell.fromRow)
    local eased = animation.progress * animation.progress
    local scale = self.config.swapDrawOffsetScale
    return (srcX - dstX) * eased * scale, (srcY - dstY) * eased * scale
end

function Board:buildRowRadiusCache()
    local config = self.config
    local outerRx = config.width / 2
    local outerRy = config.height / 2
    local depth = config.depth
    local scaleDelta = 1.0 - config.innerScale

    self.rowRadiusCache = {}
    for boundary = -1, depth + 1 do
        local t = boundary / depth
        local scale = 1.0 - scaleDelta * t
        self.rowRadiusCache[boundary] = {
            rx = outerRx * scale,
            ry = outerRy * scale
        }
    end
end

function Board:rebuildFrameGeometryCache()
    local config = self.config
    local columns = config.columns
    local depth = config.depth
    local cx = config.cx
    local cy = config.cy
    local twoPi = math.pi * 2
    local offsetColumns = (self.currentColumnAngleOffset or config.columnAngleOffsetColumns or 0) - 1
    local framePointCache = self.framePointCache
    local frameCellCenterCache = self.frameCellCenterCache

    for colBoundary = 0, columns do
        local angle = (colBoundary + offsetColumns) / columns * twoPi - math.pi / 2
        local cosAngle = math.cos(angle)
        local sinAngle = math.sin(angle)
        local columnCache = framePointCache[colBoundary]
        if columnCache == nil then
            columnCache = {}
            framePointCache[colBoundary] = columnCache
        end

        for rowBoundary = -1, depth + 1 do
            local radius = self.rowRadiusCache[rowBoundary]
            local point = columnCache[rowBoundary]
            if point == nil then
                point = {}
                columnCache[rowBoundary] = point
            end

            point.x = cx + cosAngle * radius.rx
            point.y = cy + sinAngle * radius.ry
        end
    end

    for row = 0, depth + 1 do
        local rowCache = frameCellCenterCache[row]
        if rowCache == nil then
            rowCache = {}
            frameCellCenterCache[row] = rowCache
        end

        local outerBoundary = row - 1
        local innerBoundary = row
        for col = 1, columns do
            local outerLeft = framePointCache[col - 1][outerBoundary]
            local outerRight = framePointCache[col][outerBoundary]
            local innerLeft = framePointCache[col - 1][innerBoundary]
            local innerRight = framePointCache[col][innerBoundary]
            local center = rowCache[col]
            if center == nil then
                center = {}
                rowCache[col] = center
            end

            center.x = (outerLeft.x + outerRight.x + innerLeft.x + innerRight.x) * 0.25
            center.y = (outerLeft.y + outerRight.y + innerLeft.y + innerRight.y) * 0.25
        end
    end
end

function Board:startSlideUpAnimation()
    if self.slideUpAnimation ~= nil then
        return false
    end

    local incomingRow = {}
    for col = 1, self.config.columns do
        incomingRow[col] = math.random(1, 4)
    end

    self.slideUpAnimation = {
        progress = 0,
        incomingRow = incomingRow
    }

    return true
end

function Board:updateSlideUpAnimation()
    if self.slideUpAnimation == nil then
        return
    end

    local animation = self.slideUpAnimation
    animation.progress = animation.progress + self.config.slideUpAnimationStep

    if animation.progress < 1 then
        return
    end

    self.cells:slideY(-1)
    for col = 1, self.config.columns do
        self.cells:set(col, self.config.depth, animation.incomingRow[col])
    end

    self.slideUpAnimation = nil
end

-- せり上げアニメーションが終了したかどうか.
function Board:isEndSlidingUp()
	return self.slideUpAnimation == nil
end

function Board:getSlideUpDrawOffset(col, row)
    if self.slideUpAnimation == nil then
        return 0, 0
    end

    local progress = self.slideUpAnimation.progress
    local srcX, srcY = self:getCellCenter(col, row)
    local dstX, dstY = self:getCellCenter(col, row - 1)
    return (dstX - srcX) * progress, (dstY - srcY) * progress
end

function Board:getIncomingSlideUpOffset(col)
    if self.slideUpAnimation == nil then
        return 0, 0
    end

    local progress = self.slideUpAnimation.progress
    local srcX, srcY = self:getCellCenter(col, self.config.depth + 1)
    local dstX, dstY = self:getCellCenter(col, self.config.depth)
    return (srcX - dstX) * (1 - progress), (srcY - dstY) * (1 - progress)
end

function Board:buildEraseIndexSet(eraseList)
    local indexSet = {}

    if eraseList == nil or eraseList:isEmpty() then
        return indexSet
    end

    for _, group in ipairs(eraseList.groups) do
        for _, index in ipairs(group.indices) do
            indexSet[index] = true
        end
    end

    return indexSet
end

function Board:startEraseBlinkAnimation(eraseList)
    if eraseList == nil or eraseList:isEmpty() then
        return false
    end

	-- 消去アニメーション設定.
    self.eraseBlinkAnimation = {
        remainingFrames = 24, -- 24Fで終了.
        tick = 0,
        visible = true,
        indexSet = self:buildEraseIndexSet(eraseList),
        eraseList = eraseList
    }

    return true
end

function Board:updateEraseBlinkAnimation()
    if self.eraseBlinkAnimation == nil then
        return
    end

    local animation = self.eraseBlinkAnimation
    animation.remainingFrames = animation.remainingFrames - 1
    animation.tick = animation.tick + 1

    if (animation.tick % 4) == 0 then
        animation.visible = not animation.visible
    end

    if animation.remainingFrames <= 0 then
        self:eraseByList(animation.eraseList)
        self.eraseBlinkAnimation = nil
    end
end

function Board:isEndEraseAnimation()
	return self.eraseBlinkAnimation == nil
end

function Board:isCellBlinkHidden(col, row)
    local animation = self.eraseBlinkAnimation
    if animation == nil or animation.visible then
        return false
    end

    local index = self.cells:_get_index(col, row)
    return animation.indexSet[index] == true
end

function Board:setCursor(x, y)
    -- 列は円周上なのでループ、行は範囲内にクランプ.
	local minY = 1
	if self.mode == BOARD_MODE.VERTICAL_SWAP then
		minY = 2 -- 縦入れ替えモードの場合、カーソルは最下段以外にする（下段は入れ替え対象のみになるため）
	end
    self.cursorX = ((x - 1) % self.config.columns) + 1
    self.cursorY = math.max(minY, math.min(y, self.config.depth))
end

function Board:getCursor()
    return self.cursorX, self.cursorY
end

-- カーソル移動.
function Board:moveCursorBy(dx, dy)
    self:setCursor(self.cursorX + dx, self.cursorY + dy)

    if dx ~= 0 then
        -- 右移動で左回転、左移動で右回転となるように追従目標を更新する.
        self.targetColumnAngleOffset = self.targetColumnAngleOffset - dx
    end
end

-- 回転の更新.
function Board:updateBoardRotation()
    local diff = self.targetColumnAngleOffset - self.currentColumnAngleOffset
    local step = self.config.cursorFollowRotationStep

	-- 割合で補間します.
	self.currentColumnAngleOffset += (diff * step)
end

-- カーソルを左に移動.
function Board:moveCursorLeft()
    self:moveCursorBy(-1, 0)
end

-- カーソルを右に移動.
function Board:moveCursorRight()
    self:moveCursorBy(1, 0)
end

-- カーソルを上に移動.
function Board:moveCursorUp()
    self:moveCursorBy(0, -1)
end

-- カーソルを下に移動.
function Board:moveCursorDown()
    self:moveCursorBy(0, 1)
end

-- 指定した位置のパネルを交換する.
function Board:swapCells(dx, dy)
	local x1, y1 = self.cursorX, self.cursorY
    local x2, y2 = self:normalizeColumn(x1 + dx), y1 + dy
    if not self:isValidRow(y2) then
        return
    end

    self.cells:swap(x1, y1, x2, y2, false, false)
    self:startSwapDrawAnimation(x1, y1, x2, y2)
end

-- 全体をせり上げて新しいパネルを出現させる.
function Board:slideUpNewRow()
    self:startSlideUpAnimation()
end

-- 接続チェックをするためのノードIDを取得する.
function Board:getNodeId(columnBoundary, rowBoundary)
    local normalizedColumn = ((columnBoundary - 1) % self.config.columns) + 1
    return rowBoundary * self.config.columns + normalizedColumn
end

function Board:getNodeKey(columnBoundary, rowBoundary)
	return self:getNodeId(columnBoundary, rowBoundary)
end

-- 各パネルの接続関係をノードとエッジの集合として表現する.
function Board:getCellEdge(col, row, blockType)
	--[[
		[outerLeft]  ---- [outerRight]
		     |              |
	         |     cell     |
		     |              |
		[innerLeft]  ---- [innerRight]
	--]]
    -- row が大きいほど外周になるように、外側境界を row、内側境界を row+1 とする.
    local outerLeft  = self:getNodeId(col,     row)     -- 左上の境界点
    local outerRight = self:getNodeId(col + 1, row)     -- 右上の境界点
    local innerLeft  = self:getNodeId(col,     row + 1) -- 左下の境界点
    local innerRight = self:getNodeId(col + 1, row + 1) -- 右下の境界点
    if blockType == BLOCK.SLASH then
        return innerLeft, outerRight -- / の場合は左下と右上がつながる
    elseif blockType == BLOCK.BACKSLASH then
        return outerLeft, innerRight -- \ の場合は左上と右下がつながる
    elseif blockType == BLOCK.VALLEY then
        return outerLeft, outerRight -- 谷型の場合は左上と右上がつながる
    elseif blockType == BLOCK.PEAK then
        return innerLeft, innerRight -- 山型の場合は左下と右下がつながる
    end

    return nil, nil
end

function Board:addAdjacency(adjacency, adjacencyLookup, a, b)
    local aLookup = adjacencyLookup[a]
    if aLookup == nil then
        aLookup = {}
        adjacencyLookup[a] = aLookup
        adjacency[a] = {}
    end

    local bLookup = adjacencyLookup[b]
    if bLookup == nil then
        bLookup = {}
        adjacencyLookup[b] = bLookup
        adjacency[b] = {}
    end

    if not aLookup[b] then
        aLookup[b] = true
        bLookup[a] = true
        local aNeighbors = adjacency[a]
        local bNeighbors = adjacency[b]
        aNeighbors[#aNeighbors + 1] = b
        bNeighbors[#bNeighbors + 1] = a
    end
end

function Board:buildCellGraph()
    local nodeToCells = {}
    local edgeByIndex = {}
    local adjacency = {}
    local adjacencyLookup = {}
    local config = self.config
    local depth = config.depth
    local columns = config.columns
    local cells = self.cells

    for row = 1, depth do
        for col = 1, columns do
            local blockType = cells:get(col, row)
            if blockType ~= BLOCK.EMPTY then
                local index = cells:_get_index(col, row)
                local a, b = self:getCellEdge(col, row, blockType)
                if a ~= nil and b ~= nil then
                    edgeByIndex[index] = { a = a, b = b }

                    local aCells = nodeToCells[a]
                    if aCells == nil then
                        aCells = {}
                        nodeToCells[a] = aCells
                    end
                    aCells[#aCells + 1] = index

                    local bCells = nodeToCells[b]
                    if bCells == nil then
                        bCells = {}
                        nodeToCells[b] = bCells
                    end
                    bCells[#bCells + 1] = index
                end
            end
        end
    end

    for _, cellsAtNode in pairs(nodeToCells) do
        for i = 1, #cellsAtNode do
            for j = i + 1, #cellsAtNode do
                self:addAdjacency(adjacency, adjacencyLookup, cellsAtNode[i], cellsAtNode[j])
            end
        end
    end

    return adjacency, nodeToCells, edgeByIndex
end

function Board:isEdgeInCycle(edgeIndex, edgeByIndex, nodeToCells)
    local edge = edgeByIndex[edgeIndex]
    if edge == nil then
        return false
    end

    local startNode = edge.a
    local goalNode = edge.b
    local queue = { startNode }
    local head = 1
    local visitedNodes = {}
    visitedNodes[startNode] = true

    while head <= #queue do
        local currentNode = queue[head]
        head = head + 1

        local connectedEdges = nodeToCells[currentNode]
        if connectedEdges ~= nil then
            for i = 1, #connectedEdges do
                local nextEdgeIndex = connectedEdges[i]
            if nextEdgeIndex ~= edgeIndex then
                local nextEdge = edgeByIndex[nextEdgeIndex]
                if nextEdge ~= nil then
                    local nextNode = nil
                    if nextEdge.a == currentNode then
                        nextNode = nextEdge.b
                    elseif nextEdge.b == currentNode then
                        nextNode = nextEdge.a
                    end

                    if nextNode ~= nil then
                        if nextNode == goalNode then
                            return true
                        end

                        if not visitedNodes[nextNode] then
                            visitedNodes[nextNode] = true
                            table.insert(queue, nextNode)
                        end
                    end
                end
            end
            end
        end
    end

    return false
end

function Board:collectConnectedIndices(startIndex, adjacency, allowSet, visited)
    local ordered = {}
    local stack = { startIndex }

    while #stack > 0 do
        local current = stack[#stack]
        stack[#stack] = nil
        if not visited[current] and allowSet[current] then
            visited[current] = true
            ordered[#ordered + 1] = current

            local neighbors = adjacency[current] or {}
            for i = 1, #neighbors do
                local neighborIndex = neighbors[i]
                if allowSet[neighborIndex] and not visited[neighborIndex] then
                    stack[#stack + 1] = neighborIndex
                end
            end
        end
    end

    return ordered
end

function Board:walkCycle(startIndex, adjacency, componentSet, visited)
    local ordered = {}
    local neighbors = adjacency[startIndex]
    if neighbors == nil then
        return ordered
    end

    local firstNeighbor
    for i = 1, #neighbors do
        local neighborIndex = neighbors[i]
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
        ordered[#ordered + 1] = current
        visited[current] = true

        local nextIndex = nil
        local nextNeighbors = adjacency[current] or {}
        for i = 1, #nextNeighbors do
            local neighborIndex = nextNeighbors[i]
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
    local adjacency, nodeToCells, edgeByIndex = self:buildCellGraph()
    local eraseList = ErasePanelList()
    local cycleCellSet = {}
    local columns = self.config.columns
    local depth = self.config.depth
    local maxIndex = columns * depth

    for edgeIndex = 1, maxIndex do
        if edgeByIndex[edgeIndex] ~= nil and self:isEdgeInCycle(edgeIndex, edgeByIndex, nodeToCells) then
            cycleCellSet[edgeIndex] = true
        end
    end

    local visited = {}

    for row = 1, depth do
        for col = 1, columns do
            local index = self.cells:_get_index(col, row)
            local blockType = self.cells:get(col, row)
            if blockType ~= BLOCK.EMPTY and cycleCellSet[index] and not visited[index] then
                local component = self:collectConnectedIndices(index, adjacency, cycleCellSet, visited)
                if #component > 0 then
                    local group = ErasePanelGroup()
                    for i = 1, #component do
                        group:addIndex(component[i])
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
    local radius = self.rowRadiusCache[boundary]
    if radius ~= nil then
        return radius.rx, radius.ry
    end

    local outerRx = self.config.width / 2
    local outerRy = self.config.height / 2
    local t = boundary / self.config.depth
    local scale = 1.0 - (1.0 - self.config.innerScale) * t
    return outerRx * scale, outerRy * scale
end

function Board:getColumnBoundaryAngle(boundary)
	-- カラムのオフセット.
    local offsetColumns = self.currentColumnAngleOffset or self.config.columnAngleOffsetColumns or 0
	offsetColumns -= 1 -- Luaが1始まりなのでオフセットを1減らす.
    return (boundary + offsetColumns) / self.config.columns * math.pi * 2 - math.pi / 2
end

function Board:getCellCorners(col, row)
    local leftBoundary = col - 1
    local rightBoundary = col
    local outerBoundary = row - 1
    local innerBoundary = row
    local framePointCache = self.framePointCache

    if framePointCache[leftBoundary] ~= nil and framePointCache[rightBoundary] ~= nil then
        local outerLeft = framePointCache[leftBoundary][outerBoundary]
        local outerRight = framePointCache[rightBoundary][outerBoundary]
        local innerLeft = framePointCache[leftBoundary][innerBoundary]
        local innerRight = framePointCache[rightBoundary][innerBoundary]
        if outerLeft ~= nil and outerRight ~= nil and innerLeft ~= nil and innerRight ~= nil then
            return outerLeft.x, outerLeft.y, outerRight.x, outerRight.y,
                   innerLeft.x, innerLeft.y, innerRight.x, innerRight.y
        end
    end

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

function Board:buildBoardGuideEllipseCache()
    local cacheWidth = math.ceil(self.config.width)
    local cacheHeight = math.ceil(self.config.height)
    local guideImage = gfx.image.new(cacheWidth, cacheHeight)

    if guideImage == nil then
        return nil
    end

    gfx.pushContext(guideImage)
    gfx.clear(gfx.kColorClear)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)

    local centerX = cacheWidth * 0.5
    local centerY = cacheHeight * 0.5

    for b = 0, self.config.depth do
        local rx, ry = self:getRowBoundaryRadius(b)
        self:drawEllipsePolylineAt(centerX, centerY, rx, ry)
    end

    gfx.popContext()
    return guideImage
end

function Board:drawEllipsePolylineAt(cx, cy, rx, ry)
    local steps = 320 -- 円周を分割するステップ数。大きいほど滑らかになるが描画コストも上がる.
    local dash = 2 -- 描く区間
    local gap  = 2 -- 空ける区間

    local prevX, prevY

    for i = 0, steps do
        local a = i / steps * math.pi * 2
        local x, y = self:ellipsePoint(cx, cy, rx, ry, a)

        if prevX then
            local period = dash + gap
            if (i % period) < dash then
                gfx.drawLine(prevX, prevY, x, y)
            end
        end

        prevX, prevY = x, y
    end
end

function Board:drawEllipsePolyline(rx, ry)
    self:drawEllipsePolylineAt(self.config.cx, self.config.cy, rx, ry)
end

function Board:drawDashedLine(x1, y1, x2, y2, dash, gap)
    dash = dash or self.config.guideDashLength
    gap = gap or self.config.guideGapLength

    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0 then
        return
    end

    local ux = dx / length
    local uy = dy / length
    local step = dash + gap
    local distance = 0

    while distance < length do
        local segStart = distance
        local segEnd = math.min(distance + dash, length)
        local sx = x1 + ux * segStart
        local sy = y1 + uy * segStart
        local ex = x1 + ux * segEnd
        local ey = y1 + uy * segEnd
        gfx.drawLine(sx, sy, ex, ey)
        distance = distance + step
    end
end

function Board:buildBoardGuideRadialCache()
    local cacheWidth = math.ceil(self.config.width)
    local cacheHeight = math.ceil(self.config.height)
    local guideImage = gfx.image.new(cacheWidth, cacheHeight)

    if guideImage == nil then
        return nil
    end

    local originX = self.config.cx - cacheWidth * 0.5
    local originY = self.config.cy - cacheHeight * 0.5

    gfx.pushContext(guideImage)
    gfx.clear(gfx.kColorClear)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)

    local framePointCache = self.framePointCache
    for c = 0, self.config.columns - 1 do
        local outer = framePointCache[c][0]
        local inner = framePointCache[c][self.config.depth]
        self:drawDashedLine(
            outer.x - originX,
            outer.y - originY,
            inner.x - originX,
            inner.y - originY
        )
    end

    gfx.popContext()
    return guideImage
end

function Board:updateBoardGuideRadialCache()
    local offset = self.currentColumnAngleOffset or self.config.columnAngleOffsetColumns or 0
    local step = self.config.boardGuideRadialCacheStep
    local quantizedOffset = math.floor(offset / step + 0.5) * step

    if self.boardGuideRadialCache ~= nil and self.boardGuideRadialCacheOffset == quantizedOffset then
        return
    end

    self.boardGuideRadialCache = self:buildBoardGuideRadialCache()
    self.boardGuideRadialCacheOffset = quantizedOffset
end

function Board:drawBoardGuide()
    gfx.setLineWidth(1)

    if self.boardGuideEllipseCache ~= nil then
        self.boardGuideEllipseCache:draw(self.config.cx - self.config.width * 0.5, self.config.cy - self.config.height * 0.5)
    else
		for b = 0, self.config.depth do
			local rx, ry = self:getRowBoundaryRadius(b)
			self:drawEllipsePolyline(rx, ry)
		end
    end

    self:updateBoardGuideRadialCache()
    if self.boardGuideRadialCache ~= nil then
        self.boardGuideRadialCache:draw(self.config.cx - self.config.width * 0.5, self.config.cy - self.config.height * 0.5)
    else
        local framePointCache = self.framePointCache
        for c = 0, self.config.columns - 1 do
            local outer = framePointCache[c][0]
            local inner = framePointCache[c][self.config.depth]
            self:drawDashedLine(outer.x, outer.y, inner.x, inner.y)
        end
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

-- ブロックの描画.
function Board:drawGunpeyBlock(col, row, blockType, offsetX, offsetY)
    if blockType == BLOCK.EMPTY then
        return -- 空のセルは描画しない
    end

	offsetX = offsetX or 0
	offsetY = offsetY or 0

    local outerLeftX, outerLeftY, outerRightX, outerRightY,
          innerLeftX, innerLeftY, innerRightX, innerRightY = self:getCellCorners(col, row)

	outerLeftX, outerLeftY = outerLeftX + offsetX, outerLeftY + offsetY
	outerRightX, outerRightY = outerRightX + offsetX, outerRightY + offsetY
	innerLeftX, innerLeftY = innerLeftX + offsetX, innerLeftY + offsetY
	innerRightX, innerRightY = innerRightX + offsetX, innerRightY + offsetY

	-- 各ブロック種別ごとの描画処理.
    if blockType == BLOCK.SLASH then
        gfx.drawLine(innerLeftX, innerLeftY, outerRightX, outerRightY)

    elseif blockType == BLOCK.BACKSLASH then
        gfx.drawLine(outerLeftX, outerLeftY, innerRightX, innerRightY)

    elseif blockType == BLOCK.VALLEY then
        local outerMidX = (outerLeftX + outerRightX) * 0.5
        local outerMidY = (outerLeftY + outerRightY) * 0.5
        local innerMidX = (innerLeftX + innerRightX) * 0.5
        local innerMidY = (innerLeftY + innerRightY) * 0.5
        local valleyT = self.config.valleyHeightRatio
        local valleyApexX = outerMidX + (innerMidX - outerMidX) * valleyT
        local valleyApexY = outerMidY + (innerMidY - outerMidY) * valleyT
        gfx.drawLine(outerLeftX, outerLeftY, valleyApexX, valleyApexY)
        gfx.drawLine(outerRightX, outerRightY, valleyApexX, valleyApexY)

    elseif blockType == BLOCK.PEAK then
        local outerMidX = (outerLeftX + outerRightX) * 0.5
        local outerMidY = (outerLeftY + outerRightY) * 0.5
        local innerMidX = (innerLeftX + innerRightX) * 0.5
        local innerMidY = (innerLeftY + innerRightY) * 0.5
        local peakT = self.config.peakHeightRatio
        local peakApexX = outerMidX + (innerMidX - outerMidX) * peakT
        local peakApexY = outerMidY + (innerMidY - outerMidY) * peakT
        gfx.drawLine(innerLeftX, innerLeftY, peakApexX, peakApexY)
        gfx.drawLine(innerRightX, innerRightY, peakApexX, peakApexY)
    end
end

-- ブロックの描画.
function Board:drawBlocks()
    gfx.setLineWidth(self.config.lineWidth)
    for r = 1, self.config.depth do
        for c = 1, self.config.columns do
			if self:isCellBlinkHidden(c, r) then
				goto continue
			end
            local offsetX, offsetY = self:getCellDrawOffset(c, r)
            local slideX, slideY = self:getSlideUpDrawOffset(c, r)
            self:drawGunpeyBlock(c, r, self.cells:get(c, r), offsetX + slideX, offsetY + slideY)
			::continue::
        end
    end

    if self.slideUpAnimation ~= nil then
        for c = 1, self.config.columns do
            local blockType = self.slideUpAnimation.incomingRow[c]
            local incomingOffsetX, incomingOffsetY = self:getIncomingSlideUpOffset(c)
            self:drawGunpeyBlock(c, self.config.depth, blockType, incomingOffsetX, incomingOffsetY)
        end
    end
end

-- カーソルの描画.
function Board:drawCursor(cursorX, cursorY)
    local outerLeftX, outerLeftY, outerRightX, outerRightY,
          innerLeftX, innerLeftY, innerRightX, innerRightY = self:getCellCorners(cursorX, cursorY)

    gfx.setColor(gfx.kColorXOR)
    gfx.fillPolygon(
        outerLeftX, outerLeftY,
        outerRightX, outerRightY,
        innerRightX, innerRightY,
        innerLeftX, innerLeftY
    )
    gfx.setColor(gfx.kColorBlack)
end