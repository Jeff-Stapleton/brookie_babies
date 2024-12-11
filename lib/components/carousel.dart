import 'dart:async';
import 'dart:developer';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class CarouselExample extends StatefulWidget {
  const CarouselExample({super.key});

  @override
  State<CarouselExample> createState() => _CarouselExampleState();
}

class _CarouselExampleState extends State<CarouselExample> {
  final PageController _pageController = PageController();
  final String _storageFolderPath = 'gs://brookie-babies.firebasestorage.app/_admin/gallery';
  List<String> _imageUrls = [];
  int _currentPage = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    pageViewHandler();
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> pageViewHandler() async {
    await _getImagesFromFolder();
    // Initial scroll so there is no delay
    _scrollToNextPage();
      // Handles all scrolling after the first
    _timer = Timer.periodic(Duration(seconds: 10), (Timer timer) {
      _scrollToNextPage();
    });
  }

  void _scrollToNextPage() {
    if (_currentPage < _imageUrls.length - 1) {
      _currentPage++;
    } else {
      _currentPage = 0;
    }

    _pageController.animateToPage(
      _currentPage,
      duration: Duration(milliseconds: 10000),
      curve: Curves.linear,
    );
  }

  Future<void> _getImagesFromFolder() async {
    try {
      final storageRef = FirebaseStorage.instance.ref(_storageFolderPath);
      final ListResult result = await storageRef.listAll();
      for (Reference child in result.items) {
        final downloadUrl = await child.getDownloadURL();
        log(downloadUrl);
        setState(() {
          _imageUrls.add(downloadUrl);
        });
      }
    } catch (e) {
      log('Error getting images: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height),
        child: PageView.builder(
          controller: _pageController,
          physics: NeverScrollableScrollPhysics(),
          itemCount: _imageUrls.length,
          itemBuilder: (context, index) {
            return Image.network(
              _imageUrls[index],
              fit: BoxFit.cover,
            );
          },
          onPageChanged: (index) {
            setState(() {
              _currentPage = index;
            });
          },
        ),
      )
    );
  }
}