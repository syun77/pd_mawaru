---@diagnostic disable
--[[
	GameContext.lua

	GameContextクラスは、ゲーム全体の状態を管理するクラスです。
	プレイヤー、敵、弾などの共有オブジェクトを保持し、ゲームの初期化や状態管理を行います。
--]]
import "CoreLibs/object"
import "actor_manager"
import "sound"

class("GameContext").extends()

GameContext.instance = nil

-- シングルトンインスタンスを取得.
function GameContext.getInstance()
	if GameContext.instance == nil then
		-- GameContext:init()が呼び出されます.
		GameContext.instance = GameContext()
	end
	return GameContext.instance
end

-- 初期化.
function GameContext:init()
	-- ここにゲームで使うオブジェクトを初期化.
	self.sound = Sound() -- init()呼び出されます.
end

-- 破棄.
function GameContext:destroy()
	-- ここにゲームで使うオブジェクトを破棄.
	self.sound = nil
end

-- ゲームで使う共有オブジェクトを一度だけ初期化する.
function GameContext:setup()
	-- ここにゲームで使うオブジェクトをセットアップ.
end
