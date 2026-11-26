/// OB Max: no audioplayers backend on Linux. Calls into audioplayers would
/// fail with a MissingPluginException; OB Max never makes them there.
class AudioplayersLinuxDisabled {
  static void registerWith() {}
}
