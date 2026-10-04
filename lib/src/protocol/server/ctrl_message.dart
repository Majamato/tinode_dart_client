part of 'server_message.dart';

/// The reply to a client request, matched to it by [id].
final class CtrlMessage extends ServerMessage {
  const CtrlMessage({
    required this.code,
    required this.text,
    required this.time,
    this.id,
    this.topic,
    this.params = const {},
  });

  factory CtrlMessage._fromJson(Json json) {
    final r = StrictJson(json);
    return CtrlMessage(
      id: r.optional('id', 'ctrl'),
      topic: r.optional('topic', 'ctrl'),
      code: r.require('code', 'ctrl'),
      text: r.optional('text', 'ctrl') ?? '',
      params: r.optionalObject('params', 'ctrl') ?? const {},
      time: r.requireTime('ts', 'ctrl'),
    );
  }

  final String? id;
  @override
  final String? topic;

  /// HTTP-like status: 2xx ok, 3xx more input needed, 4xx/5xx failure.
  final int code;
  final String text;

  /// Request-specific values (token, seq…), read by the client per request.
  final Json params;
  final DateTime time;

  bool get isError => code >= 300;

  @override
  List<Object?> get props => [id, topic, code, text, params, time];
}
