import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'domain.dart';
import 'services.dart';

const customerBlue = Color(0xFF2457DB);
const driverGreen = Color(0xFF087F68);
const ink = Color(0xFF15253D);

class TaxiApp extends StatelessWidget {
  const TaxiApp({super.key, required this.home, required this.isDriver});
  final Widget home;
  final bool isDriver;
  @override
  Widget build(BuildContext context) {
    final accent = isDriver ? driverGreen : customerBlue;
    return MaterialApp(
      title: isDriver ? 'Такси · Водитель' : 'Такси · Клиент',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          primary: accent,
          surface: Colors.white,
          onSurface: ink,
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          centerTitle: false,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
          ),
          titleLarge: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
          ),
          titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(fontSize: 14, height: 1.4),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 68,
          backgroundColor: Colors.white,
          indicatorColor: accent.withValues(alpha: .12),
        ),
      ),
      home: home,
    );
  }
}

class Workspace extends StatelessWidget {
  const Workspace({
    super.key,
    required this.map,
    required this.panel,
    this.phase,
  });
  final Widget map;
  final Widget panel;
  final String? phase;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final wide = size.maxWidth >= 850;
      final sheet = Material(
        color: Colors.white,
        child: SingleChildScrollView(
          key: ValueKey(phase),
          padding: EdgeInsets.all(wide ? 28 : 20),
          child: panel,
        ),
      );
      if (wide) {
        return Row(
          children: [
            Expanded(child: map),
            SizedBox(width: 410, child: sheet),
          ],
        );
      }
      return Column(
        children: [
          Expanded(flex: size.maxHeight < 540 ? 4 : 5, child: map),
          Expanded(flex: 6, child: sheet),
        ],
      );
    },
  );
}

class MapPin {
  const MapPin(this.point, this.label, this.color, {this.car = false});
  final GeoPoint point;
  final String label;
  final Color color;
  final bool car;
}

class CityMap extends StatefulWidget {
  const CityMap({
    super.key,
    required this.pins,
    this.route,
    this.onTap,
    this.onLocate,
    this.locating = false,
    this.hint,
    this.enableTiles = true,
  });
  final List<MapPin> pins;
  final RoutePlan? route;
  final ValueChanged<GeoPoint>? onTap;
  final VoidCallback? onLocate;
  final bool locating;
  final String? hint;
  final bool enableTiles;
  @override
  State<CityMap> createState() => _CityMapState();
}

