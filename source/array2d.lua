---@diagnostic disable
-- Array2D.lua
-- 2次元配列を1次元配列で管理するユーティリティクラスです。
import "CoreLibs/object"

class("Array2D").extends()
-- コンストラクタ
function Array2D:init(width, height, default_value)
	self.width = width
	self.height = height
	self.data = {}
	self.outOfBoundsValue = -1 -- 境界外の値として返す値（必要に応じて変更可能）
	
	-- 初期値（指定がなければ0）で1次元配列を埋める
	local val = default_value or 0
	for i = 1, width * height do
		self.data[i] = val
	end
end
-- インデックス計算の共通メソッド
function Array2D:_get_index(x, y)
    -- 境界チェック（エラーハンドリング）
    if x < 1 or x > self.width or y < 1 or y > self.height then
		-- 領域外.
		return -1
    end
    -- 1次元インデックスへの変換公式（1始まり用）
    return (y - 1) * self.width + x
end

-- 値の取得 (get)
function Array2D:get(x, y)
    local index = self:_get_index(x, y)
    if index == -1 then
        return self.outOfBoundsValue -- エラー値として-1を返す（必要に応じて変更可能）
    end
    return self.data[index]
end

-- 値の設定 (set)
function Array2D:set(x, y, v)
    local index = self:_get_index(x, y)
    if index == -1 then
        return
    end
    self.data[index] = v
end

-- 値の交換
-- x1, y1: 交換する最初のセルの座標
-- x2, y2: 交換する2つ目のセルの座標
-- bLoopX, bLoopY: ループフラグ (trueの場合、境界を超えた場合に反対側にループする)
function Array2D:swap(x1, y1, x2, y2, bLoopX, bLoopY)
	if bLoopX then
		-- ループ処理: 境界を超えた場合に反対側にループする
		if x1 < 1 then x1 = self.width end
		if x1 > self.width then x1 = 1 end
		if x2 < 1 then x2 = self.width end
		if x2 > self.width then x2 = 1 end
	else
		-- 境界チェック: 境界外の場合は処理を中止する
		if x1 < 1 or x1 > self.width or x2 < 1 or x2 > self.width then
			return
		end
	end
	if bLoopY then
		if y1 < 1 then y1 = self.height end
		if y1 > self.height then y1 = 1 end
		if y2 < 1 then y2 = self.height end
		if y2 > self.height then y2 = 1 end
	else
		-- 境界チェック: 境界外の場合は処理を中止する
		if y1 < 1 or y1 > self.height or y2 < 1 or y2 > self.height then
			return
		end
	end
	local index1 = self:_get_index(x1, y1)
	local index2 = self:_get_index(x2, y2)
	self.data[index1], self.data[index2] = self.data[index2], self.data[index1]
end
