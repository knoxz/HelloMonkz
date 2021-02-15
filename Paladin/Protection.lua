--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local HL = HeroLib
local Unit = HL.Unit
local Player = Unit.Player
local Target = Unit.Target
local Spell = HL.Spell
local MultiSpell = HL.MultiSpell
local Item = HL.Item
-- -- HeroRotation
-- local HR = HeroRotation
-- local AoEON = HR.AoEON
-- local .CDsON HR..CDsON- local Cast = HR.Cast
-- Lua
local mathmin = math.min

local addonName, HM = ...

HelloMonkz = HM

--- ============================ CONTENT ===========================
--- ======= APL LOCALS =======
-- luacheck: max_line_length 9999

-- Define S/I for spell and item arrays
local S = Spell.Paladin.Protection

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {}

-- Interrupts List
-- local StunInterrupts = {
--   {S.HammerofJustice, "Cast Hammer of Justice (Interrupt)", function () return true; end},
-- }

-- Rotation Var
local ShouldReturn  -- Used to get the return string
local ActiveMitigationNeeded
local IsTanking
local Enemies8y, Enemies30y
local EnemiesCount8y, EnemiesCount30y

-- GUI Settings
-- local Everyone = HR.Commons.Everyone
-- local Settings = {
--   General = HR.GUISettings.General,
--   Commons = HR.GUISettings.APL.Paladin.Commons,
--   Protection = HR.GUISettings.APL.Paladin.Protection
-- }

local function EvaluateCycleJudgment200(TargetUnit)
  return TargetUnit:DebuffRefreshable(S.JudgmentDebuff)
end

local function Defensives()
  if
    S.GuardianofAncientKings:IsCastable() and
      (Player:HealthPercentage() <= HM.Settings.ProtPala.GoAKHP and Player:BuffDown(S.ArdentDefenderBuff))
   then
    return {["spell"] = S.GuardianofAncientKings, ["multitarget"] = false}
  end
  if
    S.ArdentDefender:IsCastable() and
      (Player:HealthPercentage() <= HM.Settings.ProtPala.ArdentDefenderHP and
        Player:BuffDown(S.GuardianofAncientKingsBuff))
   then
    return {["spell"] = S.ArdentDefender, ["multitarget"] = false}
  end
  if
    S.WordofGlory:IsReady() and
      (Player:HealthPercentage() <= HM.Settings.ProtPala.WordofGloryHP and not Player:HealingAbsorbed())
   then
    return {["spell"] = S.WordofGlory, ["multitarget"] = false}
  end
  if
    S.ShieldoftheRighteous:IsReady() and
      (Player:BuffRefreshable(S.ShieldoftheRighteousBuff) and
        (ActiveMitigationNeeded or Player:HealthPercentage() <= HM.Settings.ProtPala.ShieldoftheRighteousHP))
   then
    return {["spell"] = S.ShieldoftheRighteous, ["multitarget"] = false}
  end
end

local function Cooldowns()
  -- fireblood,if=buff.avenging_wrath.up
  if S.Fireblood:IsCastable() and (Player:BuffUp(S.AvengingWrathBuff)) then
    return {["spell"] = S.Fireblood, ["multitarget"] = false}
  end
  -- seraphim
  if S.Seraphim:IsReady() then
    return {["spell"] = S.Seraphim, ["multitarget"] = false}
  end
  -- avenging_wrath
  if S.AvengingWrath:IsCastable() then
    return {["spell"] = S.AvengingWrath, ["multitarget"] = false}
  end
  -- holy_avenger,if=buff.avenging_wrath.up|cooldown.avenging_wrath.remains>60
  if S.HolyAvenger:IsCastable() and (Player:BuffUp(S.AvengingWrathBuff) or S.AvengingWrath:CooldownRemains() > 60) then
    return {["spell"] = S.HolyAvenger, ["multitarget"] = false}
  end
  -- potion,if=buff.avenging_wrath.up
  -- if I.PotionofUnbridledFury:IsReady() and Settings.Commons.UsePotions and (Player:BuffUp(S.AvengingWrathBuff)) then
  --   if HR.CastSuggested(I.PotionofUnbridledFury) then return "potion 40"; end
  -- end
  -- use_items,if=buff.seraphim.up|!talent.seraphim.enabled
  -- if (Player:BuffUp(S.SeraphimBuff) or not S.Seraphim:IsAvailable()) then
  --   local TrinketToUse = Player:GetUseableTrinkets(OnUseExcludes)
  --   if TrinketToUse then
  --     return TrinketToUse, nil, Settings.Commons.TrinketDisplayStyle) then return "Generic use_items for " .. TrinketToUse:Name(); end
  --   end
  -- end
  -- moment_of_glory,if=prev_gcd.1.avengers_shield&cooldown.avengers_shield.remains
  if S.MomentofGlory:IsCastable() and (Player:PrevGCD(1, S.AvengersShield) and not S.AvengersShield:CooldownUp()) then
    return {["spell"] = S.MomentofGlory, ["multitarget"] = false}
  end
