/// User-agent markers of in-app browsers built on an embedded web view, where
/// Google blocks sign-in with "403 disallowed_useragent". `; wv)` is Android's
/// generic WebView marker; the rest are apps' own (Barcelona is Threads).
final RegExp _embeddedBrowserMarkers = RegExp(
  r'; wv\)|Instagram|FBAN|FBAV|FB_IAB|musical_ly|BytedanceWebview|Snapchat|'
  r'\bLine/|Pinterest|LinkedInApp|Barcelona',
);

/// Whether [userAgent] belongs to an in-app browser such as Instagram's,
/// Facebook's or TikTok's.
bool isEmbeddedBrowser(String userAgent) =>
    _embeddedBrowserMarkers.hasMatch(userAgent);
