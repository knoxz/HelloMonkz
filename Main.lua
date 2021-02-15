local addonName, HM = ...
local HL = HeroLib
local Unit = HL.Unit
local Player = Unit.Player
local Target = Unit.Target

HelloMonkz = HM
HM.Version = 0.1

HM.Settings = {Active = true, CDsON = true, AoEON = true}

HM.Settings.ProtPala = {
    AutoDefs = true,
    -- CDs HP %
    GoAKHP = 30,
    WordofGloryHP = 70,
    ArdentDefenderHP = 60,
    ShieldoftheRighteousHP = 80
}

HM.Settings.Brewmaster = {
    Purify = {
        Low = false,
        Medium = true,
        High = true
    }
}

local toDebug = false
local toPrintActions = false

HM.Timer = {Pulse = 0, PulseOffset = 0.1, TTD = 0}

function HM.debugPrint(...)
    if toDebug then
        print(...)
    end
end

function HM.actionPrint(...)
    if toPrintActions then
        print(...)
    end
end

function HM.TargetIsValid()
    return Target:Exists() and Player:CanAttack(Target) and not Target:IsDeadOrGhost()
end

function HM.CastCycle(Object, Enemies, Condition, OutofRange)
    if Condition(Target) then
        if OutofRange then
            return Object, {["spell"] = SpellObject, ["multitarget"] = false}
        end
    end
    if HM.Settings.AoEON then
        local TargetGUID = Target:GUID()
        for _, CycleUnit in pairs(Enemies) do
            if
                CycleUnit:GUID() ~= TargetGUID and not CycleUnit:IsFacingBlacklisted() and
                    not CycleUnit:IsUserCycleBlacklisted() and
                    Condition(CycleUnit) and
                    CycleUnit:IsSpellInRange(Object)
             then
                return Object, {["spell"] = SpellObject, ["multitarget"] = CycleUnit:GUID()}
            end
        end
    end
end

-- Compare two values
local CompareThisTable = {
    [">"] = function(A, B)
        return A > B
    end,
    ["<"] = function(A, B)
        return A < B
    end,
    [">="] = function(A, B)
        return A >= B
    end,
    ["<="] = function(A, B)
        return A <= B
    end,
    ["=="] = function(A, B)
        return A == B
    end,
    ["min"] = function(A, B)
        return A < B
    end,
    ["max"] = function(A, B)
        return A > B
    end
}
local function CompareThis(Operator, A, B)
    return CompareThisTable[Operator](A, B)
end

function HM.CastTargetIf(Object, Enemies, TargetIfMode, TargetIfCondition, Condition, InRange)
    local TargetCondition = (not Condition or (Condition and Condition(Target)))
    if not HM.Settings.AoEON and TargetCondition and InRange then
        return Object
    end
    if HM.Settings.AoEON then
        -- print("Cycle:")
        local BestUnit, BestConditionValue = nil, nil
        local count = 0
        for _, CycleUnit in pairs(Enemies) do
            -- print("UnitGUID:", CycleUnit:GUID())
            count = count + 1
            if
                not CycleUnit:IsFacingBlacklisted() and not CycleUnit:IsUserCycleBlacklisted() and
                    (CycleUnit:AffectingCombat() or CycleUnit:IsDummy()) and
                    ((Condition and Condition(CycleUnit)) or not Condition) and
                    (not BestConditionValue or
                        CompareThis(TargetIfMode, TargetIfCondition(CycleUnit), BestConditionValue)) and
                    HM.CanCast(Object:ID(), CycleUnit:GUID())
             then
                BestUnit, BestConditionValue = CycleUnit, TargetIfCondition(CycleUnit)
            -- print("New Best Unit:", BestUnit:GUID(), " Remaining: ",BestConditionValue)
            end
        end
        -- print("Count was: ", count)
        if BestUnit then
            if
                (BestUnit:GUID() == Target:GUID()) or
                    (TargetCondition and (BestConditionValue == TargetIfCondition(Target)))
             then
                if InRange then
                    return Object
                end
            else
                HM.debugPrint("TargetGUID: ", Target:GUID())
                HM.debugPrint("Spell: ", Object:Name(), "on BestTarget: ", BestUnit:GUID())
                return Object, BestUnit:GUID()
            end
        end
    end
end

