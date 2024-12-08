import 'dart:async';

import 'package:flutter/material.dart';

/// A zero-width character that is used to mark the beginning of a tag.
const String tagStartMarker = '\u200c';

/// A zero-width character that is used to mark the end of a tag.
const String tagEndMarker = '\u200d';

/// A utility class that splits a tag prompt into a prefix and a tag name.
class TagPrompt {
  TagPrompt({this.prefix, this.tagName});

  final String? prefix;
  final String? tagName;

  int get length => (prefix?.length ?? 0) + (tagName?.length ?? 0);

  @override
  String toString() => 'TagPrompt(prefix: $prefix, tagName: $tagName)';
}

/// A controller for an editable text field that supports tagging behaviour.
class TagTextEditingController<T> extends TextEditingController {
  TagTextEditingController(
      {required this.buildTaggables,
      required this.searchTaggables,
      required this.toFrontendConverter,
      required this.toBackendConverter,
      this.tagStyles = const {
        '@': TextStyle(color: Colors.blue),
      }})
      : super() {
    addListener(cursorController);
    addListener(tagStringController);
    addListener(ensureWhiteSpaceController);
    addListener(updateTaggables);
    addListener(updatePreviousCursorPosition);
  }

  @override
  void dispose() {
    removeListener(cursorController);
    removeListener(tagStringController);
    removeListener(ensureWhiteSpaceController);
    removeListener(updateTaggables);
    removeListener(updatePreviousCursorPosition);
    super.dispose();
  }

  /// Searches for taggables based on the tag prefix and query.
  final FutureOr<Iterable<T>> Function(String prefix, String? query)
      searchTaggables;

  /// Builds the list of taggables, if any.
  final Future<T?> Function(FutureOr<Iterable<T>> taggables) buildTaggables;

  /// Converts a taggable to a string that is displayed to the user.
  final String Function(T taggable) toFrontendConverter;

  /// Converts a taggable to a string that is stored in the database.
  final String Function(T taggable) toBackendConverter;

  final Map<String, TextStyle?> tagStyles;

  /// The text that follows the tag prefix, but is not yet a tag.
  TagPrompt _tagPrompt = TagPrompt();

  /// A map that maps user display names to taggables.
  Map<String, (String, T)> _tagStringsToTaggables = {};

  /// The cursor position before the last change.
  int previousCursorPosition = 0;

  @override
  void clear() {
    _tagStringsToTaggables = {};
    _tagPrompt = TagPrompt();
    super.clear();
  }

  /// Sets the comment this controller is editing.
  ///
  /// The comment is parsed for tags, and the text is formatted accordingly.
  ///
  /// The [backendToTaggable] function is used to convert the backend format of
  /// a taggable to a taggable object. It takes the tag prefix and the backend
  /// string as arguments and returns the taggable object.
  void setInitialText(
    String initialText,
    FutureOr<T?> Function(String prefix, String backendString)
        backendToTaggable,
  ) async {
    clear();
    final StringBuffer tmpText = StringBuffer();
    for (final String word in initialText.split(' ')) {
      final tagPrefix =
          tagStyles.keys.where((prefix) => word.startsWith(prefix)).firstOrNull;
      if (tagPrefix == null) {
        tmpText.write('$word ');
        continue;
      }
      final tagId = word.substring(tagPrefix.length);
      final taggable = await backendToTaggable(tagPrefix, tagId);
      if (taggable == null) {
        tmpText.write('$word ');
        continue;
      }
      final frontendString = toFrontendConverter(taggable);
      _tagStringsToTaggables[tagPrefix + frontendString] =
          (tagPrefix, taggable);
      tmpText.write('$tagStartMarker$tagPrefix$frontendString$tagEndMarker ');
    }
    text = tmpText.toString().trimRight();
  }

  /// Parses a tag prompt into a [TagPrompt] object.
  TagPrompt _parseTagPrompt(String tagPrompt) {
    final prefix = tagStyles.keys
        .where((prefix) => tagPrompt.startsWith(prefix))
        .firstOrNull;
    if (prefix == null) return TagPrompt();
    final tagName = tagPrompt.substring(prefix.length);
    return TagPrompt(prefix: prefix, tagName: tagName);
  }

