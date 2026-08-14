local addonName, addonTable = ...
local LootRememberer = LibStub("AceAddon-3.0"):GetAddon("LootRememberer")

-- Local references for performance
local CreateFrame = CreateFrame
local GetItemInfo = GetItemInfo
local GetItemIcon = GetItemIcon
local UnitClass = UnitClass
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local UIParent = UIParent
local GameTooltip = GameTooltip
local IsShiftKeyDown = IsShiftKeyDown
local ChatFrameEditBox = ChatFrameEditBox

local ICONS = {
    ["Need"] = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    ["Greed"] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    ["Pass"] = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    ["Disenchant"] = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
}

local PRIO = { ["Need"] = 4, ["Greed"] = 3, ["Disenchant"] = 3, ["Pass"] = 1 }

local function SkinSimpleButton(btn, text)
    btn:SetNormalTexture("")
    btn:SetPushedTexture("")
    btn:SetHighlightTexture("")
    
    local fs = btn:GetFontString()
    if not fs then
        fs = btn:CreateFontString(nil, "OVERLAY")
        btn:SetFontString(fs)
    end
    fs:SetFont("Fonts\\ARIALN.TTF", 14, "OUTLINE")
    fs:SetTextColor(1, 0.82, 0)
    fs:SetPoint("CENTER", 0, 0)
    btn:SetText(text)
    
    btn:HookScript("OnEnter", function(self)
        fs:SetTextColor(1, 1, 1)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tooltipText)
            GameTooltip:Show()
        end
    end)
    btn:HookScript("OnLeave", function(self)
        fs:SetTextColor(1, 0.82, 0)
        GameTooltip:Hide()
    end)
end

local function GetLeaderRoll(itemRecord)
    if not itemRecord or not itemRecord.rolls or #itemRecord.rolls == 0 then
        return nil
    end

    local sorted = {}
    for _, r in ipairs(itemRecord.rolls) do
        table.insert(sorted, r)
    end

    table.sort(sorted, function(a, b)
        local aWin = (a.player == itemRecord.winner)
        local bWin = (b.player == itemRecord.winner)
        if aWin and not bWin then return true end
        if bWin and not aWin then return false end

        local aPrio = PRIO[a.type] or 0
        local bPrio = PRIO[b.type] or 0
        if aPrio ~= bPrio then return aPrio > bPrio end

        local valA, valB = a.value or 0, b.value or 0
        if valA ~= valB then return valA > valB end

        return a.player < b.player
    end)

    return sorted[1]
end

-- Helper to draw a precise pixel-perfect black border (identical to OutfitterSkin.lua)
local function CreatePixelBorder(frame, thickness, r, g, b, a)
    if frame.PixelBorder then return end
    local t = thickness or 1
    frame.PixelBorder = {}
    local function Line() 
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(r or 0, g or 0, b or 0, a or 1)
        return tex
    end
    frame.PixelBorder.T = Line(); frame.PixelBorder.T:SetPoint("TOPLEFT"); frame.PixelBorder.T:SetPoint("TOPRIGHT"); frame.PixelBorder.T:SetHeight(t)
    frame.PixelBorder.B = Line(); frame.PixelBorder.B:SetPoint("BOTTOMLEFT"); frame.PixelBorder.B:SetPoint("BOTTOMRIGHT"); frame.PixelBorder.B:SetHeight(t)
    frame.PixelBorder.L = Line(); frame.PixelBorder.L:SetPoint("TOPLEFT"); frame.PixelBorder.L:SetPoint("BOTTOMLEFT"); frame.PixelBorder.L:SetWidth(t)
    frame.PixelBorder.R = Line(); frame.PixelBorder.R:SetPoint("TOPRIGHT"); frame.PixelBorder.R:SetPoint("BOTTOMRIGHT"); frame.PixelBorder.R:SetWidth(t)
end

-- Define the Rolls Frame
local f = CreateFrame("Frame", "LootRemembererRollsFrame", UIParent)
f:Hide()
f:SetFrameStrata("BACKGROUND")
f:SetToplevel(true)
f:EnableMouse(true)
f:SetMovable(true)
f:SetResizable(true)
f:SetMinResize(260, 200)
f:SetMaxResize(500, 900)

-- Solid Tiled Background using WHITE8x8 colored dark charcoal with 0.75 alpha (identical to Ascension Outfitter background)
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetTexture("Interface\\Buttons\\WHITE8x8")
bg:SetVertexColor(0.07, 0.07, 0.07, 0.75) -- Exact skinned Outfitter transparency (0.75)

-- 1px Solid Black Outline
CreatePixelBorder(f, 1, 0, 0, 0, 1)

-- Dragging
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function(self)
    local settings = LootRememberer:GetSettings()
    if settings.rollsWindowLocked then return end
    self:StartMoving()
    self.isMoving = true
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.isMoving = nil
    local settings = LootRememberer:GetSettings()
    local scale = self:GetScale() or 1
    local left = self:GetLeft() / scale
    local top = self:GetTop() / scale
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    settings.rollsWindowX = left
    settings.rollsWindowTop = top
    settings.rollsWindowY = self:GetBottom() / scale
end)

-- Title Bar Icon (questcollect brown pouch icon with no gold frame border outline)
local titleIcon = f:CreateTexture(nil, "OVERLAY")
titleIcon:SetSize(18, 18)
titleIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
titleIcon:SetTexture("Interface\\AddOns\\LootRememberer\\Media\\questcollect.blp")

-- Title Text
local titleText = f:CreateFontString(nil, "OVERLAY")
titleText:SetFont("Fonts\\ARIALN.TTF", 16, "OUTLINE")
titleText:SetTextColor(1, 0.82, 0)
titleText:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
titleText:SetText("Loot Rolls")

-- Quest Log Filigree Title Underline
local underline = f:CreateTexture(nil, "ARTWORK")
underline:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleLine")
underline:SetHeight(4)
underline:Hide()

-- Header Background Texture for Classic Skin (DragonUI)
local headerBg = f:CreateTexture(nil, "BORDER")
headerBg:SetTexture("Interface\\AddOns\\LootRememberer\\Media\\QuestTracker.blp")
headerBg:SetTexCoord(0.0107421875, 0.5576171875, 0.482421875, 0.619140625)
headerBg:SetAlpha(0.9)
headerBg:Hide()
f.headerBg = headerBg

