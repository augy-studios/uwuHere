// The site's own icons (main-site/js/icons.js), as the same SVG paths: no emoji, no icon font.
// viewBox 0 0 24 24, stroked in the colour of the words around them. The names are the site's;
// the few the apps add (help, bug, the desktop's window buttons) follow them.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _paths = <String, String>{
  // ---- main-site/js/icons.js ----
  'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/>',
  'moon': '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
  'close': '<path d="M18 6 6 18M6 6l12 12"/>',
  'clock': '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/>',
  'play': '<path d="M5.25 4.5v15l12-7.5z"/>',
  'pause': '<path d="M9 4v16M15 4v16"/>',
  'reset': '<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/>',
  'edit': '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
  'scripts': '<path d="M4 6h16M4 12h16M4 18h10"/>',
  'settings': '<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/>',
  'remote': '<rect x="7" y="2" width="10" height="20" rx="3"/><path d="M12 6v.01M10 10h4M10 14h4M12 18v.01"/>',
  'fullscreen': '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>',
  'exitFullscreen': '<path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5"/>',
  'flipX': '<path d="M12 3v18"/><path d="M8 7 3 12l5 5z"/><path d="M16 7l5 5-5 5z"/>',
  'flipY': '<path d="M3 12h18"/><path d="M7 8 12 3l5 5z"/><path d="M7 16l5 5 5-5z"/>',
  'focus': '<path d="M2 12h20"/><path d="M6 9l3 3-3 3M18 9l-3 3 3 3"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'minus': '<path d="M5 12h14"/>',
  'chevronsLeft': '<path d="M11 17l-5-5 5-5M18 17l-5-5 5-5"/>',
  'chevronsRight': '<path d="M13 17l5-5-5-5M6 17l5-5-5-5"/>',
  'trash': '<path d="M4 7h16M10 11v6M14 11v6"/><path d="M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13"/><path d="M9 7V4h6v3"/>',
  'copy': '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/>',
  'check': '<path d="M20 6 9 17l-5-5"/>',
  'up': '<path d="M12 19V5M5 12l7-7 7 7"/>',
  'down': '<path d="M12 5v14M19 12l-7 7-7-7"/>',
  'chevronRight': '<path d="M9 6l6 6-6 6"/>',
  'download': '<path d="M12 4v11M7 10l5 5 5-5"/><path d="M4 20h16"/>',
  'appUpdate': '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v8M8.5 12l3.5 3.5 3.5-3.5"/>',
  'brightness': '<rect x="8" y="4" width="8" height="16" rx="2"/><path d="M3 12h2M19 12h2M4.6 6.6l1.6 1.2M19.4 6.6l-1.6 1.2M4.6 17.4l1.6-1.2M19.4 17.4l-1.6-1.2"/>',
  'bell': '<path d="M6 15.25v-5a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 19.75h4"/>',
  'pin': '<path d="M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z"/><circle cx="12" cy="9" r="2.5"/>',
  'pushpin': '<path d="M8 3h8"/><path d="M9.5 3v6.5L7 13h10l-2.5-3.5V3"/><path d="M12 13v8"/>',
  'keyboard': '<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8"/>',
  'nearby': '<rect x="9.5" y="6" width="5" height="12" rx="1.2"/><path d="M6.5 9.5a3.5 3.5 0 0 0 0 5M17.5 9.5a3.5 3.5 0 0 1 0 5M4 7a7 7 0 0 0 0 10M20 7a7 7 0 0 1 0 10"/>',
  // ---- uwuHere's (main-site/js/icons.js) ----
  'home': '<path d="M3 11l9-7 9 7"/><path d="M5 10v10h5v-6h4v6h5V10"/>',
  'stop': '<rect x="6" y="6" width="12" height="12" rx="2"/>',
  'tap': '<rect x="4" y="3" width="10" height="18" rx="2"/><path d="M17.5 9a4.5 4.5 0 0 1 0 6M20.5 6.5a8 8 0 0 1 0 11"/>',
  'bluetooth': '<path d="m7 7 10 10-5 5V2l5 5L7 17"/>',
  'hotspot': '<rect x="8" y="10" width="8" height="12" rx="1.5"/><path d="M12 19h.01"/><path d="M8.5 6.5a5 5 0 0 1 7 0M5.5 3.5a9 9 0 0 1 13 0"/>',
  'wifi': '<path d="M2 8.8a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/><path d="M12 19.5v.01"/>',
  'users': '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18.5 14a6.5 6.5 0 0 1 3 6"/>',
  'hand': '<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V11"/><path d="M11 10V4.5a1.5 1.5 0 0 1 3 0V11"/><path d="M14 10.5V6a1.5 1.5 0 0 1 3 0v8a7 7 0 0 1-7 7h-.5a6 6 0 0 1-4.6-2.2L2.6 15.6a1.5 1.5 0 0 1 2.3-1.9L8 16"/>',
  'door': '<path d="M14 4H6v16h8"/><path d="M14 4l5 1.5v13L14 20z"/><path d="M11 12h.01"/>',
  'qr': '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v.01M14 20h.01M17 17h4v4h-4"/>',
  'alert': '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17v.01"/>',
  'shield': '<path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.2 7.5 9.5 4.3-1.3 7.5-4.9 7.5-9.5V6z"/>',
  // ---- the apps' own (and the site's tours and bug report) ----
  'help': '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6"/><path d="M12 17.2v.1"/>',
  'bug': '<path d="m8 2 1.9 1.9M16 2l-1.9 1.9"/><path d="M9 7.1V6a3 3 0 1 1 6 0v1.1"/><path d="M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6z"/><path d="M12 20v-9M6.5 13H2M22 13h-4.5M6 9.5 3 8M18 9.5 21 8M6 17l-3 1.5M18 17l3 1.5"/>',
  'send': '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7z"/>',
  'image': '<rect x="3" y="3" width="18" height="18" rx="2.5"/><circle cx="9" cy="9" r="2"/><path d="m21 15-4.5-4.5L6 21"/>',
  'screenshot': '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><circle cx="12" cy="12" r="3"/>',
  'screenshot-long': '<path d="M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M12 7v10M9 14l3 3 3-3"/>',
  'link': '<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"/>',
  'search': '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.8-3.8"/>',
  'sidebar': '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16"/>',
  'power': '<path d="M12 3v8"/><path d="M6.6 6.6a7.5 7.5 0 1 0 10.8 0"/>',
  'refresh': '<path d="M20 11a8 8 0 1 0-2.3 6.3"/><path d="M20 4v7h-7"/>',
  'chevron-left': '<path d="m15 5-7 7 7 7"/>',
  'chevron-right': '<path d="m9 5 7 7-7 7"/>',
  'chevron-down': '<path d="m5 9 7 7 7-7"/>',
  'chevron-up': '<path d="m5 15 7-7 7 7"/>',
  'arrow-right': '<path d="M5 12h14M13 6l6 6-6 6"/>',
  'arrow-left': '<path d="M19 12H5M11 6l-6 6 6 6"/>',
  'minimise': '<path d="M5 12h14"/>',
  'maximise': '<rect x="5" y="5" width="14" height="14" rx="1"/>',
  'restore': '<rect x="4.5" y="8" width="11.5" height="11.5" rx="1"/><path d="M8 8V4.5h11.5V16H16"/>',
  'widget': '<rect x="3" y="3" width="8" height="8" rx="2"/><rect x="13" y="3" width="8" height="5" rx="2"/><rect x="13" y="10" width="8" height="11" rx="2"/><rect x="3" y="13" width="8" height="8" rx="2"/>',
  'phone':
      '<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/>',
  'monitor': '<rect x="2.5" y="3.5" width="19" height="13" rx="2"/><path d="M8 21h8M12 16.5V21"/>',
  'globe': '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  'star': '<path d="M12 3l2.6 5.3 5.9.9-4.3 4.2 1 5.9L12 16.5l-5.2 2.8 1-5.9L3.5 9.2l5.9-.9z" fill="currentColor"/>',
  'lock': '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7.5a4 4 0 0 1 8 0V11"/>',
  'watch': '<rect x="6" y="6" width="12" height="12" rx="3"/><path d="M9 6l1-3h4l1 3M9 18l1 3h4l1-3"/>',
  'palette': '<path d="M12 3a9 9 0 1 0 0 18c1.5 0 2-1 2-2s-.6-1.6-.6-2.5c0-1 .8-1.5 1.8-1.5H17a4 4 0 0 0 4-4c0-4.4-4-8-9-8z"/><circle cx="7.5" cy="11.5" r="1" fill="currentColor"/><circle cx="10" cy="7.5" r="1" fill="currentColor"/><circle cx="15" cy="7.5" r="1" fill="currentColor"/>',
};

