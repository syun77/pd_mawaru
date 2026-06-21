---@diagnostic disable
--[[
	shot.lua

	Shotクラスは、プレイヤーが発射する弾を表すクラスです。
	Actorクラスを継承し、弾特有の動きや当たり判定を実装します。]]
import "CoreLibs/object"
import "actor"

-- ショットの定義.
class("Shot").extends(Actor)

function Shot:init(x, y)
	Shot.super.init(self, x, y, 4, 4)
	-- print("Shot created at (" .. x .. ", " .. y .. ")")
end

function Shot:update()
	Shot.super.update(self)
	self:move(self.vx, self.vy, false) -- 画面外に出ても移動.
	if self:isOffScreen() then
		self:despawn() -- 画面外に出たら管理情報ごと削除.
	end
end
