import 'package:flutter/foundation.dart';

import '../models/ledger.dart';
import '../services/ledger_service.dart';

/// State for the store dashboard and the book. One instance app-wide so a
/// quick entry written from any screen refreshes the tiles everywhere.
class LedgerProvider extends ChangeNotifier {
  final _service = LedgerService();

  StoreDashboard? dashboard;
  String period = 'month';
  DateTime? customStart;
  DateTime? customEnd;
  bool loadingDashboard = false;
  String? dashboardError;

  List<LedgerContact> contacts = [];
  bool loadingContacts = false;

  /// Bumped after every write so list screens know to refetch.
  int revision = 0;

  Future<void> loadDashboard({String? period, DateTime? start, DateTime? end}) async {
    if (period != null) this.period = period;
    if (period == 'custom') {
      customStart = start;
      customEnd = end;
    }
    loadingDashboard = true;
    dashboardError = null;
    notifyListeners();
    try {
      dashboard = await _service.fetchDashboard(
        period: this.period, start: customStart, end: customEnd);
    } catch (e) {
      dashboardError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loadingDashboard = false;
      notifyListeners();
    }
  }

  Future<void> loadContacts() async {
    loadingContacts = true;
    notifyListeners();
    try {
      contacts = await _service.fetchContacts();
    } catch (_) {
      // Keep whatever we had; the picker shows an empty state if nothing.
    } finally {
      loadingContacts = false;
      notifyListeners();
    }
  }

  /// After any write: dashboard tiles and contact balances are both stale.
  Future<void> refreshAfterWrite() async {
    revision++;
    notifyListeners();
    await Future.wait([loadDashboard(), loadContacts()]);
  }

  void clear() {
    dashboard = null;
    contacts = [];
    dashboardError = null;
    notifyListeners();
  }
}
