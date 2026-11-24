local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("HexAI", function()
    local Board, AI

    setup(function()
        Board = dofile(DIR .. "board.lua")
        AI    = dofile(DIR .. "ai.lua")
    end)

    local fast = { playouts = 400, max_time = 5, bridges = true }

    -- The bridge tables the playouts answer intrusions from. (This used to
    -- ask MCTS to find the reply on a 7x7 board, but more playouts move away
    -- from it -- 9/12 at 4 000, 0/12 at 80 000 -- so it was not the one good
    -- move, and the test failed one run in two. 2026-11-24.)
    it("lists a bridge's saving reply in its tables", function()
        -- (3, 3) and (5, 2) form a bridge over the carriers (4, 2) and (4, 3).
        local n = 7
        local idx = function(r, c) return (r - 1) * n + c end
        local function hasSave(x, y, p, q)
            local s = AI._getTables(n).saves[x]
            for k = 1, #s, 3 do
                if s[k] == y and ((s[k + 1] == p and s[k + 2] == q)
                               or (s[k + 1] == q and s[k + 2] == p)) then
                    return true
                end
            end
            return false
        end
        -- White takes (4, 3): Black's answer is (4, 2), and back.
        assert.is_true(hasSave(idx(4, 3), idx(4, 2), idx(3, 3), idx(5, 2)))
        assert.is_true(hasSave(idx(4, 2), idx(4, 3), idx(3, 3), idx(5, 2)))
        -- An edge template: (2, 3) to the top edge over (1, 3) and (1, 4).
        assert.is_true(hasSave(idx(1, 3), idx(1, 4), idx(2, 3), n * n + 1))
        -- Not a bridge: (4, 4) is not a carrier of this one.
        assert.is_false(hasSave(idx(4, 4), idx(4, 2), idx(3, 3), idx(5, 2)))
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