do -- wrap the script in do/end to not pollute global namespace
    --------------------------------------------------------------------------------------------------------------------------------
    -- globals
    --------------------------------------------------------------------------------------------------------------------------------
    local HM = HelloMonkz
    local HL = HeroLib

    --------------------------------------------------------------------------------------------------------------------------------
    -- minor functions
    --------------------------------------------------------------------------------------------------------------------------------

    local function IsUnitInLineOfSight(unita, unitb)
        local ax, ay, az = GetUnitPosition(unita)
        local bx, by, bz = GetUnitPosition(unitb)
        local losFlags = bit.bor(0x10, 0x100, 0x1)
        local hit, x, y, z = TraceLine(ax, ay, az + 2.25, bx, by, bz + 2.25, losFlags)
        return hit == 0
    end

    local function IsUnitFacing(unita, unitb)
        local ax, ay, az = GetUnitPosition(unita)
        local bx, by, bz = GetUnitPosition(unitb)
        local dx, dy, dz = ax - bx, ay - by, az - bz
        local rotation = UnitFacing(unita)
        local value = (dy * math.sin(-rotation) - dx * math.cos(-rotation)) / math.sqrt(dx * dx + dy * dy)
        local isFacing = value > 0.20
        return isFacing
    end

    local function DistanceTo(unita, unitb)
        local ax, ay, az = GetUnitPosition(unita)
        local bx, by, bz = GetUnitPosition(unitb)
        local dx, dy, dz = ax - bx, ay - by, az - bz
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    local function GetRemainingCd(skillId)
        local startTime, duration = GetSpellCooldown(skillId)
        if not startTime then
            return 0
        end

        local cd = startTime + duration - GetTime()
        if cd > 0 then
            return cd
        else
            return 0
        end
    end

    local function Ping()
        local _, _, _, latencyWorld = GetNetStats()
        return latencyWorld * 0.001 + 0.25
    end

    function HM.CurrentlyCasting()
        if UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil then
            HM.debugPrint("currently casting")
            return true
        end
    end

    --------------------------------------------------------------------------------------------------------------------------------
    -- CanCast
    --------------------------------------------------------------------------------------------------------------------------------
    function HM.CanCast(id, unit)
        --------------------------------
        -- check if I have a target
        --------------------------------
        if not UnitGUID("target") then
            HM.debugPrint("no target")
            return
        end

        --------------------------------
        -- check if I am casting
        --------------------------------
        -- if UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil then
        --     HM.debugPrint("currently casting")
        --     return
        -- end

        --------------------------------
        -- check if I can attack
        --------------------------------
        -- if not UnitCanAttack("player", unit) then
        --     HM.debugPrint("can't attack target")
        --     return false
        -- end

        --------------------------------
        -- check if GCD is active
        --------------------------------
        -- if GetRemainingCd(61304) > Ping() then
        --     HM.debugPrint("gcd")
        --     return false
        -- end

        --------------------------------
        -- check if target is dead
        --------------------------------
        if UnitIsDeadOrGhost(unit) then
            HM.debugPrint("target dead")
            return false
        end

        --------------------------------
        -- check IsUsableSpell
        --------------------------------
        -- local canUse, noMana = IsUsableSpell(id)
        -- if not canUse or noMana then
        --     HM.debugPrint("spell not usable")
        --     return false
        -- end

        --------------------------------
        -- check if spell is in cooldown
        -- --------------------------------
        -- if GetRemainingCd(id) > Ping() then
        --     HM.debugPrint("cooldown")
        --     return false
        -- end

        --------------------------------
        -- check spell range
        --------------------------------
        -- local _, _, _, _, _, maxRange, _ = GetSpellInfo(id)
        -- if maxRange == 0 then
        --     -- melee or self-cast
        --     local skillName = GetSpellInfo(id)
        --     if IsHelpfulSpell(skillName) then
        --         -- self-cast; continue on to the next check
        --     elseif not IsItemInRange(8149, unit) then
        --         HM.debugPrint("not in melee range")
        --         return false
        --     end
        -- else
        --     -- ranged
        --     if IsSpellInRange(id, unit) == 0 then
        --         HM.debugPrint("not in range")
        --         return false
        --     end
        -- end

        --------------------------------
        -- check spell LOS
        --------------------------------
        if not IsUnitInLineOfSight("player", unit) then
            HM.debugPrint("not in LOS")
            return false
        end

        --------------------------------
        -- check facing
        --------------------------------
        if not IsUnitFacing("player", unit) then
            HM.debugPrint("not facing")
            return false
        end

        --------------------------------
        -- success
        --------------------------------
        HM.debugPrint("can cast")
        return true
    end

    local availableRotations = {
        -- Death Knight
        [250] = false, -- Blood
        [251] = false, -- Frost
        [252] = false, -- Unholy
        -- Demon Hunter
        [577] = false, -- Havoc
        [581] = false, -- Vengeance
        -- Druid
        [102] = false, -- Balance
        [103] = false, -- Feral
        [104] = false, -- Guardian
        [105] = false, -- Restoration
        -- Hunter
        [253] = false, -- Beast Mastery
        [254] = false, -- Marksmanship
        [255] = false, -- Survival
        -- Mage
        [62] = false, -- Arcane
        [63] = false, -- Fire
        [64] = false, -- Frost
        -- Monk
        [268] = {apl = HM.BrewmasterAPL}, -- Brewmaster
        [269] = {apl = HM.WindwalkerAPL}, -- Windwalker
        [270] = false, -- Mistweaver
        -- Paladin
        [65] = false, -- Holy
        [66] = {apl = HM.ProtAPL}, -- Protection
        [70] = {apl = HM.RetriAPL}, -- Retribution
        -- Priest
        [256] = false, -- Discipline
        [257] = false, -- Holy
        [258] = false, -- Shadow
        -- Rogue
        [259] = false, -- Assassination
        [260] = false, -- Outlaw
        [261] = false, -- Subtlety
        -- Shaman
        [262] = {apl = HM.ElementalAPL}, -- Elemental
        [263] = {apl = HM.EnhancementAPL}, -- Enhancement
        [264] = false, -- Restoration
        -- Warlock
        [265] = false, -- Affliction
        [266] = false, -- Demonology
        [267] = false, -- Destruction
        -- Warrior
        [71] = false, -- Arms
        [72] = false, -- Fury
        [73] = false -- Protection
    }

    --------------------------------------------------------------------------------------------------------------------------------
    -- OnUpdate
    --------------------------------------------------------------------------------------------------------------------------------
    local function OnUpdate(self, elapsed)
        if GetTime(true) > HM.Timer.Pulse and not IsMounted() then
            -- Put a 10ms min and 50ms max limiter to save FPS (depending on World Latency).
            -- And add the Reduce CPU Load offset (default 50ms) in case it's enabled.
            -- HL.Timer.PulseOffset = mathmax(10, mathmin(50, HL.Latency()))/1000 + (HL.GUISettings.General.ReduceCPULoad and HL.GUISettings.General.ReduceCPULoadOffset or 0)
            -- Until further performance improvements, we'll use 66ms (i.e. 15Hz) as baseline. Offset (positive or negative) can still be added from Settings.lua
            -- HL.Timer.PulseOffset = 0.066 + (HL.GUISettings.General.ReduceCPULoad and HL.GUISettings.General.ReduceCPULoadOffset or 0)
            -- HM.debugPrint("OnUpdate")
            HM.Timer.Pulse = GetTime() + HM.Timer.PulseOffset

            -- print("Mouseover:" .. UnitGUID("mouseover"))

            local specID = HeroCache.Persistent.Player.Spec[1]
            -- HM.debugPrint("SpecID:", specID)
            if specID and HM.Settings.Active and availableRotations[specID] and not HM.CurrentlyCasting() then
                -- print("")
                -- print("Tick:")
                spellToUseTable = availableRotations[specID].apl()
                -- HM.debugPrint("Spell:" .. spell .. "   multiDotTarget:" .. multiDotTarget)
                if spellToUseTable and spellToUseTable["spell"] then
                    HM.debugPrint(
                        "Main Function = Spell: ",
                        spellToUseTable["spell"]:Name(),
                        " on ",
                        spellToUseTable["multitarget"]
                    )
                    if spellToUseTable["multitarget"] then
                        -- print("MultiDot Spell: " , spellToUseTable["spell"])
                        -- print("GUID: " , spellToUseTable["multitarget"])
                        local old_state = UnitGUID("mouseover")
                        CallSecureFunction(
                            "CastSpellByName",
                            spellToUseTable["spell"]:Name(),
                            SetMouseOver(spellToUseTable["multitarget"])
                        )
                        SetMouseOver(old_state)
                    else
                        CallSecureFunction("CastSpellByName", spellToUseTable["spell"]:Name(), "target")
                        HM.actionPrint(
                            "casting " ..
                                spellToUseTable["spell"]:Name() ..
                                    "(" .. spellToUseTable["spell"]:ID() .. ") on " .. UnitGUID("target")
                        )
                        if IsGuid(UnitGUID("target")) and SpellIsTargeting() then
                            local x, y, z = GetUnitPosition("target")
                            local xoffset = math.random(-1, 1)
                            local yoffset = math.random(-1, 1)
                            ClickPosition(x + xoffset, y + yoffset, z)
                            HM.actionPrint("clicking")
                            return
                        end
                    end
                else
                    --    HM.debugPrint("No Spell found!")
                end
            end
        -- --------------------------------
        -- -- main logic
        -- --------------------------------
        -- if CanCast(skillId, "target")
        -- and (lastSkillUsed ~= skillId or GetTime() > lastSkillTime + 0.25)
        -- then
        -- 	lastSkillUsed, lastSkillTime = skillId, GetTime()
        -- 	CallSecureFunction("CastSpellByName", skillName, "target")
        -- 	actionPrint("casting " .. skillName .. "(" .. skillId .. ") on " .. GetUnitName("target"))
        -- 	if IsGuid(UnitGUID("target")) and SpellIsTargeting() then
        -- 		local x, y, z = GetUnitPosition("target")
        -- 		local xoffset = math.random(-1, 1)
        -- 		local yoffset = math.random(-1, 1)
        -- 		ClickPosition(x + xoffset, y + yoffset, z)
        -- 		actionPrint("clicking")
        -- 		return
        -- 	end
        -- end
        end
    end

    --------------------------------------------------------------------------------------------------------------------------------
    --
    --------------------------------------------------------------------------------------------------------------------------------
    local callbackFrame = CreateFrame("frame", nil, UIParent)
    callbackFrame:SetScript("OnUpdate", OnUpdate)
