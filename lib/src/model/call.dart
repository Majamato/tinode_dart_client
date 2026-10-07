import 'package:tinode_dart_client/src/json/json_reader.dart';
import 'package:tinode_dart_client/src/model/value_object.dart';

/// One step of a call, sent as a `call` note and forwarded as a `call`
/// info; [wire] is the protocol's `event` value.
enum CallEvent {
  /// The callee's device is showing the call.
  ringing('ringing'),
  accept('accept'),

  /// The caller's WebRTC offer, carrying a [CallDescription].
  offer('offer'),

  /// The callee's WebRTC answer, carrying a [CallDescription].
  answer('answer'),

  /// A network path to try, carrying an [IceCandidate].
  iceCandidate('ice-candidate'),

  /// Ends the call, or declines it before it was accepted.
  hangUp('hang-up'),
  unknown('');

  const CallEvent(this.wire);

  final String wire;

  static final Map<String, CallEvent> _byWire = {
    for (final e in values) e.wire: e,
  };

  static CallEvent of(String wire) => _byWire[wire] ?? unknown;
}

/// A WebRTC session description (SDP offer or answer), in the shape of
/// `RTCSessionDescription.toJSON()`.
final class CallDescription with ValueObject {
  const CallDescription({required this.type, required this.sdp});

  final String type;
  final String sdp;

  /// `null` unless [json] has both fields as strings.
  static CallDescription? tryParse(Json? json) {
    if (json == null) return null;
    final j = LooseJson(json);
    return switch ((j.get<String>('type'), j.get<String>('sdp'))) {
      (final type?, final sdp?) => CallDescription(type: type, sdp: sdp),
      _ => null,
    };
  }

  Json toJson() => {'type': type, 'sdp': sdp};

  @override
  List<Object?> get props => [type, sdp];
}

/// A WebRTC ICE candidate, in the shape of `RTCIceCandidate.toJSON()`.
final class IceCandidate with ValueObject {
  const IceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
    this.usernameFragment,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  final String? usernameFragment;

  /// `null` unless [json] has a `candidate` string. Extra keys, like the
  /// `type` that Android clients add, are ignored.
  static IceCandidate? tryParse(Json? json) {
    if (json == null) return null;
    final j = LooseJson(json);
    final candidate = j.get<String>('candidate');
    if (candidate == null) return null;

    return IceCandidate(
      candidate: candidate,
      sdpMid: j.get('sdpMid'),
      sdpMLineIndex: j.get('sdpMLineIndex'),
      usernameFragment: j.get('usernameFragment'),
    );
  }

  Json toJson() => {
    'candidate': candidate,
    'sdpMid': ?sdpMid,
    'sdpMLineIndex': ?sdpMLineIndex,
    'usernameFragment': ?usernameFragment,
  };

  @override
  List<Object?> get props => [
    candidate,
    sdpMid,
    sdpMLineIndex,
    usernameFragment,
  ];
}

/// Where a call stands, as the server records it in the call message's
/// head (`webrtc`); [wire] is the protocol's value.
enum CallState {
  /// The caller published the call and the peer has not answered yet.
  started('started'),
  accepted('accepted'),

  /// Ended after being accepted; the head also carries the duration.
  finished('finished'),

  /// Not accepted in time, or cancelled by the caller before that.
  missed('missed'),

  /// Rejected by the callee.
  declined('declined'),

  /// A party dropped before the call was accepted.
  disconnected('disconnected'),

  /// Documented by Tinode but never written by its server.
  busy('busy'),
  unknown('');

  const CallState(this.wire);

  final String wire;

  bool get isOver => switch (this) {
    finished || missed || declined || disconnected || busy => true,
    started || accepted || unknown => false,
  };

  static final Map<String, CallState> _byWire = {
    for (final s in values) s.wire: s,
  };

  static CallState of(String wire) => _byWire[wire] ?? unknown;
}
