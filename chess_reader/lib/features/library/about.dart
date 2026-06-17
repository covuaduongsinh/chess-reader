import 'package:flutter/material.dart';

/// App version shown in the About box. Keep in sync with pubspec `version`.
const String kAppVersion = '1.5.0';

/// Shows the About dialog: what the app does, its license, and author.
/// The dialog's built-in "View licenses" button lists all bundled
/// open-source license texts.
void showAppAboutDialog(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'Chess Reader',
    applicationVersion: kAppVersion,
    applicationIcon: const Icon(Icons.menu_book, size: 40),
    applicationLegalese:
        'Made by Vu-Hung Quan\nLicensed under the GNU GPL v3.0',
    children: const [
      SizedBox(height: 12),
      Text(
        'An offline interactive chess book reader.\n\n'
        '• Opens PDF and EPUB chess books.\n'
        '• Click any move in the text to follow it on the board.\n'
        '• Analyse any position with the built-in Stockfish engine.\n'
        '• Automatically detects printed diagrams and reads them into '
        'positions you can load with one tap.\n'
        '• Converts books to a reflowed reading view and can export them as '
        'standalone HTML.\n\n'
        'Everything runs locally — no internet connection or server is '
        'required.\n\n'
        'This program is free software, distributed under the GNU General '
        'Public License v3.0. It bundles Stockfish and the lichess '
        'chessground/dartchess libraries (also GPL/open source).',
      ),
    ],
  );
}
