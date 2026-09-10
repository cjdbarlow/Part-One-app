class ChapterNode {
  final String title;
  final String? href;
  final List<ChapterNode> children;

  const ChapterNode({required this.title, this.href, this.children = const []});

  factory ChapterNode.fromJson(Map<String, dynamic> json) => ChapterNode(
    title: json['title'] as String,
    href: json['href'] as String?,
    children: (json['children'] as List? ?? [])
        .map((value) => ChapterNode.fromJson(value as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'href': href,
    'children': children.map((child) => child.toJson()).toList(),
  };
}

class SearchSection {
  final String pagePath;
  final String pageTitle;
  final String heading;
  final String anchor;
  final String text;
  final Map<String, String> glossary;

  const SearchSection({
    required this.pagePath,
    required this.pageTitle,
    required this.heading,
    required this.anchor,
    required this.text,
    this.glossary = const {},
  });

  String get href => anchor.isEmpty ? pagePath : '$pagePath#$anchor';

  factory SearchSection.fromJson(Map<String, dynamic> json) => SearchSection(
    pagePath: json['pagePath'] as String,
    pageTitle: json['pageTitle'] as String,
    heading: json['heading'] as String,
    anchor: json['anchor'] as String,
    text: json['text'] as String,
    glossary: (json['glossary'] as Map? ?? {}).cast<String, String>(),
  );

  Map<String, dynamic> toJson() => {
    'pagePath': pagePath,
    'pageTitle': pageTitle,
    'heading': heading,
    'anchor': anchor,
    'text': text,
    'glossary': glossary,
  };
}

class BookContent {
  final String commit;
  final DateTime installedAt;
  final DateTime? committedAt;
  final String entryPage;
  final List<ChapterNode> chapters;
  final List<SearchSection> sections;
  final int pageCount;

  const BookContent({
    required this.commit,
    required this.installedAt,
    this.committedAt,
    required this.entryPage,
    required this.chapters,
    required this.sections,
    required this.pageCount,
  });

  factory BookContent.fromJson(Map<String, dynamic> json) => BookContent(
    commit: json['commit'] as String,
    installedAt: DateTime.parse(json['installedAt'] as String),
    committedAt: json['committedAt'] == null
        ? null
        : DateTime.parse(json['committedAt'] as String).toUtc(),
    entryPage: json['entryPage'] as String,
    chapters: (json['chapters'] as List)
        .map((value) => ChapterNode.fromJson(value as Map<String, dynamic>))
        .toList(),
    sections: (json['sections'] as List)
        .map((value) => SearchSection.fromJson(value as Map<String, dynamic>))
        .toList(),
    pageCount: json['pageCount'] as int,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'commit': commit,
    'installedAt': installedAt.toUtc().toIso8601String(),
    if (committedAt != null)
      'committedAt': committedAt!.toUtc().toIso8601String(),
    'entryPage': entryPage,
    'chapters': chapters.map((node) => node.toJson()).toList(),
    'sections': sections.map((section) => section.toJson()).toList(),
    'pageCount': pageCount,
  };
}
