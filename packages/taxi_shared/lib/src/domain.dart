import 'dart:math' as math;

class GeoPoint {
  const GeoPoint(this.lat, this.lon);
  final double lat;
  final double lon;
  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
    (json['lat'] as num).toDouble(),
    (json['lon'] as num).toDouble(),
  );
  double distanceTo(GeoPoint other) {
    final dLat = (other.lat - lat) * math.pi / 180;
    final dLon = (other.lon - lon) * math.pi / 180;
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat * math.pi / 180) *
            math.cos(other.lat * math.pi / 180) *
            math.pow(math.sin(dLon / 2), 2);
    return 6371 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}

class Place {
  const Place(this.name, this.address, this.point);
  final String name;
  final String address;
  final GeoPoint point;
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'point': point.toJson(),
  };
  factory Place.fromJson(Map<String, dynamic> json) => Place(
    json['name'] as String,
    json['address'] as String,
    GeoPoint.fromJson(json['point'] as Map<String, dynamic>),
  );
  static Place onMap(GeoPoint point) => Place(
    'Точка на карте',
    '${point.lat.toStringAsFixed(5)}, ${point.lon.toStringAsFixed(5)}',
    point,
  );
}

const cityCenter = GeoPoint(52.2864, 104.2807);
const places = [
  Place('Сквер Кирова', 'Центр, Иркутск', GeoPoint(52.2864, 104.2807)),
  Place('130-й квартал', 'Улица 3 Июля', GeoPoint(52.2738, 104.2897)),
  Place(
    'Драматический театр',
    'Улица Карла Маркса, 14',
    GeoPoint(52.2775, 104.2823),
  ),
  Place(
    'Железнодорожный вокзал',
    'Улица Челнокова, 1',
    GeoPoint(52.2836, 104.2592),
  ),
  Place('Аэропорт Иркутск', 'Улица Ширямова, 13', GeoPoint(52.2730, 104.3890)),
  Place('Центральный рынок', 'Улица Чехова', GeoPoint(52.2830, 104.3007)),
  Place(
    'Нижняя набережная',
    'Улица Нижняя Набережная',
    GeoPoint(52.2912, 104.2808),
  ),
  Place('Бульвар Гагарина', 'Набережная Ангары', GeoPoint(52.2746, 104.2777)),
];

enum Tariff {
  economy('Эконом', 'На каждый день', 99, 24, 0),
  comfort('Комфорт', 'Просторный салон', 149, 32, 1),
  business('Бизнес', 'Поездка с комфортом', 249, 48, 2);

  const Tariff(
    this.title,
    this.subtitle,
    this.base,
    this.perKm,
    this.iconIndex,
  );
  final String title;
  final String subtitle;
  final int base;
  final int perKm;
  final int iconIndex;
  int price(double km) => ((base + perKm * km) / 10).ceil() * 10;
}

enum TripStatus {
  searching('Ищем водителя'),
  accepted('Водитель едет к вам'),
  arrived('Водитель на месте'),
  inProgress('В пути'),
  completed('Поездка завершена'),
  cancelled('Заказ отменён');

  const TripStatus(this.title);
  final String title;
  bool get isActive => this != completed && this != cancelled;
}

class RoutePlan {
  const RoutePlan({
    required this.points,
    required this.km,
    required this.minutes,
    this.approximate = false,
  });
  final List<GeoPoint> points;
  final double km;
  final int minutes;
  final bool approximate;
}

class Trip {
  const Trip({
    required this.id,
    required this.customerId,
    required this.pickup,
    required this.destination,
    required this.tariff,
    required this.km,
    required this.minutes,
    required this.price,
    required this.status,
    required this.createdAt,
    this.driverId,
    this.demo = false,
  });
  final String id;
  final String customerId;
  final String? driverId;
  final Place pickup;
  final Place destination;
  final Tariff tariff;
  final double km;
  final int minutes;
  final int price;
  final TripStatus status;
  final DateTime createdAt;
  final bool demo;
  Map<String, dynamic> toJson() => {
    'id': id,
    'customerId': customerId,
    'driverId': driverId,
    'pickup': pickup.toJson(),
    'destination': destination.toJson(),
    'tariff': tariff.name,
    'km': km,
    'minutes': minutes,
    'price': price,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'demo': demo,
  };
  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String,
    customerId: json['customerId'] as String,
    driverId: json['driverId'] as String?,
    pickup: Place.fromJson(json['pickup'] as Map<String, dynamic>),
    destination: Place.fromJson(json['destination'] as Map<String, dynamic>),
    tariff: Tariff.values.byName(json['tariff'] as String),
    km: (json['km'] as num).toDouble(),
    minutes: json['minutes'] as int,
    price: json['price'] as int,
    status: TripStatus.values.byName(json['status'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    demo: json['demo'] == true,
  );
  Trip transition(TripStatus next, {String? driver}) => Trip(
    id: id,
    customerId: customerId,
    driverId: driver ?? driverId,
    pickup: pickup,
    destination: destination,
    tariff: tariff,
    km: km,
    minutes: minutes,
    price: price,
    status: next,
    createdAt: createdAt,
    demo: demo,
  );
}
