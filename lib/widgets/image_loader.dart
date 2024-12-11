import 'package:flutter/material.dart';

class ImageLoader extends StatelessWidget{
  const ImageLoader({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
        if (loadingProgress == null) {
          return child; // Image has loaded
        }
        return CircularProgressIndicator(
          value: loadingProgress.expectedTotalBytes != null
              ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
              : null,
        ); // Show progress indicator while loading
      },
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
        return const Icon(
          Icons.error,
          color: Colors.red,
        ); // Display an error icon if image fails to load
      },
    );
  }
}