import 'package:native_assets_cli/native_assets_cli.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    // This package ships the generated Dart model schema used by `flutter_scene`
    // at runtime. Building the offline importer executable is only needed when
    // converting `.glb` assets during development, not when consuming checked-in
    // `.model` files in an application build.
  });
}
