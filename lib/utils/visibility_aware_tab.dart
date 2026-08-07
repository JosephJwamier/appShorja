/// Implemented by the `State` of a tab that owns something too expensive to
/// keep running while it isn't on screen — a playing video, a timer, a poll.
///
/// Sibling of `RefreshableTab`: that one fires when a tab *becomes* selected,
/// this one brackets visibility on both sides. Both `MainShell` and
/// `MediaHubScreen` keep their children alive in an `IndexedStack`, so
/// without this contract a reel keeps playing — and keeps making noise —
/// behind whatever the user switched to.
///
/// Notifications cascade: `MainShell` calls it on the tab being left/entered,
/// and a host tab (`MediaHubScreen`) forwards it to whichever of its own
/// children is currently showing.
abstract class VisibilityAwareTab {
  /// This tab is no longer the one on screen. Pause everything.
  void onTabHidden();

  /// This tab is on screen again. Resume where [onTabHidden] stopped.
  void onTabVisible();
}