/// The stroke width each icon is drawn with where it isn't the site's usual 1.8.
const _strokes = <String, double>{'chevronRight': 2};

/// Whether there's an icon of that name.
bool hasIcon(String name) => _paths.containsKey(name);

/// The SVG of one icon, in a colour: for places that need the picture itself (the tray icon). An
/// unknown name draws nothing, so in a debug build it says so instead (test/logic_test.dart also
/// checks every name the app asks for).
String iconSvg(String name, {String colour = '#000000', double? stroke}) {
  assert(hasIcon(name), 'No icon called "$name" in lib/theme/icons.dart');
  return _svg(name, colour, stroke);
}

String _svg(String name, String colour, double? stroke) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="$colour" stroke-width="${stroke ?? _strokes[name] ?? 1.8}" '
    'stroke-linecap="round" stroke-linejoin="round">${(_paths[name] ?? '').replaceAll('currentColor', colour)}</svg>';

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color,
    this.stroke,
  });

  final String name;
  final double size;
  final Color? color;
  final double? stroke;

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        Colors.black;
    final hex =
        '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    return Opacity(
      opacity: c.a,
      child: SvgPicture.string(
        iconSvg(name, colour: hex, stroke: stroke),
        width: size,
        height: size,
        excludeFromSemantics: true,
      ),
    );
  }
}
