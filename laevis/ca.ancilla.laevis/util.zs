#namespace TFLV;
#debug off;

class ::Util : Object {
  static string DebugTag(Actor act) {
    if (!act) return "null";
    return string.format("%s[%p]", act.GetTag(), act);
  }

  static string DebugClass(Class<Actor> cls) {
    if (!cls) return "Class<Null>";
    return string.format("Class<%s>", cls.GetClassName());
  }

  static uint MonstersInRadius(Actor origin, double radius, out Array<Actor> found) {
    BlockThingsIterator it = BlockThingsIterator.Create(origin, radius);
    found.clear();
    DEBUG("MonstersInRadius: start");
    while (it.next()) {
      Actor act = it.thing;
      if (!act || !act.bISMONSTER || act.bFRIENDLY || act.player || act.health <= 0 || origin.Distance3D(act) > radius)
        continue;
      DEBUG("MonstersInRadius: %s", TAG(act));
      found.push(act);
    }
    DEBUG("MonstersInRadius: end");
    return found.size();
  }
}
