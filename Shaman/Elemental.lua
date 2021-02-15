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

local addonName, HM = ...

HelloMonkz = HM

--- ============================ CONTENT ============================
--- ======= APL LOCALS =======

-- Define S/I for spell and item arrays
local S = Spell.Shaman.Elemental

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {}

-- Rotation Var
local Enemies40y, Enemies40yCount, EnemiesCount10ySplash
local SEActive, FEActive
local EnemiesFlameShockCount = 0
local DeeptremorStoneEquipped = Player:HasLegendaryEquipped(131)
local ElementalEquilibriumEquipped = Player:HasLegendaryEquipped(135)
local EchoesofGreatSunderingEquipped = Player:HasLegendaryEquipped(136)

HL:RegisterForEvent(
  function()
    DeeptremorStoneEquipped = Player:HasLegendaryEquipped(131)
    ElementalEquilibriumEquipped = Player:HasLegendaryEquipped(135)
    EchoesofGreatSunderingEquipped = Player:HasLegendaryEquipped(136)
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

local function EvaluateCycleLavaBurst200(TargetUnit)
  return (TargetUnit:DebuffUp(S.FlameShockDebuff))
end

local function EvaluateCycleFlameShock202(TargetUnit)
  return (TargetUnit:DebuffRemains(S.FlameShockDebuff) <= Player:GCD() and
    (Player:BuffUp(S.LavaSurgeBuff) or Player:BloodlustDown()))
end

local function EvaluateCycleFlameShock204(TargetUnit)
  return ((TargetUnit:DebuffRemains(S.FlameShockDebuff) <= Player:GCD() or
    S.Ascendance:IsAvailable() and
      Target:DebuffRemains(S.FlameShockDebuff) < (S.Ascendance:CooldownRemains() + S.Ascendance:BaseDuration()) and
      S.Ascendance:CooldownRemains() < 4) and
    (Player:BuffUp(S.LavaSurgeBuff) or Player:BloodlustDown()))
end

local function Precombat()
  -- flask
  -- food
  -- augmentation
  -- lightning_shield
  if S.LightningShield:IsCastable() and Player:BuffDown(S.LightningShield) then
    return {["spell"] = S.LightningShield, ["multitarget"] = false}
  end
  -- potion
  -- snapshot_stats
  -- Manually added: flame_shock
  -- if S.FlameShock:IsReady() and Target:DebuffDown(S.FlameShockDebuff) then
  --   return {["spell"] = S.FlameShock, nil, nil, not Target:IsSpellInRange(S.FlameShock)) then
  --     return "FlameShock precombat"
  --   end
  -- end
end

local function Aoe()
  -- earthquake,if=buff.echoing_shock.up
  if S.Earthquake:IsReady() and (Player:BuffUp(S.EchoingShockBuff)) then
    return {["spell"] = S.Earthquake, ["multitarget"] = false}
  end
  -- chain_harvest
  if S.ChainHarvest:IsReady() and Target:IsSpellInRange(S.ChainHarvest) then
    return {["spell"] = S.ChainHarvest, ["multitarget"] = false}
  end
  -- stormkeeper,if=talent.stormkeeper.enabled
  if S.Stormkeeper:IsCastable() and not Player:IsCasting(S.Stormkeeper) then
    return {["spell"] = S.Stormkeeper, ["multitarget"] = false}
  end
  -- flame_shock,if=active_dot.flame_shock<3&active_enemies<=5,target_if=refreshable
  if S.FlameShock:IsReady() and (EnemiesFlameShockCount < 3 and EnemiesCount10ySplash <= 5) then
    local spell, array =
      HM.CastCycle(S.FlameShock, Enemies40y, EvaluateCycleFlameShock, not Target:IsSpellInRange(S.FlameShock))
    if spell then
      return array
    end
  end
  -- flame_shock,if=!active_dot.flame_shock
  if S.FlameShock:IsReady() and (Target:DebuffDown(S.FlameShockDebuff)) and Target:IsSpellInRange(S.FlameShock) then
    return {["spell"] = S.FlameShock, ["multitarget"] = false}
  end
  -- echoing_shock,if=talent.echoing_shock.enabled&maelstrom>=60
  if S.EchoingShock:IsReady() and (Player:Maelstrom() >= 60) then
    return {["spell"] = S.EchoingShock, ["multitarget"] = false}
  end
  -- ascendance,if=talent.ascendance.enabled&(!pet.storm_elemental.active)&(!talent.icefury.enabled|!buff.icefury.up&!cooldown.icefury.up)
  if
    S.Ascendance:IsCastable() and
      ((not SEActive) and
        (not S.Icefury:IsAvailable() or not Player:BuffUp(S.IcefuryBuff) and not S.Icefury:CooldownUp()))
   then
    return {["spell"] = S.Ascendance, ["multitarget"] = false}
  end
  -- liquid_magma_totem,if=talent.liquid_magma_totem.enabled
  if S.LiquidMagmaTotem:IsReady() then
    return {["spell"] = S.LiquidMagmaTotem, ["multitarget"] = false}
  end
  -- earth_shock,if=runeforge.echoes_of_great_sundering.equipped&!buff.echoes_of_great_sundering.up
  if
    S.EarthShock:IsReady() and (EchoesofGreatSunderingEquipped and Player:BuffDown(S.EchoesofGreatSunderingBuff)) and
      Target:IsSpellInRange(S.EarthShock)
   then
    return {["spell"] = S.EarthShock, ["multitarget"] = false}
  end
  -- earth_elemental,if=runeforge.deeptremor_stone.equipped&(!talent.primal_elementalist.enabled|(!pet.storm_elemental.active&!pet.fire_elemental.active))
  -- if
  --   S.EarthElemental:IsCastable() and
  --     (DeeptremorStoneEquipped and (not S.PrimalElementalist:IsAvailable() or (not SEActive and not FEActive)))
  --  then
  --   return {["spell"] = S.EarthElemental) then
  --     return "earth_elemental aoe 20"
  --   end
  -- end
  -- lavaburst,target_if=dot.flame_shock.remains,if=spell_targets.chain_lightning<4|buff.lava_surge.up|(talent.master_of_the_elements.enabled&!buff.master_of_the_elements.up&maelstrom>=60)
  if
    S.LavaBurst:IsReady() and
      (EnemiesCount10ySplash < 4 or Player:BuffUp(S.LavaSurgeBuff) or
        (S.MasterOfTheElements:IsAvailable() and Player:BuffDown(S.MasterOfTheElementsBuff) and Player:Maelstrom() >= 60))
   then
    local spell, array =
      HM.CastCycle(S.FlameShock, Enemies40y, EvaluateCycleLavaBurst200, not Target:IsSpellInRange(S.FlameShock))
    if spell then
      return array
    end
  end
  -- earthquake,if=!talent.master_of_the_elements.enabled|buff.stormkeeper.up|maelstrom>=(100-4*spell_targets.chain_lightning)|buff.master_of_the_elements.up|spell_targets.chain_lightning>3
  if
    S.Earthquake:IsReady() and
      (not S.MasterOfTheElements:IsAvailable() or Player:BuffUp(S.StormkeeperBuff) or
        Player:Maelstrom() >= (100 - 4 * EnemiesCount10ySplash) or
        Player:BuffUp(S.MasterOfTheElementsBuff) or
        EnemiesCount10ySplash > 3)
   then
    return {["spell"] = S.Earthquake, ["multitarget"] = false}
  end
  -- chain_lightning,if=buff.stormkeeper.remains<3*gcd*buff.stormkeeper.stack
  if
    S.ChainLightning:IsReady() and
      (Player:BuffRemains(S.StormkeeperBuff) < 3 * Player:GCD() * Player:BuffStack(S.StormkeeperBuff)) and
      Target:IsSpellInRange(S.ChainLightning)
   then
    return {["spell"] = S.ChainLightning, ["multitarget"] = false}
  end
  -- lava_burst,if=buff.lava_surge.up&spell_targets.chain_lightning<4&(!pet.storm_elemental.active)&dot.flame_shock.ticking
  if
    S.LavaBurst:IsReady() and
      (Player:BuffUp(S.LavaSurgeBuff) and EnemiesCount10ySplash < 4 and (not SEActive) and
        Target:DebuffUp(S.FlameShockDebuff)) and
      Target:IsSpellInRange(S.LavaBurst)
   then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- elemental_blast,if=talent.elemental_blast.enabled&spell_targets.chain_lightning<5&(!pet.storm_elemental.active)
  if
    S.ElementalBlast:IsReady() and (EnemiesCount10ySplash < 5 and (not SEActive)) and
      Target:IsSpellInRange(S.ElementalBlast)
   then
    return {["spell"] = S.ElementalBlast, ["multitarget"] = false}
  end
  -- lava_beam,if=talent.ascendance.enabled
  if S.LavaBeam:IsReady() and Target:IsSpellInRange(S.LavaBeam) then
    return {["spell"] = S.LavaBeam, ["multitarget"] = false}
  end
  -- chain_lightning
  if S.ChainLightning:IsReady() and Target:IsSpellInRange(S.ChainLightning) then
    return {["spell"] = S.ChainLightning, ["multitarget"] = false}
  end
  -- lava_burst,moving=1,if=buff.lava_surge.up&cooldown_react
  if
    S.LavaBurst:IsReady() and Player:IsMoving() and (Player:BuffUp(S.LavaSurgeBuff)) and
      Target:IsSpellInRange(S.LavaBurst)
   then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- flame_shock,moving=1,target_if=refreshable
  if
    S.FlameShock:IsReady() and Player:IsMoving() and Target:DebuffRefreshable(S.FlameShockDebuff) and
      Target:IsSpellInRange(S.FlameShock)
   then
    return {["spell"] = S.FlameShock, ["multitarget"] = false}
  end
  -- frost_shock,moving=1
  if S.FrostShock:IsReady() and Player:IsMoving() and Target:IsSpellInRange(S.FrostShock) then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
end

local function SESingle()
  -- flame_shock,target_if=(remains<=gcd)&(buff.lava_surge.up|!buff.bloodlust.up)
  if S.FlameShock:IsReady() then
    local spell, array =
      HM.CastCycle(S.FlameShock, Enemies40y, EvaluateCycleFlameShock202, not Target:IsSpellInRange(S.FlameShock))
    if spell then
      return array
    end
  end
  -- ascendance,if=talent.ascendance.enabled&(time>=60|buff.bloodlust.up)&(cooldown.lava_burst.remains>0)&(!talent.icefury.enabled|!buff.icefury.up&!cooldown.icefury.up)
  if
    S.Ascendance:IsCastable() and
      ((HL.CombatTime() >= 60 or Player:BloodlustUp()) and S.LavaBurst:CooldownRemains() > 0 and
        (not S.Icefury:IsAvailable() or Player:BuffDown(S.IcefuryBuff) and not S.Icefury:CooldownUp()))
   then
    return {["spell"] = S.Ascendance, ["multitarget"] = false}
  end
  -- elemental_blast,if=talent.elemental_blast.enabled
  if S.ElementalBlast:IsReady() and Target:IsSpellInRange(S.ElementalBlast) then
    return {["spell"] = S.ElementalBlast, ["multitarget"] = false}
  end
  -- stormkeeper,if=talent.stormkeeper.enabled&(maelstrom<44)
  if S.Stormkeeper:IsCastable() and (Player:Maelstrom() < 44) then
    return {["spell"] = S.Stormkeeper, ["multitarget"] = false}
  end
  -- echoing_shock,if=talent.echoing_shock.enabled
  if S.EchoingShock:IsReady() and Target:IsSpellInRange(S.EchoingShock) then
    return {["spell"] = S.EchoingShock, ["multitarget"] = false}
  end
  -- lava_burst,if=buff.wind_gust.stack<18|buff.lava_surge.up
  if
    S.LavaBurst:IsReady() and (Player:BuffStack(S.WindGustBuff) < 18 or Player:BuffUp(S.LavaSurgeBuff)) and
      Target:IsSpellInRange(S.LavaBurst)
   then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- lightning_bolt,if=buff.stormkeeper.up
  if S.LightningBolt:IsReady() and (Player:BuffUp(S.StormkeeperBuff)) and Target:IsSpellInRange(S.LightningBolt) then
    return {["spell"] = S.LightningBolt, ["multitarget"] = false}
  end
  -- earthquake,if=buff.echoes_of_great_sundering.up
  if S.Earthquake:IsReady() and (Player:BuffUp(S.EchoesofGreatSunderingBuff)) then
    return {["spell"] = S.Earthquake, ["multitarget"] = false}
  end
  -- earthquake,if=(spell_targets.chain_lightning>1)&(!dot.flame_shock.refreshable)
  if S.Earthquake:IsReady() and (EnemiesCount10ySplash > 1 and not Target:DebuffRefreshable(S.FlameShockDebuff)) then
    return {["spell"] = S.Earthquake, ["multitarget"] = false}
  end
  -- earth_shock,if=spell_targets.chain_lightning<2&maelstrom>=60&(buff.wind_gust.stack<20|maelstrom>90)
  if
    S.EarthShock:IsReady() and
      (EnemiesCount10ySplash < 2 and Player:Maelstrom() >= 60 and
        (Player:BuffStack(S.WindGustBuff) < 20 or Player:Maelstrom() > 90)) and
      Target:IsSpellInRange(S.EarthShock)
   then
    return {["spell"] = S.EarthShock, ["multitarget"] = false}
  end
  -- lightning_bolt,if=(buff.stormkeeper.remains<1.1*gcd*buff.stormkeeper.stack|buff.stormkeeper.up&buff.master_of_the_elements.up)
  if
    S.LightningBolt:IsReady() and
      (Player:BuffRemains(S.StormkeeperBuff) < 1.1 * Player:GCD() * Player:BuffStack(S.StormkeeperBuff) or
        Player:BuffUp(S.StormkeeperBuff) and Player:BuffUp(S.MasterOfTheElementsBuff)) and
      Target:IsSpellInRange(S.LightningBolt)
   then
    return {["spell"] = S.LightningBolt, ["multitarget"] = false}
  end
  -- frost_shock,if=talent.icefury.enabled&talent.master_of_the_elements.enabled&buff.icefury.up&buff.master_of_the_elements.up
  if
    S.FrostShock:IsReady() and
      (S.Icefury:IsAvailable() and S.MasterOfTheElements:IsAvailable() and Player:BuffUp(S.IcefuryBuff) and
        Player:BuffUp(S.MasterOfTheElementsBuff)) and
      Target:IsSpellInRange(S.FrostShock)
   then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
  -- lava_burst,if=buff.ascendance.up
  if S.LavaBurst:IsReady() and (Player:BuffUp(S.AscendanceBuff)) and Target:IsSpellInRange(S.LavaBurst) then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- lava_burst,if=cooldown_react&!talent.master_of_the_elements.enabled
  if S.LavaBurst:IsReady() and (not S.MasterOfTheElements:IsAvailable()) and Target:IsSpellInRange(S.LavaBurst) then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- icefury,if=talent.icefury.enabled&!(maelstrom>75&cooldown.lava_burst.remains<=0)
  if
    S.Icefury:IsReady() and not Player:IsCasting(S.IceFury) and
      (not (Player:Maelstrom() > 75 and S.LavaBurst:CooldownUp())) and
      Target:IsSpellInRange(S.Icefury)
   then
    return {["spell"] = S.Icefury, ["multitarget"] = false}
  end
  -- lava_burst,if=cooldown_react&charges>talent.echo_of_the_elements.enabled
  if
    S.LavaBurst:IsReady() and (S.LavaBurst:Charges() > num(S.EchoOfTheElements:IsAvailable())) and
      Target:IsSpellInRange(S.LavaBurst)
   then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- frost_shock,if=talent.icefury.enabled&buff.icefury.up
  if S.FrostShock:IsReady() and (Player:BuffUp(S.IcefuryBuff)) and Target:IsSpellInRange(S.FrostShock) then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
  -- chain_harvest
  if S.ChainHarvest:IsReady() and Target:IsSpellInRange(S.ChainHarvest) then
    return {["spell"] = S.ChainHarvest, ["multitarget"] = false}
  end
  -- static_discharge,if=talent.static_discharge.enabled
  if S.StaticDischarge:IsReady() and Target:IsSpellInRange(S.StaticDischarge) then
    return {["spell"] = S.StaticDischarge, ["multitarget"] = false}
  end
  -- earth_elemental,if=!talent.primal_elementalist.enabled|talent.primal_elementalist.enabled&(!pet.storm_elemental.active)
  -- if
  --   S.EarthElemental:IsCastable() and
  --     (not S.PrimalElementalist:IsAvailable() or S.PrimalElementalist:IsAvailable() and (not SEActive))
  --  then
  --   return {["spell"] = S.EarthElemental) then
  --     return "earth_elemental ses 98"
  --   end
  -- end
  -- lightning_bolt
  if S.LightningBolt:IsReady() and Target:IsSpellInRange(S.LightningBolt) then
    return {["spell"] = S.LightningBolt, ["multitarget"] = false}
  end
  -- flame_shock,moving=1,target_if=refreshable
  -- flame_shock,moving=1,if=movement.distance>6
  if
    S.FlameShock:IsReady() and Player:IsMoving() and Target:DebuffRefreshable(S.FlameShockDebuff) and
      Target:IsSpellInRange(S.FlameShock)
   then
    return {["spell"] = S.FlameShock, ["multitarget"] = false}
  end
  -- frost_shock,moving=1
  if S.FrostShock:IsReady() and Player:IsMoving() and Target:IsSpellInRange(S.FrostShock) then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
end

local function Single()
  -- flame_shock,target_if=(!ticking|dot.flame_shock.remains<=gcd|talent.ascendance.enabled&dot.flame_shock.remains<(cooldown.ascendance.remains+buff.ascendance.duration)&cooldown.ascendance.remains<4)&(buff.lava_surge.up|!buff.bloodlust.up)
  if S.FlameShock:IsReady() then
    local spell, array =
      HM.CastCycle(S.FlameShock, Enemies40y, EvaluateCycleFlameShock204, not Target:IsSpellInRange(S.FlameShock))
    if spell then
      return array
    end
  end
  -- ascendance,if=talent.ascendance.enabled&(time>=60|buff.bloodlust.up)&(cooldown.lava_burst.remains>0)&(!talent.icefury.enabled|!buff.icefury.up&!cooldown.icefury.up)
  if
    S.Ascendance:IsCastable() and
      ((HL.CombatTime() >= 60 or Player:BloodlustUp()) and S.LavaBurst:CooldownRemains() > 0 and
        (not S.Icefury:IsAvailable() or Player:BuffDown(S.IcefuryBuff) and not S.Icefury:CooldownUp()))
   then
    return {["spell"] = S.Ascendance, ["multitarget"] = false}
  end
  -- elemental_blast,if=talent.elemental_blast.enabled&(talent.master_of_the_elements.enabled&(buff.master_of_the_elements.up&maelstrom<60|!buff.master_of_the_elements.up)|!talent.master_of_the_elements.enabled)
  if
    S.ElementalBlast:IsReady() and
      (S.MasterOfTheElements:IsAvailable() and
        (Player:BuffUp(S.MasterOfTheElementsBuff) and Player:Maelstrom() < 60 or
          Player:BuffDown(S.MasterOfTheElementsBuff)) or
        not S.MasterOfTheElements:IsAvailable()) and
      Target:IsSpellInRange(S.ElementalBlast)
   then
    return {["spell"] = S.ElementalBlast, ["multitarget"] = false}
  end
  -- stormkeeper,if=talent.stormkeeper.enabled&(raid_event.adds.count<3|raid_event.adds.in>50)&(maelstrom<44)
  if S.Stormkeeper:IsCastable() and not Player:IsCasting(S.Stormkeeper) and (Player:Maelstrom() < 44) then
    return {["spell"] = S.Stormkeeper, ["multitarget"] = false}
  end
  -- echoing_shock,if=talent.echoing_shock.enabled&cooldown.lava_burst.remains<=0
  if S.EchoingShock:IsReady() and (S.LavaBurst:CooldownUp()) and Target:IsSpellInRange(S.EchoingShock) then
    return {["spell"] = S.EchoingShock, ["multitarget"] = false}
  end
  -- lava_burst,if=talent.echoing_shock.enabled&buff.echoing_shock.up
  if S.LavaBurst:IsReady() and (Player:BuffUp(S.EchoingShockBuff)) and Target:IsSpellInRange(S.LavaBurst) then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- liquid_magma_totem,if=talent.liquid_magma_totem.enabled
  if S.LiquidMagmaTotem:IsReady() then
    return {["spell"] = S.LiquidMagmaTotem, ["multitarget"] = false}
  end
  -- lightning_bolt,if=buff.stormkeeper.up&spell_targets.chain_lightning<2&(buff.master_of_the_elements.up)
  if
    S.LightningBolt:IsReady() and
      (Player:BuffUp(S.StormkeeperBuff) and EnemiesCount10ySplash < 2 and Player:BuffUp(S.MasterOfTheElementsBuff)) and
      Target:IsSpellInRange(S.LightningBolt)
   then
    return {["spell"] = S.LightningBolt, ["multitarget"] = false}
  end
  -- earthquake,if=buff.echoes_of_great_sundering.up&(!talent.master_of_the_elements.enabled|buff.master_of_the_elements.up)
  if
    S.Earthquake:IsReady() and
      (Player:BuffUp(S.EchoesofGreatSunderingBuff) and
        (not S.MasterOfTheElements:IsAvailable() or Player:BuffUp(S.MasterOfTheElementsBuff)))
   then
    return {["spell"] = S.Earthquake, ["multitarget"] = false}
  end
  -- earthquake,if=(spell_targets.chain_lightning>1)&(!dot.flame_shock.refreshable)&(!talent.master_of_the_elements.enabled|buff.master_of_the_elements.up|cooldown.lava_burst.remains>0&maelstrom>=92)
  if
    S.Earthquake:IsReady() and
      (EnemiesCount10ySplash > 1 and not Target:DebuffRefreshable(S.FlameShockDebuff) and
        (not S.MasterOfTheElements:IsAvailable() or Player:BuffUp(S.MasterOfTheElementsBuff) or
          S.LavaBurst:CooldownRemains() > 0 and Player:Maelstrom() >= 92))
   then
    return {["spell"] = S.Earthquake, ["multitarget"] = false}
  end
  -- earth_shock,if=talent.master_of_the_elements.enabled&(buff.master_of_the_elements.up|cooldown.lava_burst.remains>0&maelstrom>=92|spell_targets.chain_lightning<2&buff.stormkeeper.up&cooldown.lava_burst.remains<=gcd)|!talent.master_of_the_elements.enabled
  if
    S.EarthShock:IsReady() and
      (S.MasterOfTheElements:IsAvailable() and
        (Player:BuffUp(S.MasterOfTheElementsBuff) or S.LavaBurst:CooldownRemains() > 0 and Player:Maelstrom() >= 92 or
          EnemiesCount10ySplash < 2 and Player:BuffUp(S.StormkeeperBuff) and
            S.LavaBurst:CooldownRemains() <= Player:GCD()) or
        not S.MasterOfTheElements:IsAvailable()) and
      Target:IsSpellInRange(S.EarthShock)
   then
    return {["spell"] = S.EarthShock, ["multitarget"] = false}
  end
  -- lightning_bolt,if=(buff.stormkeeper.remains<1.1*gcd*buff.stormkeeper.stack|buff.stormkeeper.up&buff.master_of_the_elements.up)
  if
    S.LightningBolt:IsReady() and
      (Player:BuffRemains(S.StormkeeperBuff) < 1.1 * Player:GCD() * Player:BuffStack(S.StormkeeperBuff) or
        Player:BuffUp(S.StormkeeperBuff) and Player:BuffUp(S.MasterOfTheElementsBuff)) and
      Target:IsSpellInRange(S.LightningBolt)
   then
    return {["spell"] = S.LightningBolt, ["multitarget"] = false}
  end
  -- frost_shock,if=talent.icefury.enabled&talent.master_of_the_elements.enabled&buff.icefury.up&buff.master_of_the_elements.up
  if
    S.FrostShock:IsReady() and
      (S.Icefury:IsAvailable() and S.MasterOfTheElements:IsAvailable() and Player:BuffUp(S.IcefuryBuff) and
        Player:BuffUp(S.MasterOfTheElementsBuff)) and
      Target:IsSpellInRange(S.FrostShock)
   then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
  -- lava_burst,if=buff.ascendance.up
  if S.LavaBurst:IsReady() and (Player:BuffUp(S.AscendanceBuff)) and Target:IsSpellInRange(S.LavaBurst) then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- lava_burst,if=cooldown_react&!talent.master_of_the_elements.enabled
  if S.LavaBurst:IsReady() and (not S.MasterOfTheElements:IsAvailable()) and Target:IsSpellInRange(S.LavaBurst) then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- icefury,if=talent.icefury.enabled&!(maelstrom>75&cooldown.lava_burst.remains<=0)
  if
    S.Icefury:IsReady() and not Player:IsCasting(S.IceFury) and
      (not (Player:Maelstrom() > 75 and S.LavaBurst:CooldownUp())) and
      Target:IsSpellInRange(S.Icefury)
   then
    return {["spell"] = S.Icefury, ["multitarget"] = false}
  end
  -- lava_burst,if=cooldown_react&charges>talent.echo_of_the_elements.enabled
  if
    S.LavaBurst:IsReady() and (S.LavaBurst:Charges() > num(S.EchoOfTheElements:IsAvailable())) and
      Target:IsSpellInRange(S.LavaBurst)
   then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- frost_shock,if=talent.icefury.enabled&buff.icefury.up&buff.icefury.remains<1.1*gcd*buff.icefury.stack
  if
    S.FrostShock:IsReady() and
      (S.Icefury:IsAvailable() and Player:BuffUp(S.IcefuryBuff) and
        Player:BuffRemains(S.IcefuryBuff) < 1.1 * Player:GCD() * Player:BuffStack(S.IcefuryBuff)) and
      Target:IsSpellInRange(S.FrostShock)
   then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
  -- lava_burst,if=cooldown_react
  if S.LavaBurst:IsReady() and Target:IsSpellInRange(S.LavaBurst) then
    return {["spell"] = S.LavaBurst, ["multitarget"] = false}
  end
  -- flame_shock,target_if=refreshable
  if S.FlameShock:IsReady() then
    local spell, array =
      HM.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateCycleFlameShock, not Target:IsSpellInRange(S.FlameShock))
    if spell then
      return array
    end
  end
  -- earthquake,if=spell_targets.chain_lightning>1&!runeforge.echoes_of_great_sundering.equipped|(buff.echoes_of_great_sundering.up&buff.master_of_the_elements.up)
  if
    S.Earthquake:IsReady() and
      (EnemiesCount10ySplash > 1 and not EchoesofGreatSunderingEquipped or
        (Player:BuffUp(S.EchoesofGreatSunderingBuff) and Player:BuffUp(S.MasterOfTheElementsBuff)))
   then
    return {["spell"] = S.Earthquake, ["multitarget"] = false}
  end
  -- frost_shock,if=talent.icefury.enabled&buff.icefury.up&(buff.icefury.remains<gcd*4*buff.icefury.stack|buff.stormkeeper.up|!talent.master_of_the_elements.enabled)
  if
    S.FrostShock:IsReady() and
      (Player:BuffUp(S.IcefuryBuff) and
        (Player:BuffRemains(S.IcefuryBuff) < Player:GCD() * 4 * Player:BuffStack(S.IcefuryBuff) or
          Player:BuffUp(S.StormkeeperBuff) or
          not S.MasterOfTheElements:IsAvailable())) and
      Target:IsSpellInRange(S.FrostShock)
   then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
  -- frost_shock,if=runeforge.elemental_equilibrium.equipped&!buff.elemental_equilibrium_debuff.up&!talent.elemental_blast.enabled&!talent.echoing_shock.enabled
  if
    S.FrostShock:IsReady() and
      (ElementalEquilibriumEquipped and Player:BuffDown(S.ElementalEquilibriumBuff) and
        not S.ElementalBlast:IsAvailable() and
        not S.EchoingShock:IsAvailable()) and
      Target:IsSpellInRange(S.FrostShock)
   then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
  -- chain_harvest
  if S.ChainHarvest:IsReady() and Target:IsSpellInRange(S.ChainHarvest) then
    return {["spell"] = S.ChainHarvest, ["multitarget"] = false}
  end
  -- static_discharge,if=talent.static_discharge.enabled
  if S.StaticDischarge:IsReady() then
    return {["spell"] = S.StaticDischarge, ["multitarget"] = false}
  end
  -- earth_elemental,if=!talent.primal_elementalist.enabled|!pet.fire_elemental.active
  -- if S.EarthElemental:IsCastable() and (not S.PrimalElementalist:IsAvailable() or not FEActive) then
  --   return {["spell"] = S.EarthElemental) then
  --     return "earth_elemental single 172"
  --   end
  -- end
  -- lightning_bolt
  if S.LightningBolt:IsReady() and Target:IsSpellInRange(S.LightningBolt) then
    return {["spell"] = S.LightningBolt, ["multitarget"] = false}
  end
  -- flame_shock,moving=1,target_if=refreshable
  -- flame_shock,moving=1,if=movement.distance>6
  if
    S.FlameShock:IsCastable() and Player:IsMoving() and Target:DebuffRefreshable(S.FlameShock) and
      Target:IsSpellInRange(S.FlameShock)
   then
    return {["spell"] = S.FlameShock, ["multitarget"] = false}
  end
  -- frost_shock,moving=1
  if S.FrostShock:IsCastable() and Player:IsMoving() and Target:IsSpellInRange(S.FrostShock) then
    return {["spell"] = S.FrostShock, ["multitarget"] = false}
  end
