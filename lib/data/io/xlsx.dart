import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// One sheet: a name and a grid of strings, numbers and blanks.
class XlsxSheet {
  const XlsxSheet({required this.name, required this.rows});

  final String name;
  final List<List<Object?>> rows;
}

/// Minimal .xlsx reader and writer.
///
/// An .xlsx is a zip of XML parts, so this needs only `archive` and `xml`. It
/// exists because the one pure-Dart spreadsheet package is years stale and the
/// maintained alternative is proprietary — neither fits a GPL app that should be
/// easy to build.
///
/// Deliberately small: strings are written inline so there is no sharedStrings
/// part, and dates are written as text so there is no styles part or 1900 epoch
/// arithmetic. Reading still accepts shared strings, because other tools emit
/// them.
const _mainNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _relNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkgRelNs = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _ctNs = 'http://schemas.openxmlformats.org/package/2006/content-types';

Uint8List encodeXlsx(List<XlsxSheet> sheets) {
  if (sheets.isEmpty) {
    throw ArgumentError.value(sheets, 'sheets', 'A workbook needs a sheet');
  }

  final archive = Archive()
    ..addFile(_file('[Content_Types].xml', _contentTypes(sheets.length)))
    ..addFile(_file('_rels/.rels', _rootRels()))
    ..addFile(_file('xl/workbook.xml', _workbook(sheets)))
    ..addFile(_file('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length)));

  for (final (index, sheet) in sheets.indexed) {
    archive.addFile(
      _file('xl/worksheets/sheet${index + 1}.xml', _sheet(sheet)),
    );
  }

  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped);
}

/// Reads every sheet. Cells arrive as `String`, `num` or null, and gaps in a
/// sparse row are filled so column positions stay aligned.
List<XlsxSheet> decodeXlsx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  ArchiveFile? find(String name) =>
      archive.files.where((file) => file.name == name).firstOrNull;

  final workbookFile = find('xl/workbook.xml');
  if (workbookFile == null) {
    throw const FormatException('Not an .xlsx file: xl/workbook.xml is missing');
  }

  final sharedStrings = _readSharedStrings(find('xl/sharedStrings.xml'));

  // Sheet order and names come from the workbook; targets from its rels.
  final targets = _readRelTargets(find('xl/_rels/workbook.xml.rels'));
  final workbook = XmlDocument.parse(utf8.decode(workbookFile.content));

  final sheets = <XlsxSheet>[];
  for (final node in workbook.findAllElements('sheet', namespaceUri: '*')) {
    final name = node.getAttribute('name') ?? 'Sheet${sheets.length + 1}';
    final relId = node.getAttribute('id', namespaceUri: _relNs) ??
        node.getAttribute('r:id');
    final target = targets[relId];
    final path = target == null
        ? 'xl/worksheets/sheet${sheets.length + 1}.xml'
        : (target.startsWith('/') ? target.substring(1) : 'xl/$target');

    final sheetFile = find(path);
    if (sheetFile == null) continue;

    sheets.add(
      XlsxSheet(
        name: name,
        rows: _readRows(
          XmlDocument.parse(utf8.decode(sheetFile.content)),
          sharedStrings,
        ),
      ),
    );
  }

  return sheets;
}

ArchiveFile _file(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile.bytes(name, bytes);
}

String _contentTypes(int sheetCount) {
  final builder = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  builder.element(
    'Types',
    attributes: {'xmlns': _ctNs},
    nest: () {
      builder.element('Default', attributes: {
        'Extension': 'rels',
        'ContentType':
            'application/vnd.openxmlformats-package.relationships+xml',
      });
      builder.element('Default', attributes: {
        'Extension': 'xml',
        'ContentType': 'application/xml',
      });
      builder.element('Override', attributes: {
        'PartName': '/xl/workbook.xml',
        'ContentType':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
      });
      for (var index = 1; index <= sheetCount; index++) {
        builder.element('Override', attributes: {
          'PartName': '/xl/worksheets/sheet$index.xml',
          'ContentType':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml',
        });
      }
    },
  );
  return builder.buildDocument().toXmlString();
}

String _rootRels() {
  final builder = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  builder.element(
    'Relationships',
    attributes: {'xmlns': _pkgRelNs},
    nest: () {
      builder.element('Relationship', attributes: {
        'Id': 'rId1',
        'Type': '$_relNs/officeDocument',
        'Target': 'xl/workbook.xml',
      });
    },
  );
  return builder.buildDocument().toXmlString();
}

String _workbook(List<XlsxSheet> sheets) {
  final builder = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  builder.element(
    'workbook',
    attributes: {'xmlns': _mainNs, 'xmlns:r': _relNs},
    nest: () {
      builder.element('sheets', nest: () {
        for (final (index, sheet) in sheets.indexed) {
          builder.element('sheet', attributes: {
            'name': _sheetName(sheet.name),
            'sheetId': '${index + 1}',
            'r:id': 'rId${index + 1}',
          });
        }
      });
    },
  );
  return builder.buildDocument().toXmlString();
}

