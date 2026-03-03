-- ==========================================================
-- ZealCycle-turtle (Standalone Addon)
-- Opener: Crusader Strike x3
-- Maintain: Holy Strike spam
-- Refresh: 1x Crusader Strike at REFRESH_AFTER seconds after LAST CS
-- Reset: if ZEAL_DURATION seconds since last CS (cushion vs 30s Zeal)
-- HARD RESYNC: if Zeal stacks == 0, force opener immediately
--
-- Author: TerraBaddie
-- Version: 1.0
-- ==========================================================

-- Toggle in-game if you want:
-- /run ZEAL_DEBUG=true
-- /run ZEAL_DEBUG=false

if ZEAL_DEBUG == nil then ZEAL_DEBUG = false end

-- Persistent state (globals on purpose so they persist between calls)
if zealStart == nil then zealStart = 0 end
if phase == nil then phase = "OPEN" end
if openRemaining == nil then openRemaining = 0 end

-- Tunables
local ZEAL_DURATION = 29.7   -- 300ms early reset cushion vs 30s Zeal expiry jitter
local REFRESH_AFTER = 22.2   -- refresh timing (cushion vs drop window)
local ZEAL_BUFF_NAME = "Zeal" -- IMPORTANT: must match tooltip title exactly

-- ----------------------------------------------------------
-- Debug helper
-- ----------------------------------------------------------
local function Debug(msg)
    if ZEAL_DEBUG and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

-- ----------------------------------------------------------
-- Spellbook lookup (standalone replacement for SpellNum)
-- ----------------------------------------------------------
local spellIndexCache = {}

local function FindSpellBookIndexByName(spellName)
    if not spellName then return nil end
    if spellIndexCache[spellName] then return spellIndexCache[spellName] end

    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if name == spellName then
            spellIndexCache[spellName] = i
            return i
        end
        i = i + 1
        if i > 500 then break end -- safety guard
    end

    return nil
end

local function SpellReady(spellName)
    local idx = FindSpellBookIndexByName(spellName)
    if not idx then return false end

    local start, dur, enabled = GetSpellCooldown(idx, BOOKTYPE_SPELL)
    if enabled == 0 then return false end

    local now = GetTime()
    return (start == 0 or dur == 0 or (start + dur) <= now)
end

-- ----------------------------------------------------------
-- Buff stack lookup by tooltip title (Vanilla/Turtle style)
-- ----------------------------------------------------------
local function GetPlayerBuffStacksByName(buffName)
    if not GameTooltip or not buffName then return 0 end

    for i = 0, 31 do
        local b = GetPlayerBuff(i, "HELPFUL")
        if b and b >= 0 then
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            GameTooltip:SetPlayerBuff(b)

            local name = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
            if name == buffName then
                local apps = GetPlayerBuffApplications(b)
                if apps and apps > 0 then return apps end
                return 1
            end
        end
    end

    return 0
end

-- ----------------------------------------------------------
-- Range gate (vanilla-era-ish)
-- ----------------------------------------------------------
local function InMeleeishRange()
    if not UnitExists("target") then return false end
    if UnitIsDead("target") then return false end
    if not UnitCanAttack("player", "target") then return false end

    if CheckInteractDistance then
        return CheckInteractDistance("target", 3)
    end
    return true
end

-- ----------------------------------------------------------
-- Cycle reset
-- ----------------------------------------------------------
local function ResetCycle()
    zealStart = 0
    phase = "OPEN"
    openRemaining = 0
    Debug("|cffff0000[ZEAL]|r Zeal expired/desynced — restarting opener")
end

-- ----------------------------------------------------------
-- Main entry point: call this from a normal macro
-- /run ZealStrikeCycle()
-- ----------------------------------------------------------
function ZealStrikeCycle()
    if not InMeleeishRange() then return end

    -- Turtle: Crusader Strike and Holy Strike share the same cooldown bucket
    if not SpellReady("Crusader Strike") then return end -- shared CD gate

    local now = GetTime()

    -- HARD RESYNC: if Zeal stacks are gone, force opener immediately
    local zealStacks = GetPlayerBuffStacksByName(ZEAL_BUFF_NAME)
    if zealStacks == 0 and (phase ~= "OPEN" or zealStart > 0 or openRemaining ~= 0) then
        ResetCycle()
    end

    -- Expire/reset based on time since LAST CS (with cushion)
    if zealStart > 0 and (now - zealStart) >= ZEAL_DURATION then
        ResetCycle()
    end

    -- ===== OPENER =====
    if phase == "OPEN" then
        if zealStacks >= 3 then
            phase = "MAINT"
            openRemaining = 0
            return
        end

        if openRemaining == 0 then openRemaining = 3 end

        CastSpellByName("Crusader Strike")
        openRemaining = openRemaining - 1
        zealStart = now -- baseline is ALWAYS the most recent CS press

        Debug(string.format("|cff00ff00[ZEAL]|r Building stacks (%d CS remaining)", openRemaining))

        if openRemaining <= 0 then
            phase = "MAINT"
            openRemaining = 0
        end
        return
    end

    -- ===== MAINTENANCE =====
    if zealStart > 0 and (now - zealStart) >= REFRESH_AFTER then
        Debug("|cffff8800[ZEAL]|r Refreshing with Crusader Strike!")
        CastSpellByName("Crusader Strike")
        zealStart = now
        return
    end

    -- Otherwise Holy Strike
    if ZEAL_DEBUG and zealStart > 0 then
        local untilRefresh = REFRESH_AFTER - (now - zealStart)
        if untilRefresh < 0 then untilRefresh = 0 end
        Debug(string.format(
            "|cff00ff00[ZEAL]|r Holy Strike phase (%.1fs until refresh) (stacks: %d)",
            untilRefresh, zealStacks
        ))
    end

    CastSpellByName("Holy Strike")
end