local function SkinClassicButton(btn, text)
    if not btn.classicBg then
        local bgTex = btn:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgTex:SetVertexColor(0.08, 0.08, 0.08, 0.9)
        btn.classicBg = bgTex
    end
    btn.classicBg:Show()
    
    if not btn.classicBorder then
        btn.classicBorder = {}
        local function Line()
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(0.5, 0.4, 0.15, 0.8) -- gold border matching Objectives style
            return tex
        end
        local t = 1
        btn.classicBorder.T = Line(); btn.classicBorder.T:SetPoint("TOPLEFT"); btn.classicBorder.T:SetPoint("TOPRIGHT"); btn.classicBorder.T:SetHeight(t)
        btn.classicBorder.B = Line(); btn.classicBorder.B:SetPoint("BOTTOMLEFT"); btn.classicBorder.B:SetPoint("BOTTOMRIGHT"); btn.classicBorder.B:SetHeight(t)
        btn.classicBorder.L = Line(); btn.classicBorder.L:SetPoint("TOPLEFT"); btn.classicBorder.L:SetPoint("BOTTOMLEFT"); btn.classicBorder.L:SetWidth(t)
        btn.classicBorder.R = Line(); btn.classicBorder.R:SetPoint("TOPRIGHT"); btn.classicBorder.R:SetPoint("BOTTOMRIGHT"); btn.classicBorder.R:SetWidth(t)
    else
        btn.classicBorder.T:Show()
        btn.classicBorder.B:Show()
        btn.classicBorder.L:Show()
        btn.classicBorder.R:Show()
    end
    
    if not btn.classicHighlight then
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\WHITE8x8")
        hl:SetVertexColor(1, 1, 1, 0.2)
        btn.classicHighlight = hl
    end
    btn.classicHighlight:Show()
    
    local fs = btn:GetFontString()
    if fs then
        fs:SetFont("Fonts\\FRIZQT__.TTF", 11)
        fs:SetTextColor(1, 0.82, 0)
        fs:SetPoint("CENTER", 0, 0)
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    end
    btn:SetText(text)
end

local function SkinClassicLockButton(btn)
    if not btn.classicBg then
        local bgTex = btn:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgTex:SetVertexColor(0.08, 0.08, 0.08, 0.9)
        btn.classicBg = bgTex
    end
    btn.classicBg:Show()
    
    if not btn.classicBorder then
        btn.classicBorder = {}
        local function Line()
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(0.5, 0.4, 0.15, 0.8) -- gold border matching Objectives style
            return tex
        end
        local t = 1
        btn.classicBorder.T = Line(); btn.classicBorder.T:SetPoint("TOPLEFT"); btn.classicBorder.T:SetPoint("TOPRIGHT"); btn.classicBorder.T:SetHeight(t)
        btn.classicBorder.B = Line(); btn.classicBorder.B:SetPoint("BOTTOMLEFT"); btn.classicBorder.B:SetPoint("BOTTOMRIGHT"); btn.classicBorder.B:SetHeight(t)
        btn.classicBorder.L = Line(); btn.classicBorder.L:SetPoint("TOPLEFT"); btn.classicBorder.L:SetPoint("BOTTOMLEFT"); btn.classicBorder.L:SetWidth(t)
        btn.classicBorder.R = Line(); btn.classicBorder.R:SetPoint("TOPRIGHT"); btn.classicBorder.R:SetPoint("BOTTOMRIGHT"); btn.classicBorder.R:SetWidth(t)
    else
        btn.classicBorder.T:Show()
        btn.classicBorder.B:Show()
        btn.classicBorder.L:Show()
        btn.classicBorder.R:Show()
    end
    
    if not btn.classicHighlight then
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\WHITE8x8")
        hl:SetVertexColor(1, 1, 1, 0.2)
        btn.classicHighlight = hl
    end
    btn.classicHighlight:Show()
end

local function UnskinClassicLockButton(btn)
    if btn.classicBg then btn.classicBg:Hide() end
    if btn.classicBorder then
        btn.classicBorder.T:Hide()
        btn.classicBorder.B:Hide()
        btn.classicBorder.L:Hide()
        btn.classicBorder.R:Hide()
    end
    if btn.classicHighlight then btn.classicHighlight:Hide() end
end

local function UnskinClassicButton(btn)
    if btn.classicBg then btn.classicBg:Hide() end
    if btn.classicBorder then
        btn.classicBorder.T:Hide()
        btn.classicBorder.B:Hide()
        btn.classicBorder.L:Hide()
        btn.classicBorder.R:Hide()
    end
    if btn.classicHighlight then btn.classicHighlight:Hide() end
    
    btn:SetNormalTexture("")
    btn:SetPushedTexture("")
    btn:SetHighlightTexture("")
    
    local fs = btn:GetFontString()
    if fs then
        fs:SetFont("Fonts\\ARIALN.TTF", 14, "OUTLINE")
        fs:SetTextColor(1, 0.82, 0)
        fs:SetPoint("CENTER", 0, 0)
        fs:SetShadowOffset(0, 0)
    end
end

-- Simple Scale and Close Buttons (identical to Main Window)
local closeBtn = CreateFrame("Button", nil, f)
f.closeBtn = closeBtn
closeBtn:SetSize(22, 22)
closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
SkinSimpleButton(closeBtn, "X")
closeBtn.tooltipText = "Minimize"
closeBtn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then return end
    local settings = LootRememberer:GetSettings()
    settings.rollsWindowCollapsed = not settings.rollsWindowCollapsed
    PlaySound(settings.rollsWindowCollapsed and "igMiniMapZoomOut" or "igMiniMapZoomIn")
    f:UpdateCollapseState()
    if f.UpdateList then
        f:UpdateList()
    end
    local UpdateLootRemembererAnchor = _G["UpdateLootRemembererAnchor"]
    if UpdateLootRemembererAnchor then
        UpdateLootRemembererAnchor()
    end
end)

local scaleUp = CreateFrame("Button", nil, f)
scaleUp:SetSize(22, 22)
scaleUp:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
SkinSimpleButton(scaleUp, "+")
scaleUp.tooltipText = "Increase Scale"
scaleUp:SetScript("OnClick", function()
    local settings = LootRememberer:GetSettings()
    local currentScale = f:GetScale() or 1.0
    local newScale = math.min(currentScale + 0.1, 2.0)
    f:SetScale(newScale)
    settings.rollsWindowScale = newScale
end)

local scaleDown = CreateFrame("Button", nil, f)
scaleDown:SetSize(22, 22)
scaleDown:SetPoint("RIGHT", scaleUp, "LEFT", -5, 0)
SkinSimpleButton(scaleDown, "-")
scaleDown.tooltipText = "Decrease Scale"
scaleDown:SetScript("OnClick", function()
    local settings = LootRememberer:GetSettings()
    local currentScale = f:GetScale() or 1.0
    local newScale = math.max(currentScale - 0.1, 0.5)
    f:SetScale(newScale)
    settings.rollsWindowScale = newScale
end)