end -- wrap the script in do/end to not pollute global namespace

-- local frame = CreateFrame("Frame")
-- frame:RegisterEvent("ADDON_LOADED")
-- frame:RegisterEvent("PLAYER_LOGOUT")

-- frame:SetScript(
--     "OnEvent",
--     function(self, event, arg1)
--         if event == "ADDON_LOADED" and arg1 == "HelloMonkz" then
--             -- Our saved variables, if they exist, have been loaded at this point.
--             print("HelloMonkz loaded!")
--             if HM.Settings == nil then
--                 -- This is the first time this addon is loaded; set SVs to default values
--                 HM.Settings = {
--                     CDsON = true,
--                     AoEON = true
--                 }
--             end
--         end
--     end
-- )

function HM.CreateUIFrame()
    -- create the UI frame
    HM.OptionsFrame = {}
    HM.OptionsFrame.MainFrame = CreateFrame("frame", "HM_OptionsMainFrame", UIParent)
    HM.OptionsFrame.MainFrame:SetWidth(250)
    HM.OptionsFrame.MainFrame:SetHeight(300)
    HM.OptionsFrame.MainFrame:SetFrameStrata("MEDIUM")
    HM.OptionsFrame.MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    HM.OptionsFrame.MainFrame:SetMovable(true)
    HM.OptionsFrame.MainFrame:EnableMouse(true)
    local t = HM.OptionsFrame.MainFrame:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    t:SetAllPoints(HM.OptionsFrame.MainFrame)
    HM.OptionsFrame.MainFrame.texture = t

    HM.OptionsFrame.MainFrame:Hide()

    HM.OptionsFrame.MainFrame:SetScript(
        "OnMouseDown",
        function(self, button)
            if button == "LeftButton" and not HM.OptionsFrame.MainFrame.isMoving then
                HM.OptionsFrame.MainFrame:StartMoving()
                HM.OptionsFrame.MainFrame.isMoving = true
            end
        end
    )
    HM.OptionsFrame.MainFrame:SetScript(
        "OnMouseUp",
        function(self, button)
            if button == "LeftButton" and HM.OptionsFrame.MainFrame.isMoving then
                HM.OptionsFrame.MainFrame:StopMovingOrSizing()
                HM.OptionsFrame.MainFrame.isMoving = false
            end
        end
    )
    HM.OptionsFrame.MainFrame:SetScript(
        "OnHide",
        function(self)
            if (HM.OptionsFrame.MainFrame.isMoving) then
                HM.OptionsFrame.MainFrame:StopMovingOrSizing()
                HM.OptionsFrame.MainFrame.isMoving = false
            end
        end
    )

    HM.OptionsFrame.FontString1 =
        HM.OptionsFrame.MainFrame:CreateFontString("HM_OptionsTitle", "ARTWORK", "ChatFontNormal")
    HM.OptionsFrame.FontString1:SetParent(HM.OptionsFrame.MainFrame)
    HM.OptionsFrame.FontString1:SetPoint("TOP", HM.OptionsFrame.MainFrame, "TOP", 0, 0)
    HM.OptionsFrame.FontString1:SetWidth(250)
    HM.OptionsFrame.FontString1:SetHeight(20)
    HM.OptionsFrame.FontString1:SetFontObject("GameFontHighlightLarge")
    HM.OptionsFrame.FontString1:SetText("HelloMonkz - v" .. HM.Version)
    HM.OptionsFrame.FontString1:SetTextColor(1, 1, 0)

    HM.OptionsFrame.MainFrame.Options = CreateFrame("frame", "HM_OptionsMainFrame_Selection", HM_OptionsMainFrame)
    HM.OptionsFrame.MainFrame.Options:SetWidth(100)
    HM.OptionsFrame.MainFrame.Options:SetHeight(260)
    HM.OptionsFrame.MainFrame.Options:SetFrameStrata("MEDIUM")
    HM.OptionsFrame.MainFrame.Options:SetPoint("LEFT", HM_OptionsMainFrame, "LEFT", 0, -10)
    HM.OptionsFrame.MainFrame.Options:EnableMouse(true)

    local t = HM.OptionsFrame.MainFrame.Options:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    t:SetAllPoints(HM.OptionsFrame.MainFrame.Options)
    HM.OptionsFrame.MainFrame.Options.texture = t

    -- General Label FRAME

    HM.OptionsFrame.MainFrame.SelectOptionsGeneral =
        CreateFrame("frame", "HM_OptionsMainFrame_GeneralOptions", HM_OptionsMainFrame)
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral:SetWidth(100)
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral:SetHeight(30)
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral:SetFrameStrata("HIGH")
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral:SetPoint("TOPLEFT", HM_OptionsMainFrame, "TOPLEFT", 0, -40)
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral:EnableMouse(true)
    local t = HM.OptionsFrame.MainFrame.SelectOptionsGeneral:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    t:SetAllPoints(HM.OptionsFrame.MainFrame.SelectOptionsGeneral)
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.texture = t

    HM.OptionsFrame.MainFrame.SelectOptionsGeneral:SetScript(
        "OnMouseDown",
        function(self, button)
            if button == "LeftButton" then
                HM.OptionsFrame.MainFrame.OptionsGeneral:Show()
                HM.OptionsFrame.MainFrame.OptionsProtPala:Hide()
            -- HM.OptionsFrame.MainFrame.OptionsGeneral:Hide()
            end
        end
    )

    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.texture = t
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.FontString =
        HM.OptionsFrame.MainFrame:CreateFontString("HM_SelectOptionsGeneralFS1", "ARTWORK", "ChatFontNormal")
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.FontString:SetParent(HM.OptionsFrame.MainFrame.SelectOptionsGeneral)
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.FontString:SetPoint(
        "CENTER",
        HM.OptionsFrame.MainFrame.SelectOptionsGeneral,
        "CENTER",
        0,
        0
    )
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.FontString:SetWidth(100)
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.FontString:SetHeight(20)
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.FontString:SetFontObject("GameFontHighlightLarge")
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.FontString:SetText("General")
    HM.OptionsFrame.MainFrame.SelectOptionsGeneral.FontString:SetTextColor(1, 1, 0)

    -- General Options Frame

    HM.OptionsFrame.MainFrame.OptionsGeneral = CreateFrame("frame", "HM_OptionsMainFrame_General", HM_OptionsMainFrame)
    HM.OptionsFrame.MainFrame.OptionsGeneral:SetWidth(140)
    HM.OptionsFrame.MainFrame.OptionsGeneral:SetHeight(260)
    HM.OptionsFrame.MainFrame.OptionsGeneral:SetFrameStrata("MEDIUM")
    HM.OptionsFrame.MainFrame.OptionsGeneral:SetPoint("LEFT", HM_OptionsMainFrame, "LEFT", 105, -10)
    HM.OptionsFrame.MainFrame.OptionsGeneral:EnableMouse(true)
    local t = HM.OptionsFrame.MainFrame.OptionsGeneral:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    t:SetAllPoints(HM.OptionsFrame.MainFrame.OptionsGeneral)
    HM.OptionsFrame.MainFrame.OptionsGeneral.texture = t
    HM.OptionsFrame.MainFrame.OptionsGeneral:Hide()

    -- Active Checkbox
    HM.OptionsFrame.Active =
        CreateFrame(
        "CheckButton",
        "HM_Active",
        HM.OptionsFrame.MainFrame.OptionsGeneral,
        "ChatConfigCheckButtonTemplate"
    )
    HM.OptionsFrame.Active:SetPoint("TOPLEFT", HM.OptionsFrame.MainFrame.OptionsGeneral, "TOPLEFT", 10, -10)
    if (HM.Settings.Active) then
        HM.OptionsFrame.Active:SetChecked(true)
    else
        HM.OptionsFrame.Active:SetChecked(false)
    end
    getglobal(HM.OptionsFrame.Active:GetName() .. "Text"):SetText(": " .. "Active")
    getglobal(HM.OptionsFrame.Active:GetName() .. "Text"):SetTextColor(1, 1, 1)
    HM.OptionsFrame.Active:SetScript(
        "OnClick",
        function()
            if (HM.OptionsFrame.Active:GetChecked() == true) then
                HM.Settings.Active = true
            else
                HM.Settings.Active = false
            end
        end
    )

    -- Automatic CDs Checkbox
    HM.OptionsFrame.AutomaticCDs =
        CreateFrame(
        "CheckButton",
        "HM_AutomaticCDs",
        HM.OptionsFrame.MainFrame.OptionsGeneral,
        "ChatConfigCheckButtonTemplate"
    )
    HM.OptionsFrame.AutomaticCDs:SetPoint("TOPLEFT", HM.OptionsFrame.MainFrame.OptionsGeneral, "TOPLEFT", 10, -40)
    if (HM.Settings.CDsON) then
        HM.OptionsFrame.AutomaticCDs:SetChecked(true)
    else
        HM.OptionsFrame.AutomaticCDs:SetChecked(false)
    end
    getglobal(HM.OptionsFrame.AutomaticCDs:GetName() .. "Text"):SetText(": " .. "Auto CDs")
    getglobal(HM.OptionsFrame.AutomaticCDs:GetName() .. "Text"):SetTextColor(1, 1, 1)
    HM.OptionsFrame.AutomaticCDs:SetScript(
        "OnClick",
        function()
            if (HM.OptionsFrame.AutomaticCDs:GetChecked() == true) then
                HM.Settings.CDsON = true
            else
                HM.Settings.CDsON = false
            end
        end
    )

    -- Automatic AoE Checkbox
    HM.OptionsFrame.AutomaticAoE =
        CreateFrame(
        "CheckButton",
        "HM_AutomaticAoE",
        HM.OptionsFrame.MainFrame.OptionsGeneral,
        "ChatConfigCheckButtonTemplate"
    )
    HM.OptionsFrame.AutomaticAoE:SetPoint("TOPLEFT", HM.OptionsFrame.MainFrame.OptionsGeneral, "TOPLEFT", 10, -70)
    if (HM.Settings.CDsON) then
        HM.OptionsFrame.AutomaticAoE:SetChecked(true)
    else
        HM.OptionsFrame.AutomaticAoE:SetChecked(false)
    end
    getglobal(HM.OptionsFrame.AutomaticAoE:GetName() .. "Text"):SetText(": " .. "Auto AoE")
    getglobal(HM.OptionsFrame.AutomaticAoE:GetName() .. "Text"):SetTextColor(1, 1, 1)
    HM.OptionsFrame.AutomaticAoE:SetScript(
        "OnClick",
        function()
            if (HM.OptionsFrame.AutomaticAoE:GetChecked() == true) then
                HM.Settings.AoEON = true
            else
                HM.Settings.AoEON = false
            end
        end
    )

    -- General Label FRAME

    HM.OptionsFrame.MainFrame.SelectOptionsProtection =
        CreateFrame("frame", "HM_OptionsMainFrame_ProtectionOptions", HM_OptionsMainFrame)
    HM.OptionsFrame.MainFrame.SelectOptionsProtection:SetWidth(100)
    HM.OptionsFrame.MainFrame.SelectOptionsProtection:SetHeight(30)
    HM.OptionsFrame.MainFrame.SelectOptionsProtection:SetFrameStrata("HIGH")
    HM.OptionsFrame.MainFrame.SelectOptionsProtection:SetPoint("TOPLEFT", HM_OptionsMainFrame, "TOPLEFT", 0, -70)
    HM.OptionsFrame.MainFrame.SelectOptionsProtection:EnableMouse(true)
    local t = HM.OptionsFrame.MainFrame.SelectOptionsProtection:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    t:SetAllPoints(HM.OptionsFrame.MainFrame.SelectOptionsProtection)
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.texture = t

    HM.OptionsFrame.MainFrame.SelectOptionsProtection:SetScript(
        "OnMouseDown",
        function(self, button)
            if button == "LeftButton" then
                HM.OptionsFrame.MainFrame.OptionsGeneral:Hide()
                HM.OptionsFrame.MainFrame.OptionsProtPala:Show()
            -- HM.OptionsFrame.MainFrame.OptionsGeneral:Hide()
            end
        end
    )

    HM.OptionsFrame.MainFrame.SelectOptionsProtection.texture = t
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.FontString =
        HM.OptionsFrame.MainFrame:CreateFontString("HM_SelectOptionsProtextionFS1", "ARTWORK", "ChatFontNormal")
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.FontString:SetParent(
        HM.OptionsFrame.MainFrame.SelectOptionsGeneral
    )
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.FontString:SetPoint(
        "CENTER",
        HM.OptionsFrame.MainFrame.SelectOptionsProtection,
        "CENTER",
        0,
        0
    )
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.FontString:SetWidth(100)
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.FontString:SetHeight(20)
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.FontString:SetFontObject("GameFontHighlightLarge")
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.FontString:SetText("Prot Pala")
    HM.OptionsFrame.MainFrame.SelectOptionsProtection.FontString:SetTextColor(1, 1, 0)

    -- ProtPala Options Frame

    HM.OptionsFrame.MainFrame.OptionsProtPala =
        CreateFrame("frame", "HM_OptionsMainFrame_ProtPala", HM_OptionsMainFrame)
    HM.OptionsFrame.MainFrame.OptionsProtPala:SetWidth(140)
    HM.OptionsFrame.MainFrame.OptionsProtPala:SetHeight(260)
    HM.OptionsFrame.MainFrame.OptionsProtPala:SetFrameStrata("MEDIUM")
    HM.OptionsFrame.MainFrame.OptionsProtPala:SetPoint("LEFT", HM_OptionsMainFrame, "LEFT", 105, -10)
    HM.OptionsFrame.MainFrame.OptionsProtPala:EnableMouse(true)
    local t = HM.OptionsFrame.MainFrame.OptionsProtPala:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    t:SetAllPoints(HM.OptionsFrame.MainFrame.OptionsProtPala)
    HM.OptionsFrame.MainFrame.OptionsProtPala.texture = t
    HM.OptionsFrame.MainFrame.OptionsProtPala:Hide()

    -- ProtPala Options

    HM.OptionsFrame.AutoDefs =
        CreateFrame(
        "CheckButton",
        "HM_AutoDefs",
        HM.OptionsFrame.MainFrame.OptionsProtPala,
        "ChatConfigCheckButtonTemplate"
    )
    HM.OptionsFrame.AutoDefs:SetPoint("TOPLEFT", HM.OptionsFrame.MainFrame.OptionsGeneral, "TOPLEFT", 10, -10)
    if (HM.Settings.ProtPala.AutoDefs) then
        HM.OptionsFrame.AutoDefs:SetChecked(true)
    else
        HM.OptionsFrame.AutoDefs:SetChecked(false)
    end
    getglobal(HM.OptionsFrame.AutoDefs:GetName() .. "Text"):SetText(": " .. "Auto Defs/HP")
    getglobal(HM.OptionsFrame.AutoDefs:GetName() .. "Text"):SetTextColor(1, 1, 1)
    HM.OptionsFrame.AutoDefs:SetScript(
        "OnClick",
        function()
            if (HM.OptionsFrame.AutoDefs:GetChecked() == true) then
                HM.Settings.ProtPala.AutoDefs = true
            else
                HM.Settings.ProtPala.AutoDefs = false
            end
        end
    )

    -- UseAKHP
    HM.OptionsFrame.UseAKHP =
        CreateFrame("Slider", "HM_UseAKHP", HM.OptionsFrame.MainFrame.OptionsProtPala, "OptionsSliderTemplate")
    HM.OptionsFrame.UseAKHP:SetWidth(120)
    HM.OptionsFrame.UseAKHP:SetHeight(15)
    HM.OptionsFrame.UseAKHP:SetPoint("TOPLEFT", HM.OptionsFrame.MainFrame.OptionsProtPala, "TOPLEFT", 10, -50)
    HM.OptionsFrame.UseAKHP:SetOrientation("HORIZONTAL")
    HM.OptionsFrame.UseAKHP:SetMinMaxValues(0, 100)
    HM.OptionsFrame.UseAKHP.minValue, HM.OptionsFrame.UseAKHP.maxValue = HM.OptionsFrame.UseAKHP:GetMinMaxValues()
    getglobal(HM.OptionsFrame.UseAKHP:GetName() .. "Low"):SetText("0")
    getglobal(HM.OptionsFrame.UseAKHP:GetName() .. "High"):SetText("100")
    getglobal(HM.OptionsFrame.UseAKHP:GetName() .. "Text"):SetText(
        "Use AK below " .. HM.Settings.ProtPala.GoAKHP .. "%"
    )
    HM.OptionsFrame.UseAKHP:SetValueStep(1)
    HM.OptionsFrame.UseAKHP:SetValue(HM.Settings.ProtPala.GoAKHP)
    HM.OptionsFrame.UseAKHP:SetScript(
        "OnValueChanged",
        function(self, event)
            event = event - event % 1
            HM.Settings.ProtPala.GoAKHP = floor(event)
            getglobal(HM.OptionsFrame.UseAKHP:GetName() .. "Text"):SetText(
                "Use AK below " .. HM.Settings.ProtPala.GoAKHP .. "%"
            )
        end
    )
    HM.OptionsFrame.UseAKHP:SetScript(
        "OnMouseWheel",
        function(self, delta)
            if tonumber(self:GetValue()) == nil then
                return
            end
            self:SetValue(tonumber(self:GetValue()) + delta)
        end
    )
    HM.OptionsFrame.UseAKHP:SetValue(HM.Settings.ProtPala.GoAKHP)

    -- WorldOfGloryHP
    HM.OptionsFrame.UseWoGHP =
        CreateFrame("Slider", "HM_UseWoGHP", HM.OptionsFrame.MainFrame.OptionsProtPala, "OptionsSliderTemplate")
    HM.OptionsFrame.UseWoGHP:SetWidth(120)
    HM.OptionsFrame.UseWoGHP:SetHeight(15)
    HM.OptionsFrame.UseWoGHP:SetPoint("TOPLEFT", HM.OptionsFrame.MainFrame.OptionsProtPala, "TOPLEFT", 10, -100)
    HM.OptionsFrame.UseWoGHP:SetOrientation("HORIZONTAL")
    HM.OptionsFrame.UseWoGHP:SetMinMaxValues(0, 100)
    HM.OptionsFrame.UseWoGHP.minValue, HM.OptionsFrame.UseWoGHP.maxValue = HM.OptionsFrame.UseWoGHP:GetMinMaxValues()
    getglobal(HM.OptionsFrame.UseWoGHP:GetName() .. "Low"):SetText("0")
    getglobal(HM.OptionsFrame.UseWoGHP:GetName() .. "High"):SetText("100")
    getglobal(HM.OptionsFrame.UseWoGHP:GetName() .. "Text"):SetText(
        "Use WoG below " .. HM.Settings.ProtPala.WordofGloryHP .. "%"
    )
    HM.OptionsFrame.UseWoGHP:SetValueStep(1)
    HM.OptionsFrame.UseWoGHP:SetValue(HM.Settings.ProtPala.WordofGloryHP)
    HM.OptionsFrame.UseWoGHP:SetScript(
        "OnValueChanged",
        function(self, event)
            event = event - event % 1
            HM.Settings.ProtPala.WordofGloryHP = floor(event)
            getglobal(HM.OptionsFrame.UseWoGHP:GetName() .. "Text"):SetText(
                "Use WoG below " .. HM.Settings.ProtPala.WordofGloryHP .. "%"
            )
        end
    )
    HM.OptionsFrame.UseWoGHP:SetScript(
        "OnMouseWheel",
        function(self, delta)
            if tonumber(self:GetValue()) == nil then
                return
            end
            self:SetValue(tonumber(self:GetValue()) + delta)
        end
    )
    HM.OptionsFrame.UseWoGHP:SetValue(HM.Settings.ProtPala.WordofGloryHP)

    -- ArdentDefenderHP
    HM.OptionsFrame.ArdentDefenderHP =
        CreateFrame("Slider", "HM_ArdentDefenderHP", HM.OptionsFrame.MainFrame.OptionsProtPala, "OptionsSliderTemplate")
    HM.OptionsFrame.ArdentDefenderHP:SetWidth(120)
    HM.OptionsFrame.ArdentDefenderHP:SetHeight(15)
    HM.OptionsFrame.ArdentDefenderHP:SetPoint("TOPLEFT", HM.OptionsFrame.MainFrame.OptionsProtPala, "TOPLEFT", 10, -150)
    HM.OptionsFrame.ArdentDefenderHP:SetOrientation("HORIZONTAL")
    HM.OptionsFrame.ArdentDefenderHP:SetMinMaxValues(0, 100)
    HM.OptionsFrame.ArdentDefenderHP.minValue, HM.OptionsFrame.ArdentDefenderHP.maxValue =
        HM.OptionsFrame.ArdentDefenderHP:GetMinMaxValues()
    getglobal(HM.OptionsFrame.ArdentDefenderHP:GetName() .. "Low"):SetText("0")
    getglobal(HM.OptionsFrame.ArdentDefenderHP:GetName() .. "High"):SetText("100")
    getglobal(HM.OptionsFrame.ArdentDefenderHP:GetName() .. "Text"):SetText(
        "Use AD below " .. HM.Settings.ProtPala.ArdentDefenderHP .. "%"
    )
    HM.OptionsFrame.ArdentDefenderHP:SetValueStep(1)
    HM.OptionsFrame.ArdentDefenderHP:SetValue(HM.Settings.ProtPala.ArdentDefenderHP)
    HM.OptionsFrame.ArdentDefenderHP:SetScript(
        "OnValueChanged",
        function(self, event)
            event = event - event % 1
            HM.Settings.ProtPala.ArdentDefenderHP = floor(event)
            getglobal(HM.OptionsFrame.ArdentDefenderHP:GetName() .. "Text"):SetText(
                "Use AD below " .. HM.Settings.ProtPala.ArdentDefenderHP .. "%"
            )
        end
    )
    HM.OptionsFrame.ArdentDefenderHP:SetScript(
        "OnMouseWheel",
        function(self, delta)
            if tonumber(self:GetValue()) == nil then
                return
            end
            self:SetValue(tonumber(self:GetValue()) + delta)
        end
    )
    HM.OptionsFrame.ArdentDefenderHP:SetValue(HM.Settings.ProtPala.ArdentDefenderHP)

    -- SotRHP
    HM.OptionsFrame.SotRHP =
        CreateFrame("Slider", "HM_SotRHP", HM.OptionsFrame.MainFrame.OptionsProtPala, "OptionsSliderTemplate")
    HM.OptionsFrame.SotRHP:SetWidth(120)
    HM.OptionsFrame.SotRHP:SetHeight(15)
    HM.OptionsFrame.SotRHP:SetPoint("TOPLEFT", HM.OptionsFrame.MainFrame.OptionsProtPala, "TOPLEFT", 10, -200)
    HM.OptionsFrame.SotRHP:SetOrientation("HORIZONTAL")
    HM.OptionsFrame.SotRHP:SetMinMaxValues(0, 100)
    HM.OptionsFrame.SotRHP.minValue, HM.OptionsFrame.SotRHP.maxValue = HM.OptionsFrame.SotRHP:GetMinMaxValues()
    getglobal(HM.OptionsFrame.SotRHP:GetName() .. "Low"):SetText("0")
    getglobal(HM.OptionsFrame.SotRHP:GetName() .. "High"):SetText("100")
    getglobal(HM.OptionsFrame.SotRHP:GetName() .. "Text"):SetText(
        "Use SotR below " .. HM.Settings.ProtPala.ShieldoftheRighteousHP .. "%"
    )
    HM.OptionsFrame.SotRHP:SetValueStep(1)
    HM.OptionsFrame.SotRHP:SetValue(HM.Settings.ProtPala.ShieldoftheRighteousHP)
    HM.OptionsFrame.SotRHP:SetScript(
        "OnValueChanged",
        function(self, event)
            event = event - event % 1
            HM.Settings.ProtPala.ShieldoftheRighteousHP = floor(event)
            getglobal(HM.OptionsFrame.SotRHP:GetName() .. "Text"):SetText(
                "Use SotR below " .. HM.Settings.ProtPala.ShieldoftheRighteousHP .. "%"
            )
        end
    )
    HM.OptionsFrame.SotRHP:SetScript(
        "OnMouseWheel",
        function(self, delta)
            if tonumber(self:GetValue()) == nil then
                return
            end
            self:SetValue(tonumber(self:GetValue()) + delta)
        end
    )
    HM.OptionsFrame.SotRHP:SetValue(HM.Settings.ProtPala.ShieldoftheRighteousHP)
