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
        error(string.format("Index out of bounds: (%d, %d) on size (%dx%d)", x, y, self.width, self.height))
    end
    -- 1次元インデックスへの変換公式（1始まり用）
    return (y - 1) * self.width + x
end

-- 値の取得 (get)
function Array2D:get(x, y)
    local index = self:_get_index(x, y)
    return self.data[index]
end

-- 値の設定 (set)
function Array2D:set(x, y, v)
    local index = self:_get_index(x, y)
    self.data[index] = v
end
