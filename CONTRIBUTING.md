# Contributing to syncitron

Thank you for your interest in contributing to syncitron! We welcome contributions from everyone. This document provides guidelines and instructions for contributing.

## Code of Conduct

We are committed to providing a welcoming, inclusive environment for all contributors. Please:

- Be respectful and constructive
- Welcome diverse perspectives
- Focus on what is best for the community
- Show empathy to other contributors

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check the issue list as you might find out that you don't need to create one.

When filing a bug report, include:

- **Description**: Clear and concise description of the bug
- **Environment**: Flutter version, Dart version, platform (iOS/Android/web)
- **Steps to Reproduce**: Minimal code sample that triggers the bug
- **Expected Behavior**: What should happen
- **Actual Behavior**: What actually happens
- **Screenshots/Videos**: If applicable

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When suggesting an enhancement:

- Use a clear descriptive title
- Provide a detailed description of the enhancement
- Provide use cases for the enhancement
- List similar functionality in other packages

### Pull Requests

We actively welcome pull requests!

#### Before You Start

1. Fork the repository
2. Create a new branch for your feature: `git checkout -b feature/my-feature`
3. Make sure you have the latest code from main

#### Guidelines

- **One feature per PR**: Keep PRs focused and small
- **Follow the code style**: See style guide below
- **Write tests**: All new features must have tests
- **Update documentation**: Update README, inline docs if needed
- **Reference issues**: Link related issues in the PR description

#### Development Environment Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/syncitron.git

# Navigate to the directory
cd syncitron

# Get dependencies
flutter pub get

# Run tests
flutter test

# Run lints
flutter analyze
```

## Code Style Guide

### Dart Style

We follow the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style):

- Use 2 spaces for indentation (never tabs)
- Use camelCase for variables, functions, and methods
- Use PascalCase for classes and enums
- Use UPPER_SNAKE_CASE for constants
- Keep lines under 80 characters when possible

### Formatting

Run `dart format` to automatically format code:

```bash
dart format lib/
```

### Linting

We use the following lints via `flutter_lints`:

```bash
flutter analyze
```

Fix issues before submitting your PR.

### Documentation

All public APIs must be documented:

```dart
/// Syncs all registered tables in sequence.
///
/// Returns metrics summarizing the sync session including:
/// - Number of records pulled and pushed
/// - Conflicts encountered and resolved
/// - Duration of the sync
/// - Any errors that occurred
///
/// Throws [syncitronException] on fatal errors.
/// Individual table errors are logged but don't prevent other tables from syncing.
///
/// Example:
/// ```dart
/// final metrics = await engine.syncAll();
/// print('Synced ${metrics.totalRecordsPulled} records');
/// ```
Future<SyncSessionMetrics> syncAll() async {
  // Implementation
}
```

### Commit Messages

Use clear, descriptive commit messages:

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit first line to 50 characters
- Reference issues and PRs in the body

Example:
```
Add comprehensive logging framework

- Implement Logger interface for dependency injection
- Add ConsoleLogger and MultiLogger implementations
- Support structured logging for APM integrations

Fixes #123
```

## Testing

### Writing Tests

All new features must include tests. We use `flutter_test`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:syncitron/syncitron.dart';

void main() {
  group('SyncEngine', () {
    test('initializes without errors', () async {
      final engine = SyncEngine(
        localStore: MockLocalStore(),
        remoteAdapter: MockRemoteAdapter(),
        config: syncitronConfig.testing(),
      );

      await engine.init();
      expect(engine, isNotNull);
    });

    test('handles network errors gracefully', () async {
      final engine = SyncEngine(
        localStore: MockLocalStore(),
        remoteAdapter: MockRemoteAdapter(throwNetworkError: true),
      );

      expect(
        () => engine.syncAll(),
        throwsA(isA<SyncNetworkException>()),
      );
    });
  });
}
```

### Running Tests

```bash
# Run all tests
flutter test

# Run tests in a specific file
flutter test test/file_test.dart

# Run tests with coverage
flutter test --coverage

# Monitor tests (watch mode)
flutter test --watch
```

### Test Organization

- Place tests in the `test/` directory
- Mirror the `lib/` structure in `test/`
- Use descriptive test names that explain what is being tested
- Group related tests with `group()`

## Documentation

### README Files

- Keep README.md up-to-date with current API usage
- Include examples for all major features
- Link to detailed guides for complex topics
- Use clear, accessible language

### API Documentation

- Document all public classes and methods
- Use triple-slash comments (`///`) for public API
- Include examples in doc comments
- Document parameters, return values, and exceptions

### Changelog

Update CHANGELOG.md for all changes:

- Follow [Keep a Changelog](https://keepachangelog.com/) format
- Group changes by type (Added, Changed, Fixed, etc.)
- Include migration notes for breaking changes

## Architecture & Design Patterns

### Design Principles

syncitron follows these principles:

1. **Simplicity**: Simple APIs for common use cases
2. **Flexibility**: Pluggable architecture for advanced use cases
3. **Composability**: Components work well together
4. **Observability**: Comprehensive logging and metrics
5. **Safety**: Strong error handling and recovery

### Patterns Used

- **Dependency Injection**: Pass dependencies, don't create them
- **Strategy Pattern**: Conflict resolution strategies
- **Adapter Pattern**: Remote adapters for different backends
- **Observer Pattern**: Status streams for UI updates

### Code Organization

```
lib/
  syncitron.dart (root export)
  src/
    core/ (sync logic, models, exceptions, configuration)
    adapters/ (RemoteAdapter implementations)
    storage/ (LocalStore implementations)
    utils/ (Helper functions)
```

## Submitting Changes

### Pre-submission Checklist

- [ ] Code follows the style guide
- [ ] Code is properly formatted (`dart format`)
- [ ] Linter passes (`flutter analyze`)
- [ ] All tests pass (`flutter test`)
- [ ] New tests added for new features
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Commit messages are clear and descriptive

### Creating a Pull Request

1. Push to your fork
2. Open a pull request on GitHub
3. Fill in the PR template completely
4. Link related issues
5. Request review from maintainers

### Code Review Process

- At least one maintainer will review your PR
- We may request changes or ask clarifying questions
- Be prepared to iterate on feedback
- Tests must pass before merging

## Release Process

Only maintainers can create releases. The process is:

1. Update version in `pubspec.yaml`
2. Update `CHANGELOG.md`
3. Create GitHub release with changelog
4. Run `flutter pub publish`

## Support

### Getting Help

- **Documentation**: Check [ENTERPRISE_README.md](ENTERPRISE_README.md)
- **Examples**: See [example/](example/) directory
- **Issues**: Search [GitHub issues](https://github.com/leonhardWullich/syncitron/issues)
- **Discussions**: Ask in [GitHub discussions](https://github.com/leonhardWullich/syncitron/discussions)

## Legal

By contributing to syncitron, you agree that your contributions are licensed
under the MIT License for the current open-source distribution.

Roadmap note: maintainers may offer future releases under a dual-license
model as the project grows. Permissions already granted under MIT for
published versions remain valid.

---

Thank you for contributing to syncitron! 🎉
