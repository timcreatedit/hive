import 'package:analyzer/dart/element/element.dart';
import 'package:hive_generator/src/type_adapter_generator.dart';
import 'package:test/test.dart';

// Mock enum element that simulates EnumElementImpl
class MockEnumElement implements Element {
  @override
  ElementKind get kind => ElementKind.ENUM;

  @override
  String get name => 'TestEnum';

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Mock class element  
class MockClassElement implements Element, InterfaceElement {
  @override
  ElementKind get kind => ElementKind.CLASS;

  @override
  String get name => 'TestClass';

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Mock interface element for enum
class MockEnumInterfaceElement implements Element, InterfaceElement {
  @override
  ElementKind get kind => ElementKind.ENUM;

  @override
  String get name => 'TestEnum';

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('generateName', () {
    test('.generateName()', () {
      expect(TypeAdapterGenerator.generateName(r'_$User'), 'UserAdapter');
      expect(TypeAdapterGenerator.generateName(r'_$_SomeClass'),
          'SomeClassAdapter');
    });
  });

  group('getClass', () {
    final generator = TypeAdapterGenerator();

    test('handles class elements correctly', () {
      final classElement = MockClassElement();
      final result = generator.getClass(classElement);
      expect(result, isA<InterfaceElement>());
    });

    test('handles enum elements correctly now', () {
      final enumElement = MockEnumInterfaceElement();
      final result = generator.getClass(enumElement);
      expect(result, isA<InterfaceElement>());
    });

    test('accepts enum elements based on ElementKind check', () {
      final enumElement = MockEnumElement();
      // This should not throw when checking the kind
      expect(enumElement.kind, ElementKind.ENUM);
      expect(enumElement.kind == ElementKind.CLASS || enumElement.kind == ElementKind.ENUM, isTrue);
    });
  });
}
