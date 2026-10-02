/// The storage buckets an application may address.
///
/// Buckets are declared here, not in the consuming application, so the bucket
/// layout is part of the SDK's reviewed surface rather than a string that
/// silently reaches the network. A provider maps each value onto its own
/// bucket identifier.
///
/// Whether a bucket is public or private is a **database and infrastructure**
/// decision, enforced by storage policies in the Supabase project - see
/// `supabase/migrations`. The enum itself grants no access: it is a typed name
/// for a bucket, nothing more. Private buckets must always be read through
/// `createSignedUrl`.
enum StorageBucket {
  /// General-purpose bucket for miscellaneous user content.
  general,

  /// Private bucket for user profile images. Requires a signed URL.
  avatars,

  /// Private bucket for product media. Requires a signed URL.
  products,

  /// Private bucket for user documents. Requires a signed URL.
  documents;

  /// The stable, provider-independent key of this bucket.
  String get key => name;
}

/// A single file in a bucket, as returned by a listing.
class StorageFileEntry {
  /// The path of the file inside its bucket.
  final String path;

  /// The bucket the file lives in.
  final StorageBucket bucket;

  /// The size of the file in bytes, when the provider reports it.
  final int? sizeInBytes;

  /// The MIME content type, when the provider reports it.
  final String? contentType;

  /// When the file was last modified.
  final DateTime? updatedAt;

  /// Creates a storage file entry.
  const StorageFileEntry({
    required this.path,
    required this.bucket,
    this.sizeInBytes,
    this.contentType,
    this.updatedAt,
  });

  @override
  String toString() => 'StorageFileEntry(bucket: ${bucket.key}, path: $path)';
}
