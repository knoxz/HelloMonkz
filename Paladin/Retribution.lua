--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- HeroLib
local HL = HeroLib
local Unit = HL.Unit
local Player = Unit.Player
local Target = Unit.Target
local Spell = HL.Spell
local MultiSpell = HL.MultiSpell
-- -- HeroRotation
-- local HR = HeroRotation
-- local AoEON = HR.AoEON
-- local HM.Settings.CDsON HR.HM.Settings.CDsON- local Cast = HR.Cast
-- Lua
local mathmin = math.min

local addonName, HM = ...

HelloMonkz = HM

--- ============================ CONTENT ============================
--- ======= APL LOCALS =======
-- Commons
-- local Everyone = HR.Commons.Everyone
-- local Paladin = HR.Commons.Paladin

-- GUI Settings
-- local Settings = {
--     General = HR.GUISettings.General,
--     Commons = HR.GUISettings.APL.Paladin.Commons,
--     Retribution = HR.GUISettings.APL.Paladin.Retribution
-- }

-- Spells
local S = Spell.Paladin.Retribution

-- -- Items
-- local I = Item.Paladin.Retribution
-- local OnUseExcludeTrinkets = {}

-- Enemies
local MeleeEnemies8y, MeleeEnemies8yCount, MeleeEnemies5y

-- Rotation Variables
local ShouldReturn
local TimeToHPG

-- Interrupts
local Interrupts = {
    {
        S.HammerofJustice,
        "Cast Hammer of Justice (Interrupt)",
        function()
            return true
        end
    }
}

--- ======= HELPERS =======
-- paladin_t::get_how_availability @ https://github.com/simulationcraft/simc/blob/shadowlands/engine/class_modules/paladin/sc_paladin.cpp#L2614
local function HoWAvailable(ThisUnit)
    if not ThisUnit:Exists() or not Player:CanAttack(ThisUnit) or ThisUnit:IsDeadOrGhost() then
        return false
    end

    if S.HammerofWrath2:IsAvailable() and (Player:BuffUp(S.AvengingWrath) or Player:BuffUp(S.Crusade)) then
        return true
    end

    if Player:BuffUp(S.FinalVerdictBuff) then
        return true
    end

    -- TODO: standing_in_hallow() @ https://github.com/simulationcraft/simc/blob/shadowlands/engine/class_modules/paladin/sc_paladin.cpp#L2588

    if ThisUnit:HealthPercentage() <= 20 then
        return true
    end

    return false
end

-- time_to_hpg_expr_t @ https://github.com/simulationcraft/simc/blob/shadowlands/engine/class_modules/paladin/sc_paladin.cpp#L2664
local function ComputeTimeToHPG()
    local GCDRemains = Player:GCDRemains()
    local ShortestHPGTime =
        mathmin(
        S.CrusaderStrike:CooldownRemains(), -- Crusader Strike
        S.BladeofJustice:CooldownRemains(), -- Blade of Justice
        HoWAvailable(Target) and S.HammerofWrath:CooldownRemains() or 10, -- Hammer or Wrath (if available, else a dummy 10s)
        S.WakeofAshes:CooldownRemains()
    )

    if GCDRemains > ShortestHPGTime then
        return GCDRemains
    end

    return ShortestHPGTime
end

