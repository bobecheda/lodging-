import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/phone.dart';
import '../../../core/money/kes.dart';
import '../data/receipts_repository.dart';
import 'receipt_view.dart';
import 'receipts_providers.dart';

/// FD-6 "Receipts": find a receipt by its number or the guest's phone
/// (never by name, as for guests), view it and print or save it again.
/// After the first print or save, it says COPY.
class ReceiptsScreen extends ConsumerStatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  ConsumerState<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends ConsumerState<ReceiptsScreen> {
  final _search = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _listWidth = 340.0;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final list = ref.watch(receiptListProvider(_search.text));
    final selected = _selected;

    final Widget items = switch (list) {
      AsyncError(:final error) => Note.error(
        '$error',
        title: 'Receipts could not be loaded.',
      ),
      AsyncData(value: final receipts) when receipts.isEmpty => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x8),
        child: Text(
          _search.text.trim().isEmpty
              ? 'No receipts yet. Each check-in issues one.'
              : 'No receipt matches. Search by receipt number or phone.',
          key: const ValueKey('receipts.none'),
          style: t.small,
        ),
      ),
      AsyncData(value: final receipts) => ListView.builder(
        key: const ValueKey('receipts.list'),
        itemCount: receipts.length,
        itemBuilder: (context, i) => _ReceiptTile(
          receipts[i],
          selected: receipts[i].paymentId == selected,
          onTap: () => setState(() => _selected = receipts[i].paymentId),
        ),
      ),
      _ => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Receipts', style: t.pageTitle)),
        const SizedBox(height: Space.x16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _listWidth,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LabeledField(
                          label: 'Find by receipt number or phone',
                          controller: _search,
                          fieldKey: const ValueKey('receipts.search'),
                          hintText: 'R-000041 or 0722 418 905',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Space.x12),
                        Expanded(child: items),
                        const SizedBox(height: Space.x8),
                        Text(
                          'Newest first. Showing up to '
                          '${ReceiptsRepository.listLimit}.',
                          style: t.small.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.x24),
              Expanded(
                child: selected == null
                    ? const Align(
                        alignment: Alignment.topLeft,
                        child: Note.info(
                          'Choose a receipt to view it and print or save it '
                          'again.',
                        ),
                      )
                    : SingleChildScrollView(
                        child: ReceiptPanel(
                          key: ValueKey('receipts.panel.$selected'),
                          paymentId: selected,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Number, time, guest with the phone masked, room and total.
class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile(
    this.receipt, {
    required this.selected,
    required this.onTap,
  });

  final ReceiptSummary receipt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final r = receipt;
    return Material(
      color: selected ? c.marineTint : c.white,
      borderRadius: BorderRadius.circular(Radii.control),
      child: InkWell(
        key: ValueKey('receipts.item.${r.receiptNumber}'),
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x12,
            vertical: Space.x10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(r.receiptNumber, style: t.monoStrong)),
                  Text(formatKes(r.total), style: t.monoStrong),
                ],
              ),
              Text(
                '${r.guestName} · ${maskPhone(r.guestPhone)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.small.copyWith(color: c.inkSoft),
              ),
              Text(
                '${r.roomAndBed} · ${formatDayDateTime(r.receivedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.small.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