  /// Returns a list of pairs of start and end matches of tags in the text.
  /// 
  /// If a tag is broken, the start or end match is null.
  List<(Match?, Match?)> getTagMatchPairs(String text) {
    final List<Match> startMatches = tagStartMarker.allMatches(text).toList();
    final List<Match> endMatches = tagEndMarker.allMatches(text).toList();
    if (startMatches.isEmpty && endMatches.isEmpty) return [];
    final List<(Match?, Match?)> matches = [];
    // Add all endMatches that are before the first startMatch to the list
    while ((endMatches.firstOrNull?.start ?? double.infinity) <
        (startMatches.firstOrNull?.start ?? double.infinity)) {
      matches.add((null, endMatches.removeAt(0)));
    }
    // At this point, we are certain that the first startMatch is before the first endMatch
    for (int i = 0; i < startMatches.length; i++) {
      final startMatch = startMatches[i];
      final nextStartMatch = startMatches.elementAtOrNull(i + 1);
      final nextEndMatch = endMatches.firstOrNull;
      if ((nextEndMatch?.start ?? double.infinity) <
          (nextStartMatch?.start ?? double.infinity)) {
        // The next endMatch is before the next startMatch, so we have a pair
        matches.add((startMatch, endMatches.removeAt(0)));
      } else {
        // There is no endMatch for this startMatch
        matches.add((startMatch, null));
      }
    }
    // Add all remaining endMatches to the list
    for (final endMatch in endMatches) {
      matches.add((null, endMatch));
    }
    return matches;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> textSpanChildren = <InlineSpan>[];
    final matchPairs = getTagMatchPairs(text);
    int position = 0;

    // For each pair of markers, add the text before the tag and the tag itself
    for (int i = 0; i < matchPairs.length; i = i + 1) {
      // Matches are not null because null values are corrected by the cursorController
      final (start as Match, end as Match) = matchPairs[i];
      final String textBeforeTag = text.substring(position, start.start);
      textSpanChildren.add(TextSpan(text: textBeforeTag, style: style));

      final String textInTag = text.substring(start.end, end.start);
      final tagPrompt = _parseTagPrompt(textInTag);
      final tagTextStyle = style?.merge(tagStyles[tagPrompt.prefix]) ??
          tagStyles[tagPrompt.prefix];
      textSpanChildren.add(TextSpan(
          text: '$tagStartMarker$textInTag$tagEndMarker', style: tagTextStyle));

      position = end.end;
    }


    // Finally, format the text after the last tag with the default style
    final String textAfterAllTags = text.substring(position, text.length);
    textSpanChildren.add(TextSpan(text: textAfterAllTags, style: style));

    return TextSpan(style: style, children: textSpanChildren);
  }

  /// A listener that ensures that the cursor is always outside of a tag.
  /// 
  /// If the cursor is inside a tag, it is moved to the nearest side, unless the
  /// user moved into the tag with the arrow keys, in which case the cursor is
  /// moved to the other side.
  /// 
  /// If a tag is broken, the text between the cursor and the tag is removed.
  /// 
  /// If a tag is selected, the tag is selected as a whole.
  void cursorController() {
    final int baseOffset = selection.baseOffset;
    final int extentOffset = selection.extentOffset;
    if (baseOffset == -1) return; // This is sometimes -1; it is unclear why

    // Now, find the positions of all markers. If the cursor is between 1 and 2
    // or 3 and 4, etc., move it out of this range to the nearest side.
    final List<(Match?, Match?)> matchPairs = getTagMatchPairs(text);
    for (int i = 0; i < matchPairs.length; i = i + 1) {
      final (start, end) = matchPairs[i];
      if (start == null && end != null) {
        // A tag has been broken, so remove the text between the cursor and end
        value = TextEditingValue(
          text: text.replaceRange(baseOffset, end.end, ''),
          selection: TextSelection.collapsed(offset: baseOffset),
        );
      } else if (start != null && end == null) {
        // A tag has been broken, so remove the text between the cursor and start
        value = TextEditingValue(
          text: text.replaceRange(start.start, baseOffset, ''),
          selection: TextSelection.collapsed(offset: start.start),
        );
      } else if (start != null && end != null) {
        if (!selection.isCollapsed) {
          // A range is selected, so ensure that the tag is selected as a whole
          if (start.start < baseOffset && baseOffset < end.end) {
            // The baseOffset is within the tag
            if (baseOffset < extentOffset) {
              selection = TextSelection(
                baseOffset: start.start,
                extentOffset: extentOffset,
              );
            } else {
              selection = TextSelection(
                baseOffset: end.end,
                extentOffset: extentOffset,
              );
            }
          } else if (start.start < extentOffset && extentOffset < end.end) {
            // The extentOffset is within the tag
            if (extentOffset < baseOffset) {
              selection = TextSelection(
                baseOffset: start.start,
                extentOffset: baseOffset,
              );
            } else {
              selection =
                  TextSelection(baseOffset: end.end, extentOffset: baseOffset);
            }
          }
        } else if (start.start < baseOffset && baseOffset < end.end) {
          // The cursor is within the tag
          if (previousCursorPosition == start.start &&
              baseOffset == (previousCursorPosition + 2)) {
            // The cursor was moved to the right
            selection = TextSelection.collapsed(offset: end.end);
          } else if (previousCursorPosition == end.end &&
              baseOffset == (previousCursorPosition - 2)) {
            // The cursor was moved to the left
            selection = TextSelection.collapsed(offset: start.start);
          } else if ((baseOffset - start.start) < (end.end - baseOffset)) {
            selection = TextSelection.collapsed(offset: start.start);
          } else {
            selection = TextSelection.collapsed(offset: end.end);
          }
        }
      }
    }
  }

