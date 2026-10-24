import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/money_input.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/money/kes.dart';
import '../../price_requests/domain/price_request.dart';
import '../../price_requests/presentation/price_request_card.dart';
import '../../setup/domain/bed_category.dart';
import '../../setup/domain/prices_settings.dart';
import '../data/owner_cloud.dart';
import '../data/owner_prices_repository.dart';
import '../domain/owner_today.dart';
import 'owner_providers.dart';

/// The owner's Prices on the phone (Figma "06 Prices"): requests waiting,
/// each with Approve and Reject, then every category's price per night; a
/// category opens "Edit price" (Figma "06b"). Cloud first: offline it is
/// refused. Adding and closing categories stay on the desk.
class OwnerPricesScreen extends ConsumerStatefulWidget {
  const OwnerPricesScreen({super.key});

  @override
  ConsumerState<OwnerPricesScreen> createState() => _OwnerPricesState();
}

class _OwnerPricesState extends ConsumerState<OwnerPricesScreen> {
  String? _busyId;
  String? _problem;
  String? _done;

  Future<void> _refresh() =>
      ref.read(ownerTodayDataProvider.notifier).refresh();

  /// Runs [action] as the owner; the answer shows above the list.
  Future<void> _run(
    String busyId,
    Future<void> Function() action, {
    required String done,
    required String offline,
  }) async {
    setState(() {
      _busyId = busyId;
      _problem = null;
      _done = null;
    });
    try {
      await action();
      if (mounted) setState(() => _done = done);
    } on PriceRequestRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on StalePriceRequest catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'Only the owner decides prices.');
    } on OwnerCloudOffline {
      if (mounted) setState(() => _problem = offline);
    } on OwnerCloudRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on OwnerSignInRefused {
      ref.read(ownerSessionProvider.notifier).ended();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
    await _refresh();
  }

  Future<void> _decide(OwnerPriceRequest r, {required bool approve}) async {
    final signedIn = ref.read(ownerSessionProvider).value;
    if (signedIn == null) return;
    String? note;
    if (!approve) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => RejectPriceDialog(
          categoryName: r.category.name,
          oldPrice: r.request.oldPrice,
          newPrice: r.request.newPrice,
          requestedByFirstName: r.requestedByName.split(' ').first,
        ),
      );
      if (note == null || !mounted) return;
    }
    await _run(
      r.id,
      () => ref
          .read(ownerPricesRepositoryProvider)
          .decide(ownerAccount(signedIn), r, approve: approve, note: note),
      done: approve
          ? '${r.category.name} is now ${formatKes(r.request.newPrice)} for '
                'new check-ins.'
          : 'Request rejected. ${r.requestedByName.split(' ').first} will see '
                'your reason.',
      offline: approve
          ? 'Approving needs an internet connection.'
          : 'Rejecting needs an internet connection.',
    );
  }

  Future<void> _edit(OwnerCategory c) async {
    final saved = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditPriceSheet(category: c),
    );
    if (saved != null && mounted) {
      setState(() {
        _problem = null;
        _done =
            '${c.category.name} is now ${formatKes(saved)} for new '
            'check-ins.';
      });
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final now = ref.watch(ownerClockProvider).now();
    final data = ref.watch(ownerTodayDataProvider);
    final today = data.value?.today;
    if (today == null) {
      return data.hasError
          ? Padding(
              padding: const EdgeInsets.all(Space.x16),
              child: Note.error(
                data.error is OwnerCloudOffline
                    ? 'No internet connection. Prices show once the phone is '
                          'online.'
                    : '${data.error}',
                title: 'Prices could not be loaded.',
              ),
            )
          : const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('owner.prices'),
        padding: const EdgeInsets.all(Space.x16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Semantics(header: true, child: Text('Prices', style: t.pageTitle)),
          const SizedBox(height: Space.x12),
          if (_done != null) ...[
            Note.info(_done!, key: const ValueKey('priceRequest.done')),
            const SizedBox(height: Space.x12),
          ],
          if (_problem != null) ...[
            Note.error(_problem!, key: const ValueKey('priceRequest.problem')),
            const SizedBox(height: Space.x12),
          ],
          for (final r in today.priceRequests) ...[
            PriceRequestCard(
              request: r.request,
              categoryName: r.category.name,
              requestedByFirstName: r.requestedByName.split(' ').first,
              requestedByRole: r.requestedByRole,
              staleMessage: r.staleMessage,
              now: now,
              busy: _busyId == r.id,
              locked: _busyId != null,
              onApprove: () => _decide(r, approve: true),
              onReject: () => _decide(r, approve: false),
            ),
            const SizedBox(height: Space.x16),
          ],
          Text(
            'PRICE PER NIGHT',
            style: t.cardHeading.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.x12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, category) in today.categories.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.lineSoft),
                  _CategoryRow(
                    category,
                    onTap: category.category.isActive && _busyId == null
                        ? () => _edit(category)
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.x12),
          Text(
            'A new price applies to check-ins after the desk receives it, '
            'usually within a minute. Guests already staying keep the price '
            'they checked in at.',
            style: t.small.copyWith(color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow(this.category, {required this.onTap});

  final OwnerCategory category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final cat = category.category;
    return InkWell(
      key: ValueKey('owner.price.${cat.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.target + 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x16,
            vertical: Space.x12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cat.name, style: t.bodyStrong),
                    Text(
                      cat.isActive
                          ? category.bedsLine
                          : 'Closed · open it again on the desk',
                      style: t.small.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.x12),
              Text(
                formatKes(cat.pricePerNight),
                key: ValueKey('owner.price.${cat.id}.value'),
                style: t.monoStrong.copyWith(
                  color: cat.isActive ? c.ink : c.muted,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: Space.x8),
                Icon(Icons.chevron_right_rounded, color: c.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Deluxe · price per night" (Figma "06b Edit price"): the new price, the
/// change it makes, and Save; a change of more than 50% asks "Are you
/// sure?" first. Pops the saved price.
class EditPriceSheet extends ConsumerStatefulWidget {
  const EditPriceSheet({super.key, required this.category});

  final OwnerCategory category;

  @override
  ConsumerState<EditPriceSheet> createState() => _EditPriceSheetState();
}

class _EditPriceSheetState extends ConsumerState<EditPriceSheet> {
  final _price = TextEditingController();
  String? _error;
  var _busy = false;

  BedCategory get _category => widget.category.category;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  PriceChange? _change() {
    final price = parseKes(_price.text);
    if (price == null || price == _category.pricePerNight) return null;
    return PriceChange(
      categoryId: _category.id,
      name: _category.name,
      oldPrice: _category.pricePerNight,
      newPrice: price,
    );
  }

  Future<void> _save() async {
    final signedIn = ref.read(ownerSessionProvider).value;
    if (signedIn == null) return;
    final price = parseKes(_price.text);
    final problem =
        priceError(price) ??
        (price == _category.pricePerNight ? 'That’s already the price.' : null);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final change = _change()!;
    if (change.isBig) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('editPrice.sure'),
          title: Text(
            'Are you sure?',
            style: LodgingType.of(context).sectionTitle,
          ),
          content: Text(bigPriceChangeQuestion(change)),
          actions: [
            AppButton.secondary(
              key: const ValueKey('editPrice.sure.cancel'),
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppButton.primary(
              key: const ValueKey('editPrice.sure.save'),
              label: 'Save new price',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ownerPricesRepositoryProvider)
          .changePrice(ownerAccount(signedIn), _category, newPrice: price);
      if (mounted) Navigator.of(context).pop(price);
    } on PriceEditRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on OwnerCloudOffline {
      if (mounted) {
        setState(
          () => _error = 'Changing prices needs an internet connection.',
        );
      }
    } on OwnerCloudRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on OwnerSignInRefused {
      ref.read(ownerSessionProvider.notifier).ended();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final change = _change();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.x16),
          child: Column(
            key: const ValueKey('editPrice.sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_category.name} · price per night',
                style: t.sectionTitle,
              ),
              const SizedBox(height: Space.x8),
              Text(
                'Now ${formatKes(_category.pricePerNight)} · '
                '${widget.category.bedsLine}',
                style: t.small.copyWith(color: c.muted),
              ),
              const SizedBox(height: Space.x12),
              MoneyInput(
                label: 'New price',
                controller: _price,
                fieldKey: const ValueKey('editPrice.price'),
                errorText: _error,
                large: true,
                autofocus: true,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _save(),
              ),
              if (change != null) ...[
                const SizedBox(height: Space.x8),
                Text(
                  '${change.label} '
                  '(${formatPriceChange(change.newPrice - change.oldPrice)} a '
                  'night). Applies to new check-ins only.',
                  key: const ValueKey('editPrice.change'),
                  style: t.small.copyWith(color: c.inkSoft),
                ),
              ],
              const SizedBox(height: Space.x16),
              AppButton.primary(
                key: const ValueKey('editPrice.save'),
                label: 'Save new price',
                large: true,
                busy: _busy,
                onPressed: _save,
              ),
              const SizedBox(height: Space.x12),
              AppButton.secondary(
                key: const ValueKey('editPrice.cancel'),
                label: 'Cancel',
                large: true,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
