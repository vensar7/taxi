import 'package:flutter/material.dart';
import 'package:taxi_shared/taxi_shared.dart';

class DriverApp extends StatelessWidget {
  const DriverApp({super.key, this.controller, this.enableTiles = true});
  final TaxiController? controller;
  final bool enableTiles;
  @override
  Widget build(BuildContext context) => TaxiApp(
    isDriver: true,
    home: DriverHome(controller: controller, enableTiles: enableTiles),
  );
}

class DriverHome extends StatefulWidget {
  const DriverHome({super.key, this.controller, this.enableTiles = true});
  final TaxiController? controller;
  final bool enableTiles;
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  late final TaxiController c;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    c = widget.controller ?? TaxiController(isDriver: true);
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

  Future<void> cancel(Trip trip) async {
    if (await confirmCancellation(context)) {
      await c.act(trip, 'cancel');
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = c.displayed;
    final onTrip = trip?.status == TripStatus.inProgress;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: driverGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.drive_eta, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'Такси Водитель',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить заказы',
            onPressed: c.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: switch (tab) {
          1 => TripHistory(trips: c.history, driver: true),
          2 => AboutPage(
            driver: true,
            identity: c.identity,
            earnings: c.earnings,
          ),
          _ => Workspace(
            phase: '${c.active?.id}:${c.active?.status.name}',
            map: CityMap(
              enableTiles: widget.enableTiles,
              route: c.route,
              hint: trip == null
                  ? 'Иркутск · заказы рядом'
                  : onTrip
                  ? 'Маршрут до назначения'
                  : 'Маршрут до клиента',
              pins: [
                MapPin(
                  c.driverPosition,
                  'Ваша позиция',
                  driverGreen,
                  car: true,
                ),
                if (trip != null) ...[
                  MapPin(trip.pickup.point, 'А', customerBlue),
                  MapPin(trip.destination.point, 'Б', driverGreen),
                ] else if (c.online)
                  ...c.available.map(
                    (t) => MapPin(t.pickup.point, 'А', customerBlue),
                  ),
              ],
              onLocate: c.geolocate,
              locating: c.locating,
            ),
            panel: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.error != null) Notice(c.error!, action: c.refresh),
                if (c.active != null)
                  ...activeTrip(context, c.active!)
                else
                  ...orders(context),
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
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Заказы',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Поездки',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Кабинет',
          ),
        ],
      ),
    );
  }

  List<Widget> orders(BuildContext context) => [
    Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.online ? 'Вы на линии' : 'Вы не на линии',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                c.connected
                    ? 'Связь с сервером установлена'
                    : 'Сервер недоступен',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6F7E90)),
              ),
            ],
          ),
        ),
        Switch(value: c.online, onChanged: c.busy ? null : c.toggleOnline),
      ],
    ),
    const SizedBox(height: 14),
    if (!c.online) ...[
      const SizedBox(height: 28),
      const Icon(Icons.coffee_outlined, size: 48, color: Color(0xFF9EAFC1)),
      const SizedBox(height: 14),
      const Text(
        'Можно сделать перерыв',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Включите переключатель, чтобы снова видеть заказы.',
        textAlign: TextAlign.center,
      ),
    ] else ...[
      Row(
        children: [
          Expanded(
            child: Text(
              'Доступные заказы',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            '${c.available.length}',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: driverGreen,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (c.available.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 26),
          child: Column(
            children: [
              Icon(Icons.radar, size: 42, color: Color(0xFF9EAFC1)),
              SizedBox(height: 12),
              Text(
                'Ждём новые заказы',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Создайте заказ в приложении клиента. Он появится здесь автоматически.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      for (final trip in c.available) orderCard(context, trip),
      if (c.selected != null) ...[
        const SizedBox(height: 6),
        RouteSummary(
          route: c.route,
          loading: c.routing,
          onRetry: () => c.updateRoute(force: true),
        ),
        FilledButton(
          onPressed: !c.busy && c.connected && c.online
              ? () => c.act(c.selected!, 'accept')
              : null,
          child: Text(
            c.busy
                ? 'Принимаем заказ…'
                : 'Принять заказ · ${c.selected!.price} ₽',
          ),
        ),
      ],
      const SizedBox(height: 14),
      const Text(
        'Выберите заказ, чтобы увидеть маршрут до клиента. Метка автомобиля — ваша последняя полученная позиция.',
        style: TextStyle(fontSize: 11, color: Color(0xFF78879B)),
      ),
    ],
  ];

  Widget orderCard(BuildContext context, Trip trip) {
    final selected = c.selected?.id == trip.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xFFEBF7F3) : const Color(0xFFF5F7FA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? driverGreen : const Color(0xFFE3E9F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: c.busy ? null : () => c.select(trip),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trip.tariff.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${trip.price} ₽',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (trip.demo)
                  const Text(
                    'Демо-заказ',
                    style: TextStyle(color: Color(0xFF6F7E90), fontSize: 11),
                  ),
                const SizedBox(height: 8),
                Text(
                  'А  ${trip.pickup.name}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                Text('Б  ${trip.destination.name}'),
                const SizedBox(height: 10),
                Text(
                  '${trip.km.toStringAsFixed(1)} км · ≈ ${trip.minutes} мин · наличные',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6F7E90),
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: driverGreen),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Выбран · маршрут на карте',
                            style: TextStyle(fontSize: 12, color: driverGreen),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> activeTrip(BuildContext context, Trip trip) => [
    Text(switch (trip.status) {
      TripStatus.accepted => 'Едем к клиенту',
      TripStatus.arrived => 'Ожидаем клиента',
      TripStatus.inProgress => 'Выполняем поездку',
      _ => trip.status.title,
    }, style: Theme.of(context).textTheme.headlineMedium),
    StatusSteps(status: trip.status),
    Text(switch (trip.status) {
      TripStatus.accepted => 'Следуйте к точке А и отметьте прибытие.',
      TripStatus.arrived => 'Начните поездку, когда пассажир сядет в машину.',
      TripStatus.inProgress =>
        'Следуйте к точке Б. Завершите заказ после прибытия.',
      _ => '',
    }, style: const TextStyle(color: Color(0xFF6F7E90))),
    const SizedBox(height: 12),
    AddressRow(place: trip.pickup, label: 'А', color: customerBlue),
    AddressRow(place: trip.destination, label: 'Б', color: driverGreen),
    RouteSummary(
      route: c.route,
      loading: c.routing,
      onRetry: () => c.updateRoute(force: true),
    ),
    const Divider(),
    Row(
      children: [
        Expanded(child: Text('${trip.tariff.title}\nНаличные')),
        Text(
          '${trip.price} ₽',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
    ),
    const SizedBox(height: 18),
    FilledButton.icon(
      onPressed: c.busy || !c.connected
          ? null
          : () => c.act(trip, switch (trip.status) {
              TripStatus.accepted => 'arrive',
              TripStatus.arrived => 'start',
              _ => 'complete',
            }),
      icon: Icon(c.busy ? Icons.hourglass_top : Icons.check_circle_outline),
      label: Text(
        c.busy
            ? 'Сохраняем…'
            : switch (trip.status) {
                TripStatus.accepted => 'Я на месте',
                TripStatus.arrived => 'Начать поездку',
                _ => 'Завершить поездку',
              },
      ),
    ),
    if (trip.status != TripStatus.inProgress)
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton(
          onPressed: c.busy ? null : () => cancel(trip),
          child: const Text('Отменить заказ'),
        ),
      ),
    const SizedBox(height: 12),
    const Text(
      'Клиент увидит изменение статуса автоматически. Расчёты учебные.',
      style: TextStyle(fontSize: 11, color: Color(0xFF78879B)),
    ),
  ];
}
