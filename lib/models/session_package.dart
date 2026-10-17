/// A session package families can book. Each one has a Stripe Payment Link
/// under the same [name] (services/payment_links.dart).
class SessionPackage {
  const SessionPackage({required this.name, required this.price, required this.inclusions});

  final String name;

  /// Whole dollars.
  final int price;

  /// What the package includes, in the same order on every package so they
  /// can be compared line by line.
  final List<String> inclusions;

  /// The price as shown: "$50".
  String get priceLabel => '\$$price';

  /// Every package, cheapest first.
  static const all = [
    SessionPackage(
      name: 'Basic',
      price: 25,
      inclusions: ['15-minute session', 'One person', '5–10 edited photos'],
    ),
    SessionPackage(
      name: 'Premium',
      price: 50,
      inclusions: ['15-minute session', 'One person', '5–10 edited photos'],
    ),
    SessionPackage(
      name: 'Ultimate',
      price: 99,
      inclusions: ['15-minute session', 'One person', '5–10 edited photos'],
    ),
  ];

  /// The package called [name], or null if there isn't one.
  static SessionPackage? named(String name) {
    for (final package in all) {
      if (package.name == name) return package;
    }
    return null;
  }
}
