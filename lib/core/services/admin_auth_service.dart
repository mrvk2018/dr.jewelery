/// Заглушка биометрической авторизации для доступа к админ-панели.
///
/// В будущем здесь будет интеграция с пакетом [local_auth] для проверки
/// Face ID, Touch ID или PIN-кода перед входом владельца в панель управления.
Future<bool> authenticateAdmin() async {
  // TODO(local_auth): заменить на LocalAuthentication().authenticate(...)
  // с localizedReason: 'Подтвердите вход в панель управления'.
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return true;
}
