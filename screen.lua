-- ---------------------------------------------------------------------------
-- HexScreen — full-screen UI for Hex, 7×7 / 9×9 / 11×11
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")

local HexBoard       = lrequire("board")
local HexAI          = lrequire("ai")
local HexBoardWidget = lrequire("board_widget")

local GAME_RULES_EN = _([[
Hex — Rules

Two players take turns placing one stone on any empty cell of the rhombus.

• Black moves first and tries to join the top and bottom edges (the solid black bands).
• White tries to join the left and right edges (the hollow bands).
• Each cell touches six others. A chain of your stones touching each other from one of your edges to the other wins.
• There is no draw: once the board is full, exactly one player is connected.

Swap rule (optional):
Moving first is a big advantage. With the swap rule on, White's first turn may be "Swap" instead of a stone: Black's opening stone becomes a White stone (mirrored across the long diagonal) and Black moves again. So Black should open with a move that is neither too strong nor too weak.

Tip: two stones with two empty cells between them (a "bridge") cannot be cut — if the opponent takes one cell, take the other.
]])

local GAME_RULES_FR = [[
Hex — Règles

Les deux joueurs posent à tour de rôle une pierre sur une case vide du losange.

• Les Noirs commencent et cherchent à relier le bord du haut et le bord du bas (les bandes noires pleines).
• Les Blancs cherchent à relier les bords gauche et droit (les bandes creuses).
• Chaque case touche six voisines. Une chaîne de pierres qui se touchent, d'un de vos bords à l'autre, gagne.
• Pas de match nul : une fois le plateau rempli, un seul joueur est relié.

Règle du gâteau (optionnelle) :
Jouer en premier est un gros avantage. Avec cette règle, au premier tour des Blancs, ils peuvent « Échanger » au lieu de poser une pierre : la pierre d'ouverture noire devient une pierre blanche (symétrique par rapport à la grande diagonale) et les Noirs rejouent. Les Noirs ont donc intérêt à ouvrir par un coup ni trop fort ni trop faible.

Astuce : deux pierres séparées par deux cases vides communes (un « pont ») ne peuvent pas être coupées — si l'adversaire prend l'une des cases, prenez l'autre.
]]

local HexScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function HexScreen:init()
    local state = self.plugin:loadState()
    self.board  = HexBoard:new()
    if not self.board:load(state) then
        self.board:reset(self.plugin:getSetting("size", HexBoard.DEFAULT_N),
                         self.plugin:getSetting("swap_rule", false))
    end
    ScreenBase.init(self)
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

function HexScreen:isRoundOver()
    return self.board.status ~= "playing"
end

function HexScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function HexScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Hex"), function()
        local items = {
            { text = _("New game"),                callback = function() self:onNewGame() end },
            { text = T(_("Size: %1"), self:_sizeLabel(self.plugin:getSetting("size", HexBoard.DEFAULT_N))),
              callback = function() self:openSizeMenu() end },
            { text = self:_diffLabel(),            callback = function() self:openDifficultyMenu() end },
            { text = self:_playersLabel(),         callback = function() self:openPlayersMenu() end },
        }
        if self.plugin:getSetting("players", 1) == 1 then
            items[#items + 1] = { text = self:_playAsLabel(), callback = function() self:openPlayAsMenu() end }
        end
        items[#items + 1] = {
            text = self.plugin:getSetting("swap_rule", false) and _("Swap rule: on") or _("Swap rule: off"),
            callback = function() self:toggleSwapRule() end,
        }
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
        return items
    end)

    local actions = {}
    if self.board.swap_rule then
        actions[#actions + 1] = { text = _("Swap"), callback = function() self:onSwap() end }
    end
    actions[#actions + 1] = { text = _("Undo"), callback = function() self:onUndo() end }

    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(actions),
    }

    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = HexBoardWidget:new{
        board        = self.board,
        max_width    = budget_w,
        max_height   = budget_h,
        onCellAction = function(r, c) self:onCellAction(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding    = 0,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Turn helpers
-- ---------------------------------------------------------------------------

function HexScreen:_isAITurn()
    if self.board.status ~= "playing" then return false end
    if self.plugin:getSetting("players", 1) ~= 1 then return false end
    return self.board.turn ~= self.plugin:getSetting("player_color", HexBoard.BLACK)
end

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

function HexScreen:_afterMove(result)
    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
    self:updateStatus()
    if result == "won" then
        self:showMessage(self:_winText(), 3)
    elseif self:_isAITurn() then
        self:triggerAI()
    end
end

function HexScreen:onCellAction(r, c)
    if self.board.status ~= "playing" or self:_isAITurn() or self.ai_pending then return end
    local result = self.board:play(r, c)
    if result == "occupied" or result == "invalid" or result == "over" then return end
    self:_afterMove(result)
end

function HexScreen:onSwap()
    if self.board.status ~= "playing" or self:_isAITurn() or self.ai_pending then return end
    if not self.board:canSwap() then
        self:updateStatus(_("Swapping is only allowed as White's first move."))
        return
    end
    self:_afterMove(self.board:swap())
end

-- Against the AI, one tap takes back the AI's reply and your move with it.
function HexScreen:onUndo()
    if self.board.status ~= "playing" or self.ai_pending then return end
    if not self.board:undo() then return end
    if self.plugin:getSetting("players", 1) == 1 then
        while self:_isAITurn() and self.board:undo() do end
    end
    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
    self:updateStatus()
    -- Undoing the AI's opening leaves it to move again.
    if self:_isAITurn() then self:triggerAI() end
end

-- ---------------------------------------------------------------------------
-- AI
-- ---------------------------------------------------------------------------

function HexScreen:triggerAI()
    if not self:_isAITurn() or self.ai_pending then return end
    self.ai_pending = true
    self:updateStatus(_("AI is thinking..."))
    local board = self.board
    UIManager:scheduleIn(0.05, function()
        self.ai_pending = false
        -- A new game may have replaced the board meanwhile.
        if board ~= self.board or not self:_isAITurn() then return end
        local diff = self.plugin:getSetting("difficulty", "medium")
        local move = HexAI.chooseMove(board, diff)
        local result
        if move.swap then
            result = board:swap()
        else
            result = board:playIndex(move.cell)
        end
        self:_afterMove(result)
        if move.swap then
            self:updateStatus(_("The AI swapped your opening stone. Your move."))
        end
    end)
end

-- ---------------------------------------------------------------------------
-- New game / settings
-- ---------------------------------------------------------------------------

function HexScreen:onNewGame()
    self.ai_pending = false
    self.board = HexBoard:new{
        n         = self.plugin:getSetting("size", HexBoard.DEFAULT_N),
        swap_rule = self.plugin:getSetting("swap_rule", false),
    }
    self.plugin:saveState(self:serializeState())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

function HexScreen:toggleSwapRule()
    self.plugin:saveSetting("swap_rule", not self.plugin:getSetting("swap_rule", false))
    self:onNewGame()
end

function HexScreen:openSizeMenu()
    local items = {}
    for _, n in ipairs(HexBoard.SIZES) do
        items[#items + 1] = { id = n, text = self:_sizeLabel(n) }
    end
    MenuHelper.openPickerMenu{
        title      = _("Size"),
        items      = items,
        current_id = self.plugin:getSetting("size", HexBoard.DEFAULT_N),
        on_select  = function(id)
            self.plugin:saveSetting("size", id)
            self:onNewGame()
        end,
        parent = self,
    }
end

function HexScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            self:updateStatus()
        end,
        parent = self,
    }
end

function HexScreen:openPlayersMenu()
    MenuHelper.openPickerMenu{
        title      = _("Players"),
        items      = {
            { id = 1, text = _("1 player (vs AI)") },
            { id = 2, text = _("2 players") },
        },
        current_id = self.plugin:getSetting("players", 1),
        on_select  = function(id)
            self.plugin:saveSetting("players", id)
            self:onNewGame()
        end,
        parent = self,
    }
end

function HexScreen:openPlayAsMenu()
    MenuHelper.openPickerMenu{
        title      = _("Play as"),
        items      = {
            { id = HexBoard.BLACK, text = _("Black") },
            { id = HexBoard.WHITE, text = _("White") },
        },
        current_id = self.plugin:getSetting("player_color", HexBoard.BLACK),
        on_select  = function(id)
            self.plugin:saveSetting("player_color", id)
            self:onNewGame()
        end,
        parent = self,
    }
end

-- ---------------------------------------------------------------------------
-- Status / labels
-- ---------------------------------------------------------------------------

function HexScreen:_colorName(p)
    return p == HexBoard.BLACK and _("Black") or _("White")
end

function HexScreen:_winText()
    return self.board.winner == HexBoard.BLACK and _("Black wins!") or _("White wins!")
end

function HexScreen:_sizeLabel(n)
    return T("%1×%1", n)
end

function HexScreen:_diffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    return T(_("Difficulty: %1"), MenuHelper.DIFFICULTY_LABELS[diff] or diff)
end

function HexScreen:_playersLabel()
    return T(_("Players: %1"), self.plugin:getSetting("players", 1))
end

function HexScreen:_playAsLabel()
    return T(_("Play as: %1"), self:_colorName(self.plugin:getSetting("player_color", HexBoard.BLACK)))
end

function HexScreen:updateStatus(msg)
    local status
    local board = self.board
    if msg then
        status = msg
    elseif board.status == "won" then
        status = self:_winText()
    else
        local dlabel
        if self.plugin:getSetting("players", 1) == 1 then
            local diff = self.plugin:getSetting("difficulty", "medium")
            dlabel = MenuHelper.DIFFICULTY_LABELS[diff] or diff
        end
        status = self:joinStatus(
            self:_sizeLabel(board.n),
            dlabel,
            T(_("%1 to move"), self:_colorName(board.turn)),
            board:canSwap() and not self:_isAITurn() and _("Swap allowed") or nil)
    end
    ScreenBase.updateStatus(self, status)
    self:refreshActionBar()
end

return HexScreen