-- History Button
local histBtn = CreateFrame("Button", nil, f)
histBtn:SetSize(22, 22)
histBtn:SetPoint("RIGHT", scaleDown, "LEFT", -5, 0)
SkinSimpleButton(histBtn, "H")
histBtn.tooltipText = "Open History"
histBtn:SetScript("OnClick", function()
    if LootRememberer.guiContainer then
        if LootRememberer.guiContainer:IsVisible() then
            LootRememberer.guiContainer:Hide()
        else
            LootRememberer.guiContainer:Show()
            if LootRememberer.SelectTab then
                LootRememberer.SelectTab(2)
            end
        end
    else
        LootRememberer:SlashProcessor("")
        if LootRememberer.SelectTab then
            LootRememberer.SelectTab(2)
        end
    end
end)
f.histBtn = histBtn

-- Scroll Area
local scrollFrame = CreateFrame("ScrollFrame", "LootRemembererRollsScrollFrame", f, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -42)
scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 16)

-- Apply Addon's Scrollbar Skinning
local function SkinScrollBarLocal(sf)
    local name = sf:GetName()
    local scrollbar = _G[name.."ScrollBar"]
    if not scrollbar then return end
    local up = _G[name.."ScrollBarScrollUpButton"]
    local down = _G[name.."ScrollBarScrollDownButton"]
    if up then up:Hide() up:SetScale(0.0001) end
    if down then down:Hide() down:SetScale(0.0001) end
    local thumb = scrollbar:GetThumbTexture()
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetVertexColor(1, 1, 1, 0.5)
        thumb:SetWidth(8)
    end
    scrollbar:SetWidth(8)
end
SkinScrollBarLocal(scrollFrame)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(310, 1)
scrollFrame:SetScrollChild(scrollChild)

local UpdateLockIcon
-- Bottom-Right Diagonal Resizer
local resizeBR = CreateFrame("Button", nil, f)
resizeBR:SetSize(16, 16)
resizeBR:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

resizeBR:SetNormalTexture("")
resizeBR:SetHighlightTexture("")

if not resizeBR.Base then
    resizeBR.Base = resizeBR:CreateTexture(nil, "ARTWORK")
    resizeBR.Base:SetSize(10, 10)
    resizeBR.Base:SetTexture("Interface\\AddOns\\LootRememberer\\Media\\ModernTriangle.tga")
    resizeBR.Base:SetPoint("BOTTOMRIGHT", -3, 3)
    resizeBR.Base:SetTexCoord(0, 1, 1, 0) -- Flip Vertically
    resizeBR.Base:SetVertexColor(0.5, 0.5, 0.5, 1)
end

if not resizeBR.Mask then
    resizeBR.Mask = resizeBR:CreateTexture(nil, "OVERLAY")
    resizeBR.Mask:SetSize(10, 10)
    resizeBR.Mask:SetTexture("Interface\\AddOns\\LootRememberer\\Media\\ModernTriangle.tga")
    resizeBR.Mask:SetPoint("BOTTOMRIGHT", -3, 3)
    resizeBR.Mask:SetTexCoord(0, 1, 1, 0) -- Flip Vertically
end

local function UpdateResizerGrip(btn, forceHover)
    local settings = LootRememberer:GetSettings()
    local isLocked = settings.rollsWindowLocked
    
    if btn.Base then btn.Base:SetVertexColor(0.5, 0.5, 0.5, 1) end
    if not btn.Mask then return end
    
    if isLocked then
        btn.Mask:Show()
        btn.Mask:SetVertexColor(1, 0.82, 0, 1) -- Gold
        btn.Mask:SetBlendMode("BLEND")
    elseif btn.IsHovering or forceHover then
        btn.Mask:Show()
        btn.Mask:SetVertexColor(1, 1, 1, 0.5) -- White Highlight
        btn.Mask:SetBlendMode("ADD")
    else
        btn.Mask:Hide()
    end
end

local function UpdateResizerVisibility()
    if not LootRememberer.db or not LootRememberer.db.char or not LootRememberer.db.char.settings then
        return
    end
    local settings = LootRememberer:GetSettings()
    if settings.rollsWindowCollapsed or not f:IsShown() then
        resizeBR:Hide()
        return
    end
    
    if f:IsMouseOver() then
        resizeBR:Show()
        resizeBR:SetAlpha(1.0)
    else
        resizeBR:Hide()
    end
end

local hoverPoller = CreateFrame("Frame", nil, f)
hoverPoller:SetScript("OnUpdate", function(self, elapsed)
    UpdateResizerVisibility()
end)

resizeBR:SetScript("OnEnter", function(self)
    self.IsHovering = true
    UpdateResizerGrip(self, true)
    
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Resize Window", 1, 0.82, 0)
    local settings = LootRememberer:GetSettings()
    if settings.rollsWindowLocked then
        GameTooltip:AddLine("Right-click to unlock window.", 1, 1, 1)
    else
        GameTooltip:AddLine("Right-click to lock window.", 1, 1, 1)
    end
    GameTooltip:Show()
end)

resizeBR:SetScript("OnLeave", function(self)
    self.IsHovering = false
    UpdateResizerGrip(self, false)
    GameTooltip:Hide()
end)

resizeBR:SetScript("OnMouseDown", function(self, button)
    if button == "RightButton" then return end
    local settings = LootRememberer:GetSettings()
    if settings.rollsWindowLocked then return end
    
    local scale = f:GetScale() or 1
    local left = f:GetLeft() / scale
    local top = f:GetTop() / scale
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    f:StartSizing("BOTTOMRIGHT")
    f.isResizing = true
end)

