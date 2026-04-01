import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/animation.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/skin.dart';
import 'package:vector_math/vector_math.dart';

/// Parses a GLB (glTF Binary) file and builds a [Node] scene graph directly,
/// bypassing the intermediate .model (FlatBuffer) format.
class GlbLoader {
  GlbLoader._(this._json, this._binData);

  final Map<String, dynamic> _json;
  final ByteData _binData;

  /// Load a GLB file from the Flutter asset bundle and return the root [Node].
  static Future<Node> load(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    return loadFromBytes(data);
  }

  /// Load a GLB from raw bytes and return the root [Node].
  static Future<Node> loadFromBytes(ByteData data) async {
    final loader = _parseGlbContainer(data);
    return loader._buildScene();
  }

  /// Parse the GLB binary container into JSON + BIN chunks.
  static GlbLoader _parseGlbContainer(ByteData data) {
    // GLB Header: magic(4) + version(4) + length(4) = 12 bytes
    final magic = data.getUint32(0, Endian.little);
    if (magic != 0x46546C67) {
      throw Exception('Not a valid GLB file (bad magic)');
    }
    final version = data.getUint32(4, Endian.little);
    if (version != 2) {
      throw Exception('Unsupported glTF version: $version');
    }

    // Chunk 0: JSON
    int offset = 12;
    final jsonChunkLength = data.getUint32(offset, Endian.little);
    final jsonChunkType = data.getUint32(offset + 4, Endian.little);
    if (jsonChunkType != 0x4E4F534A) {
      throw Exception(
        'Expected JSON chunk, got 0x${jsonChunkType.toRadixString(16)}',
      );
    }
    offset += 8;
    final jsonBytes = data.buffer.asUint8List(
      data.offsetInBytes + offset,
      jsonChunkLength,
    );
    final json = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    offset += jsonChunkLength;

    // Chunk 1: BIN (optional)
    ByteData binData = ByteData(0);
    if (offset < data.lengthInBytes) {
      final binChunkLength = data.getUint32(offset, Endian.little);
      final binChunkType = data.getUint32(offset + 4, Endian.little);
      if (binChunkType == 0x004E4942) {
        offset += 8;
        binData = ByteData.sublistView(
          data.buffer.asUint8List(data.offsetInBytes + offset, binChunkLength),
        );
      }
    }

    return GlbLoader._(json, binData);
  }

  // ---- Accessor helpers ----

  List<dynamic>? _list(String key) => _json[key] as List<dynamic>?;

  Map<String, dynamic> _accessor(int index) =>
      (_json['accessors'] as List)[index] as Map<String, dynamic>;

  Map<String, dynamic> _bufferView(int index) =>
      (_json['bufferViews'] as List)[index] as Map<String, dynamic>;

  /// Read raw bytes for an accessor, respecting bufferView offset and stride.
  _AccessorInfo _readAccessor(int accessorIndex) {
    final acc = _accessor(accessorIndex);
    final bv = _bufferView(acc['bufferView'] as int);
    final byteOffset =
        (bv['byteOffset'] as int? ?? 0) + (acc['byteOffset'] as int? ?? 0);
    final count = acc['count'] as int;
    final componentType = acc['componentType'] as int;
    final type = acc['type'] as String;

    final componentCount = _componentCount(type);
    final componentSize = _componentSize(componentType);
    final defaultStride = componentCount * componentSize;
    final stride = bv['byteStride'] as int? ?? defaultStride;

    return _AccessorInfo(
      byteOffset: byteOffset,
      count: count,
      componentType: componentType,
      componentCount: componentCount,
      stride: stride,
    );
  }

