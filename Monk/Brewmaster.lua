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
-- Lua
local mathmin = math.min
local pairs = pairs

--- ============================ CONTENT ============================
-- Spells
local S = Spell.Monk.Brewmaster
-- local I = Item.Monk.Brewmaster

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {}

-- Rotation Var
local Enemies5y
local Enemies8y
local EnemiesCount8
local IsInMeleeRange, IsInAoERange
local ShouldReturn  -- Used to get the return string
local Interrupts = {
    {S.SpearHandStrike, "Cast Spear Hand Strike (Interrupt)", function()
            return true
        end}
}
local Stuns = {
    {S.LegSweep, "Cast Leg Sweep (Stun)", function()
            return true
        end}
}
local Traps = {
    {S.Paralysis, "Cast Paralysis (Stun)", function()
            return true
        end}
}

-- -- GUI Settings
-- local Everyone = HR.Commons.Everyone;
-- local Monk = HR.Commons.Monk;
-- local Settings = {
--   General    = HR.GUISettings.General,
--   Commons    = HR.GUISettings.APL.Monk.Commons,
--   Brewmaster = HR.GUISettings.APL.Monk.Brewmaster
-- };

-- Legendary variables
local CelestialInfusionEquipped = Player:HasLegendaryEquipped(88)
local CharredPassionsEquipped = Player:HasLegendaryEquipped(86)
local EscapeFromRealityEquipped = Player:HasLegendaryEquipped(82)
local FatalTouchEquipped = Player:HasLegendaryEquipped(85)
local InvokersDelightEquipped = Player:HasLegendaryEquipped(83)
local ShaohaosMightEquipped = Player:HasLegendaryEquipped(89)
local StormstoutsLastKegEquipped = Player:HasLegendaryEquipped(87)
local SwiftsureWrapsEquipped = Player:HasLegendaryEquipped(84)

HL:RegisterForEvent(
    function()
        VarFoPPreChan = 0
    end,
    "PLAYER_REGEN_ENABLED"
)

-- Melee Is In Range w/ Movement Handlers
local function IsInMeleeRange(range)
    if S.TigerPalm:TimeSinceLastCast() <= Player:GCD() then
        return true
    end
    return range and Target:IsInMeleeRange(range) or Target:IsInMeleeRange(5)
end

-- local function UseItems()
--   -- use_items
--   local TrinketToUse = Player:GetUseableTrinkets(OnUseExcludes)
--   if TrinketToUse then
--     return {["spell"] = TrinketToUse, nil, Settings.Commons.TrinketDisplayStyle) then return "Generic use_items for " .. TrinketToUse:Name(); end
--   end
-- end

-- Compute healing amount available from orbs
local function HealingSphereAmount()
    return 1.5 * Player:AttackPowerDamageMod() * (1 + (Player:VersatilityDmgPct() / 100)) * S.ExpelHarm:Count()
end

local function GetStaggerTick(ThisSpell)
    local ThisSpellID = ThisSpell:ID()
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, ThisDebuffID, _, _, _, _, _, ThisStaggerTick = UnitDebuff("player", i)
        if (ThisDebuffID == ThisSpellID) then
            return ThisStaggerTick
        end
    end
end

-- I am going keep this function in place in case it is needed in the future.
-- The code is sound for a smoothing of damage intake.
-- However this is not needed in the current APL.
local function ShouldPurify()
    local NextStaggerTick = 0
    local NextStaggerTickMaxHPPct = 0
    local StaggersRatioPct = 0

    if Player:DebuffUp(S.HeavyStagger) then
        --    NextStaggerTick = select(16, Player:DebuffInfo(S.HeavyStagger, true, true))
        NextStaggerTick = GetStaggerTick(S.HeavyStagger)
    elseif Player:DebuffUp(S.ModerateStagger) then
        --    NextStaggerTick = select(16, Player:DebuffInfo(S.ModerateStagger, true, true))
        NextStaggerTick = GetStaggerTick(S.ModerateStagger)
    elseif Player:DebuffUp(S.LightStagger) then
        NextStaggerTick = GetStaggerTick(S.LightStagger)
    --    NextStaggerTick = select(16, Player:DebuffInfo(S.LightStagger, false, true))
    end

    if NextStaggerTick > 0 then
        NextStaggerTickMaxHPPct = (NextStaggerTick / Player:StaggerMax()) * 100
        StaggersRatioPct = (Player:Stagger() / Player:StaggerFull()) * 100
    end

    -- Do not purify at the start of a combat since the normalization is not stable yet
    if HL.CombatTime() <= 9 then
        return false
    end

    -- Do purify only if we are loosing more than 3% HP per second (1.5% * 2 since it ticks every 500ms), i.e. above Grey level
    if NextStaggerTickMaxHPPct > 1.5 and StaggersRatioPct > 0 then
        -- 3% is considered a Moderate Stagger
        if NextStaggerTickMaxHPPct <= 3 then -- Yellow: 6% HP per second, only if the stagger ratio is > 80%
            -- 4.5% is considered a Heavy Stagger
            return HM.Settings.Brewmaster.Purify.Low and StaggersRatioPct > 80 or false
        elseif NextStaggerTickMaxHPPct <= 4.5 then -- Orange: <= 9% HP per second, only if the stagger ratio is > 71%
            return HM.Settings.Brewmaster.Purify.Medium and StaggersRatioPct > 71 or false
        elseif NextStaggerTickMaxHPPct <= 9 then -- Red: <= 18% HP per second, only if the stagger ratio value is > 53%
            return HM.Settings.Brewmaster.Purify.High and StaggersRatioPct > 53 or false
        else -- Magenta: > 18% HP per second, ASAP
            return true
        end
    end
