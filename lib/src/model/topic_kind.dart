/// The kind of a topic, derived from its name.
enum TopicKind {
  /// `me`: the user's account, chat list and presence feed.
  account,

  /// `fnd`: search for users and topics by tags.
  search,

  /// `slf`: notes to self.
  notes,

  /// `sys`: a write-only line to the server administrators.
  system,

  /// A 1:1 chat, named after the peer (`usr…`) or `p2p…`.
  direct,

  /// `grp…`, or `new…` when creating one.
  group,

  /// `chn…`, or `nch…` when creating one.
  channel,

  /// A name this client does not recognise, e.g. from a newer server.
  unknown;

  static TopicKind of(String name) => switch (name) {
    'me' => account,
    'fnd' => search,
    'slf' => notes,
    'sys' => system,
    _ when name.startsWith('usr') || name.startsWith('p2p') => direct,
    _ when name.startsWith('grp') || name.startsWith('new') => group,
    _ when name.startsWith('chn') || name.startsWith('nch') => channel,
    _ => unknown,
  };
}
