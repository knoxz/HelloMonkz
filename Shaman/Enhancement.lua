--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
-- HeroDBC
local DBC = HeroDBC.DBC
-- HeroLib
local HL = HeroLib
local Cache = HeroCache
local Unit = HL.Unit
local Player = Unit.Player
local Target = Unit.Target
local Spell = HL.Spell
local MultiSpell = HL.MultiSpell
-- local Item = HL.Item
-- Lua
local GetWeaponEnchantInfo = GetWeaponEnchantInfo

local addonName, HM = ...

HelloMonkz = HM

--- ============================ CONTENT ============================
--- ======= APL LOCALS =======

-- Define S/I for spell and item arrays
local S = Spell.Shaman.Enhancement

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {}

-- Rotation Var
local hasMainHandEnchant,
    mainHandExpiration,
    mainHandCharges,
    mainHandEnchantID,
    hasOffHandEnchant,
    offHandExpiration,
    offHandCharges,
    offHandEnchantId
local Enemies40y, MeleeEnemies10y, MeleeEnemies10yCount, MeleeEnemies5y, Enemies40yCount, EnemiesCount30ySplash
local EnemiesFlameShockCount = 0
local DoomWindsEquipped = Player:HasLegendaryEquipped(138)
local PrimalLavaActuatorsEquipped = Player:HasLegendaryEquipped(141)

HL:RegisterForEvent(
    function()
        DoomWindsEquipped = Player:HasLegendaryEquipped(138)
        PrimalLavaActuatorsEquipped = Player:HasLegendaryEquipped(141)
    end,
    "PLAYER_EQUIPMENT_CHANGED"
)

local function num(val)
    if val then
        return 1
    else
        return 0
    end
end

local function bool(val)
    return val ~= 0
end

local function totemFinder()
    for i = 1, 6, 1 do
        if string.match(Player:TotemName(i), "Totem") then
            return i
        end
    end
end

-- Counter for Debuff on other enemies
local function calcEnemiesFlameShockCount(Object, Enemies)
    local debuffs = 0
    if HM.Settings.AoEON then
        for _, CycleUnit in pairs(Enemies) do
            if CycleUnit:DebuffUp(Object) then
                debuffs = debuffs + 1
                EnemiesFlameShockCount = debuffs
            end
        end
    end
end

local function EvaluateCycleFlameShock(TargetUnit)
    return (TargetUnit:DebuffRefreshable(S.FlameShockDebuff))
end

local function EvaluateCycleLavaLash(TargetUnit)
    return (TargetUnit:DebuffRefreshable(S.LashingFlamesDebuff))
end

