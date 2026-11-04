/// Identifies which site a gallery belongs to.
///
/// Acervo H&C was written for E-Hentai only. This enum lets the external
/// source (Xlecx) reuse the same models, database tables and reader without
/// touching the E-H code paths.
///
/// The source is encoded in [GalleryUrl.gid] itself instead of adding a column
/// to the database: E-Hentai gids are currently around 4.6M, so any gid at or
/// above [xlecxGidOffset] is unambiguously an external gallery.
enum GallerySource { eh, xlecx }

/// First gid handed out to Xlecx galleries.
const int xlecxGidOffset = 2100000000;

/// Encode a Xlecx gallery id as an Acervo H&C gid.
int xlecxGid(int externalId) => xlecxGidOffset + externalId;

/// Which source produced [gid].
GallerySource sourceOfGid(int? gid) {
  if (gid != null && gid >= xlecxGidOffset) {
    return GallerySource.xlecx;
  }
  return GallerySource.eh;
}
