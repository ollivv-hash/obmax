import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/obmax/obmax_defaults.dart';
import 'package:moonfin/preference/preference_constants.dart';

void main() {
  test('home rows: fixed rows, then the outside charts, in order', () {
    final shown = [
      for (final c in ObMaxDefaults.homeSections()..sort((a, b) => a.order - b.order))
        if (c.enabled) c.type,
    ];
    expect(shown, [
      HomeSectionType.libraryButtons,
      HomeSectionType.resume,
      HomeSectionType.nextUp,
      HomeSectionType.latestMedia,
      HomeSectionType.justwatchTopMovies,
      HomeSectionType.justwatchTopShows,
      HomeSectionType.mdblistAnticipatedMovies,
      HomeSectionType.tmdbNewDigitalMovies,
    ]);
  });

  // A chart Moonfin adds would show its English title on Home.
  test('every outside chart has a French title', () {
    for (final entry in externalCharts.entries) {
      expect(
        ObMaxDefaults.chartTitle(entry.key, entry.value.title),
        isNot(entry.value.title),
        reason: '${entry.key} has no French title',
      );
    }
  });
}