--- ======= ACTION LISTS =======
local function Cooldowns()
    -- actions.cooldowns=lights_judgment,if=spell_targets.lights_judgment>=2|(!raid_event.adds.exists|raid_event.adds.in>75)
    if HM.Settings.CDsON and S.LightsJudgment:IsCastable() and Target:IsInRange(40) then
        return {["spell"] = S.LightsJudgment, ["multitarget"] = false}
    end
    -- actions.cooldowns+=/fireblood,if=buff.avenging_wrath.up|buff.crusade.up&buff.crusade.stack=10
    if
        HM.Settings.CDsON and S.Fireblood:IsCastable() and
            (Player:BuffUp(S.AvengingWrath) or (Player:BuffUp(S.Crusade) and Player:BuffStack(S.Crusade) == 10))
     then
        return {["spell"] = S.Fireblood, ["multitarget"] = false}
    end
    -- actions.cooldowns+=/shield_of_vengeance
    -- TODO: How to suggest it properly?
    -- actions.cooldowns+=/use_item,name=some_trinket,if=buff.avenging_wrath.up|buff.crusade.up
    if HM.Settings.CDsON and Player:BuffUp(S.AvengingWrath) or Player:BuffUp(S.Crusade) then
        local TrinketToUse = Player:GetUseableTrinkets(OnUseExcludeTrinkets)
        if TrinketToUse then
            return TrinketToUse
        end
    end
    -- actions.cooldowns+=/avenging_wrath,if=(holy_power>=4&time<5|holy_power>=3&time>5|talent.holy_avenger.enabled&cooldown.holy_avenger.remains=0)&time_to_hpg=0
    if
        HM.Settings.CDsON and S.AvengingWrath:IsCastable() and
            (((Player:HolyPower() >= 4 and HL.CombatTime() < 5) or (Player:HolyPower() >= 3 and HL.CombatTime() >= 5) or
                (S.HolyAvenger:IsAvailable() and S.HolyAvenger:CooldownRemains() == 0)) and
                TimeToHPG <= Player:GCDRemains())
     then
        return {["spell"] = S.AvengingWrath, ["multitarget"] = false}
    end
    -- actions.cooldowns+=/crusade,if=(holy_power>=4&time<5|holy_power>=3&time>5|talent.holy_avenger.enabled&cooldown.holy_avenger.remains=0)&time_to_hpg=0
    if
        HM.Settings.CDsON and S.Crusade:IsCastable() and
            (((Player:HolyPower() >= 4 and HL.CombatTime() < 5) or (Player:HolyPower() >= 3 and HL.CombatTime() >= 5) or
                (S.HolyAvenger:IsAvailable() and S.HolyAvenger:CooldownRemains() == 0)) and
                TimeToHPG <= Player:GCDRemains())
     then
        return {["spell"] = S.Crusade, ["multitarget"] = false}
    end
    -- actions.cooldowns+=/ashen_hallow
    if HM.Settings.CDsON and S.AshenHallow:IsCastable() then
        return {["spell"] = S.AshenHallow, ["multitarget"] = false}
    end
    -- actions.cooldowns+=/holy_avenger,if=time_to_hpg=0&((buff.avenging_wrath.up|buff.crusade.up)|(buff.avenging_wrath.down&cooldown.avenging_wrath.remains>40|buff.crusade.down&cooldown.crusade.remains>40))
    if
        HM.Settings.CDsON and S.HolyAvenger:IsCastable() and TimeToHPG <= Player:GCDRemains() and
            ((Player:BuffUp(S.AvengingWrath) or Player:BuffUp(S.Crusade)) or
                ((Player:BuffDown(S.AvengingWrath) and S.AvengingWrath:CooldownRemains() > 40) or
                    (Player:BuffDown(S.Crusade) and S.Crusade:CooldownRemains() > 40)))
     then
        return {["spell"] = S.HolyAvenger, ["multitarget"] = false}
    end
    -- actions.cooldowns+=/final_reckoning,if=holy_power>=3&cooldown.avenging_wrath.remains>gcd&time_to_hpg=0&(!talent.seraphim.enabled|buff.seraphim.up)
    if
        HM.Settings.CDsON and S.FinalReckoning:IsCastable() and Player:HolyPower() >= 3 and
            S.AvengingWrath:CooldownRemains() > Player:GCD() and
            TimeToHPG <= Player:GCDRemains() and
            (not S.Seraphim:IsAvailable() or Player:BuffUp(S.Seraphim))
     then
        return {["spell"] = S.FinalReckoning, ["multitarget"] = false}
    end
end

