/// OBMAX: applied by the server implementations to every views response.
Map<String, dynamic> Function(Map<String, dynamic> response)? userViewsFilter;

abstract class UserViewsApi {
  /// [includeHidden] also returns the views the user hid from My Media, so
  /// rows that ignore that toggle can still see them. Servers without the
  /// parameter return only the visible views.
  Future<Map<String, dynamic>> getUserViews({bool includeHidden = false});
}
