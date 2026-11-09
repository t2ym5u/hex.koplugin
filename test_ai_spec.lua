local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("HexAI", function()
    local Board, AI

    setup(function()
        Board = dofile(DIR .. "board.lua")
        AI    = dofile(DIR .. "ai.lua")
    end)

    local fast = { playouts = 400, max_time = 5, bridges = true }

    it("saves a bridge in its playouts (bridge table sanity)", function()
        -- (3, 3) and (5, 2) form a bridge over the carriers (4, 2) and (4, 3).
        local b = Board:new{ n = 7 }
        b:play(3, 3)            -- Black
        b:play(1, 7)            -- White elsewhere
        b:play(5, 2)            -- Black: bridge with (3, 3) via (4, 2), (4, 3)
        b:play(4, 3)            -- White intrudes
        -- The defending reply is (4, 2): a strong MCTS must find it.
        local mv = AI.chooseMove(b, { playouts = 4000, max_time = 10, bridges = true })
        local r, c = b:rc(mv.cell)
        assert.are.same({ 4, 2 }, { r, c })
    end)

    it("swaps a central opening and keeps an edge one", function()
        local b = Board:new{ n = 9, swap_rule = true }
        b:play(5, 5)
        assert.is_true(AI.chooseMove(b, "easy").swap)
        local e = Board:new{ n = 9, swap_rule = true }
        e:play(1, 4)
        assert.is_nil(AI.chooseMove(e, fast).swap)
    end)

    it("opens on an edge row when the opponent may swap", function()
        math.randomseed(3)
        for _ = 1, 20 do
            local b = Board:new{ n = 9, swap_rule = true }
            local r = b:rc(AI.chooseMove(b, "hard").cell)
            assert.is_true(r == 1 or r == 9)
        end
    end)

    it("beats a random player", function()
        math.randomseed(5)
        local wins = 0
        for g = 1, 6 do
            local b = Board:new{ n = 7 }
            local ai_side = (g % 2 == 1) and Board.BLACK or Board.WHITE
            while b.status == "playing" do
                if b.turn == ai_side then
                    b:playIndex(AI.chooseMove(b, fast).cell)
                else
                    local e = b:emptyCells()
                    b:playIndex(e[math.random(#e)])
                end
            end
            if b.winner == ai_side then wins = wins + 1 end
        end
        assert.are.equal(6, wins)
    end)

    it("reuses its tree only when the position follows from it", function()
        -- Hard keeps its tree between moves; undo, new games and other
        -- sizes must never make it answer with an occupied cell.
        local saved = AI.time_scale
        AI.time_scale = 0.01
        math.randomseed(9)
        for _, n in ipairs({ 7, 9, 7 }) do
            local b = Board:new{ n = n }
            for step = 1, 30 do
                if b.status ~= "playing" then break end
                local mv = AI.chooseMove(b, "hard")
                if mv.swap then b:swap() else
                    assert.are.equal(Board.EMPTY, b.cells[mv.cell])
                    b:playIndex(mv.cell)
                end
                if step % 4 == 0 then b:undo() end
                if b.status == "playing" and step % 3 == 0 then
                    local e = b:emptyCells()
                    b:playIndex(e[math.random(#e)])
                end
            end
        end
        AI.time_scale = saved
    end)
end)
