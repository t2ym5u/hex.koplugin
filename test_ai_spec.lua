local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("HexAI", function()
    local Board, AI

    setup(function()
        Board = dofile(DIR .. "board.lua")
        AI    = dofile(DIR .. "ai.lua")
    end)

    local fast = { playouts = 400, max_time = 5, bridges = true }

    it("always returns a legal move, at every level, until the game ends", function()
        math.randomseed(11)
        for _, level in ipairs({ "easy", fast }) do
            for _, n in ipairs({ 7, 9 }) do
                local b = Board:new{ n = n }
                while b.status == "playing" do
                    local mv = AI.chooseMove(b, level)
                    assert.is_number(mv.cell)
                    assert.are.equal(Board.EMPTY, b.cells[mv.cell])
                    b:playIndex(mv.cell)
                end
                assert.is_truthy(b.winner)
            end
        end
    end)

    it("takes a one-move win", function()
        -- Black has rows 1-6 of column 3; (7, 3) or (7, 2) wins.
        local b = Board:new{ n = 7 }
        local white = { {1,6}, {2,6}, {3,6}, {4,6}, {5,6}, {6,6} }
        for r = 1, 6 do
            b:play(r, 3)
            b:play(white[r][1], white[r][2])
        end
        local mv = AI.chooseMove(b, "easy")
        b:playIndex(mv.cell)
        assert.are.equal("won", b.status)
        assert.are.equal(Board.BLACK, b.winner)
    end)

    it("blocks the opponent's only winning cell", function()
        -- White to move; Black's column 3 has one gap at (4, 3) and nothing
        -- else wins for Black, so White must play there.
        local b = Board:new{ n = 7 }
        local moves = { {1,3},{1,7}, {2,3},{2,7}, {3,3},{3,7}, {5,3},{5,7}, {6,3},{6,7}, {7,3} }
        for _, m in ipairs(moves) do b:play(m[1], m[2]) end
        assert.are.equal(Board.WHITE, b.turn)
        assert.are.equal(1, #AI.winningCells(b.cells, 7, Board.BLACK))
        local mv = AI.chooseMove(b, "easy")
        assert.are.same({ 4, 3 }, { b:rc(mv.cell) })
        b:playIndex(mv.cell)
        assert.are.equal(0, #AI.winningCells(b.cells, 7, Board.BLACK))
    end)

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
end)
