import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/company_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the loading state is announced before any work starts', () async {
    final provider = CompanyProvider();
    final states = <bool>[];
    provider.addListener(() => states.add(provider.isLoading));

    final load = provider.initialize();
    expect(
      provider.isLoading,
      isTrue,
      reason: 'the pill must show it is trying the moment it is asked',
    );
    expect(states.first, isTrue);

    await load;
    expect(provider.isLoading, isFalse);
  });

  test(
    'an attempt that fails instantly is still on screen long enough to see',
    () async {
      // With no session stored, the load never reaches the network and finishes
      // in a millisecond or two. Shown for less than a frame, the spinner is
      // invisible and "Tap to retry" looks like a dead button — which is exactly
      // what it looked like.
      final provider = CompanyProvider();

      final startedAt = DateTime.now();
      await provider.initialize();
      final elapsed = DateTime.now().difference(startedAt);

      expect(
        elapsed.inMilliseconds,
        greaterThanOrEqualTo(400),
        reason: 'the loading state must outlast a single frame',
      );
    },
  );

  test(
    'no session is reported as a failed load, not as an empty account',
    () async {
      // Nothing was determined: there is no session yet. Saying "No companies"
      // here states a fact about the account that was never established.
      final provider = CompanyProvider();
      await provider.initialize();

      expect(provider.companies, isEmpty);
      expect(
        provider.loadFailed,
        isTrue,
        reason: 'the pill should offer a retry, not claim there are none',
      );
    },
  );

  test(
    'a retry asked for while one is running is queued, not dropped',
    () async {
      final provider = CompanyProvider();
      var loadsStarted = 0;
      provider.addListener(() {
        if (provider.isLoading) loadsStarted++;
      });

      final first = provider.initialize();
      // Arrives mid-flight. It must not be thrown away: the user asked.
      final second = provider.initialize();
      await Future.wait([first, second]);

      // The queued one runs after the first finishes, so by now a second load
      // has been started on its own.
      expect(
        loadsStarted,
        greaterThanOrEqualTo(2),
        reason: 'the retry that arrived mid-flight has to run too',
      );
    },
  );

  test('clearData leaves no failure claim behind', () async {
    final provider = CompanyProvider();
    await provider.initialize();
    expect(provider.loadFailed, isTrue);

    provider.clearData();
    expect(provider.loadFailed, isFalse);
    expect(provider.companies, isEmpty);
  });
}
