import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:fymemos/data/services/api/api_client.dart';
import 'package:fymemos/model/memo_request.dart';
import 'package:fymemos/model/memos.dart';
import 'package:fymemos/model/resources.dart';
import 'package:fymemos/utils/result.dart';
import 'package:fymemos/utils/strings.dart';
import 'package:mime/mime.dart';
import 'package:refena_flutter/refena_flutter.dart';

final memoEditVMProvider = NotifierProvider<MemoEditVM, MemoEditData>(
  (ref) => MemoEditVM(),
);

class MemoEditVM extends Notifier<MemoEditData> {
  @override
  MemoEditData init() {
    return MemoEditData(
      content: "",
      images: [],
      visibility: MemoVisibility.Public,
    );
  }

  void updateVisibility(MemoVisibility visibility) {
    state = state.copyWith(newVisibility: visibility, initial: true);
  }

  void initMemo(Memo memo) {
    state = MemoEditData.fromMemo(memo);
  }

  void clear() {
    state = init();
  }

  Future<MemoResource> _uploadImage(File image, {String? memo}) async {
    // 使用 path 包的 basename 跨平台获取文件名，Windows 路径使用 \ 分隔符
    final fileName = p.basename(image.path);
    // 使用 lookupMimeType 获取准确的 MIME 类型，比手动拼 image/ext 更可靠
    final type = lookupMimeType(image.path) ?? 'image/png';
    final bytes = await image.readAsBytes();
    final base64Content = base64Encode(bytes);
    return await ApiClient.instance.createResource(
      CreateResourceRequest(
        filename: fileName,
        content: base64Content,
        type: type,
        memo: memo,
      ),
    );
  }

  bool _isImageFile(File file) {
    final mimeType = lookupMimeType(file.path);
    return mimeType?.startsWith('image/') ?? false;
  }

  void addImage(File image) async {
    print("image: ${image.path}");
    final images = state.images ?? [];
    if (!_isImageFile(image)) {
      return;
    }
    images.add(MemoImage(file: image));
    state = state.copyWith(image: images);
    // 上传统一在 checkImages 中处理，避免竞态条件和重复上传
  }

  void deleteImage(MemoImage img) async {
    final images = state.images ?? [];
    images.remove(img);
    state = state.copyWith(image: images);
    if (img.memoResource != null) {
      await ApiClient.instance.deleteResource(img.memoResource!.name.id);
    }
  }

  void updateContent(String content) {
    state = state.copyWith(desc: content);
  }

  Future<Result<Memo>> saveMemo() async {
    if (state.memoName == null || state.memo == null) {
      return _createMemo();
    } else {
      return _updateMemo();
    }
  }

  Future<Result<Memo>> _updateMemo() async {
    final request = UpdateMemoRequest.copyFromMemo(
      state.memo!,
      content: state.content,
      visibility: state.visibility,
    );
    final result = await ApiClient.instance.updateMemo(state.memoName!, request);
    // 编辑场景下，上传新增的图片并重新获取笔记以包含资源
    if (result is Ok<Memo>) {
      await _uploadPendingImages(result.value.name);
      return await _refetchOrOriginal(result);
    }
    return result;
  }

  Future<Result<Memo>> _createMemo() async {
    // 先创建笔记（不含附件 — v0.29 不支持在创建时关联附件）
    final request = CreateMemoRequest(
      state.content,
      state.visibility,
      [],
    );
    final result = await ApiClient.instance.createMemo(request);
    // 笔记创建成功后，上传图片并关联，然后重新获取完整的笔记数据
    if (result is Ok<Memo>) {
      await _uploadPendingImages(result.value.name);
      return await _refetchOrOriginal(result);
    }
    return result;
  }

  /// 重新获取笔记（含资源），失败时回退到原始结果
  Future<Result<Memo>> _refetchOrOriginal(Result<Memo> original) async {
    try {
      final name = (original as Ok<Memo>).value.name;
      final memo = await ApiClient.instance.getMemoDirect(name);
      return Result.ok(memo);
    } catch (e) {
      print("重新获取笔记失败，使用原始数据: $e");
      return original; // 笔记已保存成功，回退到不含资源的原始数据
    }
  }

  /// 上传所有待处理的图片，关联到指定笔记
  Future<void> _uploadPendingImages(String memoName) async {
    final images = state.images ?? [];
    for (final img in images) {
      if (img.file == null || img.memoResource != null) {
        continue;
      }
      try {
        img.memoResource = await _uploadImage(img.file!, memo: memoName);
      } catch (e) {
        print("图片上传失败: $e");
      }
    }
  }
}

class MemoEditData {
  final String content;
  final String? memoName;
  final List<MemoImage> images;
  final MemoVisibility visibility;
  final Memo? memo;
  final bool initial;

  MemoEditData copyWith({
    List<MemoImage>? image,
    String? name,
    String? desc,
    MemoVisibility? newVisibility,
    bool? initial,
  }) {
    return MemoEditData(
      content: desc ?? content,
      images: image ?? images,
      memoName: name ?? memoName,
      visibility: newVisibility ?? visibility,
      memo: memo,
      initial: initial ?? this.initial,
    );
  }

  factory MemoEditData.fromMemo(Memo memo) {
    return MemoEditData(
      content: memo.content,
      images: memo.resources.map((e) => MemoImage(memoResource: e)).toList(),
      visibility: memo.visibility,
      memoName: memo.name,
      memo: memo,
      initial: true,
    );
  }

  MemoEditData({
    required this.content,
    required this.images,
    required this.visibility,
    this.memoName,
    this.memo = null,
    this.initial = false,
  });
}

class MemoImage {
  File? file;
  MemoResource? memoResource;

  MemoImage({this.file, this.memoResource});
}
