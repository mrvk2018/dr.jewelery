import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/database_service.dart';
import '../../features/profile/domain/models/user_profile.dart';
import '../models/feedback_item.dart';

/// Глобальное хранилище обратной связи: память + постоянная база.
class FeedbackController extends ChangeNotifier {
  FeedbackController(this._database);

  final DatabaseService _database;
  final List<FeedbackItem> _messages = [];
  bool _isLoading = false;

  List<FeedbackItem> get messages => List.unmodifiable(_messages);

  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final loaded = await _database.loadFeedback();
      _messages
        ..clear()
        ..addAll(loaded);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> submitMessage({
    required String message,
    required String languageCode,
  }) async {
    final item = FeedbackItem(
      id: 'fb-${DateTime.now().millisecondsSinceEpoch}',
      message: message,
      languageCode: languageCode,
      createdAt: DateTime.now(),
    );

    _messages.insert(0, item);
    notifyListeners();
    await _database.saveFeedback(item);
  }

  void removeMessage(
    String id, {
    UserRole actorRole = UserRole.admin,
  }) {
    final before = _messages.length;
    _messages.removeWhere((item) => item.id == id);
    if (_messages.length == before) return;
    notifyListeners();
    unawaited(_database.deleteFeedback(id, actorRole: actorRole));
  }
}
