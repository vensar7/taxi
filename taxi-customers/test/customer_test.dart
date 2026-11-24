import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_customers/main.dart';
import 'package:taxi_shared/taxi_shared.dart';

class TestRouter extends RouteService {
  @override
  Future<RoutePlan> route(GeoPoint start, GeoPoint end) async =>
      RoutePlan(points: [start, end], km: 2.8, minutes: 8);
}

class TestApi extends TaxiApi {
  List<Trip> data = [];
  @override
  Future<List<Trip>> orders({String? customerId}) async => data;
  @override
  Future<Trip> create({
    required String customerId,
    required Place pickup,
    required Place destination,
    required Tariff tariff,
    required RoutePlan route,
  }) async {
    final trip = Trip(
      id: 'test-order',
      customerId: customerId,
      pickup: pickup,
      destination: destination,
      tariff: tariff,
      km: route.km,
      minutes: route.minutes,
      price: tariff.price(route.km),
      status: TripStatus.searching,
      createdAt: DateTime(2026),
    );
    data = [trip];
    return trip;
  }
}

void main() {
  testWidgets('customer chooses tariff, books and sees completion in history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = TestApi();
    final c = TaxiController(
      isDriver: false,
      identity: 'customer-test',
      api: api,
      router: TestRouter(),
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(CustomerApp(controller: c, enableTiles: false));
    await tester.pumpAndSettle();
    expect(find.text('Куда поедем?'), findsOneWidget);
    await tester.ensureVisible(find.text('Комфорт'));
    await tester.tap(find.text('Комфорт'));
    await tester.pump();
    expect(c.tariff, Tariff.comfort);
    await tester.ensureVisible(find.text('Заказать такси'));
    await tester.tap(find.text('Заказать такси'));
    await tester.pumpAndSettle();
    expect(find.text('Ищем водителя'), findsOneWidget);
    expect(c.active?.price, Tariff.comfort.price(2.8));
    api.data = [api.data.first.transition(TripStatus.completed)];
    await c.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(find.text('Поездка завершена'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('address picker and wide layout work', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = TaxiController(
      isDriver: false,
      identity: 'customer-test',
      api: TestApi(),
      router: TestRouter(),
      pollInterval: const Duration(days: 1),
    );
    await tester.pumpWidget(CustomerApp(controller: c, enableTiles: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('130-й квартал'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Аэропорт');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Аэропорт Иркутск'));
    await tester.pumpAndSettle();
    expect(c.destination.name, 'Аэропорт Иркутск');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
