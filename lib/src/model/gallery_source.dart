/// Identifies which site a gallery belongs to.
///
/// Acervo H&C was written for E-Hentai only. This enum lets a second, external
/// source (8muses) reuse the same models, database tables and reader without
/// touching the E-H code paths.
///
/// The source is encoded in [GalleryUrl.gid] itself instead of adding a column
/// to the database: E-Hentai gids are currently around 4.6M, so any gid at or
/// above [eightMusesGidOffset] is unambiguously an external gallery. That keeps
/// the drift schema (and every migration) untouched.
enum GallerySource { eh, eightMuses }

/// First gid handed out to external galleries.
const int eightMusesGidOffset = 2000000000;

/// Encode an 8muses gallery id as an Acervo H&C gid.
int eightMusesGid(int externalId) => eightMusesGidOffset + externalId;

/// Decode an 8muses gallery id from an Acervo H&C gid, or null for E-H galleries.
int? eightMusesExternalId(int? gid) {
  if (gid == null || gid < eightMusesGidOffset) {
    return null;
  }
  return gid - eightMusesGidOffset;
}

/// Which source produced [gid].
GallerySource sourceOfGid(int? gid) {
  if (gid != null && gid >= eightMusesGidOffset) {
    return GallerySource.eightMuses;
  }
  return GallerySource.eh;
}
