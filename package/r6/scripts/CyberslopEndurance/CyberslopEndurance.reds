// Cyberslop Endurance 1.3.2, for game 2.5 and Dark Future 3.0.
// 1.3.2 (2026-11-26): oxygen capacity / refill x1.3 while a status effect tagged CyberslopOxygen.Cap / .Refill runs
// (Cyberslop Merc Stims: Respirocyte Infusion, Bronchodilator Inhaler).
// 1.3.1 (2026-11-23): a save made under 25 % oxygen no longer loads with the heavy-breathing sway stuck on
// (the savable BreathingHeavy effect is removed in the first 5 s after a load unless this mod owns it).
// 1.3.0 (2026-11-17, port): Dark Future 3.0 renamed its HUD slot (DarkFutureWidgetSlot) and dropped the lock icon
// fields of its bar setup; game 2.5 passes the left-hand weapon to UpdateEquippedWeaponsHandling and puts the same
// handling modifiers on both weapons, so the low-oxygen sway is applied to both hands too.
// 1.2.0 (2026-11-06): chest injuries from the Injuries mod
// cut the oxygen capacity (tier 1 -10 %, 2 -20 %, 3 -35 %: rib fractures and lung injury limit breathing).
// A second, deeper reserve on top of the vanilla stamina pool: Oxygen. Needs Dark Future (its need values and its HUD
// bar classes), Codeware and Mod Settings.
//
//  - Stamina stays vanilla (crosshair bar, costs from other mods). This mod only shrinks max stamina and stamina
//    refill when oxygen is low (down to x0.5 at 0 oxygen) and adds a few exertion costs: takedown / grapple 15 %,
//    finisher 10 %, grenade throw 4 %, taking a hit 3 / 6 / 10 % (ranged / melee / strong melee).
//  - Oxygen (aqua bar right under Dark Future's Nerve bar, Nerve width; the three need bars move one row down):
//    capacity = 100 x Body bonus (+30 % at Body 20) x well-being (thirst and sleep take up to 30 % each, hunger 20 %,
//    floor 45 %). Drains 0.3 per stamina point spent plus a steady drain while sprinting (0.8 %/s), crouch-sprinting
//    (0.6), climbing / vaulting / on a ladder (1.2), swimming fast (1.0) or carrying a body (0.8). Refills after a wait
//    of 3 s (8 s from empty; longer with low Reflexes, low Nerve, thirst, tiredness) at rest 1.5 %/s, walking 0.8, running
//    0.3, never while sprinting etc.; refill is fastest when the deficit is large.
//  - Below 50 % oxygen max stamina and stamina refill shrink gradually; below 25 % recoil, sway and spread grow (up to
//    x1.4 at 0), V breathes heavily (vanilla camera breathing + breath sound). No locks.
//  - Oxygen is not saved: full on every load and after a time skip.
//  - The YAML next to this file sets Dark Future's direct stamina penalties (Energy -> max stamina, Hydration ->
//    stamina refill) to 1.0: those needs now act through oxygen instead of counting twice.
//
// All numbers are Mod Settings > Cyberslop Endurance.
// 1.1.0: event log. "Log" writes [Endurance] lines to the CET game log on events only (activity changes, oxygen band
// crossings, drain start / end with the wait that applies, refill start with the measured wait, stamina factor and sway
// steps, breathing, every exertion cost with the stamina before it, capacity changes from the needs, resets, the bar)
// plus a summary every 10 s while oxygen moves. Lines are buffered and written every 5 s or 40 lines, at most 60 lines
// per flush (the rest is counted and reported), so a bad state cannot flood the log. "Verbose" adds the 2 s snapshot.

module CyberslopEndurance

import DarkFuture.Needs.{DFHydrationSystem, DFNutritionSystem, DFEnergySystem}
import DarkFuture.UI.{DFHUDSystem, DFNeedsHUDBar, DFNeedsHUDBarGroup, DFNeedsHUDBarSetupData}
import DarkFuture.Utils.{DFBarColorTheme, DFBarColorThemeName, GetDarkFutureBarColorTheme}
import DarkFuture.Settings.DFSettings
@if(ModuleExists("Injuries"))
import Injuries.*

// 1.2.0: chest trauma limits breathing. Rib fractures alone cut vital capacity by 25-50 % (pain splinting);
// a lung injury more. Injuries mod torso tier: 1 = x0.90, 2 = x0.80, 3 = x0.65 of the capacity.
@if(ModuleExists("Injuries"))
func CEN_ChestMult(gi: GameInstance) -> Float {
  let sys: ref<InjuriesSystem> = InjuriesSystem.Get(gi);
  let cfg: ref<InjuriesConfig> = InjuriesConfig.Get();
  let t: Int32;
  if !IsDefined(sys) || !IsDefined(cfg) || !cfg.modON || !sys.IsLive() {
    return 1.0;
  }
  t = sys.GetSeverity(1);
  if t >= 3 {
    return 0.65;
  }
  if t == 2 {
    return 0.80;
  }
  if t == 1 {
    return 0.90;
  }
  return 1.0;
}
@if(!ModuleExists("Injuries"))
func CEN_ChestMult(gi: GameInstance) -> Float {
  return 1.0;
}

public class EnduranceTick extends DelayCallback {
  public let system: wref<CyberslopEndurance>;

  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnTick();
    }
  }
}

public class CyberslopEndurance extends ScriptableSystem {

