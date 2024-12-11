import 'package:flutter/material.dart';

class PageFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo Section
          Image.asset(
            'assets/logo.png', // Replace with your logo's asset path
            height: 60,
          ),
          SizedBox(height: 20),
          // Social Media Links Section
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.facebook),
                color: Colors.white,
                onPressed: () {
                  // Add your Facebook link here
                  print("Facebook tapped");
                },
              ),
              IconButton(
                icon: Icon(Icons.camera_alt), // Placeholder for Instagram
                color: Colors.white,
                onPressed: () {
                  // Add your Instagram link here
                  print("Instagram tapped");
                },
              ),
              IconButton(
                icon: Icon(Icons.music_note), // Placeholder for TikTok
                color: Colors.white,
                onPressed: () {
                  // Add your TikTok link here
                  print("TikTok tapped");
                },
              ),
              IconButton(
                icon: Icon(Icons.work), // Placeholder for LinkedIn
                color: Colors.white,
                onPressed: () {
                  // Add your LinkedIn link here
                  print("LinkedIn tapped");
                },
              ),
            ],
          ),
          SizedBox(height: 20),
          // Copyright Text
          Text(
            '© 2024 Your Company Name. All rights reserved.',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
