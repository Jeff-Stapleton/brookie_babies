import 'package:brookie_babies/utilities/embedded_browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const inAppBrowsers = {
    'Instagram (iOS)':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 302.0.0.23.114 (iPhone14,2; iOS 17_0; en_US; en; scale=3.00; 1170x2532; 517523539)',
    'Facebook (iOS)':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/437.0.0.36.111;FBBV/545404454;FBDV/iPhone14,2;FBMD/iPhone;FBSN/iOS;FBSV/17.0;FBSS/3;FBID/phone;FBLC/en_US;FBOP/5]',
    'Facebook (Android)':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UD1A.230803.041; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/119.0.6045.66 Mobile Safari/537.36 [FB_IAB/FB4A;FBAV/440.0.0.31.105;]',
    'TikTok (iOS)':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 musical_ly_32.5.0 JsSdk/2.0 NetType/WIFI Channel/App Store ByteLocale/en Region/US',
    'Pinterest (iOS)':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [Pinterest/iOS]',
    'Threads (iOS)':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Barcelona 289.0.0.77.109 (iPhone14,2; iOS 17_0; en_US; en-US; scale=3.00; 1170x2532; 500160043)',
    'LinkedIn (iOS)':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [LinkedInApp]/9.29.1',
    'any Android WebView':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UD1A.230803.041; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/129.0.0.0 Mobile Safari/537.36',
  };
  const browsers = {
    'Safari (iOS)':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    'Chrome (Android)':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36',
    'Chrome (macOS)':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
  };

  inAppBrowsers.forEach((name, userAgent) {
    test('detects $name', () => expect(isEmbeddedBrowser(userAgent), isTrue));
  });
  browsers.forEach((name, userAgent) {
    test('allows $name', () => expect(isEmbeddedBrowser(userAgent), isFalse));
  });
}
