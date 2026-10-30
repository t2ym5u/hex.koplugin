local Blitbuffer     = require("ffi/blitbuffer")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager      = require("ui/uimanager")

local C_BG        = Blitbuffer.COLOR_WHITE
local C_LINE      = Blitbuffer.COLOR_BLACK
local C_BLACK     = Blitbuffer.COLOR_BLACK
local C_WHITE     = Blitbuffer.COLOR_WHITE
local C_CHAIN     = Blitbuffer.COLOR_GRAY_B   -- cells of the winning chain

local SQRT3 = math.sqrt(3)

-- ---------------------------------------------------------------------------
-- HexBoardWidget — draws the n×n rhombus of pointy-top hexagons
--
-- Each row is shifted half a cell to the right of the one above, so the board
-- leans right and the left/right sides slope at 60°. Black's goal edges (top
-- and bottom) carry a solid black band; White's (left and right) a hollow
-- band -- a black outline round a white strip -- the same contrast as the
-- stones themselves: Black's are filled discs, White's are white discs with a
-- thick black ring.
--
-- Hexagons are not cells of a square grid, so this widget is an
-- InputContainer of its own (like go's) rather than a GridWidgetBase. Shapes
-- are filled with a scanline polygon filler on top of paintRect.
-- ---------------------------------------------------------------------------

local HexBoardWidget = InputContainer:extend{
    board        = nil,
    onCellAction = nil,  -- callback(r, c)
    max_width    = 300,
    max_height   = 300,
}

-- Even-odd scanline fill; pts = { x1, y1, x2, y2, ... } (may be concave).
local function fillPolygon(bb, pts, color)
    local npts = #pts / 2
    local ymin, ymax = math.huge, -math.huge
    for k = 2, #pts, 2 do
        if pts[k] < ymin then ymin = pts[k] end
        if pts[k] > ymax then ymax = pts[k] end
    end
    local xs = {}
    for y = math.floor(ymin), math.ceil(ymax) - 1 do
        local sy = y + 0.5
        local cnt = 0
        for k = 1, npts do
            local x1, y1 = pts[2 * k - 1], pts[2 * k]
            local j = (k % npts) + 1
            local x2, y2 = pts[2 * j - 1], pts[2 * j]
            if (y1 <= sy and y2 > sy) or (y2 <= sy and y1 > sy) then
                cnt = cnt + 1
                xs[cnt] = x1 + (sy - y1) * (x2 - x1) / (y2 - y1)
            end
        end
        if cnt >= 2 then
            for k = cnt + 1, #xs do xs[k] = nil end
            table.sort(xs)
            for k = 1, cnt - 1, 2 do
                local xa = math.floor(xs[k] + 0.5)
                local xb = math.floor(xs[k + 1] + 0.5)
                if xb > xa then bb:paintRect(xa, y, xb - xa, 1, color) end
            end
        end
    end
end

local function hexPoints(cx, cy, s)
    local hw = s * SQRT3 / 2
    return { cx, cy - s, cx + hw, cy - s / 2, cx + hw, cy + s / 2,
             cx, cy + s, cx - hw, cy + s / 2, cx - hw, cy - s / 2 }
end

function HexBoardWidget:init()
    local n = self.board.n
    self.n = n
    -- Width:  hexes span (1.5n - 0.5) hex widths, plus a side band each way.
    -- Height: (1.5n + 0.5) radii, plus a top and a bottom band.
    -- Bands are BAND × radius thick; solve for the largest radius that fits.
    local BAND = 0.55
    -- The side bands overhang the end rows by a further 1/sqrt(3) radius.
    local s_w = self.max_width  / (SQRT3 * (1.5 * n - 0.5) + 2 * BAND / 0.866 + 2 / SQRT3 + 0.2)
    local s_h = self.max_height / (1.5 * n + 0.5 + 2 * BAND + 0.2)
    local s = math.max(4, math.floor(math.min(s_w, s_h)))
    self.s    = s                         -- hexagon circumradius
    self.hw   = s * SQRT3 / 2             -- half a hexagon's width
    self.band = math.floor(s * BAND)
    self.band_h = self.band / 0.866       -- the side bands' horizontal thickness

    local over = s / SQRT3
    local w = math.floor(SQRT3 * s * (1.5 * n - 0.5) + 2 * (self.band_h + over) + 2)
    local h = math.floor(s * (1.5 * n + 0.5) + 2 * self.band + 2)
    self.ox = self.band_h + over + 1      -- left of hexagon (1, 1)
    self.oy = self.band + 1               -- top of hexagon (1, 1)
    self.dimen = Geom:new{ w = w, h = h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = w, h = h }

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            },
        },
    }
end

function HexBoardWidget:getSize()
    return self.dimen
end

-- Centre of cell (r, c) in widget-local pixels.
function HexBoardWidget:_center(r, c)
    local hw, s = self.hw, self.s
    return self.ox + hw + (c - 1) * 2 * hw + (r - 1) * hw,
           self.oy + s + (r - 1) * 1.5 * s
end

-- Nearest cell centre, if the tap is inside (roughly) that hexagon.
function HexBoardWidget:cellAt(lx, ly)
    local best, br, bc = math.huge, nil, nil
    for r = 1, self.n do
        for c = 1, self.n do
            local cx, cy = self:_center(r, c)
            local d = (lx - cx) ^ 2 + (ly - cy) ^ 2
            if d < best then best, br, bc = d, r, c end
        end
    end
    if best > (self.s * 1.05) ^ 2 then return nil end
    return br, bc
