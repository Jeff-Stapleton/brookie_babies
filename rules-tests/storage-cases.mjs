// What storage.rules must allow and deny, as Rules API test cases:
// [expectation, name, test case]. scripts/test-rules.sh sends them with the
// repository's rules to the read-only test endpoint, which deploys nothing
// and touches no files. Add a case with every rules change.
const BUCKET = 'brookie-babies.firebasestorage.app';
const B = `/b/${BUCKET}/o/`;
const T = '2026-10-19T12:00:00Z';
const MiB = 1024 * 1024;
const adm = {uid: 'adm', token: {admin: true, email: 'b@gmail.com', email_verified: true}};
const usr = {uid: 'u1', token: {email: 'j@gmail.com', email_verified: true}};

const res = (name, contentType, size) => ({
  name, bucket: BUCKET, size, metadata: {},
  ...(contentType === undefined ? {} : {contentType}),
});
const read = (auth, path, method) => ({request: {...(auth ? {auth} : {}), path: B + path, method, time: T}});
// (No URL_ENCODED cases: with that encoding the API treats %2F as part of one
// segment, so "_admin%2Fgallery" never matches /_admin/gallery/..., whatever
// the rules say. Plain paths model list prefixes.)
const put = (auth, path, method, contentType, size) =>
  ({request: {...(auth ? {auth} : {}), path: B + path, method, time: T, resource: res(path, contentType, size)}});
const del = (auth, path) => ({request: {...(auth ? {auth} : {}), path: B + path, method: 'delete', time: T}});

