// Analyzer 8 marks required replacement element APIs as experimental.
// ignore_for_file: experimental_member_use

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:hive_generator/src/helper.dart';

import 'type_helper.dart';

class ClassBuilder extends Builder {
  ClassBuilder(
    InterfaceElement cls,
    List<AdapterField> getters,
    List<AdapterField> setters,
  ) : super(cls, getters, setters);

  var hiveListChecker = const _TypeMatcher('HiveList', package: 'hive');
  var listChecker = const _TypeMatcher('List', sdk: true);
  var mapChecker = const _TypeMatcher('Map', sdk: true);
  var setChecker = const _TypeMatcher('Set', sdk: true);
  var iterableChecker = const _TypeMatcher('Iterable', sdk: true);
  var uint8ListChecker = const _TypeMatcher('Uint8List', sdk: true);

  @override
  String buildRead() {
    var constr = cls.constructors.firstOrNullWhere((it) => it.name == 'new');
    check(constr != null, 'Provide an unnamed constructor.');

    // The remaining fields to initialize.
    var fields = setters.toList();

    // Empty classes
    if (constr!.formalParameters.isEmpty && fields.isEmpty) {
      return 'return ${cls.name}();';
    }

    var code = StringBuffer();
    code.writeln('''
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++)
        reader.readByte(): reader.read(),
    };
    return ${cls.name}(
    ''');

    for (var param in constr.formalParameters) {
      var field = fields.firstOrNullWhere((it) => it.name == param.name);
      // Final fields
      field ??= getters.firstOrNullWhere((it) => it.name == param.name);
      if (field != null) {
        if (param.isNamed) {
          code.write('${param.name}: ');
        }
        code.write(
          _value(param.type, 'fields[${field.index}]', field.defaultValue),
        );
        code.writeln(',');
        fields.remove(field);
      }
    }

    code.writeln(')');

    // There may still be fields to initialize that were not in the constructor
    // as initializing formals. We do so using cascades.
    for (var field in fields) {
      code.write('..${field.name} = ');
      code.writeln(
        _value(field.type, 'fields[${field.index}]', field.defaultValue),
      );
    }

    code.writeln(';');

    return code.toString();
  }

  String _value(DartType type, String variable, DartObject? defaultValue) {
    var value = _cast(type, variable);
    if (defaultValue?.isNull != false) return value;
    return '$variable == null ? ${constantToString(defaultValue!)} : $value';
  }

  String _cast(DartType type, String variable) {
    var suffix = _suffixFromType(type);
    if (hiveListChecker.isAssignableFromType(type)) {
      return '($variable as HiveList$suffix)$suffix.castHiveList()';
    } else if (iterableChecker.isAssignableFromType(type) &&
        !isUint8List(type)) {
      return '($variable as List$suffix)${_castIterable(type)}';
    } else if (mapChecker.isAssignableFromType(type)) {
      return '($variable as Map$suffix)${_castMap(type)}';
    } else {
      return '$variable as ${_displayString(type)}';
    }
  }

  bool isMapOrIterable(DartType type) {
    return iterableChecker.isAssignableFromType(type) ||
        mapChecker.isAssignableFromType(type);
  }

  bool isUint8List(DartType type) {
    return uint8ListChecker.isExactlyType(type);
  }

  String _castIterable(DartType type) {
    var paramType = type as ParameterizedType;
    var arg = paramType.typeArguments.first;
    var suffix = _accessorSuffixFromType(type);
    if (isMapOrIterable(arg) && !isUint8List(arg)) {
      var cast = '';
      // Using assignable because List? is not exactly List
      if (listChecker.isAssignableFromType(type)) {
        cast = '.toList()';
        // Using assignable because Set? is not exactly Set
      } else if (setChecker.isAssignableFromType(type)) {
        cast = '.toSet()';
      }
      // The suffix is not needed with nnbd on $cast becauuse it short circuits,
      // otherwise it is needed.
      var castWithSuffix = isLibraryNNBD(cls) ? '$cast' : '$suffix$cast';
      return '$suffix.map((dynamic e)=> ${_cast(arg, 'e')})$castWithSuffix';
    } else {
      return '$suffix.cast<${_displayString(arg)}>()';
    }
  }

  String _castMap(DartType type) {
    var paramType = type as ParameterizedType;
    var arg1 = paramType.typeArguments[0];
    var arg2 = paramType.typeArguments[1];
    var suffix = _accessorSuffixFromType(type);
    if (isMapOrIterable(arg1) || isMapOrIterable(arg2)) {
      return '$suffix.map((dynamic k, dynamic v)=>'
          'MapEntry(${_cast(arg1, 'k')},${_cast(arg2, 'v')}))';
    } else {
      return '$suffix.cast<${_displayString(arg1)}, '
          '${_displayString(arg2)}>()';
    }
  }

  @override
  String buildWrite() {
    var code = StringBuffer();
    code.writeln('writer');
    code.writeln('..writeByte(${getters.length})');
    for (var field in getters) {
      var value = _convertIterable(field.type, 'obj.${field.name}');
      code.writeln('''
      ..writeByte(${field.index})
      ..write($value)''');
    }
    code.writeln(';');

    return code.toString();
  }

  String _convertIterable(DartType type, String accessor) {
    if (listChecker.isAssignableFromType(type)) {
      return accessor;
    } else
    // Using assignable because Set? and Iterable? are not exactly Set and
    // Iterable
    if (setChecker.isAssignableFromType(type) ||
        iterableChecker.isAssignableFromType(type)) {
      var suffix = _accessorSuffixFromType(type);
      return '$accessor$suffix.toList()';
    } else {
      return accessor;
    }
  }
}

extension _FirstOrNullWhere<T> on Iterable<T> {
  T? firstOrNullWhere(bool Function(T) predicate) {
    for (var it in this) {
      if (predicate(it)) {
        return it;
      }
    }
    return null;
  }
}

/// Suffix to use when accessing a field in [type].
/// $variable$suffix.field
String _accessorSuffixFromType(DartType type) {
  if (type.nullabilitySuffix == NullabilitySuffix.star) {
    return '?';
  }
  if (type.nullabilitySuffix == NullabilitySuffix.question) {
    return '?';
  }
  return '';
}

/// Suffix to use when casting a value to [type].
/// $variable as $type$suffix
String _suffixFromType(DartType type) {
  if (type.nullabilitySuffix == NullabilitySuffix.star) {
    return '';
  }
  if (type.nullabilitySuffix == NullabilitySuffix.question) {
    return '?';
  }
  return '';
}

String _displayString(DartType e) {
  return e.getDisplayString();
}

class _TypeMatcher {
  const _TypeMatcher(this.name, {this.package, this.sdk = false});

  final String name;
  final String? package;
  final bool sdk;

  bool isExactlyType(DartType type) => _matches(type.element);

  bool isAssignableFromType(DartType type) {
    if (isExactlyType(type)) return true;
    if (type is! InterfaceType) return false;
    return type.allSupertypes.any((supertype) => _matches(supertype.element));
  }

  bool _matches(Element? element) {
    if (element?.name != name) return false;
    final uri = element?.library?.firstFragment.source.uri;
    if (uri == null) return false;
    if (sdk) return uri.scheme == 'dart';
    return package == null ||
        (uri.scheme == 'package' && uri.pathSegments.first == package);
  }
}