resizeBR:SetScript("OnMouseUp", function(self, button)
    if f.isResizing then
        f:StopMovingOrSizing()
        f.isResizing = false
        local settings = LootRememberer:GetSettings()
        settings.rollsWindowWidth = f:GetWidth()
        settings.rollsWindowHeight = f:GetHeight()
        
        local scale = f:GetScale() or 1
        local left = f:GetLeft() / scale
        local top = f:GetTop() / scale
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        settings.rollsWindowX = left
        settings.rollsWindowTop = top
        settings.rollsWindowY = f:GetBottom() / scale
    end
    
    if button == "RightButton" then
        local settings = LootRememberer:GetSettings()
        settings.rollsWindowLocked = not settings.rollsWindowLocked
        if not settings.rollsWindowLocked then
            if _G["DEMODAL_DB"] then
                _G["DEMODAL_DB"].anchorLootRememberer = false
            end
        end
        PlaySound(settings.rollsWindowLocked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        UpdateLockIcon()
        if settings.rollsWindowLocked then
            f:StopMovingOrSizing()
        end
        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText("Resize Window", 1, 0.82, 0)
            if settings.rollsWindowLocked then
                GameTooltip:AddLine("Right-click to unlock window.", 1, 1, 1)
            else
                GameTooltip:AddLine("Right-click to lock window.", 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end
end)

resizeBR:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Lock Button (for Classic Skin)
local lockBtn = CreateFrame("Button", nil, f)
lockBtn:SetSize(16, 16)
lockBtn:Hide()
f.lockBtn = lockBtn

lockBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")

function UpdateLockIcon()
    local settings = LootRememberer:GetSettings()
    if settings.rollsWindowLocked then
        lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        lockBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Down")
    else
        lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        lockBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
    end
    
    if resizeBR then
        UpdateResizerGrip(resizeBR)
        UpdateResizerVisibility()
    end
end
f.UpdateLockIcon = UpdateLockIcon

lockBtn:SetScript("OnClick", function()
    local settings = LootRememberer:GetSettings()
    settings.rollsWindowLocked = not settings.rollsWindowLocked
    if not settings.rollsWindowLocked then
        if _G["DEMODAL_DB"] then
            _G["DEMODAL_DB"].anchorLootRememberer = false
        end
    end
    PlaySound(settings.rollsWindowLocked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    UpdateLockIcon()
    if settings.rollsWindowLocked then
        f:StopMovingOrSizing()
    end
end)

lockBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local settings = LootRememberer:GetSettings()
    if settings.rollsWindowLocked then
        GameTooltip:SetText("Unlock Loot Rolls Window")
    else
        GameTooltip:SetText("Lock Loot Rolls Window")
    end
    GameTooltip:Show()
end)
lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function UpdateCollapseState()
    local settings = LootRememberer:GetSettings()
    local collapsed = settings.rollsWindowCollapsed
    
    local scale = f:GetScale() or 1
    local left = f:GetLeft()
    local currentTop = f:GetTop()
    
    local skin = settings.rollsWindowSkin or "Classic"
    if collapsed then
        closeBtn:SetText(skin == "Classic" and "+" or "^")
        closeBtn.tooltipText = "Expand"
        scrollFrame:Hide()
        f:SetHeight(30)
    else
        closeBtn:SetText(skin == "Classic" and "-" or "v")
        closeBtn.tooltipText = "Minimize"
        scrollFrame:Show()
        f:SetHeight(settings.rollsWindowHeight or 400)
    end
    
    if left and currentTop then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, currentTop / scale)
        settings.rollsWindowX = left / scale
        settings.rollsWindowTop = currentTop / scale
        settings.rollsWindowY = f:GetBottom() / scale
    end
    
    if resizeBR then
        UpdateResizerVisibility()
    end
end
f.UpdateCollapseState = UpdateCollapseState

-- Dynamic Skin Application
function LootRememberer:ApplyRollsWindowSkin()
    local settings = self:GetSettings()
    local skin = settings.rollsWindowSkin or "Classic"
    local fontName = "Fonts\\FRIZQT__.TTF"
    if skin == "Classic" then
        local lineFont = _G["WatchFrameLine1"] and _G["WatchFrameLine1"].text and _G["WatchFrameLine1"].text:GetFont()
        local btnFont = _G["WatchFrameCollapseExpandButton"] and _G["WatchFrameCollapseExpandButton"]:GetFontString() and _G["WatchFrameCollapseExpandButton"]:GetFontString():GetFont()
        if lineFont then
            fontName = lineFont
        elseif btnFont then
            fontName = btnFont
        else
            fontName = GameFontNormal:GetFont() or "Fonts\\FRIZQT__.TTF"
        end
    else
        fontName = GameFontNormal:GetFont() or "Fonts\\FRIZQT__.TTF"
    end
    
    if skin == "Classic" then
        bg:Hide()
        if f.PixelBorder then
            f.PixelBorder.T:Hide()
            f.PixelBorder.B:Hide()
            f.PixelBorder.L:Hide()
            f.PixelBorder.R:Hide()
        end
        titleIcon:Hide()
        
        -- Hide scale buttons
        scaleUp:Hide()
        scaleDown:Hide()
        
        -- Show and style lock button
        lockBtn:Show()
        
        closeBtn:ClearAllPoints()
        closeBtn:SetSize(16, 16)
        closeBtn:SetPoint("RIGHT", f, "TOPRIGHT", -6, -15)
        SkinClassicButton(closeBtn, settings.rollsWindowCollapsed and "+" or "-")
        
        lockBtn:ClearAllPoints()
        lockBtn:SetSize(16, 16)
        lockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        SkinClassicLockButton(lockBtn)
        UpdateLockIcon()
        
        histBtn:ClearAllPoints()
        histBtn:SetSize(16, 16)
        histBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)
        SkinClassicButton(histBtn, "H")
        histBtn:Show()
        
        -- Show header background (try global SetAtlasTexture first, fallback to path)
        local success = false
        if _G["SetAtlasTexture"] then
            success = pcall(_G["SetAtlasTexture"], headerBg, 'QuestTracker-Header')
        end
        if not success then
            headerBg:SetTexture("Interface\\AddOns\\LootRememberer\\Media\\QuestTracker.blp")
            headerBg:SetTexCoord(0.0107421875, 0.5576171875, 0.482421875, 0.619140625)
        end
        headerBg:SetAlpha(0.9)
        headerBg:ClearAllPoints()
        headerBg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        headerBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        headerBg:SetHeight(30)
        headerBg:Show()
        
        -- Align Title Text centered vertically in the headerBg
        titleText:ClearAllPoints()
        titleText:SetPoint("LEFT", f, "TOPLEFT", 32, -15)
        titleText:SetFont("Fonts\\FRIZQT__.TTF", 13)
        titleText:SetShadowColor(0, 0, 0, 1)
        titleText:SetShadowOffset(1, -1)
        titleText:SetText("Loot Rolls") -- Force font redraw
        
        -- Objectives filigree underline is anchored underneath the headerBg
        underline:ClearAllPoints()
        underline:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -30)
        underline:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -30)
        underline:Show()
        
        -- Scroll frame offset to sit below the header background and filigree line
        local scrollbar = _G["LootRemembererRollsScrollFrameScrollBar"]
        local scrollbarShown = scrollbar and scrollbar:IsShown()
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -36)
        scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", scrollbarShown and -28 or -10, 16)
        
        f:SetMinResize(200, 150)
    else
        lockBtn:Hide()
        UnskinClassicLockButton(lockBtn)
        
        -- Show scale buttons
        scaleUp:Show()
        scaleDown:Show()
        
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.07, 0.07, 0.07, 0.75)
        bg:Show()
        
        if f.PixelBorder then
            f.PixelBorder.T:Show()
            f.PixelBorder.B:Show()
            f.PixelBorder.L:Show()
            f.PixelBorder.R:Show()
        end
        titleIcon:Show()
        
        titleText:ClearAllPoints()
        titleText:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
        titleText:SetFont("Fonts\\ARIALN.TTF", 16, "OUTLINE")
        titleText:SetShadowOffset(0, 0)
        titleText:SetText("Loot Rolls") -- Force font redraw
        
        underline:Hide()
        headerBg:Hide()
        
        -- Unskin buttons
        closeBtn:ClearAllPoints()
        closeBtn:SetSize(22, 22)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
        UnskinClassicButton(closeBtn)
        
        scaleUp:ClearAllPoints()
        scaleUp:SetSize(22, 22)
        scaleUp:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
        UnskinClassicButton(scaleUp)
        
        scaleDown:ClearAllPoints()
        scaleDown:SetSize(22, 22)
        scaleDown:SetPoint("RIGHT", scaleUp, "LEFT", -5, 0)
        UnskinClassicButton(scaleDown)
        
        histBtn:ClearAllPoints()
        histBtn:SetSize(22, 22)
        histBtn:SetPoint("RIGHT", scaleDown, "LEFT", -5, 0)
        UnskinClassicButton(histBtn)
        histBtn:Show()
        
        -- Restore scroll frame offset for Modern skin
        local scrollbar = _G["LootRemembererRollsScrollFrameScrollBar"]
        local scrollbarShown = scrollbar and scrollbar:IsShown()
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -42)
        scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", scrollbarShown and -28 or -10, 16)
        
        if resizeBR then
            UpdateResizerVisibility()
        end
        
        f:SetMinResize(260, 200)
    end
    
    UpdateCollapseState()
    
    if f:IsShown() then
        f:UpdateList()
    end
