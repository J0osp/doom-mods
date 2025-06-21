#namespace TFLV::Upgrade;
#debug off

class ::ExplosiveDeath : ::BaseUpgrade {
  override ::UpgradePriority Priority() { return ::PRI_EXPLOSIVE; }

  override void OnKill(PlayerPawn player, Actor shot, Actor target) {
    let aux = ::ExplosiveDeath::Aux(target.Spawn("::ExplosiveDeath::Aux", target.pos));
    aux.weaponspecial = Priority();
    aux.target = player;
    aux.level = level;
    aux.power = (target.SpawnHealth() + abs(target.health)) * (1.0 - 0.8 ** level);
    aux.radius = target.radius;
    DEBUG("Created explosion: level=%d power=%d overkill=%d",
      aux.level, aux.power, abs(target.health));
  }

  override bool IsSuitableForWeapon(TFLV::WeaponInfo info) {
    return !info.IsMelee();
  }

  override void GetTooltipFields(Dictionary fields, uint level) {
    fields.insert("radius", AsPercent(3.0 + 0.5*level));
    fields.insert("damage", AsPercent(1.0 - 0.8**level));
    fields.insert("self-damage", AsPercentDecrease(0.5 ** level));
  }
}

class ::ExplosiveDeath::Aux : Actor {
  uint level;
  uint power;
  uint radius;

  Default {
    PainType "Extreme";
    +NOBLOCKMAP;
    +NOGRAVITY;
  }

  override int DoSpecialDamage(Actor target, int damage, Name damagetype) {
    if (target == self.target) {
      return damage * (0.5 ** self.level);
    }
    return damage;
  }

  States {
    Spawn:
      LEXP B 7 Bright;
      // Delay 1/5th of a second before actually dealing damage, so that chain
      // reactions "ripple" across the room rather than happening in a single frame.
      LEXP C 7 Bright A_Explode(power, radius*(3.0 + level*0.5), XF_HURTSOURCE, false, level*16);
      LEXP D 7 Bright;
      STOP;
  }
}
