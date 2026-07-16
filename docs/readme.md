# Generating docs

- Ensure [dartdoc](https://pub.dev/packages/dartdoc) is installed globally.
- Comment out the external exports in `lib/sizzle.dart`
- `dart doc --output=docs/api .`
- Uncomment the exports again
- Copy the logo referenced by the README into the output so `index.html`
  resolves it: `cp sizzle-logo.png docs/api/sizzle-logo.png`
  (dartdoc does not copy README-referenced images, and wiping `docs/api`
  before a run removes any previous copy)