class _CityMapState extends State<CityMap> {
  final controller = MapController();
  bool ready = false;
  bool failed = false;
  int tileGeneration = 0;
  LatLng ll(GeoPoint p) => LatLng(p.lat, p.lon);
  void fit() {
    if (!ready) {
      return;
    }
    final points = [
      ...?widget.route?.points,
      ...widget.pins.map((p) => p.point),
    ];
    if (points.isEmpty) {
      controller.move(ll(cityCenter), 13);
    } else if (points.length == 1 ||
        points.every((p) => p.distanceTo(points.first) < .02)) {
      controller.move(ll(points.first), 14);
    } else {
      controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points.map(ll).toList()),
          padding: const EdgeInsets.fromLTRB(50, 65, 65, 45),
          maxZoom: 15,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(CityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.pins
        .map((p) => '${p.point.lat},${p.point.lon}')
        .join(':');
    final newKey = widget.pins
        .map((p) => '${p.point.lat},${p.point.lon}')
        .join(':');
    if (oldWidget.route != widget.route || oldKey != newKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          fit();
        }
      });
    }
  }

  void tileFailed() {
    if (failed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !failed) {
        setState(() => failed = true);
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCenter: ll(cityCenter),
          initialZoom: 13,
          minZoom: 3,
          maxZoom: 18,
          backgroundColor: const Color(0xFFE7EDF0),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: () {
            ready = true;
            fit();
          },
          onTap: (_, point) =>
              widget.onTap?.call(GeoPoint(point.latitude, point.longitude)),
        ),
        children: [
          if (widget.enableTiles)
            TileLayer(
              key: ValueKey(tileGeneration),
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'vensar7.taxi.lab',
              maxNativeZoom: 19,
              errorTileCallback: (_, _, _) => tileFailed(),
            ),
          if (widget.route != null)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.route!.points.map(ll).toList(),
                  color: widget.route!.approximate
                      ? const Color(0xFFC17A18)
                      : customerBlue,
                  strokeWidth: 5,
                  borderStrokeWidth: 2,
                  borderColor: Colors.white,
                  pattern: widget.route!.approximate
                      ? const StrokePattern.dotted()
                      : const StrokePattern.solid(),
                ),
              ],
            ),
          MarkerLayer(
            markers: widget.pins
                .map(
                  (pin) => Marker(
                    point: ll(pin.point),
                    width: 46,
                    height: 46,
                    child: Tooltip(
                      message: pin.label,
                      child: Container(
                        decoration: BoxDecoration(
                          color: pin.color,
                          borderRadius: BorderRadius.circular(
                            pin.car ? 12 : 23,
                          ),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Color(0x26000000), blurRadius: 7),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: pin.car
                            ? const Icon(
                                Icons.local_taxi,
                                color: Colors.white,
                                size: 22,
                              )
                            : Text(
                                pin.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                ),
              ),
            ],
          ),
        ],
      ),
      Positioned(
        top: 12,
        left: 12,
        right: 64,
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.hint ?? 'Иркутск · карта города',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
      if (failed)
        Positioned(
          left: 12,
          bottom: 28,
          right: 70,
          child: Material(
            color: const Color(0xFFFFF2D7),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Карта недоступна. Проверьте интернет.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Повторить загрузку карты',
                    onPressed: () => setState(() {
                      failed = false;
                      tileGeneration++;
                    }),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
        ),
      Positioned(
        right: 12,
        top: 12,
        child: Column(
          children: [
            MapButton(
              icon: Icons.add,
              label: 'Приблизить',
              onPressed: () {
                if (ready) {
                  controller.move(
                    controller.camera.center,
                    (controller.camera.zoom + 1).clamp(3, 18),
                  );
                }
              },
            ),
            const SizedBox(height: 7),
            MapButton(
              icon: Icons.remove,
              label: 'Отдалить',
              onPressed: () {
                if (ready) {
                  controller.move(
                    controller.camera.center,
                    (controller.camera.zoom - 1).clamp(3, 18),
                  );
                }
              },
            ),
            const SizedBox(height: 7),
            MapButton(
              icon: Icons.route,
              label: 'Показать весь маршрут',
              onPressed: fit,
            ),
            if (widget.onLocate != null) ...[
              const SizedBox(height: 7),
              MapButton(
                icon: widget.locating ? Icons.hourglass_top : Icons.my_location,
                label: 'Моё местоположение',
                onPressed: widget.locating ? null : widget.onLocate,
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class MapButton extends StatelessWidget {
  const MapButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    elevation: 1,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
    ),
  );
}

class AddressRow extends StatelessWidget {
  const AddressRow({
    super.key,
    required this.place,
    required this.label,
    required this.color,
    this.onTap,
    this.caption,
  });
  final Place place;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? caption;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      radius: 17,
      backgroundColor: color.withValues(alpha: .1),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    ),
    title: Text(
      place.name,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      caption ?? place.address,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12),
    ),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

class Notice extends StatelessWidget {
  const Notice(
    this.text, {
    super.key,
    this.action,
    this.actionLabel = 'Повторить',
  });
  final String text;
  final VoidCallback? action;
  final String actionLabel;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3DB),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 19, color: Color(0xFF8B5B0C)),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        if (action != null)
          TextButton(onPressed: action, child: Text(actionLabel)),
      ],
    ),
  );
}

class RouteSummary extends StatelessWidget {
  const RouteSummary({
    super.key,
    this.route,
    this.loading = false,
    this.onRetry,
  });
  final RoutePlan? route;
  final bool loading;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Строим маршрут…'),
          ],
        ),
      );
    }
    if (route == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.route_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                '${route!.km.toStringAsFixed(1)} км',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 20),
              const Icon(Icons.schedule, size: 18),
              const SizedBox(width: 6),
              Text('≈ ${route!.minutes} мин'),
            ],
          ),
        ),
        if (route!.approximate)
          Notice(
            'Сервис маршрутов недоступен. Пунктир — прямая линия; расстояние и цена примерные.',
            action: onRetry,
          ),
      ],
    );
  }
}