end

-- Track Window dimensions and position
f:SetScript("OnShow", function()
    local settings = LootRememberer:GetSettings()
    settings.rollsWindowShown = true
    f:UpdateList()
end)
f:SetScript("OnHide", function()
    local settings = LootRememberer:GetSettings()
    settings.rollsWindowShown = false
end)
f:SetScript("OnSizeChanged", function(self)
    local width = scrollFrame:GetWidth()
    if width > 0 then
        scrollChild:SetWidth(width)
    end
    
    local settings = LootRememberer:GetSettings()
    local skin = settings.rollsWindowSkin or "Classic"
    if skin == "Classic" then
        headerBg:SetHeight(30)
        titleText:ClearAllPoints()
        titleText:SetPoint("LEFT", self, "TOPLEFT", 32, -15)
        
        closeBtn:ClearAllPoints()
        closeBtn:SetSize(16, 16)
        closeBtn:SetPoint("RIGHT", self, "TOPRIGHT", -6, -15)
        
        lockBtn:ClearAllPoints()
        lockBtn:SetSize(16, 16)
        lockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        
        histBtn:ClearAllPoints()
        histBtn:SetSize(16, 16)
        histBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)
        
        underline:ClearAllPoints()
        underline:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -30)
        underline:SetPoint("TOPRIGHT", self, "TOPRIGHT", -6, -30)
        
        local scrollbar = _G["LootRemembererRollsScrollFrameScrollBar"]
        local scrollbarShown = scrollbar and scrollbar:IsShown()
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 10, -36)
        scrollFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", scrollbarShown and -28 or -10, 16)
    end
    
    f:UpdateList()
end)

-- Pools for reusing UI frames to avoid garbage collection lag
f.headerPool = {}
f.subPool = {}
f.expandedItems = {}

local function AcquireHeader()
    for _, frame in ipairs(f.headerPool) do
        if not frame:IsShown() then
            frame:Show()
            return frame
        end
    end

    local frame = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    frame:SetHeight(40)
    
    -- Plus/Minus button
    local expandBtn = CreateFrame("Button", nil, frame)
    expandBtn:SetSize(16, 16)
    expandBtn:SetPoint("LEFT", frame, "LEFT", 2, 0)
    
    local expandBg = expandBtn:CreateTexture(nil, "BACKGROUND")
    expandBg:SetTexture("Interface\\Buttons\\UI-RadioButton")
    expandBg:SetTexCoord(0, 0.25, 0, 1) -- Unchecked radio button (circle)
    expandBg:SetVertexColor(1, 0.82, 0)
    expandBg:SetAllPoints()
    
    local expandText = expandBtn:CreateFontString(nil, "OVERLAY")
    expandText:SetFont("Fonts\\ARIALN.TTF", 12, "BOLD")
    expandText:SetTextColor(1, 0.3, 0.3)
    expandText:SetPoint("CENTER", 0, 0)
    
    expandBtn.text = expandText
    frame.expandBtn = expandBtn

    -- Item Icon (larger 36x36 size)
    local iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    iconFrame:EnableMouse(true)
    iconFrame:SetSize(36, 36)
    iconFrame:SetPoint("LEFT", expandBtn, "RIGHT", 6, 0)
    iconFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1.5,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    
    local iconTex = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconTex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1.5, -1.5)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1.5, 1.5)
    iconFrame.tex = iconTex
    frame.iconFrame = iconFrame

    -- Text Info Box (flat 1px black outline removed, frame kept for hover/click)
    local box = CreateFrame("Button", nil, frame)
    box:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
    box:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    box:SetHeight(36)

    local name = box:CreateFontString(nil, "OVERLAY")
    name:SetFont("Fonts\\ARIALN.TTF", 13, "OUTLINE")
    name:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
    name:SetPoint("TOPRIGHT", box, "TOPRIGHT", -80, -2)
    name:SetJustifyH("LEFT")
    
    local sub = box:CreateFontString(nil, "OVERLAY")
    sub:SetFont("Fonts\\ARIALN.TTF", 14, "OUTLINE")
    sub:SetTextColor(1, 0.82, 0) -- Gold player name
    sub:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 2, 2)
    sub:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -80, 2)
    sub:SetJustifyH("LEFT")

    local rollVal = box:CreateFontString(nil, "OVERLAY")
    rollVal:SetFont("Fonts\\ARIALN.TTF", 20, "OUTLINE")
    rollVal:SetTextColor(1, 0.82, 0)

    local rollIcon = box:CreateTexture(nil, "OVERLAY")
    rollIcon:SetSize(28, 28) -- Larger icon size

    box.name = name
    box.sub = sub
    box.rollVal = rollVal
    box.rollIcon = rollIcon
    frame.box = box

    table.insert(f.headerPool, frame)
    return frame
end

local function AcquireSub()
    for _, frame in ipairs(f.subPool) do
        if not frame:IsShown() then
            frame:Show()
            return frame
        end
    end

    local frame = CreateFrame("Frame", nil, scrollChild)
    frame:SetHeight(22)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
    text:SetPoint("LEFT", frame, "LEFT", 25, 0)
    text:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
    text:SetJustifyH("LEFT")
    frame.text = text

    table.insert(f.subPool, frame)
    return frame
end

