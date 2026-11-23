// The check-in page (main-site/join.html, js/join.js): the code box when there's no code, a
// message for an event that isn't there or has ended, or the big button with the name above it
// and "I'm leaving early" under it.
import 'package:flutter/material.dart';

import '../../app/pages.dart';
import '../../data/codes.dart';
import '../../data/format.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/edge_tray.dart';
import '../../widgets/here_button.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/sheet.dart';
import '../tour/tour.dart';
import 'join_controller.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() {
    return _JoinScreenState();
  }
}

class _JoinScreenState extends State<JoinScreen> {
  JoinController? _controller;
  final _nameFocus = FocusNode();
  final _codeField = TextEditingController();
  String _codeError = '';

  @override
  void initState() {
    super.initState();
    AppPages.joinOpened.addListener(_onPageOpened);
    AppPages.current.addListener(_showPageActions);
    AppPages.refreshers[AppPages.join] = () async {
      final controller = _controller;
      if (controller != null) {
        await controller.load();
      }
    };
    _onPageOpened();
  }

  @override
  void dispose() {
    AppPages.joinOpened.removeListener(_onPageOpened);
    AppPages.current.removeListener(_showPageActions);
    _disposeController();
    _nameFocus.dispose();
    _codeField.dispose();
    super.dispose();
  }

  /// Stops listening to the current controller, if there is one, and disposes it.
  void _disposeController() {
    final controller = _controller;
    if (controller != null) {
      controller.focusName.removeListener(_focusNameField);
      controller.dispose();
    }
  }

  void _focusNameField() {
    _nameFocus.requestFocus();
  }

  /// The page opened by a link or the code box: the same event takes a new tap; another event
  /// starts again.
  void _onPageOpened() {
    final joinCode = AppPages.joinCode.value;
    String code = '';
    if (joinCode != null) {
      code = joinCode;
    }
    final tap = AppPages.joinTap;
    AppPages.joinTap = null;
    if (_controller != null && _controller!.code == code) {
      if (tap != null) _controller!.takeTap(tap);
      return;
    }
    _disposeController();
    final controller = JoinController(code, tapToken: tap);
    controller.focusName.addListener(_focusNameField);
    _controller = controller;
    controller.boot();
    if (mounted) setState(() {});
    _showPageActions();
  }

  /// While this page is on screen, the Edge Tray's only action is Home.
  void _showPageActions() {
    if (AppPages.active() != AppPages.join) return;
    if (PageActions.items.value.length == 1 && PageActions.items.value.first.label == 'Home') return;
    PageActions.items.value = [
      TrayItem(
        icon: 'home',
        label: 'Home',
        onTap: () {
          AppPages.open(AppPages.home);
        },
      ),
    ];
  }

  void _submitCode() {
    final typed = normaliseCode(_codeField.text);
    if (!isValidCode(typed)) {
      setState(() {
        _codeError = badCodeMessage;
      });
      return;
    }
    _codeField.clear();
    AppPages.openJoin(typed);
  }

