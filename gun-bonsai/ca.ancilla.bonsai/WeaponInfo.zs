// Info about a single weapon. These are held by the PerPlayerStats and each
// one records information about one of the player's weapons.
// It's also responsible for handling weapon level-ups.
#namespace TFLV;

class ::WeaponInfo : Object play {
  // At the moment "wpn" is used both as a convenient way to remember a reference
  // to the weapon itself, and as the key for the info lookup when the caller has
  // a weapon but not the WeaponInfo.
  // We call it "wpn" rather than "weapon" because ZScript gets super confused
  // if we have both a type and an instance variable in scope with the same name.
  // Sigh.
  Weapon wpn;
  string wpnClass;
  ::PerPlayerStats stats;
  ::Upgrade::UpgradeBag upgrades;
  double XP;
  double maxXP;
  uint level;
  ::LegendoomWeaponInfo ld_info;

  // Called when a new WeaponInfo is created. This should initialize the entire object.
  void Init(Weapon wpn) {
    DEBUG("Initializing WeaponInfo for %s", TAG(wpn));
    upgrades = new("::Upgrade::UpgradeBag");
    ld_info = new("::LegendoomWeaponInfo");
    ld_info.Init(self);
    Rebind(wpn);
    XP = 0;
    level = 0;
    DEBUG("WeaponInfo initialize, class=%s level=%d xp=%d/%d",
        wpnClass, level, XP, maxXP);
  }

  // Called when this WeaponInfo is being reassociated with a new weapon. It
  // should keep most of its stats.
  void Rebind(Weapon wpn) {
    self.wpn = wpn;
    if (self.wpnClass != wpn.GetClassName()) {
      // Rebinding to a weapon of an entirely different type. Reset the attack
      // modality inference counters.
      self.wpnClass = wpn.GetClassName();
      self.ResetTypeInference();
      ::RC.GetRC().Configure(self);
      if (!wpn.bPOWERED_UP || !maxXP)
        // If this is not a PoweredUp weapon, recalculate max XP as well. If it is
        // powered up, assume that we're using the max XP for it's unpowered sister.
        self.maxXP = GetXPForLevel(level+1);
    }
    ld_info.Rebind(self);
  }

  void ToggleUpgrade(uint index) {
    let upgrade = upgrades.upgrades[index];
    upgrade.enabled = !upgrade.enabled;
    if (upgrade.enabled) {
      upgrade.OnActivate(stats, self);
    } else {
      upgrade.OnDeactivate(stats, self);
    }
  }

  void OnActivate() {
    self.upgrades.OnActivate(stats, self);
  }
  void OnDeactivate() {
    self.upgrades.OnDeactivate(stats, self);
  }

  // List of upgrade classes that are unavailable on this weapon, even if they
  // would normally spawn.
  array<string> disabled_upgrades;
  void DisableUpgrades(array<string> upgrades) {
    disabled_upgrades.copy(upgrades);
  }
  bool CanAcceptUpgrade(string upgrade) {
    return disabled_upgrades.find(upgrade) == disabled_upgrades.size();
  }

  // List of classes that this weapon is considered equivalent to.
  array<string> equivalencies;
  void SetEquivalencies(array<string> classes) {
    equivalencies.copy(classes);
  }

  bool IsEquivalentTo(Weapon wpn) {
    let result = wpn.GetClassName() == self.wpnClass
      || equivalencies.find(wpn.GetClassName()) != equivalencies.size();
    DEBUG("Eqv? %s %s -> %d", wpnClass, TAG(wpn), result);
    return result;
  }

  // Given another weapon to look at, determine if this WeaponInfo can be rebound
  // to it. The actual logic used depends on the bonsai_upgrade_binding_mode cvar.
  bool CanRebindTo(Weapon wpn) {
    ::UpgradeBindingMode mode = bonsai_upgrade_binding_mode;

    // SisterWeapon overrides everything else; a weapon and its sister are always
    // considered to share a binding regardless of binding mode.
    if (self.wpn && self.wpn.SisterWeapon == wpn) return true;

    // Can't rebind at all in BIND_WEAPON mode under normal circumstances.
    // As a special case, we will permit rebinds if:
    // - the new weapon has a different class from the old one;
    // - the old weapon no longer exists;
    // - the two classes are marked equivalent in BONSAIRC.
    if (mode == ::BIND_WEAPON) {
      DEBUG("BIND_WEAPON reuse check: orphaned=%d equivalent=%d",
        self.wpn == null, IsEquivalentTo(wpn));
      return
        self.wpnClass != wpn.GetClassName()
        && self.wpn == null
        && IsEquivalentTo(wpn);
    }

    // In class-bound mode, all weapons of the same type share the same WeaponInfo.
    // When you switch weapons, the WeaponInfo for that type gets rebound to the
    // newly wielded weapon.
    if (mode == ::BIND_CLASS) {
      return IsEquivalentTo(wpn);
    }

    // In inheritable weapon-bound mode, a weaponinfo is only reusable if the
    // weapon it was bound to is no longer carried by the player.
    if (mode == ::BIND_WEAPON_INHERITABLE) {
      // We need IsReallyInInventory here because sometimes, for some reason,
      // PlayerPawn.RemoveInventory(i) doesn't set i.owner to null, even though
      // it absolutely should and the source code says it does, and this is most
      // obvious when dealing with Universal Pistol Start.
      return (self.wpn == null || self.wpn.owner == null || !IsReallyInInventory(wpn.owner, self.wpn))
        && self.IsEquivalentTo(wpn);
    }

    ThrowAbortException("Unknown UpgradeBindingMode %d!", mode);
    return false;
  }

