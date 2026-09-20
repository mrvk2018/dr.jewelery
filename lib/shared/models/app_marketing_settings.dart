/// Глобальные настройки приветственной акции (Facebook / Instagram).
class AppMarketingSettings {
  const AppMarketingSettings({
    required this.welcomeBonusEnabled,
    required this.welcomeBonusAmountKrw,
  });

  final bool welcomeBonusEnabled;
  final int welcomeBonusAmountKrw;

  static const defaults = AppMarketingSettings(
    welcomeBonusEnabled: false,
    welcomeBonusAmountKrw: 0,
  );

  AppMarketingSettings copyWith({
    bool? welcomeBonusEnabled,
    int? welcomeBonusAmountKrw,
  }) {
    return AppMarketingSettings(
      welcomeBonusEnabled: welcomeBonusEnabled ?? this.welcomeBonusEnabled,
      welcomeBonusAmountKrw: welcomeBonusAmountKrw ?? this.welcomeBonusAmountKrw,
    );
  }
}