  // ---------------------------------------------------------------- settings

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Enabled")
  @runtimeProperty("ModSettings.description", "Off: oxygen stays full, no stamina shrink, no extra costs, the bar stays at 100 %. Dark Future's own stamina penalties stay switched off by the YAML either way.")
  public let enabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Oxygen per stamina point")
  @runtimeProperty("ModSettings.description", "Oxygen points burned for every stamina point spent. 0.3 = a full 100-point stamina bar costs 30 oxygen, about 3 bars from full at Body 3.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "1.0")
  @runtimeProperty("ModSettings.step", "0.05")
  public let oxygenPerStamina: Float = 0.3;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Sprint drain (% per second)")
  @runtimeProperty("ModSettings.description", "Steady oxygen drain while sprinting, on top of what the sprint's stamina cost burns. With Chrome Stride's 3 %/s sprint cost the total is about 1.7 %/s: a minute of sprinting from full.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "5.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let sprintDrain: Float = 0.8;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Crouch sprint drain (% per second)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "5.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let crouchSprintDrain: Float = 0.6;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Climb / vault / ladder drain (% per second)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "5.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let climbDrain: Float = 1.2;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Fast swimming drain (% per second)")
  @runtimeProperty("ModSettings.description", "While swimming or diving faster than the speed below. Slow swimming neither drains nor refills.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "5.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let swimDrain: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Fast swimming from (m/s)")
  @runtimeProperty("ModSettings.min", "0.5")
  @runtimeProperty("ModSettings.max", "6.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let swimFastSpeed: Float = 2.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Carrying a body drain (% per second)")
  @runtimeProperty("ModSettings.description", "Added to whatever else you do with a body on your shoulder; no refill while carrying.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "5.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let carryDrain: Float = 0.8;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Refill at rest (% per second)")
  @runtimeProperty("ModSettings.description", "Standing still (below the rest speed) or sitting in a vehicle. 1.5 = empty to full in about 70 s. Refill runs faster while the deficit is large and slows on the last stretch.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "10.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let restRefill: Float = 1.5;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Refill walking (% per second)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "10.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let walkRefill: Float = 0.8;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Refill running (% per second)")
  @runtimeProperty("ModSettings.description", "Moving at or above the walk speed without sprinting.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "10.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let runRefill: Float = 0.3;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Rest speed (m/s)")
  @runtimeProperty("ModSettings.description", "Below this horizontal speed you count as resting.")
  @runtimeProperty("ModSettings.min", "0.1")
  @runtimeProperty("ModSettings.max", "3.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let restSpeed: Float = 0.5;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Walk speed (m/s)")
  @runtimeProperty("ModSettings.description", "Below this horizontal speed you count as walking, at or above it as running. The log shows your measured speed.")
  @runtimeProperty("ModSettings.min", "1.0")
  @runtimeProperty("ModSettings.max", "8.0")
  @runtimeProperty("ModSettings.step", "0.1")
  public let walkSpeed: Float = 3.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Refill wait after light effort (s)")
  @runtimeProperty("ModSettings.description", "Seconds after the last drain before oxygen refills, when oxygen is still nearly full. Reflexes 20 cuts the wait by a quarter; Dark Future's low Nerve, thirst and tiredness stretch it.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "20.0")
  @runtimeProperty("ModSettings.step", "0.5")
  public let waitMin: Float = 3.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Oxygen")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "Refill wait from empty (s)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "30.0")
  @runtimeProperty("ModSettings.step", "0.5")
  public let waitMax: Float = 8.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Well-being (Dark Future)")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.displayName", "Thirst: capacity lost at 0 (%)")
  @runtimeProperty("ModSettings.description", "Starts below Hydration 75, grows faster the worse it gets. The lost part shows red at the end of the bar. Thirst also slows the refill (up to -40 %) and stretches the wait (+25 %).")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "60.0")
  @runtimeProperty("ModSettings.step", "5.0")
  public let thirstPenalty: Float = 30.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Well-being (Dark Future)")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.displayName", "Sleep: capacity lost at 0 (%)")
  @runtimeProperty("ModSettings.description", "Starts below Energy 75. Tiredness also slows the refill (up to -25 %) and stretches the wait (+40 %).")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "60.0")
  @runtimeProperty("ModSettings.step", "5.0")
  public let sleepPenalty: Float = 30.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Well-being (Dark Future)")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.displayName", "Hunger: capacity lost at 0 (%)")
  @runtimeProperty("ModSettings.description", "Starts below Nutrition 50. Hunger also slows the refill (up to -15 %). All three multiply; capacity never drops below 45 %, refill never below 40 %.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "60.0")
  @runtimeProperty("ModSettings.step", "5.0")
  public let hungerPenalty: Float = 20.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Low oxygen")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "Stamina at 0 oxygen (x)")
  @runtimeProperty("ModSettings.description", "Below 50 % oxygen, max stamina and stamina refill shrink evenly down to this share at 0 oxygen. 1.0 = off.")
  @runtimeProperty("ModSettings.min", "0.2")
  @runtimeProperty("ModSettings.max", "1.0")
  @runtimeProperty("ModSettings.step", "0.05")
  public let staminaAtEmpty: Float = 0.5;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Low oxygen")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "Weapon sway at 0 oxygen (x)")
  @runtimeProperty("ModSettings.description", "Below 25 % oxygen, recoil, sway and spread of the held weapon grow evenly up to this factor at 0 oxygen. 1.0 = off.")
  @runtimeProperty("ModSettings.min", "1.0")
  @runtimeProperty("ModSettings.max", "2.5")
  @runtimeProperty("ModSettings.step", "0.1")
  public let swayAtEmpty: Float = 1.4;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Low oxygen")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "Heavy breathing")
  @runtimeProperty("ModSettings.description", "Below 25 % oxygen: the game's heavy-breathing camera movement, a breath sound every 10 s and the tired weapon stance.")
  public let breathing: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Stamina costs")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "Takedown / grapple (% stamina)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "50.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let takedownCost: Float = 15.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Stamina costs")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "Finisher (% stamina)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "50.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let finisherCost: Float = 10.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Stamina costs")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "Grenade throw (% stamina)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "50.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let grenadeCost: Float = 4.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Stamina costs")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "Taking a melee hit (% stamina)")
  @runtimeProperty("ModSettings.description", "Only hits that cost you health (blocked hits are free).")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "50.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let hitMeleeCost: Float = 6.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Stamina costs")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "Taking a strong melee hit (% stamina)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "50.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let hitStrongCost: Float = 10.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Stamina costs")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "Taking a bullet or blast (% stamina)")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "50.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let hitRangedCost: Float = 3.0;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Debug")
  @runtimeProperty("ModSettings.category.order", "4")
  @runtimeProperty("ModSettings.displayName", "Log")
  @runtimeProperty("ModSettings.description", "Event log: activity changes, oxygen crossing 75 / 50 / 25 / 10 / 0 %, drain start and end, refill start with the wait that was applied, stamina factor and sway steps, breathing, every exertion cost, capacity changes from the needs, resets and the bar, plus a summary every 10 s while oxygen moves. [Endurance] lines in the CET game log (bin\\x64\\plugins\\cyber_engine_tweaks\\gamelog.log), buffered and written every 5 s. Cheap enough to leave on.")
  public let log: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Endurance")
  @runtimeProperty("ModSettings.category", "Debug")
  @runtimeProperty("ModSettings.category.order", "4")
  @runtimeProperty("ModSettings.displayName", "Verbose log")
  @runtimeProperty("ModSettings.description", "With Log: a full snapshot every 2 s while oxygen is not full (speed, stamina, oxygen, needs, multipliers, rates, locomotion state). For tuning sessions only.")
  @runtimeProperty("ModSettings.dependency", "log")
  public let logVerbose: Bool = false;

  // ---------------------------------------------------------------- state (not saved)

  private let m_player: wref<PlayerPuppet>;
  private let m_tickId: DelayID;
  private let m_lastTime: Float;
  private let m_first: Bool;
  private let m_oxygen: Float;
  private let m_healthy: Float = 100.0;
  private let m_capacity: Float = 100.0;
  private let m_capMult: Float = 1.0;
  private let m_refillMult: Float = 1.0;
  private let m_waitMult: Float = 1.0;
  private let m_needThirst: Float = 100.0;
  private let m_needSleep: Float = 100.0;
  private let m_needHunger: Float = 100.0;
  private let m_lastStaminaPct: Float;  // -1 = unknown (set on attach)
  private let m_waitUntil: Float;
  private let m_lastWait: Float;
  private let m_staminaMod: ref<gameStatModifierData>;
  private let m_regenMod: ref<gameStatModifierData>;
  private let m_applied: Float = 1.0;
  private let m_swaySent: Float = 1.0;
  private let m_breathingOn: Bool;
  // 1.3.1: until this sim time after an attach, a BreathingHeavy restored from the save is removed (see OnTick)
  private let m_breathCleanUntil: Float;
  private let m_breathSoundAt: Float;
  private let m_animAt: Float;
  private let m_bar: ref<DFNeedsHUDBar>;
  private let m_barShown: Float;  // -1 = not drawn yet (set on attach)
  private let m_barForced: Float = 1.0;
  private let m_barEmpty: Float;
  private let m_barAt: Float;
  private let m_hudTimer: Float;
  private let m_logTimer: Float;
  private let m_activity: String;
  private let m_speed: Float;
  private let m_staminaPct: Float;
  private let m_staminaMax: Float;
  private let m_factor: Float = 1.0;

  // Current sway factor (1.0 = none); read by the weapon handling wrap below.
  public let m_sway: Float = 1.0;

  // Event log state.
  private let m_logBuf: array<String>;
  private let m_logFlushAt: Float;
  private let m_logDropped: Int32;
  private let m_logSummaryAt: Float;
  private let m_lastActivity: String;
  private let m_lastBand: Int32;
  private let m_lastFactorLogged: Float = 1.0;
  private let m_lastCapLogged: Float;
  private let m_capNextAt: Float; // tick-fix 2026-11-22: next time the capacity block (Body, needs, chest) is recomputed
  private let m_draining: Bool;
  private let m_waiting: Bool;
  private let m_waitStartedAt: Float;
  private let m_waitActivity: String;

  public static func Get(gi: GameInstance) -> ref<CyberslopEndurance> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(NameOf<CyberslopEndurance>()) as CyberslopEndurance;
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnAttach() -> Void {
    ModSettings.RegisterListenerToClass(this);
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnDetach() -> Void {
    ModSettings.UnregisterListenerToClass(this);
  }

  private final func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) {
      return;
    }
    this.m_player = player;
    this.m_first = true;
    this.m_lastStaminaPct = -1.0;
    this.m_applied = 1.0;
    this.m_staminaMod = null;
    this.m_regenMod = null;
    this.m_sway = 1.0;
    this.m_swaySent = 1.0;
    this.m_breathingOn = false;
    this.m_breathCleanUntil = this.Now() + 5.0;
    this.m_bar = null;
    this.m_barShown = -1.0;
    this.m_barEmpty = -1.0;
    this.m_hudTimer = 0.0;
    this.m_logTimer = 0.0;
    this.m_lastTime = this.Now();
    this.m_logFlushAt = this.m_lastTime;
    this.m_logSummaryAt = this.m_lastTime;
    this.m_lastActivity = "";
    this.m_lastBand = 5;
    this.m_lastFactorLogged = 1.0;
    this.m_lastCapLogged = 0.0;
    this.m_draining = false;
    this.m_waiting = false;
    this.Schedule(0.5);
  }

  private final func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.CancelTick();
    if IsDefined(this.m_player) {
      this.RemoveStaminaMods();
      this.StopBreathing(true);
      this.Log("player detached");
      this.FlushLog(true);
    }
    this.m_player = null;
    this.m_bar = null;
  }

  // ---------------------------------------------------------------- tick

  private final func Now() -> Float {
    return EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
  }

  private final func Schedule(delay: Float) -> Void {
    let cb: ref<EnduranceTick> = new EnduranceTick();
    cb.system = this;
    this.m_tickId = GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delay, false);
  }

  private final func CancelTick() -> Void {
    GameInstance.GetDelaySystem(this.GetGameInstance()).CancelCallback(this.m_tickId);
  }

  // ---------------------------------------------------------------- event log (buffered, capped)

  private final func Log(text: String) -> Void {
    if !this.log {
      return;
    }
    if ArraySize(this.m_logBuf) >= 60 {
      this.m_logDropped += 1;
      return;
    }
    ArrayPush(this.m_logBuf, "[Endurance] t=" + FloatToStringPrec(this.m_lastTime, 1) + " " + text);
  }

  private final func FlushLog(force: Bool) -> Void {
    let n: Int32 = ArraySize(this.m_logBuf);
    if n == 0 {
      return;
    }
    if !force && n < 40 && this.m_lastTime - this.m_logFlushAt < 5.0 {
      return;
    }
    let i: Int32 = 0;
    while i < n {
      FTLog(this.m_logBuf[i]);
      i += 1;
    }
    ArrayClear(this.m_logBuf);
    if this.m_logDropped > 0 {
      FTLog("[Endurance] " + IntToString(this.m_logDropped) + " log lines dropped (cap 60 per flush)");
      this.m_logDropped = 0;
    }
    this.m_logFlushAt = this.m_lastTime;
  }

  private final func Band(o: Float) -> Int32 {
    if o <= 0.001 {
      return 0;
    }
    if o < 0.10 {
      return 1;
    }
    if o < 0.25 {
      return 2;
    }
    if o < 0.50 {
      return 3;
    }
    if o < 0.75 {
      return 4;
    }
    return 5;
  }

  private final func BandName(b: Int32) -> String {
    if b == 0 {
      return "0 %";
    }
    if b == 1 {
      return "under 10 %";
    }
    if b == 2 {
      return "10-25 %";
    }
    if b == 3 {
      return "25-50 %";
    }
    if b == 4 {
      return "50-75 %";
    }
    return "over 75 %";
  }

  private final func Status() -> String {
    return "oxygen " + FloatToStringPrec(this.m_oxygen, 1) + "/" + FloatToStringPrec(this.m_capacity, 1) + ", stamina " + FloatToStringPrec(this.m_staminaPct, 0) + " % of " + FloatToStringPrec(this.m_staminaMax, 0) + ", " + this.m_activity + " " + FloatToStringPrec(this.m_speed, 1) + " m/s";
  }

  public final func OnTick() -> Void {
    if !IsDefined(this.m_player) {
      return;
    }
    let gi: GameInstance = this.GetGameInstance();
    let now: Float = this.Now();
    let dt: Float = now - this.m_lastTime;
    this.m_lastTime = now;
    let jump: Bool = this.m_first || dt > 5.0 || dt < 0.0;
    this.m_first = false;
    dt = ClampF(dt, 0.0, 0.5);

    // 1.3.1: BreathingHeavy has no duration and is savable, so a save made while V was out of breath loads with the
    // sway on and nothing owns it (this system and Dark Future both start with their breathing flag off). For the
    // first 5 s after an attach, remove it unless this system turned it on itself.
    if now < this.m_breathCleanUntil && !this.m_breathingOn && StatusEffectSystem.ObjectHasStatusEffect(this.m_player, t"BaseStatusEffect.BreathingHeavy") {
      StatusEffectHelper.RemoveStatusEffect(this.m_player, t"BaseStatusEffect.BreathingHeavy");
      this.Log("heavy breathing from the save removed after the load");
    }

    if !this.enabled {
      this.Schedule(1.0);
      this.Disabled(gi);
      return;
    }
    this.Schedule(0.1);

    let stats: ref<StatsSystem> = GameInstance.GetStatsSystem(gi);
    let id: StatsObjectID = Cast<StatsObjectID>(this.m_player.GetEntityID());

    // Capacity: Body bonus x well-being.
    // tick-fix 2026-11-22: Body, the three Dark Future needs and chest injuries change over minutes; recompute every 2 s
    // (and on the first tick / a load / a time skip). Stamina and drain math below still run at 10 Hz on the cached values.
    let body: Float = 0.0;
    if jump || now >= this.m_capNextAt || now < this.m_capNextAt - 2.0 {
      this.m_capNextAt = now + 2.0;
      body = stats.GetStatValue(id, gamedataStatType.Strength);
      this.m_healthy = 100.0 * (1.0 + 0.30 * ClampF((body - 3.0) / 17.0, 0.0, 1.0));
      this.UpdateNeeds(gi);
      this.m_capacity = this.m_healthy * MaxF(0.30, this.m_capMult * CEN_ChestMult(gi));
    }
    if jump {
      // First tick, a load or a time skip (sleep): start full.
      this.m_oxygen = this.m_capacity;
      this.m_waitUntil = now;
      this.m_lastStaminaPct = -1.0;
      this.m_lastBand = 5;
      this.m_lastCapLogged = this.m_capacity;
      this.m_draining = false;
      this.m_waiting = false;
      this.Log("reset to full (" + (dt > 5.0 ? "gap " + FloatToStringPrec(dt, 0) + " s: load or time skip" : "attach") + "): capacity " + FloatToStringPrec(this.m_capacity, 1) + " (healthy " + FloatToStringPrec(this.m_healthy, 0) + ", Body " + FloatToStringPrec(body, 0) + ", Reflexes " + FloatToStringPrec(stats.GetStatValue(id, gamedataStatType.Reflexes), 0) + "), needs thirst " + FloatToStringPrec(this.m_needThirst, 0) + " sleep " + FloatToStringPrec(this.m_needSleep, 0) + " hunger " + FloatToStringPrec(this.m_needHunger, 0) + ", mult cap " + FloatToStringPrec(this.m_capMult, 2) + " refill " + FloatToStringPrec(this.m_refillMult, 2) + " wait " + FloatToStringPrec(this.m_waitMult, 2) + "; settings oxygen/stamina " + FloatToStringPrec(this.oxygenPerStamina, 2) + ", drains sprint " + FloatToStringPrec(this.sprintDrain, 1) + " climb " + FloatToStringPrec(this.climbDrain, 1) + " swim " + FloatToStringPrec(this.swimDrain, 1) + " carry " + FloatToStringPrec(this.carryDrain, 1) + ", refill " + FloatToStringPrec(this.restRefill, 1) + "/" + FloatToStringPrec(this.walkRefill, 1) + "/" + FloatToStringPrec(this.runRefill, 1) + ", speeds " + FloatToStringPrec(this.restSpeed, 1) + "/" + FloatToStringPrec(this.walkSpeed, 1) + ", wait " + FloatToStringPrec(this.waitMin, 1) + "-" + FloatToStringPrec(this.waitMax, 1) + " s");
    } else {
      if AbsF(this.m_capacity - this.m_lastCapLogged) >= 2.0 {
        this.Log("capacity " + FloatToStringPrec(this.m_lastCapLogged, 1) + " -> " + FloatToStringPrec(this.m_capacity, 1) + " (thirst " + FloatToStringPrec(this.m_needThirst, 0) + " sleep " + FloatToStringPrec(this.m_needSleep, 0) + " hunger " + FloatToStringPrec(this.m_needHunger, 0) + ", mult cap " + FloatToStringPrec(this.m_capMult, 2) + " refill " + FloatToStringPrec(this.m_refillMult, 2) + " wait " + FloatToStringPrec(this.m_waitMult, 2) + ")");
        this.m_lastCapLogged = this.m_capacity;
      }
    }
    if this.m_oxygen > this.m_capacity {
      this.m_oxygen = this.m_capacity;
    }

    // Stamina spent since the last tick (pools are kept in %, so our own max-stamina modifier doesn't show as spending).
    let pools: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(gi);
    this.m_staminaPct = pools.GetStatPoolValue(id, gamedataStatPoolType.Stamina, true);
    this.m_staminaMax = stats.GetStatValue(id, gamedataStatType.Stamina);
    let spent: Float = 0.0;
    if this.m_lastStaminaPct >= 0.0 && this.m_staminaPct < this.m_lastStaminaPct {
      spent = (this.m_lastStaminaPct - this.m_staminaPct) / 100.0 * this.m_staminaMax;
    }
    this.m_lastStaminaPct = this.m_staminaPct;

    // Activity: steady drain or refill rate, in % of the healthy capacity per second.
    let bb: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gi).GetLocalInstanced(this.m_player.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
    let def: ref<PlayerStateMachineDef> = GetAllBlackboardDefs().PlayerStateMachine;
    let loco: Int32 = IsDefined(bb) ? bb.GetInt(def.LocomotionDetailed) : 0;
    let carrying: Bool = IsDefined(bb) ? bb.GetBool(def.Carrying) : false;
    let swimming: Int32 = IsDefined(bb) ? bb.GetInt(def.Swimming) : 0;
    let mounted: Bool = VehicleComponent.IsMountedToVehicle(gi, this.m_player);
    this.m_speed = Vector4.Length2D(this.m_player.GetVelocity());
    let drainRate: Float = 0.0;
    let refillRate: Float = 0.0;
    if mounted {
      refillRate = this.restRefill;
      this.m_activity = "vehicle";
    } else {
      if loco == 4 {
        drainRate = this.sprintDrain;
        this.m_activity = "sprint";
      } else {
        if loco == 30 {
          drainRate = this.crouchSprintDrain;
          this.m_activity = "crouch sprint";
        } else {
          if loco == 8 || loco == 9 || (loco >= 10 && loco <= 13) {
            drainRate = this.climbDrain;
            this.m_activity = loco == 8 ? "climb" : (loco == 9 ? "vault" : "ladder");
          } else {
            if swimming != 0 {
              if this.m_speed >= this.swimFastSpeed {
                drainRate = this.swimDrain;
                this.m_activity = "swim fast";
              } else {
                this.m_activity = "swim";
              }
            } else {
              if this.m_speed < this.restSpeed {
                refillRate = this.restRefill;
                this.m_activity = "rest";
              } else {
                if this.m_speed < this.walkSpeed {
                  refillRate = this.walkRefill;
                  this.m_activity = "walk";
                } else {
                  refillRate = this.runRefill;
                  this.m_activity = "run";
                }
              }
            }
          }
        }
      }
      if carrying {
        drainRate += this.carryDrain;
        refillRate = 0.0;
        this.m_activity = this.m_activity + " + carry";
      }
    }

    // Drain, then the refill wait.
    if NotEquals(this.m_activity, this.m_lastActivity) {
      if NotEquals(this.m_lastActivity, "") {
        this.Log("activity " + this.m_lastActivity + " -> " + this.m_activity + " (" + FloatToStringPrec(this.m_speed, 1) + " m/s, oxygen " + FloatToStringPrec(this.m_oxygen, 1) + "/" + FloatToStringPrec(this.m_capacity, 1) + ", stamina " + FloatToStringPrec(this.m_staminaPct, 0) + " %, drain " + FloatToStringPrec(drainRate, 1) + " refill " + FloatToStringPrec(refillRate, 1) + " %/s)");
      }
      this.m_lastActivity = this.m_activity;
    }
    let drain: Float = spent * this.oxygenPerStamina + drainRate / 100.0 * this.m_healthy * dt;
    if drain > 0.0 {
      if !this.m_draining {
        this.m_draining = true;
        this.Log("drain started: " + this.Status() + (spent > 0.0 ? ", stamina spent " + FloatToStringPrec(spent, 1) + " pts" : ""));
      }
      this.m_oxygen = MaxF(0.0, this.m_oxygen - drain);
      let depth: Float = 1.0 - this.m_oxygen / MaxF(1.0, this.m_capacity);
      let reflexes: Float = stats.GetStatValue(id, gamedataStatType.Reflexes);
      let reflexMult: Float = 1.0 - 0.25 * ClampF((reflexes - 3.0) / 17.0, 0.0, 1.0);
      let delayStat: Float = MaxF(0.0, stats.GetStatValue(id, gamedataStatType.StaminaRegenStartDelay));
      this.m_lastWait = (this.waitMin + (this.waitMax - this.waitMin) * ClampF(depth, 0.0, 1.0)) * reflexMult * (1.0 + delayStat) * this.m_waitMult;
      this.m_waitUntil = now + this.m_lastWait;
    } else {
      if this.m_draining {
        this.m_draining = false;
        this.m_waiting = true;
        this.m_waitStartedAt = now;
        this.m_waitActivity = this.m_activity;
        this.Log("drain ended: " + this.Status() + ", wait " + FloatToStringPrec(this.m_lastWait, 1) + " s (depth " + FloatToStringPrec(1.0 - this.m_oxygen / MaxF(1.0, this.m_capacity), 2) + ", delay stat " + FloatToStringPrec(stats.GetStatValue(id, gamedataStatType.StaminaRegenStartDelay), 2) + ", wait mult " + FloatToStringPrec(this.m_waitMult, 2) + ")");
      }
      if refillRate > 0.0 && now >= this.m_waitUntil && this.m_oxygen < this.m_capacity {
        if this.m_waiting {
          this.m_waiting = false;
          this.Log("refill started after " + FloatToStringPrec(now - this.m_waitStartedAt, 1) + " s (" + this.m_waitActivity + " -> " + this.m_activity + "): rate " + FloatToStringPrec(refillRate, 1) + " %/s x " + FloatToStringPrec(0.6 + 0.8 * (1.0 - this.m_oxygen / MaxF(1.0, this.m_capacity)), 2) + " deficit x " + FloatToStringPrec(this.m_refillMult, 2) + " well-being, " + this.Status());
        }
        let deficit: Float = 1.0 - this.m_oxygen / MaxF(1.0, this.m_capacity);
        this.m_oxygen = MinF(this.m_capacity, this.m_oxygen + refillRate / 100.0 * this.m_capacity * (0.6 + 0.8 * deficit) * this.m_refillMult * dt);
        if this.m_oxygen >= this.m_capacity {
          this.Log("oxygen full again: " + this.Status());
        }
      }
    }

    // Effects keyed on the fill ratio of the (well-being shrunk) tank.
    let o: Float = this.m_oxygen / MaxF(1.0, this.m_capacity);
    let band: Int32 = this.Band(o);
    if band != this.m_lastBand {
      this.Log("oxygen " + (band < this.m_lastBand ? "down to " : "up to ") + this.BandName(band) + ": " + this.Status());
      this.m_lastBand = band;
    }
    this.m_factor = 1.0 - (1.0 - this.staminaAtEmpty) * ClampF((0.5 - o) / 0.5, 0.0, 1.0);
    if AbsF(this.m_factor - this.m_lastFactorLogged) >= 0.05 || (this.m_factor >= 0.995 && this.m_lastFactorLogged < 0.995) {
      this.Log("stamina factor " + FloatToStringPrec(this.m_lastFactorLogged, 2) + " -> " + FloatToStringPrec(this.m_factor, 2) + " (max stamina " + FloatToStringPrec(this.m_staminaMax, 0) + " before this tick)");
      this.m_lastFactorLogged = this.m_factor;
    }
    this.ApplyStaminaFactor(stats, id, this.m_factor);
    this.m_sway = 1.0 + (this.swayAtEmpty - 1.0) * ClampF((0.25 - o) / 0.25, 0.0, 1.0);
    if AbsF(this.m_sway - this.m_swaySent) >= 0.05 || (this.m_sway <= 1.001 && this.m_swaySent > 1.001) {
      this.SendHandlingUpdate();
    }
    if this.breathing && o < 0.25 {
      this.StartBreathing(now, o, bb, def);
    } else {
      this.StopBreathing(false);
    }

    // HUD.
    this.m_hudTimer -= dt;
    if this.m_hudTimer <= 0.0 {
      this.m_hudTimer = 1.0;
      this.EnsureBar(gi);
    }
    this.UpdateBar(now, false);

    // Log: summary every 10 s while oxygen moves (2 s snapshot with Verbose), then flush.
    if this.log {
      let moving: Bool = this.m_oxygen < this.m_capacity - 0.01 || drain > 0.0;
      let period: Float = this.logVerbose ? 2.0 : 10.0;
      if moving && now - this.m_logSummaryAt >= period {
        this.m_logSummaryAt = now;
        let wait: String = now < this.m_waitUntil ? FloatToStringPrec(this.m_waitUntil - now, 1) + " s left" : "over";
        if this.logVerbose {
          this.Log("snapshot " + this.Status() + " (healthy " + FloatToStringPrec(this.m_healthy, 0) + "), needs thirst " + FloatToStringPrec(this.m_needThirst, 0) + " sleep " + FloatToStringPrec(this.m_needSleep, 0) + " hunger " + FloatToStringPrec(this.m_needHunger, 0) + ", mult cap " + FloatToStringPrec(this.m_capMult, 2) + " refill " + FloatToStringPrec(this.m_refillMult, 2) + " wait " + FloatToStringPrec(this.m_waitMult, 2) + ", wait " + wait + ", factor " + FloatToStringPrec(this.m_factor, 2) + ", sway x" + FloatToStringPrec(this.m_sway, 2) + ", spent " + FloatToStringPrec(spent, 1) + " pts, drain rate " + FloatToStringPrec(drainRate, 1) + " refill rate " + FloatToStringPrec(refillRate, 1) + ", loco " + IntToString(loco) + " swim " + IntToString(swimming) + (carrying ? " carrying" : "") + (mounted ? " mounted" : ""));
        } else {
          this.Log("summary " + this.Status() + ", wait " + wait + ", factor " + FloatToStringPrec(this.m_factor, 2) + ", sway x" + FloatToStringPrec(this.m_sway, 2) + ", breathing " + (this.m_breathingOn ? "on" : "off"));
        }
      }
      this.FlushLog(false);
    }
  }

  // Mod switched off: everything back to neutral, bar full.
  private final func Disabled(gi: GameInstance) -> Void {
    if this.m_factor < 1.0 || this.m_swaySent > 1.001 || this.m_breathingOn {
      this.Log("mod disabled in settings: oxygen full, modifiers removed");
    }
    this.m_oxygen = this.m_capacity;
    this.m_lastStaminaPct = -1.0;
    this.m_factor = 1.0;
    this.RemoveStaminaMods();
    this.m_sway = 1.0;
    if this.m_swaySent > 1.001 {
      this.SendHandlingUpdate();
    }
    this.StopBreathing(false);
    this.EnsureBar(gi);
    this.UpdateBar(this.m_lastTime, true);
  }

  // ---------------------------------------------------------------- well-being

  // Penalty share at need value v: Pmax x ((T - v) / T)^1.5, 0 at or above the threshold T.
  private final func Penalty(pmax: Float, threshold: Float, value: Float) -> Float {
    return pmax / 100.0 * PowF(ClampF((threshold - value) / threshold, 0.0, 1.0), 1.5);
  }

  private final func UpdateNeeds(gi: GameInstance) -> Void {
    let v: Float;
    let hydration: ref<DFHydrationSystem> = DFHydrationSystem.GetInstance(gi);
    if IsDefined(hydration) {
      v = hydration.GetNeedValue();
      if v >= 0.0 { this.m_needThirst = v; }
    }
    let energy: ref<DFEnergySystem> = DFEnergySystem.GetInstance(gi);
    if IsDefined(energy) {
      v = energy.GetNeedValue();
      if v >= 0.0 { this.m_needSleep = v; }
    }
    let nutrition: ref<DFNutritionSystem> = DFNutritionSystem.GetInstance(gi);
    if IsDefined(nutrition) {
      v = nutrition.GetNeedValue();
      if v >= 0.0 { this.m_needHunger = v; }
    }
    // Capacity: thirst 30 / sleep 30 / hunger 20 at 0 (settings). Refill: thirst 40 / sleep 25 / hunger 15.
    // Wait: thirst +25 / sleep +40. The refill and wait figures follow the capacity settings in those ratios.
    let tCap: Float = this.Penalty(this.thirstPenalty, 75.0, this.m_needThirst);
    let sCap: Float = this.Penalty(this.sleepPenalty, 75.0, this.m_needSleep);
    let hCap: Float = this.Penalty(this.hungerPenalty, 50.0, this.m_needHunger);
    this.m_capMult = MaxF(0.45, (1.0 - tCap) * (1.0 - sCap) * (1.0 - hCap));
    let tRef: Float = this.Penalty(this.thirstPenalty * 4.0 / 3.0, 75.0, this.m_needThirst);
    let sRef: Float = this.Penalty(this.sleepPenalty * 5.0 / 6.0, 75.0, this.m_needSleep);
    let hRef: Float = this.Penalty(this.hungerPenalty * 3.0 / 4.0, 50.0, this.m_needHunger);
    this.m_refillMult = MaxF(0.40, (1.0 - tRef) * (1.0 - sRef) * (1.0 - hRef));
    // 1.3.2 (2026-11-26): Cyberslop Merc Stims oxygen drugs (Respirocyte, Bronchodilator) via status effect tags,
    // no dependency on that mod: CyberslopOxygen.Cap = capacity x1.3, CyberslopOxygen.Refill = refill x1.3.
    if IsDefined(this.m_player) {
      if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.m_player, n"CyberslopOxygen.Cap") { this.m_capMult *= 1.3; }
      if StatusEffectSystem.ObjectHasStatusEffectWithTag(this.m_player, n"CyberslopOxygen.Refill") { this.m_refillMult *= 1.3; }
    }
    let tWait: Float = this.Penalty(this.thirstPenalty * 5.0 / 6.0, 75.0, this.m_needThirst);
    let sWait: Float = this.Penalty(this.sleepPenalty * 4.0 / 3.0, 75.0, this.m_needSleep);
    this.m_waitMult = (1.0 + tWait) * (1.0 + sWait);
  }

  // ---------------------------------------------------------------- low oxygen: stamina

  private final func ApplyStaminaFactor(stats: ref<StatsSystem>, id: StatsObjectID, f: Float) -> Void {
    let neutral: Bool = f >= 0.995;
    if neutral && !IsDefined(this.m_staminaMod) {
      this.m_applied = 1.0;
      return;
    }
    if !neutral && AbsF(f - this.m_applied) <= 0.01 {
      return;
    }
    this.RemoveStaminaMods();
    if !neutral {
      this.m_staminaMod = RPGManager.CreateStatModifier(gamedataStatType.Stamina, gameStatModifierType.Multiplier, f);
      this.m_regenMod = RPGManager.CreateStatModifier(gamedataStatType.StaminaRegenRate, gameStatModifierType.Multiplier, f);
      stats.AddModifier(id, this.m_staminaMod);
      stats.AddModifier(id, this.m_regenMod);
      this.m_applied = f;
    } else {
      this.m_applied = 1.0;
    }
  }

  private final func RemoveStaminaMods() -> Void {
    if !IsDefined(this.m_player) {
      return;
    }
    let stats: ref<StatsSystem> = GameInstance.GetStatsSystem(this.GetGameInstance());
    let id: StatsObjectID = Cast<StatsObjectID>(this.m_player.GetEntityID());
    if IsDefined(this.m_staminaMod) {
      stats.RemoveModifier(id, this.m_staminaMod);
      this.m_staminaMod = null;
    }
    if IsDefined(this.m_regenMod) {
      stats.RemoveModifier(id, this.m_regenMod);
      this.m_regenMod = null;
    }
    this.m_applied = 1.0;
  }

  // ---------------------------------------------------------------- low oxygen: sway and breathing

  // Re-runs the vanilla handling update (and our wrap below) so the weapon picks up the new sway factor.
  private final func SendHandlingUpdate() -> Void {
    let evt: ref<UpdateEquippedWeaponsHandlingEvent> = new UpdateEquippedWeaponsHandlingEvent();
    evt.currentStaminaValue = this.m_staminaPct / 100.0;
    this.m_player.QueueEvent(evt);
    this.Log("sway x" + FloatToStringPrec(this.m_swaySent, 2) + " -> x" + FloatToStringPrec(this.m_sway, 2));
    this.m_swaySent = this.m_sway;
  }

  // Scales one handling group of the held weapon (called from the wrap below). Vanilla re-sets every value from its
  // curve on each update, so this never accumulates.
  // 2.5 port: same order as vanilla's PlayerWeaponHandlingModifiers.UpdateModifier (playerWeaponHandler.swift): the
  // one modifier object sits on the right and the left weapon; an empty hand passes an empty id, as vanilla does.
  public final func ScaleGroup(stats: ref<StatsSystem>, rightId: EntityID, leftId: EntityID, group: array<ref<gameConstantStatModifierData>>, factor: Float) -> Void {
    let i: Int32 = 0;
    while i < ArraySize(group) {
      stats.RemoveModifier(Cast<StatsObjectID>(rightId), group[i]);
      stats.RemoveModifier(Cast<StatsObjectID>(leftId), group[i]);
      stats.UncacheModifier(group[i]);
      group[i].value = group[i].value * factor;
      stats.AddModifier(Cast<StatsObjectID>(rightId), group[i]);
      stats.AddModifier(Cast<StatsObjectID>(leftId), group[i]);
      i += 1;
    }
  }

  // Vanilla's heavy-breathing camera (BreathingHeavy: animation only, Dark Future uses it too), its breath sound and
  // the tired weapon stance (AnimFeature_Stamina), the last one only while vanilla's own Exhausted state isn't running.
  private final func StartBreathing(now: Float, o: Float, bb: ref<IBlackboard>, def: ref<PlayerStateMachineDef>) -> Void {
    if !this.m_breathingOn {
      this.m_breathingOn = true;
      this.m_breathSoundAt = now - 100.0;
      this.m_animAt = now - 100.0;
      this.Log("heavy breathing on: " + this.Status());
    }
    if !StatusEffectSystem.ObjectHasStatusEffect(this.m_player, t"BaseStatusEffect.BreathingHeavy") {
      StatusEffectHelper.ApplyStatusEffect(this.m_player, t"BaseStatusEffect.BreathingHeavy");
    }
    if now - this.m_breathSoundAt >= 10.0 {
      this.m_breathSoundAt = now;
      let evt: ref<SoundPlayEvent> = new SoundPlayEvent();
      evt.soundName = n"ono_v_breath_fast";
      this.m_player.QueueEvent(evt);
    }
    if now - this.m_animAt >= 1.0 {
      this.m_animAt = now;
      let exhausted: Bool = IsDefined(bb) && bb.GetInt(def.Stamina) == 2;
      if !exhausted {
        let feature: ref<AnimFeature_Stamina> = new AnimFeature_Stamina();
        feature.staminaValue = this.m_staminaPct / 100.0;
        feature.tiredness = ClampF((0.25 - o) / 0.25, 0.0, 1.0);
        AnimationControllerComponent.ApplyFeature(this.m_player, n"StaminaData", feature);
      }
    }
  }

  private final func StopBreathing(detaching: Bool) -> Void {
    if !this.m_breathingOn {
      return;
    }
    this.m_breathingOn = false;
    this.Log(detaching ? "heavy breathing off (detach)" : "heavy breathing off: " + this.Status());
    StatusEffectHelper.RemoveStatusEffect(this.m_player, t"BaseStatusEffect.BreathingHeavy");
    if !detaching {
      let bb: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).GetLocalInstanced(this.m_player.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
      let exhausted: Bool = IsDefined(bb) && bb.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Stamina) == 2;
      if !exhausted {
        AnimationControllerComponent.ApplyFeature(this.m_player, n"StaminaData", new AnimFeature_Stamina());
      }
    }
  }

  // ---------------------------------------------------------------- exertion costs (called from the wraps below)

  public static func Exert(player: ref<PlayerPuppet>, cost: Float) -> Void {
    if IsDefined(player) && cost > 0.0 {
      PlayerStaminaHelpers.ModifyStamina(player, -cost, true);
    }
  }

  // Logs an exertion: the cost and the stamina before it (the pool change is queued; the next tick shows the result).
  private final func LogExert(kind: String, cost: Float) -> Void {
    if !this.log || !IsDefined(this.m_player) {
      return;
    }
    let pct: Float = GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(Cast<StatsObjectID>(this.m_player.GetEntityID()), gamedataStatPoolType.Stamina, true);
    this.Log("cost " + kind + " " + FloatToStringPrec(cost, 0) + " % stamina (stamina " + FloatToStringPrec(pct, 0) + " % before, oxygen " + FloatToStringPrec(this.m_oxygen, 1) + "/" + FloatToStringPrec(this.m_capacity, 1) + ")");
  }

  public static func OnTakedown(player: ref<PlayerPuppet>) -> Void {
    if !IsDefined(player) {
      return;
    }
    let sys: ref<CyberslopEndurance> = CyberslopEndurance.Get(player.GetGame());
    if IsDefined(sys) && sys.enabled {
      sys.LogExert("takedown", sys.takedownCost);
      CyberslopEndurance.Exert(player, sys.takedownCost);
    }
  }

  public static func OnFinisher(player: ref<PlayerPuppet>) -> Void {
    if !IsDefined(player) {
      return;
    }
    let sys: ref<CyberslopEndurance> = CyberslopEndurance.Get(player.GetGame());
    if IsDefined(sys) && sys.enabled {
      sys.LogExert("finisher", sys.finisherCost);
      CyberslopEndurance.Exert(player, sys.finisherCost);
    }
  }

  public static func OnGrenade(player: ref<PlayerPuppet>) -> Void {
    if !IsDefined(player) {
      return;
    }
    let sys: ref<CyberslopEndurance> = CyberslopEndurance.Get(player.GetGame());
    if IsDefined(sys) && sys.enabled {
      sys.LogExert("grenade", sys.grenadeCost);
      CyberslopEndurance.Exert(player, sys.grenadeCost);
    }
  }

  // A hit that cost the player health: melee 6, strong melee 10, bullets / blasts / thrown 3 (settings). DoTs,
  // quickhacks and effects cost nothing.
  public static func OnPlayerHit(player: ref<PlayerPuppet>, attackData: ref<AttackData>, valuesLost: array<SDamageDealt>) -> Void {
    let sys: ref<CyberslopEndurance> = CyberslopEndurance.Get(player.GetGame());
    if !IsDefined(sys) || !sys.enabled || !IsDefined(attackData) || AttackData.IsDoT(attackData) {
      return;
    }
    let hurt: Bool = false;
    let i: Int32 = 0;
    while i < ArraySize(valuesLost) {
      if Equals(valuesLost[i].affectedStatPool, gamedataStatPoolType.Health) && valuesLost[i].value > 0.0 {
        hurt = true;
      }
      i += 1;
    }
    if !hurt {
      return;
    }
    let attackType: gamedataAttackType = attackData.GetAttackType();
    let cost: Float = 0.0;
    let kind: String = "hit";
    if AttackData.IsStrongMelee(attackType) {
      cost = sys.hitStrongCost;
      kind = "strong melee hit";
    } else {
      if AttackData.IsMelee(attackType) {
        cost = sys.hitMeleeCost;
        kind = "melee hit";
      } else {
        if AttackData.IsRangedOrDirectOrThrown(attackType) {
          cost = sys.hitRangedCost;
          kind = "ranged / blast hit";
        }
      }
    }
    if cost > 0.0 {
      sys.LogExert(kind, cost);
    }
    CyberslopEndurance.Exert(player, cost);
  }

  // ---------------------------------------------------------------- HUD bar (Dark Future's bar classes)

  // Once per second: if Dark Future's HUD slot exists and has no Oxygen bar yet, build it and move the need bars down.
  private final func EnsureBar(gi: GameInstance) -> Void {
    let hud: ref<DFHUDSystem> = DFHUDSystem.GetInstance(gi);
    if !IsDefined(hud) || !IsDefined(hud.DarkFutureWidgetSlot) || !IsDefined(hud.hydrationBar) || !IsDefined(hud.player) {
      return;
    }
    // 2.5 port: Dark Future 3.0 calls its bar slot DarkFutureWidgetSlot (DFHUDSystem.reds)
    let slot: ref<inkCompoundWidget> = hud.DarkFutureWidgetSlot;
    let existing: ref<inkWidget> = slot.GetWidgetByPathName(n"cyberslopOxygenBar");
    if IsDefined(existing) && IsDefined(this.m_bar) {
      return;
    }
    if IsDefined(existing) {
      // A bar from an earlier life of this system: replace it.
      slot.RemoveChild(existing);
    }
    let setup: DFNeedsHUDBarSetupData = DFNeedsHUDBarSetupData(slot, n"cyberslopOxygenBar", r"base\\gameplay\\gui\\common\\stamina_oxygen_bar\\stamina_oxygen_bar.inkatlas", n"oxygen", GetDarkFutureBarColorTheme(DFBarColorThemeName.Aqua), 800.0, 700.0, 0.0, 41.0, true, false);
    this.m_bar = new DFNeedsHUDBar();
    this.m_bar.Init(setup);
    this.m_bar.UpdateShear(!DFSettings.Get().compatibilityProjectE3HUD);

    let group: ref<DFNeedsHUDBarGroup> = new DFNeedsHUDBarGroup();
    group.Init(hud.player, true, true);
    group.AddBarToGroup(this.m_bar);
    // Child of the physical-needs group: shows with the need bars, and on its own when it changes or runs low.
    if IsDefined(hud.hydrationBar.m_barGroup) {
      hud.hydrationBar.m_barGroup.AddGroupToChildren(group);
    }
    group.BarGroupSetupDone();

    // Need bars one row down (41 -> 82), only if they still sit on the original row.
    this.MoveBar(slot, n"hydrationBar");
    this.MoveBar(slot, n"nutritionBar");
    this.MoveBar(slot, n"energyBar");

    this.m_barShown = -1.0;
    this.m_barEmpty = -1.0;
    this.m_barForced = 1.0;
    this.UpdateBar(this.m_lastTime, true);
    this.Log("oxygen bar built under Nerve (need bars moved to row 82 if they were at 41)");
  }

  private final func MoveBar(slot: ref<inkCompoundWidget>, name: CName) -> Void {
    let w: ref<inkWidget> = slot.GetWidgetByPathName(name);
    if IsDefined(w) {
      let t: Vector2 = w.GetTranslation();
      if AbsF(t.Y - 41.0) < 0.5 {
        w.SetTranslation(Vector2(t.X, 82.0));
      }
    }
  }

  // Bar value = oxygen over the healthy capacity; the red segment is the share lost to well-being and chest injuries. Animated updates
  // at most twice a second (DF's change flash and its 50 % / 25 % pulses come with them); a change of 2 % or more
  // shows the bar for a few seconds on its own.
  private final func UpdateBar(now: Float, instant: Bool) -> Void {
    if !IsDefined(this.m_bar) {
      return;
    }
    let empty: Float = ClampF(1.0 - this.m_capacity / MaxF(1.0, this.m_healthy), 0.0, 1.0);
    if AbsF(empty - this.m_barEmpty) > 0.002 {
      this.m_bar.SetProgressEmpty(empty);
      this.m_barEmpty = empty;
    }
    let v: Float = ClampF(this.m_oxygen / MaxF(1.0, this.m_healthy), 0.0, 1.0);
    let delta: Float = AbsF(v - this.m_barShown);
    let due: Bool = this.m_barShown < 0.0 || delta >= 0.01 || (delta >= 0.002 && now - this.m_barAt >= 0.5) || (v >= 0.999 && this.m_barShown < 0.999) || (v <= 0.001 && this.m_barShown > 0.001);
    if !due {
      return;
    }
    let force: Bool = AbsF(v - this.m_barForced) >= 0.02;
    if force {
      this.m_barForced = v;
    }
    this.m_bar.SetForceBright(false);
    this.m_bar.SetProgress(v, force, instant || this.m_barShown < 0.0, false, false);
    this.m_barShown = v;
    this.m_barAt = now;
  }
}

