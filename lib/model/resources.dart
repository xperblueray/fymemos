class MemoResource {
  final String name;
  final DateTime createTime;
  final String filename;
  final String type;
  final String size;
  final String? memo;

  /// Use the ApiClient's baseUrl for constructing image URLs.
  static String _serverBaseUrl = '';

  static void setServerBaseUrl(String url) {
    _serverBaseUrl = url.replaceAll(RegExp(r'/+$'), '');
  }

  String get imageUrl {
    return "$_serverBaseUrl/file/$name/$filename";
  }

  String get thumbnailUrl {
    return "$_serverBaseUrl/file/$name/$filename?thumbnail=true";
  }

  MemoResource({
    required this.name,
    required this.createTime,
    required this.filename,
    required this.type,
    required this.size,
    required this.memo,
  });

  factory MemoResource.fromJson(Map<String, dynamic> json) {
    return MemoResource(
      name: json['name'] as String,
      createTime: DateTime.parse(json['createTime'] as String),
      filename: json['filename'] as String,
      type: json['type'] as String,
      size: json['size']?.toString() ?? '',
      memo: json['memo'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'filename': filename,
      'type': type,
      'size': size,
      if (memo != null) 'memo': memo,
    };
  }
}

class MemoResourcesResponse {
  final List<MemoResource>? resources;

  MemoResourcesResponse({this.resources});

  factory MemoResourcesResponse.fromJson(Map<String, dynamic> json) {
    // v0.29: the key is 'attachments', older versions used 'resources'
    final List<MemoResource> resources =
        ((json['attachments'] as List?) ?? (json['resources'] as List?))
                ?.map((e) => MemoResource.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
    return MemoResourcesResponse(resources: resources);
  }
}
