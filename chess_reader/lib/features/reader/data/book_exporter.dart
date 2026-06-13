import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'epub_book.dart';

/// Builds a self-contained, browser-viewable HTML document from the book's
/// chapters. The app-only `<chessmove>` / `<chessdiagram>` tags are lowered to
/// plain HTML: moves become highlighted spans, diagrams become a `<figure>`
/// with the (base64) board image and its FEN as a caption.
String buildExportHtml(String title, List<EpubChapter> chapters) {
  final body = StringBuffer();
  for (final chapter in chapters) {
    final doc = html_parser.parse(chapter.html);

    for (final move in doc.querySelectorAll('chessmove')) {
      final span = dom.Element.tag('span')
        ..className = 'move'
        ..append(dom.Text(move.text));
      _replace(move, span);
    }

    for (final diagram in doc.querySelectorAll('chessdiagram')) {
      final fen = diagram.attributes['fen'] ?? '';
      final figure = dom.Element.tag('figure')..className = 'diagram';
      final img = diagram.querySelector('img');
      if (img != null) {
        img.remove();
        figure.append(img);
      }
      figure.append(dom.Element.tag('figcaption')..append(dom.Text(fen)));
      _replace(diagram, figure);
    }

    body.write('<section><h2>${_escape(chapter.title)}</h2>');
    body.write(doc.body?.innerHtml ?? '');
    body.write('</section>');
  }

  return '<!DOCTYPE html>\n'
      '<html lang="en"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<title>${_escape(title)}</title>'
      '<style>$_css</style></head>'
      '<body><h1>${_escape(title)}</h1>$body</body></html>';
}

const _css = '''
body{font-family:Georgia,serif;line-height:1.5;max-width:46rem;margin:2rem auto;padding:0 1rem;color:#222}
h1{font-size:1.6rem}h2{font-size:1.2rem;margin-top:2rem;color:#555}
.move{color:#1565c0;font-weight:600}
figure.diagram{margin:1.5rem auto;text-align:center}
figure.diagram img{max-width:360px;width:100%;height:auto;border:1px solid #ccc}
figure.diagram figcaption{font-family:monospace;font-size:.8rem;color:#666;word-break:break-all;margin-top:.4rem}
''';

void _replace(dom.Element element, dom.Node replacement) {
  final parent = element.parentNode;
  if (parent == null) return;
  final i = parent.nodes.indexOf(element);
  parent.nodes.removeAt(i);
  parent.nodes.insert(i, replacement);
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