export const cases = [
  // ---- _admin/gallery: public read ----
  ['ALLOW', 'public list _admin/gallery', read(null, '_admin/gallery', 'list')],
  ['ALLOW', 'public get _admin/gallery/a.jpg', read(null, '_admin/gallery/a.jpg', 'get')],
  ['ALLOW', 'public get nested _admin/gallery/sub/a.jpg', read(null, '_admin/gallery/sub/a.jpg', 'get')],
  ['ALLOW', 'signed-in user list _admin/gallery', read(usr, '_admin/gallery', 'list')],
  // ---- _admin/gallery: admin create ----
  ['ALLOW', 'admin create jpeg a.jpg', put(adm, '_admin/gallery/a.jpg', 'create', 'image/jpeg', 1000)],
  ['ALLOW', 'admin create jpeg A.JPEG (case-insensitive extension)', put(adm, '_admin/gallery/A.JPEG', 'create', 'image/jpeg', 1000)],
  ['ALLOW', 'admin create png b.png', put(adm, '_admin/gallery/b.png', 'create', 'image/png', 1000)],
  ['ALLOW', 'admin create webp c.WebP', put(adm, '_admin/gallery/c.WebP', 'create', 'image/webp', 1000)],
  ['ALLOW', 'admin create jpeg of 20 MiB - 1 byte', put(adm, '_admin/gallery/big.jpg', 'create', 'image/jpeg', 20 * MiB - 1)],
  ['ALLOW', 'admin create 1-byte jpeg', put(adm, '_admin/gallery/tiny.jpg', 'create', 'image/jpeg', 1)],
  ['DENY', 'admin create jpeg of exactly 20 MiB', put(adm, '_admin/gallery/big.jpg', 'create', 'image/jpeg', 20 * MiB)],
  ['DENY', 'admin create 0-byte jpeg', put(adm, '_admin/gallery/empty.jpg', 'create', 'image/jpeg', 0)],
  ['DENY', 'admin create HEIC (image/heic, .heic)', put(adm, '_admin/gallery/IMG_1.HEIC', 'create', 'image/heic', 1000)],
  ['DENY', 'admin create HEIC bytes named .jpg', put(adm, '_admin/gallery/IMG_1.jpg', 'create', 'image/heic', 1000)],
  ['DENY', 'admin create jpeg named .heic', put(adm, '_admin/gallery/IMG_1.heic', 'create', 'image/jpeg', 1000)],
  ['DENY', 'admin create svg', put(adm, '_admin/gallery/a.svg', 'create', 'image/svg+xml', 1000)],
  ['DENY', 'admin create gif', put(adm, '_admin/gallery/a.gif', 'create', 'image/gif', 1000)],
  ['DENY', 'admin create jpeg with no extension', put(adm, '_admin/gallery/photo', 'create', 'image/jpeg', 1000)],
  // \\. in the rules string must be a literal dot, not "any character".
  ['DENY', 'admin create jpeg named photojpg (no dot)', put(adm, '_admin/gallery/photojpg', 'create', 'image/jpeg', 1000)],
  ['ALLOW', 'admin create png bytes named .jpg (type and name each allowed)', put(adm, '_admin/gallery/p.jpg', 'create', 'image/png', 1000)],
  ['DENY', 'admin create jpeg named a.jpg.html',put(adm, '_admin/gallery/a.jpg.html', 'create', 'image/jpeg', 1000)],
  ['DENY', 'admin create content type "image/jpeg; x=1"', put(adm, '_admin/gallery/a.jpg', 'create', 'image/jpeg; x=1', 1000)],
  ['DENY', 'admin create with no content type', put(adm, '_admin/gallery/a.jpg', 'create', undefined, 1000)],
  ['DENY', 'admin create nested _admin/gallery/sub/a.jpg', put(adm, '_admin/gallery/sub/a.jpg', 'create', 'image/jpeg', 1000)],
  ['DENY', 'admin update (overwrite) _admin/gallery/a.jpg', put(adm, '_admin/gallery/a.jpg', 'update', 'image/jpeg', 1000)],
  ['DENY', 'non-admin create _admin/gallery/a.jpg', put(usr, '_admin/gallery/a.jpg', 'create', 'image/jpeg', 1000)],
  ['DENY', 'signed out create _admin/gallery/a.jpg', put(null, '_admin/gallery/a.jpg', 'create', 'image/jpeg', 1000)],
  ['DENY', 'admin claim "true" string create', put({uid: 'adm', token: {admin: 'true'}}, '_admin/gallery/a.jpg', 'create', 'image/jpeg', 1000)],
  ['ALLOW', 'admin delete _admin/gallery/a.jpg', del(adm, '_admin/gallery/a.jpg')],
  ['ALLOW', 'admin delete non-photo _admin/gallery/IMG_1.HEIC', del(adm, '_admin/gallery/IMG_1.HEIC')],
  ['DENY', 'non-admin delete _admin/gallery/a.jpg', del(usr, '_admin/gallery/a.jpg')],
  ['DENY', 'signed out delete _admin/gallery/a.jpg', del(null, '_admin/gallery/a.jpg')],
  // ---- galleries/<bookingId>/ ----
  ['ALLOW', 'admin list galleries/abc', read(adm, 'galleries/abc', 'list')],
  ['ALLOW', 'admin list galleries/abc/edits (subfolder)', read(adm, 'galleries/abc/edits', 'list')],
  ['ALLOW', 'admin get galleries/abc/IMG.jpg', read(adm, 'galleries/abc/IMG.jpg', 'get')],
  ['ALLOW', 'admin get galleries/abc/edits/IMG.jpg', read(adm, 'galleries/abc/edits/IMG.jpg', 'get')],
  ['ALLOW', 'admin create galleries jpeg', put(adm, 'galleries/abc/IMG.jpg', 'create', 'image/jpeg', 8 * MiB)],
  ['ALLOW', 'admin create galleries heic', put(adm, 'galleries/abc/IMG.heic', 'create', 'image/heic', 5 * MiB)],
  ['ALLOW', 'admin create galleries tiff in a subfolder', put(adm, 'galleries/abc/edits/IMG.tif', 'create', 'image/tiff', 60 * MiB)],
  ['ALLOW', 'admin create galleries 100 MiB - 1 byte', put(adm, 'galleries/abc/huge.jpg', 'create', 'image/jpeg', 100 * MiB - 1)],
  ['DENY', 'admin create galleries exactly 100 MiB', put(adm, 'galleries/abc/huge.jpg', 'create', 'image/jpeg', 100 * MiB)],
  ['DENY', 'admin create galleries 0-byte', put(adm, 'galleries/abc/empty.jpg', 'create', 'image/jpeg', 0)],
  ['DENY', 'admin create galleries text/html', put(adm, 'galleries/abc/x.html', 'create', 'text/html', 10)],
  ['DENY', 'admin create galleries application/zip', put(adm, 'galleries/abc/x.zip', 'create', 'application/zip', 10)],
  ['DENY', 'admin create galleries video/mp4', put(adm, 'galleries/abc/x.mp4', 'create', 'video/mp4', 10)],
  ['DENY', 'admin create galleries with no content type', put(adm, 'galleries/abc/x.jpg', 'create', undefined, 10)],
  ['DENY', 'admin update galleries (overwrite)', put(adm, 'galleries/abc/IMG.jpg', 'update', 'image/jpeg', 10)],
  // {allPaths=**} matches zero segments, so this is "booking folder IMG.jpg" (admin only; no
  // booking's prefix galleries/<id>/ contains it). Harmless, and how the match is written.
  ['ALLOW', 'admin create galleries/IMG.jpg (** matches zero segments)', put(adm, 'galleries/IMG.jpg', 'create', 'image/jpeg', 10)],
  ['DENY', 'non-admin create galleries/IMG.jpg', put(usr, 'galleries/IMG.jpg', 'create', 'image/jpeg', 10)],
  ['DENY', 'admin list galleries (all bookings, no booking id)', read(adm, 'galleries', 'list')],
  ['DENY', 'non-admin list galleries/abc', read(usr, 'galleries/abc', 'list')],
  ['DENY', 'non-admin get galleries/abc/IMG.jpg', read(usr, 'galleries/abc/IMG.jpg', 'get')],
  ['DENY', 'signed out get galleries/abc/IMG.jpg', read(null, 'galleries/abc/IMG.jpg', 'get')],
  ['DENY', 'non-admin create galleries', put(usr, 'galleries/abc/IMG.jpg', 'create', 'image/jpeg', 10)],
  ['ALLOW', 'admin delete galleries photo', del(adm, 'galleries/abc/IMG.jpg')],
  ['ALLOW', 'admin delete galleries photo in a subfolder', del(adm, 'galleries/abc/edits/IMG.jpg')],
  ['DENY', 'non-admin delete galleries photo', del(usr, 'galleries/abc/IMG.jpg')],
  // ---- gallery-zips/ ----
  ['ALLOW', 'admin delete gallery-zips/abc.zip', del(adm, 'gallery-zips/abc.zip')],
  ['DENY', 'admin get gallery-zips/abc.zip', read(adm, 'gallery-zips/abc.zip', 'get')],
  ['DENY', 'admin list gallery-zips', read(adm, 'gallery-zips', 'list')],
  ['DENY', 'admin create gallery-zips/abc.zip', put(adm, 'gallery-zips/abc.zip', 'create', 'application/zip', 10)],
  ['DENY', 'non-admin delete gallery-zips/abc.zip', del(usr, 'gallery-zips/abc.zip')],
  ['DENY', 'signed out get gallery-zips/abc.zip', read(null, 'gallery-zips/abc.zip', 'get')],
  // ---- everything else ----
  ['DENY', 'admin create elsewhere (uploads/x.jpg)', put(adm, 'uploads/x.jpg', 'create', 'image/jpeg', 10)],
  ['DENY', 'admin get elsewhere (_admin/other/x.jpg)', read(adm, '_admin/other/x.jpg', 'get')],
];
