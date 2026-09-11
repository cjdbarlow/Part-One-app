# Part One

A Flutter app for reading [Part One](https://partone.litfl.com/) offline on iPhone, iPad and Android.

The app downloads rendered Quarto HTML, replaces the chapter navigation and search with native offline versions. It also provides a toggle for margin notes (I use Tufte styling).

On first use, readers are prompted to download the book. Later launches check GitHub; a new commit shows **Update content** at the bottom of the sidebar. Readers choose when to update, without an app-store release.

The app is designed to be easily forked for other quarto projects.

## Run locally

Use Flutter with the SDK versions specified in [pubspec.yaml](pubspec.yaml), plus Xcode for iOS or the Android SDK for Android. From this repository:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

Select a simulator, emulator or connected device. The initial download needs internet access. See the [Flutter CLI reference](https://docs.flutter.dev/reference/flutter-cli).

## Port to another Quarto project

Fork and clone this repository, then follow these steps for your book.

### 1. Publish the rendered book

The app reads **rendered HTML from a public GitHub repository branch**. Include the complete output: HTML pages, `site_libs/`, images, stylesheets and other resources.

From the **book's repository**, connected to GitHub, render and publish to `gh-pages`:

```sh
quarto publish gh-pages
```

Follow [Quarto's GitHub Pages guide](https://quarto.org/docs/publishing/github-pages.html). Existing branches containing rendered output also work; an Actions deployment artefact alone is insufficient.

Use a Quarto HTML book or website with standard sidebar navigation (`nav#quarto-sidebar`), generator metadata and `main#quarto-document-content`. Search indexes the entry page and its sidebar's pages, so include every chapter there.

### 2. Edit the app configuration

In your **app fork**, replace [assets/config/app.json](assets/config/app.json), for example:

```json
{
  "id": "my_book",
  "title": "My Book",
  "applicationId": "org.example.mybook",
  "displayName": "My Book",
  "owner": "example-owner",
  "repository": "my-book",
  "branch": "gh-pages",
  "contentPath": "",
  "siteUrl": "https://example-owner.github.io/my-book/",
  "entryPage": "index.html",
  "excludedPages": [],
  "hiddenSelectors": [],
  "accentColour": "ff3478f6",
  "disclaimer": {
    "text": "Read the project disclaimer at",
    "linkText": "My Book",
    "url": "https://example-owner.github.io/my-book/disclaimer.html"
  }
}
```

- `id`: unique lowercase storage key; letters, numbers and underscores, starting with a letter. Choose your own `applicationId` and home-screen `displayName`.
- `owner`, `repository`, `branch`: the published book's location. `contentPath` is `""` for the branch root or, for example, `"docs"`. `entryPage` is relative to it.
- `siteUrl`: the actual HTTPS site root, including subdirectories and a trailing slash, used to resolve links offline.
- `excludedPages`: relative HTML paths to omit from app navigation and search. `hiddenSelectors`: CSS selectors for additional website elements to hide. Both affect only the app.
- `accentColour`: eight hexadecimal digits in `AARRGGBB` order. Replace the disclaimer wording and HTTPS link, or omit the object.

### 3. Apply the name, identifier and artwork

After resolving Flutter dependencies, run from the app repository:

```sh
dart run tool/configure_app.dart
```

This updates iOS and Android names and identifiers, including Android's namespace and `MainActivity`. Rerun after changing the native name or identifier. The internal Dart package name `part_one` can remain unchanged.

Replace [assets/icon/part-one.svg](assets/icon/part-one.svg) with your artwork, then generate the native icon sizes on macOS:

```sh
swift tool/generate_app_icons.swift
```

The generator accepts square SVGs made only of filled polygons. Otherwise, export the iOS and Android icons separately. Configure your own signing before distribution.