end

local frame_shown = true

function HM.Commands(command)
    if command == "activate" then
        HM.Settings.Active = not HM.Settings.Active
        HM.OptionsFrame.Active:SetChecked(HM.Settings.Active)
        if HM.Settings.Active then
            print("HelloMonkz enabled!")
        else
            print("HelloMonkz disbaled!")
        end
    elseif command == "cds" then
        HM.Settings.CDsON = not HM.Settings.CDsON
        HM.OptionsFrame.AutomaticCDs:SetChecked(HM.Settings.CDsON)
        if HM.Settings.CDsON then
            print("CDs enabled!")
        else
            print("CDs disbaled!")
        end
    elseif command == "aoe" then
        HM.Settings.AoEON = not HM.Settings.AoEON
        HM.OptionsFrame.AutomaticAoE:SetChecked(HM.Settings.AoEON)
        if HM.Settings.AoEON then
            print("AOE enabled!")
        else
            print("AOE disbaled!")
        end
    else
        frame_shown = not frame_shown
        HM.OptionsFrame.MainFrame:SetShown(frame_shown)
    end
end

HM.CreateUIFrame()
HM.OptionsFrame.MainFrame:SetShown(frame_shown)

SLASH_HELLOMONKZ1 = "/hm"
SlashCmdList["HELLOMONKZ"] = HM.Commands
