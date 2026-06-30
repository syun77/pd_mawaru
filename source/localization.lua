----------------------------------------------
--- Localization
--- L(key)          : 現在言語 → en → key名 の順でフォールバック
--- LF(key, vars)   : L(key) に {変数名} 置換を適用
--- setGameLanguage : 言語切替 + datastore 保存
----------------------------------------------
---@diagnostic disable
import "CoreLibs/graphics"

local pd  <const> = playdate
local gfx <const> = pd.graphics

-- ロードした文字列テーブル.
local _strings = {
	en = {},
	jp = {},
}

-- JSON ファイルから文字列テーブルをロード（json.decodeFile を使用）.
local function loadStrings(folder)
	_strings.en = json.decodeFile(folder .. "/en.json") or {}
	_strings.jp = json.decodeFile(folder .. "/jp.json") or {}
end

-- ============================================================
-- Localization オブジェクト
-- ============================================================
Localization = {
	language = "en",
	_folder = "localization",
}

function Localization:init(folder)
	self._folder = folder or "localization"
	loadStrings(self._folder)

	-- datastore から言語設定を復元.
	local settings = pd.datastore.read("settings") or {}
	local lang = settings.language
	if lang == "en" or lang == "jp" then
		self.language = lang
	else
		-- システム言語を初期値に使用.
		local sysLang = pd.getSystemLanguage()
		if sysLang == pd.LANGUAGE_JAPANESE then
			self.language = "jp"
		else
			self.language = "en"
		end
	end
end

function Localization:setLanguage(lang)
	if lang ~= "en" and lang ~= "jp" then
		lang = "en"
	end
	self.language = lang
end

-- ============================================================
-- L(key) : 文字列取得（jp → en → key名 フォールバック）
-- ============================================================
function L(key)
	local lang = Localization.language

	local val = _strings[lang] and _strings[lang][key]
	if val ~= nil and val ~= "" then
		return val
	end
	-- jp で見つからなければ en にフォールバック.
	if lang ~= "en" then
		val = _strings.en and _strings.en[key]
		if val ~= nil and val ~= "" then
			return val
		end
	end

	-- どちらにもなければキー名をそのまま返す.
	return "[" .. key .. "]"
end

-- ============================================================
-- LF(key, vars) : 変数置換付き文字列取得
-- 例: LF("puzzle_moves_label", { used=3, limit=10 })
--   → "Moves: 3/10"  or  "手数: 3/10"
-- ============================================================
function LF(key, vars)
	local text = L(key)
	if vars == nil then return text end
	for name, value in pairs(vars) do
		text = text:gsub("{" .. name .. "}", tostring(value))
	end
	return text
end

-- ============================================================
-- setGameLanguage : 言語変更 + 設定保存
-- ============================================================
function setGameLanguage(lang)
	Localization:setLanguage(lang)

	local settings = pd.datastore.read("settings") or {}
	settings.language = lang
	pd.datastore.write(settings, "settings")
end
