import 'package:flutter/material.dart';

class UncontainedLayoutCard extends StatelessWidget {
  const UncontainedLayoutCard({
    super.key,
    required this.index,
    required this.label,
  });

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.primaries[index % Colors.primaries.length].withOpacity(0.5),
      child: Center(
        child: Image.network(
          'https://firebasestorage.googleapis.com/v0/b/brookie-babies.firebasestorage.app/o/_admin%2Fgallery%2FIMG_1672.JPG?alt=media&token=cecc1b32-a3ac-40e3-ad8f-e96ea2132872',
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
        ),
      ),
    );
  }
}