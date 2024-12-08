import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:taggable/taggable.dart';

class Taggable {
  const Taggable({required this.id, required this.name});

  final String id;
  final String name;
}

class User extends Taggable {
  const User({required super.id, required super.name});
}

class Topic extends Taggable {
  const Topic({required super.id, required super.name});
}

const users = <User>[
  User(id: '1ax', name: 'Alice'),
  User(id: '2by', name: 'Bob'),
  User(id: '3cz', name: 'Charlie'),
  User(id: '4dw', name: 'Carol'),
];

const topics = <Topic>[
  Topic(id: 'myDartId', name: 'Dart'),
  Topic(id: 'myFlutterId', name: 'Flutter'),
  Topic(id: 'myPubId', name: 'Pub'),
];

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: HomePage()));
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _layerLink = LayerLink();
  final _formKey = GlobalKey<FormState>();
  late FocusNode _focusNode;

  final List<List<InlineSpan>> comments = [];

  late final TagTextEditingController _controller;

  OverlayEntry? _overlayEntry;
  String backendFormat = '';

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _controller = TagTextEditingController<Taggable>(
        searchTaggables: searchTaggables,
        buildTaggables: buildTaggables,
        toFrontendConverter: (taggable) => taggable.name,
        toBackendConverter: (taggable) => taggable.id,
        tagStyles: {
          '@': const TextStyle(color: Colors.blue),
          '#': const TextStyle(color: Colors.green),
          'all:': const TextStyle(color: Colors.purple),
        });
    _controller.addListener(() {
      setState(() {
        backendFormat = _controller.backendTextFormat;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  FutureOr<List<InlineSpan>> _buildTextSpans(
    String backendFormat, {
    TextStyle? defaultStyle,
  }) async {
    String? leadingSpace;
    List<InlineSpan> spans = [];
    for (String word in backendFormat.split(' ')) {
      leadingSpace = leadingSpace == null ? "" : " ";

      final tagPrefix = _controller.tagStyles.keys
          .where(
            (prefix) => word.startsWith(prefix),
          )
          .firstOrNull;
      if (tagPrefix == null) {
        spans.add(TextSpan(text: "$leadingSpace$word", style: defaultStyle));
        continue;
      }

      final taggable =
          await backendToTaggable(tagPrefix, word.substring(tagPrefix.length));

      if (taggable == null) {
        spans.add(TextSpan(text: "$leadingSpace$word", style: defaultStyle));
        continue;
      }

      final tagStyle = _controller.tagStyles[tagPrefix]!;
      final mergedStyle = defaultStyle?.merge(tagStyle) ?? tagStyle;

      spans.add(TextSpan(
        text: "$leadingSpace$tagPrefix${taggable.name}",
        style: mergedStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => debugPrint('Tapped on ${taggable.name}'),
      ));
    }
    return spans;
  }

  Future<Taggable?> buildTaggables(
      FutureOr<Iterable<Taggable>> taggables) async {
    final availableTaggables = await taggables;
    Completer<Taggable?> completer = Completer();
    _overlayEntry?.remove();
    if (availableTaggables.isEmpty) {
      _overlayEntry = null;
      completer.complete(null);
    } else {
      _overlayEntry = OverlayEntry(builder: (context) {
        final renderBox =
            _formKey.currentContext!.findRenderObject() as RenderBox;
        return Positioned(
          width: renderBox.size.width,
          bottom: renderBox.size.height + 8,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            followerAnchor: Alignment.bottomLeft,
            child: Material(
              child: ListView(
                shrinkWrap: true,
                children: availableTaggables.map((taggable) {
                  return ListTile(
                    title: Text(taggable.name),
                    tileColor: Theme.of(context).colorScheme.primaryContainer,
                    onTap: () {
                      _overlayEntry?.remove();
                      _overlayEntry = null;
                      completer.complete(taggable);
                      _focusNode.requestFocus();
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        );
      });
      if (mounted) {
        Overlay.of(context).insert(_overlayEntry!);
      }
    }
    return completer.future;
  }

  Future<Iterable<Taggable>> searchTaggables(
      String tagPrefix, String? tagName) async {
    if (tagName == null || tagName.isEmpty) {
      return [];
    }
    return switch (tagPrefix) {
      '@' => users
          .where((user) =>
              user.name.toLowerCase().startsWith(tagName.toLowerCase()))
          .toList(),
      '#' => topics
          .where((topic) =>
              topic.name.toLowerCase().startsWith(tagName.toLowerCase()))
          .toList(),
      'all:' => [...users, ...topics].where((taggable) =>
          taggable.name.toLowerCase().startsWith(tagName.toLowerCase())),
      _ => [],
    };
  }

  FutureOr<Taggable?> backendToTaggable(String prefix, String id) {
    return switch (prefix) {
      '@' => users.where((user) => user.id == id).firstOrNull,
      '#' => topics.where((topic) => topic.id == id).firstOrNull,
      'all:' => [...users, ...topics]
          .where((taggable) => taggable.id == id)
          .firstOrNull,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...comments.map((comment) {
              return Card(
                margin: const EdgeInsets.all(4),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text.rich(
                    TextSpan(
                      children: comment,
                    ),
                  ),
                ),
              );
            }),
            Form(
              key: _formKey,
              child: CompositedTransformTarget(
                link: _layerLink,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Type @ to tag a user or # to tag a topic',
                    helperText: 'Backend format: $backendFormat',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () async {
                        final textSpans = await _buildTextSpans(
                            _controller.backendTextFormat);
                        setState(() {
                          comments.add(textSpans);
                          _controller.clear();
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _controller.setInitialText(
                  "Hello @1ax and welcome to #myFlutterId",
                  backendToTaggable,
                );
              },
              child: const Text('Set initial text'),
            ),
          ],
        ),
      ),
    );
  }
}
