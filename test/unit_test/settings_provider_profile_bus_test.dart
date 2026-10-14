import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/providers/settings_provider.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_services.dart';

/// The name and photo every screen takes from the settings provider (the app
/// bar avatar, the dashboard's fallback) follow an edit made on the profile
/// screens, without anyone calling the provider by hand.
void main() {
  late DataChangeBus bus;
  late MockSettingsService service;
  late SettingsProvider provider;

  /// What the "server" holds for the signed-in user.
  late Map<String, dynamic> server;
  late int reads;

  Future<void> afterDebounce() =>
      Future<void>.delayed(const Duration(milliseconds: 600));

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    bus = DataChangeBus.forTesting();
    service = MockSettingsService();
    server = {'id': 1, 'name': 'Ada', 'image_1920': null};
    reads = 0;
    when(() => service.fetchUserProfile()).thenAnswer((_) async {
      reads++;
      return Map<String, dynamic>.from(server);
    });
    provider = SettingsProvider(settingsService: service, bus: bus);
  });

  tearDown(() => provider.dispose());

  test('a profile edit is read again, and the new name is what it shows', () async {
    await provider.fetchUserProfile();
    expect(provider.userProfile?['name'], 'Ada');
    final before = reads;

    server = {'id': 1, 'name': 'Ada Lovelace', 'image_1920': 'AAAA'};
    bus.profileChanged();
    await afterDebounce();

    expect(reads, before + 1);
    expect(provider.userProfile?['name'], 'Ada Lovelace');
    expect(provider.userProfile?['image_1920'], 'AAAA');
  });

  testWidgets('listeners of the provider are told, so the avatar redraws', (
    tester,
  ) async {
    // The provider announces through a post-frame callback, which asks for no
    // frame itself: with no widgets on screen, one is scheduled by hand.
    Future<void> frame() async {
      tester.binding.scheduleFrame();
      await tester.pump();
    }

    await tester.runAsync(() => provider.fetchUserProfile());
    await frame();
    var notified = 0;
    provider.addListener(() => notified++);

    server = {'id': 1, 'name': 'Grace', 'image_1920': null};
    await tester.runAsync(() async {
      bus.profileChanged();
      await afterDebounce();
    });
    await frame();

    expect(notified, greaterThan(0));
    expect(provider.userProfile?['name'], 'Grace');
  });

  test('a burst of edits is one read', () async {
    await provider.fetchUserProfile();
    final before = reads;

    bus.profileChanged();
    bus.profileChanged();
    bus.profileChanged();
    await afterDebounce();

    expect(reads, before + 1);
  });

  test('changes to other records do not re-read the profile', () async {
    await provider.fetchUserProfile();
    final before = reads;

    bus.productChanged(1);
    bus.quotationChanged(1);
    bus.invoiceChanged(1);
    bus.paymentChanged(1);
    bus.publish(DataEntity.customer, DataChangeKind.updated, id: 1);
    await afterDebounce();

    expect(reads, before);
  });

  test('once disposed, it no longer listens', () async {
    await provider.fetchUserProfile();
    final before = reads;
    provider.dispose();

    bus.profileChanged();
    await afterDebounce();

    expect(reads, before);
    // tearDown disposes again, which a ChangeNotifier forbids: stand in a
    // fresh one so the shared tearDown has something live to close.
    provider = SettingsProvider(settingsService: service, bus: bus);
  });
}
