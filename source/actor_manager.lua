---@diagnostic disable
--[[
	ActorManager.lua

	ActorManagerクラスは、ゲーム内のすべてのActorを管理するクラスです。
	Actorの生成、削除、取得などの機能を提供します。
--]]
import "CoreLibs/object"

---@class ActorManager
---@field pool Actor[]
---@generic T
class("ActorManager").extends()

--- コンストラクタ.
---@generic T
---@param actorClass fun(...): T 生成を行うクラス.
function ActorManager:init(actorClass)
	self.actorClass = actorClass
	self.pool = {}
end

--- Actorの生成.
---@generic T
---@param ... any
---@return T
function ActorManager:create(...)
	local actor = self.actorClass(...)
	---@cast actor any
	actor.manager = self -- Actorに自分を管理者として設定.
	table.insert(self.pool, actor)
	return actor
end

--- 外部から要素を追加する.
--- @generic T
--- @param actor T
function ActorManager:add(actor)
	---@cast actor any
	actor.manager = self -- Actorに自分を管理者として設定.
	table.insert(self.pool, actor)
end

--- すべてのActorを取得.
---@generic T
---@return T[]
function ActorManager:getAll()
	return self.pool
end

--- Actorの削除.
---@generic T
---@param actor T
function ActorManager:remove(actor)
	---@cast actor any
	for i = #self.pool, 1, -1 do
		if self.pool[i] == actor then
			table.remove(self.pool, i)
			actor.manager = nil
			actor:remove()
			return true
		end
	end
	return false
end

--- Actor生成数の取得.
--- @generic T
--- @return integer 生成されているActorの数.
function ActorManager:getCount()
	return #self.pool
end

--- foreachで管理しているActorに処理を行う.
--- @generic T
--- @param func fun(actor: T) 処理を行う関数.
function ActorManager:forEach(func)
	for _, actor in ipairs(self.pool) do
		func(actor)
	end
end

--- 指定の条件に当てはまるActorをリストで取得.
--- @generic T
--- @param predicate fun(actor: T): boolean 判定条件を行う関数.
--- @return T[] 条件に一致するActorのリスト
function ActorManager:findAll(predicate)
	local result = {}
	for _, actor in ipairs(self.pool) do
		if predicate(actor) then
			-- 条件に一致.
			table.insert(result, actor)
		end
	end
	return result
end

--- 指定の条件に当てはまる最初のActorを取得.
--- @generic T
--- @param predicate fun(actor: T): boolean 判定条件を行う関数.
--- @return T? actor 最初に見つかったActor、見つからない場合はnil
function ActorManager:findFirst(predicate)
	for _, actor in ipairs(self.pool) do
		if predicate(actor) then
			return actor
		end
	end
	return nil
end