end

local ShuffleDuration = 5
local function Defensives()
    local IsTanking = Player:IsTankingAoE(8) or Player:IsTanking(Target)

    -- celestial_brew,if=buff.blackout_combo.down&incoming_damage_1999ms>(health.max*0.1+stagger.last_tick_damage_4)&buff.elusive_brawler.stack<2
    -- Note: Extra handling of the charge management only while tanking.
    --       "- (IsTanking and 1 + (Player:BuffRemains(S.Shuffle) <= ShuffleDuration * 0.5 and 0.5 or 0) or 0)"
    -- TODO: See if this can be optimized
    if
        S.CelestialBrew:IsCastable() and Settings.Brewmaster.ShowCelestialBrewCD and
            Player:BuffDown(S.BlackoutComboBuff) and
            (IsTanking and 1 + (Player:BuffRemains(S.Shuffle) <= ShuffleDuration * 0.5 and 0.5 or 0) or 0) and
            Player:BuffStack(S.ElusiveBrawlerBuff) < 2
     then
        return {["spell"] = S.CelestialBrew, ["multitarget"] = false}
    end
    -- purifying_brew
    if Settings.Brewmaster.Purify.Enabled and S.PurifyingBrew:IsCastable() then
        return {["spell"] = S.PurifyingBrew, ["multitarget"] = false}
    end
    -- Blackout Combo Stagger Pause w/ Celestial Brew
    if
        S.CelestialBrew:IsCastable() and Settings.Brewmaster.ShowCelestialBrewCD and Player:BuffUp(S.BlackoutComboBuff) and
            Player:HealingAbsorbed() and
            ShouldPurify()
     then
        return {["spell"] = S.CelestialBrew, ["multitarget"] = false}
    end
    -- Dampen Harm
    if S.DampenHarm:IsCastable() and Settings.Brewmaster.ShowDampenHarmCD then
        return {["spell"] = S.DampenHarm, ["multitarget"] = false}
    end
    -- Fortifying Brew
    if S.FortifyingBrew:IsCastable() then
        return {["spell"] = S.FortifyingBrew, ["multitarget"] = false}
    end
end