String _workbookRels(int sheetCount) {
  final builder = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  builder.element(
    'Relationships',
    attributes: {'xmlns': _pkgRelNs},
    nest: () {
      for (var index = 1; index <= sheetCount; index++) {
        builder.element('Relationship', attributes: {
          'Id': 'rId$index',
          'Type': '$_relNs/worksheet',
          'Target': 'worksheets/sheet$index.xml',
        });
      }
    },
  );
  return builder.buildDocument().toXmlString();
}

String _sheet(XlsxSheet sheet) {
  final builder = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  builder.element(
    'worksheet',
    attributes: {'xmlns': _mainNs},
    nest: () {
      builder.element('sheetData', nest: () {
        for (final (rowIndex, row) in sheet.rows.indexed) {
          builder.element(
            'row',
            attributes: {'r': '${rowIndex + 1}'},
            nest: () {
              for (final (columnIndex, value) in row.indexed) {
                if (value == null) continue;
                final ref = '${columnName(columnIndex)}${rowIndex + 1}';
                if (value is num) {
                  builder.element('c', attributes: {'r': ref}, nest: () {
                    builder.element('v', nest: () => builder.text('$value'));
                  });
                } else {
                  builder.element(
                    'c',
                    attributes: {'r': ref, 't': 'inlineStr'},
                    nest: () {
                      builder.element('is', nest: () {
                        builder.element(
                          't',
                          // Keeps leading and trailing spaces in a note.
                          attributes: {'xml:space': 'preserve'},
                          nest: () => builder.text('$value'),
                        );
                      });
                    },
                  );
                }
              }
            },
          );
        }
      });
    },
  );
  return builder.buildDocument().toXmlString();
}

/// Excel rejects these characters in a sheet name, and caps it at 31 chars.
String _sheetName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\[\]\*/\\\?:]'), ' ').trim();
  final safe = cleaned.isEmpty ? 'Sheet' : cleaned;
  return safe.length <= 31 ? safe : safe.substring(0, 31);
}

/// 0 → A, 25 → Z, 26 → AA.
String columnName(int index) {
  var remaining = index;
  final letters = <int>[];
  do {
    letters.insert(0, 65 + remaining % 26);
    remaining = remaining ~/ 26 - 1;
  } while (remaining >= 0);
  return String.fromCharCodes(letters);
}

/// A1 → 0, AA1 → 26. Null when the ref has no column part.
int? columnIndexOf(String? reference) {
  if (reference == null) return null;
  var index = 0;
  var seen = 0;
  for (final code in reference.codeUnits) {
    if (code < 65 || code > 90) break;
    index = index * 26 + (code - 64);
    seen++;
  }
  return seen == 0 ? null : index - 1;
}

List<String> _readSharedStrings(ArchiveFile? file) {
  if (file == null) return const [];
  final document = XmlDocument.parse(utf8.decode(file.content));
  return [
    for (final si in document.findAllElements('si', namespaceUri: '*'))
      si.findAllElements('t', namespaceUri: '*').map((t) => t.innerText).join(),
  ];
}

Map<String, String> _readRelTargets(ArchiveFile? file) {
  if (file == null) return const {};
  final document = XmlDocument.parse(utf8.decode(file.content));
  final targets = <String, String>{};
  for (final node in document.findAllElements('Relationship', namespaceUri: '*')) {
    final id = node.getAttribute('Id');
    if (id != null) targets[id] = node.getAttribute('Target') ?? '';
  }
  return targets;
}

List<List<Object?>> _readRows(XmlDocument sheet, List<String> shared) {
  final rows = <List<Object?>>[];

  for (final row in sheet.findAllElements('row', namespaceUri: '*')) {
    final cells = <Object?>[];
    for (final cell in row.findAllElements('c', namespaceUri: '*')) {
      // Honour the cell reference so a sparse row keeps its columns aligned.
      final column = columnIndexOf(cell.getAttribute('r'));
      if (column != null) {
        while (cells.length < column) {
          cells.add(null);
        }
      }
      cells.add(_readCell(cell, shared));
    }
    rows.add(cells);
  }

  return rows;
}

Object? _readCell(XmlElement cell, List<String> shared) {
  final type = cell.getAttribute('t');

  if (type == 'inlineStr') {
    return cell
        .findAllElements('t', namespaceUri: '*')
        .map((node) => node.innerText)
        .join();
  }

  final value = cell.findElements('v', namespaceUri: '*').firstOrNull ??
      cell.findAllElements('v', namespaceUri: '*').firstOrNull;
  final raw = value?.innerText;
  if (raw == null || raw.isEmpty) return null;

  if (type == 's') {
    final index = int.tryParse(raw);
    return (index != null && index < shared.length) ? shared[index] : null;
  }
  if (type == 'str') return raw;

  return num.tryParse(raw) ?? raw;
}
