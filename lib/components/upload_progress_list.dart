import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/keyboard_input.dart';
import 'package:brookie_babies/utilities/upload_queue.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';

/// How an [UploadQueue] is going, for both admin upload pages: one summary
/// line ("Uploading 37 of 150 · 2 failed · 4 skipped"), the photos uploading
/// now, which failed or were skipped and why, and "Retry failed" and "Cancel
/// uploads".
///
/// Only the summary is a live region, so a screen reader hears one short
/// line as each photo finishes, not every progress bar. Queued and finished
/// photos aren't listed one by one: a folder can hold hundreds. Shows
/// nothing for an empty queue.
///
/// "Retry failed" and "Cancel uploads" go once they've done their work, so
/// the focused one hands keyboard focus on rather than dropping it: to the
/// other button if it's there, else to [focusWhenDone], else to the summary.
class UploadProgressList extends StatefulWidget {
  const UploadProgressList({super.key, required this.queue, this.focusWhenDone});

  final UploadQueue queue;

  /// Where focus goes when the focused button goes and the other isn't
  /// there either, such as the page's upload button.
  final FocusNode? focusWhenDone;

  @override
  State<UploadProgressList> createState() => _UploadProgressListState();
}

class _UploadProgressListState extends State<UploadProgressList> {
  final _retryFocus = FocusNode(debugLabel: 'Retry failed');
  final _cancelFocus = FocusNode(debugLabel: 'Cancel uploads');
  // Holds focus only when handed it: Tab never stops on the summary.
  final _summaryFocus = FocusNode(debugLabel: 'Upload summary', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    KeyboardInput.listen();
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    _cancelFocus.dispose();
    _summaryFocus.dispose();
    super.dispose();
  }

  /// Hands focus on, once the next frame has built the buttons, if a
  /// focused button isn't shown any more.
  void _keepFocus({required bool retry, required bool cancel}) {
    final losing = !retry && _retryFocus.hasFocus || !cancel && _cancelFocus.hasFocus;
    if (!losing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = cancel
          ? _cancelFocus
          : retry
              ? _retryFocus
              : widget.focusWhenDone ?? ((_summaryFocus.context?.mounted ?? false) ? _summaryFocus : null);
      target?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    return ListenableBuilder(
      listenable: queue,
      builder: (context, child) {
        final retry = queue.canRetry;
        final cancel = queue.isBusy;
        _keepFocus(retry: retry, cancel: cancel);
        if (queue.items.isEmpty) return const SizedBox.shrink();
        final uploading = [
          for (final item in queue.items)
            if (item.status == UploadStatus.uploading) item,
        ];
        final failed = [
          for (final item in queue.items)
            if (item.status == UploadStatus.failed) item,
        ];
        final skipped = [
          for (final item in queue.items)
            if (item.status == UploadStatus.skipped) item,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              focusNode: _summaryFocus,
              includeSemantics: false,
              child: ListenableBuilder(
                listenable: Listenable.merge([_summaryFocus, KeyboardInput.changes]),
                builder: (context, child) => FocusRing(
                  visible: _summaryFocus.hasFocus && KeyboardInput.lastWasKey,
                  child: child!,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(uploadSummary(queue), style: Theme.of(context).textTheme.titleSmall),
                ),
              ),
            ),
            for (final item in uploading) ...[
              const SizedBox(height: BrookieSpace.s3),
              _Uploading(item: item),
            ],
            if (failed.isNotEmpty) ...[
              const SizedBox(height: BrookieSpace.s3),
              // Open from the start: each says how to fix it.
              _Details(
                key: const ValueKey(UploadStatus.failed),
                label: '${failed.length} failed',
                items: failed,
                initiallyOpen: true,
              ),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: BrookieSpace.s3),
              _Details(
                key: const ValueKey(UploadStatus.skipped),
                label: '${skipped.length} skipped',
                items: skipped,
                initiallyOpen: false,
              ),
            ],
            if (retry || cancel) ...[
              const SizedBox(height: BrookieSpace.s4),
              Wrap(
                spacing: BrookieSpace.s3,
                runSpacing: BrookieSpace.s3,
                children: [
                  if (retry)
                    OutlinedButton(
                      focusNode: _retryFocus,
                      onPressed: queue.retryFailed,
                      child: const Text('Retry failed'),
                    ),
                  if (cancel)
                    TextButton(
                      focusNode: _cancelFocus,
                      onPressed: queue.cancelAll,
                      child: const Text('Cancel uploads'),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The summary line for [queue]: "Uploading 37 of 150 · 2 failed · 4
/// skipped" while it works, "Uploaded 150 photos" or "Uploaded 148 of 150 ·
/// 2 failed" once it's done. Skipped photos aren't counted as ones to
/// upload.
String uploadSummary(UploadQueue queue) {
  final done = queue.countOf(UploadStatus.done);
  final failed = queue.countOf(UploadStatus.failed);
  final cancelled = queue.countOf(UploadStatus.cancelled);
  final skipped = queue.countOf(UploadStatus.skipped);
  final total = queue.items.length - skipped;
  return [
    if (queue.isBusy)
      'Uploading $done of $total'
    else if (total == 0)
      'Nothing new to upload'
    else if (done == total)
      'Uploaded $done ${done == 1 ? 'photo' : 'photos'}'
    else
      'Uploaded $done of $total',
    if (failed > 0) '$failed failed',
    if (cancelled > 0) '$cancelled cancelled',
    if (skipped > 0) '$skipped skipped',
  ].join(' · ');
}

/// A photo on its way: its name and how much has been sent.
class _Uploading extends StatelessWidget {
  const _Uploading({required this.item});

  final UploadItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: BrookieSpace.s1),
        LinearProgressIndicator(
          value: item.progress,
          minHeight: BrookieSpace.s1,
          borderRadius: BorderRadius.circular(BrookieSpace.s1 / 2),
          semanticsLabel: item.name,
          semanticsValue: '${(item.progress * 100).round()}%',
        ),
      ],
    );
  }
}

/// "2 failed" or "4 skipped", opening into each photo's name and the
/// reason.
class _Details extends StatefulWidget {
  const _Details({super.key, required this.label, required this.items, required this.initiallyOpen});

  final String label;
  final List<UploadItem> items;
  final bool initiallyOpen;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One node: "2 failed", a button, expanded or collapsed.
        MergeSemantics(
          child: Semantics(
            expanded: _open,
            child: TextButton.icon(
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
              label: Text(widget.label),
            ),
          ),
        ),
        if (_open)
          for (final item in widget.items)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(BrookieSpace.s3, BrookieSpace.s2, 0, 0),
              // One node per photo: its name, then why.
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.name, style: Theme.of(context).textTheme.titleSmall),
                    if (item.message case final message?)
                      Text(message, style: BrookieType.ui.copyWith(color: c.inkSoft)),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