--- ======= ACTION LISTS =======
function HM.BrewmasterAPL()
    -- Unit Update
    IsInMeleeRange()
    Enemies5y = Player:GetEnemiesInMeleeRange(5) -- Multiple Abilities
    Enemies8y = Player:GetEnemiesInMeleeRange(8) -- Multiple Abilities
    EnemiesCount8 = #Enemies8y -- AOE Toogle

    --- Out of Combat
    if not Player:AffectingCombat() or not HM.TargetIsValid() then
        -- flask
        -- food
        -- augmentation
        -- snapshot_stats
        -- potion
        -- if I.PotionofPhantomFire:IsReady() and Settings.Commons.UsePotions then
        --     if HR.CastSuggested(I.PotionofPhantomFire) then
        --         return "Potion of Phantom Fire"
        --     end
        -- end
        -- if I.PotionofSpectralAgility:IsReady() and Settings.Commons.UsePotions then
        --     if HR.CastSuggested(I.PotionofSpectralAgility) then
        --         return "Potion of Spectral Agility"
        --     end
        -- end
        -- if I.PotionofDeathlyFixation:IsReady() and Settings.Commons.UsePotions then
        --     if HR.CastSuggested(I.PotionofDeathlyFixation) then
        --         return "Potion of Deathly Fixation"
        --     end
        -- end
        -- if I.PotionofEmpoweredExorcisms:IsReady() and Settings.Commons.UsePotions then
        --     if HR.CastSuggested(I.PotionofEmpoweredExorcisms) then
        --         return "Potion of Empowered Exorcisms"
        --     end
        -- end
        -- if I.PotionofHardenedShadows:IsReady() and Settings.Commons.UsePotions then
        --     if HR.CastSuggested(I.PotionofHardenedShadows) then
        --         return "Potion of Hardened Shadows"
        --     end
        -- end
        -- if I.PotionofSpectralStamina:IsReady() and Settings.Commons.UsePotions then
        --     if HR.CastSuggested(I.PotionofSpectralStamina) then
        --         return "Potion of Spectral Stamina"
        --     end
        -- end
        -- chi_burst
        -- if S.ChiBurst:IsCastable() and Target:IsInRange(40) then
        --     return {["spell"] = S.ChiBurst, ["multitarget"] = false}
        -- end
        -- -- chi_wave
        -- if S.ChiWave:IsCastable() and Target:IsInRange(40) then
        --     return {["spell"] = S.ChiWave, ["multitarget"] = false}
        -- end
        return
    end

    --- In Combat
    if HM.TargetIsValid() then
        -- auto_attack
        -- Interrupts
        -- local ShouldReturn =
        --     Everyone.Interrupt(5, S.SpearHandStrike, Settings.Commons.OffGCDasOffGCD.SpearHandStrike, Interrupts)
        -- if ShouldReturn then
        --     return ShouldReturn
        -- end
        -- -- Stun
        -- local ShouldReturn = Everyone.Interrupt(5, S.LegSweep, Settings.Commons.GCDasOffGCD.LegSweep, Stuns)
        -- if ShouldReturn and Settings.General.InterruptWithStun then
        --     return ShouldReturn
        -- end
        -- -- Trap
        -- local ShouldReturn = Everyone.Interrupt(5, S.Paralysis, Settings.Commons.GCDasOffGCD.Paralysis, Stuns)
        -- if ShouldReturn and Settings.General.InterruptWithStun then
        --     return ShouldReturn
        -- end
        -- Defensives
        -- ShouldReturn = Defensives()
        -- if ShouldReturn then
        --     return ShouldReturn
        -- end
        if HM.Settings.CDsON then
            -- use_item
            --   if (Settings.Commons.UseTrinkets) then
            --     if (true) then
            --       local ShouldReturn = UseItems(); if ShouldReturn then return ShouldReturn; end
            --     end
            --   end
            --   -- potion
            --   if I.PotionofPhantomFire:IsReady() and Settings.Commons.UsePotions then
            --     if HR.CastSuggested(I.PotionofPhantomFire) then return "Potion of Phantom Fire 2"; end
            --   end
            --   if I.PotionofSpectralAgility:IsReady() and Settings.Commons.UsePotions then
            --     if HR.CastSuggested(I.PotionofSpectralAgility) then return "Potion of Spectral Agility 2"; end
            --   end
            --   if I.PotionofDeathlyFixation:IsReady() and Settings.Commons.UsePotions then
            --     if HR.CastSuggested(I.PotionofDeathlyFixation) then return "Potion of Deathly Fixation 2"; end
            --   end
            --   if I.PotionofEmpoweredExorcisms:IsReady() and Settings.Commons.UsePotions then
            --     if HR.CastSuggested(I.PotionofEmpoweredExorcisms) then return "Potion of Empowered Exorcisms 2"; end
            --   end
            --   if I.PotionofHardenedShadows:IsReady() and Settings.Commons.UsePotions then
            --     if HR.CastSuggested(I.PotionofHardenedShadows) then return "Potion of Hardened Shadows 2"; end
            --   end
            --   if I.PotionofSpectralStamina:IsReady() and Settings.Commons.UsePotions then
            --     if HR.CastSuggested(I.PotionofSpectralStamina) then return "Potion of Spectral Stamina 2"; end
            --   end
            -- blood_fury
            if S.BloodFury:IsCastable() then
                return {["spell"] = S.BloodFury, ["multitarget"] = false}
            end
            -- berserking
            if S.Berserking:IsCastable() then
                return {["spell"] = S.Berserking, ["multitarget"] = false}
            end
            -- lights_judgment
            if S.LightsJudgment:IsCastable() and Target:IsInRange(40) then
                return {["spell"] = S.LightsJudgment, ["multitarget"] = false}
            end
            -- fireblood
            if S.Fireblood:IsCastable() then
                return {["spell"] = S.Fireblood, ["multitarget"] = false}
            end
            -- ancestral_call
            if S.AncestralCall:IsCastable() then
                return {["spell"] = S.AncestralCall, ["multitarget"] = false}
            end
            -- bag_of_tricks
            if S.BagOfTricks:IsCastable() and Target:IsInRange(40) then
                return {["spell"] = S.BagOfTricks, ["multitarget"] = false}
            end
            -- weapons_of_order
            if S.WeaponsOfOrder:IsCastable() and Target:IsInRange(10)  then
                return {["spell"] = S.WeaponsOfOrder, ["multitarget"] = false}
            end
            -- fallen_order
            if S.FallenOrder:IsCastable() and Target:IsInRange(10)  then
                return {["spell"] = S.FallenOrder, ["multitarget"] = false}
            end
            -- bonedust_brew
            if S.BonedustBrew:IsCastable() and Target:IsInRange(15)  then
                return {["spell"] = S.BonedustBrew, ["multitarget"] = false}
            end
            -- invoke_niuzao_the_black_ox
            if S.InvokeNiuzaoTheBlackOx:IsCastable() and HL.BossFilteredFightRemains(">", 25) and Target:IsInRange(10)  then
                return {["spell"] = S.InvokeNiuzaoTheBlackOx, ["multitarget"] = false}
            end
            -- black_ox_brew,if=cooldown.purifying_brew.charges_fractional<0.5
            if S.BlackOxBrew:IsCastable() and S.PurifyingBrew:ChargesFractional() < 0.5 then
                return {["spell"] = S.BlackOxBrew, ["multitarget"] = false}
            end
            -- black_ox_brew,if=(energy+(energy.regen*cooldown.keg_smash.remains))<40&buff.blackout_combo.down&cooldown.keg_smash.up
            if
                S.BlackOxBrew:IsCastable() and
                    (Player:Energy() + (Player:EnergyRegen() * S.KegSmash:CooldownRemains())) < 40 and
                    Player:BuffDown(S.BlackoutComboBuff) and
                    S.KegSmash:CooldownUp()
             then
                return {["spell"] = S.BlackOxBrew, ["multitarget"] = false}
            end
        end
        -- keg_smash,if=spell_targets>=2
        if S.KegSmash:IsCastable() and HM.Settings.AoEON and EnemiesCount8 >= 2 and Target:IsSpellInRange(S.KegSmash) then
            return {["spell"] = S.KegSmash, ["multitarget"] = false}
        end
        -- faeline_stomp,if=spell_targets>=2
        if S.FaelineStomp:IsCastable() and HM.Settings.AoEON and EnemiesCount8 >= 2 then
            return {["spell"] = S.FaelineStomp, ["multitarget"] = false}
        end
        -- keg_smash,if=buff.weapons_of_order.up
        if S.KegSmash:IsCastable() and Player:BuffUp(S.WeaponsOfOrder) and Target:IsSpellInRange(S.KegSmash) then
            return {["spell"] = S.KegSmash, ["multitarget"] = false}
        end
        -- tiger_palm,if=talent.rushing_jade_wind.enabled&buff.blackout_combo.up&buff.rushing_jade_wind.up
        if
            S.TigerPalm:IsCastable() and S.RushingJadeWind:IsAvailable() and Player:BuffUp(S.BlackoutComboBuff) and
                Player:BuffUp(S.RushingJadeWind) and
                Target:IsSpellInRange(S.TigerPalm)
         then
            return {["spell"] = S.TigerPalm, ["multitarget"] = false}
        end
        -- breath_of_fire,if=buff.charred_passions.down&runeforge.charred_passions.equipped
        if
            S.BreathOfFire:IsCastable(10, true) and (Player:BuffDown(S.CharredPassions) and CharredPassionsEquipped) and
                not Target:IsInMeleeRange(8)
         then
            return {["spell"] = S.BreathOfFire, ["multitarget"] = false}
        end
        -- blackout_strike
        if S.BlackoutKick:IsCastable() and Target:IsSpellInRange(S.BlackoutKick) then
            return {["spell"] = S.BlackoutKick, ["multitarget"] = false}
        end
        -- keg_smash
        if S.KegSmash:IsCastable() and Target:IsSpellInRange(S.KegSmash) then
            return {["spell"] = S.KegSmash, ["multitarget"] = false}
        end
        -- faeline_stomp
        if S.FaelineStomp:IsCastable() then
            return {["spell"] = S.FaelineStomp, ["multitarget"] = false}
        end
        -- expel_harm,if=buff.gift_of_the_ox.stack>=3
        -- Note : Extra handling to prevent Expel Harm over-healing
        if
            S.ExpelHarm:IsReady() and Player:Health() + HealingSphereAmount() < Player:MaxHealth() and
                Target:IsInMeleeRange(8)
         then
            return {["spell"] = S.ExpelHarm, ["multitarget"] = false}
        end
        if S.TouchOfDeath:IsReady() and Target:HealthPercentage() <= 15 and Target:IsSpellInRange(S.TouchOfDeath) then
            return {["spell"] = S.TouchOfDeath, ["multitarget"] = false}
        end
        -- rushing_jade_wind,if=buff.rushing_jade_wind.down
        if S.RushingJadeWind:IsCastable() and Player:BuffDown(S.RushingJadeWind) and Target:IsInMeleeRange(8) then
            return {["spell"] = S.RushingJadeWind, ["multitarget"] = false}
        end
        -- spinning_crane_kick,if=buff.charred_passions.up
        if S.SpinningCraneKick:IsCastable() and Player:BuffUp(S.CharredPassions) and Target:IsInMeleeRange(8) then
            return {["spell"] = S.SpinningCraneKick, ["multitarget"] = false}
        end
        -- breath_of_fire,if=buff.blackout_combo.down&(buff.bloodlust.down|(buff.bloodlust.up&dot.breath_of_fire_dot.refreshable))
        if
            S.BreathOfFire:IsCastable(10, true) and
                (Player:BuffDown(S.BlackoutComboBuff) and
                    (Player:BloodlustDown() or
                        (Player:BloodlustUp() and Target:BuffRefreshable(S.BreathOfFireDotDebuff)))) and
                Target:IsInMeleeRange(8)
         then
            return {["spell"] = S.BreathOfFire, ["multitarget"] = false}
        end
        -- chi_burst
        if S.ChiBurst:IsCastable() and Target:IsInRange(40) then
            return {["spell"] = S.ChiBurst, ["multitarget"] = false}
        end
        -- chi_wave
        if S.ChiWave:IsCastable() and Target:IsInRange(40) then
            return {["spell"] = S.ChiWave, ["multitarget"] = false}
        end
        -- spinning_crane_kick,if=active_enemies>=3&cooldown.keg_smash.remains>gcd&(energy+(energy.regen*(cooldown.keg_smash.remains+execute_time)))>=65&(!talent.spitfire.enabled|!runeforge.charred_passions.equipped)
        if
            S.SpinningCraneKick:IsCastable() and
                (HM.Settings.AoEON and EnemiesCount8 >= 3 and S.KegSmash:CooldownRemains() > Player:GCD() and
                    (Player:Energy() +
                        (Player:EnergyRegen() * (S.KegSmash:CooldownRemains() + S.SpinningCraneKick:ExecuteTime())) >=
                        65) and
                    (not S.Spitfire:IsAvailable() or not CharredPassionsEquipped)) and
                Target:IsInMeleeRange(8)
         then
            return {["spell"] = S.SpinningCraneKick, ["multitarget"] = false}
        end
        -- tiger_palm,if=!talent.blackout_combo.enabled&cooldown.keg_smash.remains>gcd&(energy+(energy.regen*(cooldown.keg_smash.remains+gcd)))>=65
        if
            S.TigerPalm:IsCastable() and
                (not S.BlackoutCombo:IsAvailable() and S.KegSmash:CooldownRemains() > Player:GCD() and
                    ((Player:Energy() + (Player:EnergyRegen() * (S.KegSmash:CooldownRemains() + Player:GCD()))) >= 65)) and
                Target:IsSpellInRange(S.TigerPalm)
         then
            return {["spell"] = S.TigerPalm, ["multitarget"] = false}
        end
        -- arcane_torrent,if=energy<31
        if S.ArcaneTorrent:IsCastable() and Player:Energy() < 31 and Target:IsInMeleeRange(8) then
            return {["spell"] = S.ArcaneTorrent, ["multitarget"] = false}
        end
        -- rushing_jade_wind
        if S.RushingJadeWind:IsCastable() and Target:IsInMeleeRange(8) then
            return {["spell"] = S.RushingJadeWind, ["multitarget"] = false}
        end
        -- Manually added Pool filler
        return
    end
end
