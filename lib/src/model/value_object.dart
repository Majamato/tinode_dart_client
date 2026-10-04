import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

const _equality = DeepCollectionEquality();

/// Deep value equality over [props], so raw JSON blobs compare by content.
@immutable
mixin ValueObject {
  @internal
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValueObject &&
          other.runtimeType == runtimeType &&
          _equality.equals(props, other.props);

  @override
  int get hashCode => _equality.hash(props);

  @override
  String toString() => '$runtimeType(${props.join(', ')})';
}
