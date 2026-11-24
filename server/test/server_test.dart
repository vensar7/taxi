import 'dart:convert';
import 'dart:io';

import '../../packages/taxi_shared/lib/src/domain.dart';

void check(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

Future<void> main() async {
  final root = Directory.current.path;
  final directory = Directory.systemTemp.createTempSync('taxi_api_test_');
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  final client = HttpClient();
  Process? process;
  Future<void> start() async {
    process = await Process.start(
      Platform.resolvedExecutable,
      ['$root/server/bin/server.dart'],
      environment: {
        'PORT': '$port',
        'TAXI_DATA_FILE': '${directory.path}/orders.json',
        'SEED_DEMO': 'false',
      },
    );
    process!.stderr.transform(utf8.decoder).listen(stderr.write);
    await process!.stdout
        .transform(utf8.decoder)
        .first
        .timeout(const Duration(seconds: 20));
  }

  Future<(int, dynamic)> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final r = await client.openUrl(
      method,
      Uri.parse('http://localhost:$port$path'),
    );
    r.headers.contentType = ContentType.json;
    if (body != null) {
      r.write(jsonEncode(body));
    }
    final response = await r.close();
    final content = await response.transform(utf8.decoder).join();
    return (response.statusCode, content.isEmpty ? null : jsonDecode(content));
  }

  Map<String, dynamic> booking(String customer) => {
    'customerId': customer,
    'pickup': places[0].toJson(),
    'destination': places[1].toJson(),
    'tariff': 'comfort',
    'km': 2.8,
    'minutes': 8,
  };
  try {
    await start();
    check((await request('GET', '/health')).$1 == 200, 'health');
    check((await request('OPTIONS', '/orders')).$1 == 204, 'CORS preflight');
    final invalid = booking('bad')..['km'] = -1;
    check(
      (await request('POST', '/orders', invalid)).$1 == 400,
      'invalid distance rejected',
    );
    final created = await request('POST', '/orders', booking('customer-a'));
    check(created.$1 == 201, 'customer creates order');
    final id = created.$2['id'];
    check(
      created.$2['price'] == Tariff.comfort.price(2.8),
      'server calculates price',
    );
    check(
      (await request('POST', '/orders', booking('customer-a'))).$1 == 409,
      'duplicate active order rejected',
    );
    check(
      ((await request('GET', '/orders?customerId=customer-b')).$2 as List)
          .isEmpty,
      'customer history filtered',
    );
    check(
      ((await request('GET', '/orders')).$2 as List).length == 1,
      'driver sees customer order',
    );
    final attempts = await Future.wait([
      request('PATCH', '/orders/$id', {
        'action': 'accept',
        'actorId': 'driver-a',
      }),
      request('PATCH', '/orders/$id', {
        'action': 'accept',
        'actorId': 'driver-b',
      }),
    ]);
    check(
      attempts.where((r) => r.$1 == 200).length == 1 &&
          attempts.where((r) => r.$1 == 409).length == 1,
      'exactly one driver accepts order',
    );
    final driver = attempts.firstWhere((r) => r.$1 == 200).$2['driverId'];
    check(
      (await request('PATCH', '/orders/$id', {
            'action': 'complete',
            'actorId': driver,
          })).$1 ==
          409,
      'cannot skip trip stages',
    );
    check(
      (await request('PATCH', '/orders/$id', {
            'action': 'arrive',
            'actorId': 'intruder',
          })).$1 ==
          403,
      'other driver cannot modify order',
    );
    for (final action in ['arrive', 'start', 'complete']) {
      final result = await request('PATCH', '/orders/$id', {
        'action': action,
        'actorId': driver,
      });
      check(result.$1 == 200, '$action succeeds');
      if (action == 'start') {
        check(
          (await request('PATCH', '/orders/$id', {
                'action': 'cancel',
                'actorId': 'customer-a',
              })).$1 ==
              409,
          'cannot cancel trip in progress',
        );
      }
    }
    final history =
        (await request('GET', '/orders?customerId=customer-a')).$2 as List;
    check(
      history.single['status'] == 'completed',
      'customer sees completed trip',
    );
    final another = await request('POST', '/orders', booking('customer-a'));
    check(another.$1 == 201, 'customer can book again');
    final cancel = await request('PATCH', '/orders/${another.$2['id']}', {
      'action': 'cancel',
      'actorId': 'customer-a',
    });
    check(cancel.$2['status'] == 'cancelled', 'customer cancels order');
    process!.kill();
    await process!.exitCode;
    await start();
    final persisted =
        (await request('GET', '/orders?customerId=customer-a')).$2 as List;
    check(
      persisted.length == 2 && persisted.any((o) => o['status'] == 'completed'),
      'orders survive server restart',
    );
    stdout.writeln(
      'PASS: shared orders, price, CORS, validation, competing drivers, trip lifecycle, cancellation, persistence',
    );
  } finally {
    process?.kill();
    if (process != null) {
      await process!.exitCode;
    }
    client.close(force: true);
    directory.deleteSync(recursive: true);
  }
}
