---@diagnostic disable
import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/sprites"
import "localization"
import "title"
import "mode_endless"
import "mode_puzzle"

local pd <const> = playdate
local gfx <const> = pd.graphics

-- 50FPSに高速化.
pd.display.setRefreshRate(50)

-- フォント読み込み.
local font = gfx.font.new("fonts/k8x12")
pd.graphics.setFont(font)

-- ローカライズ初期化（localization/ フォルダを使用）.
Localization:init("localization")

-- 現在実行中のシーン.
local currentScene = nil

-- シーン切り替え.
local function changeScene(nextScene)
    if currentScene ~= nil and currentScene.exit ~= nil then
		-- 前のシーンの終了処理.
        currentScene:exit()
    end

	-- 次のシーンに切り替え.
    currentScene = nextScene

    if currentScene ~= nil and currentScene.enter ~= nil then
		-- 次のシーンの開始処理.
        currentScene:enter()
    end
end

-- タイトルシーンの開始.
local function openTitleScene()
    local titleScene = TitleScene(function(modeId)
        if modeId == "endless" then
			-- エンドレスモード.
            changeScene(ModeEndless(openTitleScene))
        elseif modeId == "puzzle" then
			-- パズルモード.
            changeScene(ModePuzzle(openTitleScene))
        end
    end)
    changeScene(titleScene)
end

-- システムメニューに言語切替を追加（タイトルシーン開始前に一度だけ設定）.
do
	local sysMenu = pd.getSystemMenu()
	local langOptions = { "en", "jp" }
	local initialLang = (Localization.language == "jp") and "jp" or "en"
	sysMenu:addOptionsMenuItem("Language", langOptions, initialLang, function(value)
		local lang = (value == "jp") and "jp" or "en"
		setGameLanguage(lang)
	end)
end

-- タイトルシーンを開始.
openTitleScene()

-- メインループ.
function playdate.update()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)

    if currentScene ~= nil then
        if currentScene.update ~= nil then
            currentScene:update()
        end
        if currentScene.draw ~= nil then
            currentScene:draw()
        end
    end

    pd.drawFPS(4, 4)
end
