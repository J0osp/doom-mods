// The fire elemental upgrade tree.
//
// APPRENTICE: INCENDIARY SHOTS
// Burns enemies down to a certain % of health.
// More stacks increase both the burn rate, and the minimum %.
// Stack application depends on damage dealt.
// Leveling increases the softcap.
//
// JOURNEYMAN: BURNING TERROR
//
// Reduces the health % at which fire stops burning. Cannot reduce it to 0 --
// diminishing returns.
//
// MASTER: CONFLAGRATION
// Enemies with sufficient fire stacks on them will spread them to nearby enemies.
// More stacks increases the cap for spread fire.
// Higher levels increase the spread speed and radius.
//
// MASTER: INFERNAL KILN
// Attacking burning enemies gives you a temporary damage/resistance bonus.
#namespace TFLV::Upgrade;
#debug off

// Fire will try to do this proportion of the target's health in damage.
const BASE_FIRE_FACTOR = 0.5;
const HEAT_FACTOR = 0.9;
const DAMAGE_PER_STACK = 4.0; // per dot tick, so multiply by 5 to get DPS

class ::IncendiaryShots : ::ElementalUpgrade {
  override ::UpgradeElement Element() { return ::ELEM_FIRE; }
  override void OnDamageDealt(Actor player, Actor shot, Actor target, int damage) {
    // Apply stacks equal to 20% of damage.
    // Softcap == level -- since fire never burns out we can afford to set it pretty low
    // and gradually turn up the heat.
    ::Dot.GiveStacks(player, target, "::FireDot", damage*0.2, level);
  }

  override void GetTooltipFields(Dictionary fields, uint level) {
    fields.insert("stacks", AsPercent(level*0.2));
    fields.insert("softcap", ""..level);
    fields.insert("cutoff", AsPercent(BASE_FIRE_FACTOR));
  }
}

class ::BurningTerror : ::DotModifier {
  override ::UpgradeElement Element() { return ::ELEM_FIRE; }
  override string DotType() { return "::FireDot"; }

  override void ModifyDot(Actor player, Actor shot, Actor target, int damage, ::Dot dot_item) {
    ::FireDot(dot_item).terror = level;
  }

  override bool IsSuitableForWeapon(TFLV::WeaponInfo info) {
    return HasIntermediatePrereq(info, "::IncendiaryShots");
  }

  override void GetTooltipFields(Dictionary fields, uint level) {
    fields.insert("threshold", AsPercent(1.0 - 0.7**level));
    fields.insert("damage", "+"..level);
  }
}

class ::Conflagration : ::DotModifier {
  override ::UpgradeElement Element() { return ::ELEM_FIRE; }
  override string DotType() { return "::FireDot"; }

  override void ModifyDot(Actor player, Actor shot, Actor target, int damage, ::Dot dot_item) {
    ::FireDot(dot_item).spread = level;
  }

  override bool IsSuitableForWeapon(TFLV::WeaponInfo info) {
    return HasMasteryPrereq(info, "::BurningTerror", "::InfernalKiln");
  }

  override void GetTooltipFields(Dictionary fields, uint level) {
    fields.insert("range", AsPercent(1.0 + level*0.5));
    fields.insert("softcap", ""..level);
  }
}

class ::InfernalKiln : ::ElementalUpgrade {
  override ::UpgradeElement Element() { return ::ELEM_FIRE; }
  double hardness;

  // Dealing damage to a burning enemy adds "kiln points" equal to 1% of the
  // amount of damage dealt times the number of stacks.
  override void OnDamageDealt(Actor player, Actor shot, Actor target, int damage) {
    let softcap = GetSoftcap(level);
    let hardcap = GetHardcap(level);
    DEBUG("Kiln: hardness %f/%d", hardness, softcap);
    double bonus = ::Dot.CountStacks(target, "::FireDot") * GetDamageFactor(level) * damage;
    if (hardness > softcap) {
      bonus *= 1.0 - double(hardness - softcap)/double(hardcap - softcap);
    }
    DEBUG("Kiln: %f -> %f", hardness, hardness + bonus);
    hardness = min(hardcap, hardness + bonus);
  }

  override void Tick(Actor owner) {
    if (hardness > 0) hardness = max(0, hardness - 1.0/35.0);
  }

  override double ModifyDamageDealt(Actor pawn, Actor shot, Actor target, double damage, Name attacktype) {
    // Adds damage ranging from (upgrade level) to (upgrade level * 3)
    // depending on how much buff is stacked.
    if (hardness <= 0) return damage;
    DEBUG("Kiln: %f + %f (%f)", damage, GetDamageBonus(level, hardness), hardness);
    return damage + GetDamageBonus(level, hardness);
  }

  override double ModifyDamageReceived(Actor pawn, Actor shot, Actor attacker, double damage, Name attacktype) {
    // Blocks damage up to level*2, and loses 1 second of time per 10 damage blocked.
    if (hardness <= 0) return damage;
    let block = GetBlock(level);
    DEBUG("Kiln: %f - %f (%f)", damage, block, hardness);
    if (damage > block) {
      hardness = max(0, hardness - block/10.0);
      damage -= block;
    } else {
      hardness = max(0, hardness - (damage-1)/10.0);
      damage = 1;
    }
    return damage;
  }

  override bool IsSuitableForWeapon(TFLV::WeaponInfo info) {
    return HasMasteryPrereq(info, "::BurningTerror", "::Conflagration");
  }

