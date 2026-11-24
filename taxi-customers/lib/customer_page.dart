import 'package:flutter/material.dart';
import 'package:taxi_shared/taxi_shared.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key, this.controller, this.enableTiles = true});
  final TaxiController? controller;
  final bool enableTiles;
  @override
  Widget build(BuildContext context) => TaxiApp(
    isDriver: false,
    home: CustomerHome(controller: controller, enableTiles: enableTiles),
  );
}

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key, this.controller, this.enableTiles = true});
  final TaxiController? controller;
  final bool enableTiles;
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  late final TaxiController c;
  int tab = 0;
  bool? pickingPickup;
  @override
  void initState() {
    super.initState();
    c = widget.controller ?? TaxiController(isDriver: false);
    c.addListener(changed);
    c.initialize();
  }

  void changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    c.removeListener(changed);
    if (widget.controller == null) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick(bool pickup) async {
    final result = await choosePlace(
      context,
      pickup ? 'Откуда поедем?' : 'Куда поедем?',
    );
    if (!mounted || result == null) {
      return;
    }
    if (result.onMap) {
      setState(() => pickingPickup = pickup);
    } else if (result.place != null) {
      c.setPlace(result.place!, isPickup: pickup);
    }
  }

  Future<void> cancel(Trip trip) async {
    if (await confirmCancellation(context)) {
      await c.act(trip, 'cancel');
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = c.active;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: customerBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.local_taxi,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Такси', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: c.connected ? driverGreen : Colors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  c.connected ? 'Клиент' : 'Нет связи',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: switch (tab) {
          1 => TripHistory(trips: c.history),
          2 => AboutPage(driver: false, identity: c.identity),
          _ => Workspace(
            phase: '${trip?.id}:${trip?.status.name}',
            map: CityMap(
              enableTiles: widget.enableTiles,
              route: c.route,
              pins: [
                MapPin((trip?.pickup ?? c.pickup).point, 'А', customerBlue),
                MapPin(
                  (trip?.destination ?? c.destination).point,
                  'Б',
                  driverGreen,
                ),
              ],
              hint: pickingPickup == null
                  ? 'Иркутск · от А до Б'
                  : pickingPickup!
                  ? 'Нажмите на место подачи на карте'
                  : 'Нажмите на место назначения на карте',
              onTap: trip != null || c.busy
                  ? null
                  : (point) {
                      c.setPlace(
                        Place.onMap(point),
                        isPickup: pickingPickup ?? false,
                      );
                      setState(() => pickingPickup = null);
                    },
              onLocate: trip == null ? c.geolocate : null,
              locating: c.locating,
            ),
            panel: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.error != null) Notice(c.error!, action: c.refresh),
                if (pickingPickup != null)
                  Notice(
                    'Выберите точку касанием карты.',
                    actionLabel: 'Закрыть',
                    action: () => setState(() => pickingPickup = null),
                  ),
                if (trip == null)
                  ...booking(context)
                else
                  ...currentTrip(context, trip),
              ],
            ),
          ),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.local_taxi_outlined),
            selectedIcon: Icon(Icons.local_taxi),
            label: 'Поездка',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'История'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }

  List<Widget> booking(BuildContext context) => [
    Text('Куда поедем?', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 4),
    const Text(
      'Выберите адрес или точку на карте',
      style: TextStyle(color: Color(0xFF6F7E90)),
    ),
    const SizedBox(height: 12),
    AddressRow(
      place: c.pickup,
      label: 'А',
      color: customerBlue,
      caption: 'Откуда · ${c.pickup.address}',
      onTap: c.busy ? null : () => pick(true),
    ),
    const Divider(height: 1),
    AddressRow(
      place: c.destination,
      label: 'Б',
      color: driverGreen,
      caption: 'Куда · ${c.destination.address}',
      onTap: c.busy ? null : () => pick(false),
    ),
    RouteSummary(
      route: c.route,
      loading: c.routing,
      onRetry: () => c.updateRoute(force: true),
    ),
    if (c.pickup.point.distanceTo(c.destination.point) < .1)
      const Notice(
        'Места подачи и назначения слишком близко. Выберите другую точку.',
      ),
    if (c.pickup.point.distanceTo(c.destination.point) > 100)
      const Notice('Для лабораторной выберите маршрут в пределах 100 км.'),
    const SizedBox(height: 6),
    Text('Тариф', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 10),
    for (final tariff in Tariff.values) tariffCard(tariff),
    const SizedBox(height: 9),
    const Row(
      children: [
        Icon(Icons.payments_outlined, size: 20),
        SizedBox(width: 9),
        Expanded(child: Text('Наличные · учебная оплата')),
      ],
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: c.validRoute && c.connected && !c.busy ? c.book : null,
      icon: Icon(c.busy ? Icons.hourglass_top : Icons.local_taxi, size: 21),
      label: Text(c.busy ? 'Создаём заказ…' : 'Заказать такси'),
    ),
    const SizedBox(height: 9),
    const Text(
      'Заказ появится у водителя, подключённого к тому же серверу.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, color: Color(0xFF78879B)),
    ),
  ];

  Widget tariffCard(Tariff tariff) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      selected: c.tariff == tariff,
      button: true,
      child: Material(
        color: c.tariff == tariff
            ? const Color(0xFFEEF3FF)
            : const Color(0xFFF6F8FB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: c.tariff == tariff ? customerBlue : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: c.busy ? null : () => setState(() => c.tariff = tariff),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Icon(
                  [
                    Icons.local_taxi_outlined,
                    Icons.directions_car_filled_outlined,
                    Icons.airport_shuttle_outlined,
                  ][tariff.iconIndex],
                  color: c.tariff == tariff
                      ? customerBlue
                      : const Color(0xFF78879B),
                  size: 29,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tariff.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        tariff.subtitle,
                        style: const TextStyle(
                          color: Color(0xFF6F7E90),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  c.route == null
                      ? '—'
                      : '${c.route!.approximate ? '≈ ' : ''}${tariff.price(c.route!.km)} ₽',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> currentTrip(BuildContext context, Trip trip) => [
    Text(trip.status.title, style: Theme.of(context).textTheme.headlineMedium),
    StatusSteps(status: trip.status),
    Text(switch (trip.status) {
      TripStatus.searching =>
        'Заказ отправлен. Ждём, когда водитель примет его.',
      TripStatus.accepted =>
        'Машина направляется к месту подачи. Ожидайте у точки А.',
      TripStatus.arrived => 'Машина ждёт у точки А. Можно садиться.',
      TripStatus.inProgress =>
        'Хорошей дороги! Водитель завершит поездку в точке Б.',
      _ => '',
    }, style: const TextStyle(color: Color(0xFF6F7E90))),
    const SizedBox(height: 16),
    if (trip.driverId != null)
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            CircleAvatar(child: Icon(Icons.person)),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Учебный водитель',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Подключён в приложении водителя',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.local_taxi_outlined),
          ],
        ),
      ),
    AddressRow(place: trip.pickup, label: 'А', color: customerBlue),
    AddressRow(place: trip.destination, label: 'Б', color: driverGreen),
    const Divider(),
    Row(
      children: [
        Expanded(
          child: Text(
            '${trip.tariff.title} · ${trip.km.toStringAsFixed(1)} км',
          ),
        ),
        Text(
          '${trip.price} ₽',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
    ),
    const SizedBox(height: 6),
    const Text(
      'Стоимость зафиксирована · наличные',
      style: TextStyle(fontSize: 12),
    ),
    RouteSummary(
      route: c.route,
      loading: c.routing,
      onRetry: () => c.updateRoute(force: true),
    ),
    if (trip.status != TripStatus.inProgress)
      OutlinedButton(
        onPressed: c.busy ? null : () => cancel(trip),
        child: const Text('Отменить заказ'),
      ),
    const SizedBox(height: 12),
    const Text(
      'Статус обновляется автоматически. Перемещение машины не моделируется.',
      style: TextStyle(fontSize: 11, color: Color(0xFF78879B)),
    ),
  ];
}