function f:UpdateList(preventRecursion)
    -- Hide all current pool items
    for _, frame in ipairs(f.headerPool) do frame:Hide() end
    for _, frame in ipairs(f.subPool) do frame:Hide() end

    local settings = LootRememberer:GetSettings()
    local skin = settings.rollsWindowSkin or "Classic"
    local fontName = "Fonts\\ARIALN.TTF"
    if skin == "Classic" then
        local lineFont = _G["WatchFrameLine1"] and _G["WatchFrameLine1"].text and _G["WatchFrameLine1"].text:GetFont()
        local btnFont = _G["WatchFrameCollapseExpandButton"] and _G["WatchFrameCollapseExpandButton"]:GetFontString() and _G["WatchFrameCollapseExpandButton"]:GetFontString():GetFont()
        if lineFont then
            fontName = lineFont
        elseif btnFont then
            fontName = btnFont
        else
            fontName = GameFontNormal:GetFont() or "Fonts\\FRIZQT__.TTF"
        end
    end

    local session = LootRememberer.History and LootRememberer.History.currentSession
    if not session or not session.items or not session.itemOrder or #session.itemOrder == 0 then
        if not f.emptyLabel then
            f.emptyLabel = scrollChild:CreateFontString(nil, "OVERLAY")
            f.emptyLabel:SetTextColor(0.6, 0.6, 0.6)
            f.emptyLabel:SetPoint("TOP", scrollChild, "TOP", 0, -20)
        end
        f.emptyLabel:SetFont(fontName, skin == "Classic" and 13 or 12, skin == "Classic" and "" or "OUTLINE")
        if skin == "Classic" then
            f.emptyLabel:SetShadowColor(0, 0, 0, 1)
            f.emptyLabel:SetShadowOffset(1, -1)
        else
            f.emptyLabel:SetShadowOffset(0, 0)
        end
        f.emptyLabel:SetText("No rolls in current session.")
        f.emptyLabel:Show()
        scrollChild:SetHeight(40)
        local scrollbar = _G["LootRemembererRollsScrollFrameScrollBar"]
        if scrollbar then
            scrollbar:Hide()
        end
        return
    end

    if f.emptyLabel then f.emptyLabel:Hide() end

    local fWidth = f:GetWidth() or 330
    if fWidth <= 0 then fWidth = 330 end

    local scrollbar = _G["LootRemembererRollsScrollFrameScrollBar"]
    local scrollbarShown = scrollbar and scrollbar:IsShown()

    -- Dynamically position scrollFrame based on scrollbar visibility
    scrollFrame:ClearAllPoints()
    if skin == "Classic" then
        scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -36)
        scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", scrollbarShown and -28 or -10, 16)
    else
        scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -42)
        scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", scrollbarShown and -28 or -10, 16)
    end

    -- Calculate scrollWidth and child width based on active scrollbar
    local scrollWidth = fWidth - (scrollbarShown and 38 or 20)
    scrollChild:SetWidth(scrollWidth)
    local width = scrollWidth
    local yOffset = 0

    -- Iterate backwards to show newest first
    for i = #session.itemOrder, 1, -1 do
        local key = session.itemOrder[i]
        local record = session.items[key]
        if record then
            local itemLink = record.link
            local name, _, quality, _, _, _, _, _, _, _, _ = GetItemInfo(itemLink)
            
            -- Fallback in case item details are still loading
            if not name then
                name = itemLink:match("%[(.-)%]") or "Loading..."
                quality = 1 -- default to white color for loading state
            end

            -- Quality filter (multi-select table)
            local shouldShow = true
            local qualFilter = settings.rollsQualityFilter
            if type(qualFilter) == "table" and quality then
                if qualFilter[quality] == false then
                    shouldShow = false
                end
            end

            -- Fade-out filter
            if shouldShow then
                local fadeOutEnabled = settings.rollsWindowFadeOutEnabled ~= false
                local fadeOutSec = settings.rollsWindowFadeOutSec
                if fadeOutEnabled and fadeOutSec and fadeOutSec > 0 and record.timestamp then
                    local elapsed = time() - record.timestamp
                    if elapsed >= fadeOutSec then
                        shouldShow = false
                    end
                end
            end

            if shouldShow then
            local r, g, b = GetItemQualityColor(quality)

            -- Acquire & Setup Header Frame
            local row = AcquireHeader()
            row:SetWidth(width)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)

            -- Plus/Minus button configuration
            local isExpanded = f.expandedItems[key]
            if skin == "Classic" then
                -- Always use ARIALN for the expand glyphs in Classic; FRIZQT__ has a lower baseline
                -- that makes + look off-center inside the radio-button circle.
                row.expandBtn.text:SetFont("Fonts\\ARIALN.TTF", 16, "BOLD")
                row.expandBtn.text:SetShadowColor(0, 0, 0, 1)
                row.expandBtn.text:SetShadowOffset(1, -1)
                row.expandBtn.text:ClearAllPoints()
                if isExpanded then
                    row.expandBtn.text:SetPoint("CENTER", row.expandBtn, "CENTER", 0, 2)
                else
                    row.expandBtn.text:SetPoint("CENTER", row.expandBtn, "CENTER", 0, 0)
                end
            else
                row.expandBtn.text:SetFont(fontName, 12, "BOLD")
                row.expandBtn.text:SetShadowOffset(0, 0)
                row.expandBtn.text:ClearAllPoints()
                row.expandBtn.text:SetPoint("CENTER", row.expandBtn, "CENTER", 0, 0)
            end
            row.expandBtn.text:SetText(isExpanded and "-" or "+")
            row.expandBtn:SetScript("OnClick", function()
                f.expandedItems[key] = not isExpanded
                f:UpdateList()
            end)

            -- Item Icon configuration
            row.iconFrame.tex:SetTexture(GetItemIcon(itemLink))
            row.iconFrame:SetBackdropBorderColor(r, g, b, 1)

            local nameSize = (skin == "Classic") and 13 or 13
            local subSize = (skin == "Classic") and 13 or 14
            row.box.name:SetFont(fontName, nameSize, skin == "Classic" and "" or "OUTLINE")
            row.box.sub:SetFont(fontName, subSize, skin == "Classic" and "" or "OUTLINE")
            if skin == "Classic" then
                row.box.name:SetShadowColor(0, 0, 0, 1)
                row.box.name:SetShadowOffset(1, -1)
                row.box.sub:SetShadowColor(0, 0, 0, 1)
                row.box.sub:SetShadowOffset(1, -1)
            else
                row.box.name:SetShadowOffset(0, 0)
                row.box.sub:SetShadowOffset(0, 0)
            end
            
            -- Dynamically adjust text right anchor based on skin to maximize text width
            row.box.name:ClearAllPoints()
            row.box.sub:ClearAllPoints()
            if skin == "Classic" then
                row.box.name:SetPoint("TOPLEFT", row.box, "TOPLEFT", 2, -2)
                row.box.name:SetPoint("TOPRIGHT", row.box, "TOPRIGHT", -55, -2)
                row.box.sub:SetPoint("BOTTOMLEFT", row.box, "BOTTOMLEFT", 2, 2)
                row.box.sub:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -55, 2)
            else
                row.box.name:SetPoint("TOPLEFT", row.box, "TOPLEFT", 2, -2)
                row.box.name:SetPoint("TOPRIGHT", row.box, "TOPRIGHT", -80, -2)
                row.box.sub:SetPoint("BOTTOMLEFT", row.box, "BOTTOMLEFT", 2, 2)
                row.box.sub:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -80, 2)
            end

            -- Box detail styling
            row.box.name:SetText(name)
            row.box.name:SetTextColor(r, g, b)

            -- Hook tooltips and clicks
            row.iconFrame:SetScript("OnEnter", function()
                GameTooltip:SetOwner(row.iconFrame, "ANCHOR_TOPRIGHT")
                GameTooltip:SetHyperlink(itemLink)
                GameTooltip:Show()
            end)
            row.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

            row.box:SetScript("OnEnter", function()
                GameTooltip:SetOwner(row.box, "ANCHOR_TOPRIGHT")
                GameTooltip:SetHyperlink(itemLink)
                GameTooltip:Show()
            end)
            row.box:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.box:SetScript("OnClick", function()
                if IsShiftKeyDown() and ChatFrameEditBox and ChatFrameEditBox:IsShown() then
                    ChatFrameEditBox:Insert(itemLink)
                end
            end)

            -- Display Winner or Leader Roll
            local leader = GetLeaderRoll(record)
            local rollValSize = (skin == "Classic") and 16 or 20
            row.box.rollVal:SetFont(fontName, rollValSize, skin == "Classic" and "" or "OUTLINE")
            if skin == "Classic" then
                row.box.rollVal:SetShadowColor(0, 0, 0, 1)
                row.box.rollVal:SetShadowOffset(1, -1)
            else
                row.box.rollVal:SetShadowOffset(0, 0)
            end

            if leader then
                row.box.sub:SetText(leader.player)
                
                local iconTex = ICONS[leader.type] or ICONS["Pass"]
                row.box.rollIcon:SetTexture(iconTex)
                row.box.rollIcon:Show()

                if skin == "Classic" then
                    -- Stacking vertically (Classic)
                    row.box.rollIcon:SetSize(18, 18)
                    row.box.rollVal:SetJustifyH("CENTER")
                    
                    if leader.value > 0 then
                        row.box.rollVal:SetText(tostring(leader.value))
                        row.box.rollVal:Show()
                        row.box.rollVal:ClearAllPoints()
                        row.box.rollVal:SetPoint("TOP", row.box.rollIcon, "BOTTOM", 0, -1)
                        
                        local valSize = 12
                        row.box.rollVal:SetFont(fontName, valSize, "")
                        
                        row.box.rollIcon:ClearAllPoints()
                        row.box.rollIcon:SetPoint("TOPRIGHT", row.box, "TOPRIGHT", -16, -4)
                    else
                        row.box.rollVal:SetText("")
                        row.box.rollVal:Hide()
                        
                        row.box.rollIcon:ClearAllPoints()
                        row.box.rollIcon:SetPoint("RIGHT", row.box, "RIGHT", -16, 0)
                    end
                else
                    -- Stacking vertically (Modern)
                    row.box.rollIcon:SetSize(20, 20)
                    row.box.rollVal:SetJustifyH("CENTER")
                    
                    if leader.value > 0 then
                        row.box.rollVal:SetText(tostring(leader.value))
                        row.box.rollVal:Show()
                        row.box.rollVal:ClearAllPoints()
                        row.box.rollVal:SetPoint("TOP", row.box.rollIcon, "BOTTOM", 0, -1)
                        
                        local valSize = 13
                        row.box.rollVal:SetFont(fontName, valSize, "OUTLINE")
                        
                        row.box.rollIcon:ClearAllPoints()
                        row.box.rollIcon:SetPoint("TOPRIGHT", row.box, "TOPRIGHT", -18, -3)
                    else
                        row.box.rollVal:SetText("")
                        row.box.rollVal:Hide()
                        
                        row.box.rollIcon:ClearAllPoints()
                        row.box.rollIcon:SetPoint("RIGHT", row.box, "RIGHT", -18, 0)
                    end
                end
            else
                row.box.sub:SetText("|cffaaaaaaNo rolls yet|r")
                row.box.rollVal:SetText("")
                row.box.rollVal:Hide()
                row.box.rollIcon:Hide()
            end

            yOffset = yOffset - 42

            -- Sub-rows for expanded rolls
            if isExpanded then
                local rolls = {}
                for _, roll in ipairs(record.rolls) do
                    table.insert(rolls, roll)
                end

                -- Sort rolls: Winner first, then Need (high->low), Greed/DE (high->low), Pass
                table.sort(rolls, function(a, b)
                    local aWin = (a.player == record.winner)
                    local bWin = (b.player == record.winner)
                    if aWin and not bWin then return true end
                    if bWin and not aWin then return false end

                    local aPrio = PRIO[a.type] or 0
                    local bPrio = PRIO[b.type] or 0
                    if aPrio ~= bPrio then return aPrio > bPrio end

                    local valA, valB = a.value or 0, b.value or 0
                    if valA ~= valB then return valA > valB end

                    return a.player < b.player
                end)

                local subSize = (skin == "Classic") and 12 or 13
                local winSize = (skin == "Classic") and 13 or 14
                local subIconSize = (skin == "Classic") and 15 or 18

                if #rolls == 0 then
                    local sub = AcquireSub()
                    sub:SetWidth(width)
                    sub:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
                    sub.text:SetFont(fontName, subSize, skin == "Classic" and "" or "OUTLINE")
                    if skin == "Classic" then
                        sub.text:SetShadowColor(0, 0, 0, 1)
                        sub.text:SetShadowOffset(1, -1)
                    else
                        sub.text:SetShadowOffset(0, 0)
                    end
                    sub.text:SetText("|cff888888No rolls recorded.|r")
                    sub:EnableMouse(false)
                    sub:SetScript("OnEnter", nil)
                    sub:SetScript("OnLeave", nil)
                    yOffset = yOffset - 22
                else
                    for _, r in ipairs(rolls) do
                        local sub = AcquireSub()
                        sub:SetWidth(width)
                        sub:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)

                        local iconTex = ICONS[r.type] or ICONS["Pass"]
                        local valStr = (r.value and r.value > 0) and (r.value .. " - ") or ""
                        local specIconStr = (r.info and r.info.icon) and (string.format("|T%s:%d:%d:0:0|t ", r.info.icon, subIconSize, subIconSize)) or ""
                        
                        local detailStr = ""
                        if r.info and r.info.level then
                            detailStr = string.format(" |cff888888(Lvl %s %s)|r", r.info.level or "?", r.info.spec or "")
                        end

                        local lineText
                        -- Determine player name color: class color if available, gold fallback
                        local nameHex = "ffd100"
                        if r.info and r.info.class then
                            local cc = RAID_CLASS_COLORS[r.info.class]
                            if cc then
                                nameHex = string.format("%02x%02x%02x",
                                    math.floor(cc.r * 255),
                                    math.floor(cc.g * 255),
                                    math.floor(cc.b * 255))
                            end
                        end
                        local nameColor = "|cff" .. nameHex
                        if r.player == record.winner then
                            -- Winner row styling: thicker outline font (bold look), no "Winner:" prefix tag
                            sub.text:SetFont(fontName, winSize, skin == "Classic" and "" or "THICKOUTLINE")
                            if skin == "Classic" then
                                sub.text:SetShadowColor(0, 0, 0, 1)
                                sub.text:SetShadowOffset(1, -1)
                            else
                                sub.text:SetShadowOffset(0, 0)
                            end
                            lineText = string.format("|T%s:%d:%d:0:0|t %s%s|r%s%s%s|r%s",
                                iconTex, subIconSize, subIconSize, nameColor, valStr, nameColor, specIconStr, r.player, detailStr)
                        else
                            -- Regular row styling
                            sub.text:SetFont(fontName, subSize, skin == "Classic" and "" or "OUTLINE")
                            if skin == "Classic" then
                                sub.text:SetShadowColor(0, 0, 0, 1)
                                sub.text:SetShadowOffset(1, -1)
                            else
                                sub.text:SetShadowOffset(0, 0)
                            end
                            lineText = string.format("|T%s:%d:%d:0:0|t %s%s|r%s%s%s|r%s",
                                iconTex, subIconSize, subIconSize, nameColor, valStr, nameColor, specIconStr, r.player, detailStr)
                        end

                        sub.text:SetText(lineText)

                        -- Enable mouse and set player hover tooltip
                        sub:EnableMouse(true)
                        local rollPlayer = r.player
                        local rollInfo = r.info
                        sub:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
                            local cc = rollInfo and rollInfo.class and RAID_CLASS_COLORS[rollInfo.class]
                            local cr, cg, cb = cc and cc.r or 1, cc and cc.g or 0.82, cc and cc.b or 0
                            GameTooltip:AddLine(rollPlayer, cr, cg, cb)
                            if rollInfo then
                                if rollInfo.level and rollInfo.level ~= "??" then
                                    GameTooltip:AddLine("Level: " .. rollInfo.level, 1, 1, 1)
                                end
                                if rollInfo.race and rollInfo.race ~= "UNKNOWN" then
                                    local formattedRace = rollInfo.race
                                    if formattedRace == "BloodElf" or formattedRace == "Bloodelf" then formattedRace = "Blood Elf" end
                                    if formattedRace == "NightElf" or formattedRace == "Nightelf" then formattedRace = "Night Elf" end
                                    if formattedRace == "Scourge" then formattedRace = "Undead" end
                                    formattedRace = formattedRace:gsub("^%l", string.upper)
                                    GameTooltip:AddLine("Race: " .. formattedRace, 1, 1, 1)
                                end
                                if rollInfo.class and rollInfo.class ~= "UNKNOWN" then
                                    local formattedClass = rollInfo.class:sub(1,1):upper() .. rollInfo.class:sub(2):lower()
                                    GameTooltip:AddLine("Class: " .. formattedClass, 1, 1, 1)
                                end
                                if rollInfo.spec then
                                    GameTooltip:AddLine("Spec: " .. rollInfo.spec, 1, 1, 1)
                                end
                            end
                            GameTooltip:Show()
                        end)
                        sub:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)

                        yOffset = yOffset - 22
                    end
                end
            end

            yOffset = yOffset - 4 -- separator padding
            end -- if shouldShow
        end
    end

    scrollChild:SetHeight(-yOffset)

    local scrollbar = _G["LootRemembererRollsScrollFrameScrollBar"]
    if scrollbar then
        local viewHeight = scrollFrame:GetHeight() or 0
        if viewHeight <= 0 then
            local fHeight = f:GetHeight() or 0
            if fHeight <= 0 then
                fHeight = settings.rollsWindowHeight or 400
            end
            local skin = settings.rollsWindowSkin or "Classic"
            if skin == "Classic" then
                local w = f:GetWidth() or 230
                if w <= 0 then w = 230 end
                viewHeight = fHeight - (w / 8 + 8) - 16
            else
                viewHeight = fHeight - 58
            end
        end
        local contentHeight = -yOffset
        local shouldShow = contentHeight > viewHeight + 2
        local isShown = not not scrollbar:IsShown()
        if shouldShow ~= isShown then
            if shouldShow then
                scrollbar:Show()
            else
                scrollbar:Hide()
            end
            if not preventRecursion then
                f:UpdateList(true)
            end
        end
    end