local function Finishers()
    -- actions.finishers=variable,name=ds_castable,value=spell_targets.divine_storm>=2|buff.empyrean_power.up&debuff.judgment.down&buff.divine_purpose.down|spell_targets.divine_storm>=2&buff.crusade.up&buff.crusade.stack<10
    -- Note: The last part with "spell_targets.divine_storm>=2&..." is redundant with the first condition.
    local DSCastable =
        MeleeEnemies8yCount >= 2 or
        (Player:BuffUp(S.EmpyreanPower) and Target:DebuffDown(S.Judgment) and Player:BuffDown(S.DivinePurpose))
    -- actions.finishers+=/seraphim,if=((!talent.crusade.enabled&buff.avenging_wrath.up|cooldown.avenging_wrath.remains>25)|(buff.crusade.up|cooldown.crusade.remains>25))
    -- &(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains<10)
    -- &(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains<10)
    -- &time_to_hpg=0
    if
        HM.Settings.CDsON and S.Seraphim:IsReady() and Target:IsInRange(30) and
            ((((not S.Crusade:IsAvailable() and Player:BuffUp(S.AvengingWrath)) or
                S.AvengingWrath:CooldownRemains() > 25) or
                (Player:BuffUp(S.Crusade) or S.Crusade:CooldownRemains() > 25)) and
                (not S.FinalReckoning:IsAvailable() or S.FinalReckoning:CooldownRemains() < 10) and
                (not S.ExecutionSentence:IsAvailable() or S.ExecutionSentence:CooldownRemains() < 10) and
                TimeToHPG <= Player:GCDRemains())
     then
        return {["spell"] = S.Seraphim, ["multitarget"] = false}
    end
    -- actions.finishers+=/vanquishers_hammer,if=(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains>gcd*10|debuff.final_reckoning.up)
    -- &(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*10|debuff.execution_sentence.up)|spell_targets.divine_storm>=2
    if
        HM.Settings.CDsON and S.VanquishersHammer:IsCastable() and Target:IsInRange(30) and
            (((not S.FinalReckoning:IsAvailable() or S.FinalReckoning:CooldownRemains() > Player:GCD() * 10 or
                Target:DebuffUp(S.FinalReckoning)) and
                (not S.ExecutionSentence:IsAvailable() or S.ExecutionSentence:CooldownRemains() > Player:GCD() * 10 or
                    Target:DebuffUp(S.ExecutionSentence))) or
                MeleeEnemies8yCount >= 2)
     then
        return {["spell"] = S.VanquishersHammer, ["multitarget"] = false}
    end
    -- actions.finishers+=/execution_sentence,if=spell_targets.divine_storm<=3&((!talent.crusade.enabled|buff.crusade.down&cooldown.crusade.remains>10)|buff.crusade.stack>=3|cooldown.avenging_wrath.remains>10|debuff.final_reckoning.up)&time_to_hpg=0
    -- Note: Slight reorder for lisibility
    if
        HM.Settings.CDsON and S.ExecutionSentence:IsReady() and Target:IsInRange(30) and MeleeEnemies8yCount <= 3 and
            TimeToHPG <= Player:GCDRemains() and
            ((not S.Crusade:IsAvailable() or (Player:BuffDown(S.Crusade) and S.Crusade:CooldownRemains() > 10)) or
                Player:BuffStack(S.Crusade) >= 3 or
                S.AvengingWrath:CooldownRemains() > 10 or
                Target:DebuffUp(S.FinalReckoning))
     then
        return {["spell"] = S.ExecutionSentence, ["multitarget"] = false}
    end
    -- actions.finishers+=/divine_storm,if=variable.ds_castable&!buff.vanquishers_hammer.up
    -- &((!talent.crusade.enabled|cooldown.crusade.remains>gcd*3)
    --     &(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*3|spell_targets.divine_storm>=3)
    --   |spell_targets.divine_storm>=2&(talent.holy_avenger.enabled&cooldown.holy_avenger.remains<gcd*3|buff.crusade.up&buff.crusade.stack<10))
    if
        S.DivineStorm:IsReady() and Target:IsInMeleeRange(5) and DSCastable and not Player:BuffUp(S.VanquishersHammer) and
            (((not S.Crusade:IsAvailable() or not HM.Settings.CDsON or S.Crusade:CooldownRemains() > Player:GCD() * 3) and
                (not S.ExecutionSentence:IsAvailable() or not HM.Settings.CDsON or
                    S.ExecutionSentence:CooldownRemains() > Player:GCD() * 3 or
                    MeleeEnemies8yCount >= 3)) or
                (MeleeEnemies8yCount >= 2 and
                    ((S.HolyAvenger:IsAvailable() and HM.Settings.CDsON and
                        S.HolyAvenger:CooldownRemains() < Player:GCD() * 3) or
                        (Player:BuffUp(S.Crusade) and Player:BuffStack(S.Crusade) < 10))))
     then
        return {["spell"] = S.DivineStorm, ["multitarget"] = false}
    end
    -- actions.finishers+=/templars_verdict,if=(!talent.crusade.enabled|cooldown.crusade.remains>gcd*3)
    --   &(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*3&spell_targets.divine_storm<=3)
    --   &(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains>gcd*3)
    --   &(!covenant.necrolord.enabled|cooldown.vanquishers_hammer.remains>gcd)
    -- |talent.holy_avenger.enabled&cooldown.holy_avenger.remains<gcd*3|buff.holy_avenger.up
    -- |buff.crusade.up&buff.crusade.stack<10|buff.vanquishers_hammer.up
    if
        S.TemplarsVerdict:IsReady() and Target:IsInMeleeRange(5) and
            (((not S.Crusade:IsAvailable() or S.Crusade:CooldownRemains() > Player:GCD() * 3) and
                (not S.ExecutionSentence:IsAvailable() or not HM.Settings.CDsON or
                    (S.ExecutionSentence:CooldownRemains() > Player:GCD() * 3 and MeleeEnemies8yCount <= 3)) and
                (not S.FinalReckoning:IsAvailable() or not HM.Settings.CDsON or
                    S.FinalReckoning:CooldownRemains() > Player:GCD() * 3) and
                (not S.VanquishersHammer:IsAvailable() or not HM.Settings.CDsON or
                    S.VanquishersHammer:CooldownRemains() > Player:GCD())) or
                (S.HolyAvenger:IsAvailable() and HM.Settings.CDsON and
                    S.HolyAvenger:CooldownRemains() < Player:GCD() * 3) or
                Player:BuffUp(S.HolyAvenger) or
                (Player:BuffUp(S.Crusade) and Player:BuffStack(S.Crusade) < 10) or
                Player:BuffUp(S.VanquishersHammer))
     then
        return {["spell"] = S.TemplarsVerdict, ["multitarget"] = false}
    end
