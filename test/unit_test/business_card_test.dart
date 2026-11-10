import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/business_card.dart';

/// The Name field takes one line of the card, in sentence case: a looser
/// read sweeps the job title from the next line into the name and keeps the
/// card's own capitals.
void main() {
  group('the name stops at the end of its line', () {
    test('the job title underneath is not part of the name', () {
      const card = [
        'Capslock',
        'NIVEDHYA T',
        'PYTHON DEVELOPER',
        'nivedhya@example.com',
      ];

      expect(businessCardName(card), 'Nivedhya T');
    });

    test('a company line is not mistaken for a person', () {
      const card = [
        'CYBROSYS TECHNOLOGIES',
        'JOHN SMITH',
        'Sales Manager',
      ];

      expect(businessCardName(card), 'John Smith');
    });

    test('a card with no name at all gives none', () {
      const card = ['+91 98765 43210', 'www.example.com', 'hello@example.com'];

      expect(businessCardName(card), isNull);
    });
  });

  group('a name is written, not shouted', () {
    test('capitals become a name', () {
      expect(formatPersonName('NIVEDHYA T'), 'Nivedhya T');
    });

    test('a single letter stays an initial', () {
      expect(formatPersonName('ANNA K M'), 'Anna K M');
    });

    test('a hyphenated name keeps both halves capitalised', () {
      expect(formatPersonName('JEAN-PAUL SARTRE'), 'Jean-Paul Sartre');
    });

    test('an apostrophe does too', () {
      expect(formatPersonName("O'BRIEN"), "O'Brien");
    });

    test('a name already written properly is left alone', () {
      expect(formatPersonName('Ludwig van Beethoven'), 'Ludwig van Beethoven');
    });

    test('deliberate inner capitals survive', () {
      expect(formatPersonName('Ewan McNeil'), 'Ewan McNeil');
    });
  });

  group('the company is a line that says it is one', () {
    // Sean O'Brien's card, as scanned: the Company Name field came back
    // "d4 apostrophe PNG Sean O" because the old pattern made the legal
    // suffix optional and so matched any run of letters.
    const card = [
      "Sean O'Brien",
      'Regional Director',
      'Mobo Sales Pvt. Ltd.',
      'Mobile: +91 98450 44556',
      'sean.obrien@mobosales.com',
      'www.mobosales.com',
      '12 Industrial Estate Road, Bengaluru 560001, India',
    ];

    test('the real company is picked', () {
      expect(
        businessCardCompany(card, skip: ["Sean O'Brien", 'Regional Director']),
        'Mobo Sales Pvt. Ltd.',
      );
    });

    test('the name on that card is still read correctly', () {
      expect(businessCardName(card), "Sean O'Brien");
    });

    test('stray text is not a company', () {
      expect(businessCardCompany(const ['d4 apostrophe PNG Sean O']), isNull);
    });

    test('a job title carrying a company word is not the company', () {
      expect(
        businessCardCompany(const ['Director, Technology']),
        isNull,
        reason: 'that is what the person does, not who they work for',
      );
    });

    test('a card with no company gives none', () {
      expect(
        businessCardCompany(const ['Anna K', 'anna@example.com']),
        isNull,
      );
    });
  });
}
