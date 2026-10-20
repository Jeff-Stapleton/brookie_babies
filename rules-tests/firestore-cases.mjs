// What firestore.rules must allow and deny, as Rules API test cases:
// [expectation, name, test case]. scripts/test-rules.sh sends them with the
// repository's rules to the read-only test endpoint, which deploys nothing
// and reads no data. Add a case with every rules change.
//
// `existing` is the document as stored (resource.data); a write's
// request.resource.data is the document as it would be after it.
const P =(id) => `/databases/(default)/documents/bookings/${id}`;
const HOME = '/databases/(default)/documents/site/home';
const T = '2026-10-19T12:00:00Z';
const EARLIER = '2026-10-19T11:00:00Z';

const paid = {uid: 'cust1', email: 'jane@gmail.com', status: 'paid', packageName: 'Basic', date: '2026-11-01', time: '10:00', photosReady: false, createdAt: EARLIER};
const adhoc = {status: 'adhoc', name: 'The Harper family', email: 'jane@gmail.com', packageName: 'Premium', date: '2026-11-01', time: '10:00', location: 'Liberty Park', photosReady: false, createdAt: EARLIER, createdBy: 'adm'};
const newAdhoc = {status: 'adhoc', name: 'The Harper family', email: 'jane@gmail.com', packageName: 'Premium', date: '2026-11-01', time: '10:00', location: 'Liberty Park', photosReady: false, createdAt: T, createdBy: 'adm'};
const minimalAdhoc = {status: 'adhoc', name: 'Harpers', email: 'jane@gmail.com', date: '2026-11-01', photosReady: false, createdAt: T, createdBy: 'adm'};

const tok = (extra = {}) => ({email: 'jane@gmail.com', email_verified: true, ...extra});
const customer = {uid: 'cust1', token: tok()};
const guest = {uid: 'g1', token: tok()};
const admin = {uid: 'adm', token: {admin: true, email: 'brooke@gmail.com', email_verified: true}};

const without = (obj, ...keys) => Object.fromEntries(Object.entries(obj).filter(([k]) => !keys.includes(k)));
const get = (auth, id, existing, method = 'get') => ({request: {...(auth ? {auth} : {}), path: P(id), method, time: T}, existing});
const write = (auth, id, method, next, existing) => ({request: {...(auth ? {auth} : {}), path: P(id), method, time: T, ...(next ? {resource: {data: next}} : {})}, existing});
const upd = (existing, changes, removed = [], auth = admin, id = 'x1') =>
  write(auth, id, 'update', {...without(existing, ...removed), ...changes}, existing);
const updAdhoc = (changes, removed = [], auth = admin) => upd(adhoc, {updatedAt: T, ...changes}, removed, auth, 'c1');
const updPaid = (changes, removed = [], existing = paid) => upd(existing, {updatedAt: T, ...changes}, removed, admin, 'b1');
const home = (auth, method, next, existing) => ({request: {...(auth ? {auth} : {}), path: HOME, method, time: T, ...(next ? {resource: {data: next}} : {})}, existing});
const names7 = ['1.jpg', '2.jpg', '3.jpg', '4.jpg', '5.jpg', '6.jpg', '7.jpg'];

