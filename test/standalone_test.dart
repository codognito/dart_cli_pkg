// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:io';

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'package:cli_pkg/src/utils.dart';

import 'descriptor.dart' as d;
import 'utils.dart';

/// The operating system/architecture combination for the current machine.
///
/// We build this for most tests so we can avoid downloading SDKs from the Dart
/// server.
final _target = Platform.operatingSystem +
    "-" +
    (Platform.version.contains("x64") ? "x64" : "ia32");

/// The archive suffix for the current platform.
final _archiveSuffix = _target + (Platform.isWindows ? ".zip" : ".tar.gz");

/// The contents of a `grind.dart` file that just enables standalone tasks.
final _enableStandalone = """
  void main(List<String> args) {
    pkg.addStandaloneTasks();
    grind(args);
  }
""";

void main() {
  group("directory and archive name", () {
    var pubspec = {
      "name": "my_app",
      "version": "1.2.3",
      "executables": {"foo": "foo"}
    };

    test("default to pkg.dartName", () async {
      await d.package("my_app", pubspec, _enableStandalone).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix",
          [d.dir("my_app")]).validate();
    });

    test("prefer pkg.name to pkg.dartName", () async {
      await d.package("my_app", pubspec, """
        void main(List<String> args) {
          pkg.name = "my-app";
          pkg.addStandaloneTasks();
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my-app-1.2.3-$_archiveSuffix",
          [d.dir("my-app")]).validate();
    });

    test("prefer pkg.standaloneName to pkg.name", () async {
      await d.package("my_app", pubspec, """
        void main(List<String> args) {
          pkg.name = "my-app";
          pkg.standaloneName = "my-sa-app";
          pkg.addStandaloneTasks();
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my-sa-app-1.2.3-$_archiveSuffix",
          [d.dir("my-sa-app")]).validate();
    });
  }, onPlatform: {"windows": Skip("dart-lang/sdk#37897")});

  group("executables", () {
    var pubspec = {
      "name": "my_app",
      "version": "1.2.3",
      "executables": {"foo": "foo", "bar": "bar", "qux": "bar"}
    };

    test("default to the pubspec's executables", () async {
      await d.package("my_app", pubspec, _enableStandalone).create();
      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.file("foo$dotBat", anything),
          d.file("bar$dotBat", anything),
          d.file("qux$dotBat", anything),
          d.dir("src", [
            d.file("foo.dart.snapshot", anything),
            d.file("bar.dart.snapshot", anything),
            d.nothing("qux.dart.snapshot")
          ])
        ])
      ]).validate();
    });

    test("can be removed by the user", () async {
      await d.package("my_app", pubspec, """
        void main(List<String> args) {
          pkg.executables.remove("foo");
          pkg.addStandaloneTasks();
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.nothing("foo$dotBat"),
          d.file("bar$dotBat", anything),
          d.file("qux$dotBat", anything),
          d.dir("src", [
            d.nothing("foo.dart.snapshot"),
            d.file("bar.dart.snapshot", anything)
          ])
        ])
      ]).validate();
    });

    test("can be added by the user", () async {
      await d.package("my_app", pubspec, """
        void main(List<String> args) {
          pkg.executables["zip"] = "bin/foo.dart";
          pkg.addStandaloneTasks();
          grind(args);
        }
      """).create();

      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

      await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
        d.dir("my_app", [
          d.file("foo$dotBat", anything),
          d.file("bar$dotBat", anything),
          d.file("qux$dotBat", anything),
          d.file("zip$dotBat", anything),
          d.dir("src", [
            d.file("foo.dart.snapshot", anything),
            d.file("bar.dart.snapshot", anything),
            d.nothing("zip.dart.snapshot")
          ])
        ])
      ]).validate();
    });

    // Normally each of these would be separate test cases, but running grinder
    // takes so long that we collapse them for efficiency.
    test("can be invoked", () async {
      await d.package("my_app", pubspec, _enableStandalone).create();
      await (await grind(["pkg-standalone-$_target"])).shouldExit(0);
      await extract("my_app/build/my_app-1.2.3-$_archiveSuffix", "out");

      // Directly
      var executable = await TestProcess.start(
          d.path("out/my_app/foo$dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo"));
      await executable.shouldExit(0);

      // Through a redirect
      executable = await TestProcess.start(d.path("out/my_app/qux$dotBat"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in bar"));
      await executable.shouldExit(0);

      // Through a relative symlink
      Link(d.path("foo-relative")).createSync("out/my_app/foo$dotBat");
      executable = await TestProcess.start(d.path("foo-relative"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo"));
      await executable.shouldExit(0);

      // Through an absolute symlink
      Link(d.path("foo-absolute")).createSync(d.path("out/my_app/foo$dotBat"));
      executable = await TestProcess.start(d.path("foo-absolute"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo"));
      await executable.shouldExit(0);

      // Through a nested symlink
      Link(d.path("foo-nested")).createSync(d.path("foo-relative"));
      executable = await TestProcess.start(d.path("foo-nested"), [],
          workingDirectory: d.sandbox);
      expect(executable.stdout, emits("in foo"));
      await executable.shouldExit(0);
    });
  }, onPlatform: {"windows": Skip("dart-lang/sdk#37897")});

  test("includes the package's license and Dart's license", () async {
    await d
        .package(
            "my_app",
            {
              "name": "my_app",
              "version": "1.2.3",
              "executables": {"foo": "foo"}
            },
            _enableStandalone,
            [d.file("LICENSE", "Please use my code")])
        .create();
    await (await grind(["pkg-standalone-$_target"])).shouldExit(0);

    await d.archive("my_app/build/my_app-1.2.3-$_archiveSuffix", [
      d.dir("my_app/src", [
        d.file("LICENSE", "Please use my code"),
        d.file("DART_LICENSE", contains("Dart project authors"))
      ])
    ]).validate();
  }, onPlatform: {"windows": Skip("dart-lang/sdk#37897")});

  group("creates a package for", () {
    setUp(() => d
        .package(
            "my_app",
            {
              "name": "my_app",
              "version": "1.2.3",
              "executables": {"foo": "foo"}
            },
            _enableStandalone)
        .create());

    d.Descriptor archive(String name, {bool windows = false}) =>
        d.archive(name, [
          d.dir("my_app", [
            d.file("foo${windows ? '.bat' : ''}", anything),
            d.dir("src", [
              d.file("DART_LICENSE", anything),
              d.file("dart${windows ? '.exe' : ''}", anything),
              d.file("foo.dart.snapshot", anything)
            ])
          ])
        ]);

    group("Mac OS", () {
      test("32-bit", () async {
        await (await grind(["pkg-standalone-macos-ia32"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-macos-ia32.tar.gz").validate();
      });

      test("64-bit", () async {
        await (await grind(["pkg-standalone-macos-x64"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-macos-x64.tar.gz").validate();
      });
    });

    group("Linux", () {
      test("32-bit", () async {
        await (await grind(["pkg-standalone-linux-ia32"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-linux-ia32.tar.gz").validate();
      });

      test("64-bit", () async {
        await (await grind(["pkg-standalone-linux-x64"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-linux-x64.tar.gz").validate();
      });
    });

    group("Windows", () {
      test("32-bit", () async {
        await (await grind(["pkg-standalone-windows-ia32"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-windows-ia32.zip",
                windows: true)
            .validate();
      });

      test("64-bit", () async {
        await (await grind(["pkg-standalone-windows-x64"])).shouldExit(0);
        await archive("my_app/build/my_app-1.2.3-windows-x64.zip",
                windows: true)
            .validate();
      }, onPlatform: {"windows": Skip("dart-lang/sdk#37897")});
    });

    test("all platforms", () async {
      await (await grind(["pkg-standalone-all"])).shouldExit(0);

      await Future.wait([
        archive("my_app/build/my_app-1.2.3-macos-ia32.tar.gz").validate(),
        archive("my_app/build/my_app-1.2.3-macos-x64.tar.gz").validate(),
        archive("my_app/build/my_app-1.2.3-linux-ia32.tar.gz").validate(),
        archive("my_app/build/my_app-1.2.3-linux-x64.tar.gz").validate(),
        archive("my_app/build/my_app-1.2.3-windows-ia32.zip", windows: true)
            .validate(),
        archive("my_app/build/my_app-1.2.3-windows-x64.zip", windows: true)
            .validate()
      ]);
    }, onPlatform: {"windows": Skip("dart-lang/sdk#37897")});
  });
}