local function Precombat()
    -- flask
    -- food
    -- augmentation
    -- windfury_weapon
    if not hasMainHandEnchant and S.WindfuryWeapon:IsCastable() then
        return {["spell"] = S.WindfuryWeapon, ["multitarget"] = false}
    end
    -- flametongue_weapon
    if not hasOffHandEnchant and S.FlamentongueWeapon:IsCastable() then
        return {["spell"] = S.FlamentongueWeapon, ["multitarget"] = false}
    end
    -- lightning_shield
    if S.LightningShield:IsCastable() and Player:BuffDown(S.LightningShieldBuff) then
        return {["spell"] = S.LightningShield, ["multitarget"] = false}
    end
    --   -- stormkeeper,if=talent.stormkeeper.enabled
    --   if S.Stormkeeper:IsCastable() then
    --     return {["spell"] = S.Stormkeeper
    --   end
    --   -- windfury_totem
    --   if S.WindfuryTotem:IsCastable() and Player:BuffDown(S.WindfuryTotemBuff) then
    --     return {["spell"] = S.WindfuryTotem
    --   end
    --   -- potion
    --   -- snapshot_stats
    --   -- Manually added: flame_shock
    --   if S.FlameShock:IsCastable() and Target:DebuffDown(S.FlameShockDebuff) and Target:IsSpellInRange(S.FlameShock) then
    --     return {["spell"] = S.FlameShock
    --   end
end

local function Single()
    -- primordial_wave,if=!buff.primordial_wave.up
    if
        S.PrimordialWave:IsReady() and
            (Player:BuffDown(S.PrimordialWaveBuff) and Target:IsSpellInRange(S.PrimordialWave))
     then
        return {["spell"] = S.PrimordialWave, ["multitarget"] = false}
    end
    -- windfury_totem,if=runeforge.doom_winds.equipped&buff.doom_winds_debuff.down
    if S.WindfuryTotem:IsReady() and (DoomWindsEquipped and Player:BuffDown(S.DoomWindsBuff)) then
        return {["spell"] = S.WindfuryTotem, ["multitarget"] = false}
    end
    -- flame_shock,if=!ticking
    if S.FlameShock:IsCastable() and (Target:DebuffDown(S.FlameShockDebuff) and Target:IsSpellInRange(S.FlameShock)) then
        return {["spell"] = S.FlameShock, ["multitarget"] = false}
    end
    -- vesper_totem
    if S.VesperTotem:IsReady() and Target:IsInRange(20) then
        return {["spell"] = S.VesperTotem, ["multitarget"] = false}
    end
    -- frost_shock,if=buff.hailstorm.up
    if S.FrostShock:IsCastable() and (Player:BuffUp(S.HailstormBuff) and Target:IsSpellInRange(S.FrostShock)) then
        return {["spell"] = S.FrostShock, ["multitarget"] = false}
    end
    -- earthen_spike
    if S.EarthenSpike:IsCastable() and Target:IsSpellInRange(S.EarthenSpike) then
        return {["spell"] = S.EarthenSpike, ["multitarget"] = false}
    end
    -- fae_transfusion
    if S.FaeTransfusion:IsReady() and Target:IsInRange(20) then
        return {["spell"] = S.FaeTransfusion, ["multitarget"] = false}
    end
    -- lightning_bolt,if=buff.stormkeeper.up
    if S.LightningBolt:IsCastable() and (Player:BuffUp(S.StormkeeperBuff)) and Target:IsSpellInRange(S.LightningBolt) then
        return {["spell"] = S.LightningBolt, ["multitarget"] = false}
    end
    -- elemental_blast,if=buff.maelstrom_weapon.stack>=5
    if
        S.ElementalBlast:IsCastable() and (Player:BuffStack(S.MaelstromWeaponBuff) >= 5) and
            Target:IsSpellInRange(S.ElementalBlast)
     then
        return {["spell"] = S.ElementalBlast, ["multitarget"] = false}
    end
    -- chain_harvest,if=buff.maelstrom_weapon.stack>=5
    if
        S.ChainHarvest:IsReady() and (Player:BuffStack(S.MaelstromWeaponBuff) >= 5) and
            Target:IsSpellInRange(S.ChainHarvest)
     then
        return {["spell"] = S.ChainHarvest, ["multitarget"] = false}
    end
    -- lightning_bolt,if=buff.maelstrom_weapon.stack=10
    if
        S.LightningBolt:IsCastable() and (Player:BuffStack(S.MaelstromWeaponBuff) == 10) and
            Target:IsSpellInRange(S.LightningBolt)
     then
        return {["spell"] = S.LightningBolt, ["multitarget"] = false}
    end
    -- lava_lash,if=buff.hot_hand.up|(runeforge.primal_lava_actuators.equipped&buff.primal_lava_actuators.stack>6)
    if
        S.LavaLash:IsCastable() and
            (Player:BuffUp(S.HotHandBuff) or
                (PrimalLavaActuatorsEquipped and Player:BuffStack(S.PrimalLavaActuatorsBuff) > 6)) and
            Target:IsSpellInRange(S.LavaLash)
     then
        return {["spell"] = S.LavaLash, ["multitarget"] = false}
    end
    -- stormstrike
    if S.Stormstrike:IsCastable() and Target:IsSpellInRange(S.Stormstrike) then
        return {["spell"] = S.Stormstrike, ["multitarget"] = false}
    end
    -- stormkeeper,if=buff.maelstrom_weapon.stack>=5
    if S.Stormkeeper:IsCastable() and (Player:BuffStack(S.MaelstromWeaponBuff) >= 5) then
        return {["spell"] = S.Stormkeeper, ["multitarget"] = false}
    end
    -- lava_lash
    if S.LavaLash:IsCastable() and Target:IsSpellInRange(S.LavaLash) then
        return {["spell"] = S.LavaLash, ["multitarget"] = false}
    end
    -- crash_lightning
    if S.CrashLightning:IsCastable() and Target:IsInMeleeRange(8) then
        return {["spell"] = S.CrashLightning, ["multitarget"] = false}
    end
    -- flame_shock,target_if=refreshable
    if
        S.FlameShock:IsCastable() and (Target:DebuffRefreshable(S.FlameShockDebuff)) and
            Target:IsSpellInRange(S.FlameShock)
     then
        return {["spell"] = S.FlameShock, ["multitarget"] = false}
    end
    -- frost_shock
    if S.FrostShock:IsCastable() and Target:IsSpellInRange(S.FrostShock) then
        return {["spell"] = S.FrostShock, ["multitarget"] = false}
    end
    -- ice_strike
    if S.IceStrike:IsCastable() then
        return {["spell"] = S.IceStrike, ["multitarget"] = false}
    end
    -- sundering
    if S.Sundering:IsCastable() then
        return {["spell"] = S.Sundering, ["multitarget"] = false}
    end
    -- fire_nova,if=active_dot.flame_shock
    if S.FireNova:IsCastable() and (Target:DebuffUp(S.FlameShockDebuff)) then
        return {["spell"] = S.FireNova, ["multitarget"] = false}
    end
    -- lightning_bolt,if=buff.maelstrom_weapon.stack>=5
    if
        S.LightningBolt:IsCastable() and (Player:BuffStack(S.MaelstromWeaponBuff) >= 5) and
            Target:IsSpellInRange(S.LightningBolt)
     then
        return {["spell"] = S.LightningBolt, ["multitarget"] = false}
    end
    -- earth_elemental
    -- if S.EarthElemental:IsCastable() then
    --     return {["spell"] = S.EarthElemental
    -- end
    -- windfury_totem,if=buff.windfury_totem.remains<30
    if
        S.WindfuryTotem:IsCastable() and
            (Player:BuffDown(S.WindfuryTotemBuff) or Player:TotemRemains(totemFinder()) < 30)
     then
        return {["spell"] = S.WindfuryTotem, ["multitarget"] = false}
    end
end

local function Aoe()
    --actions.aoe=frost_shock,if=buff.hailstorm.up
    if S.FrostShock:IsCastable() and (Player:BuffUp(S.HailstormBuff)) and Target:IsSpellInRange(S.FrostShock) then
        return {["spell"] = S.FrostShock, ["multitarget"] = false}
    end
    -- windfury_totem,if=runeforge.doom_winds.equipped&buff.doom_winds_debuff.down
    if S.WindfuryTotem:IsReady() and (DoomWindsEquipped and Player:BuffDown(S.DoomWindsBuff)) then
        return {["spell"] = S.WindfuryTotem, ["multitarget"] = false}
    end
    -- flame_shock,target_if=refreshable,cycle_targets=1,if=talent.fire_nova.enabled|talent.lashing_flames.enabled|covenant.necrolord
    if
        S.FlameShock:IsCastable() and
            (S.FireNova:IsAvailable() or S.LashingFlames:IsAvailable() or Player:Covenant() == "Necrolord")
     then
        local spell, array =
            HM.CastCycle(S.FlameShock, Enemies40y, EvaluateCycleFlameShock, Target:IsSpellInRange(S.FlameShock))
        if spell then
            return array
        end
    end
    -- primordial_wave,target_if=min:dot.flame_shock.remains,cycle_targets=1,if=!buff.primordial_wave.up
    if S.PrimordialWave:IsReady() and (Player:BuffDown(S.PrimordialWaveBuff)) then
        local spell, array =
            HM.CastCycle(
            S.PrimordialWave,
            MeleeEnemies10y,
            EvaluateCycleFlameShock,
            Target:IsSpellInRange(S.PrimordialWave)
        )
        if spell then
            return array
        end
    end
    -- fire_nova,if=active_dot.flame_shock>=3
    if S.FireNova:IsCastable() and (EnemiesFlameShockCount >= 3) then
        return {["spell"] = S.FireNova, ["multitarget"] = false}
    end
    -- vesper_totem
    if S.VesperTotem:IsReady() and Target:IsInRange(20) then
        return {["spell"] = S.VesperTotem, ["multitarget"] = false}
    end
    -- lightning_bolt,if=buff.primordial_wave.up&(buff.stormkeeper.up|buff.maelstrom_weapon.stack>=5)
    if
        S.LightningBolt:IsReady() and
            (Player:BuffUp(S.PrimordialWaveBuff) and
                (Player:BuffUp(S.StormkeeperBuff) or Player:BuffStack(S.MaelstromWeaponBuff) >= 5)) and
            Target:IsSpellInRange(S.LightningBolt)
     then
        return {["spell"] = S.LightningBolt, ["multitarget"] = false}
    end
    -- crash_lightning,if=talent.crashing_storm.enabled|buff.crash_lightning.down
    if
        S.CrashLightning:IsCastable() and Target:IsInMeleeRange(8) and
            (S.CrashingStorm:IsAvailable() or Player:BuffDown(S.CrashLightningBuff))
     then
        return {["spell"] = S.CrashLightning, ["multitarget"] = false}
    end
    -- lava_lash,target_if=min:debuff.lashing_flames.remains,cycle_targets=1,if=talent.lashing_flames.enabled
    if S.LavaLash:IsReady() and (S.LashingFlames:IsAvailable()) then
        local spell, array =
            HM.CastCycle(S.LavaLash, MeleeEnemies10y, EvaluateCycleLavaLash, not Target:IsSpellInRange(S.LavaLash))
        if spell then
            return array
        end
    end
    -- crash_lightning
    if S.CrashLightning:IsCastable() and Target:IsInMeleeRange(8) then
        return {["spell"] = S.CrashLightning, ["multitarget"] = false}
    end
    -- chain_lightning,if=buff.stormkeeper.up
    if S.ChainLightning:IsCastable() and (Player:BuffUp(S.StormkeeperBuff)) and Target:IsSpellInRange(S.ChainLightning) then
        return {["spell"] = S.ChainLightning, ["multitarget"] = false}
    end
    -- chain_harvest,if=buff.maelstrom_weapon.stack>=5
    if
        S.ChainHarvest:IsReady() and (Player:BuffStack(S.MaelstromWeaponBuff) >= 5) and
            Target:IsSpellInRange(S.ChainHarvest)
     then
        return {["spell"] = S.ChainHarvest, ["multitarget"] = false}
    end
    -- elemental_blast,if=buff.maelstrom_weapon.stack>=5
    if
        S.ElementalBlast:IsCastable() and (Player:BuffStack(S.MaelstromWeaponBuff) >= 5) and
            Target:IsSpellInRange(S.ElementalBlast)
     then
        return {["spell"] = S.ElementalBlast, ["multitarget"] = false}
    end
    -- stormkeeper,if=buff.maelstrom_weapon.stack>=5
    if S.Stormkeeper:IsCastable() and (Player:BuffStack(S.MaelstromWeaponBuff) >= 5) then
        return {["spell"] = S.Stormkeeper, ["multitarget"] = false}
    end
    -- chain_lightning,if=buff.maelstrom_weapon.stack=10
    if
        S.ChainLightning:IsCastable() and (Player:BuffStack(S.MaelstromWeaponBuff) == 10) and
            Target:IsSpellInRange(S.ChainLightning)
     then
        return {["spell"] = S.ChainLightning, ["multitarget"] = false}
    end
    -- flame_shock,target_if=refreshable,cycle_targets=1,if=talent.fire_nova.enabled
    if S.FlameShock:IsReady() and (S.FireNova:IsAvailable()) then
        local spell, array =
            HM.CastCycle(
            S.FlameShock,
            MeleeEnemies10y,
            EvaluateCycleFlameShock,
            not Target:IsSpellInRange(S.FlameShock)
        )
        if spell then
            return array
        end
    end
    -- sundering
    if S.Sundering:IsCastable() and Target:IsInMeleeRange(11) then
        return {["spell"] = S.Sundering, ["multitarget"] = false}
    end
    -- lava_lash,target_if=min:debuff.lashing_flames.remains,cycle_targets=1,if=runeforge.primal_lava_actuators.equipped&buff.primal_lava_actuators.stack>6
    if S.LavaLash:IsReady() and (PrimalLavaActuatorsEquipped and Player:BuffStack(S.PrimalLavaActuatorsBuff) > 6) then
        local spell, array =
            HM.CastCycle(S.LavaLash, MeleeEnemies10y, EvaluateCycleLavaLash, not Target:IsSpellInRange(S.LavaLash))
        if spell then
            return array
        end
    end
    -- stormstrike
    if S.Stormstrike:IsCastable() and Target:IsSpellInRange(S.Stormstrike) then
        return {["spell"] = S.Stormstrike, ["multitarget"] = false}
    end
    -- lava_lash
    if S.LavaLash:IsCastable() and Target:IsSpellInRange(S.LavaLash) then
        return {["spell"] = S.LavaLash, ["multitarget"] = false}
    end
    -- flame_shock,target_if=refreshable,cycle_targets=1
    if S.FlameShock:IsCastable() then
        local spell, array =
            HM.CastCycle(S.FlameShock, Enemies40y, EvaluateCycleFlameShock, not Target:IsSpellInRange(S.FlameShock))
        if spell then
            return array
        end
    end
    -- fae_transfusion
    if S.FaeTransfusion:IsReady() and Target:IsInRange(40) then
        return {["spell"] = S.FaeTransfusion, ["multitarget"] = false}
    end
    -- frost_shock
    if S.FrostShock:IsCastable() and Target:IsSpellInRange(S.FrostShock) then
        return {["spell"] = S.FrostShock, ["multitarget"] = false}
    end
    -- ice_strike
    if S.IceStrike:IsCastable() then
        return {["spell"] = S.IceStrike, ["multitarget"] = false}
    end
    -- chain_lightning,if=buff.maelstrom_weapon.stack>=5
    if
        S.ChainLightning:IsCastable() and (Player:BuffStack(S.MaelstromWeaponBuff) >= 5) and
            Target:IsSpellInRange(S.ChainLightning)
     then
        return {["spell"] = S.ChainLightning, ["multitarget"] = false}
    end
    -- fire_nova,if=active_dot.flame_shock>1
    if S.FireNova:IsCastable() and (EnemiesFlameShockCount > 1) then
        return {["spell"] = S.FireNova, ["multitarget"] = false}
    end
    -- earthen_spike
    if S.EarthenSpike:IsCastable() and Target:IsSpellInRange(S.EarthenSpike) then
        return {["spell"] = S.EarthenSpike, ["multitarget"] = false}
    end
    -- earth_elemental
    -- if S.EarthElemental:IsCastable() then
    --     return {["spell"] = S.EarthElemental
    -- end
    -- windfury_totem,if=buff.windfury_totem.remains<30
    if
        S.WindfuryTotem:IsCastable() and
            (Player:BuffDown(S.WindfuryTotemBuff) or Player:TotemRemains(totemFinder()) < 30)
     then
        return {["spell"] = S.WindfuryTotem, ["multitarget"] = false}
    end
end

--- ======= MAIN =======
function HM.EnhancementAPL()
    -- Local Update
    totemFinder()
    hasMainHandEnchant,
        mainHandExpiration,
        mainHandCharges,
        mainHandEnchantID,
        hasOffHandEnchant,
        offHandExpiration,
        offHandCharges,
        offHandEnchantId = GetWeaponEnchantInfo()
    -- Unit Update
    if not Player:AffectingCombat() then
        local ShouldReturn = Precombat()
        if ShouldReturn then
            return ShouldReturn
        end
    else
        if not IsCurrentSpell(6603) then
            CallSecureFunction("AttackTarget")
        end

        -- If nothing else to do, show the Pool icon
        -- if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Wait/Pool Resources"; end
        EnemiesCount30ySplash = Target:GetEnemiesInSplashRangeCount(30)
        MeleeEnemies10y = Player:GetEnemiesInMeleeRange(10)
        MeleeEnemies10yCount = #MeleeEnemies10y
        if HM.Settings.AoEON then
            Enemies40y = Player:GetEnemiesInRange(40)
            Enemies40yCount = #Enemies40y
            calcEnemiesFlameShockCount(S.FlameShock, Enemies40y)
        else
            Enemies40yCount = 1
            EnemiesFlameShockCount = 1
        end

        if HM.TargetIsValid() then
            -- actions=bloodlust
            -- potion,if=expected_combat_length-time<60
            -- wind_shear
            -- local ShouldReturn = Everyone.Interrupt(30, S.WindShear, Settings.Commons.OffGCDasOffGCD.WindShear, false); if ShouldReturn then return ShouldReturn; end
            -- auto_attack
            -- windstrike
            if S.Windstrike:IsCastable() and Target:IsSpellInRange(S.Windstrike) then
                return {["spell"] = S.Windstrike, ["multitarget"] = false}
            end
            -- use_items
            -- local TrinketToUse = Player:GetUseableTrinkets(OnUseExcludes)
            -- if TrinketToUse then
            --   return TrinketToUse, nil, Settings.Commons.TrinketDisplayStyle) then return "Generic use_items for " .. TrinketToUse:Name(); end
            -- end

            if (HM.Settings.CDsON) then
                -- blood_fury,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
                if
                    S.BloodFury:IsCastable() and
                        (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff) or
                            S.Ascendance:CooldownRemains() > 50)
                 then
                    return {["spell"] = S.BloodFury, ["multitarget"] = false}
                end
                -- berserking,if=!talent.ascendance.enabled|buff.ascendance.up
                if S.Berserking:IsCastable() and (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff)) then
                    return {["spell"] = S.Berserking, ["multitarget"] = false}
                end
                -- ancestral_call,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
                if
                    S.AncestralCall:IsCastable() and
                        (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff) or
                            S.Ascendance:CooldownRemains() > 50)
                 then
                    return {["spell"] = S.AncestralCall, ["multitarget"] = false}
                end
                -- fireblood,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
                if
                    S.Fireblood:IsCastable() and
                        (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff) or
                            S.Ascendance:CooldownRemains() > 50)
                 then
                    return {["spell"] = S.Fireblood, ["multitarget"] = false}
                end
                -- bag_of_tricks,if=!talent.ascendance.enabled|!buff.ascendance.up
                if
                    S.BagofTricks:IsCastable() and
                        (not S.Ascendance:IsAvailable() or
                            not Player:BuffUp(S.AscendanceBuff) and Target:IsSpellInRange(S.BagofTricks))
                 then
                    return {["spell"] = S.BagofTricks, ["multitarget"] = false}
                end
                -- feral_spirit
                if S.FeralSpirit:IsCastable() then
                    return {["spell"] = S.FeralSpirit, ["multitarget"] = false}
                end
                -- ascendance
                if S.Ascendance:IsCastable() then
                    return {["spell"] = S.Ascendance, ["multitarget"] = false}
                end
            end
            -- call_action_list,name=single,if=active_enemies=1
            if Enemies40yCount == 1 then
                local ShouldReturn = Single()
                if ShouldReturn then
                    return ShouldReturn
                end
            end
            -- call_action_list,name=aoe,if=active_enemies>1
            if Enemies40yCount > 1 then
                local ShouldReturn = Aoe()
                if ShouldReturn then
                    return ShouldReturn
                end
            end
        end
    end
end
