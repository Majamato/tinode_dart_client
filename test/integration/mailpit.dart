import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:tinode_dart_client/tinode_dart_client.dart';

/// Mailpit's API, where the test server must deliver its email.
final Uri mailpit = Uri.parse('http://localhost:8025/api/v1/');

/// Deletes every caught message.
Future<void> clearMail() => http.delete(mailpit.resolve('messages'));

/// The code in the newest email to [to], waiting for it to land.
Future<String> mailedCode(String to) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final search = await http.get(
      mailpit.resolve('search?query=${Uri.encodeQueryComponent('to:$to')}'),
    );
    final messages = (jsonDecode(search.body) as Json)['messages']! as List;
    if (messages.isNotEmpty) {
      final id = (messages.first as Json)['ID']! as String;
      final message = await http.get(mailpit.resolve('message/$id'));
      final text = (jsonDecode(message.body) as Json)['Text']! as String;
      // Reset emails say "code if prompted", validation emails "following
      // code".
      return RegExp(
        r'code(?: if prompted)?:\s*(\d+)',
      ).firstMatch(text)!.group(1)!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('no email to $to');
}
