---@diagnostic disable
import "CoreLibs/graphics"
import "CoreLibs/object" -- classを使うために必要.
import "CoreLibs/sprites" -- spriteを使うために必要.
import "game_context"
import "board"

local pd <const> = playdate
local gfx <const> = pd.graphics

local gameContext = GameContext.getInstance()
gameContext:setup()

local board = Board()

function playdate.update()
    gfx.clear(gfx.kColorWhite)

    gfx.setColor(gfx.kColorBlack)

    board:draw()

    playdate.drawFPS(4, 4)
end
