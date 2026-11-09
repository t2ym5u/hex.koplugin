-- Difficulty guarantees of the Hex computer opponent: the level table is
-- ordered, every level plays legal moves, takes a one-move win and blocks
-- the opponent's only winning cell, the same seed gives the same move, and
-- Hard stays within its time cap at Kobo speed. No full matches against
-- another level (MCTS games are slow and noisy).
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Hex difficulty", function()
    local Board, AI

    setup(function()
        Board = dofile(DIR .. "board.lua")
        AI    = dofile(DIR .. "ai.lua")
    end)

    after_each(function()
        AI.time_scale = 1
    end)

    local IDS = { "easy", "medium", "hard" }
    local fast = { playouts = 400, max_time = 5, bridges = true }

    -- Black to move, one cell from joining top and bottom down column 3.
    local function oneMoveWin()
        local b = Board:new{ n = 7 }
        local white = { {1,6}, {2,6}, {3,6}, {4,6}, {5,6}, {6,6} }
        for r = 1, 6 do
            b:play(r, 3)
            b:play(white[r][1], white[r][2])
        end
        return b
    end

    -- White to move; Black's column 3 has one gap at (4, 3).
    local function oneGap()
        local b = Board:new{ n = 7 }
        local moves = { {1,3},{1,7}, {2,3},{2,7}, {3,3},{3,7}, {5,3},{5,7}, {6,3},{6,7}, {7,3} }
        for _, m in ipairs(moves) do b:play(m[1], m[2]) end
        return b
    end

    it("orders the level table: more playouts and time from Easy to Hard", function()
        local L = AI.LEVELS
        for i = 2, #IDS do
            assert.is_true(L[IDS[i - 1]].playouts < L[IDS[i]].playouts)
            assert.is_true(L[IDS[i - 1]].max_time <= L[IDS[i]].max_time)
        end
        assert.is_false(L.easy.bridges)
        assert.is_true(L.medium.bridges and L.hard.bridges)
        for _, id in ipairs(IDS) do assert.is_true(L[id].max_time <= 2.3) end
    end)

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

    it("Medium and Hard play legal moves at Kobo speed", function()
        AI.time_scale = 0.04
        math.randomseed(13)
        for _, id in ipairs({ "medium", "hard" }) do
            for _, n in ipairs({ 7, 11 }) do
                local b = Board:new{ n = n }
                for _ = 1, 4 do
                    local mv = AI.chooseMove(b, id)
                    assert.are.equal(Board.EMPTY, b.cells[mv.cell])
                    b:playIndex(mv.cell)
                    local e = b:emptyCells()
                    b:playIndex(e[math.random(#e)])
                end
            end
        end
    end)

    it("takes a one-move win", function()
        -- Black has rows 1-6 of column 3; (7, 3) or (7, 2) wins.
        local b = oneMoveWin()
        local mv = AI.chooseMove(b, "easy")
        b:playIndex(mv.cell)
        assert.are.equal("won", b.status)
        assert.are.equal(Board.BLACK, b.winner)
    end)

    it("blocks the opponent's only winning cell", function()
        -- White to move; Black's column 3 has one gap at (4, 3) and nothing
        -- else wins for Black, so White must play there.
        local b = oneGap()
        assert.are.equal(Board.WHITE, b.turn)
        assert.are.equal(1, #AI.winningCells(b.cells, 7, Board.BLACK))
        local mv = AI.chooseMove(b, "easy")
        assert.are.same({ 4, 3 }, { b:rc(mv.cell) })
        b:playIndex(mv.cell)
        assert.are.equal(0, #AI.winningCells(b.cells, 7, Board.BLACK))
    end)

    it("every level wins at once and blocks the only winning cell", function()
        AI.time_scale = 0.04
        for _, id in ipairs(IDS) do
            local b = oneMoveWin()
            b:playIndex(AI.chooseMove(b, id).cell)
            assert.are.equal(Board.BLACK, b.winner, id .. " missed the win")
            b = oneGap()
            assert.are.same({ 4, 3 }, { b:rc(AI.chooseMove(b, id).cell) })
        end
    end)

    it("gives the same move under the same seed (Easy, Medium)", function()
        -- With a generous time cap the playout count stops the search, so
        -- the move depends on the seed only.
        AI.time_scale = 100
        for _, id in ipairs({ "easy", "medium" }) do
            local function first(seed)
                math.randomseed(seed)
                local b = Board:new{ n = 7 }
                b:play(4, 4)
                return AI.chooseMove(b, id).cell
            end
            assert.are.equal(first(3), first(3))
        end
    end)

    it("keeps every move within its time cap (Kobo budget simulated)", function()
        -- time_scale 0.04 stands for a device ~25x slower: the cap must
        -- stop Hard on 11x11 well before its 20 000 playouts.
        AI.time_scale = 0.04
        math.randomseed(5)
        local b = Board:new{ n = 11 }
        local worst = 0
        for _ = 1, 6 do
            local t0 = os.clock()
            local mv = AI.chooseMove(b, "hard")
            worst = math.max(worst, os.clock() - t0)
            assert.are.equal(Board.EMPTY, b.cells[mv.cell])
            b:playIndex(mv.cell)
        end
        -- 2.3 s x 0.04 = 92 ms of playouts, plus the win/block scan.
        assert.is_true(worst < 0.25)
    end)
end)