end

local function Standard()
  -- shield_of_the_righteous,if=debuff.judgment.up&(debuff.vengeful_shock.up|!conduit.vengeful_shock.enabled)
  if
    S.ShieldoftheRighteous:IsReady() and
      (Target:DebuffUp(S.JudgmentDebuff) and
        (Target:DebuffUp(S.VengefulShockDebuff) or not S.VengefulShock:IsAvailable()))
   then
    return {["spell"] = S.ShieldoftheRighteous, ["multitarget"] = false}
  end
  -- shield_of_the_righteous,if=holy_power=5|buff.holy_avenger.up|holy_power=4&talent.sanctified_wrath.enabled&buff.avenging_wrath.up
  if
    S.ShieldoftheRighteous:IsReady() and
      (Player:HolyPower() == 5 or Player:BuffUp(S.HolyAvengerBuff) or
        Player:HolyPower() == 4 and S.SanctifiedWrath:IsAvailable() and Player:BuffUp(S.AvengingWrathBuff))
   then
    return {["spell"] = S.ShieldoftheRighteous, ["multitarget"] = false}
  end
  -- judgment,target_if=min:debuff.judgment.remains,if=charges=2|!talent.crusaders_judgment.enabled
  -- TODO: Multidot?
  if S.Judgment:IsReady() and (S.Judgment:Charges() == 2 or not S.CrusadersJudgment:IsAvailable()) then
    return {["spell"] = S.Judgment, ["multitarget"] = false}
  end
  -- avengers_shield,if=debuff.vengeful_shock.down&conduit.vengeful_shock.enabled
  if S.AvengersShield:IsCastable() and (Target:DebuffDown(S.VengefulShockDebuff) and S.VengefulShock:IsAvailable()) then
    return {["spell"] = S.AvengersShield, ["multitarget"] = false}
  end
  -- hammer_of_wrath
  -- Note: Added IsUsable check. IsReady checks IsCastable and IsUsableP, which always returns true when not on CD
  if S.HammerofWrath:IsReady() and S.HammerofWrath:IsUsable() then
    return {["spell"] = S.HammerofWrath, ["multitarget"] = false}
  end
  -- avengers_shield
  if S.AvengersShield:IsCastable() then
    return {["spell"] = S.AvengersShield, ["multitarget"] = false}
  end
  -- judgment,target_if=min:debuff.judgment.remains
  if S.Judgment:IsReady() then
    return {["spell"] = S.Judgment, ["multitarget"] = false}
  end
  -- vanquishers_hammer
  if S.VanquishersHammer:IsReady() then
    return {["spell"] = S.VanquishersHammer, ["multitarget"] = false}
  end
  -- consecration,if=!consecration.up
  if S.Consecration:IsCastable() and (Player:BuffDown(S.ConsecrationBuff)) and Target:IsInRange(8) then
    return {["spell"] = S.Consecration, ["multitarget"] = false}
  end
  -- divine_toll
  if S.DivineToll:IsReady() then
    return {["spell"] = S.DivineToll, ["multitarget"] = false}
  end
  -- blessed_hammer,strikes=2.4,if=charges=3
  if S.BlessedHammer:IsCastable() and (S.BlessedHammer:Charges() == 3) then
    return {["spell"] = S.BlessedHammer, ["multitarget"] = false}
  end
  -- ashen_hallow
  if S.AshenHallow:IsReady() then
    return {["spell"] = S.AshenHallow, ["multitarget"] = false}
  end
  -- hammer_of_the_righteous,if=charges=2
  if S.HammeroftheRighteous:IsCastable() and (S.HammeroftheRighteous:Charges() == 2) then
    return {["spell"] = S.HammeroftheRighteous, ["multitarget"] = false}
  end
  -- word_of_glory,if=buff.vanquishers_hammer.up
  if S.WordofGlory:IsReady() and (Player:BuffUp(S.VanquishersHammerBuff)) then
    return {["spell"] = S.WordofGlory, ["multitarget"] = false}
  end
  -- blessed_hammer,strikes=2.4
  if S.BlessedHammer:IsCastable() then
    return {["spell"] = S.BlessedHammer, ["multitarget"] = false}
  end
  -- hammer_of_the_righteous
  if S.HammeroftheRighteous:IsCastable() then
    return {["spell"] = S.HammeroftheRighteous, ["multitarget"] = false}
  end
  -- lights_judgment
  if S.LightsJudgment:IsCastable() then
    return {["spell"] = S.LightsJudgment, ["multitarget"] = false}
  end
  -- arcane_torrent
  if S.ArcaneTorrent:IsCastable() and Target:IsInRange(8) then
    return {["spell"] = S.ArcaneTorrent, ["multitarget"] = false}
  end
  -- consecration
  if S.Consecration:IsCastable() and Target:IsInRange(8) then
    return {["spell"] = S.Consecration, ["multitarget"] = false}
  end
  -- word_of_glory,if=buff.shining_light_free.up&!covenant.necrolord
  if S.WordofGlory:IsReady() and (Player:BuffUp(S.ShiningLightFreeBuff) and not S.VanquishersHammer:IsAvailable()) then
    return {["spell"] = S.WordofGlory, ["multitarget"] = false}
  end