end

function HexBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local r, c = self:cellAt(ges.pos.x - self.paint_rect.x, ges.pos.y - self.paint_rect.y)
    if r and self.onCellAction then self.onCellAction(r, c) end
    return true
end

function HexBoardWidget:refresh()
    UIManager:setDirty(self, function()
        local rect = self.paint_rect
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function HexBoardWidget:_paintBands(bb, x, y)
    local n, s, hw = self.n, self.s, self.hw
    local band, bh = self.band, self.band_h
    local t = math.max(2, math.floor(band * 0.35))   -- outline of the hollow bands

    -- Top and bottom: Black's edges, solid.
    local top, bottom = {}, {}
    for c = 1, n do
        local cx, cy = self:_center(1, c)
        top[#top + 1] = x + cx - hw; top[#top + 1] = y + cy - s / 2
        top[#top + 1] = x + cx;      top[#top + 1] = y + cy - s
    end
    do
        local cx, cy = self:_center(1, n)
        top[#top + 1] = x + cx + hw; top[#top + 1] = y + cy - s / 2
        top[#top + 1] = x + cx + hw; top[#top + 1] = y + cy - s - band
        local fx, fy = self:_center(1, 1)
        top[#top + 1] = x + fx - hw; top[#top + 1] = y + fy - s - band
    end
    fillPolygon(bb, top, C_BLACK)
    for c = n, 1, -1 do
        local cx, cy = self:_center(n, c)
        bottom[#bottom + 1] = x + cx + hw; bottom[#bottom + 1] = y + cy + s / 2
        bottom[#bottom + 1] = x + cx;      bottom[#bottom + 1] = y + cy + s
    end
    do
        local cx, cy = self:_center(n, 1)
        bottom[#bottom + 1] = x + cx - hw; bottom[#bottom + 1] = y + cy + s / 2
        bottom[#bottom + 1] = x + cx - hw; bottom[#bottom + 1] = y + cy + s + band
        local lx, ly = self:_center(n, n)
        bottom[#bottom + 1] = x + lx + hw; bottom[#bottom + 1] = y + ly + s + band
    end
    fillPolygon(bb, bottom, C_BLACK)

    -- Left and right: White's edges, hollow. Each side follows the zig-zag
    -- of its column; the outer line is parallel to the 60° slope.
    local slope = hw / (1.5 * s)            -- dx per dy along a side
    local function side(col, dir)
        local pts = {}
        for r = 1, n do
            local cx, cy = self:_center(r, col)
            pts[#pts + 1] = x + cx + dir * hw; pts[#pts + 1] = y + cy - s / 2
            pts[#pts + 1] = x + cx + dir * hw; pts[#pts + 1] = y + cy + s / 2
        end
        -- The outermost vertices: lower ones on the left, upper ones on the right.
        local ax, ay = self:_center(1, col)
        local refy = ay + (dir < 0 and s / 2 or -s / 2)
        local refx = ax + dir * hw
        local function lineX(yy, off) return refx + (yy - refy) * slope + dir * off end
        local y0 = ay - s / 2
        local _, ny = self:_center(n, col)
        local y1 = ny + s / 2
        pts[#pts + 1] = x + lineX(y1, bh); pts[#pts + 1] = y + y1
        pts[#pts + 1] = x + lineX(y0, bh); pts[#pts + 1] = y + y0
        fillPolygon(bb, pts, C_BLACK)
        -- Hollow it out: everything but a `t`-thick outer line goes white,
        -- down to the hexagons, whose own outlines close the band inside.
        local ti = t / 0.866
        local nz = #pts - 4
        local inner = {}
        for k = 1, nz do inner[k] = pts[k] end
        inner[nz + 1] = x + lineX(y1 - t, bh - ti); inner[nz + 2] = y + y1 - t
        inner[nz + 3] = x + lineX(y0 + t, bh - ti); inner[nz + 4] = y + y0 + t
        fillPolygon(bb, inner, C_WHITE)
    end
    side(1, -1)
    side(n, 1)
end

function HexBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)
    self:_paintBands(bb, x, y)

    local board, n, s = self.board, self.n, self.s
    local lw = math.max(1, math.floor(s * 0.06))     -- grid line, per side
    local inner = s - lw / 0.866
    local stone_r = math.floor(self.hw * 0.78)
    local ring = math.max(2, math.floor(stone_r * 0.22))
    local last = board:lastCell()

    for r = 1, n do
        for c = 1, n do
            local cx, cy = self:_center(r, c)
            cx, cy = x + cx, y + cy
            local i = (r - 1) * n + c
            fillPolygon(bb, hexPoints(cx, cy, s), C_LINE)
            fillPolygon(bb, hexPoints(cx, cy, inner), board:isChainCell(i) and C_CHAIN or C_BG)
            local v = board.cells[i]
            local px, py = math.floor(cx + 0.5), math.floor(cy + 0.5)
            if v == 1 then
                bb:paintCircle(px, py, stone_r, C_BLACK)
            elseif v == 2 then
                bb:paintCircle(px, py, stone_r, C_WHITE)
                bb:paintCircle(px, py, stone_r, C_BLACK, ring)
            end
            if i == last and v ~= 0 then
                -- Last move: a dot in the opposite colour.
                bb:paintCircle(px, py, math.max(2, math.floor(stone_r * 0.25)),
                    v == 1 and C_WHITE or C_BLACK)
            end
        end
    end
end

return HexBoardWidget