// ---------------------------------------------------------------- wraps

// Takedown / grapple start (KeepDrawingTheLine wraps this too; wraps compose).
@wrapMethod(TakedownBeginEvents)
public func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
  wrappedMethod(stateContext, scriptInterface);
  CyberslopEndurance.OnTakedown(scriptInterface.executionOwner as PlayerPuppet);
}

// Finisher (TDO Kurosawa wraps this too).
@wrapMethod(FinisherAttackEvents)
public final func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
  wrappedMethod(stateContext, scriptInterface);
  CyberslopEndurance.OnFinisher(scriptInterface.executionOwner as PlayerPuppet);
}

// Grenade: the quick throw and the charged throw states (entered when the grenade leaves the hand).
@wrapMethod(CombatGadgetQuickThrowEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
  wrappedMethod(stateContext, scriptInterface);
  CyberslopEndurance.OnGrenade(scriptInterface.executionOwner as PlayerPuppet);
}

@wrapMethod(CombatGadgetChargedThrowEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
  wrappedMethod(stateContext, scriptInterface);
  CyberslopEndurance.OnGrenade(scriptInterface.executionOwner as PlayerPuppet);
}

// Taking a hit (TDO wraps this too). Only real damage, only the player.
@wrapMethod(StatPoolsManager)
public final static func ApplyDamage(hitEvent: ref<gameHitEvent>, forReal: Bool, out valuesLost: array<SDamageDealt>) -> Void {
  wrappedMethod(hitEvent, forReal, valuesLost);
  if forReal && IsDefined(hitEvent) && IsDefined(hitEvent.attackData) {
    let player: ref<PlayerPuppet> = hitEvent.target as PlayerPuppet;
    if IsDefined(player) {
      CyberslopEndurance.OnPlayerHit(player, hitEvent.attackData, valuesLost);
    }
  }
}

