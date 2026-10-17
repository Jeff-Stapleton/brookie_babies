import 'package:brookie_babies/models/session_package.dart';

/// Stripe Payment Links, keyed by [SessionPackage.name]: one for every
/// package in [SessionPackage.all].
///
/// Interim: these will be replaced by Stripe Checkout Sessions created by a
/// Cloud Function, which takes the user from their verified sign-in rather
/// than from a URL anyone can edit.
const Map<String, String> kPaymentLinks = {
  'Basic': 'https://buy.stripe.com/7sI7tD0KTfBedwccMM',
  'Premium': 'https://buy.stripe.com/9AQ9BL9hpbkY4ZGeUV',
  'Ultimate': 'https://buy.stripe.com/aEUcNXctB74IfEk002',
};

/// The Payment Link for [packageName], tagged so the payment can be matched to
/// the signed-in customer in Stripe: [uid] as `client_reference_id` and
/// [email] as `locked_prefilled_email`, which the customer can't change.
///
/// Returns null for an unknown package.
Uri? paymentLinkUri(String packageName, {required String uid, String? email}) {
  final link = kPaymentLinks[packageName];
  if (link == null) return null;
  return Uri.parse(link).replace(queryParameters: {
    'client_reference_id': uid,
    if (email != null && email.isNotEmpty) 'locked_prefilled_email': email,
  });
}
