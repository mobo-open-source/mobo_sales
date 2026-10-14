import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/form_change_tracker.dart';

void main() {
  late String name;
  late int? category;
  late List<Map<String, Object?>> lines;
  late FormChangeTracker tracker;

  setUp(() {
    name = 'Chair';
    category = 1;
    lines = [
      {'product': 7, 'qty': 2.0},
    ];
    tracker = FormChangeTracker(
      () => {
        'name': name,
        'category': category,
        // Rebuilt on every read, as the doc asks of a real form.
        'lines': [
          for (final l in lines) {...l},
        ],
      },
    );
  });

  test('nothing counts as changed before a baseline is recorded', () {
    expect(tracker.hasBaseline, isFalse);
    name = 'Table';
    expect(tracker.isDirty, isFalse);
  });

  test('a freshly marked form is clean', () {
    tracker.markClean();
    expect(tracker.hasBaseline, isTrue);
    expect(tracker.isDirty, isFalse);
  });

  test(
    'changing a value makes it dirty, and putting it back makes it clean',
    () {
      tracker.markClean();

      name = 'Table';
      expect(tracker.isDirty, isTrue);

      name = 'Chair';
      expect(tracker.isDirty, isFalse);
    },
  );

  test('a value cleared to null, or set from null, is a change', () {
    tracker.markClean();
    category = null;
    expect(tracker.isDirty, isTrue);

    category = 1;
    expect(tracker.isDirty, isFalse);
  });

  test('edits inside a nested list are seen', () {
    tracker.markClean();

    lines[0]['qty'] = 3.0;
    expect(tracker.isDirty, isTrue);

    lines[0]['qty'] = 2.0;
    expect(tracker.isDirty, isFalse);

    lines.add({'product': 8, 'qty': 1.0});
    expect(tracker.isDirty, isTrue);

    lines.removeLast();
    expect(tracker.isDirty, isFalse);

    lines.clear();
    expect(tracker.isDirty, isTrue);
  });

  test('order of list items matters', () {
    lines.add({'product': 8, 'qty': 1.0});
    tracker.markClean();

    lines = lines.reversed.toList();
    expect(tracker.isDirty, isTrue);
  });

  test(
    'the baseline is a copy, so mutating the live list cannot rewrite it',
    () {
      tracker.markClean();

      // Same list object, edited in place — what a form does all the time.
      lines.first['product'] = 99;

      expect(tracker.isDirty, isTrue);
    },
  );

  test('markClean again after a save resets the baseline', () {
    tracker.markClean();
    name = 'Table';
    expect(tracker.isDirty, isTrue);

    tracker.markClean();
    expect(tracker.isDirty, isFalse);

    name = 'Chair';
    expect(tracker.isDirty, isTrue);
  });
}