// Low oxygen sway: after vanilla sets the recoil / sway / spread groups from its stamina curve, scale the recoil,
// multiplicative sway and spread groups by the oxygen factor (the timeout and additive-sway groups stay vanilla).
// Fires on every stamina change and whenever the oxygen factor moves by 0.05.
@wrapMethod(PlayerWeaponHandlingModifiers)
public final func UpdateEquippedWeaponsHandling(evt: ref<UpdateEquippedWeaponsHandlingEvent>, equippedRightHandWeapon: wref<WeaponObject>, equippedLeftHandWeapon: wref<WeaponObject>) -> Void {
  // 2.5 port: left-hand weapon parameter (playerWeaponHandler.swift)
  wrappedMethod(evt, equippedRightHandWeapon, equippedLeftHandWeapon);
  if !IsDefined(this.m_player) || (!IsDefined(equippedRightHandWeapon) && !IsDefined(equippedLeftHandWeapon)) {
    return;
  }
  let sys: ref<CyberslopEndurance> = CyberslopEndurance.Get(this.m_player.GetGame());
  if !IsDefined(sys) || sys.m_sway <= 1.001 {
    return;
  }
  let factor: Float = Equals(this.m_opSymbol, n"inv") ? 1.0 / sys.m_sway : sys.m_sway;
  let stats: ref<StatsSystem> = GameInstance.GetStatsSystem(this.m_player.GetGame());
  let rightId: EntityID;
  let leftId: EntityID;
  if IsDefined(equippedRightHandWeapon) {
    rightId = equippedRightHandWeapon.GetEntityID();
  }
  if IsDefined(equippedLeftHandWeapon) {
    leftId = equippedLeftHandWeapon.GetEntityID();
  }
  sys.ScaleGroup(stats, rightId, leftId, this.recoilGroup, factor);
  sys.ScaleGroup(stats, rightId, leftId, this.multSwayGroup, factor);
  sys.ScaleGroup(stats, rightId, leftId, this.spreadGroup, factor);
}
