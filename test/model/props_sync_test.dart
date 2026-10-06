import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// `ValueObject` equality only sees what `props` lists, so a field missing
/// there makes two different values compare equal. Dart can't list fields
/// without codegen, so this reads the source instead.
void main() {
  final classes = {
    for (final file in Directory('lib').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        for (final c in _parse(file).declarations.whereType<ClassDeclaration>())
          c.namePart.typeName.lexeme: c,
  };

  ClassDeclaration? parentOf(ClassDeclaration c) =>
      classes[c.extendsClause?.superclass.name.lexeme];

  bool isValueObject(ClassDeclaration? c) =>
      c != null &&
      ((c.withClause?.mixinTypes.any((t) => t.name.lexeme == 'ValueObject') ??
              false) ||
          isValueObject(parentOf(c)));

  final concrete = [
    for (final c in classes.values)
      if (isValueObject(c) &&
          c.abstractKeyword == null &&
          c.sealedKeyword == null)
        c,
  ];

  test('finds the value objects', () {
    expect(concrete.length, greaterThan(20));
    expect(
      concrete.map((c) => c.namePart.typeName.lexeme),
      containsAll(['PlainText', 'CtrlMessage', 'ServerInfo', 'Connected']),
    );
  });

  for (final c in concrete) {
    final name = c.namePart.typeName.lexeme;
    test('$name lists every field in props', () {
      final fields = <String>{};
      MethodDeclaration? props;
      for (ClassDeclaration? k = c; k != null; k = parentOf(k)) {
        for (final member in k.body.members) {
          switch (member) {
            case FieldDeclaration(
              isStatic: false,
              fields: VariableDeclarationList(:final variables),
            ):
              fields.addAll(variables.map((v) => v.name.lexeme));
            case MethodDeclaration(
              isGetter: true,
              name: Token(lexeme: 'props'),
            ):
              props ??= member;
            case _:
          }
        }
      }
      expect(props, isNotNull, reason: '$name has no props getter');
      final listed = _Identifiers()..visit(props!.body);
      expect(listed.names, fields, reason: 'props of $name vs its fields');
    });
  }
}

CompilationUnit _parse(File file) => parseFile(
  path: file.absolute.path,
  featureSet: FeatureSet.latestLanguageVersion(),
).unit;

/// Every identifier a node mentions.
final class _Identifiers extends RecursiveAstVisitor<void> {
  final names = <String>{};

  void visit(AstNode node) => node.accept(this);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) => names.add(node.name);
}