  static double GetDamageFactor(uint level) { return level*0.02; }
  static uint GetSoftcap(uint level) { return 5+level*5; }
  static uint GetHardcap(uint level) { return GetSoftcap(level)*2; }
  static uint GetDamageBonus(uint level, double hardness) {
    if (hardness <= 0) return 0;
    return ceil(level + level * hardness/GetSoftcap(level));
  }
  static uint GetBlock(uint level) { return level * 2; }

  override void GetTooltipFields(Dictionary fields, uint level) {
    fields.insert("hardness", AsPercent(GetDamageFactor(level)));
    fields.insert("softcap", AsSeconds(GetSoftcap(level)*35));
    fields.insert("hardcap", AsSeconds(GetHardcap(level)*35));
    fields.insert("damage", AsRange(GetDamageBonus(level, 1), GetDamageBonus(level, GetHardcap(level))));
    fields.insert("block", ""..GetBlock(level));
  }
}

class ::FireDot : ::Dot {
  bool burning;
  uint terror; // level of Searing Heat upgrade
  uint spread; // level of Conflagration upgrade

  Default {
    DamageType "Fire";
  }

  override string GetParticleColour() {
    static const string hot[] = { "red", "orangered", "orange", "yellow", "lightyellow" };
    static const string cold[] = { "red4", "orangered4", "orange4", "orangered4", "red4" };
    if (burning)
      return hot[random(0,4)];
    else
      return cold[random(0,4)];
  }

  override double GetParticleZV() {
    return 0.1;
  }

  override double GetDamage() {
    double goal = owner.SpawnHealth() * BASE_FIRE_FACTOR * HEAT_FACTOR ** (stacks-1);
    double total_damage = owner.health - goal;

    if (spread > 0)
      SpreadFlames();

    if (total_damage <= 0.0) {
      burning = false;
      if (terror && !owner.bNOFEAR) DoTerror(0);
      return 0.0;
    }

    DEBUG("fire damage, hp=%d, goal=%f, total=%f, damage=%f",
      owner.health, goal, total_damage, clamp(total_damage/10.0, 0.2, stacks));

    burning = true;
    double damage = min(total_damage/10.0+terror/5.0, stacks * DAMAGE_PER_STACK);
    if (terror > 0 && !owner.bNOFEAR) DoTerror(damage);
    return damage;
  }

  // Burning Terror implementation.
  void DoTerror(double damage) {
    // If the target's health is below a certain amount -- which scales with
    // both levels of terror and stacks of fire -- it flees.
    DEBUG("DoTerror: %s health %f", TAG(owner), double(owner.health)/owner.SpawnHealth());
    if (damage > 0.1 && !owner.bFRIGHTENED) {
      let missing_health = 1 - double(owner.health)/owner.SpawnHealth();
      if (missing_health >= 0.7 ** (stacks+terror)) {
        DEBUG("Making %s frightened", TAG(owner));
        owner.bFRIGHTENED = true;
      }
    } else if (owner.bFRIGHTENED && frandom(0.0, 1.0) > 0.95) {
      DEBUG("Making %s unfrightened", TAG(owner));
      owner.bFRIGHTENED = false;
    }
  }

  // Conflagration implementation.
  // Drop a fire-spreading entity that sets everything around it on fire.
  void SpreadFlames() {
    let aux = ::Conflagration::Aux(Spawn("::Conflagration::Aux", owner.pos));
    aux.target = self.target;
    aux.spread = self.spread;
    aux.stacks = self.stacks;
    aux.terror = self.terror;
    aux.range = owner.radius;
  }

  override void CopyFrom(::Dot _src) {
    super.CopyFrom(_src);
    let src = ::FireDot(_src);
    self.terror = max(self.terror, src.terror);
    self.spread = max(self.spread, src.spread);
  }
}

class ::Conflagration::Aux : Actor {
  double stacks;
  uint terror; // level of Burning Terror upgrade
  uint spread; // level of Conflagration upgrade
  uint range; // radius of parent actor

  Default {
    RenderStyle "Translucent";
    Alpha 0.4;
    +NODAMAGETHRUST;
    +NOGRAVITY;
  }

  override void PostBeginPlay() {
    DEBUG("conflagration running");
    self.SetStateLabel("Spawn");
  }

  uint GetRange() {
    DEBUG("GetRange: %d", 32 + spread*16 + stacks);
    return range * (1.0 + 0.5*spread + 0.1*stacks);
  }

  void SpreadTo(Actor target) {
    let fdot = ::FireDot(::Dot.GiveStacks(self.target, target, "::FireDot", 0, 1));
    if (fdot.stacks < self.stacks) {
      fdot.AddStacks(1, spread);
      DEBUG("Transfer: %s with softcap %d -> %.1f stacks", TAG(target), spread, fdot.stacks);
    }
    fdot.terror = max(fdot.terror, self.terror);
    fdot.spread = max(fdot.spread, self.spread - 1);
  }

  void Ignite() {
    Array<Actor> targets;
    TFLV::Util.MonstersInRadius(self, GetRange(), targets);
    for (uint i = 0; i < targets.size(); ++i) {
      SpreadTo(targets[i]);
    }
  }

  States {
    Spawn:
      LFIR G 7 NoDelay Ignite();
      LFIR H 7;
      STOP;
  }
}
