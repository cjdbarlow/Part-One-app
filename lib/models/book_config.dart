class BookConfig {
  final String id;
  final String title;
  final String owner;
  final String repository;
  final String branch;
  final String contentPath;
  final Uri siteUrl;
  final String entryPage;
  final List<String> excludedPages;
  final List<String> hiddenSelectors;
  final int accentColour;
  final DisclaimerConfig? disclaimer;

  const BookConfig({
    required this.id,
    required this.title,
    required this.owner,
    required this.repository,
    required this.branch,
    required this.siteUrl,
    this.contentPath = '',
    this.entryPage = 'index.html',
    this.excludedPages = const [],
    this.hiddenSelectors = const [],
    this.accentColour = 0xff3478f6,
    this.disclaimer,
  });

  factory BookConfig.fromJson(Map<String, dynamic> json) {
    final config = BookConfig(
      id: json['id'] as String,
      title: json['title'] as String,
      owner: json['owner'] as String,
      repository: json['repository'] as String,
      branch: json['branch'] as String,
      contentPath: json['contentPath'] as String? ?? '',
      siteUrl: Uri.parse(json['siteUrl'] as String),
      entryPage: json['entryPage'] as String? ?? 'index.html',
      excludedPages: (json['excludedPages'] as List? ?? []).cast<String>(),
      hiddenSelectors: (json['hiddenSelectors'] as List? ?? []).cast<String>(),
      accentColour: int.parse(
        json['accentColour'] as String? ?? 'ff3478f6',
        radix: 16,
      ),
      disclaimer: json['disclaimer'] == null
          ? null
          : DisclaimerConfig.fromJson(
              json['disclaimer'] as Map<String, dynamic>,
            ),
    );
    config.validate();
    return config;
  }

  void validate() {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id) ||
        title.trim().isEmpty ||
        !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(owner) ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(repository) ||
        branch.trim().isEmpty ||
        siteUrl.scheme != 'https' ||
        siteUrl.host.isEmpty) {
      throw const FormatException('Invalid book configuration.');
    }
    final configuredDisclaimer = disclaimer;
    if (configuredDisclaimer != null &&
        (configuredDisclaimer.text.trim().isEmpty ||
            configuredDisclaimer.linkText.trim().isEmpty ||
            configuredDisclaimer.url.scheme != 'https' ||
            configuredDisclaimer.url.host.isEmpty)) {
      throw const FormatException('Invalid disclaimer configuration.');
    }
    for (final value in [contentPath, entryPage, ...excludedPages]) {
      final decoded = Uri.decodeComponent(value);
      if (Uri.parse(value).hasScheme ||
          decoded.startsWith('/') ||
          decoded.contains('\\') ||
          decoded.contains('\u0000') ||
          decoded.split('/').contains('..') ||
          decoded.contains('?') ||
          decoded.contains('#')) {
        throw const FormatException('Book paths must stay inside the book.');
      }
    }
    if (!entryPage.endsWith('.html')) {
      throw const FormatException('The entry page must be an HTML file.');
    }
    if (excludedPages.any(
          (value) =>
              !value.endsWith('.html') ||
              Uri.decodeComponent(
                value,
              ).split('/').any((segment) => segment.isEmpty || segment == '.'),
        ) ||
        isPageExcluded(Uri.decodeComponent(entryPage))) {
      throw const FormatException(
        'Excluded pages must be relative HTML paths without empty or dot segments, other than the entry page.',
      );
    }
  }

  bool isPageExcluded(String pagePath) => excludedPages.any(
    (excluded) => Uri.decodeComponent(excluded) == pagePath,
  );
}

class DisclaimerConfig {
  final String text;
  final String linkText;
  final Uri url;

  const DisclaimerConfig({
    required this.text,
    required this.linkText,
    required this.url,
  });

  factory DisclaimerConfig.fromJson(Map<String, dynamic> json) {
    return DisclaimerConfig(
      text: json['text'] as String,
      linkText: json['linkText'] as String,
      url: Uri.parse(json['url'] as String),
    );
  }
}