end

--- ======= MAIN =======
function HM.ElementalAPL()
  -- Unit Update
  Enemies40y = Player:GetEnemiesInRange(40)
  Enemies10ySplash = Target:GetEnemiesInSplashRange(10)
  if HM.Settings.AoEON then
    EnemiesCount10ySplash = Target:GetEnemiesInSplashRangeCount(10)
    Enemies40yCount = #Enemies40y
    calcEnemiesFlameShockCount(S.FlameShock, Enemies40y)
  else
    EnemiesCount10ySplash = 1
    Enemies40yCount = 1
    EnemiesFlameShockCount = 1
  end

  SEActive = (S.StormElemental:IsAvailable() and S.StormElemental:CooldownRemains() > S.StormElemental:Cooldown() - 30)
  FEActive =
    (not S.StormElemental:IsAvailable() and S.FireElemental:CooldownRemains() > S.FireElemental:Cooldown() - 30)

  -- In Combat
  if HM.TargetIsValid() then
    -- Precombat
    if not Player:AffectingCombat() then
      -- wind_shear
      -- local ShouldReturn = Everyone.Interrupt(30, S.WindShear, Settings.Commons.OffGCDasOffGCD.WindShear, false)
      -- if ShouldReturn then
      --   return ShouldReturn
      -- end
      -- use_items
      -- local TrinketToUse = Player:GetUseableTrinkets(OnUseExcludes)
      -- if TrinketToUse then
      --   return TrinketToUse, nil, Settings.Commons.TrinketDisplayStyle) then
      --     return "Generic use_items for " .. TrinketToUse:Name()
      --   end
      -- end
      -- flame_shock,if=!ticking
      local ShouldReturn = Precombat()
      if ShouldReturn then
        return ShouldReturn
      end
    else
      -- -- If nothing else to do, show the Pool icon
      -- if HR.CastAnnotated(S.Pool, false, "WAIT") then
      --   return "Wait/Pool Resources"
      -- end
      if S.FlameShock:IsCastable() and Target:DebuffDown(S.FlameShock) and Target:IsSpellInRange(S.FlameShock) then
        return {["spell"] = S.FlameShock, ["multitarget"] = false}
      end
      if HM.Settings.CDsON then
        -- fire_elemental
        if S.FireElemental:IsCastable() then
          return {["spell"] = S.FireElemental, ["multitarget"] = false}
        end
        -- storm_elemental
        if S.StormElemental:IsCastable() then
          return {["spell"] = S.StormElemental, ["multitarget"] = false}
        end
        -- blood_fury,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
        if
          S.BloodFury:IsCastable() and
            (not S.Ascendance:IsAvailable() or Player:BuffUp(S.Ascendance) or S.Ascendance:CooldownRemains() > 50)
         then
          return {["spell"] = S.BloodFury, ["multitarget"] = false}
        end
        -- berserking,if=!talent.ascendance.enabled|buff.ascendance.up
        if S.BloodFury:IsCastable() and (not S.Ascendance:IsAvailable() or Player:BuffUp(S.Ascendance)) then
          return {["spell"] = S.Berserking, ["multitarget"] = false}
        end
        -- ancestral_call,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
        if
          S.AncestralCall:IsCastable() and
            (not S.Ascendance:IsAvailable() or Player:BuffUp(S.Ascendance) or S.Ascendance:CooldownRemains() > 50)
         then
          return {["spell"] = S.AncestralCall, ["multitarget"] = false}
        end
        -- fireblood,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
        if
          S.Fireblood:IsCastable() and
            (not S.Ascendance:IsAvailable() or Player:BuffUp(S.Ascendance) or S.Ascendance:CooldownRemains() > 50)
         then
          return {["spell"] = S.Fireblood, ["multitarget"] = false}
        end
        -- bag_of_tricks,if=!talent.ascendance.enabled|!buff.ascendance.up
        if
          S.BagofTricks:IsCastable() and (not S.Ascendance:IsAvailable() or not Player:BuffUp(S.Ascendance)) and
            Target:SpellInRange(S.BagofTricks)
         then
          return {["spell"] = S.BagofTricks, ["multitarget"] = false}
        end
      end
      -- primordial_wave,target_if=min:dot.flame_shock.remains,cycle_targets=1,if=!buff.primordial_wave.up
      if S.PrimordialWave:IsReady() and (Player:BuffDown(S.PrimordialWaveBuff)) then
        local spell, array =
          HM.CastCycle(S.FlameShock, Enemies40y, EvaluateCycleFlameShock, not Target:IsSpellInRange(S.FlameShock))
        if spell then
          return array
        end
      end
      -- vesper_totem,if=covenant.kyrian
      if S.VesperTotem:IsReady() and arget:IsInRange(40) then
        return {["spell"] = S.VesperTotem, ["multitarget"] = false}
      end
      -- fae_transfusion,if=covenant.night_fae
      if S.FaeTransfusion:IsReady() and Target:IsInRange(40) then
        return {["spell"] = S.FaeTransfusion, ["multitarget"] = false}
      end
      -- run_action_list,name=aoe,if=active_enemies>2&(spell_targets.chain_lightning>2|spell_targets.lava_beam>2)
      if EnemiesCount10ySplash > 2 then
        local ShouldReturn = Aoe()
        if ShouldReturn then
          return ShouldReturn
        end
      end
      -- run_action_list,name=single_target,if=!talent.storm_elemental.enabled&active_enemies<=2
      if not S.StormElemental:IsAvailable() and EnemiesCount10ySplash <= 2 then
        local ShouldReturn = Single()
        if ShouldReturn then
          return ShouldReturn
        end
      end
      -- run_action_list,name=se_single_target,if=talent.storm_elemental.enabled&active_enemies<=2
      if S.StormElemental:IsAvailable() and EnemiesCount10ySplash <= 2 then
        local ShouldReturn = SESingle()
        if ShouldReturn then
          return ShouldReturn
        end
      end
    end
  end
end
