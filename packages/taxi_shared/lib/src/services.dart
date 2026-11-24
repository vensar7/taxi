import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'domain.dart';

const apiBaseUrl = String.fromEnvironment(
  'TAXI_API_URL',
  defaultValue: 'http://localhost:8081',
);

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TaxiApi {
  TaxiApi({http.Client? client, this.baseUrl = apiBaseUrl})
    : client = client ?? http.Client();
  final http.Client client;
  final String baseUrl;
  Future<dynamic> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
      final response = await client
          .send(
            http.Request(method, uri)
              ..headers['Content-Type'] = 'application/json'
              ..body = body == null ? '' : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(
        await response.stream.bytesToString().timeout(
          const Duration(seconds: 8),
        ),
      );
      if (response.statusCode >= 400) {
        throw ApiException(
          (data as Map<String, dynamic>)['error'] as String? ??
              'Ошибка сервера',
        );
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Нет связи с сервером. Проверьте запуск сервера и адрес API.',
      );
    }
  }

  Future<List<Trip>> orders({String? customerId}) async {
    final suffix = customerId == null
        ? ''
        : '?customerId=${Uri.encodeQueryComponent(customerId)}';
    final data = await _request('GET', '/orders$suffix') as List<dynamic>;
    return data.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Trip> create({
    required String customerId,
    required Place pickup,
    required Place destination,
    required Tariff tariff,
    required RoutePlan route,
  }) async => Trip.fromJson(
    await _request('POST', '/orders', {
      'customerId': customerId,
      'pickup': pickup.toJson(),
      'destination': destination.toJson(),
      'tariff': tariff.name,
      'km': route.km,
      'minutes': route.minutes,
    }) as Map<String, dynamic>,
  );
  Future<Trip> action(Trip trip, String action, String actorId) async =>
      Trip.fromJson(
        await _request('PATCH', '/orders/${trip.id}', {
          'action': action,
          'actorId': actorId,
        }) as Map<String, dynamic>,
      );
  void close() => client.close();
}

class RouteService {
  RouteService({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  Future<RoutePlan> route(GeoPoint start, GeoPoint end) async {
    try {
      final response = await client
          .get(
            Uri.parse(
              'https://router.project-osrm.org/route/v1/driving/'
              '${start.lon},${start.lat};${end.lon},${end.lat}'
              '?overview=full&geometries=geojson',
            ),
          )
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) {
        throw const FormatException();
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>;
      if (data['code'] != 'Ok' || routes.isEmpty) {
        throw const FormatException();
      }
      final r = routes.first as Map<String, dynamic>;
      final coordinates =
          (r['geometry'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>;
      return RoutePlan(
        points: coordinates
            .map(
              (c) =>
                  GeoPoint((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList(),
        km: (r['distance'] as num).toDouble() / 1000,
        minutes: ((r['duration'] as num) / 60).ceil().clamp(1, 999),
      );
    } catch (_) {
      final km = start.distanceTo(end) * 1.4;
      return RoutePlan(
        points: [start, end],
        km: km,
        minutes: (km / 25 * 60).ceil().clamp(1, 999),
        approximate: true,
      );
    }
  }

  void close() => client.close();
}

Future<String> loadIdentity(String role) async {
  final preferences = SharedPreferencesAsync();
  final key = 'taxi_${role}_id';
  final saved = await preferences.getString(key);
  if (saved != null) {
    return saved;
  }
  final id = '${role}_${DateTime.now().microsecondsSinceEpoch}';
  await preferences.setString(key, id);
  return id;
}

Future<GeoPoint> locate() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const ApiException(
      'Включите геолокацию на устройстве или выберите точку на карте.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const ApiException(
      'Нет разрешения на геолокацию. Разрешите доступ в настройках или выберите точку вручную.',
    );
  }
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return GeoPoint(position.latitude, position.longitude);
  } catch (_) {
    throw const ApiException(
      'Не удалось определить позицию. В браузере нужен HTTPS или localhost. Выберите точку вручную.',
    );
  }
}
