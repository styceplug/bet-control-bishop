class PinUtils {
  static const String _suffix = 'BC@Secure#';

  static String encode(String pin) => '$pin$_suffix';
}