const written = [
  // ---- reads: customers (uid) ----
  ['ALLOW', 'customer get own paid booking', get(customer, 'b1', paid)],
  ['ALLOW', 'customer list own paid booking', get(customer, 'b1', paid, 'list')],
  ['ALLOW', 'customer without email claim gets own booking', get({uid: 'cust1', token: {}}, 'b1', paid)],
  ['ALLOW', 'customer unverified email gets own booking', get({uid: 'cust1', token: tok({email_verified: false})}, 'b1', paid)],
  ['ALLOW', 'customer gets own hand-entered booking with no status', get(customer, 'b2', without(paid, 'status'))],
  ['ALLOW', 'customer gets own booking whose email is someone else\'s', get(customer, 'b1', {...paid, email: 'other@x.com'})],
  ['DENY', 'another customer get paid booking', get({uid: 'cust2', token: tok({email: 'bob@gmail.com'})}, 'b1', paid)],
  ['DENY', 'signed out get paid booking', get(null, 'b1', paid)],
  // ---- reads: ad hoc guests (verified email) ----
  ['ALLOW', 'guest verified email get adhoc', get(guest, 'c1', adhoc)],
  ['ALLOW', 'guest verified email list adhoc', get(guest, 'c1', adhoc, 'list')],
  ['ALLOW', 'guest mixed-case token email get adhoc', get({uid: 'g1', token: tok({email: 'Jane@Gmail.COM'})}, 'c1', adhoc)],
  ['DENY', 'guest unverified email get adhoc', get({uid: 'g1', token: tok({email_verified: false})}, 'c1', adhoc)],
  ['DENY', 'guest without email_verified claim get adhoc', get({uid: 'g1', token: {email: 'jane@gmail.com'}}, 'c1', adhoc)],
  ['DENY', 'guest email_verified "true" string get adhoc', get({uid: 'g1', token: tok({email_verified: 'true'})}, 'c1', adhoc)],
  ['DENY', 'guest without email claim get adhoc', get({uid: 'g1', token: {email_verified: true}}, 'c1', adhoc)],
  ['DENY', 'guest verified other email get adhoc', get({uid: 'g1', token: tok({email: 'bob@gmail.com'})}, 'c1', adhoc)],
  ['DENY', 'guest email vs PAID booking with same email (get)', get(guest, 'b1', paid)],
  ['DENY', 'guest email vs PAID booking with same email (list)', get(guest, 'b1', paid, 'list')],
  ['DENY', 'guest email vs status "Adhoc" (not exact)', get(guest, 'c1', {...adhoc, status: 'Adhoc'})],
  ['DENY', 'guest vs stored mixed-case email', get(guest, 'c1', {...adhoc, email: 'Jane@gmail.com'})],
  ['DENY', 'signed out get adhoc', get(null, 'c1', adhoc)],
  // ---- reads: admins ----
  ['ALLOW', 'admin get paid booking', get(admin, 'b1', paid)],
  ['ALLOW', 'admin list paid booking', get(admin, 'b1', paid, 'list')],
  ['ALLOW', 'admin get adhoc (no uid)', get(admin, 'c1', adhoc)],
  ['ALLOW', 'admin list adhoc (no uid)', get(admin, 'c1', adhoc, 'list')],
  ['ALLOW', 'admin get hand-entered doc with no uid or status', get(admin, 'z1', {date: 'soon'})],
  ['DENY', 'admin claim "true" string get paid', get({uid: 'adm', token: {admin: 'true'}}, 'b1', paid)],
  ['DENY', 'admin claim false get paid', get({uid: 'adm', token: {admin: false}}, 'b1', paid)],

  // ---- create ----
  ['ALLOW', 'admin create valid adhoc (all fields)', write(admin, 'n1', 'create', newAdhoc)],
  ['ALLOW', 'admin create valid adhoc (required fields only)', write(admin, 'n1', 'create', minimalAdhoc)],
  ['ALLOW', 'admin create name of 100 chars, location of 200', write(admin, 'n1', 'create', {...newAdhoc, name: 'n'.repeat(100), location: 'l'.repeat(200)})],
  ['ALLOW', 'admin create packageName Basic, time 23:45', write(admin, 'n1', 'create', {...newAdhoc, packageName: 'Basic', time: '23:45'})],
  ['DENY', 'non-admin create valid adhoc', write(guest, 'n1', 'create', {...newAdhoc, createdBy: 'g1'})],
  ['DENY', 'signed out create valid adhoc', write(null, 'n1', 'create', newAdhoc)],
  ['DENY', 'admin create with uid', write(admin, 'n1', 'create', {...newAdhoc, uid: 'victim'})],
  ['DENY', 'admin create status paid', write(admin, 'n1', 'create', {...newAdhoc, status: 'paid'})],
  ['DENY', 'admin create status Adhoc', write(admin, 'n1', 'create', {...newAdhoc, status: 'Adhoc'})],
  ['DENY', 'admin create uppercase email', write(admin, 'n1', 'create', {...newAdhoc, email: 'Jane@gmail.com'})],
  ['DENY', 'admin create email with surrounding space', write(admin, 'n1', 'create', {...newAdhoc, email: ' jane@gmail.com'})],
  ['DENY', 'admin create email without @', write(admin, 'n1', 'create', {...newAdhoc, email: 'jane.gmail.com'})],
  ['DENY', 'admin create email without dot in domain', write(admin, 'n1', 'create', {...newAdhoc, email: 'jane@gmail'})],
  ['DENY', 'admin create email with inner space', write(admin, 'n1', 'create', {...newAdhoc, email: 'ja ne@gmail.com'})],
  // \\s in the rules string must be the whitespace class, not a literal "s".
  ['ALLOW', 'admin create email full of s (regex escape check)', write(admin, 'n1', 'create', {...newAdhoc, email: 'sass.s@ss-s.ss'})],
  ['DENY', 'admin create email with a tab', write(admin, 'n1', 'create', {...newAdhoc, email: 'ja\tne@gmail.com'})],
  ['DENY', 'admin create email with backslash-free dot check (a@bcom)', write(admin, 'n1', 'create', {...newAdhoc, email: 'a@bcom'})],
  ['DENY', 'admin create email with two @',write(admin, 'n1', 'create', {...newAdhoc, email: 'a@b@gmail.com'})],
  ['DENY', 'admin create extra key', write(admin, 'n1', 'create', {...newAdhoc, notes: 'hi'})],
  ['DENY', 'admin create updatedAt key', write(admin, 'n1', 'create', {...newAdhoc, updatedAt: T})],
  ['DENY', 'admin create missing createdAt', write(admin, 'n1', 'create', without(newAdhoc, 'createdAt'))],
  ['DENY', 'admin create createdAt not request.time', write(admin, 'n1', 'create', {...newAdhoc, createdAt: EARLIER})],
  ['DENY', 'admin create missing createdBy', write(admin, 'n1', 'create', without(newAdhoc, 'createdBy'))],
  ['DENY', 'admin create createdBy another uid', write(admin, 'n1', 'create', {...newAdhoc, createdBy: 'someone'})],
  ['DENY', 'admin create photosReady true', write(admin, 'n1', 'create', {...newAdhoc, photosReady: true})],
  ['DENY', 'admin create missing photosReady', write(admin, 'n1', 'create', without(newAdhoc, 'photosReady'))],
  ['DENY', 'admin create missing name', write(admin, 'n1', 'create', without(newAdhoc, 'name'))],
  ['DENY', 'admin create missing email', write(admin, 'n1', 'create', without(newAdhoc, 'email'))],
  ['DENY', 'admin create missing date', write(admin, 'n1', 'create', without(newAdhoc, 'date'))],
  ['DENY', 'admin create missing status', write(admin, 'n1', 'create', without(newAdhoc, 'status'))],
  ['DENY', 'admin create untrimmed name', write(admin, 'n1', 'create', {...newAdhoc, name: 'Harpers '})],
  ['DENY', 'admin create empty name', write(admin, 'n1', 'create', {...newAdhoc, name: ''})],
  ['DENY', 'admin create name of 101 chars', write(admin, 'n1', 'create', {...newAdhoc, name: 'n'.repeat(101)})],
  ['DENY', 'admin create non-string name', write(admin, 'n1', 'create', {...newAdhoc, name: 42})],
  ['DENY', 'admin create packageName Deluxe', write(admin, 'n1', 'create', {...newAdhoc, packageName: 'Deluxe'})],
  ['DENY', 'admin create packageName premium (case)', write(admin, 'n1', 'create', {...newAdhoc, packageName: 'premium'})],
  ['DENY', 'admin create date 2026-1-1', write(admin, 'n1', 'create', {...newAdhoc, date: '2026-1-1'})],
  ['DENY', 'admin create date with time', write(admin, 'n1', 'create', {...newAdhoc, date: '2026-11-01T00:00'})],
  ['DENY', 'admin create time 24:00', write(admin, 'n1', 'create', {...newAdhoc, time: '24:00'})],
  ['DENY', 'admin create time 9:00', write(admin, 'n1', 'create', {...newAdhoc, time: '9:00'})],
  ['DENY', 'admin create location of 201 chars', write(admin, 'n1', 'create', {...newAdhoc, location: 'l'.repeat(201)})],
  ['DENY', 'admin create non-string location', write(admin, 'n1', 'create', {...newAdhoc, location: 7})],

  // ---- update: ad hoc sessions ----
  ['ALLOW', 'admin update adhoc name', updAdhoc({name: 'The Harpers'})],
  ['ALLOW', 'admin update adhoc email', updAdhoc({email: 'harper@example.com'})],
  ['ALLOW', 'admin update adhoc date', updAdhoc({date: '2026-12-24'})],
  ['ALLOW', 'admin update adhoc time', updAdhoc({time: '06:15'})],
  ['ALLOW', 'admin update adhoc location', updAdhoc({location: 'Home'})],
  ['ALLOW', 'admin update adhoc packageName', updAdhoc({packageName: 'Ultimate'})],
  ['ALLOW', 'admin update adhoc photosReady true', updAdhoc({photosReady: true})],
  ['ALLOW', 'admin update adhoc photosReady false (only updatedAt changes)', updAdhoc({})],
  ['ALLOW', 'admin update adhoc every editable field at once', updAdhoc({name: 'A', email: 'a@b.co', date: '2027-01-01', time: '21:00', location: 'Park', packageName: 'Basic', photosReady: true})],
  ['ALLOW', 'admin adds packageName/time/location to a minimal adhoc', upd(without(adhoc, 'packageName', 'time', 'location'), {updatedAt: T, packageName: 'Basic', time: '09:00', location: 'Park'}, [], admin, 'c1')],
  ['ALLOW', 'admin update photosReady on adhoc with odd untouched name', upd({...adhoc, name: ' odd '}, {updatedAt: T, photosReady: true}, [], admin, 'c1')],
  ['DENY', 'admin update adhoc name without updatedAt', upd(adhoc, {name: 'The Harpers'}, [], admin, 'c1')],
  ['DENY', 'admin update adhoc photosReady without updatedAt', upd(adhoc, {photosReady: true}, [], admin, 'c1')],
  ['DENY', 'admin update adhoc date without updatedAt', upd(adhoc, {date: '2026-12-24'}, [], admin, 'c1')],
  ['DENY', 'admin update adhoc with updatedAt not request.time', upd(adhoc, {name: 'X', updatedAt: EARLIER}, [], admin, 'c1')],
  ['ALLOW', 'admin removes time', updAdhoc({}, ['time'])],
  ['ALLOW', 'admin removes location', updAdhoc({}, ['location'])],
  ['ALLOW', 'admin removes packageName', updAdhoc({}, ['packageName'])],
  ['ALLOW', 'admin removes time, location and packageName together', updAdhoc({}, ['time', 'location', 'packageName'])],
  ['DENY', 'admin removes date', updAdhoc({}, ['date'])],
  ['DENY', 'admin removes name', updAdhoc({}, ['name'])],
  ['DENY', 'admin removes email', updAdhoc({}, ['email'])],
  ['DENY', 'admin removes photosReady', updAdhoc({}, ['photosReady'])],
  ['DENY', 'admin update adhoc email uppercase', updAdhoc({email: 'Harper@example.com'})],
  ['DENY', 'admin update adhoc email invalid', updAdhoc({email: 'harper'})],
  ['DENY', 'admin update adhoc name empty', updAdhoc({name: ''})],
  ['DENY', 'admin update adhoc name untrimmed', updAdhoc({name: ' Harpers'})],
  ['DENY', 'admin update adhoc date invalid', updAdhoc({date: '24/12/2026'})],
  ['DENY', 'admin update adhoc time invalid', updAdhoc({time: '10:60'})],
  ['DENY', 'admin update adhoc location too long', updAdhoc({location: 'l'.repeat(201)})],
  ['DENY', 'admin update adhoc packageName invalid', updAdhoc({packageName: 'Gold'})],
  ['DENY', 'admin update adhoc photosReady "true" string', updAdhoc({photosReady: 'true'})],
  ['DENY', 'admin update adhoc -> paid status', updAdhoc({status: 'paid'})],
  ['DENY', 'admin update adhoc adds uid', updAdhoc({uid: 'victim'})],
  ['DENY', 'admin update adhoc createdAt', updAdhoc({createdAt: T})],
  ['DENY', 'admin update adhoc createdBy', updAdhoc({createdBy: 'someone'})],
  ['DENY', 'admin update adhoc extra key', updAdhoc({notes: 'hi'})],
  ['DENY', 'non-admin (the guest) update adhoc photosReady', updAdhoc({photosReady: true}, [], guest)],
  ['DENY', 'signed out update adhoc', updAdhoc({photosReady: true}, [], null)],

  // ---- update: customers' bookings and other docs ----
  ['ALLOW', 'admin update paid photosReady true', updPaid({photosReady: true})],
  ['ALLOW', 'admin update paid photosReady false (only updatedAt changes)', updPaid({})],
  ['ALLOW', 'admin update photosReady on odd hand-entered paid doc', updPaid({photosReady: true}, [], {uid: 'cust1', status: ' Paid ', date: 'Nov 1', packageName: 7})],
  ['ALLOW', 'admin adds photosReady to hand-entered doc with no status', updPaid({photosReady: true}, [], {uid: 'cust1', date: '2026-11-01'})],
  ['ALLOW', 'admin update pending booking photosReady', updPaid({photosReady: true}, [], {...paid, status: 'pending'})],
  ['DENY', 'admin update paid photosReady without updatedAt', upd(paid, {photosReady: true}, [], admin, 'b1')],
  ['DENY', 'admin update paid photosReady "true" string', updPaid({photosReady: 'true'})],
  ['DENY', 'admin update paid date', updPaid({date: '2026-12-01'})],
  ['DENY', 'admin update paid time', updPaid({time: '11:00'})],
  ['DENY', 'admin update paid packageName', updPaid({packageName: 'Ultimate'})],
  ['DENY', 'admin update paid status', updPaid({status: 'refunded'})],
  ['DENY', 'admin update paid -> adhoc status', updPaid({status: 'adhoc'})],
  ['DENY', 'admin update paid uid', updPaid({uid: 'someone'})],
  ['DENY', 'admin update paid email', updPaid({email: 'x@y.com'})],
  ['DENY', 'admin update paid name (adds a name)', updPaid({name: 'The Smiths'})],
  ['DENY', 'admin removes paid time', updPaid({}, ['time'])],
  ['DENY', 'admin update no-status doc date', updPaid({date: '2026-12-01'}, [], {uid: 'cust1', date: '2026-11-01'})],
  ['DENY', 'customer update own paid photosReady', upd(paid, {photosReady: true, updatedAt: T}, [], customer, 'b1')],

  // ---- delete ----
  ['ALLOW', 'admin delete adhoc', write(admin, 'c1', 'delete', null, adhoc)],
  ['DENY', 'admin delete paid', write(admin, 'b1', 'delete', null, paid)],
  ['DENY', 'admin delete doc with no status', write(admin, 'b2', 'delete', null, without(paid, 'status'))],
  ['DENY', 'admin delete status "Adhoc" (not exact)', write(admin, 'c1', 'delete', null, {...adhoc, status: 'Adhoc'})],
  ['DENY', 'guest delete adhoc', write(guest, 'c1', 'delete', null, adhoc)],
  ['DENY', 'customer delete own paid', write(customer, 'b1', 'delete', null, paid)],

  // ---- site/home ----
  ['ALLOW', 'public get site/home', home(null, 'get', null, {photos: ['a.jpg'], updatedAt: EARLIER, updatedBy: 'adm'})],
  ['DENY', 'public list site/home', home(null, 'list', null, {photos: ['a.jpg'], updatedAt: EARLIER, updatedBy: 'adm'})],
  ['ALLOW', 'admin create site/home with 7 names', home(admin, 'create', {photos: names7, updatedAt: T, updatedBy: 'adm'})],
  ['ALLOW', 'admin update site/home with 7 names', home(admin, 'update', {photos: names7, updatedAt: T, updatedBy: 'adm'}, {photos: ['a.jpg'], updatedAt: EARLIER, updatedBy: 'adm'})],
  ['ALLOW', 'admin update site/home with no names', home(admin, 'update', {photos: [], updatedAt: T, updatedBy: 'adm'}, {photos: ['a.jpg'], updatedAt: EARLIER, updatedBy: 'adm'})],
  ['DENY', 'admin set site/home with 8 names', home(admin, 'update', {photos: [...names7, '8.jpg'], updatedAt: T, updatedBy: 'adm'}, {photos: [], updatedAt: EARLIER, updatedBy: 'adm'})],
  ['DENY', 'admin create site/home with 8 names', home(admin, 'create', {photos: [...names7, '8.jpg'], updatedAt: T, updatedBy: 'adm'})],
  ['DENY', 'admin set site/home extra key', home(admin, 'create', {photos: names7, updatedAt: T, updatedBy: 'adm', hero: '1.jpg'})],
  ['DENY', 'admin set site/home photos not a list', home(admin, 'create', {photos: '1.jpg', updatedAt: T, updatedBy: 'adm'})],
  ['DENY', 'admin set site/home missing photos', home(admin, 'create', {updatedAt: T, updatedBy: 'adm'})],
  ['DENY', 'admin set site/home updatedAt not request.time', home(admin, 'create', {photos: names7, updatedAt: EARLIER, updatedBy: 'adm'})],
  ['DENY', 'admin set site/home missing updatedAt', home(admin, 'create', {photos: names7, updatedBy: 'adm'})],
  ['DENY', 'admin set site/home updatedBy another uid', home(admin, 'create', {photos: names7, updatedAt: T, updatedBy: 'someone'})],
  ['DENY', 'non-admin set site/home', home(customer, 'create', {photos: names7, updatedAt: T, updatedBy: 'cust1'})],
  ['DENY', 'signed out set site/home', home(null, 'create', {photos: names7, updatedAt: T, updatedBy: 'x'})],
  ['DENY', 'admin delete site/home', home(admin, 'delete', null, {photos: [], updatedAt: EARLIER, updatedBy: 'adm'})],
];

export const cases = written.map(([expectation, name, {request, existing}]) => [
  expectation,
  name,
  {request, ...(existing ? {resource: {data: existing}} : {})},
]);
