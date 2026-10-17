import 'package:brookie_babies/services/payment_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tags the link with the uid and locks the email', () {
    final uri = paymentLinkUri('Premium', uid: 'uid123', email: 'parent+1@example.com')!;

    expect('${uri.origin}${uri.path}', 'https://buy.stripe.com/9AQ9BL9hpbkY4ZGeUV');
    expect(uri.queryParameters, {
      'client_reference_id': 'uid123',
      'locked_prefilled_email': 'parent+1@example.com',
    });
    expect(uri.query, contains('parent%2B1%40example.com'));
  });

  test('leaves out the email when there is none', () {
    final uri = paymentLinkUri('Basic', uid: 'uid123')!;

    expect(uri.queryParameters, {'client_reference_id': 'uid123'});
  });

  test('has a link for every package', () {
    for (final package in ['Basic', 'Premium', 'Ultimate']) {
      expect(paymentLinkUri(package, uid: 'u'), isNotNull, reason: package);
    }
  });

  test('returns null for an unknown package', () {
    expect(paymentLinkUri('', uid: 'uid123'), isNull);
  });
}
