import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../domain/receipt.dart';
import 'receipt_pdf.dart';
import 'receipts_providers.dart';

/// The receipt on screen beside its actions (FD-6): [title] and Print /
/// Save PDF on the right, then [actions]. Below 680px they stack.
class ReceiptPanel extends ConsumerWidget {
  const ReceiptPanel({
    super.key,
    required this.paymentId,
    this.title,
    this.actions = const [],
  });

  final String paymentId;
  final Widget? title;
  final List<Widget> actions;

  static const receiptWidth = 400.0;
  static const actionsWidth = 240.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(receiptProvider(paymentId));
    final Widget view = switch (receipt) {
      AsyncData(:final value) => ReceiptView(value),
      AsyncError(:final error) => Note.error(
        '$error',
        title: 'The receipt could not be loaded.',
      ),
      _ => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
    };
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[title!, const SizedBox(height: Space.x16)],
        ReceiptActions(paymentId: paymentId),
        for (final a in actions) ...[const SizedBox(height: Space.x12), a],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < receiptWidth + Space.x24 + actionsWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: receiptWidth, child: side),
              const SizedBox(height: Space.x16),
              SizedBox(width: receiptWidth, child: view),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: receiptWidth, child: view),
            const SizedBox(width: Space.x24),
            SizedBox(width: actionsWidth, child: side),
          ],
        );
      },
    );
  }
}

/// Print (main) and Save PDF. Each one, once done, counts the receipt as
/// printed (`payment.print`), so the next says COPY; a cancelled print
/// dialog counts nothing.
class ReceiptActions extends ConsumerStatefulWidget {
  const ReceiptActions({super.key, required this.paymentId});

  final String paymentId;

  @override
  ConsumerState<ReceiptActions> createState() => _ReceiptActionsState();
}

enum _Busy { print, save }

class _ReceiptActionsState extends ConsumerState<ReceiptActions> {
  _Busy? _busy;
  String? _savedPath;
  String? _error;

  Future<void> _run(_Busy what) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() {
      _busy = what;
      _error = null;
      if (what == _Busy.print) _savedPath = null;
    });
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final output = ref.read(receiptOutputProvider);
      final receipt = await repo.receipt(widget.paymentId);
      final fonts = await ref.read(receiptFontsProvider.future);
      final pdf = await buildReceiptPdf(receipt, fonts);
      switch (what) {
        case _Busy.print:
          final printed = await output.print(
            pdf,
            name: receiptFileName(receipt),
          );
          if (printed) await repo.markPrinted(user, widget.paymentId);
        case _Busy.save:
          final path = await output.save(
            pdf,
            folder: receiptFolderName(receipt.lodgingName),
            file: receiptFileName(receipt),
          );
          await repo.markPrinted(user, widget.paymentId);
          if (mounted) setState(() => _savedPath = path);
      }
    } on NotPermitted {
      if (mounted) setState(() => _error = 'You can’t print receipts.');
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = what == _Busy.print
              ? 'Could not print: $e'
              : 'Could not save the PDF: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final saved = _savedPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton.primary(
          key: const ValueKey('receipt.print'),
          label: 'Print',
          icon: Icons.print_outlined,
          busy: _busy == _Busy.print,
          onPressed: _busy == null ? () => _run(_Busy.print) : null,
        ),
        const SizedBox(height: Space.x8),
        AppButton.secondary(
          key: const ValueKey('receipt.save'),
          label: 'Save PDF',
          icon: Icons.picture_as_pdf_outlined,
          busy: _busy == _Busy.save,
          onPressed: _busy == null ? () => _run(_Busy.save) : null,
        ),
        if (saved != null) ...[
          const SizedBox(height: Space.x12),
          Note.info(
            saved,
            title: 'Saved',
            key: const ValueKey('receipt.saved'),
          ),
          const SizedBox(height: Space.x8),
          AppButton.secondary(
            key: const ValueKey('receipt.openFolder'),
            label: 'Open folder',
            icon: Icons.folder_open_outlined,
            compact: true,
            onPressed: () => ref.read(receiptOutputProvider).openFolder(saved),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: Space.x12),
          Note.error(_error!, key: const ValueKey('receipt.error')),
        ],
        const SizedBox(height: Space.x8),
        Text(
          'The first print or save is the original; later ones say COPY.',
          style: t.small,
        ),
      ],
    );
  }
}

/// The receipt as printed, on screen (artboard "Receipt — on screen and
/// PDF"), 400 wide.
class ReceiptView extends StatelessWidget {
  const ReceiptView(this.receipt, {super.key});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final r = receipt;

    Widget row(String label, String value, {bool mono = false, Key? key}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.body.copyWith(color: c.muted)),
              const SizedBox(width: Space.x12),
              Expanded(
                child: Text(
                  value,
                  key: key,
                  textAlign: TextAlign.end,
                  style: mono ? t.monoStrong : t.bodyStrong,
                ),
              ),
            ],
          ),
        );
    Widget rule() => Container(height: 2, color: c.marine);
    Widget soft() => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x10),
      child: Divider(height: 1, color: c.line),
    );

    return Card(
      key: const ValueKey('receipt.view'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.x28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              r.lodgingName,
              textAlign: TextAlign.center,
              style: t.cardTitle.copyWith(color: c.marine),
            ),
            const SizedBox(height: Space.x16),
            rule(),
            const SizedBox(height: Space.x16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RECEIPT',
                        style: t.capsLabel.copyWith(color: c.muted),
                      ),
                      Text(
                        r.receiptNumber,
                        key: const ValueKey('receipt.number'),
                        style: t.moneyLarge,
                      ),
                    ],
                  ),
                ),
                Text(
                  r.issued,
                  textAlign: TextAlign.end,
                  style: t.small.copyWith(color: c.muted),
                ),
              ],
            ),
            if (r.isCopy) ...[
              const SizedBox(height: Space.x8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusBadge(
                  'COPY',
                  key: const ValueKey('receipt.copy'),
                  tone: BadgeTone.warning,
                ),
              ),
            ],
            const SizedBox(height: Space.x12),
            row('Guest', r.guestName),
            row(
              'Room / bed',
              r.roomAndBed,
              key: const ValueKey('receipt.room'),
            ),
            if (r.category case final category?) row('Category', category),
            row('From', r.fromText),
            row('Check out by', r.checkOutByText),
            soft(),
            for (final (label, amount) in r.chargeRows)
              row(label, amount, mono: true),
            const SizedBox(height: Space.x6),
            Row(
              children: [
                Expanded(child: Text('Total paid', style: t.bodyStrong)),
                Text(
                  r.totalText,
                  key: const ValueKey('receipt.total'),
                  style: t.moneyLarge,
                ),
              ],
            ),
            soft(),
            row('Paid by', r.paidBy),
            if (r.mpesaCode case final code?)
              row('M-Pesa code', code, mono: true),
            row('Served by', r.servedBy),
            const SizedBox(height: Space.x20),
            rule(),
            const SizedBox(height: Space.x12),
            Text(
              r.footer.first,
              textAlign: TextAlign.center,
              style: t.bodyStrong,
            ),
            for (final line in r.footer.skip(1))
              Text(
                line,
                key: const ValueKey('receipt.footer'),
                textAlign: TextAlign.center,
                style: t.small.copyWith(color: c.inkSoft),
              ),
          ],
        ),
      ),
    );
  }
}
