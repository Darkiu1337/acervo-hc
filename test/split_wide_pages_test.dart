import 'package:acervo_hc/src/database/database.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/pages/details/details_page_logic.dart';
import 'package:acervo_hc/src/pages/read/spread_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Split wide pages helpers', () {
    test('showRightHalfFirst respects direction and reverseOrder', () {
      expect(showRightHalfFirst(isRightToLeftOrVertical: true, reverseOrder: false), isTrue);
      expect(showRightHalfFirst(isRightToLeftOrVertical: true, reverseOrder: true), isFalse);
      expect(showRightHalfFirst(isRightToLeftOrVertical: false, reverseOrder: false), isFalse);
      expect(showRightHalfFirst(isRightToLeftOrVertical: false, reverseOrder: true), isTrue);
    });

    test('isRightHalfForPart maps first and second halves properly', () {
      expect(isRightHalfForPart(ImagePart.first, rightHalfFirst: true), isTrue);
      expect(isRightHalfForPart(ImagePart.second, rightHalfFirst: true), isFalse);
      expect(isRightHalfForPart(ImagePart.first, rightHalfFirst: false), isFalse);
      expect(isRightHalfForPart(ImagePart.second, rightHalfFirst: false), isTrue);
    });

    test('PageParts expands split spreads into two pages and maps back cleanly', () {
      // 4 images where image 1 and image 3 are wide spreads -> 6 pages total.
      final PageParts parts = PageParts(<bool>[false, true, false, true]);

      expect(parts.imageCount, 4);
      expect(parts.pageCount, 6);

      expect(parts.imageOf(0), 0);
      expect(parts.partOf(0), ImagePart.whole);

      expect(parts.imageOf(1), 1);
      expect(parts.partOf(1), ImagePart.first);
      expect(parts.imageOf(2), 1);
      expect(parts.partOf(2), ImagePart.second);

      expect(parts.imageOf(3), 2);
      expect(parts.partOf(3), ImagePart.whole);

      expect(parts.imageOf(4), 3);
      expect(parts.partOf(4), ImagePart.first);
      expect(parts.imageOf(5), 3);
      expect(parts.partOf(5), ImagePart.second);

      expect(parts.firstPageOf(0), 0);
      expect(parts.secondPageOf(0), 0);
      expect(parts.firstPageOf(1), 1);
      expect(parts.secondPageOf(1), 2);
      expect(parts.firstPageOf(2), 3);
      expect(parts.firstPageOf(3), 4);
      expect(parts.secondPageOf(3), 5);
    });

    test('PageParts.unsplit keeps 1:1 mapping', () {
      final PageParts parts = PageParts.unsplit(3);
      expect(parts.pageCount, 3);
      for (int i = 0; i < 3; i++) {
        expect(parts.imageOf(i), i);
        expect(parts.partOf(i), ImagePart.whole);
        expect(parts.firstPageOf(i), i);
        expect(parts.secondPageOf(i), i);
      }
    });
  });

  group('DetailsPageLogic.formatSelectedTags', () {
    test('formats multiple tags with namespace quotes for search and copy', () {
      final List<GalleryTag> tags = <GalleryTag>[
        GalleryTag(tagData: const TagData(namespace: 'artist', key: 'nanohana')),
        GalleryTag(tagData: const TagData(namespace: 'female', key: 'big breasts')),
      ];

      expect(
        DetailsPageLogic.formatSelectedTags(tags, exactSuffix: true),
        'artist:"nanohana\$" female:"big breasts\$"',
      );
      expect(
        DetailsPageLogic.formatSelectedTags(tags, exactSuffix: false),
        'artist:"nanohana" female:"big breasts"',
      );
    });
  });
}