end

local function Generators()
    -- actions.generators=call_action_list,name=finishers,if=holy_power>=5|buff.holy_avenger.up|debuff.final_reckoning.up|debuff.execution_sentence.up|buff.memory_of_lucid_dreams.up|buff.seething_rage.up
    if
        Player:HolyPower() >= 5 or Player:BuffUp(S.HolyAvenger) or Target:DebuffUp(S.FinalReckoning) or
            Target:DebuffUp(S.ExecutionSentence)
     then
        ShouldReturn = Finishers()
        if ShouldReturn then
            return ShouldReturn
        end
    end
    -- actions.generators+=/divine_toll,if=!debuff.judgment.up
    -- &(!raid_event.adds.exists|raid_event.adds.in>30)
    -- &(holy_power<=2|holy_power<=4&(cooldown.blade_of_justice.remains>gcd*2|debuff.execution_sentence.up|debuff.final_reckoning.up))
    -- &(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains>gcd*10)
    -- &(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*10)
    if
        HM.Settings.CDsON and S.DivineToll:IsCastable() and Target:IsSpellInRange(S.DivineToll) and
            not Target:DebuffUp(S.Judgment) and
            (Player:HolyPower() <= 2 or
                (Player:HolyPower() <= 4 and
                    (S.BladeofJustice:CooldownRemains() > Player:GCD() * 2 or Target:DebuffUp(S.ExecutionSentence) or
                        Target:DebuffUp(S.FinalReckoning)))) and
            (not S.FinalReckoning:IsAvailable() or S.FinalReckoning:CooldownRemains() > Player:GCD() * 10) and
            (not S.ExecutionSentence:IsAvailable() or S.ExecutionSentence:CooldownRemains() > Player:GCD() * 10)
     then
        return {["spell"] = S.DivineToll, ["multitarget"] = false}
    end
    -- actions.generators+=/wake_of_ashes,if=(holy_power=0|holy_power<=2&(cooldown.blade_of_justice.remains>gcd*2|debuff.execution_sentence.up|debuff.final_reckoning.up))
    -- &(!raid_event.adds.exists|raid_event.adds.in>20)
    -- &(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>15)
    -- &(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains>15)
    if
        HM.Settings.CDsON and S.WakeofAshes:IsCastable() and Target:IsInMeleeRange(5) and
            (Player:HolyPower() == 0 or
                (Player:HolyPower() <= 2 and
                    (S.BladeofJustice:CooldownRemains() > Player:GCD() * 2 or Target:DebuffUp(S.ExecutionSentence) or
                        Target:DebuffUp(S.FinalReckoning)))) and
            (not S.ExecutionSentence:IsAvailable() or S.ExecutionSentence:CooldownRemains() > 15) and
            (not S.FinalReckoning:IsAvailable() or S.FinalReckoning:CooldownRemains() > 15)
     then
        return {["spell"] = S.WakeofAshes, ["multitarget"] = false}
    end
    -- actions.generators+=/blade_of_justice,if=holy_power<=3
    if S.BladeofJustice:IsCastable() and Target:IsSpellInRange(S.BladeofJustice) and Player:HolyPower() <= 3 then
        return {["spell"] = S.BladeofJustice, ["multitarget"] = false}
    end
    -- actions.generators+=/hammer_of_wrath,if=holy_power<=4
    if S.HammerofWrath:IsCastable() and Target:IsInRange(30) and HoWAvailable(Target) and Player:HolyPower() <= 4 then
        return {["spell"] = S.HammerofWrath, ["multitarget"] = false}
    end
    -- actions.generators+=/judgment,if=!debuff.judgment.up&(holy_power<=2|holy_power<=4&cooldown.blade_of_justice.remains>gcd*2)
    if
        S.Judgment:IsCastable() and Target:IsInRange(30) and not Target:DebuffUp(S.Judgment) and
            (Player:HolyPower() <= 2 or
                (Player:HolyPower() <= 4 and S.BladeofJustice:CooldownRemains() > Player:GCD() * 2))
     then
        return {["spell"] = S.Judgment, ["multitarget"] = false}
    end
    -- actions.generators+=/call_action_list,name=finishers,if=(target.health.pct<=20|buff.avenging_wrath.up|buff.crusade.up|buff.empyrean_power.up)
    if
        Target:HealthPercentage() <= 20 or Player:BuffUp(S.AvengingWrath) or Player:BuffUp(S.Crusade) or
            Player:BuffUp(S.EmpyreanPower)
     then
        ShouldReturn = Finishers()
        if ShouldReturn then
            return ShouldReturn
        end
    end
    -- actions.generators+=/crusader_strike,if=cooldown.crusader_strike.charges_fractional>=1.75&(holy_power<=2|holy_power<=3&cooldown.blade_of_justice.remains>gcd*2|holy_power=4&cooldown.blade_of_justice.remains>gcd*2&cooldown.judgment.remains>gcd*2)
    if
        S.CrusaderStrike:IsCastable() and Target:IsInMeleeRange(5) and S.CrusaderStrike:ChargesFractional() >= 1.75 and
            (Player:HolyPower() <= 2 or
                (Player:HolyPower() <= 3 and S.BladeofJustice:CooldownRemains() > Player:GCD() * 2) or
                (Player:HolyPower() == 4 and S.BladeofJustice:CooldownRemains() > Player:GCD() * 2 and
                    S.Judgment:CooldownRemains() > Player:GCD() * 2))
     then
        return {["spell"] = S.CrusaderStrike, ["multitarget"] = false}
    end
    -- actions.generators+=/call_action_list,name=finishers
    ShouldReturn = Finishers()
    if ShouldReturn then
        return ShouldReturn
    end
    -- actions.generators+=/crusader_strike,if=holy_power<=4
    if S.CrusaderStrike:IsCastable() and Target:IsInMeleeRange(5) and Player:HolyPower() <= 4 then
        return {["spell"] = S.CrusaderStrike, ["multitarget"] = false}
    end
    -- actions.generators+=/arcane_torrent,if=holy_power<=4
    if S.ArcaneTorrent:IsCastable() and Target:IsInMeleeRange(5) and Player:HolyPower() <= 4 then
        return {["spell"] = S.ArcaneTorrent, ["multitarget"] = false}
    end
    -- actions.generators+=/consecration,if=time_to_hpg>gcd
    if S.Consecration:IsCastable() and Target:IsInMeleeRange(5) and TimeToHPG > Player:GCD() then
        return {["spell"] = S.Consecration, ["multitarget"] = false}
        -- {["spell"] = SpellObject, ["multitarget"] = false}
    end
