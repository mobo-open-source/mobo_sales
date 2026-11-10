/// Reading a person's name off a scanned business card.
///
/// Cards print a name on its own line, almost always in capitals, with the
/// job title on the line below. A tester scanned one and got
/// "Capslock NIVEDHYA T PYTHON DEVELOPER" in the Name field: the name ran
/// into the job title, and the shouting was kept.
library;

/// A line that reads like a person's name: two or more words of letters,
/// with the apostrophes, hyphens and full stops names really contain.
///
/// Deliberately not `\s` inside the character class — `\s` matches a newline,
/// so a pattern built from it runs straight through the end of the line and
/// swallows whatever is printed underneath, which is how the job title ended
/// up in the Name field.
final RegExp _nameLine = RegExp(
  r"^[A-Za-z][A-Za-z'\-.]*(?: +[A-Za-z][A-Za-z'\-.]*)+$",
);

/// Words that mean the line is a role or a company, not a person.
const Set<String> _notAName = {
  'developer',
  'engineer',
  'manager',
  'director',
  'officer',
  'consultant',
  'designer',
  'analyst',
  'executive',
  'president',
  'founder',
  'ceo',
  'cto',
  'cfo',
  'coo',
  'head',
  'lead',
  'specialist',
  'administrator',
  'accountant',
  'technician',
  'architect',
  'intern',
  'assistant',
  'coordinator',
  'supervisor',
  'representative',
  'partner',
  'owner',
  'ltd',
  'llc',
  'inc',
  'plc',
  'gmbh',
  'pvt',
  'private',
  'limited',
  'company',
  'corporation',
  'solutions',
  'technologies',
  'systems',
  'services',
  'software',
  'group',
  'enterprises',
  'industries',
};

/// Whether [line] names a role or an organisation rather than a person.
bool _describesWorkNotPerson(String line) =>
    line.toLowerCase().split(RegExp(r'\s+')).any(_notAName.contains);

/// The person's name on a scanned card, or null when no line reads like one.
///
/// Each line is judged on its own, so a name can never run into the title
/// beneath it.
String? businessCardName(Iterable<String> lines) {
  for (final raw in lines) {
    final line = raw.trim();
    if (line.length < 3 || !_nameLine.hasMatch(line)) continue;
    if (_describesWorkNotPerson(line)) continue;
    return formatPersonName(line);
  }
  return null;
}

/// A name as a person writes it, from a card that shouts it.
///
/// "NIVEDHYA T" becomes "Nivedhya T"; a name already written normally, or one
/// with deliberate inner capitals like "McNeil" or "O'Brien", is left alone,
/// because only a word in full capitals is being undone here.
String formatPersonName(String raw) {
  final words = raw.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.map(_formatWord).join(' ');
}

String _formatWord(String word) {
  // Leave anything the writer cased themselves: "McNeil", "van", "O'Brien".
  if (word != word.toUpperCase()) return word;
  // A single letter is an initial and stays as it is: "NIVEDHYA T" -> "T".
  if (word.length == 1) return word;
  // Capitalise after each separator, so "JEAN-PAUL" reads "Jean-Paul" and
  // "O'BRIEN" reads "O'Brien".
  final buffer = StringBuffer();
  var startOfPart = true;
  for (final rune in word.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '-' || ch == "'" || ch == '.') {
      buffer.write(ch);
      startOfPart = true;
      continue;
    }
    buffer.write(startOfPart ? ch.toUpperCase() : ch);
    startOfPart = false;
  }
  return buffer.toString();
}

/// The legal and trading words that mark a line as an organisation.
///
/// This part is required, not optional: made optional, the pattern matches
/// any run of five or more letters and fills Company Name with whatever
/// happened to be on the card. Nothing is a company here unless it says so.
final RegExp _companyLine = RegExp(
  r'\b(?:Technologies|Technology|Solutions|Systems|Software|Corporation|'
  r'Corp|Inc|LLC|LLP|Limited|Ltd|Pvt|Private|Group|Associates|Consultancy|'
  r'Consulting|Studio|Studios|Agency|Labs|Laboratories|Networks|Partners|'
  r'Holdings|Enterprises|Enterprise|Company|Industries|Ventures|'
  r'International|PLC|GmbH|SAS|BV|NV|AG|Realty|Properties|Services)\b\.?',
  caseSensitive: false,
);

/// Whether [line] names an organisation rather than a person or a job.
bool looksLikeCompanyLine(String line) =>
    line.trim().length >= 3 &&
    _companyLine.hasMatch(line) &&
    !_looksLikeRole(line);

/// The organisation on a scanned card, or null when no line names one.
///
/// [skip] are lines already claimed by something else — the person's name,
/// their job title — so the same text is never used twice.
String? businessCardCompany(
  Iterable<String> lines, {
  Iterable<String> skip = const [],
}) {
  final taken = skip
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();

  for (final raw in lines) {
    final line = raw.trim();
    if (line.length < 3) continue;
    if (taken.contains(line.toLowerCase())) continue;
    // A job title can carry one of these words too ("Director, Technology").
    if (!looksLikeCompanyLine(line)) continue;
    return line;
  }
  return null;
}

/// Whether [line] reads as somebody's job rather than the company's name.
bool _looksLikeRole(String line) {
  const roles = {
    'developer', 'engineer', 'manager', 'director', 'officer', 'consultant',
    'designer', 'analyst', 'executive', 'president', 'founder', 'ceo', 'cto',
    'cfo', 'coo', 'head', 'lead', 'specialist', 'administrator', 'accountant',
    'technician', 'architect', 'intern', 'assistant', 'coordinator',
    'supervisor', 'representative',
  };
  return line.toLowerCase().split(RegExp(r'[^a-z]+')).any(roles.contains);
}
