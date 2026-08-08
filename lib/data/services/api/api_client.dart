import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:fymemos/model/memo_request.dart';
import 'package:fymemos/model/memos.dart';
import 'package:fymemos/model/resources.dart';
import 'package:fymemos/model/users.dart';
import 'package:fymemos/utils/load_state.dart';
import 'package:fymemos/utils/result.dart';

class ApiClient {
  int PAGE_SIZE = 20;

  static final instance = ApiClient();

  final dio = Dio();
  final Map<String, String> requestHeaders = {};
  String get baseUrl {
    return dio.options.baseUrl;
  }

  void initDio({required String baseUrl, required String token}) {
    dio.options.baseUrl = baseUrl;
    MemoResource.setServerBaseUrl(baseUrl);
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          options.headers["Authorization"] = "Bearer $token";
          return handler.next(options);
        },
      ),
    );
    requestHeaders["Authorization"] = "Bearer $token";
    dio.interceptors.add(
      LogInterceptor(
        responseBody: true,
        requestHeader: true,
        requestBody: true,
        logPrint: (o) => debugPrint(o.toString()),
      ),
    );
    dio.transformer = BackgroundTransformer();
  }

  /// v0.29: POST /api/v1/auth/signin
  /// Request body: { "passwordCredentials": { "username": "...", "password": "..." } }
  /// Response: { "user": {...}, "accessToken": "..." }
  Future<Result<UserProfile>> signIn(
    String baseUrl,
    String userName,
    String password,
  ) async {
    try {
      final res = await dio.post(
        "$baseUrl/api/v1/auth/signin",
        data: {
          "passwordCredentials": {
            "username": userName,
            "password": password,
          },
        },
      );
      final data = res.data as Map<String, dynamic>;
      final token = data['accessToken'] as String?;
      return Result.ok(
        UserProfile.fromJson(data['user'] as Map<String, dynamic>).copyWith(
          token: token,
        ),
      );
    } on DioException catch (e) {
      return Result.error(e);
    }
  }

  /// v0.29: GET /api/v1/memos (global memos list, use filter for user-specific)
  Future<MemosResponse> fetchMemos({
    String? parent,
    String? pageToken,
    String? state,
    String? filter,
  }) async {
    final res = await dio.get(
      "/api/v1/memos",
      queryParameters: {
        if (parent != null) 'parent': parent,
        if (pageToken != null) 'pageToken': pageToken,
        if (state != null) 'state': state,
        if (filter != null) 'filter': filter,
        'pageSize': PAGE_SIZE,
      },
    );
    return MemosResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// v0.29: GET /api/v1/memos with filter for specific user
  /// e.g. filter = 'creator == "users/username"'
  Future<LoadState<MemosResponse>> fetchUserMemos({
    required user,
    String? pageToken,
    String? state,
    String? filter,
  }) async {
    try {
      // v0.29: no per-user endpoint, use global with filter
      final userFilter = 'creator == "users/$user"';
      final combinedFilter = filter != null
          ? '$userFilter && ($filter)'
          : userFilter;
      final res = await dio.get(
        "/api/v1/memos",
        queryParameters: {
          if (pageToken != null) 'pageToken': pageToken,
          'filter': combinedFilter,
          'pageSize': PAGE_SIZE,
        },
      );
      return LoadState.ok(
        MemosResponse.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return LoadState.error(e);
    }
  }

  /// v0.29: same as fetchUserMemos but throws on error
  Future<MemosResponse> fetchUserMemosDirect({
    required user,
    String? pageToken,
    String? state,
    String? filter,
  }) async {
    final userFilter = 'creator == "users/$user"';
    final combinedFilter = filter != null
        ? '$userFilter && ($filter)'
        : userFilter;
    final res = await dio.get(
      "/api/v1/memos",
      queryParameters: {
        if (pageToken != null) 'pageToken': pageToken,
        'filter': combinedFilter,
        'pageSize': PAGE_SIZE,
      },
    );
    return MemosResponse.fromJson(res.data as Map<String, dynamic>);
  }

  /// v0.29: GET /api/v1/attachments (renamed from resources)
  Future<List<MemoResource>> fetchMemoResources() async {
    final res = await dio.get("/api/v1/attachments");
    final data = res.data as Map<String, dynamic>;
    // 使用 MemoResourcesResponse.fromJson 安全解析，兼容 v0.29 attachments 和旧版 resources 字段
    final response = MemoResourcesResponse.fromJson(data);
    return response.resources ?? [];
  }

  /// v0.29: POST /api/v1/attachments (renamed from resources)
  Future<MemoResource> createResource(CreateResourceRequest request) async {
    final res = await dio.post(
      "/api/v1/attachments",
      data: jsonEncode(request.toJson()),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );
    return MemoResource.fromJson(res.data as Map<String, dynamic>);
  }

  /// v0.29: DELETE /api/v1/{name=attachments/*}
  Future<void> deleteResource(String id) async {
    await dio.delete("/api/v1/$id");
  }

  /// v0.29: tags endpoints removed. Use memo update to remove tags.
  Future<Result<void>> deleteTag(String name) async {
    try {
      // In v0.29, there's no dedicated tag delete endpoint.
      // Tags are extracted from memo content, so we skip this.
      return Result.ok(null);
    } on DioException catch (e) {
      return Result.error(e);
    }
  }

  /// v0.29: tags:rename endpoint removed.
  Future<Result<void>> renameTag(String oldName, String newName) async {
    try {
      // In v0.29, there's no dedicated tag rename endpoint.
      // Tags are extracted from memo content.
      return Result.ok(null);
    } on DioException catch (e) {
      return Result.error(e);
    }
  }

  /// v0.29: POST /api/v1/memos
  /// v0.29 ignores "memo" wrapper for create, use flat format
  Future<Result<Memo>> createMemo(CreateMemoRequest request) async {
    try {
      final res = await dio.post(
        "/api/v1/memos",
        data: jsonEncode(request.toJson()),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );
      return Result.ok(Memo.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Result.error(e);
    }
  }

  /// v0.29: GET /api/v1/{name=memos/*}
  Future<LoadState<Memo>> getMemo(String name) async {
    try {
      final res = await dio.get("/api/v1/$name");
      return LoadState.success(Memo.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return LoadState.error(e);
    }
  }

  /// v0.29: GET /api/v1/{name=memos/*}
  Future<Memo> getMemoDirect(String name) async {
    final res = await dio.get("/api/v1/$name");
    return Memo.fromJson(res.data as Map<String, dynamic>);
  }

  /// v0.29: GET /api/v1/{name=users/*}:getStats
  /// name should be like "rayleighaether" (username only, without "users/" prefix)
  Future<Result<UserStats>> getUserStats(String name) async {
    try {
      final res = await dio.get("/api/v1/users/$name:getStats");
      return Result.ok(UserStats.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Result.error(e);
    }
  }

  /// v0.29: GET /api/v1/auth/me
  Future<Result<UserProfile>> getAuthStatus() async {
    try {
      final res = await dio.get("/api/v1/auth/me");
      final data = res.data as Map<String, dynamic>;
      return Result.ok(
        UserProfile.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Result.error(e);
    }
  }

  /// v0.29: GET /api/v1/{name=users/*/settings/*}
  /// Not critical for basic functionality, skip if not found.
  Future<UserSttings> getUserSettings(String name) async {
    try {
      final res = await dio.get("/api/v1/$name/settings/general");
      return UserSttings.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (_) {
      // Return default if settings endpoint not available
      return UserSttings(memoVisibility: MemoVisibility.Private);
    }
  }

  /// v0.29: GET /api/v1/{name=users/*}:getStats
  Future<UserStats> getUserStatsDirect(String name) async {
    // name is like "users/rayleighaether" - just pass it directly
    final res = await dio.get("/api/v1/$name:getStats");
    return UserStats.fromJson(res.data as Map<String, dynamic>);
  }

  /// v0.29: GET /api/v1/auth/me
  Future<UserProfile> getAuthStatusDirect() async {
    final res = await dio.get("/api/v1/auth/me");
    final data = res.data as Map<String, dynamic>;
    return UserProfile.fromJson(data['user'] as Map<String, dynamic>);
  }

  Map<String, dynamic> _parseAndDecode(String response) {
    return jsonDecode(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> parseJson(String text) {
    return compute(_parseAndDecode, text);
  }

  /// v0.29: DELETE /api/v1/{name=memos/*}
  Future<Result<void>> deleteMemo(String name) async {
    try {
      await dio.delete("/api/v1/$name");
      return Result.ok(null);
    } on DioException catch (e) {
      return Result.error(e);
    }
  }

  /// v0.29: DELETE /api/v1/{name=memos/*}
  Future<void> deleteMemoDirect(String name) async {
    await dio.delete("/api/v1/$name");
  }

  /// v0.29: PATCH /api/v1/{memo.name=memos/*} (body uses "memo" wrapper)
  Future<Result<Memo>> updateMemo(
    String name,
    UpdateMemoRequest request,
  ) async {
    try {
      final res = await dio.patch(
        "/api/v1/$name",
        data: jsonEncode({"memo": request.toJson()}),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );
      return Result.ok(Memo.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Result.error(e);
    }
  }

  /// v0.29: GET /api/v1/{name=users/*}
  Future<UserProfile> getUser(String id) async {
    final res = await dio.get("/api/v1/users/$id");
    return UserProfile.fromJson(res.data as Map<String, dynamic>);
  }

  String getId(String name) {
    return name.contains("/") ? name.split("/").last : name;
  }
}