end

--- ======= MAIN =======
function HM.RetriAPL()
    -- Enemies Update
    if HM.Settings.AoEON then
        MeleeEnemies8y = Player:GetEnemiesInMeleeRange(8) -- Divine Storm
        MeleeEnemies8yCount = #MeleeEnemies8y
        MeleeEnemies5y = Player:GetEnemiesInMeleeRange(5) -- Light's Judgment
    else
        MeleeEnemies8y = {}
        MeleeEnemies8yCount = 0
        MeleeEnemies5y = {}
    end

    -- Rotation Variables Update
    TimeToHPG = ComputeTimeToHPG()

    -- Defensives

    -- Out of Combat
    if not Player:AffectingCombat() then
        -- In Combat
        -- Flask
        -- Food
        -- Rune
        -- PrePot w/ Bossmod Countdown
        -- Opener
        -- if Everyone.TargetIsValid() then
        --     if Player:HolyPower() >= 4 and Target:IsInMeleeRange(5) then
        --         if S.DivineStorm:IsReady() and MeleeEnemies8yCount >= 2 then
        --             return {["spell"] = S.DivineStorm
        --         end
        --         if S.TemplarsVerdict:IsReady() and MeleeEnemies8yCount < 2 then
        --             return {["spell"] = S.TemplarsVerdict
        --         end
        --     end
        --     if S.BladeofJustice:IsCastable() and Target:IsSpellInRange(S.BladeofJustice) then
        --         return {["spell"] = S.BladeofJustice
        --     end
        --     if S.HammerofWrath:IsCastable() and Target:IsInRange(30) and HoWAvailable(Target) then
        --         return {["spell"] = S.HammerofWrath
        --     end
        --     if S.Judgment:IsCastable() and Target:IsInRange(30) then
        --         return {["spell"] = S.Judgment
        --     end
        --     if S.CrusaderStrike:IsCastable() and Target:IsInMeleeRange(5) then
        --         return {["spell"] = S.CrusaderStrike
        --     end
        -- end

        return
    elseif HM.TargetIsValid() then
        -- actions=auto_attack
        if not IsCurrentSpell(6603) then
            CallSecureFunction("AttackTarget")
        end
        -- actions+=/rebuke
        -- ShouldReturn = Everyone.Interrupt(5, S.Rebuke, Settings.Commons.OffGCDasOffGCD.Rebuke, Interrupts)
        -- if ShouldReturn then
        --     return ShouldReturn
        -- end
        -- actions+=/call_action_list,name=cooldowns
        ShouldReturn = Cooldowns()
        if ShouldReturn then
            return ShouldReturn
        end
        -- actions+=/call_action_list,name=generators
        ShouldReturn = Generators()
        if ShouldReturn then
            return ShouldReturn
        end

        return
    end
end

--- ======= SIMC =======
-- Last Update: 11/17/2020
-- Note: "time_to_hpg=0" as to be implemented as "time_to_hpg<=gcd.remains" since we have to display an icon during the gcd and not only when it's ready (like on SimC)
-- Note: Removed essences + used generic trinket condition instead of razor specific one.

-- # Executed before combat begins. Accepts non-harmful actions only.
-- actions.precombat=flask
-- actions.precombat+=/food
-- actions.precombat+=/augmentation
-- # Snapshot raid buffed stats before combat begins and pre-potting is done.
-- actions.precombat+=/snapshot_stats
-- actions.precombat+=/potion
-- actions.precombat+=/arcane_torrent

-- # Executed every time the actor is available.
-- actions=auto_attack
-- actions+=/rebuke
-- actions+=/call_action_list,name=cooldowns
-- actions+=/call_action_list,name=generators

-- actions.cooldowns=lights_judgment,if=spell_targets.lights_judgment>=2|(!raid_event.adds.exists|raid_event.adds.in>75)
-- actions.cooldowns+=/fireblood,if=buff.avenging_wrath.up|buff.crusade.up&buff.crusade.stack=10
-- actions.cooldowns+=/shield_of_vengeance
-- actions.cooldowns+=/use_item,name=ashvanes_razor_coral,if=debuff.razor_coral_debuff.down|(buff.avenging_wrath.remains>=20|buff.crusade.stack=10&buff.crusade.remains>15)&(cooldown.guardian_of_azeroth.remains>90|target.time_to_die<30)
-- actions.cooldowns+=/avenging_wrath,if=(holy_power>=4&time<5|holy_power>=3&time>5|talent.holy_avenger.enabled&cooldown.holy_avenger.remains=0)&time_to_hpg=0
-- actions.cooldowns+=/crusade,if=(holy_power>=4&time<5|holy_power>=3&time>5|talent.holy_avenger.enabled&cooldown.holy_avenger.remains=0)&time_to_hpg=0
-- actions.cooldowns+=/ashen_hallow
-- actions.cooldowns+=/holy_avenger,if=time_to_hpg=0&((buff.avenging_wrath.up|buff.crusade.up)|(buff.avenging_wrath.down&cooldown.avenging_wrath.remains>40|buff.crusade.down&cooldown.crusade.remains>40))
-- actions.cooldowns+=/final_reckoning,if=holy_power>=3&cooldown.avenging_wrath.remains>gcd&time_to_hpg=0&(!talent.seraphim.enabled|buff.seraphim.up)

-- actions.finishers=variable,name=ds_castable,value=spell_targets.divine_storm>=2|buff.empyrean_power.up&debuff.judgment.down&buff.divine_purpose.down|spell_targets.divine_storm>=2&buff.crusade.up&buff.crusade.stack<10
-- actions.finishers+=/seraphim,if=((!talent.crusade.enabled&buff.avenging_wrath.up|cooldown.avenging_wrath.remains>25)|(buff.crusade.up|cooldown.crusade.remains>25))&(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains<10)&(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains<10)&time_to_hpg=0
-- actions.finishers+=/vanquishers_hammer,if=(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains>gcd*10|debuff.final_reckoning.up)&(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*10|debuff.execution_sentence.up)|spell_targets.divine_storm>=2
-- actions.finishers+=/execution_sentence,if=spell_targets.divine_storm<=3&((!talent.crusade.enabled|buff.crusade.down&cooldown.crusade.remains>10)|buff.crusade.stack>=3|cooldown.avenging_wrath.remains>10|debuff.final_reckoning.up)&time_to_hpg=0
-- actions.finishers+=/divine_storm,if=variable.ds_castable&!buff.vanquishers_hammer.up&((!talent.crusade.enabled|cooldown.crusade.remains>gcd*3)&(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*3|spell_targets.divine_storm>=3)|spell_targets.divine_storm>=2&(talent.holy_avenger.enabled&cooldown.holy_avenger.remains<gcd*3|buff.crusade.up&buff.crusade.stack<10))
-- actions.finishers+=/templars_verdict,if=(!talent.crusade.enabled|cooldown.crusade.remains>gcd*3)&(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*3&spell_targets.divine_storm<=3)&(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains>gcd*3)&(!covenant.necrolord.enabled|cooldown.vanquishers_hammer.remains>gcd)|talent.holy_avenger.enabled&cooldown.holy_avenger.remains<gcd*3|buff.holy_avenger.up|buff.crusade.up&buff.crusade.stack<10|buff.vanquishers_hammer.up

-- actions.generators=call_action_list,name=finishers,if=holy_power>=5|buff.holy_avenger.up|debuff.final_reckoning.up|debuff.execution_sentence.up|buff.memory_of_lucid_dreams.up|buff.seething_rage.up
-- actions.generators+=/divine_toll,if=!debuff.judgment.up&(!raid_event.adds.exists|raid_event.adds.in>30)&(holy_power<=2|holy_power<=4&(cooldown.blade_of_justice.remains>gcd*2|debuff.execution_sentence.up|debuff.final_reckoning.up))&(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains>gcd*10)&(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*10)
-- actions.generators+=/wake_of_ashes,if=(holy_power=0|holy_power<=2&(cooldown.blade_of_justice.remains>gcd*2|debuff.execution_sentence.up|debuff.final_reckoning.up))&(!raid_event.adds.exists|raid_event.adds.in>20)&(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>15)&(!talent.final_reckoning.enabled|cooldown.final_reckoning.remains>15)
-- actions.generators+=/blade_of_justice,if=holy_power<=3
-- actions.generators+=/hammer_of_wrath,if=holy_power<=4
-- actions.generators+=/judgment,if=!debuff.judgment.up&(holy_power<=2|holy_power<=4&cooldown.blade_of_justice.remains>gcd*2)
-- actions.generators+=/call_action_list,name=finishers,if=(target.health.pct<=20|buff.avenging_wrath.up|buff.crusade.up|buff.empyrean_power.up)
-- actions.generators+=/crusader_strike,if=cooldown.crusader_strike.charges_fractional>=1.75&(holy_power<=2|holy_power<=3&cooldown.blade_of_justice.remains>gcd*2|holy_power=4&cooldown.blade_of_justice.remains>gcd*2&cooldown.judgment.remains>gcd*2)
-- actions.generators+=/call_action_list,name=finishers
-- actions.generators+=/crusader_strike,if=holy_power<=4
-- actions.generators+=/arcane_torrent,if=holy_power<=4
-- actions.generators+=/consecration,if=time_to_hpg>gcd
