-- ---------------------------------------------------------------------------
-- HexBoard — rules of Hex on an n×n rhombus
--
-- Cells are kept in one flat array, index i = (r - 1) * n + c, because the AI
-- copies the position thousands of times a second and a flat array is the
-- cheapest thing to copy. (r, c) helpers exist for the UI and the tests.
--
-- Black (player 1) moves first and joins the TOP and BOTTOM rows; White
-- (player 2) joins the LEFT and RIGHT columns. A full board always has exactly
-- one winner, so there is no draw.
--
-- On this rhombus each cell touches six others:
--   (r-1, c) (r-1, c+1)
--   (r, c-1)            (r, c+1)
--   (r+1, c-1) (r+1, c)
--
-- Swap (pie) rule: when it is on, White's first turn may be "swap" instead of
-- a stone. The colours stay with the players -- Black's stone is replaced by a
-- White stone mirrored across the long diagonal, (r, c) -> (c, r), and Black
-- moves again. This is the usual way to play the rule with fixed sides, and it
-- is strictly equivalent to swapping colours.
-- ---------------------------------------------------------------------------

local EMPTY, BLACK, WHITE = 0, 1, 2

local SIZES = { 7, 9, 11 }
local DEFAULT_N = 9

local NEIGHBOUR_DELTAS = { { -1, 0 }, { -1, 1 }, { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 0 } }

