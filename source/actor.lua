---@diagnostic disable
-- Actor.lua
-- Actorクラスは、ゲーム内のすべての動くオブジェクトの基本クラスです。
-- 位置、速度、移動方法などを管理します。
import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/sprites"

local pd <const> = playdate
local gfx <const> = pd.graphics
local sprite <const> = gfx.sprite

--- Actorクラスの定義.
---@class Actor : playdate.graphics.sprite
---@field vx number X方向の速度
---@field vy number Y方向の速度
---@field ax number X方向の加速度
---@field ay number Y方向の加速度
---@field radius number 当たり判定用の半径。円形コリジョンとして扱う
---@field manager ActorManager? このActorを管理しているActorManager。未登録ならnil
class("Actor").extends(sprite)

-- コンストラクタ.
--- @param x number 初期X座標
--- @param y number 初期Y座標
--- @param w number 幅
--- @param h number 高さ
function Actor:init(x, y, w, h)
	Actor.super.init(self)
	local image = gfx.image.new(w, h, gfx.kColorBlack)
	self:setImage(image)
	self:moveTo(x, y)
	self:add()
	self.vx = 0 -- X方向の速度.
	self.vy = 0 -- Y方向の速度.
	self.ax = 0 -- X方向の加速度.
	self.ay = 0 -- Y方向の加速度.
	self.radius = w * 0.5 -- 当たり判定用の半径（円形と仮定）.
	self.manager = nil -- ActorManagerが管理している場合はそこから削除するための参照.
	-- print("Actor created at (" .. x .. ", " .. y .. ") with size (" .. w .. ", " .. h .. ")")
end

-- 移動.
--- @param dx integer X方向の移動量
--- @param dy integer Y方向の移動量
--- @param bClip boolean 画面外に出ないようにするかどうか
function Actor:move(dx, dy, bClip)
	if bClip == false then
		return self:moveBy(dx, dy)
	end

	-- 画面外に出ないように移動.
	local newX = self.x + dx
	local newY = self.y + dy
	local w2 = self.width * 0.5
	local h2 = self.height * 0.5
	newX = math.max(w2, math.min(newX, pd.display.getWidth() - w2))
	newY = math.max(h2, math.min(newY, pd.display.getHeight() - h2))
	self:moveBy(newX-self.x, newY-self.y)
end

-- 画面外に出ているかどうかを判定する関数.
--- @return boolean 画面外に出ているかどうか.
function Actor:isOffScreen()
	local w2 = self.width * 0.5
	local h2 = self.height * 0.5
	return self.x < -w2 or self.x + w2 > pd.display.getWidth() or
		   self.y < -h2 or self.y + h2 > pd.display.getHeight()
end

-- 角度と速度を指定して移動量を設定する.
--- @param angle number 角度（度）
--- @param speed number 速度
function Actor:setVelocity(angle, speed)
	local rad = math.rad(angle)
	self.vx = math.cos(rad) * speed
	self.vy = math.sin(-rad) * speed
end

-- ActorManagerから生成された場合はそこから消す
-- そうでなければ直接スプライトを削除する.
function Actor:despawn()
	if self.manager ~= nil then
		-- 管理しているActorManagerから削除する.
		self.manager:remove(self)
		return
	end
	self:remove()
end

-- 円の当たり判定を行う.
--- @param other Actor 判定対象のActor
--- @return boolean 当たっているかどうか
function Actor:isCollidingCircle(other)
	local dx = self.x - other.x
	local dy = self.y - other.y
	local distanceSq = dx * dx + dy * dy
	local radiusSum = self.radius + other.radius
	return distanceSq <= radiusSum * radiusSum
end
