import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../reader/data/epub_book.dart';

/// Target width of a generated cover thumbnail, in pixels.
const int _coverWidth = 240;

/// Returns a cached cover-thumbnail PNG for the book at [path], generating it on
/// first use (PDF: page 1 raster; EPUB: the OPF cover image). Returns null when
/// no cover can be produced — callers fall back to a generic format icon.
Future<File?> bookCoverThumbnail(String path) async {
  try {
    final file = await _coverFile(path);
    if (file.existsSync() && file.lengthSync() > 0) return file;
    final png = path.toLowerCase().endsWith('.epub')
        ? await _epubCoverPng(path)
        : await _pdfCoverPng(path);
    if (png == null) return null;
    await file.writeAsBytes(png);
    return file;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _pdfCoverPng(String path) async {
  final doc = await PdfDocument.openFile(path);
  try {
    if (doc.pages.isEmpty) return null;
    final page = doc.pages.first;
    final scale = _coverWidth / page.width;
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (image == null) return null;
    final im = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.pixels.buffer,
      order: img.ChannelOrder.bgra,
    );
    image.dispose();
    return img.encodePng(im);
  } finally {
    doc.dispose();
  }
}

Future<Uint8List?> _epubCoverPng(String path) async {
  final bytes = await epubCoverImage(path);
  if (bytes == null) return null;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = decoded.width > _coverWidth
      ? img.copyResize(decoded, width: _coverWidth)
      : decoded;
  return img.encodePng(resized);
}

/// Cache file for a book's cover, keyed by name+size+mtime so it invalidates
/// when the source file changes (mirrors book_conversion's cache key).
Future<File> _coverFile(String path) async {
  final dir = await getApplicationSupportDirectory();
  final coversDir = Directory(p.join(dir.path, 'covers'));
  if (!coversDir.existsSync()) coversDir.createSync(recursive: true);
  final stat = File(path).statSync();
  final base = p
      .basenameWithoutExtension(path)
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final key =
      '${base}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_${path.length}';
  return File(p.join(coversDir.path, '$key.png'));
}

/// Small circular action button overlaid on a cover's corner (remove / delete).
class CoverOverlayButton extends StatelessWidget {
  const CoverOverlayButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          tooltip: tooltip,
          color: Colors.white,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// A bookshelf tile: the extracted cover (or a generic icon while loading / when
/// none exists) with the title underneath. Caches the cover future so grid
/// rebuilds don't re-hit the disk. [trailing] overlays the cover's top-right
/// corner (e.g. a remove/delete action).
class BookCoverTile extends StatefulWidget {
  const BookCoverTile({
    super.key,
    required this.path,
    required this.title,
    required this.isEpub,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });

  final String path;
  final String title;
  final bool isEpub;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? trailing;

  @override
  State<BookCoverTile> createState() => _BookCoverTileState();
}

class _BookCoverTileState extends State<BookCoverTile> {
  late final Future<File?> _cover = bookCoverThumbnail(widget.path);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Center(
      child: Icon(
        widget.isEpub ? Icons.menu_book : Icons.picture_as_pdf,
        size: 40,
        color: theme.colorScheme.outline,
      ),
    );

    return Opacity(
      opacity: widget.enabled ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: widget.enabled ? widget.onTap : null,
                    child: FutureBuilder<File?>(
                      future: _cover,
                      builder: (context, snap) {
                        final file = snap.data;
                        if (file != null) {
                          return Image.file(file,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => fallback);
                        }
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return fallback;
                      },
                    ),
                  ),
                ),
                if (widget.trailing != null)
                  Positioned(top: 0, right: 0, child: widget.trailing!),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