end

-- APL Main
function HM.ProtAPL()
  Enemies8y = Player:GetEnemiesInMeleeRange(8)
  Enemies30y = Player:GetEnemiesInRange(30)
  if (HM.Settings.AoEON) then
    EnemiesCount8y = #Enemies8y
    EnemiesCount30y = #Enemies30y
  else
    EnemiesCount8y = 1
    EnemiesCount30y = 1
  end

  ActiveMitigationNeeded = Player:ActiveMitigationNeeded()
  IsTanking = Player:IsTankingAoE(8) or Player:IsTanking(Target)

  if HM.TargetIsValid() and Player:AffectingCombat() then
    -- Precombat
    -- if not Player:AffectingCombat() then
    --   local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
    -- end
    -- auto_attack
    if not IsCurrentSpell(6603) then
      CallSecureFunction("AttackTarget")
    end
    -- Interrupts
    -- local ShouldReturn = Everyone.Interrupt(5, S.Rebuke, Settings.Commons.OffGCDasOffGCD.Rebuke, StunInterrupts); if ShouldReturn then return ShouldReturn; end
    -- Manually added: Defensives!
    if (IsTanking and HM.Settings.ProtPala.AutoDefs) then
      local ShouldReturn = Defensives()
      if ShouldReturn then
        return ShouldReturn
      end
    end
    -- call_action_list,name=cooldowns
    if HM.Settings.CDsON then
      local ShouldReturn = Cooldowns()
      if ShouldReturn then
        return ShouldReturn
      end
    end
    -- call_action_list,name=standard
    if (true) then
      local ShouldReturn = Standard()
      if ShouldReturn then
        return ShouldReturn
      end
    end
    -- Manually added: Pool, if nothing else to do
    if ShouldReturn then
      return ShouldReturn
    end
  end
end
