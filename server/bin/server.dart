import 'dart:convert';
import 'dart:io';

import '../../packages/taxi_shared/lib/src/domain.dart';

/// A single-process teaching API. IDs identify demo sessions, not authenticated users.
Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8081');
  final file = File(
    Platform.environment['TAXI_DATA_FILE'] ?? 'server/data/orders.json',
  );
  final orders = <Trip>[];
  if (file.existsSync()) {
    orders.addAll(
      (jsonDecode(file.readAsStringSync()) as List<dynamic>).map(
        (e) => Trip.fromJson(e as Map<String, dynamic>),
      ),
    );
  } else if (Platform.environment['SEED_DEMO'] != 'false') {
    for (var i = 0; i < 3; i++) {
      final pickup = places[i];
      final destination = places[i + 3];
      final km = pickup.point.distanceTo(destination.point) * 1.4;
      orders.add(
        Trip(
          id: 'demo-${i + 1}',
          customerId: 'demo-${i + 1}',
          pickup: pickup,
          destination: destination,
          tariff: Tariff.values[i],
          km: km,
          minutes: (km / 25 * 60).ceil().clamp(1, 999),
          price: Tariff.values[i].price(km),
          status: TripStatus.searching,
          createdAt: DateTime.now(),
          demo: true,
        ),
      );
    }
  }
  void save() {
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(
      jsonEncode(orders.map((o) => o.toJson()).toList()),
    );
    temporary.renameSync(file.path);
  }

  save();
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Taxi API listening on http://localhost:$port');
  await for (final request in server) {
    final response = request.response;
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, PATCH, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      ..contentType = ContentType.json;
    void reply(int code, Object body) {
      response.statusCode = code;
      response.write(jsonEncode(body));
    }

    try {
      final path = request.uri.path;
      if (request.method == 'OPTIONS') {
        response.statusCode = 204;
      } else if (path == '/health' && request.method == 'GET') {
        reply(200, {'status': 'ok'});
      } else if (path == '/orders' && request.method == 'GET') {
        final customerId = request.uri.queryParameters['customerId'];
        reply(
          200,
          orders
              .where((o) => customerId == null || o.customerId == customerId)
              .map((o) => o.toJson())
              .toList()
              .reversed
              .toList(),
        );
      } else if (path == '/orders' && request.method == 'POST') {
        final data = await readBody(request);
        final customerId = text(data['customerId']);
        if (orders.any(
          (o) => o.customerId == customerId && o.status.isActive,
        )) {
          throw const HttpError(409, 'У вас уже есть активный заказ');
        }
        final pickup = parsePlace(data['pickup']);
        final destination = parsePlace(data['destination']);
        final direct = pickup.point.distanceTo(destination.point);
        if (direct < .1 || direct > 100) {
          throw const HttpError(400, 'Выберите разные точки в пределах 100 км');
        }
        final tariff = Tariff.values.byName(text(data['tariff']));
        final km = (data['km'] as num).toDouble();
        final minutes = (data['minutes'] as num).toInt();
        if (!km.isFinite ||
            km < direct * .8 ||
            km > 250 ||
            minutes < 1 ||
            minutes > 999) {
          throw const HttpError(400, 'Некорректная длина или время маршрута');
        }
        final trip = Trip(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          customerId: customerId,
          pickup: pickup,
          destination: destination,
          tariff: tariff,
          km: km,
          minutes: minutes,
          price: tariff.price(km),
          status: TripStatus.searching,
          createdAt: DateTime.now(),
        );
        orders.add(trip);
        save();
        reply(201, trip.toJson());
      } else if (RegExp(r'^/orders/[^/]+$').hasMatch(path) &&
          request.method == 'PATCH') {
        final id = path.split('/').last;
        final index = orders.indexWhere((o) => o.id == id);
        if (index < 0) {
          throw const HttpError(404, 'Заказ не найден');
        }
        final data = await readBody(request);
        final action = text(data['action']);
        final actor = text(data['actorId']);
        final order = orders[index];
        Trip updated;
        if (action == 'accept') {
          if (order.status != TripStatus.searching) {
            throw const HttpError(409, 'Этот заказ уже принят или отменён');
          }
          if (orders.any((o) => o.driverId == actor && o.status.isActive)) {
            throw const HttpError(409, 'Сначала завершите текущую поездку');
          }
          updated = order.transition(TripStatus.accepted, driver: actor);
        } else if (action == 'cancel') {
          if (actor != order.customerId && actor != order.driverId) {
            throw const HttpError(403, 'Это заказ другого пользователя');
          }
          if (![
            TripStatus.searching,
            TripStatus.accepted,
            TripStatus.arrived,
          ].contains(order.status)) {
            throw const HttpError(409, 'Поездку уже нельзя отменить');
          }
          updated = order.transition(TripStatus.cancelled);
        } else {
          if (order.driverId != actor) {
            throw const HttpError(403, 'Это заказ другого водителя');
          }
          final next = switch ((order.status, action)) {
            (TripStatus.accepted, 'arrive') => TripStatus.arrived,
            (TripStatus.arrived, 'start') => TripStatus.inProgress,
            (TripStatus.inProgress, 'complete') => TripStatus.completed,
            _ => throw const HttpError(
              409,
              'Недопустимый переход состояния заказа',
            ),
          };
          updated = order.transition(next);
        }
        // All validation and writes run synchronously after reading the body:
        // two drivers cannot accept the same order in this single process.
        orders[index] = updated;
        save();
        reply(200, updated.toJson());
      } else {
        reply(404, {'error': 'Маршрут API не найден'});
      }
    } on HttpError catch (e) {
      reply(e.code, {'error': e.message});
    } on FormatException {
      reply(400, {'error': 'Некорректный JSON или значение поля'});
    } on TypeError {
      reply(400, {'error': 'Проверьте обязательные поля заказа'});
    } on ArgumentError {
      reply(400, {'error': 'Неизвестный тариф или значение поля'});
    } catch (e, stack) {
      stderr.writeln('$e\n$stack');
      reply(500, {'error': 'Ошибка сервера'});
    } finally {
      await response.close();
    }
  }
}

class HttpError implements Exception {
  const HttpError(this.code, this.message);
  final int code;
  final String message;
}

String text(dynamic value) {
  if (value is! String || value.trim().isEmpty || value.length > 200) {
    throw const HttpError(400, 'Некорректное текстовое поле');
  }
  return value.trim();
}

Place parsePlace(dynamic value) {
  final map = value as Map<String, dynamic>;
  final place = Place(
    text(map['name']),
    text(map['address']),
    GeoPoint.fromJson(map['point'] as Map<String, dynamic>),
  );
  if (!place.point.lat.isFinite ||
      !place.point.lon.isFinite ||
      place.point.lat.abs() > 90 ||
      place.point.lon.abs() > 180) {
    throw const HttpError(400, 'Некорректные координаты');
  }
  return place;
}

Future<Map<String, dynamic>> readBody(HttpRequest request) async {
  var size = 0;
  final bytes = <int>[];
  await for (final chunk in request) {
    size += chunk.length;
    if (size > 16384) {
      throw const HttpError(413, 'Слишком большой запрос');
    }
    bytes.addAll(chunk);
  }
  return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}
