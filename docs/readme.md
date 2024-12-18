# Generating docs

- Ensure [dartdoc](https://pub.dev/packages/dartdoc) is installed globally.
- Comment out the external exports in `lib/sizzle.dart`
- `dart doc --output=docs/api .`
- Uncomment the exports again
