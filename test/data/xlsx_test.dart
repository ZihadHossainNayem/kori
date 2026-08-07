import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/data/io/xlsx.dart';

void main() {
  group('column names', () {
    test('counts like a spreadsheet', () {
      expect(columnName(0), 'A');
      expect(columnName(25), 'Z');
      expect(columnName(26), 'AA');
      expect(columnName(27), 'AB');
      expect(columnName(51), 'AZ');
      expect(columnName(52), 'BA');
      expect(columnName(701), 'ZZ');
      expect(columnName(702), 'AAA');
    });

    test('parses a reference back to an index', () {
      expect(columnIndexOf('A1'), 0);
      expect(columnIndexOf('Z9'), 25);
      expect(columnIndexOf('AA12'), 26);
      expect(columnIndexOf('AAA1'), 702);
      expect(columnIndexOf('1'), isNull);
      expect(columnIndexOf(null), isNull);
    });

    test('round-trips every index it will ever see', () {
      for (var index = 0; index < 800; index++) {
        expect(columnIndexOf('${columnName(index)}1'), index);
      }
    });
  });

  group('round trip', () {
    test('preserves strings, numbers and blanks', () {
      final bytes = encodeXlsx([
        const XlsxSheet(
          name: 'Transactions',
          rows: [
            ['Date', 'Type', 'Amount', 'Note'],
            ['2026-08-07', 'expense', 250.5, 'Lunch'],
            ['2026-08-08', 'income', 4200, null],
          ],
        ),
      ]);

      final sheets = decodeXlsx(bytes);
      expect(sheets, hasLength(1));
      expect(sheets.single.name, 'Transactions');
      expect(sheets.single.rows[0], ['Date', 'Type', 'Amount', 'Note']);
      expect(sheets.single.rows[1], ['2026-08-07', 'expense', 250.5, 'Lunch']);
      // The trailing blank is dropped rather than becoming an empty string.
      expect(sheets.single.rows[2].take(3), ['2026-08-08', 'income', 4200]);
    });

    test('keeps three sheets in order with their names', () {
      final bytes = encodeXlsx([
        const XlsxSheet(name: 'Transactions', rows: [['a']]),
        const XlsxSheet(name: 'Wallets', rows: [['b']]),
        const XlsxSheet(name: 'Categories', rows: [['c']]),
      ]);

      final sheets = decodeXlsx(bytes);
      expect(sheets.map((s) => s.name), ['Transactions', 'Wallets', 'Categories']);
      expect(sheets.map((s) => s.rows.single.single), ['a', 'b', 'c']);
    });

    test('escapes characters that would break the XML', () {
      final nasty = 'Ampersand & <tag> "quoted" \'apostrophe\'';
      final bytes = encodeXlsx([
        XlsxSheet(name: 'S', rows: [[nasty]]),
      ]);

      expect(decodeXlsx(bytes).single.rows.single.single, nasty);
    });

    test('survives non-Latin text and emoji', () {
      const rows = [
        ['বাংলা টাকা', 'ভাত ও তরকারি'],
        ['日本円', 'ラーメン'],
        ['emoji', '☕️🍜'],
      ];
      final bytes = encodeXlsx([const XlsxSheet(name: 'S', rows: rows)]);

      expect(decodeXlsx(bytes).single.rows, rows);
    });

    test('keeps spaces at the edges of a note', () {
      final bytes = encodeXlsx([
        const XlsxSheet(name: 'S', rows: [['  padded  ']]),
      ]);

      expect(decodeXlsx(bytes).single.rows.single.single, '  padded  ');
    });

    test('keeps a sparse row aligned to its columns', () {
      final bytes = encodeXlsx([
        const XlsxSheet(
          name: 'S',
          rows: [
            ['a', null, 'c', null, 'e'],
          ],
        ),
      ]);

      expect(decodeXlsx(bytes).single.rows.single, ['a', null, 'c', null, 'e']);
    });

    test('handles negative and fractional amounts', () {
      final bytes = encodeXlsx([
        const XlsxSheet(name: 'S', rows: [[-1250.75, 0, 0.05]]),
      ]);

      expect(decodeXlsx(bytes).single.rows.single, [-1250.75, 0, 0.05]);
    });

    test('handles a wide sheet past column Z', () {
      final row = [for (var index = 0; index < 30; index++) 'c$index'];
      final bytes = encodeXlsx([XlsxSheet(name: 'S', rows: [row])]);

      expect(decodeXlsx(bytes).single.rows.single, row);
    });
  });

  group('the file it produces', () {
    late Uint8List bytes;

    setUp(() {
      bytes = encodeXlsx([
        const XlsxSheet(name: 'Transactions', rows: [['Date'], ['2026-08-07']]),
        const XlsxSheet(name: 'Wallets', rows: [['Name']]),
      ]);
    });

    test('contains exactly the parts a reader looks for', () {
      final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name);
      expect(
        names,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet2.xml',
        ]),
      );
    });

    test('ships no sharedStrings or styles part', () {
      final names =
          ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toList();
      expect(names, isNot(contains('xl/sharedStrings.xml')));
      expect(names, isNot(contains('xl/styles.xml')));
    });

    test('declares a content type for every sheet', () {
      final archive = ZipDecoder().decodeBytes(bytes);
      final types = utf8.decode(
        archive.files.firstWhere((f) => f.name == '[Content_Types].xml').content,
      );
      expect(types, contains('/xl/worksheets/sheet1.xml'));
      expect(types, contains('/xl/worksheets/sheet2.xml'));
    });

    test('rejects a workbook with no sheets', () {
      expect(() => encodeXlsx([]), throwsArgumentError);
    });

    test('sanitises a sheet name Excel would refuse', () {
      final bytes = encodeXlsx([
        const XlsxSheet(name: 'Bad/Name[With]Chars:*?', rows: [['x']]),
      ]);

      final name = decodeXlsx(bytes).single.name;
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('[')));
      expect(name.length, lessThanOrEqualTo(31));
    });

    test('truncates a sheet name past 31 characters', () {
      final bytes = encodeXlsx([
        XlsxSheet(name: 'x' * 50, rows: const [['v']]),
      ]);

      expect(decodeXlsx(bytes).single.name.length, 31);
    });
  });

  group('reading files from other tools', () {
    test('resolves shared strings', () {
      // What Excel and LibreOffice emit instead of inline strings.
      final archive = Archive()
        ..addFile(_part('[Content_Types].xml', '''
<?xml version="1.0"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'''))
        ..addFile(_part('xl/workbook.xml', '''
<?xml version="1.0"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Imported" sheetId="1" r:id="rId1"/></sheets>
</workbook>'''))
        ..addFile(_part('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="worksheets/sheet1.xml"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"/>
</Relationships>'''))
        ..addFile(_part('xl/sharedStrings.xml', '''
<?xml version="1.0"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Groceries</t></si>
  <si><t>Rickshaw</t></si>
</sst>'''))
        ..addFile(_part('xl/worksheets/sheet1.xml', '''
<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
      <c r="B1"><v>860</v></c>
    </row>
    <row r="2">
      <c r="A2" t="s"><v>1</v></c>
      <c r="B2"><v>15</v></c>
    </row>
  </sheetData>
</worksheet>'''));

      final sheets = decodeXlsx(
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );

      expect(sheets.single.name, 'Imported');
      expect(sheets.single.rows[0], ['Groceries', 860]);
      expect(sheets.single.rows[1], ['Rickshaw', 15]);
    });

    test('refuses something that is not a workbook', () {
      final archive = Archive()..addFile(_part('hello.txt', 'not a workbook'));
      expect(
        () => decodeXlsx(Uint8List.fromList(ZipEncoder().encode(archive))),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

ArchiveFile _part(String name, String content) =>
    ArchiveFile.bytes(name, utf8.encode(content));