  /// One of the controller's views: loading, the code box, a message, or the check-in view.
  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.view) {
          case 'loading':
            return PageFrame(
              page: AppPages.join,
              children: [SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))],
            );
          case 'code':
            return PageFrame(page: AppPages.join, children: [_codeCard(context)]);
          case 'message':
            return PageFrame(
              page: AppPages.join,
              children: [
                Card2(
                  title: controller.messageTitle,
                  big: true,
                  children: [
                    Text(controller.messageText),
                    if (controller.messageAction != null) ...[
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: () {
                          if (controller.messageAction == 'reload') {
                            controller.load();
                          } else {
                            AppPages.openJoin(null);
                          }
                        },
                        child: IconLabel('refresh', _messageActionLabel(controller)),
                      ),
                    ],
                  ],
                ),
              ],
            );
        }
        return _checkInView(context, controller);
      },
    );
  }

  /// The words on the message's button.
  String _messageActionLabel(JoinController controller) {
    if (controller.messageAction == 'reload') {
      return 'Try again';
    }
    return 'Try another code';
  }

  /// The box for typing an event's code, shown when the page has none.
  Widget _codeCard(BuildContext context) {
    final colors = UwuColors.of(context);
    return Card2(
      title: 'Enter the event code',
      big: true,
      children: [
        Text("It is on the host's screen, under the QR code.", style: TextStyle(color: colors.muted)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Named(
                'Event code',
                child: TextField(
                  controller: _codeField,
                  maxLength: 7,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, letterSpacing: 4, color: colors.ink, fontFamily: 'Jua'),
                  decoration: const InputDecoration(hintText: 'CODE', counterText: ''),
                  onChanged: (typed) {
                    final upperCase = typed.toUpperCase();
                    if (upperCase != typed) _codeField.value = _codeField.value.copyWith(text: upperCase);
                    if (_codeError.isNotEmpty) {
                      setState(() {
                        _codeError = '';
                      });
                    }
                  },
                  onSubmitted: (_) {
                    _submitCode();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _submitCode, child: const Text('Join')),
          ],
        ),
        if (_codeError.isNotEmpty) ...[const SizedBox(height: 8), Banner2(_codeError, tone: 'error')],
      ],
    );
  }

  /// The check-in view: the event's name and code, the name (and note) boxes until checked in,
  /// the big button, the status line, "I'm leaving early", and which ways the event checks by.
  Widget _checkInView(BuildContext context, JoinController controller) {
    final colors = UwuColors.of(context);
    final event = controller.event!;
    final checkedIn = controller.checkedIn;
    final attendance = controller.attendance;
    bool held = false;
    String? leftAt;
    String attendeeName = '';
    if (attendance != null) {
      held = attendance['held'] == true;
      leftAt = attendance['leftEarlyAt'] as String?;
      if (attendance['name'] != null) {
        attendeeName = '${attendance['name']}';
      }
    }
    String title = '';
    if (event['title'] != null) {
      title = '${event['title']}';
    }
    final noteLabel = controller.noteLabel;
    final width = MediaQuery.sizeOf(context).width;

    String heading = title;
    if (title.isEmpty) {
      heading = 'Check in';
    }
    String eventCode = controller.code;
    if (event['code'] != null) {
      eventCode = '${event['code']}';
    }
    String buttonColour = '#ccffcc';
    if (event['buttonColor'] != null) {
      buttonColour = '${event['buttonColor']}';
    }
    String buttonLabel = "I'm here";
    if (event['buttonLabel'] != null) {
      buttonLabel = '${event['buttonLabel']}';
    }
    // The button takes most of a narrow screen, and at most 280 pixels.
    double buttonSize = 280;
    if (width * 0.72 < 280) {
      buttonSize = width * 0.72;
    }
    // Under the button once checked in: when, and whether the tap is still waiting to be sent.
    String? buttonSubtitle;
    if (checkedIn) {
      if (held) {
        buttonSubtitle = 'Tapped at ${formatTime(attendance!['checkedInAt'] as String?)}, not sent yet';
      } else {
        buttonSubtitle = 'Checked in at ${formatTime(attendance!['checkedInAt'] as String?)}';
      }
    }
    String checkedInBanner;
    if (held) {
      checkedInBanner = "Tapped as $attendeeName. It's sent as soon as this phone is back online.";
    } else {
      checkedInBanner = 'Checked in as $attendeeName.';
    }
    Color statusColour;
    if (controller.tone == 'error') {
      statusColour = colors.error;
    } else if (controller.tone == 'ok') {
      statusColour = colors.ok;
    } else {
      statusColour = colors.muted;
    }
    // "I'm leaving early" works once, after a check-in that has been sent.
    VoidCallback? onLeave;
    if (checkedIn && !held && leftAt == null && !controller.busy) {
      onLeave = () {
        _openLeaveSheet(context, controller);
      };
    }
    String leaveLabel = "I'm leaving early";
    if (leftAt != null) {
      leaveLabel = 'Left at ${formatTime(leftAt)}';
    }

    return PageFrame(
      page: AppPages.join,
      children: [
        Column(
          children: [
            Semantics(
              header: true,
              child: Text(
                heading,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, color: colors.ink, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            Text('Event $eventCode', style: TextStyle(color: colors.muted, letterSpacing: 1)),
          ],
        ),
        if (!checkedIn)
          KeyedSubtree(
            key: TourTargets.key('join-name'),
            child: GlassPanel(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldHead('Your name'),
                  Named(
                    'Your name',
                    child: TextField(
                      key: const ValueKey('join-name'),
                      controller: controller.nameField,
                      focusNode: _nameFocus,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(counterText: ''),
                    ),
                  ),
                  if (noteLabel != null) ...[
                    const SizedBox(height: 12),
                    FieldHead(noteLabel),
                    Named(
                      noteLabel,
                      child: TextField(
                        controller: controller.noteField,
                        maxLength: 120,
                        decoration: const InputDecoration(counterText: ''),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (checkedIn && attendeeName.isNotEmpty) Banner2(checkedInBanner),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: KeyedSubtree(
              key: TourTargets.key('here-btn'),
              child: HereButton(
                key: const ValueKey('here-btn'),
                colour: buttonColour,
                label: buttonLabel,
                size: buttonSize,
                done: checkedIn,
                busy: controller.busy,
                paused: controller.paused,
                sub: buttonSubtitle,
                onPressed: controller.checkIn,
              ),
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Text(
              controller.status,
              key: const ValueKey('here-status'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: statusColour),
            ),
          ),
        ),
        Center(
          child: KeyedSubtree(
            key: TourTargets.key('leave-btn'),
            child: OutlinedButton(
              onPressed: onLeave,
              child: IconLabel('door', leaveLabel),
            ),
          ),
        ),
        if (controller.methodNote.isNotEmpty)
          Text(
            controller.methodNote,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted, fontSize: 13, height: 1.4),
          ),
      ],
    );
  }

  Future<void> _openLeaveSheet(BuildContext context, JoinController controller) {
    return AppSheet.show(
      context,
      id: 'leave',
      width: 420,
      builder: (context) {
        return _LeaveSheet(controller: controller);
      },
    );
  }
}

/// "Leaving early?": asks before telling the host, since it can only be done once.
class _LeaveSheet extends StatefulWidget {
  const _LeaveSheet({required this.controller});
  final JoinController controller;

  @override
  State<_LeaveSheet> createState() {
    return _LeaveSheetState();
  }
}

class _LeaveSheetState extends State<_LeaveSheet> {
  String _error = '';
  bool _busy = false;

  /// Tells the host this attendee is leaving; closes the sheet when done, else shows why not.
  Future<void> _leave() async {
    setState(() {
      _busy = true;
    });
    final leaveError = await widget.controller.leave();
    if (!context.mounted) return;
    setState(() {
      _busy = false;
    });
    if (leaveError == null || leaveError.isEmpty) {
      AppSheet.close(context);
      return;
    }
    setState(() {
      _error = leaveError;
    });
  }

  @override
  Widget build(BuildContext context) {
    VoidCallback? onLeave;
    if (!_busy) {
      onLeave = _leave;
    }
    return SheetFrame(
      title: 'Leaving early?',
      footer: [
        OutlinedButton(
          onPressed: () {
            AppSheet.close(context);
          },
          child: const Text('Stay'),
        ),
        FilledButton(
          onPressed: onLeave,
          child: const IconLabel('door', "I'm leaving"),
        ),
      ],
      children: [
        const Text('The host sees the time you left. This can only be done once.'),
        if (_error.isNotEmpty) ...[const SizedBox(height: 10), Banner2(_error, tone: 'error')],
      ],
    );
  }
}
