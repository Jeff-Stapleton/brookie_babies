import 'package:brookie_babies/carousel.dart';
import 'package:brookie_babies/packages.dart';
import 'package:brookie_babies/page_footer.dart';
import 'package:brookie_babies/text_section.dart';
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  HomePage({super.key});

  final ScrollController _scrollController = ScrollController();

  navigateToBookingSection() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              children: [
                CarouselExample(),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Spacer(flex: 1),
                        Image.asset('assets/logo.png', scale: 1.5),
                        SizedBox(height: 50),
                        ElevatedButton(onPressed: navigateToBookingSection, child: Text("Book Now")),
                        Spacer(flex: 1),
                      ]
                    ),
                  )
                ),
              ],
            ),
            TextSection(),
            Packages(),
            SizedBox(height: 100),
            PageFooter()
          ],
        ),
      )
    );
  }
}
