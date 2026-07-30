/// Implemented by the `State` of any screen sitting inside [MainShell]'s
/// `IndexedStack` — those tabs are created once and kept alive for the whole
/// app session, so their `initState` never runs again when the user switches
/// back to them. [MainShellState] looks up each tab's `State` through a
/// `GlobalKey`, checks it against this interface, and calls [refreshTab]
/// every time that tab becomes the selected one, so switching back to a tab
/// reloads it the same way a freshly-pushed screen would.
abstract class RefreshableTab {
  Future<void> refreshTab();
}
