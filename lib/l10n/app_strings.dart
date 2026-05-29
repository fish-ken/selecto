/// Immutable lookup table for one locale, loaded from `assets/i18n/<code>.json`.
class AppStrings {
  const AppStrings(this._values);
  final Map<String, String> _values;

  /// Look up [key]; falls back to the key itself if missing. `{name}`
  /// placeholders are replaced from [params].
  String tr(String key, [Map<String, String>? params]) {
    var s = _values[key] ?? key;
    if (params != null) {
      params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    }
    return s;
  }
}