class StatusSteps extends StatelessWidget {
  const StatusSteps({super.key, required this.status});
  final TripStatus status;
  @override
  Widget build(BuildContext context) {
    final index = [
      TripStatus.searching,
      TripStatus.accepted,
      TripStatus.arrived,
      TripStatus.inProgress,
      TripStatus.completed,
    ].indexOf(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: List.generate(
          5,
          (i) => Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == 4 ? 0 : 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i <= index
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFFE7ECF2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TripHistory extends StatelessWidget {
  const TripHistory({super.key, required this.trips, this.driver = false});
  final List<Trip> trips;
  final bool driver;
  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 54, color: Color(0xFF9EAFC2)),
              SizedBox(height: 16),
              Text(
                'Здесь будут ваши поездки',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Завершённые и отменённые заказы сохранятся в истории.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final trip = trips[index];
        return Card(
          elevation: 0,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trip.status.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${trip.price} ₽',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${trip.createdAt.day}.${trip.createdAt.month.toString().padLeft(2, '0')} · ${trip.tariff.title}',
                  style: const TextStyle(color: Color(0xFF6F7E90)),
                ),
                AddressRow(place: trip.pickup, label: 'А', color: customerBlue),
                AddressRow(
                  place: trip.destination,
                  label: 'Б',
                  color: driverGreen,
                ),
                Text(
                  '${trip.km.toStringAsFixed(1)} км · ${trip.minutes} мин · ${trip.demo ? 'Демонстрационный заказ' : 'Учебная поездка'}',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({
    super.key,
    required this.driver,
    required this.identity,
    this.earnings = 0,
  });
  final bool driver;
  final String? identity;
  final int earnings;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 34,
              child: Icon(
                driver ? Icons.drive_eta : Icons.person_outline,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              driver ? 'Кабинет водителя' : 'Ваш профиль',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text('Учебный проект · Иркутск'),
            if (driver)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Заработок за поездки: $earnings ₽',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Как работает приложение',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              driver
                  ? 'Выйдите на линию, выберите заказ и примите его. Отметьте прибытие, начало и завершение поездки. Клиент увидит смену статуса.'
                  : 'Выберите место подачи и назначения, тариф и закажите машину. Заказ появится в приложении водителя. Статус обновляется автоматически.',
            ),
            const SizedBox(height: 20),
            const Text(
              'Геолокация',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 10),
            const Text(
              'Нажмите кнопку с прицелом на карте и разрешите доступ к позиции. GPS используется только по запросу. Можно выбрать адрес вручную. В браузере нужен HTTPS или localhost.',
            ),
            const SizedBox(height: 20),
            const Notice(
              'Это лабораторная работа. Оплата наличными условная, реальные машины не вызываются. Движение автомобиля и авторизация не реализованы.',
            ),
            const SizedBox(height: 12),
            const Text('Адрес учебного сервера'),
            SelectableText(
              apiBaseUrl,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Идентификатор сессии: ${identity ?? 'загрузка…'}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirmCancellation(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: const Text('Заказ закроется у клиента и водителя.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отменить заказ'),
          ),
        ],
      ),
    ) ??
    false;

class PlaceChoice {
  const PlaceChoice({this.place, this.onMap = false});
  final Place? place;
  final bool onMap;
}

Future<PlaceChoice?> choosePlace(BuildContext context, String title) =>
    showModalBottomSheet<PlaceChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PlacePicker(title: title),
    );

class _PlacePicker extends StatefulWidget {
  const _PlacePicker({required this.title});
  final String title;
  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final results = places
        .where(
          (p) => '${p.name} ${p.address}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Поиск по местам Иркутска',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            TextButton.icon(
              onPressed: () =>
                  Navigator.pop(context, const PlaceChoice(onMap: true)),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Выбрать точку на карте'),
            ),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text('Место не найдено. Выберите точку на карте.'),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(results[i].name),
                        subtitle: Text(results[i].address),
                        onTap: () => Navigator.pop(
                          context,
                          PlaceChoice(place: results[i]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
