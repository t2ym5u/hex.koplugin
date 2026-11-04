-- ---------------------------------------------------------------------------
-- HexAI — computer opponent for Hex
--
-- Monte Carlo tree search with RAVE (all-moves-as-first) statistics. Hex
-- suits playouts unusually well: a full board always has exactly one winner,
-- so a playout is just "fill the empty cells at random, alternating colours,
-- then see who connects" -- no rules to apply on the way, no draws.
--
-- Two things carry most of the strength:
--   * RAVE: every cell a player ends up owning in a playout counts as a
--     sample for "playing there first". On a 121-cell board that turns each
--     playout into ~60 samples instead of 1, which is what lets a few
--     thousand playouts say anything at all.
--   * Bridge-saving playouts: when the opponent plays into one of the two
--     cells of a bridge (two stones sharing two empty neighbours), the
--     playout answers in the other cell. Uniform random playouts let bridges
--     be cut half the time, so they undervalue the most important shape in
--     the game.
--
-- An alpha-beta search on a two-distance evaluation (the Queenbee approach)
-- was built and measured first: depth 2, the 8 best candidates by a one-ply
-- evaluation, it lost 0-10 to 3 000-playout MCTS at equal think time on 9×9,
-- and 0-6 on 11×11 with 40 candidates and more time than MCTS. It was
-- dropped rather than kept as dead code.
--
-- Everything works on a flat cells array (see board.lua); nothing here
-- depends on KOReader.
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Board = (package.loaded[_dir .. "board"]) or dofile(_dir .. "board.lua")

local EMPTY, BLACK, WHITE = 0, 1, 2
local INF = math.huge

local random = math.random
local sqrt, log = math.sqrt, math.log
local clock = os.clock

local HexAI = {}