  bool IsReallyInInventory(Actor stack, Actor needle) {
    for (Inventory inv = stack.inv; inv; inv = inv.inv) {
      if (inv == needle) return true;
    }
    return false;
  }

  double GetXPForLevel(uint level) const {
    double XP = bonsai_base_level_cost * double(level);
    double mul = 1.0;
    if (IsMelee()) {
      mul = min(mul, bonsai_level_cost_mul_for_melee);
    }
    if (IsWimpy()) {
      mul = min(mul, bonsai_level_cost_mul_for_wimpy);
    }
    DEBUG("GetXPForLevel: level %d -> XP %.1f", level, XP);
    return XP * mul;
  }

  void AddXP(double newXP) {
    if (IsIgnored()) return;
    DEBUG("Adding XP: %.3f + %.3f", XP, newXP);
    XP += newXP;
    DEBUG("XP is now %.3f", XP);
    if (XP >= maxXP && XP - newXP < maxXP) {
      Fanfare();
    }
  }

  void Fanfare() {
    EventHandler.SendNetworkEvent("bonsai-level-up", 1, self.level+1);
    let flash = ::Settings.levelup_flash();
    if (flash) {
      wpn.owner.A_SetBlend(flash, 0.8, 40);
    }
    if (::Settings.levelup_sound() != "") {
      wpn.owner.A_StartSound(::Settings.levelup_sound(), CHAN_AUTO,
        CHANF_OVERLAP|CHANF_UI|CHANF_NOPAUSE|CHANF_LOCAL);
    }
    if (0 <= bonsai_upgrade_choices_per_gun_level && bonsai_upgrade_choices_per_gun_level <= 1) {
      StartLevelUp();
    } else {
      wpn.owner.A_Log(string.format(
        StringTable.Localize("$TFLV_MSG_WEAPON_LEVELUP_READY"),
        wpn.GetTag()),
        true);
    }
  }

  uint CountPendingLevels() {
    uint pending = 0;
    uint xp = self.XP;
    uint maxXP = self.maxXP;
    while (xp >= maxXP) {
      DEBUG("CountPending: xp=%d/%d pending=%d", xp, maxXP, pending);
      xp -= maxXP;
      ++pending;
      maxXP = GetXPForLevel(1+level+pending);
    }
    return pending;
  }

  bool StartLevelUp() {
    if (XP < maxXP) return false;

    let giver = ::WeaponUpgradeGiver(wpn.owner.GiveInventoryType("::WeaponUpgradeGiver"));
    giver.wielded = self;
    giver.nrof = CountPendingLevels();

    return true;
  }

  void RejectLevelUp() {
    // Don't adjust maxXP -- they didn't gain a level.
    XP -= maxXP;
    wpn.owner.A_Log(StringTable.Localize("$TFLV_MSG_LEVELUP_REJECTED"), true);
    if (XP >= maxXP) Fanfare();
    return;
  }

  void FinishLevelUp(::Upgrade::BaseUpgrade upgrade) {
    XP -= maxXP;
    ++level;
    ::PerPlayerStats.GetStatsFor(wpn.owner).AddPlayerXP(1);
    maxXP = GetXPForLevel(level+1);

    if (upgrade) {
      upgrades.AddUpgrade(upgrade).OnActivate(stats, self);
      wpn.owner.A_Log(string.format(
          StringTable.Localize("$TFLV_MSG_WEAPON_LEVELUP"),
          wpn.GetTag(), upgrade.GetName()),
        true);
    }

    if (::Settings.have_legendoom()
        && bonsai_gun_levels_per_ld_effect > 0
        && (level % bonsai_gun_levels_per_ld_effect) == 0) {
      let ldGiver = ::LegendoomEffectGiver(wpn.owner.GiveInventoryType("::LegendoomEffectGiver"));
      ldGiver.info = self.ld_info;
    }
  }
}
