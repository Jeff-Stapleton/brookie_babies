import 'package:flutter/material.dart';
import 'package:flutter_stripe_web/flutter_stripe_web.dart';
import 'package:web/web.dart' as web;

String getUrlPort() => web.window.location.port;

String getReturnUrl() => web.window.location.href;

Future<void> pay() async {
  await WebStripe.instance.confirmPaymentElement(
    ConfirmPaymentElementOptions(
      confirmParams: ConfirmPaymentParams(return_url: getReturnUrl()),
    ),
  );
}

class CheckoutPage extends StatelessWidget {
  const CheckoutPage({super.key, required this.clientSecret});

  final String clientSecret;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
      ),
      body: ExpressCheckoutElement(
        onConfirm: (value) {
          pay();
        },
        clientSecret: clientSecret,
      )
    );
  }
}