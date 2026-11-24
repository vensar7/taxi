import 'dart:async';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'services.dart';

/// Coordinates polling and mutations. Mutations pause polling, avoiding stale
/// responses overwriting an accepted/cancelled trip.
class TaxiController extends ChangeNotifier {
  TaxiController({
    required this.isDriver,
    TaxiApi? api,
    RouteService? router,
    this.identity,
    this.pollInterval = const Duration(seconds: 2),
  }) : api = api ?? TaxiApi(),
       router = router ?? RouteService();
  final bool isDriver;
  final TaxiApi api;
  final RouteService router;
  final Duration pollInterval;
  String? identity;
  List<Trip> trips = [];
  Trip? selected;
  Place pickup = places.first;
  Place destination = places[1];
  GeoPoint driverPosition = cityCenter;
  Tariff tariff = Tariff.economy;
  RoutePlan? route;
  bool online = true;
  bool busy = false;
  bool routing = false;
  bool locating = false;
  bool connected = false;
  String? error;
  Timer? _timer;
  bool _disposed = false;
  bool _polling = false;
  int _revision = 0;
  int _routeRevision = 0;
  String? _routeKey;

  Trip? get active {
    for (final trip in trips) {
      if (trip.status.isActive &&
          (isDriver
              ? trip.driverId == identity
              : trip.customerId == identity)) {
        return trip;
      }
    }
    return null;
  }

  List<Trip> get available =>
      trips.where((t) => t.status == TripStatus.searching).toList();
  List<Trip> get history => trips
      .where(
        (t) =>
            !t.status.isActive &&
            (isDriver ? t.driverId == identity : t.customerId == identity),
      )
      .toList();
  int get earnings => history
      .where((t) => t.status == TripStatus.completed)
      .fold(0, (sum, trip) => sum + trip.price);
  Trip? get displayed => active ?? selected;
  bool get validRoute =>
      pickup.point.distanceTo(destination.point) >= .1 &&
      pickup.point.distanceTo(destination.point) <= 100 &&
      route != null &&
      !routing;

  Future<void> initialize() async {
    try {
      identity ??= await loadIdentity(isDriver ? 'driver' : 'customer');
      if (_disposed) {
        return;
      }
      await refresh();
      if (_disposed) {
        return;
      }
      await updateRoute();
      if (_disposed) {
        return;
      }
      _timer = Timer.periodic(pollInterval, (_) => refresh());
    } catch (_) {
      error = 'Не удалось загрузить профиль. Перезапустите приложение.';
      emit();
    }
  }

  void emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_polling || busy || identity == null || _disposed) {
      return;
    }
    _polling = true;
    final revision = _revision;
    try {
      final result = await api.orders(customerId: isDriver ? null : identity);
      if (_disposed || revision != _revision) {
        return;
      }
      trips = result;
      connected = true;
      if (error?.startsWith('Нет связи') == true) {
        error = null;
      }
      if (selected != null) {
        final matching = trips.where((t) => t.id == selected!.id).firstOrNull;
        selected = matching?.status == TripStatus.searching ? matching : null;
      }
      await updateRoute();
    } catch (e) {
      if (!_disposed && revision == _revision) {
        connected = false;
        error = e.toString();
      }
    } finally {
      _polling = false;
      emit();
    }
  }

  Future<void> updateRoute({bool force = false}) async {
    final trip = displayed;
    final start = isDriver
        ? (trip?.status == TripStatus.inProgress
              ? trip!.pickup.point
              : driverPosition)
        : (trip?.pickup.point ?? pickup.point);
    final end = isDriver && trip != null && trip.status != TripStatus.inProgress
        ? trip.pickup.point
        : (trip?.destination.point ?? destination.point);
    if (isDriver && trip == null) {
      _routeRevision++;
      _routeKey = null;
      route = null;
      routing = false;
      emit();
      return;
    }
    final key = '${start.lat},${start.lon}:${end.lat},${end.lon}';
    if (!force && key == _routeKey) {
      return;
    }
    _routeKey = key;
    final revision = ++_routeRevision;
    routing = true;
    route = null;
    emit();
    final result = await router.route(start, end);
    if (_disposed || revision != _routeRevision) {
      return;
    }
    route = result;
    routing = false;
    emit();
  }

  void setPlace(Place place, {required bool isPickup}) {
    if (active != null || busy) {
      return;
    }
    if (isPickup) {
      pickup = place;
    } else {
      destination = place;
    }
    error = null;
    updateRoute();
    emit();
  }

  void select(Trip trip) {
    if (active != null || busy) {
      return;
    }
    selected = trip;
    updateRoute();
    emit();
  }

  Future<void> geolocate() async {
    if (locating) {
      return;
    }
    locating = true;
    emit();
    try {
      final point = await locate();
      if (_disposed) {
        return;
      }
      if (isDriver) {
        driverPosition = point;
        await updateRoute(force: true);
      } else if (active == null) {
        setPlace(
          Place('Моё местоположение', 'Позиция устройства', point),
          isPickup: true,
        );
      }
    } catch (e) {
      error = e.toString();
    } finally {
      locating = false;
      emit();
    }
  }

  Future<void> _mutate(Future<Trip> Function() operation) async {
    if (busy || identity == null) {
      return;
    }
    busy = true;
    error = null;
    _revision++;
    emit();
    try {
      final trip = await operation();
      if (_disposed) {
        return;
      }
      trips = [trip, ...trips.where((t) => t.id != trip.id)];
      connected = true;
      selected = null;
      await updateRoute();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      emit();
    }
    await refresh();
  }

  Future<void> book() async {
    if (!validRoute || active != null || !connected) {
      return;
    }
    final quote = route!;
    await _mutate(
      () => api.create(
        customerId: identity!,
        pickup: pickup,
        destination: destination,
        tariff: tariff,
        route: quote,
      ),
    );
  }

  Future<void> act(Trip trip, String action) =>
      _mutate(() => api.action(trip, action, identity!));
  void toggleOnline(bool value) {
    if (active != null) {
      return;
    }
    online = value;
    if (!value) {
      selected = null;
      updateRoute();
    }
    emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    api.close();
    router.close();
    super.dispose();
  }
}