end

-- Initialize the window position and size based on saved variables
function LootRememberer:InitRollsWindow()
    local settings = self:GetSettings()
    
    if settings.rollsWindowLocked == nil then
        if _G["DEMODAL_DB"] and _G["DEMODAL_DB"].anchorLootRememberer then
            settings.rollsWindowLocked = true
        else
            settings.rollsWindowLocked = false
        end
    end
    
    f:ClearAllPoints()
    local left = settings.rollsWindowX
    local top = settings.rollsWindowTop
    if not top and settings.rollsWindowY then
        top = settings.rollsWindowY + (settings.rollsWindowHeight or 400)
        settings.rollsWindowTop = top
    end
    
    if left and top then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        f:SetPoint("CENTER")
    end
    
    f:SetSize(settings.rollsWindowWidth or 330, settings.rollsWindowHeight or 400)
    f:SetScale(settings.rollsWindowScale or 1.0)
    
    if settings.rollsWindowShown then
        f:Show()
    else
        f:Hide()
    end
    
    self:ApplyRollsWindowSkin()
end
-- OnUpdate poller: refresh list periodically when fade-out is active
-- Uses pcall so that early-load errors don't cause WoW to silently kill the OnUpdate script
local rollsFadePoller = CreateFrame("Frame")
rollsFadePoller.elapsed = 0
rollsFadePoller:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < 2 then return end -- check every 2 seconds
    self.elapsed = 0
    if not f:IsShown() then return end
    local ok, err = pcall(function()
        local settings = LootRememberer:GetSettings()
        local fadeOutEnabled = settings.rollsWindowFadeOutEnabled ~= false
        local fadeOutSec = settings.rollsWindowFadeOutSec
        if fadeOutEnabled and fadeOutSec and fadeOutSec > 0 then
            f:UpdateList()
        end
    end)
    -- silently ignore errors during addon init; script stays alive
end)
