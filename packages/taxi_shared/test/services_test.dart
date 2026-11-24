import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taxi_shared/taxi_shared.dart';

void main() {
  test(
    'OSRM route reads lon/lat in correct order and converts units',
    () async {
      final service = RouteService(
        client: MockClient((request) async {
          expect(request.url.path, contains('104.2807,52.2864'));
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'distance': 2800,
                  'duration': 480,
                  'geometry': {
                    'coordinates': [
                      [104.2807, 52.2864],
                      [104.2897, 52.2738],
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.close);
      final route = await service.route(places[0].point, places[1].point);
      expect(route.km, 2.8);
      expect(route.minutes, 8);
      expect(route.points.first.lat, 52.2864);
      expect(route.approximate, false);
    },
  );

  test('route failure returns explicitly approximate route', () async {
    final service = RouteService(
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );
    addTearDown(service.close);
    final route = await service.route(places[0].point, places[1].point);
    expect(route.approximate, true);
    expect(route.km, greaterThan(0));
    expect(route.points, hasLength(2));
  });

  test('API preserves conflict error instead of reporting success', () async {
    final api = TaxiApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'Этот заказ уже принят или отменён'}),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.create(
        customerId: 'test',
        pickup: places[0],
        destination: places[1],
        tariff: Tariff.economy,
        route: RoutePlan(points: [], km: 2.8, minutes: 8),
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('уже принят'),
        ),
      ),
    );
  });
}