-- Neighbour lists are the same for every board of a size: built once.
local nbr_cache = {}
local function neighbourTable(n)
    local t = nbr_cache[n]
    if t then return t end
    t = {}
    for r = 1, n do
        for c = 1, n do
            local list = {}
            for _, d in ipairs(NEIGHBOUR_DELTAS) do
                local rr, cc = r + d[1], c + d[2]
                if rr >= 1 and rr <= n and cc >= 1 and cc <= n then
                    list[#list + 1] = (rr - 1) * n + cc
                end
            end
            t[(r - 1) * n + c] = list
        end
    end
    nbr_cache[n] = t
    return t
end

local function validSize(n)
    for _, s in ipairs(SIZES) do
        if s == n then return true end
    end
    return false
end

-- Returns the cells of `player`'s chain joining its two edges, or nil.
-- Black: row 1 to row n. White: column 1 to column n.
local function findWinningChain(cells, n, player)
    local nbr = neighbourTable(n)
    local seen, stack, parent = {}, {}, {}
    for k = 1, n do
        local i = (player == BLACK) and k or ((k - 1) * n + 1)
        if cells[i] == player then
            seen[i] = true
            stack[#stack + 1] = i
        end
    end
    while #stack > 0 do
        local i = table.remove(stack)
        local r = math.floor((i - 1) / n) + 1
        local c = i - (r - 1) * n
        if (player == BLACK and r == n) or (player == WHITE and c == n) then
            -- Walk back to the start edge: that path is the winning chain.
            local chain = {}
            while i do
                chain[#chain + 1] = i
                i = parent[i]
            end
            return chain
        end
        for _, j in ipairs(nbr[i]) do
            if not seen[j] and cells[j] == player then
                seen[j] = true
                parent[j] = i
                stack[#stack + 1] = j
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- HexBoard
-- ---------------------------------------------------------------------------

local HexBoard = {}
HexBoard.__index = HexBoard

HexBoard.EMPTY     = EMPTY
HexBoard.BLACK     = BLACK
HexBoard.WHITE     = WHITE
HexBoard.SIZES     = SIZES
HexBoard.DEFAULT_N = DEFAULT_N
HexBoard.neighbourTable   = neighbourTable
HexBoard.findWinningChain = findWinningChain

-- opts: { n = 7|9|11, swap_rule = bool }
function HexBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({}, self)
    obj:reset(opts.n, opts.swap_rule)
    return obj
end

function HexBoard:reset(n, swap_rule)
    n = n or self.n or DEFAULT_N
    if not validSize(n) then n = DEFAULT_N end
    if swap_rule == nil then swap_rule = self.swap_rule end
    self.n         = n
    self.swap_rule = swap_rule and true or false
    self.cells     = {}
    for i = 1, n * n do self.cells[i] = EMPTY end
    self.turn      = BLACK
    self.status    = "playing"   -- "playing" | "won"
    self.winner    = nil
    self.chain     = nil         -- winning chain (cell indices), for display
    self.chain_set = nil
    self.history   = {}          -- { kind = "play"|"swap", cell, from }
end

function HexBoard:index(r, c)
    return (r - 1) * self.n + c
end

function HexBoard:rc(i)
    local r = math.floor((i - 1) / self.n) + 1
    return r, i - (r - 1) * self.n
end

function HexBoard:get(r, c)
    return self.cells[(r - 1) * self.n + c]
end

function HexBoard:neighbours(i)
    return neighbourTable(self.n)[i]
end

function HexBoard:lastCell()
    local h = self.history[#self.history]
    return h and h.cell or nil
end

function HexBoard:moveCount()
    return #self.history
end

-- White's first turn, right after Black's opening stone, with the rule on.
function HexBoard:canSwap()
    return self.swap_rule and self.status == "playing" and self.turn == WHITE
        and #self.history == 1 and self.history[1].kind == "play"
end

function HexBoard:_finishMove()
    local mover = self.turn
    local chain = findWinningChain(self.cells, self.n, mover)
    if chain then
        self.status = "won"
        self.winner = mover
        self.chain  = chain
        self.chain_set = {}
        for _, j in ipairs(chain) do self.chain_set[j] = true end
        return "won"
    end
    self.turn = 3 - mover
    return "ok"
end

-- Returns "ok", "won", "occupied", "invalid" or "over".
function HexBoard:play(r, c)
    if self.status ~= "playing" then return "over" end
    local n = self.n
    if r < 1 or r > n or c < 1 or c > n then return "invalid" end
    local i = (r - 1) * n + c
    if self.cells[i] ~= EMPTY then return "occupied" end
    self.cells[i] = self.turn
    self.history[#self.history + 1] = { kind = "play", cell = i }
    return self:_finishMove()
end

function HexBoard:playIndex(i)
    local r, c = self:rc(i)
    return self:play(r, c)
end

-- Returns "ok" or "not_allowed".
function HexBoard:swap()
    if not self:canSwap() then return "not_allowed" end
    local from = self.history[1].cell
    local r, c = self:rc(from)
    local to = self:index(c, r)
    self.cells[from] = EMPTY
    self.cells[to]   = WHITE
    self.history[#self.history + 1] = { kind = "swap", cell = to, from = from }
    -- A single stone never wins, so this is always "ok".
    return self:_finishMove()
end

-- Takes back one ply (a stone or a swap). Returns true if something was undone.
function HexBoard:undo()
    local h = self.history[#self.history]
    if not h then return false end
    self.history[#self.history] = nil
    if h.kind == "swap" then
        self.cells[h.cell] = EMPTY
        self.cells[h.from] = BLACK
        self.turn = WHITE
    else
        self.turn = self.cells[h.cell]
        self.cells[h.cell] = EMPTY
    end
    self.status, self.winner, self.chain, self.chain_set = "playing", nil, nil, nil
    return true
end

function HexBoard:emptyCells()
    local list = {}
    for i = 1, self.n * self.n do
        if self.cells[i] == EMPTY then list[#list + 1] = i end
    end
    return list
end

function HexBoard:isChainCell(i)
    return self.chain_set ~= nil and self.chain_set[i] == true
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function HexBoard:serialize()
    local hist = {}
    for k, h in ipairs(self.history) do
        hist[k] = { kind = h.kind, cell = h.cell, from = h.from }
    end
    return {
        n         = self.n,
        swap_rule = self.swap_rule,
        history   = hist,
    }
end

-- The position is replayed from the move list rather than trusted from a
-- stored grid: a save can then never hold a position the rules don't reach.
function HexBoard:load(data)
    if type(data) ~= "table" or not validSize(data.n) or type(data.history) ~= "table" then
        return false
    end
    local b = HexBoard:new{ n = data.n, swap_rule = data.swap_rule }
    for _, h in ipairs(data.history) do
        local res
        if h.kind == "swap" then
            res = b:swap()
        elseif type(h.cell) == "number" then
            res = b:playIndex(h.cell)
        end
        if res ~= "ok" and res ~= "won" then return false end
    end
    for k, v in pairs(b) do self[k] = v end
    return true
end

return HexBoard
