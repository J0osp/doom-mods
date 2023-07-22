// A pseudoitem for giving effects to players and letting them make choices from
// a menu in the process.
// This does very little on its own, but has subclasses specialized for various
// tasks. It exists mostly so that currentEffectGiver in the PerPlayerStats
// passes typechecking.
// Subclasses need to implement:
// - a state that repeatedly calls AwaitChoice(menu) until it succeeds (at which
//   point it will jump to the AwaitChoice state)
// - a Chosen state that will be jumped to once a choice is made
#namespace TFLV;
#debug off

class ::UpgradeGiver : Inventory {
  int chosen;
  array<::Upgrade::BaseUpgrade> candidates;

  Default {
    +Inventory.IgnoreSkill;
    +Inventory.Untossable;
  }

  override void PostBeginPlay() {
    DEBUG("%s PostBeginPlay", self.GetClassName());
    CreateUpgradeCandidates();
    SetStateLabel("ChooseUpgrade");
  }

  virtual void CreateUpgradeCandidates() {}

  override bool HandlePickup(Inventory item) {
    // Does not stack, ever.
    return false;
  }

  void AwaitChoice(string menuname) {
    DEBUG("%s awaitchoice: %s", self.GetClassName(), menuname);
    if (candidates.size() <= 1) {
      // Zero or one options? Skip the menu entirely.
      chosen = 0;
      self.SetStateLabel("Chosen");
      return;
    }
    let stats = ::PerPlayerStats.GetStatsFor(owner);
    if (stats.currentEffectGiver) {
      // Someone else using the menu system.
      return;
    }

    DEBUG("%s claiming menu", self.GetClassName());
    stats.currentEffectGiver = self;
    if (players[consoleplayer].mo == owner) Menu.SetMenu(menuname);
    self.SetStateLabel("AwaitChoice");
  }

  void Choose(int index) {
    DEBUG("%s chosen: %d", self.GetClassName(), index);
    let stats = ::PerPlayerStats.GetStatsFor(owner);
    stats.currentEffectGiver = null;
    chosen = index;
    self.SetStateLabel("Chosen");
  }

  States {
    Spawn:
    AwaitChoice:
      TNT1 A 1;
      LOOP;
  }
}