  static int _componentCount(String type) {
    return switch (type) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' => 4,
      'MAT4' => 16,
      _ => throw Exception('Unknown accessor type: $type'),
    };
  }

  static int _componentSize(int componentType) {
    return switch (componentType) {
      5120 || 5121 => 1, // BYTE / UNSIGNED_BYTE
      5122 || 5123 => 2, // SHORT / UNSIGNED_SHORT
      5125 || 5126 => 4, // UNSIGNED_INT / FLOAT
      _ => throw Exception('Unknown component type: $componentType'),
    };
  }

  /// Read a float from the binary buffer, converting from the source component type.
  double _readComponent(
    int byteOffset,
    int componentType, {
    bool normalized = true,
  }) {
    return switch (componentType) {
      5120 =>
        normalized
            ? _binData.getInt8(byteOffset) / 127.0
            : _binData.getInt8(byteOffset).toDouble(),
      5121 =>
        normalized
            ? _binData.getUint8(byteOffset) / 255.0
            : _binData.getUint8(byteOffset).toDouble(),
      5122 =>
        normalized
            ? _binData.getInt16(byteOffset, Endian.little) / 32767.0
            : _binData.getInt16(byteOffset, Endian.little).toDouble(),
      5123 =>
        normalized
            ? _binData.getUint16(byteOffset, Endian.little) / 65535.0
            : _binData.getUint16(byteOffset, Endian.little).toDouble(),
      5125 => _binData.getUint32(byteOffset, Endian.little).toDouble(),
      5126 => _binData.getFloat32(byteOffset, Endian.little),
      _ => throw Exception('Unknown component type: $componentType'),
    };
  }

  /// Read float values for an accessor attribute into a pre-allocated vertex buffer.
  void _readAttributeIntoVertices(
    Float32List vertices,
    int vertexFloatStride,
    int destFloatOffset,
    int destComponentCount,
    _AccessorInfo acc, {
    bool normalized = true,
  }) {
    final compSize = _componentSize(acc.componentType);
    for (int i = 0; i < acc.count; i++) {
      final srcBase = acc.byteOffset + i * acc.stride;
      final dstBase = i * vertexFloatStride + destFloatOffset;
      for (int c = 0; c < destComponentCount && c < acc.componentCount; c++) {
        vertices[dstBase + c] = _readComponent(
          srcBase + c * compSize,
          acc.componentType,
          normalized: normalized,
        );
      }
    }
  }

  // ---- Scene building ----

  Future<Node> _buildScene() async {
    // Decode textures.
    final List<gpu.Texture> textures = await _loadTextures();

    // Get the default scene.
    final scenes = _list('scenes');
    final defaultSceneIndex = _json['scene'] as int? ?? 0;
    final scene =
        (scenes != null && defaultSceneIndex < scenes.length)
            ? scenes[defaultSceneIndex] as Map<String, dynamic>
            : <String, dynamic>{};
    final sceneNodeIndices = (scene['nodes'] as List?)?.cast<int>() ?? <int>[];

    // Parse all nodes.
    final gltfNodes = _list('nodes') ?? [];
    final List<Node> sceneNodes = List.generate(
      gltfNodes.length,
      (_) => Node(),
    );

    // Root node with Z-flip (matching the C++ importer).
    final root = Node(
      name: 'root',
      localTransform: Matrix4.diagonal3Values(1, 1, -1),
    );

    // Connect scene root children.
    for (final childIndex in sceneNodeIndices) {
      root.add(sceneNodes[childIndex]);
    }

    // Unpack each node.
    for (int i = 0; i < gltfNodes.length; i++) {
      _processNode(
        gltfNodes[i] as Map<String, dynamic>,
        sceneNodes[i],
        sceneNodes,
        textures,
      );
    }

    // Unpack animations.
    final animations = _list('animations');
    if (animations != null) {
      for (final anim in animations) {
        root.parsedAnimations.add(
          _processAnimation(anim as Map<String, dynamic>, sceneNodes),
        );
      }
    }

    debugPrint(
      'GLB loaded: ${gltfNodes.length} nodes, ${textures.length} textures',
    );
    return root;
  }

  // ---- Textures ----

  Future<List<gpu.Texture>> _loadTextures() async {
    final gltfTextures = _list('textures');
    if (gltfTextures == null) return [];

    final gltfImages = _list('images') ?? [];
    final List<gpu.Texture> result = [];

    for (final tex in gltfTextures) {
      final texMap = tex as Map<String, dynamic>;
      final sourceIndex = texMap['source'] as int?;
      if (sourceIndex == null || sourceIndex >= gltfImages.length) {
        result.add(Material.getWhitePlaceholderTexture());
        continue;
      }

      final image = gltfImages[sourceIndex] as Map<String, dynamic>;
      final bufferViewIndex = image['bufferView'] as int?;

      if (bufferViewIndex != null) {
        // Embedded image - decode from binary buffer.
        final bv = _bufferView(bufferViewIndex);
        final offset = bv['byteOffset'] as int? ?? 0;
        final length = bv['byteLength'] as int;
        final imageBytes = _binData.buffer.asUint8List(
          _binData.offsetInBytes + offset,
          length,
        );

        try {
          final gpuTexture = await _decodeImageToGpuTexture(imageBytes);
          result.add(gpuTexture);
        } catch (e) {
          debugPrint('Failed to decode embedded texture $sourceIndex: $e');
          result.add(Material.getWhitePlaceholderTexture());
        }
      } else {
        // URI-based texture - not supported for GLB (would need external file loading).
        debugPrint(
          'Texture $sourceIndex has no embedded data, using placeholder.',
        );
        result.add(Material.getWhitePlaceholderTexture());
      }
    }

    return result;
  }

  /// Decode compressed image bytes (JPEG/PNG) to a GPU texture with raw RGBA pixels.
  static Future<gpu.Texture> _decodeImageToGpuTexture(
    Uint8List imageBytes,
  ) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final uiImage = frame.image;

    final byteData = await uiImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw Exception('Failed to get raw RGBA data from image');
    }

    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      uiImage.width,
      uiImage.height,
    );
    texture.overwrite(byteData);

    uiImage.dispose();
    codec.dispose();

    return texture;
  }

  // ---- Nodes ----

  void _processNode(
    Map<String, dynamic> gltfNode,
    Node node,
    List<Node> sceneNodes,
    List<gpu.Texture> textures,
  ) {
    node.name = gltfNode['name'] as String? ?? '';

    // Transform.
    node.localTransform = _parseTransform(gltfNode);

    // Children.
    final children = (gltfNode['children'] as List?)?.cast<int>();
    if (children != null) {
      for (final childIndex in children) {
        node.add(sceneNodes[childIndex]);
      }
    }

    // Mesh.
    final meshIndex = gltfNode['mesh'] as int?;
    if (meshIndex != null) {
      final meshes = _list('meshes')!;
      final mesh = meshes[meshIndex] as Map<String, dynamic>;
      final primitives =
          (mesh['primitives'] as List).cast<Map<String, dynamic>>();

      final List<MeshPrimitive> meshPrimitives = [];
      for (final primitive in primitives) {
        final mp = _processMeshPrimitive(primitive, textures);
        if (mp != null) meshPrimitives.add(mp);
      }
      if (meshPrimitives.isNotEmpty) {
        node.mesh = Mesh.primitives(primitives: meshPrimitives);
      }
    }

    // Skin.
    final skinIndex = gltfNode['skin'] as int?;
    if (skinIndex != null) {
      node.skin = _processSkin(skinIndex, sceneNodes);
    }
  }

  Matrix4 _parseTransform(Map<String, dynamic> gltfNode) {
    // If a matrix is provided, use it directly.
    final matrixData = gltfNode['matrix'] as List?;
    if (matrixData != null && matrixData.length == 16) {
      return Matrix4.fromList(
        matrixData.map((e) => (e as num).toDouble()).toList(),
      );
    }

    // Otherwise compose from TRS.
    Matrix4 transform = Matrix4.identity();

    final translation = gltfNode['translation'] as List?;
    if (translation != null && translation.length == 3) {
      transform =
          Matrix4.translationValues(
            (translation[0] as num).toDouble(),
            (translation[1] as num).toDouble(),
            (translation[2] as num).toDouble(),
          ) *
          transform;
    }

    final rotation = gltfNode['rotation'] as List?;
    if (rotation != null && rotation.length == 4) {
      final q = Quaternion(
        (rotation[0] as num).toDouble(),
        (rotation[1] as num).toDouble(),
        (rotation[2] as num).toDouble(),
        (rotation[3] as num).toDouble(),
      );
      final rotMatrix = Matrix4.identity()..setRotation(q.asRotationMatrix());
      transform = rotMatrix * transform;
    }

    final scale = gltfNode['scale'] as List?;
    if (scale != null && scale.length == 3) {
      transform =
          Matrix4.diagonal3Values(
            (scale[0] as num).toDouble(),
            (scale[1] as num).toDouble(),
            (scale[2] as num).toDouble(),
          ) *
          transform;
    }

    return transform;
  }

  // ---- Mesh Primitives ----

  MeshPrimitive? _processMeshPrimitive(
    Map<String, dynamic> primitive,
    List<gpu.Texture> textures,
  ) {
    final attributes = primitive['attributes'] as Map<String, dynamic>?;
    if (attributes == null) return null;

    final bool isSkinned =
        attributes.containsKey('JOINTS_0') &&
        attributes.containsKey('WEIGHTS_0');

    // Determine vertex count from POSITION accessor.
    final positionAccIndex = attributes['POSITION'] as int?;
    if (positionAccIndex == null) return null;
    final positionAcc = _readAccessor(positionAccIndex);
    final vertexCount = positionAcc.count;

    // Build vertex buffer.
    // Unskinned layout: position(3) + normal(3) + texcoords(2) + color(4) = 12 floats = 48 bytes
    // Skinned layout: + joints(4) + weights(4) = 20 floats = 80 bytes
    final floatsPerVertex = isSkinned ? 20 : 12;
    final vertices = Float32List(vertexCount * floatsPerVertex);

    // Default color to white (1,1,1,1).
    for (int i = 0; i < vertexCount; i++) {
      final base = i * floatsPerVertex;
      vertices[base + 8] = 1.0; // color.r
      vertices[base + 9] = 1.0; // color.g
      vertices[base + 10] = 1.0; // color.b
      vertices[base + 11] = 1.0; // color.a
    }

    // Position (offset 0, 3 components).
    _readAttributeIntoVertices(vertices, floatsPerVertex, 0, 3, positionAcc);

    // Normal (offset 3, 3 components).
    final normalAccIndex = attributes['NORMAL'] as int?;
    if (normalAccIndex != null) {
      _readAttributeIntoVertices(
        vertices,
        floatsPerVertex,
        3,
        3,
        _readAccessor(normalAccIndex),
      );
    }

    // Texture coordinates (offset 6, 2 components).
    final texCoordAccIndex = attributes['TEXCOORD_0'] as int?;
    if (texCoordAccIndex != null) {
      _readAttributeIntoVertices(
        vertices,
        floatsPerVertex,
        6,
        2,
        _readAccessor(texCoordAccIndex),
      );
    }

    // Color (offset 8, 4 components).
    final colorAccIndex = attributes['COLOR_0'] as int?;
    if (colorAccIndex != null) {
      _readAttributeIntoVertices(
        vertices,
        floatsPerVertex,
        8,
        4,
        _readAccessor(colorAccIndex),
      );
    }

    // Skinning attributes.
    if (isSkinned) {
      // Joints (offset 12, 4 components) - NOT normalized.
      final jointsAccIndex = attributes['JOINTS_0'] as int;
      _readAttributeIntoVertices(
        vertices,
        floatsPerVertex,
        12,
        4,
        _readAccessor(jointsAccIndex),
        normalized: false,
      );

      // Weights (offset 16, 4 components).
      final weightsAccIndex = attributes['WEIGHTS_0'] as int;
      _readAttributeIntoVertices(
        vertices,
        floatsPerVertex,
        16,
        4,
        _readAccessor(weightsAccIndex),
      );
    }

    // Indices.
    final indicesAccIndex = primitive['indices'] as int?;
    if (indicesAccIndex == null) {
      debugPrint('Mesh primitive has no index buffer. Skipping.');
      return null;
    }
    final indicesAcc = _readAccessor(indicesAccIndex);
    final indexComponentSize = _componentSize(indicesAcc.componentType);
    final indexByteLength = indicesAcc.count * indexComponentSize;
    final indexBytes = Uint8List(indexByteLength);

    // Copy index data.
    for (int i = 0; i < indexByteLength; i++) {
      indexBytes[i] = _binData.getUint8(indicesAcc.byteOffset + i);
    }

    gpu.IndexType indexType;
    switch (indicesAcc.componentType) {
      case 5123: // UNSIGNED_SHORT
        indexType = gpu.IndexType.int16;
      case 5125: // UNSIGNED_INT
        indexType = gpu.IndexType.int32;
      default:
        debugPrint('Unsupported index type: ${indicesAcc.componentType}');
        return null;
    }

    // Create geometry.
    Geometry geometry = isSkinned ? SkinnedGeometry() : UnskinnedGeometry();
    geometry.uploadVertexData(
      ByteData.sublistView(vertices),
      vertexCount,
      ByteData.sublistView(indexBytes),
      indexType: indexType,
    );

    // Material.
    Material material;
    final materialIndex = primitive['material'] as int?;
    if (materialIndex != null) {
      final gltfMaterials = _list('materials')!;
      material = _processMaterial(
        gltfMaterials[materialIndex] as Map<String, dynamic>,
        textures,
      );
    } else {
      material = UnlitMaterial();
    }

    return MeshPrimitive(geometry, material);
  }

  // ---- Materials ----

  Material _processMaterial(
    Map<String, dynamic> gltfMaterial,
    List<gpu.Texture> textures,
  ) {
    final pbr = gltfMaterial['pbrMetallicRoughness'] as Map<String, dynamic>?;

    final mat = PhysicallyBasedMaterial();
    mat.doubleSided = gltfMaterial['doubleSided'] as bool? ?? false;

    if (pbr != null) {
      // Base color factor.
      final bcf = pbr['baseColorFactor'] as List?;
      if (bcf != null && bcf.length == 4) {
        mat.baseColorFactor = Vector4(
          (bcf[0] as num).toDouble(),
          (bcf[1] as num).toDouble(),
          (bcf[2] as num).toDouble(),
          (bcf[3] as num).toDouble(),
        );
      }

      // Base color texture.
      final bct = pbr['baseColorTexture'] as Map<String, dynamic>?;
      if (bct != null) {
        final texIndex = _resolveTextureIndex(bct);
        if (texIndex >= 0 && texIndex < textures.length) {
          mat.baseColorTexture = textures[texIndex];
        }
      }

      // Metallic/roughness factors.
      mat.metallicFactor = (pbr['metallicFactor'] as num?)?.toDouble() ?? 1.0;
      mat.roughnessFactor = (pbr['roughnessFactor'] as num?)?.toDouble() ?? 1.0;

      // Metallic-roughness texture.
      final mrt = pbr['metallicRoughnessTexture'] as Map<String, dynamic>?;
      if (mrt != null) {
        final texIndex = _resolveTextureIndex(mrt);
        if (texIndex >= 0 && texIndex < textures.length) {
          mat.metallicRoughnessTexture = textures[texIndex];
        }
      }
    }

    // Normal texture.
    final normalTex = gltfMaterial['normalTexture'] as Map<String, dynamic>?;
    if (normalTex != null) {
      final texIndex = _resolveTextureIndex(normalTex);
      if (texIndex >= 0 && texIndex < textures.length) {
        mat.normalTexture = textures[texIndex];
      }
      mat.normalScale = (normalTex['scale'] as num?)?.toDouble() ?? 1.0;
    }

    // Emissive.
    final emissiveFactor = gltfMaterial['emissiveFactor'] as List?;
    if (emissiveFactor != null && emissiveFactor.length == 3) {
      mat.emissiveFactor = Vector4(
        (emissiveFactor[0] as num).toDouble(),
        (emissiveFactor[1] as num).toDouble(),
        (emissiveFactor[2] as num).toDouble(),
        1.0,
      );
    }
    final emissiveTex =
        gltfMaterial['emissiveTexture'] as Map<String, dynamic>?;
    if (emissiveTex != null) {
      final texIndex = _resolveTextureIndex(emissiveTex);
      if (texIndex >= 0 && texIndex < textures.length) {
        mat.emissiveTexture = textures[texIndex];
      }
    }

    // Occlusion.
    final occlusionTex =
        gltfMaterial['occlusionTexture'] as Map<String, dynamic>?;
    if (occlusionTex != null) {
      mat.occlusionStrength =
          (occlusionTex['strength'] as num?)?.toDouble() ?? 1.0;
      final texIndex = _resolveTextureIndex(occlusionTex);
      if (texIndex >= 0 && texIndex < textures.length) {
        mat.occlusionTexture = textures[texIndex];
      }
    }

    return mat;
  }

  int _resolveTextureIndex(Map<String, dynamic> textureInfo) {
    final texCoord = textureInfo['texCoord'] as int? ?? 0;
    if (texCoord != 0) return -1; // Only support texCoord set 0.
    return textureInfo['index'] as int? ?? -1;
  }

  // ---- Skin ----

  Skin _processSkin(int skinIndex, List<Node> sceneNodes) {
    final skins = _list('skins')!;
    final gltfSkin = skins[skinIndex] as Map<String, dynamic>;

    final joints = (gltfSkin['joints'] as List).cast<int>();
    final ibmAccessorIndex = gltfSkin['inverseBindMatrices'] as int;
    final ibmAcc = _readAccessor(ibmAccessorIndex);

    final skin = Skin();
    for (final jointIndex in joints) {
      sceneNodes[jointIndex].isJoint = true;
      skin.joints.add(sceneNodes[jointIndex]);
    }

    // Read inverse bind matrices.
    final compSize = _componentSize(ibmAcc.componentType);
    for (int i = 0; i < ibmAcc.count; i++) {
      final base = ibmAcc.byteOffset + i * ibmAcc.stride;
      final floats = Float64List(16);
      for (int f = 0; f < 16; f++) {
        floats[f] = _readComponent(
          base + f * compSize,
          ibmAcc.componentType,
          normalized: false,
        );
      }
      skin.inverseBindMatrices.add(Matrix4.fromList(floats.toList()));
    }

    return skin;
  }

  // ---- Animations ----

  Animation _processAnimation(
    Map<String, dynamic> gltfAnimation,
    List<Node> sceneNodes,
  ) {
    final name = gltfAnimation['name'] as String? ?? '';
    final channels =
        (gltfAnimation['channels'] as List).cast<Map<String, dynamic>>();
    final samplers =
        (gltfAnimation['samplers'] as List).cast<Map<String, dynamic>>();

    // Separate channels by type to match the C++ importer ordering.
    final List<_AnimChannelData> translationChannels = [];
    final List<_AnimChannelData> rotationChannels = [];
    final List<_AnimChannelData> scaleChannels = [];

    for (final channel in channels) {
      final target = channel['target'] as Map<String, dynamic>;
      final nodeIndex = target['node'] as int;
      final path = target['path'] as String;
      final samplerIndex = channel['sampler'] as int;
      final sampler = samplers[samplerIndex];

      // Timeline (input).
      final inputAccIndex = sampler['input'] as int;
      final inputAcc = _readAccessor(inputAccIndex);
      if (inputAcc.count <= 0) continue;

      final timeline = Float32List(inputAcc.count);
      for (int i = 0; i < inputAcc.count; i++) {
        timeline[i] = _readComponent(
          inputAcc.byteOffset + i * inputAcc.stride,
          inputAcc.componentType,
          normalized: false,
        );
      }

      // Values (output).
      final outputAccIndex = sampler['output'] as int;
      final outputAcc = _readAccessor(outputAccIndex);
      if (outputAcc.count != inputAcc.count) continue;

      final outputCompSize = _componentSize(outputAcc.componentType);

      final channelData = _AnimChannelData(
        nodeIndex: nodeIndex,
        timeline: timeline,
        path: path,
      );

      switch (path) {
        case 'translation':
          if (outputAcc.componentCount != 3) continue;
          final values = <Vector3>[];
          for (int i = 0; i < outputAcc.count; i++) {
            final base = outputAcc.byteOffset + i * outputAcc.stride;
            values.add(
              Vector3(
                _readComponent(
                  base,
                  outputAcc.componentType,
                  normalized: false,
                ),
                _readComponent(
                  base + outputCompSize,
                  outputAcc.componentType,
                  normalized: false,
                ),
                _readComponent(
                  base + 2 * outputCompSize,
                  outputAcc.componentType,
                  normalized: false,
                ),
              ),
            );
          }
          channelData.translationValues = values;
          translationChannels.add(channelData);

        case 'rotation':
          if (outputAcc.componentCount != 4) continue;
          final values = <Vector4>[];
          for (int i = 0; i < outputAcc.count; i++) {
            final base = outputAcc.byteOffset + i * outputAcc.stride;
            values.add(
              Vector4(
                _readComponent(
                  base,
                  outputAcc.componentType,
                  normalized: false,
                ),
                _readComponent(
                  base + outputCompSize,
                  outputAcc.componentType,
                  normalized: false,
                ),
                _readComponent(
                  base + 2 * outputCompSize,
                  outputAcc.componentType,
                  normalized: false,
                ),
                _readComponent(
                  base + 3 * outputCompSize,
                  outputAcc.componentType,
                  normalized: false,
                ),
              ),
            );
          }
          channelData.rotationValues = values;
          rotationChannels.add(channelData);

        case 'scale':
          if (outputAcc.componentCount != 3) continue;
          final values = <Vector3>[];
          for (int i = 0; i < outputAcc.count; i++) {
            final base = outputAcc.byteOffset + i * outputAcc.stride;
            values.add(
              Vector3(
                _readComponent(
                  base,
                  outputAcc.componentType,
                  normalized: false,
                ),
                _readComponent(
                  base + outputCompSize,
                  outputAcc.componentType,
                  normalized: false,
                ),
                _readComponent(
                  base + 2 * outputCompSize,
                  outputAcc.componentType,
                  normalized: false,
                ),
              ),
            );
          }
          channelData.scaleValues = values;
          scaleChannels.add(channelData);
      }
    }

    // Build Animation channels.
    final List<AnimationChannel> animChannels = [];

    for (final ch in translationChannels) {
      final resolver = PropertyResolver.makeTranslationTimeline(
        ch.timeline.toList(),
        ch.translationValues!,
      );
      animChannels.add(
        AnimationChannel(
          bindTarget: BindKey(
            nodeName: sceneNodes[ch.nodeIndex].name,
            property: AnimationProperty.translation,
          ),
          resolver: resolver,
        ),
      );
    }

    for (final ch in rotationChannels) {
      final values =
          ch.rotationValues!
              .map((v) => Quaternion(v.x, v.y, v.z, v.w))
              .toList();
      final resolver = PropertyResolver.makeRotationTimeline(
        ch.timeline.toList(),
        values,
      );
      animChannels.add(
        AnimationChannel(
          bindTarget: BindKey(
            nodeName: sceneNodes[ch.nodeIndex].name,
            property: AnimationProperty.rotation,
          ),
          resolver: resolver,
        ),
      );
    }

    for (final ch in scaleChannels) {
      final resolver = PropertyResolver.makeScaleTimeline(
        ch.timeline.toList(),
        ch.scaleValues!,
      );
      animChannels.add(
        AnimationChannel(
          bindTarget: BindKey(
            nodeName: sceneNodes[ch.nodeIndex].name,
            property: AnimationProperty.scale,
          ),
          resolver: resolver,
        ),
      );
    }

    return Animation(name: name, channels: animChannels);
  }
}

class _AccessorInfo {
  final int byteOffset;
  final int count;
  final int componentType;
  final int componentCount;
  final int stride;

  _AccessorInfo({
    required this.byteOffset,
    required this.count,
    required this.componentType,
    required this.componentCount,
    required this.stride,
  });
}

class _AnimChannelData {
  final int nodeIndex;
  final Float32List timeline;
  final String path;
  List<Vector3>? translationValues;
  List<Vector4>? rotationValues;
  List<Vector3>? scaleValues;

  _AnimChannelData({
    required this.nodeIndex,
    required this.timeline,
    required this.path,
  });
}
