local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("HexBoard", function()
    local Board

    setup(function()
        Board = dofile(DIR .. "board.lua")
    end)

    -- Plays a list of {r, c} pairs, alternating colours from Black.
    local function playAll(b, moves)
        local res
        for _, m in ipairs(moves) do res = b:play(m[1], m[2]) end
        return res
    end

    describe("new / reset", function()
        it("starts empty with Black to move", function()
            local b = Board:new{ n = 7 }
            assert.are.equal(7, b.n)
            assert.are.equal(Board.BLACK, b.turn)
            assert.are.equal("playing", b.status)
            for i = 1, 49 do assert.are.equal(Board.EMPTY, b.cells[i]) end
        end)

        it("falls back to the default size on an unknown one", function()
            assert.are.equal(Board.DEFAULT_N, Board:new{ n = 8 }.n)
        end)
    end)

    describe("neighbours", function()
        it("gives an inner cell six neighbours on the rhombus", function()
            local b = Board:new{ n = 7 }
            local got = {}
            for _, j in ipairs(b:neighbours(b:index(4, 4))) do
                local r, c = b:rc(j)
                got[#got + 1] = r .. "," .. c
            end
            table.sort(got)
            assert.are.same({ "3,4", "3,5", "4,3", "4,5", "5,3", "5,4" }, got)
        end)

        it("gives the acute corners two and the obtuse corners three", function()
            local b = Board:new{ n = 7 }
            assert.are.equal(2, #b:neighbours(b:index(1, 1)))
            assert.are.equal(2, #b:neighbours(b:index(7, 7)))
            assert.are.equal(3, #b:neighbours(b:index(1, 7)))
            assert.are.equal(3, #b:neighbours(b:index(7, 1)))
        end)
    end)

    describe("play", function()
        it("places a stone and passes the turn", function()
            local b = Board:new{ n = 7 }
            assert.are.equal("ok", b:play(4, 4))
            assert.are.equal(Board.BLACK, b:get(4, 4))
            assert.are.equal(Board.WHITE, b.turn)
        end)

        it("refuses an occupied or off-board cell", function()
            local b = Board:new{ n = 7 }
            b:play(4, 4)
            assert.are.equal("occupied", b:play(4, 4))
            assert.are.equal("invalid", b:play(0, 4))
            assert.are.equal("invalid", b:play(4, 8))
            assert.are.equal(Board.WHITE, b.turn)
        end)
    end)

    describe("win detection", function()
        it("Black wins with a straight column, top to bottom", function()
            local b = Board:new{ n = 7 }
            local moves = {}
            for r = 1, 7 do
                moves[#moves + 1] = { r, 1 }
                if r < 7 then moves[#moves + 1] = { r, 7 } end
            end
            assert.are.equal("won", playAll(b, moves))
            assert.are.equal(Board.BLACK, b.winner)
            assert.are.equal(7, #b.chain)
            assert.is_true(b:isChainCell(b:index(4, 1)))
        end)

        it("Black wins along a zig-zag that only hex adjacency allows", function()
            -- (r, c) -> (r+1, c-1) is a hex neighbour; a square grid would
            -- call these cells disconnected.
            local b = Board:new{ n = 7 }
            local white = { {1,1}, {1,2}, {2,1}, {2,2}, {3,1}, {3,2} }
            local res
            for k = 1, 7 do
                res = b:play(k, 8 - k)
                if k < 7 then b:play(white[k][1], white[k][2]) end
            end
            assert.are.equal("won", res)
            assert.are.equal(Board.BLACK, b.winner)
        end)

        it("White wins with a row, left to right, and Black's column does not count for White", function()
            local b = Board:new{ n = 7 }
            local moves = {}
            for c = 1, 7 do
                moves[#moves + 1] = { 7, c }      -- Black along the bottom row
                moves[#moves + 1] = { 3, c }      -- White along row 3
            end
            -- Black's bottom row joins left and right, which is White's goal,
            -- not Black's: the game must go on until White completes row 3.
            local res
            for k, m in ipairs(moves) do
                res = b:play(m[1], m[2])
                if k < #moves then assert.are.equal("ok", res) end
            end
            assert.are.equal("won", res)
            assert.are.equal(Board.WHITE, b.winner)
        end)

        it("does not let the anti-diagonal neighbour leak a connection", function()
            -- (r, c) and (r+1, c+1) are NOT adjacent in Hex.
            local b = Board:new{ n = 7 }
            local diag = {}
            for k = 1, 7 do diag[#diag + 1] = { k, k } end
            local res
            local filler = { {1,7}, {2,7}, {3,7}, {4,7}, {5,7}, {6,7} }
            for k = 1, 7 do
                res = b:play(diag[k][1], diag[k][2])
                if k < 7 then b:play(filler[k][1], filler[k][2]) end
            end
            assert.are.equal("ok", res)
            assert.are.equal("playing", b.status)
        end)

        it("always has exactly one winner on a full board", function()
            math.randomseed(7)
            for _ = 1, 50 do
                local b = Board:new{ n = 7 }
                while b.status == "playing" do
                    local e = b:emptyCells()
                    b:playIndex(e[math.random(#e)])
                end
                local black = Board.findWinningChain(b.cells, 7, Board.BLACK)
                local white = Board.findWinningChain(b.cells, 7, Board.WHITE)
                -- The game stops at the first connection, so at most the
                -- winner is connected.
                assert.is_truthy(b.winner == Board.BLACK and black or white)
                assert.is_false(black ~= nil and white ~= nil)
            end
        end)

        it("refuses moves once the game is over", function()
            local b = Board:new{ n = 7 }
            for r = 1, 7 do
                b:play(r, 1)
                if r < 7 then b:play(r, 7) end
            end
            assert.are.equal("over", b:play(5, 5))
        end)
    end)

    describe("swap rule", function()
        it("is only offered to White, right after Black's first stone", function()
            local b = Board:new{ n = 7, swap_rule = true }
            assert.is_false(b:canSwap())
            b:play(2, 5)
            assert.is_true(b:canSwap())
            b:play(4, 4)
            assert.is_false(b:canSwap())
        end)

        it("is never offered with the rule off", function()
            local b = Board:new{ n = 7, swap_rule = false }
            b:play(2, 5)
            assert.is_false(b:canSwap())
            assert.are.equal("not_allowed", b:swap())
        end)

        it("mirrors the stone to White across the diagonal and gives Black the move", function()
            local b = Board:new{ n = 7, swap_rule = true }
            b:play(2, 5)
            assert.are.equal("ok", b:swap())
            assert.are.equal(Board.EMPTY, b:get(2, 5))
            assert.are.equal(Board.WHITE, b:get(5, 2))
            assert.are.equal(Board.BLACK, b.turn)
            assert.is_false(b:canSwap())
        end)

        it("undoes a swap back to the opening stone", function()
            local b = Board:new{ n = 7, swap_rule = true }
            b:play(3, 3)
            b:swap()
            assert.is_true(b:undo())
            assert.are.equal(Board.BLACK, b:get(3, 3))
            assert.are.equal(Board.WHITE, b.turn)
            assert.is_true(b:canSwap())
        end)
    end)

    describe("undo", function()
        it("takes back a stone and the turn", function()
            local b = Board:new{ n = 7 }
            b:play(4, 4)
            assert.is_true(b:undo())
            assert.are.equal(Board.EMPTY, b:get(4, 4))
            assert.are.equal(Board.BLACK, b.turn)
        end)

        it("reopens a won game", function()
            local b = Board:new{ n = 7 }
            for r = 1, 7 do
                b:play(r, 1)
                if r < 7 then b:play(r, 7) end
            end
            assert.is_true(b:undo())
            assert.are.equal("playing", b.status)
            assert.is_nil(b.winner)
            assert.are.equal(Board.BLACK, b.turn)
        end)

        it("returns false with nothing to undo", function()
            assert.is_false(Board:new{ n = 7 }:undo())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips a game in progress, swap included", function()
            local b = Board:new{ n = 9, swap_rule = true }
            b:play(3, 4); b:swap(); b:play(5, 5); b:play(6, 2)
            local c = Board:new()
            assert.is_true(c:load(b:serialize()))
            assert.are.equal(9, c.n)
            assert.is_true(c.swap_rule)
            assert.are.same(b.cells, c.cells)
            assert.are.equal(b.turn, c.turn)
            assert.are.equal(#b.history, #c.history)
            -- And undo still works after a reload.
            assert.is_true(c:undo())
            assert.are.equal(Board.EMPTY, c:get(6, 2))
        end)

        it("round-trips a finished game", function()
            local b = Board:new{ n = 7 }
            for r = 1, 7 do
                b:play(r, 1)
                if r < 7 then b:play(r, 7) end
            end
            local c = Board:new()
            assert.is_true(c:load(b:serialize()))
            assert.are.equal("won", c.status)
            assert.are.equal(Board.BLACK, c.winner)
        end)

        it("rejects garbage and impossible move lists", function()
            local c = Board:new{ n = 7 }
            assert.is_false(c:load(nil))
            assert.is_false(c:load({ n = 8, history = {} }))
            assert.is_false(c:load({ n = 7, history = { { kind = "play", cell = 5 }, { kind = "play", cell = 5 } } }))
            assert.is_false(c:load({ n = 7, history = { { kind = "swap" } } }))
            -- A failed load leaves the board as it was.
            assert.are.equal(7, c.n)
            assert.are.equal(0, #c.history)
        end)
    end)
end)