-- Per-difficulty settings.
--   playouts   MCTS iteration budget
--   max_time   CPU-time cap in seconds (os.clock). On a fast machine the
--              playout budget stops the search; on an e-reader (a Kobo runs
--              this ~25x slower than a desktop) the cap does: Hard on 11x11
--              reaches ~5 000 of its 20 000 playouts in 2.3 s there (plus
--              the one-move win/block scan: ~2.5 s a move). It used to be
--              8 s, i.e. an 8-second wait for every move.
--   reuse      keep the search tree between moves: the subtree under the
--              move actually played (ours, then the opponent's reply) still
--              holds its playouts, so the next search starts with them
--              instead of from nothing. Hard only -- the cut from 8 s to
--              2.5 s on a Kobo is what it makes up for.
HexAI.LEVELS = {
    easy   = { playouts = 300,   max_time = 1.0, bridges = false },
    medium = { playouts = 3000,  max_time = 2.0, bridges = true },
    hard   = { playouts = 20000, max_time = 2.3, bridges = true, reuse = true },
}

-- Multiplies every max_time; test harnesses set it to ~0.04 to reproduce on
-- a desktop the playout counts a Kobo reaches in the same budget.
HexAI.time_scale = 1

-- ---------------------------------------------------------------------------
-- Static tables per board size
-- ---------------------------------------------------------------------------

local DELTAS = { { -1, 0 }, { -1, 1 }, { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 0 } }

-- Edge markers used in bridge tables in place of a cell index: a cell just
-- off the top/bottom rows belongs to Black's edge, off the side columns to
-- White's. They are two virtual cells past the board, n*n + BLACK and
-- n*n + WHITE, that the playout array permanently holds as a Black and a
-- White stone: the bridge test then reads cells[p] the same way for a real
-- cell and an edge, with no branch (branchy inner loops made LuaJIT fall
-- back to the interpreter, which cost ~40% of the playout time).
local function offBoardMarker(r, c, n)
    local off_r = r < 1 or r > n
    local off_c = c < 1 or c > n
    if off_r and off_c then return nil end
    if off_r then return n * n + BLACK end
    if off_c then return n * n + WHITE end
    return (r - 1) * n + c
end

local tables_cache = {}
local function getTables(n)
    local t = tables_cache[n]
    if t then return t end
    local nbr = Board.neighbourTable(n)
    -- saves[x] = flat list of triples (y, p, q): x and y are adjacent and p, q
    -- are their two common neighbours (or an edge). If p and q belong to the
    -- player to move and the opponent just took x, taking y keeps p and q
    -- connected: that is a bridge (or an edge template) being saved.
    local saves = {}
    for r = 1, n do
        for c = 1, n do
            local list = {}
            for _, d in ipairs(DELTAS) do
                local yr, yc = r + d[1], c + d[2]
                if yr >= 1 and yr <= n and yc >= 1 and yc <= n then
                    -- Common neighbours of two adjacent cells, by coordinates.
                    local commons = {}
                    for _, e in ipairs(DELTAS) do
                        local zr, zc = r + e[1], c + e[2]
                        for _, f in ipairs(DELTAS) do
                            if zr == yr + f[1] and zc == yc + f[2] then
                                commons[#commons + 1] = { zr, zc }
                            end
                        end
                    end
                    if #commons == 2 then
                        local p = offBoardMarker(commons[1][1], commons[1][2], n)
                        local q = offBoardMarker(commons[2][1], commons[2][2], n)
                        if p and q then
                            list[#list + 1] = (yr - 1) * n + yc
                            list[#list + 1] = p
                            list[#list + 1] = q
                        end
                    end
                end
            end
            saves[(r - 1) * n + c] = list
        end
    end
    t = { nbr = nbr, saves = saves, stamp = {}, stamp_n = 0, stack = {} }
    for i = 1, n * n do t.stamp[i] = 0 end
    tables_cache[n] = t
    return t
end

-- Does Black join row 1 to row n? On a full board "not Black" means White.
local function blackConnects(cells, n, t)
    local stamp, stack, nbr = t.stamp, t.stack, t.nbr
    t.stamp_n = t.stamp_n + 1
    local s = t.stamp_n
    local top = 0
    for i = 1, n do
        if cells[i] == BLACK then
            top = top + 1
            stack[top] = i
            stamp[i] = s
        end
    end
    local last_row = (n - 1) * n
    while top > 0 do
        local i = stack[top]
        top = top - 1
        if i > last_row then return true end
        local nb = nbr[i]
        for k = 1, #nb do
            local j = nb[k]
            if cells[j] == BLACK and stamp[j] ~= s then
                stamp[j] = s
                top = top + 1
                stack[top] = j
            end
        end
    end
    return false
end

local function connects(cells, n, t, player)
    if player == BLACK then return blackConnects(cells, n, t) end
    -- White: transpose the question rather than duplicate the search.
    local tr = {}
    for r = 1, n do
        for c = 1, n do
            local v = cells[(c - 1) * n + r]
            tr[(r - 1) * n + c] = (v == WHITE) and BLACK or EMPTY
        end
    end
    return blackConnects(tr, n, t)
end
HexAI.connects = function(cells, n, player) return connects(cells, n, getTables(n), player) end

-- ---------------------------------------------------------------------------
-- Immediate tactics: a winning cell, or the only cell that stops a loss.
-- MCTS finds these too, but not always with a small budget, and missing a
-- one-move win is the kind of blunder a player never forgives.
-- ---------------------------------------------------------------------------

local function winningCells(cells, n, t, player)
    local wins = {}
    for i = 1, n * n do
        if cells[i] == EMPTY then
            cells[i] = player
            if connects(cells, n, t, player) then wins[#wins + 1] = i end
            cells[i] = EMPTY
        end
    end
    return wins
end
HexAI.winningCells = function(cells, n, player) return winningCells(cells, n, getTables(n), player) end

-- ---------------------------------------------------------------------------
-- Playout: fill every empty cell, alternating colours from `to_move`.
-- empt[1..m] holds the empty cells and pos[cell] its slot; both are scratch
-- arrays the caller fills. Returns the winner.
-- ---------------------------------------------------------------------------

local function playout(cells, n, t, empt, pos, m, to_move, bridges)
    local saves = t.saves
    local last = 0
    for k = 1, m do
        local j
        if bridges and last > 0 then
            local s = saves[last]
            local cnt = 0
            for x = 1, #s, 3 do
                local y = s[x]
                if cells[y] == EMPTY and cells[s[x + 1]] == to_move
                   and cells[s[x + 2]] == to_move then
                        cnt = cnt + 1
                        if cnt == 1 or random(cnt) == 1 then j = pos[y] end
                end
            end
        end
        if not j then j = random(k, m) end
        local cell, other = empt[j], empt[k]
        empt[k], pos[cell] = cell, k
        empt[j], pos[other] = other, j
        cells[cell] = to_move
        last = cell
        to_move = 3 - to_move
    end
    return blackConnects(cells, n, t) and BLACK or WHITE
end

-- ---------------------------------------------------------------------------
-- MCTS with RAVE
-- ---------------------------------------------------------------------------

local EXPAND_AT = 3     -- visits of a move before it gets its own node
local RAVE_K    = 600   -- visits at which RAVE and real stats weigh the same
local EXPLORE   = 0.05

local ok_tnew, tnew = pcall(require, "table.new")
if not ok_tnew then tnew = function() return {} end end

local function newNode(cells, nn, to_move)
    local m = 0
    for i = 1, nn do
        if cells[i] == EMPTY then m = m + 1 end
    end
    local moves = tnew(m, 0)
    local N, W, AN, AW = tnew(m, 0), tnew(m, 0), tnew(m, 0), tnew(m, 0)
    m = 0
    for i = 1, nn do
        if cells[i] == EMPTY then
            m = m + 1
            moves[m], N[m], W[m], AN[m], AW[m] = i, 0, 0, 0, 0
        end
    end
    return { moves = moves, N = N, W = W, AN = AN, AW = AW, kids = {},
             total = 0, to_move = to_move }
end

local function selectMove(node, rave_k, explore)
    local moves, N, W, AN, AW = node.moves, node.N, node.W, node.AN, node.AW
    local logt = log(node.total + 1)
    local best, best_v = 1, -INF
    for k = 1, #moves do
        local nk, an = N[k], AN[k]
        local q  = (W[k] + 0.5) / (nk + 1)
        local qa = (AW[k] + 0.5) / (an + 1)
        local beta = an / (an + nk + an * nk / rave_k + 1)
        local v = (1 - beta) * q + beta * qa + explore * sqrt(logt / (nk + 1))
        if v > best_v then best, best_v = k, v end
    end
    return best
end

-- The tree of the last search with reuse on, and the position at its root.
local last_tree = nil

-- The node of the last tree for the position cells0 (to_move to play), or
-- nil. Only stones added since are allowed: an undo, a swap or a new game
-- changes or empties a cell, and the old tree no longer applies.
local function reusableNode(cells0, nn, to_move)
    local lt = last_tree
    if not lt or lt.nn ~= nn then return nil end
    local added = {}
    for i = 1, nn do
        local was, now = lt.cells[i], cells0[i]
        if was ~= now then
            if was ~= EMPTY then return nil end
            added[i] = now
        end
    end
    -- Walk down one stone at a time, each one the move of the node's side
    -- to play; every step needs a subtree the last search already built.
    local node, left = lt.root, 0
    for _ in pairs(added) do left = left + 1 end
    while left > 0 do
        local nxt = nil
        for k = 1, #node.moves do
            local c = node.moves[k]
            if added[c] == node.to_move then
                nxt = node.kids[k]
                added[c], left = nil, left - 1
                break
            end
        end
        if not nxt then return nil end
        node = nxt
    end
    if node.to_move ~= to_move then return nil end
    return node
end

-- Returns the chosen cell and the number of playouts run.
function HexAI.mcts(cells0, n, to_move, opts)
    local t = getTables(n)
    local nn = n * n
    local budget   = opts.playouts or 2000
    local deadline = clock() + (opts.max_time or 5) * HexAI.time_scale
    local bridges  = opts.bridges ~= false
    local rave_k   = opts.rave_k or RAVE_K
    local explore  = opts.explore or EXPLORE

    local root = opts.reuse and reusableNode(cells0, nn, to_move) or nil
    root = root or newNode(cells0, nn, to_move)
    if opts.reuse then
        local snap = {}
        for i = 1, nn do snap[i] = cells0[i] end
        last_tree = { nn = nn, cells = snap, root = root }
    else
        last_tree = nil
    end
    if #root.moves == 0 then return nil, 0 end
    if #root.moves == 1 then return root.moves[1], 0 end

    -- cells[nn + BLACK] / cells[nn + WHITE]: the virtual edge stones the
    -- bridge tables point at (see offBoardMarker).
    local cells, empt, pos = {}, {}, {}
    cells[nn + BLACK], cells[nn + WHITE] = BLACK, WHITE
    local path_nodes, path_k = {}, {}
    local iter = 0
    while iter < budget do
        iter = iter + 1
        if iter % 128 == 0 and clock() > deadline then break end

        for i = 1, nn do cells[i] = cells0[i] end
        -- Descend.
        local node, depth = root, 0
        local mover = to_move
        while true do
            local k = selectMove(node, rave_k, explore)
            depth = depth + 1
            path_nodes[depth], path_k[depth] = node, k
            cells[node.moves[k]] = mover
            mover = 3 - mover
            local kid = node.kids[k]
            if not kid then
                if node.N[k] + 1 >= EXPAND_AT and #node.moves > 1 then
                    kid = newNode(cells, nn, mover)
                    node.kids[k] = kid
                end
                break
            end
            if #kid.moves == 0 then break end
            node = kid
        end
        -- Play out.
        local m = 0
        for i = 1, nn do
            if cells[i] == EMPTY then
                m = m + 1
                empt[m], pos[i] = i, m
            end
        end
        local winner = playout(cells, n, t, empt, pos, m, mover, bridges)
        -- Back up real and all-moves-as-first statistics.
        for d = 1, depth do
            local nd, k = path_nodes[d], path_k[d]
            local me = nd.to_move
            local win = (winner == me) and 1 or 0
            nd.total = nd.total + 1
            nd.N[k] = nd.N[k] + 1
            nd.W[k] = nd.W[k] + win
            local moves, AN, AW = nd.moves, nd.AN, nd.AW
            for j = 1, #moves do
                if cells[moves[j]] == me then
                    AN[j] = AN[j] + 1
                    AW[j] = AW[j] + win
                end
            end
        end
    end

    -- Most visited move; RAVE value breaks ties (it matters on tiny budgets).
    local best, bn, bq = nil, -1, -1
    for k = 1, #root.moves do
        local nk = root.N[k]
        local qa = (root.AW[k] + 0.5) / (root.AN[k] + 1)
        if nk > bn or (nk == bn and qa > bq) then
            best, bn, bq = root.moves[k], nk, qa
        end
    end
    return best, iter
end

-- ---------------------------------------------------------------------------
-- Swap decision and opening
-- ---------------------------------------------------------------------------

-- Whether White should swap Black's opening stone at (r, c). Openings in the
-- middle of the board win for the first player; ones on the outer ring are
-- close to balanced or losing, so those are left alone.
function HexAI.shouldSwap(n, r, c)
    return r > 1 and r < n and c > 1 and c < n
end

-- A first move for Black when the opponent may swap it: something on the
-- edge rows that is neither a giveaway nor worth stealing.
local function pieOpening(n)
    local r = (random(2) == 1) and 1 or n
    local c = random(2, n - 1)
    return (r - 1) * n + c
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

-- board: a HexBoard. level: "easy" | "medium" | "hard" or a settings table.
-- Returns { swap = true } or { cell = i }, plus the playout count (stats).
function HexAI.chooseMove(board, level)
    local cfg = type(level) == "table" and level or HexAI.LEVELS[level] or HexAI.LEVELS.medium
    local n, me = board.n, board.turn

    if board:canSwap() then
        local r, c = board:rc(board.history[1].cell)
        if HexAI.shouldSwap(n, r, c) then return { swap = true }, 0 end
    end
    if board.swap_rule and board:moveCount() == 0 then
        return { cell = pieOpening(n) }, 0
    end

    local cells = {}
    for i = 1, n * n do cells[i] = board.cells[i] end
    local t = getTables(n)
    local wins = winningCells(cells, n, t, me)
    if #wins > 0 then return { cell = wins[1] }, 0 end
    local threats = winningCells(cells, n, t, 3 - me)
    if #threats == 1 then return { cell = threats[1] }, 0 end

    local cell, iters = HexAI.mcts(cells, n, me, cfg)
    return { cell = cell }, iters
end

return HexAI
