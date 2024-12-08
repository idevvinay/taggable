<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages).
-->

A lightweight extension to [TextEditingController](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html) that allows for tagging/mentioning users and the like, with a focus on storing tags in a database-friendly format. Tagging behaviour is similar to that of popular platforms like WhatsApp and Instagram.

![Demo Video](https://raw.githubusercontent.com/WesselvanDam/taggable/refs/heads/main/doc/taggable_screen_recording.gif)

## Motivation

There are many packages that allow for tagging/mentioning users and other entities in a text field, but not all are suitable for storing the tags in such a way that allows for easy retrieval and parsing. Imagine the following scenario:

> A user writes and posts the comment `@Ada Lovelace check out this package!`. Suppose the backend server needs to parse this comment to send a notification to Ada. If the comment is stored as-is, two issues arise:
>
> 1. It is unclear where the tag ends. Is it `@Ada`, `@Ada Lovelace` or perhaps `@Ada Lovelace check`? It would be both difficult and inefficient to determine the exact tag.
> 2. If the user Ada changes her username to `@Ada King`, the comment would no longer tag her, as the tag is hardcoded as `@Ada Lovelace`.

Typically, any taggable entity has a unique identifier, such as a user ID. This package allows for tagging users such that the frontend display is user-friendly, while providing a database-friendly format for easy parsing and retrieval.

## Features

- **Lightweight**: This package can be used with the standard [TextField](https://api.flutter.dev/flutter/material/TextField-class.html) widget - you only need to replace the `TextEditingController` with a `TagTextEditingController`.
- **End-user friendly**: The controller handles the tagging logic, so you can focus on the UI. For example, backspacing over a tag deletes the entire tag, not just one character.
- **Customizable tag format**: Specify both the frontend format (e.g. `@Ada Lovelace`) and the backend format (e.g. `@123`). This package can also support multiple types of tagging (e.g. `@Ada Lovelace` and `#MyTrendingTopic`, see the video above).
- **Customizable search**: Specify how the package should search for tags, as well as how the options should be displayed.
- **Type annotations**: Give a type to the `TagTextEditingController` for better type safety and code completion when you define your callbacks.

## Getting started

This package assumes that your 'taggable' data comes in three forms:

1. A dataclass-like object that represents the taggable entity.
2. A representation of this entity that can be displayed in the UI.
3. A representation of this entity that can be stored in the database.

In the [example](https://pub.dev/packages/taggable/example), we use the following class to represent a taggable entity:

```dart
class Taggable {
  const Taggable({required this.id, required this.name});

  final String id;
  final String name;
}
```

The `id` is the unique identifier of the taggable entity, and the `name` is the string that will be displayed in the UI. Comparing this to WhatsApp, the taggable entity would be a user, the `id` would be the user's phone number, and the `name` would be the user's name.

The package supports having multiple types of taggable entities. However, to make the code less verbose, we recommend creating a class that extends `Taggable` for each type of taggable entity. For example:

```dart
class User extends Taggable {
  const User({required super.id, required super.name});
}

class Topic extends Taggable {
  const Topic({required super.id, required super.name});
}
```

Or you can make the Taggable class have abstract methods that return the frontend and backend representations of the taggable entity, to be implemented by the subclasses.

## Usage

### Installation

Add the package with the following command:

```bash
flutter pub add taggable
```

### Basic usage

To use the package, you need to replace the default `TextEditingController` with a `TagTextEditingController` and specify a couple of parameters;

```dart
import 'package:flutter/material.dart';
import 'package:taggable/taggable.dart';

class TaggableExample extends StatefulWidget {
  @override
  _TaggableExampleState createState() => _TaggableExampleState();
}

class _TaggableExampleState extends State<TaggableExample> {
  late TagTextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TagTextEditingController<Taggable>(
    searchTaggables: searchTaggables,
    buildTaggables: buildTaggables,
    toFrontendConverter: (taggable) => taggable.name,
    toBackendConverter: (taggable) => taggable.id,
    tagStyles: {
      '@': const TextStyle(color: Colors.blue),
      '#': const TextStyle(color: Colors.green),
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Taggable Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Type @ to tag a user or # to tag a topic',
          ),
        ),
      ),
    );
  }
}
```

Note how the controller is type-annotated with the `Taggable` class. In the example above, we specify the following parameters:

```dart
FutureOr<Iterable<T>> Function(String prefix, String? query) searchTaggables
```

This function is called whenever the user types a tag. It should return a list of taggable entities that match the query. The `prefix` parameter is the character that the user typed to start the tag, and the `query` parameter is the text that the user typed after the prefix. For example, if the user types `@Ada`, the `prefix` would be `@` and the `query` would be `Ada`. The return type is of `FutureOr` because the function can be both synchronous (if the data is already available) or asynchronous (if the data needs to be fetched from somewhere).

```dart
Future<T?> Function(FutureOr<Iterable<T>> taggables) buildTaggables
```

This function takes the list of taggable entities that match the query and builds the UI representation of these entities. In the [example](https://pub.dev/packages/taggable/example), an `OverlayEntry` is used to display the options as a list. Because users typically select an option by tapping on it, the return type is a Future. The example uses a [Completer](https://api.flutter.dev/flutter/dart-async/Completer-class.html) to return the selected taggable entity, since an `OverlayEntry` does not return a value.

```dart
String Function(T taggable) toFrontendConverter
```

This function converts the taggable entity to a string that will be displayed in the UI. In the example, we use the `name` field of the `Taggable` class.

```dart
String Function(T taggable) toBackendConverter
```

This function converts the taggable entity to a string that will be stored in the database. In the example, we use the `id` field of the `Taggable` class.

```dart
Map<String, TextStyle?> tagStyles
```

This map specifies the styles that should be applied to the tags. The keys are the prefixes that the user can type to start a tag, and the values are the styles that should be applied to the tags. In the example, we use the `@` prefix for users and the `#` prefix for topics.

### Conversion

There are three processes in which the taggable entities are converted:

1. **Saving text with tags**: When a piece of text containing tags needs to be saved, you can use the `backendTextFormat` getter of the `TagTextEditingController` to get the text in the backend format.
2. **Populating the text field**: When you have a piece of text in the backend format and want to populate the text field with it, you can use the `setInitialText` method of the `TagTextEditingController`. Besides the text, you need to provide function `backendToTaggable` that converts the backend format to the taggable entity. This function has the following signature:
```dart
FutureOr<T?> Function(String prefix, String backendString) backendToTaggable
```
3. **Displaying tags outside the text field**: Typically, content created with the `TagTextEditingController` will be displayed in a different widget, such as a comment section. This package does not provide a built-in way to display tags outside the text field, as the display of such content is highly dependent on the UI of your app. However, many of the conversion functions used in the `TagTextEditingController` can be reused to display tags outside the text field. See the [example](https://pub.dev/packages/taggable/example) for one way to display tags outside the text field.

## Additional information

### Limitations

- **Whitespace**: because of the focus on database-friendly storage, tags are currently required to have whitespace before and after them, with the exception of tags that are the first or last characters in the text field. This is to make tags easier to parse and retrieve from the database. For example, the text `Hi @Ada Lovelace how are you?` is valid, but `Hi@Ada Lovelace, how are you?` is not.

### Contributions

Contributions are welcome! If you have any suggestions or improvements, please open an issue or a pull request on the [GitHub repository](https://github.com/WesselvanDam/taggable).


