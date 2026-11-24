import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_driver/main.dart';
import 'package:taxi_shared/taxi_shared.dart';

class TestRouter extends RouteService {
  @override
  Future<RoutePlan> route(GeoPoint start, GeoPoint end) async =>
      RoutePlan(points: [start, end], km: 2.8, minutes: 8);
}

class TestApi extends TaxiApi {
  Trip trip = Trip(
    id: 'test-order',
    customerId: 'customer-test',
    pickup: places[1],
    destination: places[4],
    tariff: Tariff.economy,
    km: 9,
    minutes: 20,
    price: 320,
    status: TripStatus.searching,
    createdAt: DateTime(2026),
  );
  @override
  Future<List<Trip>> orders({String? customerId}) async => [trip];
  @override
  Future<Trip> action(Trip order, String action, String actorId) async {
    trip = trip.transition(switch (action) {
      'accept' => TripStatus.accepted,
      'arrive' => TripStatus.arrived,
      'start' => TripStatus.inProgress,
      'complete' => TripStatus.completed,
      _ => TripStatus.cancelled,
    }, driver: actorId);
    return trip;
  }
}

void main() {
  testWidgets('driver accepts and completes order and sees earnings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = TaxiController(
      isDriver: true,
      identity: 'driver-test',
      api: TestApi(),
      router: TestRouter(),
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(DriverApp(controller: c, enableTiles: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('А  130-й квартал'));
    await tester.pumpAndSettle();
    final accept = find.text('Принять заказ · 320 ₽');
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(find.text('Едем к клиенту'), findsOneWidget);
    for (final label in ['Я на месте', 'Начать поездку', 'Завершить поездку']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(c.active, isNull);
    expect(c.earnings, 320);
    await tester.tap(find.text('Поездки'));
    await tester.pumpAndSettle();
    expect(find.text('Поездка завершена'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
