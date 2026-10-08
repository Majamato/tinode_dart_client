import 'package:tinode_dart_client/src/errors.dart';
import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// The message seqs `low <= seq < high`. On the wire it is `{low, hi}`,
/// and a missing `hi` means the single seq [low].
final class SeqRange with ValueObject {
  const SeqRange(this.low, this.high)
    : assert(low > 0, 'seqs start at 1'),
      assert(high > low, 'a range holds at least one seq');

  const SeqRange.single(int seq) : this(seq, seq + 1);

  /// A `hi` that doesn't lie above `low` is read as a single seq, as
  /// Tinode's own clients do.
  factory SeqRange.fromJson(Json json, String path) {
    final r = StrictJson(json);
    final low = r.require<int>('low', path);
    if (low <= 0) throw MalformedPacketException('$path.low', low);
    final high = r.optional<int>('hi', path) ?? 0;
    return SeqRange(low, high > low ? high : low + 1);
  }

  final int low;

  /// Exclusive.
  final int high;

  int get length => high - low;

  bool contains(int seq) => seq >= low && seq < high;

  Json toJson() => {'low': low, if (high > low + 1) 'hi': high};

  @override
  List<Object?> get props => [low, high];

  @override
  String toString() => 'SeqRange($low..$high)';
}

/// Deleted messages of a topic, from `get what=del` (`meta.del`).
final class DeleteLog with ValueObject {
  const DeleteLog({this.lastDeleteId = 0, this.ranges = const []});

  factory DeleteLog.fromJson(Json json, String path) {
    final r = StrictJson(json);
    return DeleteLog(
      lastDeleteId: r.optional('clear', path) ?? 0,
      ranges: r.list('delseq', path, SeqRange.fromJson),
    );
  }

  /// Nothing deleted, or nothing deleted in the window asked for.
  static const empty = DeleteLog();

  /// The latest delete ID among [ranges] (`clear`).
  final int lastDeleteId;
  final List<SeqRange> ranges;

  @override
  List<Object?> get props => [lastDeleteId, ranges];
}
