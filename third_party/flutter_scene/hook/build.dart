import 'package:native_assets_cli/native_assets_cli.dart';

import 'package:flutter_gpu_shaders/build.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    // The importer package already ships the generated Dart sources used at
    // runtime. Regenerating them here requires a local CMake toolchain, which
    // is unnecessary for this app because it consumes prebuilt `.model` assets.

    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/base.shaderbundle.json',
    );
  });
}
