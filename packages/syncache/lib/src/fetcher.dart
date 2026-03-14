/// Contains request metadata for fetch operations.
///
/// [SyncacheRequest] provides context to fetcher functions, including
/// conditional headers for HTTP caching (ETag, If-Modified-Since).
///
/// Example:
/// ```dart
/// Future<User> fetchUser(SyncacheRequest request) async {
///   final response = await http.get(
///     Uri.parse('https://api.example.com/user'),
///     headers: request.headers, // Includes conditional headers
///   );
///   return User.fromJson(jsonDecode(response.body));
/// }
/// ```
class SyncacheRequest {
  /// HTTP headers to include with the fetch request.
  ///
  /// May include conditional headers like `If-None-Match` (ETag) or
  /// `If-Modified-Since` when cached metadata is available.
  final Map<String, String> headers;

  /// Creates a [SyncacheRequest] with optional [headers].
  const SyncacheRequest({this.headers = const {}});
}

/// Result of a fetch operation that supports HTTP caching semantics.
///
/// Use [FetchResult.data] to return fresh data with optional caching headers.
/// Use [FetchResult.notModified] to signal that the cached data is still valid
/// (HTTP 304 Not Modified response).
///
/// ## Example with HTTP 304 handling
///
/// ```dart
/// Future<FetchResult<User>> fetchUser(SyncacheRequest request) async {
///   final response = await http.get(
///     Uri.parse('https://api.example.com/user/123'),
///     headers: request.headers,
///   );
///
///   if (response.statusCode == 304) {
///     // Server says cached data is still valid
///     return FetchResult.notModified();
///   }
///
///   if (response.statusCode == 200) {
///     return FetchResult.data(
///       User.fromJson(jsonDecode(response.body)),
///       etag: response.headers['etag'],
///       lastModified: parseHttpDate(response.headers['last-modified']),
///     );
///   }
///
///   throw Exception('Failed to fetch user');
/// }
/// ```
class FetchResult<T> {
  /// The fetched data, or null if not modified.
  final T? value;

  /// Whether the response was "not modified" (HTTP 304).
  final bool isNotModified;

  /// Optional ETag from the response for future conditional requests.
  final String? etag;

  /// Optional Last-Modified date from the response for future conditional requests.
  final DateTime? lastModified;

  const FetchResult._({
    this.value,
    this.isNotModified = false,
    this.etag,
    this.lastModified,
  });

  /// Creates a result with fresh data.
  ///
  /// Optionally include [etag] and [lastModified] from the response headers
  /// to enable conditional requests on subsequent fetches.
  const FetchResult.data(
    T value, {
    String? etag,
    DateTime? lastModified,
  }) : this._(
          value: value,
          isNotModified: false,
          etag: etag,
          lastModified: lastModified,
        );

  /// Creates a "not modified" result (HTTP 304).
  ///
  /// Use this when the server indicates the cached data is still valid.
  /// The cache will return the existing cached value.
  const FetchResult.notModified()
      : this._(
          value: null,
          isNotModified: true,
        );
}

/// A function that fetches data of type [T] from a remote source.
///
/// The fetcher receives a [SyncacheRequest] containing conditional headers
/// that can be used for HTTP caching. The fetcher should return the fetched
/// data, or throw an exception on failure.
///
/// Example:
/// ```dart
/// final Fetcher<User> fetchUser = (request) async {
///   final response = await http.get(
///     Uri.parse('https://api.example.com/user/123'),
///     headers: request.headers,
///   );
///   if (response.statusCode == 200) {
///     return User.fromJson(jsonDecode(response.body));
///   }
///   throw Exception('Failed to fetch user');
/// };
/// ```
typedef Fetcher<T> = Future<T> Function(SyncacheRequest request);

/// A fetcher that can return [FetchResult] to support HTTP 304 Not Modified.
///
/// Use this instead of [Fetcher] when you need to handle conditional
/// responses from the server.
///
/// Example:
/// ```dart
/// final ConditionalFetcher<User> fetchUser = (request) async {
///   final response = await http.get(
///     Uri.parse('https://api.example.com/user/123'),
///     headers: request.headers,
///   );
///   if (response.statusCode == 304) {
///     return FetchResult.notModified();
///   }
///   if (response.statusCode == 200) {
///     return FetchResult.data(
///       User.fromJson(jsonDecode(response.body)),
///       etag: response.headers['etag'],
///     );
///   }
///   throw Exception('Failed to fetch user');
/// };
/// ```
typedef ConditionalFetcher<T> = Future<FetchResult<T>> Function(
    SyncacheRequest request);