  /// A listener that checkes if a tag can be created at the current cursor
  void tagStringController() {
    if (!selection.isCollapsed) {
      // A range is selected, so no tag can be created
      _tagPrompt = TagPrompt();
      return;
    }
    final int currentPos = selection.baseOffset;
    if (currentPos == -1) return;
    int wordBeforeCursorStartPos =
        text.substring(0, currentPos).lastIndexOf(' ');
    if (wordBeforeCursorStartPos == -1) {
      // No spaces -> current word is the very first word
      wordBeforeCursorStartPos = 0;
    }
    final String wordBeforeCursor =
        text.substring(wordBeforeCursorStartPos, currentPos).trimLeft();
    _tagPrompt = _parseTagPrompt(wordBeforeCursor);
  }

  /// A listener that ensures that there is always whitespace around a tag.
  /// 
  /// If there is no whitespace to the left of a tag, the tag is removed.
  void ensureWhiteSpaceController() {
    final List<(Match?, Match?)> matchPairs = getTagMatchPairs(text);

    for (int i = 0; i < matchPairs.length; i = i + 1) {
      final (start as Match, end as Match) = matchPairs[i];

      // Remove tag if there is no whitespace to the left of the tag
      final isFirstWord = start.start == 0;
      if (!isFirstWord &&
          !tagStyles.keys.contains(text.substring(start.end, start.end + 1))) {
        value = TextEditingValue(
          text: text.replaceRange(
            start.start,
            end.end,
            text.substring(start.end, end.start),
          ),
          // Characters are removed to the right -> cursor can remain at same spot
          selection: TextSelection.collapsed(offset: start.start),
        );
        return;
      }
      // Remove tag if there is no whitespace to the right of the tag
      final isLastWord = end.end == text.length;
      if (!isLastWord && text.substring(end.end, end.end + 1) != ' ') {
        final userDidBackspace = previousCursorPosition > selection.baseOffset;
        value = TextEditingValue(
          text: text.replaceRange(
            start.start,
            end.end,
            text.substring(start.end, end.start),
          ),
          selection: TextSelection.collapsed(
              offset: end.end - 2 + (userDidBackspace ? 0 : 1)),
        );

        return;
      }
    }
  }

  /// A listener that searches for taggables based on the current tag prompt.
  /// 
  /// If taggable options are found, the user is prompted to select one.
  void updateTaggables() async {
    if (_tagPrompt.prefix == null) return;
    final taggables = searchTaggables(_tagPrompt.prefix!, _tagPrompt.tagName);
    buildTaggables(taggables).then((tagged) {
      if (tagged != null) {
        taggableUsersTapHandler(_tagPrompt.prefix!, tagged);
      }
    });
  }

  /// Inserts a taggable into the text field.
  /// 
  /// The taggable is inserted at the current cursor position.
  void taggableUsersTapHandler(String prefix, T taggable) {
    final tagName = toFrontendConverter(taggable);
    _tagStringsToTaggables[prefix + tagName] = (prefix, taggable);

    final int end = selection.baseOffset;
    final int start = end - _tagPrompt.length;
    final tagReplacement =
        '$tagStartMarker${_tagPrompt.prefix}$tagName$tagEndMarker ';

    value = TextEditingValue(
      text: text.replaceRange(start, end, tagReplacement),
      selection: TextSelection.collapsed(offset: start + tagReplacement.length),
    );

    _tagPrompt = TagPrompt();
  }

  void updatePreviousCursorPosition() {
    previousCursorPosition = selection.baseOffset;
  }

  /// Converts the text to the format required by the backend.
  ///
  /// The text is scanned for tags, and the display name of the tagged user is
  /// replaced by the user's ID.
  String get textToBackendFormat {
    String backendText = text;

    List<(Match?, Match?)> matches = getTagMatchPairs(backendText);

    while (matches.isNotEmpty) {
      final (start as Match, end as Match) = matches[0];
      final String tagName = backendText.substring(start.end, end.start);
      if (_tagStringsToTaggables.containsKey(tagName)) {
        final (String prefix, T taggable) = _tagStringsToTaggables[tagName]!;
        if (taggable == null) {
          // This should never happen, but it is better to be safe than sorry
          backendText = backendText.replaceRange(start.start, end.end, '');
          continue;
        }
        backendText = backendText.replaceRange(
          start.start,
          end.end,
          '$prefix${toBackendConverter(taggable)} ',
        );
      }
      // Redefine the matches because the replacement changed the text
      matches = getTagMatchPairs(backendText);
    }

    return backendText;
  }
}
