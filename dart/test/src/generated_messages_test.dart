import 'dart:convert';
import 'dart:io';

import 'package:cucumber_messages/cucumber_messages.dart';
import 'package:test/test.dart';

void main() {
  group('generated messages', () {
    final schemaDirectory = Directory('../jsonschema/src');

    test('round-trips a maximal envelope with value semantics', () {
      final envelopeSchema = File(
        '${schemaDirectory.path}/Envelope.schema.json',
      );
      final json = _SchemaSampleBuilder(schemaDirectory).build(envelopeSchema);

      final first = Envelope.fromJson(json);
      final second = Envelope.fromJson(json);

      expect(first.toJson(), json);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.toString(), startsWith('Envelope{'));
    });

    test('deserializes every enum value', () {
      expect(AttachmentContentEncoding.values.map((value) => value.value), [
        'IDENTITY',
        'BASE64',
      ]);
      for (final value in AttachmentContentEncoding.values) {
        expect(AttachmentContentEncoding.fromValue(value.value), value);
      }
      for (final value in HookType.values) {
        expect(HookType.fromValue(value.value), value);
      }
      for (final value in PickleStepType.values) {
        expect(PickleStepType.fromValue(value.value), value);
      }
      for (final value in SourceMediaType.values) {
        expect(SourceMediaType.fromValue(value.value), value);
      }
      for (final value in StepDefinitionPatternType.values) {
        expect(StepDefinitionPatternType.fromValue(value.value), value);
      }
      for (final value in StepKeywordType.values) {
        expect(StepKeywordType.fromValue(value.value), value);
      }
      for (final value in TestStepResultStatus.values) {
        expect(TestStepResultStatus.fromValue(value.value), value);
      }
    });

    test('reports each kind of missing required property', () {
      for (final constructor in <void Function()>[
        () => Location.fromJson(const {}),
        () => PickleTableRow.fromJson(const {}),
        () => Duration.fromJson(const {}),
        () => TestCaseFinished.fromJson(const {}),
        () => Feature.fromJson(const {}),
      ]) {
        expect(constructor, throwsA(isA<SchemaViolationException>()));
      }

      expect(
        () => TestCaseFinished.fromJson(const {
          'testCaseStartedId': 'id',
          'timestamp': {'seconds': 0, 'nanos': 0},
        }),
        throwsA(isA<SchemaViolationException>()),
      );

      final exception = SchemaViolationException('invalid schema');
      expect(exception.toString(), 'invalid schema');
    });

    test('distinguishes messages from other values and changed fields', () {
      final first = Duration.fromJson(const {'seconds': 1, 'nanos': 2});
      final second = Duration.fromJson(const {'seconds': 2, 'nanos': 2});

      expect(first == first, isTrue);
      expect(first == Object(), isFalse);
      expect(first == second, isFalse);
    });

    test('round-trips recursive capture groups', () {
      const group = Group(
        children: [Group(start: 1, value: 'child')],
        start: 0,
        value: 'parent',
      );

      expect(Group.fromJson(group.toJson()), group);
    });
  });
}

class _SchemaSampleBuilder {
  _SchemaSampleBuilder(this.schemaDirectory);

  final Directory schemaDirectory;
  final Map<String, Map<String, Object?>> _documents = {};
  final Set<String> _activeReferences = {};

  Map<String, Object?> build(File schemaFile) {
    final document = _readDocument(schemaFile);
    return _sample(document, schemaFile, document) as Map<String, Object?>;
  }

  Object? _sample(
    Map<String, Object?> schema,
    File documentFile,
    Map<String, Object?> document,
  ) {
    final reference = schema[r'$ref'];
    if (reference is String) {
      final parts = reference.split('#');
      final targetFile =
          parts.first.isEmpty
              ? documentFile
              : File(
                '${schemaDirectory.path}/${parts.first.replaceFirst('./', '')}',
              );
      final targetDocument = _readDocument(targetFile);
      final targetSchema =
          parts.length == 1 || parts.last.isEmpty
              ? targetDocument
              : _resolvePointer(targetDocument, parts.last);
      final referenceKey = '${targetFile.absolute.path}#${parts.last}';
      if (!_activeReferences.add(referenceKey)) {
        return _recursiveReference;
      }
      try {
        return _sample(targetSchema, targetFile, targetDocument);
      } finally {
        _activeReferences.remove(referenceKey);
      }
    }

    final enumValues = schema['enum'];
    if (enumValues is List<Object?>) {
      return enumValues.first;
    }

    switch (schema['type']) {
      case 'object':
        final properties = schema['properties'] as Map<String, Object?>? ?? {};
        final sample = <String, Object?>{};
        for (final property in properties.entries) {
          final value = _sample(
            property.value as Map<String, Object?>,
            documentFile,
            document,
          );
          if (!identical(value, _recursiveReference)) {
            sample[property.key] = value;
          }
        }
        return sample;
      case 'array':
        final item = _sample(
          schema['items'] as Map<String, Object?>,
          documentFile,
          document,
        );
        return identical(item, _recursiveReference) ? [] : [item];
      case 'boolean':
        return true;
      case 'integer':
      case 'number':
        return schema['minimum'] ?? 0;
      case 'string':
        return 'value';
      default:
        throw StateError('Unsupported schema: ${jsonEncode(schema)}');
    }
  }

  Map<String, Object?> _readDocument(File file) {
    return _documents.putIfAbsent(
      file.absolute.path,
      () => jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  Map<String, Object?> _resolvePointer(
    Map<String, Object?> document,
    String pointer,
  ) {
    Object? value = document;
    for (final segment in pointer.split('/').skip(1)) {
      final key = Uri.decodeComponent(
        segment.replaceAll('~1', '/').replaceAll('~0', '~'),
      );
      value = (value as Map<String, Object?>)[key];
    }
    return value as Map<String, Object?>;
  }
}

const _recursiveReference = Object();
